"""Probe hython environment for modules/nodes the sprite generator depends on."""
import importlib
import sys

import hou

out = [f"python {sys.version}", f"houdini {hou.applicationVersionString()} license {hou.licenseCategory()}"]
for mod in ("numpy", "PIL", "OpenImageIO", "imageio", "pxr.Usd"):
    try:
        m = importlib.import_module(mod)
        out.append(f"module {mod}: OK {getattr(m, '__version__', '')}")
    except Exception as e:  # noqa: BLE001
        out.append(f"module {mod}: MISSING ({e})")

for cat, names in ((hou.lopNodeTypeCategory(), ["sopimport", "camera", "distantlight::2.0", "distantlight",
                                                 "karmarenderproperties", "karmarendersettings", "usdrender_rop",
                                                 "materiallibrary", "sopcreate", "domelight::3.0"]),
                   (hou.ropNodeTypeCategory(), ["usdrender", "karma"]),
                   (hou.copNodeTypeCategory(), ["file", "blur", "layer"])):
    types = cat.nodeTypes()
    for n in names:
        out.append(f"{cat.name()}/{n}: {'OK' if n in types else 'MISSING'}")
    if cat == hou.lopNodeTypeCategory():
        out.append("lop karma*/light*/camera* types: " + ", ".join(sorted(t for t in types if t.startswith(("karma", "distantlight", "camera")))))
    if cat == hou.copNodeTypeCategory():
        out.append(f"cop type count: {len(types)} sample: " + ", ".join(sorted(types)[:60]))

print("\n".join(out))

