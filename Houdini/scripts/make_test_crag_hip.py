"""Builds Houdini/hip/Test_Crag.hiplc: a hip-source test asset for sprite_gen.py (hython).

Uses the built-in testgeometry_crag (packed pieces, VOP materials, $FF-driven animation) so the
"type": "hip" source path is exercised with real-world features. Test-only: the Crag clip is not a
looping cycle, so root motion is removed per frame (bbox centre on XZ) to keep it in place.
"""
import pathlib

import hou

HIP = pathlib.Path(__file__).resolve().parents[1] / "hip" / "Test_Crag.hiplc"

hou.hipFile.clear(suppress_save_prompt=True)
obj = hou.node("/obj").createNode("geo", "crag_asset")
crag = obj.createNode("testgeometry_crag", "crag")
inplace = obj.createNode("attribwrangle", "in_place")
inplace.setInput(0, crag)
inplace.parm("snippet").set("vector c = getbbox_center(0);\n@P.x -= c.x;\n@P.z -= c.z;\n")
scale = obj.createNode("xform", "to_cm")
scale.setInput(0, inplace)
scale.parm("scale").set(45.0)  # Crag is ~1.9 units tall -> ~85 cm
out = obj.createNode("null", "OUT")
out.setInput(0, scale)
out.setDisplayFlag(True)
out.setRenderFlag(True)
obj.layoutChildren()

# A stage node the generator must not collide with or render.
hou.node("/stage").createNode("sopimport", "asset")

HIP.parent.mkdir(parents=True, exist_ok=True)
hou.hipFile.save(str(HIP))
print(f"saved {HIP}")
