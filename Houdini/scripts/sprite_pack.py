"""Post-process rendered sprite frames and pack them into atlas sheets + JSON metadata.

Pure numpy / OpenImageIO / PIL, so it runs inside hython or any Python with those modules.
Input frames are Karma EXRs: scene-linear Rec.709, premultiplied alpha.
"""
import json
import math

import numpy as np
import OpenImageIO as oiio
from PIL import Image

SCHEMA = "towerclash.sprite_sheet/1"


def load_exr(path):
    buf = oiio.ImageBuf(str(path))
    if buf.has_error:
        raise RuntimeError(f"cannot read {path}: {buf.geterror()}")
    spec = buf.spec()
    px = np.asarray(buf.get_pixels(oiio.FLOAT), dtype=np.float32).reshape(spec.height, spec.width, spec.nchannels)
    names = list(spec.channelnames)
    if "A" not in names:
        raise RuntimeError(f"{path} has no alpha channel (channels: {names})")
    return np.dstack([px[..., names.index(c)] for c in ("R", "G", "B", "A")])


def linear_to_srgb(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)


def _edge_bleed(rgb, filled):
    """Flood straight-alpha color outward into empty pixels (8-neighbour average) until the cell is full."""
    rgb = rgb.copy()
    filled = filled.copy()
    h, w = filled.shape
    offsets = [(dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx]
    for _ in range(h + w):
        if filled.all():
            break
        pr = np.pad(rgb * filled[..., None], ((1, 1), (1, 1), (0, 0)))
        pf = np.pad(filled.astype(np.float32), 1)
        acc = np.zeros_like(rgb)
        cnt = np.zeros((h, w), np.float32)
        for dy, dx in offsets:
            acc += pr[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
            cnt += pf[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
        grow = (~filled) & (cnt > 0)
        if not grow.any():
            break
        rgb[grow] = acc[grow] / cnt[grow][:, None]
        filled |= grow
    return rgb


def process_frame(rgba_lin_premult, alpha_mode="straight", edge_bleed=True):
    """Return (uint8 HxWx4 sRGB image, alpha bbox or None, touches_border)."""
    a = np.clip(rgba_lin_premult[..., 3], 0.0, 1.0)
    safe = np.where(a > 1e-6, a, 1.0)
    straight = np.where(a[..., None] > 1e-6, rgba_lin_premult[..., :3] / safe[..., None], 0.0)
    srgb = linear_to_srgb(straight)
    a8 = np.round(a * 255.0).astype(np.uint8)
    visible = a8 > 0
    if alpha_mode == "premultiplied":
        srgb = srgb * (a8[..., None] / 255.0)
    elif edge_bleed and visible.any():
        srgb = _edge_bleed(srgb, visible)
    rgb8 = np.round(np.clip(srgb, 0.0, 1.0) * 255.0).astype(np.uint8)
    img = np.dstack([rgb8, a8])

    bbox = None
    if visible.any():
        ys, xs = np.nonzero(visible)
        bbox = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    touches = bool(visible[0, :].any() or visible[-1, :].any() or visible[:, 0].any() or visible[:, -1].any())
    return img, bbox, touches


def _pow2(n):
    return 1 << max(0, math.ceil(math.log2(n)))


def _sheet_size(cols, rows, cw, ch, pow2):
    w, h = cols * cw, rows * ch
    return (_pow2(w), _pow2(h)) if pow2 else (w, h)


def pack(asset, frames, render_dirs, dir_meta, anims, cell, pivot, canonical, out_dir, extra_meta):
    """Pack processed frames into sheets.

    frames: {(anim_name, dir_name): [uint8 HxWx4, ...]}
    render_dirs: direction names that were rendered (rows), in order.
    dir_meta: list of {"name","yaw_deg","source","flip_x"} for every logical direction.
    Returns the metadata dict (also written to <asset>_Sheet.json).
    """
    cw, ch = cell
    spr = canonical["sprite"]
    max_px, pow2 = spr["max_sheet_px"], spr["power_of_two"]

    # Try one combined sheet; fall back to one sheet per animation.
    groups = [anims]
    total_rows = len(anims) * len(render_dirs)
    cols = max(a["frames"] for a in anims)
    if max(_sheet_size(cols, total_rows, cw, ch, pow2)) > max_px:
        groups = [[a] for a in anims]

    sheets, anim_meta = [], []
    for gi, group in enumerate(groups):
        g_cols = max(a["frames"] for a in group)
        g_rows = len(group) * len(render_dirs)
        sw, sh = _sheet_size(g_cols, g_rows, cw, ch, pow2)
        if max(sw, sh) > max_px:
            raise RuntimeError(f"animation '{group[0]['name']}' needs a {sw}x{sh} sheet > max_sheet_px {max_px}; "
                               "reduce cell size, frames or directions")
        sheet = np.zeros((sh, sw, 4), np.uint8)
        row = 0
        for anim in group:
            rows = {}
            for d in render_dirs:
                for f, img in enumerate(frames[(anim["name"], d)]):
                    sheet[row * ch:(row + 1) * ch, f * cw:(f + 1) * cw] = img
                rows[d] = row
                row += 1
            anim_meta.append({"name": anim["name"], "fps": anim["fps"], "loop": anim["loop"],
                              "frames": anim["frames"], "sheet": gi, "rows": rows})
        suffix = "" if len(groups) == 1 else f"_{group[0]['name']}"
        fname = f"{asset}{suffix}_Sheet.png"
        Image.fromarray(sheet, "RGBA").save(out_dir / fname, optimize=True)
        sheets.append({"file": fname, "width": sw, "height": sh, "cols": g_cols, "rows": g_rows})

    meta = {
        "schema": SCHEMA,
        "asset": asset,
        "cell": {"w": cw, "h": ch},
        "pivot_px": {"x": pivot[0], "y": pivot[1], "origin": "cell top-left, y down"},
        "cm_per_pixel": spr["cm_per_pixel"],
        "alpha": spr["alpha"],
        "colorspace": "sRGB",
        "camera": canonical["camera"],
        "key_light": {k: canonical["key_light"][k] for k in ("azimuth_deg", "elevation_deg", "color")},
        "layout": "row = (animation, direction), column = frame index",
        "flip_x": "directions with flip_x use the source direction's row mirrored horizontally; "
                  "mirrored pivot x = cell.w - pivot_px.x",
        "sheets": sheets,
        "directions": dir_meta,
        "animations": anim_meta,
    }
    meta.update(extra_meta)
    with open(out_dir / f"{asset}_Sheet.json", "w", encoding="utf-8", newline="\n") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    return meta
