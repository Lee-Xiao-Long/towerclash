"""TowerClash directional sprite generator (hython).

Builds an asset (procedural builder or existing hip), sets up the canonical ortho camera and key
light in Solaris, renders every (animation x direction x frame) with Karma, then post-processes
and packs the frames into <Asset>_Sheet.png + <Asset>_Sheet.json.

Usage (hython is not on PATH):
  & "C:/Program Files/Side Effects Software/Houdini 22.0.368/bin/hython.exe" \
      Houdini/scripts/sprite_gen.py --asset StandIn_Blocky [--dirs S,E] [--anims Walk] [--skip-render]

Verbose output (including husk) goes to Houdini/logs/sprite_<Asset>.log; only a short summary
is printed to the terminal.
"""
import argparse
import datetime
import json
import math
import os
import pathlib
import sys
import time

HOUDINI_DIR = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HOUDINI_DIR / "scripts"))

import hou  # noqa: E402

import sprite_builders  # noqa: E402
import sprite_pack  # noqa: E402

CAM_PRIM = "/cameras/spritecam"
SETTINGS_PRIM = "/Render/spritesettings"


class Log:
    """Redirects fd 1/2 (python + child processes such as husk) to a log file; keeps a console handle."""

    def __init__(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.console = os.fdopen(os.dup(1), "w", encoding="utf-8", buffering=1)
        self.file = open(path, "w", encoding="utf-8", buffering=1, newline="\n")
        sys.stdout.flush()
        sys.stderr.flush()
        os.dup2(self.file.fileno(), 1)
        os.dup2(self.file.fileno(), 2)
        self.path = path

    def log(self, msg):
        self.file.write(f"[{time.strftime('%H:%M:%S')}] {msg}\n")

    def say(self, msg):
        self.log(msg)
        self.console.write(msg + "\n")


def _vec_rot_xyz(rx, ry, v):
    """Apply Rx then Ry (Houdini rOrd 'xyz', degrees) to vector v."""
    a, b = math.radians(rx), math.radians(ry)
    x, y, z = v
    y, z = y * math.cos(a) - z * math.sin(a), y * math.sin(a) + z * math.cos(a)
    x, z = x * math.cos(b) + z * math.sin(b), -x * math.sin(b) + z * math.cos(b)
    return x, y, z


def camera_transform(canon, cell, pivot):
    """Ortho camera placed so the world origin (asset foot pivot) lands on pivot_px."""
    tilt = canon["camera"]["tilt_from_vertical_deg"]
    rx, ry = -(90.0 - tilt), 0.0
    look = _vec_rot_xyz(rx, ry, (0, 0, -1))
    up = _vec_rot_xyz(rx, ry, (0, 1, 0))
    right = _vec_rot_xyz(rx, ry, (1, 0, 0))
    cmpp = canon["sprite"]["cm_per_pixel"]
    w, h = cell
    x_off = (pivot[0] - w / 2.0) * cmpp
    y_off = (h / 2.0 - pivot[1]) * cmpp
    dist = canon["camera"]["distance_cm"]
    pos = [-x_off * right[i] - y_off * up[i] - dist * look[i] for i in range(3)]
    return pos, (rx, ry, 0.0)


def light_rotation(az, el):
    """Distant light shines down its -Z; rotate (rOrd xyz) so +Z points at the compass azimuth/elevation it comes from."""
    return (-el, 180.0 - az, 0.0)


def resolve_directions(canon, asset_cfg):
    names = canon["sprite"]["direction_names"]
    step = 360.0 / len(names)
    yaw = {n: i * step for i, n in enumerate(names)}
    wanted = asset_cfg.get("directions", names)
    mirror = canon["sprite"]["mirror_west"] and "directions" not in asset_cfg
    dir_meta, render = [], []
    for n in wanted:
        y = yaw[n]
        if mirror and y > 180.0:
            src = names[int(round((360.0 - y) / step)) % len(names)]
            dir_meta.append({"name": n, "yaw_deg": y, "source": src, "flip_x": True})
        else:
            dir_meta.append({"name": n, "yaw_deg": y, "source": n, "flip_x": False})
            render.append(n)
    return dir_meta, render, yaw


def set_parm(node, name, value):
    p = node.parm(name)
    if p is None:
        raise RuntimeError(f"{node.path()} has no parm '{name}'")
    p.set(value)


def build_scene(canon, asset_cfg, log):
    src = asset_cfg["source"]
    if src["type"] == "procedural":
        hou.hipFile.clear(suppress_save_prompt=True)
        sop = sprite_builders.BUILDERS[src["builder"]](asset_cfg["name"])
        anim_node = sop.parent()
    elif src["type"] == "hip":
        hou.hipFile.load(str(HOUDINI_DIR.parent / src["hip"]), suppress_save_prompt=True, ignore_load_warnings=True)
        sop = hou.node(src["sop"])
        if sop is None:
            raise RuntimeError(f"SOP {src['sop']} not found in {src['hip']}")
        anim_node = hou.node(src.get("parm_node", sop.parent().path()))
    else:
        raise RuntimeError(f"unknown source type {src['type']}")
    log.log(f"asset SOP: {sop.path()}  anim parms on: {anim_node.path()}")

    # Wrapper object: pulls the asset in and applies the per-direction yaw.
    wrap = hou.node("/obj").createNode("geo", "__sprite_src")
    for c in wrap.children():
        c.destroy()
    om = wrap.createNode("object_merge", "asset")
    om.parm("objpath1").set(sop.path())
    om.parm("xformtype").set(0)
    yaw = wrap.createNode("xform", "yaw")
    yaw.setInput(0, om)
    out = wrap.createNode("null", "OUT")
    out.setInput(0, yaw)
    out.setDisplayFlag(True)
    out.setRenderFlag(True)
    wrap.setDisplayFlag(False)

    cell, pivot = asset_cfg["cell_px"], asset_cfg["pivot_px"]
    cmpp = canon["sprite"]["cm_per_pixel"]
    stage = hou.node("/stage")
    si = stage.createNode("sopimport", "asset")
    si.parm("soppath").set(out.path())
    si.parm("primpath").set("/asset")
    si.parm("pathprefix").set("/asset")

    cam = stage.createNode("camera", "spritecam")
    cam.setInput(0, si)
    cam.parm("primpath").set(CAM_PRIM)
    cam.parm("projection").set("orthographic")
    pos, rot = camera_transform(canon, cell, pivot)
    cam.parm("rOrd").set("xyz")
    cam.parmTuple("t").set(pos)
    cam.parmTuple("r").set(rot)
    # USD ortho aperture is in tenths of a scene unit. The LOP parm is scaled before it is written
    # to USD (x0.01 in H22), so measure that factor instead of assuming it.
    want_h, want_v = cell[0] * cmpp * 10.0, cell[1] * cmpp * 10.0
    cam.parm("horizontalAperture").set(1.0)
    factor = cam.parm("horizontalApertureConverted").eval()
    cam.parmTuple("aspectratio").set((cell[0], cell[1]))
    cam.parm("horizontalAperture").set(want_h / factor)
    cam.parm("verticalAperture").set(want_v / factor)
    got_h = cam.parm("horizontalApertureConverted").eval()
    got_v = cam.parm("verticalApertureConverted").eval()
    log.log(f"camera pos={[round(v, 3) for v in pos]} rot={rot} usd aperture want={want_h}x{want_v} got={got_h}x{got_v}")
    if abs(got_h - want_h) > 1e-3 or abs(got_v - want_v) > 1e-3:
        raise RuntimeError(f"camera aperture mismatch: want {want_h}x{want_v}, got {got_h}x{got_v}")

    kl = canon["key_light"]
    key = stage.createNode("distantlight::2.0", "key")
    key.setInput(0, cam)
    key.parm("primpath").set("/lights/key")
    key.parm("rOrd").set("xyz")
    key.parmTuple("r").set(light_rotation(kl["azimuth_deg"], kl["elevation_deg"]))
    set_parm(key, "xn__inputsintensity_i0a", kl["intensity"])
    set_parm(key, "xn__inputsexposure_vya", kl["exposure"])
    set_parm(key, "xn__inputsangle_zta", kl["angle_deg"])
    for i, c in enumerate("rgb"):
        set_parm(key, f"xn__inputscolor_zta{c}", kl["color"][i])

    fl = canon["fill_light"]
    fill = stage.createNode("domelight::3.0", "fill")
    fill.setInput(0, key)
    fill.parm("primpath").set("/lights/fill")
    set_parm(fill, "xn__inputsintensity_i0a", fl["intensity"])
    for i, c in enumerate("rgb"):
        set_parm(fill, f"xn__inputscolor_zta{c}", fl["color"][i])

    rc = canon["render"]
    krs = stage.createNode("karmarendersettings", "settings")
    krs.setInput(0, fill)
    krs.parm("primpath").set(SETTINGS_PRIM)
    krs.parm("camera").set(CAM_PRIM)
    krs.parm("engine").set(rc["engine"])
    krs.parm("res_mode").set("manual")
    for axis, value in (("resolutionx", cell[0]), ("resolutiony", cell[1])):
        krs.parm(axis).lock(False)
        krs.parm(axis).deleteAllKeyframes()
        krs.parm(axis).set(value)
    krs.parm("samplesperpixel").set(rc["samples"])
    krs.parm("pixelfilter").set("gauss")
    krs.parm("pixelfiltersize").set(rc["pixel_filter_width"])

    rop = stage.createNode("usdrender_rop", "render")
    rop.setInput(0, krs)
    rop.parm("renderer").set("BRAY_HdKarma")
    rop.parm("rendersettings").set(SETTINGS_PRIM)
    rop.parm("trange").set("normal")
    rop.parm("allframesatonce").set(1)
    stage.layoutChildren()
    return {"anim_node": anim_node, "yaw": yaw, "krs": krs, "rop": rop, "stage": stage}


def frame_path(frames_dir, anim, d, frame):
    return frames_dir / f"{anim}_{d}.{frame:04d}.exr"


def render_all(scene, anims, render_dirs, yaw_of, frames_dir, log):
    frames_dir.mkdir(parents=True, exist_ok=True)
    for anim in anims:
        for name, value in anim.get("set_parms", {}).items():
            set_parm(scene["anim_node"], name, value)
        start = int(anim.get("frame_start", anim.get("set_parms", {}).get("start", 1)))
        end = start + anim["frames"] - 1
        for d in render_dirs:
            scene["yaw"].parm("ry").set(yaw_of[d])
            pic = (frames_dir / f"{anim['name']}_{d}.$F4.exr").as_posix()
            scene["krs"].parm("picture").set(pic)
            t0 = time.time()
            log.log(f"render {anim['name']} {d} frames {start}-{end} -> {pic}")
            scene["rop"].render(frame_range=(start, end, 1), verbose=False, output_progress=False)
            missing = [f for f in range(start, end + 1) if not frame_path(frames_dir, anim["name"], d, f).exists()]
            if missing:
                raise RuntimeError(f"render {anim['name']} {d}: missing frames {missing} (see log)")
            log.log(f"  done in {time.time() - t0:.1f}s")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--asset", required=True, help="asset config name in Houdini/config/assets")
    ap.add_argument("--dirs", help="comma list to limit rendered directions (debug)")
    ap.add_argument("--anims", help="comma list to limit animations (debug)")
    ap.add_argument("--skip-render", action="store_true", help="re-pack existing EXRs only")
    ap.add_argument("--no-save-hip", action="store_true")
    ap.add_argument("--tilt", type=float, help="override camera tilt (experiments); output gets a _TiltNN suffix")
    args = ap.parse_args()

    log = Log(HOUDINI_DIR / "logs" / f"sprite_{args.asset}{'' if args.tilt is None else f'_Tilt{args.tilt:g}'}.log")
    t_start = time.time()
    try:
        canon = json.loads((HOUDINI_DIR / "config" / "Canonical.json").read_text(encoding="utf-8"))
        asset_cfg = json.loads((HOUDINI_DIR / "config" / "assets" / f"{args.asset}.json").read_text(encoding="utf-8"))
        name = asset_cfg["name"]
        if args.tilt is not None:
            canon["camera"]["tilt_from_vertical_deg"] = args.tilt
            name = f"{name}_Tilt{args.tilt:g}"
        log.log(f"houdini {hou.applicationVersionString()} asset {name}")

        dir_meta, render_dirs, yaw_of = resolve_directions(canon, asset_cfg)
        anims = asset_cfg["animations"]
        if args.dirs:
            keep = args.dirs.split(",")
            render_dirs = [d for d in render_dirs if d in keep]
            dir_meta = [m for m in dir_meta if m["name"] in keep or m["source"] in keep]
        if args.anims:
            anims = [a for a in anims if a["name"] in args.anims.split(",")]

        out_dir = HOUDINI_DIR / "render" / name
        frames_dir = out_dir / "frames"
        if not args.skip_render:
            scene = build_scene(canon, asset_cfg, log)
            if not args.no_save_hip:
                hip = HOUDINI_DIR / "hip" / f"Sprite_{name}.hiplc"
                hip.parent.mkdir(parents=True, exist_ok=True)
                hou.hipFile.save(str(hip))
                log.log(f"saved {hip}")
            render_all(scene, anims, render_dirs, yaw_of, frames_dir, log)
        t_render = time.time() - t_start

        spr = canon["sprite"]
        frames, union, clipped = {}, None, []
        for anim in anims:
            start = int(anim.get("frame_start", anim.get("set_parms", {}).get("start", 1)))
            for d in render_dirs:
                imgs = []
                for f in range(start, start + anim["frames"]):
                    img, bbox, touches = sprite_pack.process_frame(
                        sprite_pack.load_exr(frame_path(frames_dir, anim["name"], d, f)), spr["alpha"], spr["edge_bleed"])
                    if img.shape[1] != asset_cfg["cell_px"][0] or img.shape[0] != asset_cfg["cell_px"][1]:
                        raise RuntimeError(f"frame size {img.shape[1]}x{img.shape[0]} != cell {asset_cfg['cell_px']}")
                    if touches:
                        clipped.append(f"{anim['name']}_{d}.{f}")
                    if bbox:
                        union = bbox if union is None else (min(union[0], bbox[0]), min(union[1], bbox[1]),
                                                            max(union[2], bbox[2]), max(union[3], bbox[3]))
                    imgs.append(img)
                frames[(anim["name"], d)] = imgs

        extra = {
            "generated_utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "generator": "Houdini/scripts/sprite_gen.py",
            "houdini_version": hou.applicationVersionString(),
            "content_rect": None if union is None else {"x": union[0], "y": union[1],
                                                        "w": union[2] - union[0], "h": union[3] - union[1]},
        }
        meta = sprite_pack.pack(name, frames, render_dirs, dir_meta, anims, asset_cfg["cell_px"],
                                asset_cfg["pivot_px"], canon, out_dir, extra)
        log.log(json.dumps(meta, indent=1))

        n_frames = sum(len(v) for v in frames.values())
        sheets = ", ".join(f"{s['file']} {s['width']}x{s['height']}" for s in meta["sheets"])
        log.say(f"[sprite_gen] {name}: {n_frames} frames, dirs={','.join(render_dirs)}, "
                f"render {t_render:.0f}s, total {time.time() - t_start:.0f}s")
        log.say(f"[sprite_gen] sheets: {sheets}; content_rect={extra['content_rect']}")
        if clipped:
            log.say(f"[sprite_gen] WARNING: {len(clipped)} frames touch the cell border (clipped?): {clipped[:5]}")
        log.say(f"[sprite_gen] log: {log.path}")
    except Exception as e:  # noqa: BLE001
        import traceback
        log.log(traceback.format_exc())
        log.say(f"[sprite_gen] FAILED: {str(e).splitlines()[0] if str(e) else type(e).__name__} (see {log.path})")
        sys.exit(1)


if __name__ == "__main__":
    main()
