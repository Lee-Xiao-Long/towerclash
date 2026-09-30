"""Verify sprite camera math against a rendered Calib_Box frame.

Projects the 100 cm calibration cube analytically with the canonical camera and compares the
expected pixel bounds with the rendered alpha (50% threshold). Run after:
  hython Houdini/scripts/sprite_gen.py --asset Calib_Box
Usage: hython Houdini/scripts/check_calibration.py
"""
import json
import math
import pathlib
import sys

HOUDINI_DIR = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HOUDINI_DIR / "scripts"))

import numpy as np  # noqa: E402

import sprite_pack  # noqa: E402

TOLERANCE_PX = 1.0


def main():
    canon = json.loads((HOUDINI_DIR / "config" / "Canonical.json").read_text(encoding="utf-8"))
    asset = json.loads((HOUDINI_DIR / "config" / "assets" / "Calib_Box.json").read_text(encoding="utf-8"))
    cmpp = canon["sprite"]["cm_per_pixel"]
    px0, py0 = asset["pivot_px"]
    a = math.radians(-(90.0 - canon["camera"]["tilt_from_vertical_deg"]))
    up = (0.0, math.cos(a), math.sin(a))
    right = (1.0, 0.0, 0.0)

    xs, ys = [], []
    for x in (-50, 50):
        for y in (0, 100):
            for z in (-50, 50):
                xs.append(px0 + (x * right[0] + y * right[1] + z * right[2]) / cmpp)
                ys.append(py0 - (x * up[0] + y * up[1] + z * up[2]) / cmpp)
    expected = (min(xs), min(ys), max(xs), max(ys))

    rgba = sprite_pack.load_exr(HOUDINI_DIR / "render" / "Calib_Box" / "frames" / "Still_S.0001.exr")
    alpha = rgba[..., 3]
    rows = np.nonzero(alpha.max(axis=1) > 0.5)[0]
    cols = np.nonzero(alpha.max(axis=0) > 0.5)[0]
    measured = (cols.min(), rows.min(), cols.max() + 1, rows.max() + 1)
    err = max(abs(e - m) for e, m in zip(expected, measured))
    print(f"expected px bounds {tuple(round(v, 2) for v in expected)}")
    print(f"measured px bounds {tuple(int(v) for v in measured)}")
    print(f"max error {err:.2f}px -> {'PASS' if err <= TOLERANCE_PX else 'FAIL'}")
    sys.exit(0 if err <= TOLERANCE_PX else 1)


if __name__ == "__main__":
    main()
