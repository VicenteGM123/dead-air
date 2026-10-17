The sword blows of Heracles: the generator behind the block in game/scripts/gfx/rig_heracles.gd between
"# >>> STRIKES BEGIN" and "# <<< STRIKES END". Needs only python3 + numpy (+ matplotlib for the stick-figure strips).

Since 2026-10-17 the blows are the long blade's moveset (docs/ANIMATION.md 4.9, numbers in docs/COMBAT.md 3.2):
a1 a2 a3 a4 (combo A), b1 b2 b3 (combo B), dash, heavy; attack1/attack2/attack3 are aliases of a1/a2/a4 (STRIKE_ALIAS).

  python3 moveset.py [blow ...] [--resolve] [--report] [--trace] [--view]
                                          the single source of the blows: cut planes, keys, body / shield / feet curves, the dense
                                          IK of the sword arm (every 1/120 s). One check line per blow (lowest tip, blade-body
                                          clearance, edge leading, roll rate, tip speed, joint steps); --report and --trace print
                                          the path; --view draws a stick-figure strip (mview.py) into ../../shots/py/. With no blow
                                          named it writes strike_data.gd.txt. keys_cache_moveset.json holds the solved arm
                                          (--resolve solves again: minutes per blow; a blow whose definition changed is re-solved).
  python3 splice_strike.py [rig.gd]       puts strike_block.gd.txt (the runtime: curves -> poses, footwork, run layer, the held
                                          coil's legs, wrist limit, the aliases) and strike_data.gd.txt into the rig (default
                                          ../../game/scripts/gfx/rig_heracles.gd).
  python3 mview.py                        (module) the stick-figure views used by moveset.py --view.

Edit moveset.py (or strike_block.gd.txt for the runtime), run both scripts, then look at the blows in Godot:
  COLS=12 VIEWS="game side" tools/strike_strips.sh <out dir> a1 a2 a3 a4 b1 b2 b3 dash heavy      (from game/)
  and the strings chained: preview_heracles.gd rows "chain:a1,a2,a3,a4@game" (see tools/preview_heracles.gd);
  then the arena bot (docs/COMBAT.md 8).
smodel.py is the python model of the rig's arm (and the long blade), solve.py the least-squares fit of the joint angles.

Legacy: defs.py (the 2026-10-16 rebuild of the four old blows; moveset.py still imports its ankle_on / pin_of / rot_curve)
with a1_*, a2_*, a3_*, h_*, ev.py, jv.py and keys_cache.json. `python3 defs.py` only reports now; `--export-legacy` would
write the old four into strike_data.gd.txt. tools/anim_check.tscn mode=strike still measures attack1-3 by the old event times.

Anything added inside the markers of the rig must be added to strike_block.gd.txt too, or the next splice removes it.
