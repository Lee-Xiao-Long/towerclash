"""Procedural stand-in assets for the sprite generator.

Every builder returns the SOP node whose output is the asset, following the conventions in
Canonical.json: units cm, feet on Y=0, facing +Z at yaw 0. Animation is driven by spare parms
on the returned node's parent object (set per animation via the asset config "set_parms").
"""
import hou

# (name, size xyz, box center relative to its pivot, pivot/attach point, color rgb,
#  rx expression, ty offset expression)
_PHASE = '360*($F-ch("../start"))/ch("../cycle")'
_SWING = f'ch("../walk")*32*sin({_PHASE})'
_BOB = f'ch("../walk")*2.5*abs(sin({_PHASE})) + (1-ch("../walk"))*0.8*sin({_PHASE})'

_BLOCKY_PARTS = [
    ("leg_l", (10, 30, 10), (0, -15, 0), (-7, 30, 0), (0.22, 0.25, 0.38), f"-({_SWING})", ""),
    ("leg_r", (10, 30, 10), (0, -15, 0), (7, 30, 0), (0.22, 0.25, 0.38), _SWING, ""),
    ("torso", (26, 28, 14), (0, 14, 0), (0, 30, 0), (0.75, 0.2, 0.18), "", _BOB),
    ("belt", (27, 4, 15), (0, 2, 0), (0, 30, 0), (0.35, 0.22, 0.12), "", _BOB),
    ("arm_l", (7, 26, 7), (0, -12, 0), (-17, 56, 0), (0.75, 0.2, 0.18), _SWING, _BOB),
    ("arm_r", (7, 26, 7), (0, -12, 0), (17, 56, 0), (0.75, 0.2, 0.18), f"-({_SWING})", _BOB),
    ("head", (20, 20, 20), (0, 10, 0), (0, 59, 0), (0.93, 0.76, 0.6), "", _BOB),
    # Asymmetric front markers so facing reads in every direction.
    ("nose", (5, 5, 6), (0, 0, 3), (0, 69, 10), (0.98, 0.85, 0.1), "", _BOB),
    ("emblem", (10, 10, 2), (0, 0, 1), (-4, 48, 7), (0.98, 0.85, 0.1), "", _BOB),
    ("pack", (18, 20, 8), (0, 10, -4), (0, 36, -7), (0.3, 0.45, 0.2), "", _BOB),
]


def _add_anim_parms(obj):
    group = obj.parmTemplateGroup()
    for name, default in (("walk", 0.0), ("cycle", 8.0), ("start", 1.0)):
        if group.find(name) is None:
            group.append(hou.FloatParmTemplate(name, name.title(), 1, default_value=(default,)))
    obj.setParmTemplateGroup(group)


def blocky_standin(name):
    obj = hou.node("/obj").createNode("geo", name)
    for child in obj.children():
        child.destroy()
    _add_anim_parms(obj)

    merge = obj.createNode("merge", "merge_parts")
    for i, (part, size, center, attach, color, rx_expr, ty_expr) in enumerate(_BLOCKY_PARTS):
        box = obj.createNode("box", part)
        box.parmTuple("size").set(size)
        box.parmTuple("t").set(center)
        xf = obj.createNode("xform", f"{part}_xf")
        xf.setInput(0, box)
        xf.parmTuple("t").set(attach)
        if rx_expr:
            xf.parm("rx").setExpression(rx_expr, hou.exprLanguage.Hscript)
        if ty_expr:
            xf.parm("ty").setExpression(f"{attach[1]} + {ty_expr}", hou.exprLanguage.Hscript)
        col = obj.createNode("color", f"{part}_cd")
        col.setInput(0, xf)
        col.parmTuple("color").set(color)
        merge.setInput(i, col)

    normal = obj.createNode("normal", "normals")
    normal.setInput(0, merge)
    normal.parm("cuspangle").set(30)
    out = obj.createNode("null", "OUT")
    out.setInput(0, normal)
    out.setDisplayFlag(True)
    out.setRenderFlag(True)
    obj.layoutChildren()
    return out


def calibration_box(name):
    obj = hou.node("/obj").createNode("geo", name)
    for child in obj.children():
        child.destroy()
    _add_anim_parms(obj)
    box = obj.createNode("box", "cube")
    box.parmTuple("size").set((100, 100, 100))
    box.parmTuple("t").set((0, 50, 0))
    col = obj.createNode("color", "cd")
    col.setInput(0, box)
    col.parmTuple("color").set((0.8, 0.8, 0.8))
    out = obj.createNode("null", "OUT")
    out.setInput(0, col)
    out.setDisplayFlag(True)
    out.setRenderFlag(True)
    obj.layoutChildren()
    return out


BUILDERS = {
    "blocky_standin": blocky_standin,
    "calibration_box": calibration_box,
}
