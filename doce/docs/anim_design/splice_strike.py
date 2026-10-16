#!/usr/bin/env python3
"""Splice strike_block.gd.txt into game/scripts/gfx/rig_heracles.gd between the STRIKES BEGIN / END markers
(first time: before the 'Emits an action's events' comment)."""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
# usage: python3 splice_strike.py [path to scripts/gfx/rig_heracles.gd]   (default: ../../game/scripts/gfx/rig_heracles.gd, docs/ beside game/)
rig_path = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(os.path.join(HERE, "..", "..", "game", "scripts", "gfx", "rig_heracles.gd"))
block = open(os.path.join(HERE, "strike_block.gd.txt")).read().rstrip("\n") + "\n"
data = open(os.path.join(HERE, "strike_data.gd.txt")).read().rstrip("\n") + "\n\n"
block = block.replace("#@@DATA@@\n", data)
src = open(rig_path).read()
b = src.find("# >>> STRIKES BEGIN")
e = src.find("# <<< STRIKES END")
if b >= 0 and e >= 0:
    e_end = src.find("\n", e) + 1
    out = src[:b] + block + src[e_end:]
else:
    anchor = "## Emits an action's events (a name may carry several times)."
    i = src.find(anchor)
    assert i >= 0, "anchor not found"
    out = src[:i] + block + "\n\n" + src[i:]
open(rig_path, "w").write(out)
print("spliced", len(block), "bytes; rig now", out.count("\n"), "lines")
