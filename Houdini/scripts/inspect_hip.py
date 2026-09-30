"""Dump the node tree of a hip file to a log.

Usage: hython inspect_hip.py <hipfile> <logfile>
"""
import sys

import hou


def main():
    hip, log = sys.argv[1], sys.argv[2]
    hou.hipFile.load(hip, suppress_save_prompt=True, ignore_load_warnings=True)
    lines = [f"hip: {hip}", f"houdini: {hou.applicationVersionString()}",
             f"fps: {hou.fps()} range: {hou.playbar.frameRange()}"]
    counts = {}
    for node in hou.node("/").allSubChildren():
        t = node.type().name()
        counts[t] = counts.get(t, 0) + 1
        depth = node.path().count("/") - 1
        extra = ""
        if isinstance(node, hou.SopNode) and node.isDisplayFlagSet():
            extra = " [display]"
        lines.append(f"{'  ' * depth}{node.path()}  ({node.type().category().name()}/{t}){extra}")
    lines.append("")
    lines.append("type counts:")
    for t, c in sorted(counts.items(), key=lambda x: -x[1]):
        lines.append(f"  {t}: {c}")
    with open(log, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"nodes: {sum(counts.values())}, types: {len(counts)} -> {log}")


if __name__ == "__main__":
    main()

