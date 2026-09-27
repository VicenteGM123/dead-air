// Building shell physics: registers every collider the architecture implies (ground, walls, fence, platforms,
// stairs, ramps, bleacher rails, door blockers, player-only window/gate blockers, tower base). Pure data →
// Collision, no THREE meshes, so level.js and the node tests build the exact same physical station.
//
// Tags: floor, wall, glass, fence, platform, rail, door (id = door id, toggled by level.openDoor),
//       window (id = window id: invisible player-only blocker, ignored by shots and the camera), lattice.

import { WALLS, WALL_T, PLATFORMS, BLOCKERS, DOORS, WINDOWS, ANCHORS } from './layout.js';

const H = WALL_T / 2;
const FENCE_T = 0.2;
const GROUND = [[-80, -1, -90], [130, 0, 70]];
const TOWER_BLOCK_H = 3;

// Axis-aligned box of a wall segment: `half` across the line, optionally extended along it at non-jamb ends.
export function segmentBox(seg, half = H, extend = 0) {
  const [x0, z0, x1, z1, y0, y1, , meta] = seg;
  const alongX = z0 === z1;
  const e0 = meta && meta.jambs[0] ? 0 : extend;
  const e1 = meta && meta.jambs[1] ? 0 : extend;
  if (alongX) {
    const a = Math.min(x0, x1) - e0, b = Math.max(x0, x1) + e1;
    return [[a, y0, z0 - half], [b, y1, z0 + half]];
  }
  const a = Math.min(z0, z1) - e0, b = Math.max(z0, z1) + e1;
  return [[x0 - half, y0, a], [x0 + half, y1, b]];
}

export function addShellColliders(col) {
  col.addBox(GROUND[0], GROUND[1], { tag: 'floor', id: 'ground' });

  for (const seg of WALLS) {
    const kind = seg[6];
    const [min, max] = segmentBox(seg, kind === 'fence' ? FENCE_T / 2 : H, kind === 'fence' ? 0 : H);
    col.addBox(min, max, { tag: kind === 'solid' ? 'wall' : kind });
  }

  for (const p of PLATFORMS) {
    const [x0, z0, x1, z1] = p.rect;
    if (p.ramp > 0) col.addRamp(p.rect, 0, p.top, p.ramp, { tag: 'platform', id: p.id });
    else col.addBox([x0, 0, z0], [x1, p.top, z1], { tag: 'platform', id: p.id });
  }

  for (const b of BLOCKERS) {
    const [x0, z0, x1, z1] = b.rect;
    col.addBox([x0, b.y0, z0], [x1, b.y1, z1], { tag: b.tag, id: b.id });
  }

  for (const d of DOORS) {
    const [x0, z0, x1, z1] = d.rect;
    col.addBox([x0, d.y0, z0], [x1, d.y1, z1], { tag: 'door', id: d.id });
  }

  // Boarded windows and the gate: fill the opening. Fence climbs need nothing (the fence is continuous).
  for (const w of WINDOWS) {
    if (w.type === 'fence') continue;
    const [axis, at] = w.line;
    const t = w.type === 'gate' ? FENCE_T / 2 : H;
    const [a, b] = w.span;
    const min = axis === 'z' ? [a, w.sill, at - t] : [at - t, w.sill, a];
    const max = axis === 'z' ? [b, w.top, at + t] : [at + t, w.top, b];
    col.addBox(min, max, { tag: 'window', id: w.id });
  }

  const [tx0, tz0, tx1, tz1] = ANCHORS.tower_base.rect;
  col.addBox([tx0, 0, tz0], [tx1, TOWER_BLOCK_H, tz1], { tag: 'lattice', id: 'tower_base' });
}
