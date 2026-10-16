The four sword blows of Heracles (attack1, attack2, attack3, heavy): the generator behind the block in
game/scripts/gfx/rig_heracles.gd between "# >>> STRIKES BEGIN" and "# <<< STRIKES END". The method and the numbers are in
docs/ANIMATION.md section 4.8. Needs only python3 + numpy.

  python3 defs.py [report] [--resolve]    the single source of the blows (body curves, key poses refitted for the wrist's
                                          limits, the chain's timing, shield arm, head, feet). Prints the chain of every blow
                                          and writes strike_data.gd.txt. keys_cache.json holds the solved joint angles of the
                                          key poses (--resolve solves them again, a few minutes; the cache is checked against
                                          the body curves, the deltas and the limits, so editing defs.py re-solves what changed).
  python3 splice_strike.py [rig.gd]       puts strike_block.gd.txt (the runtime: curves -> poses, footwork, run layer, wrist
                                          limit) and strike_data.gd.txt into the rig (default ../../game/scripts/gfx/rig_heracles.gd).
  python3 jv.py <blow> [t0 t1 step]       joint angles, rates and the chain's speeds over time, to read the kinetic chain.

Edit defs.py (or strike_block.gd.txt for the runtime), run both scripts, then check with
  godot --headless --path game res://tools/anim_check.tscn -- mode=strike  (also mode=combo, lunge=0.8, carry=5.5)
a1_*, a2_*, a3_*, h_*, ev.py hold the first design of each blow (its body curves are the starting point of the refit of the key
poses: OLD_KEYS in defs.py), smodel.py is the python model of the rig's arm and solve.py the least-squares fit of the joint angles.

Checked at the ship step (2026-10-16): strike_block.gd.txt is the shipped block verbatim (step 3 added the forearm-twist tracker and the
shield strap's slip inside the markers; the template carries them), so `python3 defs.py && python3 splice_strike.py` reproduces
game/scripts/gfx/rig_heracles.gd byte for byte (defs.py also reproduces strike_data.gd.txt and keys_cache.json). Anything you add
inside the markers of the rig must be added to strike_block.gd.txt too, or the next splice removes it.
