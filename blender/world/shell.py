# Building shell physics (port of src/world/shell.js): every collider the architecture implies (ground, walls, fence,
# platforms, stairs, ramps, bleacher rails, door blockers, player-only window/gate blockers, tower base). Pure data;
# the Blender build uses segmentBox() (the wall boxes the architecture faces are cut from); the runtime twin is
# godot/scripts/world/shell.gd (addShellColliders(col) on the game's Collision).
#
# Tags: floor, wall, glass, fence, platform, rail, door (id = door id, toggled by level.openDoor),
#       window (id = window id: invisible player-only blocker, ignored by shots and the camera), lattice.

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from world.layout import WALLS, WALL_T, PLATFORMS, BLOCKERS, DOORS, WINDOWS, ANCHORS  # noqa: E402

H = WALL_T / 2
FENCE_T = 0.2
GROUND = [[-80, -1, -90], [130, 0, 70]]
TOWER_BLOCK_H = 3


def segmentBox(seg, half=H, extend=0):
    """Axis-aligned box of a wall segment: `half` across the line, optionally extended along it at non-jamb ends."""
    x0, z0, x1, z1, y0, y1 = seg[0:6]
    meta = seg[7] if len(seg) > 7 else None
    alongX = z0 == z1
    e0 = 0 if meta and meta['jambs'][0] else extend
    e1 = 0 if meta and meta['jambs'][1] else extend
    if alongX:
        a, b = min(x0, x1) - e0, max(x0, x1) + e1
        return [[a, y0, z0 - half], [b, y1, z0 + half]]
    a, b = min(z0, z1) - e0, max(z0, z1) + e1
    return [[x0 - half, y0, a], [x0 + half, y1, b]]


def addShellColliders(col):
    """col: any object with addBox(min, max, opts) / addRamp(rect, y0, y1, inset, opts) (the Collision API)."""
    col.addBox(GROUND[0], GROUND[1], {'tag': 'floor', 'id': 'ground'})
    for seg in WALLS:
        kind = seg[6]
        mn, mx = segmentBox(seg, FENCE_T / 2 if kind == 'fence' else H, 0 if kind == 'fence' else H)
        col.addBox(mn, mx, {'tag': 'wall' if kind == 'solid' else kind})
    for p in PLATFORMS:
        x0, z0, x1, z1 = p['rect']
        if p['ramp'] > 0:
            col.addRamp(p['rect'], 0, p['top'], p['ramp'], {'tag': 'platform', 'id': p['id']})
        else:
            col.addBox([x0, 0, z0], [x1, p['top'], z1], {'tag': 'platform', 'id': p['id']})
    for b in BLOCKERS:
        x0, z0, x1, z1 = b['rect']
        col.addBox([x0, b['y0'], z0], [x1, b['y1'], z1], {'tag': b['tag'], 'id': b['id']})
    for d in DOORS:
        x0, z0, x1, z1 = d['rect']
        col.addBox([x0, d['y0'], z0], [x1, d['y1'], z1], {'tag': 'door', 'id': d['id']})
    # Boarded windows and the gate: fill the opening. Fence climbs need nothing (the fence is continuous).
    for w in WINDOWS:
        if w['type'] == 'fence':
            continue
        axis, at = w['line']
        t = FENCE_T / 2 if w['type'] == 'gate' else H
        a, b = w['span']
        mn = [a, w['sill'], at - t] if axis == 'z' else [at - t, w['sill'], a]
        mx = [b, w['top'], at + t] if axis == 'z' else [at + t, w['top'], b]
        col.addBox(mn, mx, {'tag': 'window', 'id': w['id']})
    tx0, tz0, tx1, tz1 = ANCHORS['tower_base']['rect']
    col.addBox([tx0, 0, tz0], [tx1, TOWER_BLOCK_H, tz1], {'tag': 'lattice', 'id': 'tower_base'})
