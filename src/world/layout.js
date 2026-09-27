// WZTV Channel 13 as plain data (GDD §5, §13 toys, §18.2–18.6, §18.10, §18.13; ARCHITECTURE §7).
// The GDD tables are authoritative; the ASCII map is illustrative. Everything here is pure data or derived
// from it at module load (WALLS, RAMPS) so the building has a single source of truth: no THREE, no DOM.
//
// Exports
//   FOOTPRINT                         {x0,z0,x1,z1} of the 0.5 m nav grid (GDD §5: x −7…51, z −30…6)
//   AREAS    [{ id, name, rect:[x0,z0,x1,z1], floorY, ceilY|null, floor, ambient, ambientPre, fog, adjacent,
//               doors, sky, accent }]           floor = footstep surface: carpet|tile|wood|gravel|metal
//   WALLS    [[x0,z0,x1,z1, y0,y1, kind, meta]]  thin boxes (WALL_T thick) centred on the segment;
//               kind 'solid'|'glass'|'fence'; meta = { sides:[negArea,posArea], jambs:[bool,bool], opening }
//               sides = area id (or null = outdoors) on the −/+ side of the segment's normal axis;
//               jambs = that end stops at an opening (never extend it); opening = door/window id or null
//   DOORS    [{ id, label, cost, areas, rect, y0, y1, width, height, line:[axis,at], span, center, look,
//               requiresPower, keypad, onAir }]  line ['x',7] = the wall x = 7; span = extent along it
//   WINDOWS  [{ id, label, area, type:'boarded'|'fence'|'gate', style, boards, inside, outside, spawn, spawns,
//               rotY, width, sill, top, line, span, wall:[x,z], entryTime }]
//   SCREEN_SPAWNS [{ id, area, pos, rotY, prop }]
//   PLATFORMS [{ id, area, rect, top, ramp, surface, kind }]  ramp > 0 = every edge ramps down over `ramp` m
//   BLOCKERS  [{ id, area, rect, y0, y1, tag }]   static architecture obstacles that are not walls (bleacher rails)
//   RAMPS     [{ id, rect, y0, y1, axis, dir, stairs? }]  ramp faces / stair steps derived from PLATFORMS
//   FLOOR_PATCHES [{ rect, surface }]            footstep surface overrides on the floor (MC metal plates)
//   ANCHORS   { id: { pos:[x,y,z], rotY, area, ...extra } }   every GDD §5.6 anchor, EE objects, toys (§13),
//               shot cams (cam_*: target, fov), feed cams (+ monitors), sponsor sets (mark/pedestal/camera),
//               Telly homes (couch/lamp), prop_* positions quoted in §5.7. mount:'wall' = hangs on a wall.
//   APPLAUSE_ZONE { rect }                       EE step 3 kill zone (T.ee.applauseZone)
//   areaAt(x, z) → area id | null               pure lookup (rects are half-open)
//   WALL_T, ROOF_T, PARAPET, FENCE_H             building constants

import { T } from '../core/config.js';

const PI = Math.PI;

export const WALL_T = 0.3;
export const ROOF_T = 0.3;
export const PARAPET = 0.6;
export const FENCE_H = 3.0;

export const FOOTPRINT = { x0: -7, z0: -30, x1: 51, z1: 6 };

// ---------------------------------------------------------------------------------------------------------
// Areas (§5.2) with lighting per area (§3.3). ambient = post-power hemisphere; ambientPre = emergency-power
// hemisphere (§3.3 "Before Sign-On" column, intensity ×0.6). accent = the area's rim/accent color (§3.5).

export const AREAS = [
  {
    id: 'lobby', name: 'Lobby & Reception', rect: [-7, -6, 7, 6], floorY: 0, ceilY: 4.0, floor: 'carpet',
    ambient: { sky: '#FFE2B8', ground: '#6B4226', intensity: 0.9 },
    ambientPre: { sky: '#FFC27A', ground: '#4A2E1C', intensity: 0.54 },
    fog: null, accent: '#FFC98A',
  },
  {
    id: 'newsroom', name: 'Action 13 News', rect: [7, -6, 23, 4], floorY: 0, ceilY: 4.0, floor: 'tile',
    ambient: { sky: '#E8F0FF', ground: '#5A3620', intensity: 0.85 },
    ambientPre: { sky: '#AFC0E8', ground: '#4A2E1C', intensity: 0.51 },
    fog: null, accent: '#9FC8FF',
  },
  {
    id: 'green_room', name: 'Green Room Hall', rect: [-7, -12, 17, -6], floorY: 0, ceilY: 3.5, floor: 'carpet',
    ambient: { sky: '#FFE6C0', ground: '#8C9A3A', intensity: 0.8 },
    ambientPre: { sky: '#E7A6C2', ground: '#5E6630', intensity: 0.48 },
    fog: null, accent: '#FFD08A',
  },
  {
    id: 'studio_a', name: 'Studio A: Spooktacular Telethon', rect: [-7, -30, 15, -12], floorY: 0, ceilY: 8.0,
    floor: 'tile',
    ambient: { sky: '#FFD0E8', ground: '#3A2440', intensity: 0.7 },
    ambientPre: { sky: '#F2D2A8', ground: '#2A1A30', intensity: 0.42 },
    fog: { color: '#2A1740', near: 18, far: 60 }, accent: '#FF4FA0',
  },
  {
    id: 'studio_b', name: "Studio B: Hootie's Hullabaloo", rect: [15, -28, 29, -14], floorY: 0, ceilY: 6.0,
    floor: 'wood',
    ambient: { sky: '#FFF1E0', ground: '#C9A7FF', intensity: 0.95 },
    ambientPre: { sky: '#BFD4FF', ground: '#8A77B8', intensity: 0.57 },
    fog: null, accent: '#FFB6C8',
  },
  {
    id: 'master_control', name: 'Master Control', rect: [23, -14, 35, -2], floorY: 0, ceilY: 3.6, floor: 'tile',
    ambient: { sky: '#9FC8FF', ground: '#20304A', intensity: 0.55 },
    ambientPre: { sky: '#9FDCFF', ground: '#1A2638', intensity: 0.33 },
    fog: null, accent: '#7FE7FF',
  },
  {
    id: 'yard', name: 'Transmitter Yard', rect: [35, -20, 51, -2], floorY: 0, ceilY: null, floor: 'gravel',
    ambient: { sky: '#2B3A6B', ground: '#1B1E4A', intensity: 0.6 },
    ambientPre: { sky: '#2B3A6B', ground: '#1B1E4A', intensity: 0.36 },
    fog: { color: '#1B2340', near: 30, far: 90 }, accent: '#9FB6FF', sky: true,
  },
];

export function areaAt(x, z) {
  for (const a of AREAS) {
    const r = a.rect;
    if (x >= r[0] && x < r[2] && z >= r[1] && z < r[3]) return a.id;
  }
  return null;
}

const AREA = Object.fromEntries(AREAS.map((a) => [a.id, a]));

// ---------------------------------------------------------------------------------------------------------
// Doors (§5.3, costs from T.doors). look = blocker art + opening beat (level.js).

const doorRow = (id, label, a, b, rect, width, height, look, extra = {}) => {
  const [x0, z0, x1, z1] = rect;
  const alongZ = x1 - x0 < z1 - z0;           // thin in x → the wall is the line x = const
  const line = alongZ ? ['x', (x0 + x1) / 2] : ['z', (z0 + z1) / 2];
  const span = alongZ ? [z0, z1] : [x0, x1];
  return {
    id, label, cost: T.doors[id], areas: [a, b], rect, y0: 0, y1: height, width, height,
    line, span, center: [(x0 + x1) / 2, (z0 + z1) / 2], look,
    requiresPower: false, keypad: false, onAir: false, ...extra,
  };
};

export const DOORS = [
  doorRow('d1_lobby_newsroom', 'D1', 'lobby', 'newsroom', [6.8, -2.2, 7.2, 0.2], 2.4, 2.6, 'glass_chained'),
  doorRow('d2_lobby_green', 'D2', 'lobby', 'green_room', [-1.2, -6.2, 1.2, -5.8], 2.4, 2.6, 'padded'),
  doorRow('d3_newsroom_green', 'D3', 'newsroom', 'green_room', [10.8, -6.2, 13.2, -5.8], 2.4, 2.6, 'debris_desk'),
  doorRow('d4_green_studio_a', 'D4', 'green_room', 'studio_a', [2.4, -12.2, 5.6, -11.8], 3.2, 3.2, 'soundstage',
    { onAir: true }),
  doorRow('d5_newsroom_mc', 'D5', 'newsroom', 'master_control', [22.8, -5.2, 23.2, -2.8], 2.4, 2.6, 'steel_keypad',
    { keypad: true }),
  doorRow('d6_studio_a_b', 'D6', 'studio_a', 'studio_b', [14.8, -21.6, 15.2, -18.4], 3.2, 3.2, 'elephant',
    { onAir: true }),
  doorRow('d7_studio_b_mc', 'D7', 'studio_b', 'master_control', [24.8, -14.2, 27.2, -13.8], 2.4, 2.6, 'debris_cables',
    { onAir: true }),
  doorRow('dy_mc_yard', 'DY', 'master_control', 'yard', [34.8, -9.2, 35.2, -6.8], 2.4, 2.6, 'fire_exit',
    { requiresPower: true }),
];

for (const a of AREAS) {
  a.doors = DOORS.filter((d) => d.areas.includes(a.id)).map((d) => d.id);
  a.adjacent = DOORS.filter((d) => d.areas.includes(a.id)).map((d) => (d.areas[0] === a.id ? d.areas[1] : d.areas[0]));
}

// ---------------------------------------------------------------------------------------------------------
// Windows and entries (§5.4). The wall line sits 0.7 m from `inside` toward `outside`. Sill/top heights per
// style: front glass doors reach the floor, loading/dock windows are tall, clerestories sit 0.6 m above the
// stage deck they open onto. Boarded windows are 1.6 m wide (§5.4); the gate leaf pair is 3.6 m.

const WINDOW_STYLE = {
  glass_door: { sill: 0.0, top: 2.4 },
  window: { sill: 0.8, top: 2.3 },
  loading: { sill: 0.5, top: 2.5 },
  clerestory: { sill: 1.2, top: 2.7 },
  dock: { sill: 0.4, top: 2.6 },
  fence: { sill: 0.0, top: FENCE_H },
  gate: { sill: 0.0, top: FENCE_H },
};

const windowRow = (id, label, area, inside, outside, spawn, rotY, type, style) => {
  const k = 0.7 / 1.7;
  const wall = [inside[0] + (outside[0] - inside[0]) * k, inside[2] + (outside[2] - inside[2]) * k];
  const alongX = Math.abs(outside[2] - inside[2]) > Math.abs(outside[0] - inside[0]);   // wall z = const
  const width = type === 'gate' ? 3.6 : 1.6;
  const c = alongX ? wall[0] : wall[1];
  const s = WINDOW_STYLE[style];
  return {
    id, label, area, type, style,
    boards: type === 'boarded' ? 6 : 0,
    inside, outside, spawn, spawns: [spawn], rotY,
    width, sill: s.sill, top: s.top,
    line: alongX ? ['z', wall[1]] : ['x', wall[0]],
    span: [c - width / 2, c + width / 2],
    wall,
    entryTime: type === 'fence' ? T.zombies.fence : type === 'gate' ? T.zombies.gate : T.zombies.vault,
  };
};

export const WINDOWS = [
  windowRow('w_lobby_front_w', 'B1', 'lobby', [-3, 0, 5.3], [-3, 0, 7], [-3, 0, 9], 0, 'boarded', 'glass_door'),
  windowRow('w_lobby_front_e', 'B2', 'lobby', [3, 0, 5.3], [3, 0, 7], [3, 0, 9], 0, 'boarded', 'glass_door'),
  windowRow('w_lobby_west', 'B3', 'lobby', [-6.3, 0, 0], [-8, 0, 0], [-10, 0, 0], -PI / 2, 'boarded', 'window'),
  windowRow('w_news_south_w', 'B4', 'newsroom', [14, 0, 3.3], [14, 0, 5], [14, 0, 7], 0, 'boarded', 'window'),
  windowRow('w_news_south_e', 'B5', 'newsroom', [19, 0, 3.3], [19, 0, 5], [19, 0, 7], 0, 'boarded', 'window'),
  windowRow('w_green_west', 'B6', 'green_room', [-6.3, 0, -9], [-8, 0, -9], [-10, 0, -9], -PI / 2, 'boarded', 'window'),
  windowRow('w_studio_a_west_n', 'B7', 'studio_a', [-6.3, 0, -24], [-8, 0, -24], [-10, 0, -24], -PI / 2, 'boarded', 'loading'),
  windowRow('w_studio_a_west_s', 'B8', 'studio_a', [-6.3, 0, -18], [-8, 0, -18], [-10, 0, -18], -PI / 2, 'boarded', 'loading'),
  windowRow('w_studio_a_north_w', 'B9', 'studio_a', [0, 0.6, -29.3], [0, 0, -31], [0, 0, -33], PI, 'boarded', 'clerestory'),
  windowRow('w_studio_a_north_e', 'B10', 'studio_a', [8, 0.6, -29.3], [8, 0, -31], [8, 0, -33], PI, 'boarded', 'clerestory'),
  windowRow('w_studio_b_north', 'B11', 'studio_b', [22, 0, -27.3], [22, 0, -29], [22, 0, -31], PI, 'boarded', 'window'),
  windowRow('w_studio_b_east', 'B12', 'studio_b', [28.3, 0, -22], [30, 0, -22], [32, 0, -22], PI / 2, 'boarded', 'dock'),
  windowRow('w_mc_south', 'B13', 'master_control', [32, 0, -2.7], [32, 0, -1], [32, 0, 1], 0, 'boarded', 'window'),
  windowRow('f_yard_north', 'C1', 'yard', [43, 0, -19.3], [43, 0, -21], [43, 0, -23], PI, 'fence', 'fence'),
  windowRow('f_yard_east_n', 'C2', 'yard', [50.3, 0, -14], [52, 0, -14], [54, 0, -14], PI / 2, 'fence', 'fence'),
  windowRow('f_yard_east_s', 'C3', 'yard', [50.3, 0, -6], [52, 0, -6], [54, 0, -6], PI / 2, 'fence', 'fence'),
  windowRow('g_yard_gate', 'G1', 'yard', [49, 0, -2.7], [49, 0, -1], [49, 0, 1], 0, 'gate', 'gate'),
];

// ---------------------------------------------------------------------------------------------------------
// Screen spawns (§5.5).

export const SCREEN_SPAWNS = [
  { id: 'ss_newsroom', area: 'newsroom', pos: [22.3, 1.0, 3.3], rotY: PI / 4, prop: 'Stacked monitor bank' },
  { id: 'ss_green', area: 'green_room', pos: [-0.8, 1.2, -11.85], rotY: PI, prop: 'Wall-mounted TV' },
  { id: 'ss_studio_a_w', area: 'studio_a', pos: [-5.8, 1.0, -28.8], rotY: -3 * PI / 4, prop: 'Big floor-standing stage monitor' },
  { id: 'ss_studio_a_e', area: 'studio_a', pos: [10.3, 1.6, -29.2], rotY: PI, prop: 'Stage monitor on the stage' },
  { id: 'ss_studio_b', area: 'studio_b', pos: [26.0, 1.0, -27.0], rotY: PI, prop: "Hootie's giant TV in the treehouse base" },
  // the MC wall is 4 x 3 big CRTs (bc_monitor_wall): the spawn CRTs are its bottom-row corners (centres x 29.0 / 33.8, y 1.0)
  { id: 'ss_mc_w', area: 'master_control', pos: [29.0, 1.0, -13.8], rotY: PI, prop: 'Bottom-left CRT of the monitor wall' },
  { id: 'ss_mc_e', area: 'master_control', pos: [33.8, 1.0, -13.8], rotY: PI, prop: 'Bottom-right CRT of the monitor wall' },
];

// ---------------------------------------------------------------------------------------------------------
// Platforms, stairs, ramps (§5.7). Studio A stage 0.6 m with its whole front edge a 2-riser stair (0.3 m);
// newsroom anchor riser 0.4 m with ramped edges; bleacher tiers 0.45/0.9/1.35 against the D4 wall.

const TIER = [0.45, 0.9, 1.35];
const bleacherTiers = (side, x0, x1) => TIER.map((top, i) => ({
  id: `bleachers_${side}_${i + 1}`, area: 'studio_a',
  rect: [x0, -14.5 + (2.5 / 3) * i, x1, -12], top, ramp: 0, surface: 'wood', kind: 'bleacher',
}));

export const PLATFORMS = [
  { id: 'stage', area: 'studio_a', rect: [-3, -30, 11, -26], top: 0.6, ramp: 0, surface: 'wood', kind: 'stage' },
  { id: 'stage_step', area: 'studio_a', rect: [-3, -26, 11, -25.5], top: 0.3, ramp: 0, surface: 'wood', kind: 'step' },
  { id: 'anchor_riser', area: 'newsroom', rect: [18, -2, 22, 2], top: 0.4, ramp: 0.5, surface: 'carpet', kind: 'riser' },
  ...bleacherTiers('w', -6.5, 1.5),
  ...bleacherTiers('e', 6.5, 14.5),
];

// Bleacher side rails: stepped end panels 0.9 m above each tier so each block has one approach (the front).
const RAIL_H = 0.9;
const RAIL_T = 0.12;
export const BLOCKERS = [];
for (const [side, x0, x1] of [['w', -6.5, 1.5], ['e', 6.5, 14.5]]) {
  for (const [end, rx0, rx1] of [['a', x0, x0 + RAIL_T], ['b', x1 - RAIL_T, x1]]) {
    TIER.forEach((top, i) => {
      const z0 = -14.5 + (2.5 / 3) * i;
      BLOCKERS.push({
        id: `rail_${side}${end}_${i + 1}`, area: 'studio_a', rect: [rx0, z0, rx1, z0 + 2.5 / 3],
        y0: 0, y1: top + RAIL_H, tag: 'rail',
      });
    });
  }
}

export const RAMPS = PLATFORMS.flatMap((p) => {
  const [x0, z0, x1, z1] = p.rect;
  if (p.kind === 'step') return [{ id: p.id, rect: p.rect, y0: 0, y1: p.top, axis: 'z', dir: -1, stairs: true }];
  if (!p.ramp) return [];
  const r = p.ramp;
  return [
    { id: `${p.id}_w`, rect: [x0, z0, x0 + r, z1], y0: 0, y1: p.top, axis: 'x', dir: 1 },
    { id: `${p.id}_e`, rect: [x1 - r, z0, x1, z1], y0: 0, y1: p.top, axis: 'x', dir: -1 },
    { id: `${p.id}_n`, rect: [x0, z0, x1, z0 + r], y0: 0, y1: p.top, axis: 'z', dir: 1 },
    { id: `${p.id}_s`, rect: [x0, z1 - r, x1, z1], y0: 0, y1: p.top, axis: 'z', dir: -1 },
  ];
});

// Master Control "tile with metal floor plates": cable-trench covers down the VTR aisle and at the monitor wall.
export const FLOOR_PATCHES = [
  { rect: [23.15, -6.0, 34.85, -4.6], surface: 'metal' },
  { rect: [27.6, -13.85, 34.85, -12.6], surface: 'metal' },
];

// ---------------------------------------------------------------------------------------------------------
// Walls, derived from the area rects + openings. Every boundary line is split wherever the area on either
// side changes; openings cut the full-height wall and leave sills and lintels. Outdoor boundaries of the Yard
// are 3 m chain-link fence (the Yard gate leaves its span open for the gate leaves).

// Booth glass (§5.7 Lobby): knee wall, glass, header on z = −3 from x −7 to −4.5; the booth's east side is open.
const EXTRA_WALLS = [
  [-7, -3, -4.5, -3, 0.0, 0.9, 'solid'],
  [-7, -3, -4.5, -3, 0.9, 2.7, 'glass'],
  [-7, -3, -4.5, -3, 2.7, 4.0, 'solid'],
];

const eq = (a, b) => Math.abs(a - b) < 1e-6;

function buildWalls() {
  // 1. Boundary lines: key 'x|7' → list of spans along the line.
  const lines = new Map();
  const addSpan = (axis, at, a, b) => {
    const key = `${axis}|${at}`;
    if (!lines.has(key)) lines.set(key, { axis, at, spans: [] });
    lines.get(key).spans.push([a, b]);
  };
  for (const ar of AREAS) {
    const [x0, z0, x1, z1] = ar.rect;
    addSpan('z', z0, x0, x1); addSpan('z', z1, x0, x1);
    addSpan('x', x0, z0, z1); addSpan('x', x1, z0, z1);
  }
  const openings = [
    ...DOORS.map((d) => ({ id: d.id, line: d.line, span: d.span, sill: 0, top: d.height, gap: false })),
    ...WINDOWS.filter((w) => w.type !== 'fence').map((w) => ({
      id: w.id, line: w.line, span: w.span, sill: w.sill, top: w.top, gap: w.type === 'gate',
    })),
  ];
  const ceil = (id) => (id && AREA[id].ceilY) || 0;
  const indoor = (id) => !!id && !AREA[id].sky;

  const out = [];
  for (const { axis, at, spans } of lines.values()) {
    const ops = openings.filter((o) => o.line[0] === axis && eq(o.line[1], at));
    const cuts = new Set();
    for (const [a, b] of spans) { cuts.add(a); cuts.add(b); }
    for (const o of ops) { cuts.add(o.span[0]); cuts.add(o.span[1]); }
    const pts = [...cuts].sort((p, q) => p - q);
    // 2. Elementary pieces between consecutive cut points.
    const pieces = [];
    for (let i = 0; i < pts.length - 1; i++) {
      const p = pts[i], q = pts[i + 1], m = (p + q) / 2;
      if (!spans.some(([a, b]) => a <= m && m <= b)) continue;
      const probe = (s) => (axis === 'x' ? areaAt(at + s, m) : areaAt(m, at + s));
      const neg = probe(-0.05), pos = probe(0.05);
      const fence = !indoor(neg) && !indoor(pos);
      const top = fence ? FENCE_H
        : Math.max(ceil(indoor(neg) ? neg : null), ceil(indoor(pos) ? pos : null))
          + ROOF_T + (indoor(neg) && indoor(pos) ? 0 : PARAPET);
      const op = ops.find((o) => o.span[0] <= m && m <= o.span[1]) || null;
      pieces.push({ p, q, neg, pos, fence, top, op });
    }
    // 3. Merge runs with equal sides/kind/height and no opening; emit wall boxes.
    for (let i = 0; i < pieces.length; i++) {
      const s = pieces[i];
      let j = i;
      if (!s.op) {
        while (j + 1 < pieces.length) {
          const n = pieces[j + 1];
          if (n.op || n.neg !== s.neg || n.pos !== s.pos || n.fence !== s.fence || n.top !== s.top || !eq(n.p, pieces[j].q)) break;
          j++;
        }
      }
      const a = s.p, b = pieces[j].q;
      const prevOp = i > 0 && pieces[i - 1].op && eq(pieces[i - 1].q, a);
      const nextOp = j + 1 < pieces.length && pieces[j + 1].op && eq(pieces[j + 1].p, b);
      const seg = (y0, y1, kind, jambs, opening) => {
        const [x0, z0, x1, z1] = axis === 'x' ? [at, a, at, b] : [a, at, b, at];
        out.push([x0, z0, x1, z1, y0, y1, kind, { sides: [s.neg, s.pos], jambs, opening }]);
      };
      const kind = s.fence ? 'fence' : 'solid';
      if (!s.op) seg(0, s.top, kind, [!!prevOp, !!nextOp], null);
      else if (!s.op.gap) {
        if (s.op.sill > 0) seg(0, s.op.sill, kind, [true, true], s.op.id);
        if (s.op.top < s.top) seg(s.op.top, s.top, kind, [true, true], s.op.id);
      }
      i = j;
    }
  }
  for (const w of EXTRA_WALLS) {
    out.push([...w, { sides: ['lobby', 'lobby'], jambs: [false, true], opening: null }]);
  }
  return out;
}

export const WALLS = buildWalls();

// ---------------------------------------------------------------------------------------------------------
// Anchors (§5.6, §5.7, §13, §18.10, §18.13).

const yawTo = (from, to) => Math.atan2(-(to[0] - from[0]), -(to[2] - from[2]));
const A = (pos, rotY, area, extra = {}) => ({ pos, rotY, area, ...extra });
const wall = (pos, rotY, area, extra = {}) => ({ pos, rotY, area, mount: 'wall', ...extra });

const cam = (pos, target, area) => ({ pos, target, rotY: yawTo(pos, target), area, fov: 70 });

const sponsorSet = (perk, area, mark, pedestal, camera, extra = {}) => ({
  pos: mark, rotY: yawTo(mark, camera), area, perk, mark, pedestal, camera,
  target: [mark[0], 1.2, mark[2]], size: [3, 3], ...extra,
});

const feedCam = (pos, target, fov, area, monitors) => ({ pos, target, rotY: yawTo(pos, target), fov, area, monitors });

const tellyHome = (label, pos, rotY, area, couch, couchRotY, lamp) => ({
  pos, rotY, area, label, couch: { pos: couch, rotY: couchRotY }, lamp: { pos: lamp },
});

const bar = (color, z, note, freq, length) => wall([-6.7, 2.5, z], -PI / 2, 'lobby', { color, note, freq, length });

export const ANCHORS = {
  // Player & wall-buys (§5.6, §18.6)
  // x -1.3 / z 3.5 (was 0 / 4): the shoulder camera, pulled in against the south wall, sat right behind the lobby
  // letter board (x 0.3..2.1, z 5.1) and the board filled half the first frame of every game.
  player_spawn: A([-1.3, 0, 3.5], 0, 'lobby'),
  wb_pump: wall([4.0, 1.4, -5.9], PI, 'lobby', { gives: 'pump_37', show: 'Dusty Trails' }),
  wb_mp7: wall([21.0, 1.4, -5.9], PI, 'newsroom', { gives: 'mp7', show: 'Agent Thirteen' }),
  wb_m16: wall([-6.9, 1.4, -21.0], -PI / 2, 'studio_a', { gives: 'm16a1', show: 'Commando Club' }),
  wb_grenades: wall([-3.0, 1.4, -11.9], PI, 'green_room', { gives: 'tube_grenade', show: 'Tube-O-Matic' }),

  // Machines (§5.6, §18.10)
  sign_on_lever: A([29, 0, -7.6], PI, 'master_control'),
  mc_console: A([29, 0, -9.25], PI, 'master_control', { size: [4, 1.0, 1.5], rect: [27, -10, 31, -8.5] }),
  telly_home_green: tellyHome('T1', [16.2, 0, -9.0], PI / 2, 'green_room', [13.2, 0, -9.0], -PI / 2, [16.4, 0, -11.3]),
  telly_home_newsroom: tellyHome('T2', [7.9, 0, 2.6], -PI / 2, 'newsroom', [10.6, 0, 2.6], PI / 2, [7.6, 0, 3.6]),
  telly_home_studio_a: tellyHome('T3', [14.2, 0, -16.5], PI / 2, 'studio_a', [11.6, 0, -16.5], -PI / 2, [14.4, 0, -15.0]),
  telly_home_studio_b: tellyHome('T4', [28.3, 0, -18.5], PI / 2, 'studio_b', [25.9, 0, -18.5], -PI / 2, [28.5, 0, -17.0]),
  uplink_dish: A([38.5, 0, -17.5], PI, 'yard', { radius: 2.5 }),
  uplink_cradle: A([38.5, 1.3, -14.6], PI, 'yard'),
  uplink_crank: A([36.4, 1.0, -13.9], PI, 'yard'),
  tower_base: A([45, 0, -12], 0, 'yard', { rect: [43, -14, 47, -10], height: 30 }),

  // Sponsor sets (§5.6 / §10.3): pos = the floor mark X, rotY = the set faces its camera
  set_replay_ade: sponsorSet('replay_ade', 'lobby', [-5.0, 0, 4.1], [-6.2, 0, 4.1], [-3.2, 0, 4.1], { portable: true }),
  set_jump_cut: sponsorSet('jump_cut', 'green_room', [9.5, 0, -10.1], [9.5, 0, -11.3], [9.5, 0, -7.2]),
  set_double_vision: sponsorSet('double_vision', 'studio_a', [13.2, 0, -27.9], [13.9, 0, -29.3], [12.0, 0, -25.6]),
  set_wobble_up: sponsorSet('wobble_up', 'studio_b', [16.9, 0, -15.9], [15.9, 0, -14.7], [18.8, 0, -17.8]),
  set_roller_boogie: sponsorSet('roller_boogie', 'yard', [49.1, 0, -18.2], [50.2, 0, -19.2], [47.2, 0, -15.9]),

  // Live feed cameras (§5.6 / §10.0) and the monitors showing them
  feed_cam_lobby: feedCam([5.6, 1.6, 4.6], [-6.75, 1.2, -2.0], 40, 'lobby', ['mon_lobby_exhibit', 'mon_lobby_booth']),
  feed_cam_newsroom: feedCam([16.8, 1.6, 2.0], [20.2, 1.4, 0.0], 50, 'newsroom', ['mon_newsroom_cart']),
  feed_cam_studio_a: feedCam([-2.0, 1.7, -17.5], [4.0, 2.6, -29.3], 35, 'studio_a', ['mon_studio_a_stand']),
  feed_cam_studio_b: feedCam([21.0, 1.7, -16.5], [17.75, 1.3, -25.5], 55, 'studio_b', ['mon_studio_b_stand']),
  feed_cam_yard: feedCam([37.0, 3.6, -3.8], [45, 3, -12], 60, 'yard', ['mon_yard_hut', 'mon_yard_van']),
  mon_lobby_exhibit: A([4.6, 1.5, 5.4], PI / 4, 'lobby', { group: 'scr_feed_lobby', feed: 'feed_cam_lobby' }),
  mon_lobby_booth: wall([-5.6, 1.9, -5.85], PI, 'lobby', { group: 'scr_feed_lobby', feed: 'feed_cam_lobby' }),
  mon_newsroom_cart: A([16.4, 1.4, 3.2], 0, 'newsroom', { group: 'scr_feed_newsroom', feed: 'feed_cam_newsroom' }),
  mon_studio_a_stand: A([1.2, 1.5, -17.0], 0, 'studio_a', { group: 'scr_feed_studio_a', feed: 'feed_cam_studio_a' }),
  mon_studio_b_stand: A([19.8, 1.5, -15.0], 0, 'studio_b', { group: 'scr_feed_studio_b', feed: 'feed_cam_studio_b' }),
  mon_yard_hut: A([37.1, 1.2, -5.1], 0, 'yard', { group: 'scr_feed_yard', feed: 'feed_cam_yard', count: 2 }),
  mon_yard_van: A([45.4, 1.2, -3.7], -PI / 2, 'yard', { group: 'scr_feed_yard', feed: 'feed_cam_yard' }),

  // Easter-egg objects (§5.6, §13, §18.13)
  ee_chime_rack: A([-6.7, 0, -4.5], -PI / 2, 'lobby', {
    barTop: 2.5, bars: { green: -3.9, blue: -4.3, red: -4.7, yellow: -5.1 },
  }),
  ee_bar_red: bar('red', -4.7, 'G4', 392.0, 1.20),
  ee_bar_yellow: bar('yellow', -5.1, 'C5', 523.3, 1.05),
  ee_bar_green: bar('green', -3.9, 'E5', 659.3, 0.90),
  ee_bar_blue: bar('blue', -4.3, 'G5', 784.0, 0.75),
  ee_trophy_case: A([-6.75, 0, -2.0], -PI / 2, 'lobby', { length: 1.8, span: [-2.9, -1.1] }),
  ee_puppet_dudley: A([-6.75, 1.3, -2.0], -PI / 2, 'lobby', { drop: [-6.0, 0, -2.0], feed: 'feed_lobby' }),
  ee_anchor_desk: A([20.2, 0.4, 0.0], PI / 2, 'newsroom', {
    height: 0.8, top: 1.2, chair: { pos: [21.0, 0.4, 0.0], rotY: PI / 2 },
  }),
  ee_puppet_sockrates: A([20.2, 1.45, 0.0], PI / 2, 'newsroom', { drop: [19.6, 0.4, 0.0], feed: 'feed_newsroom' }),
  ee_prize_wheel: A([4.0, 0.6, -29.7], PI, 'studio_a', { diameter: 4, wedges: 13 }),
  ee_puppet_hootie: A([4.0, 2.6, -29.3], PI, 'studio_a', { drop: [4.0, 0.6, -28.6], feed: 'feed_studio_a' }),
  ee_puppet_theater: A([17.75, 0, -26.5], PI, 'studio_b', {
    rect: [16, -27.5, 19.5, -25.5],
    slots: [[17.0, 1.3, -25.5], [17.75, 1.3, -25.5], [18.5, 1.3, -25.5]],
    interact: [17.75, 0, -24.9], interactR: 1.5,
  }),
  ee_applause_sign: wall([4.0, 5.0, -12.15], 0, 'studio_a'),
  ee_tote_board: A([4, 0, -21], 0, 'studio_a', { size: [1.2, 3.2, 1.2] }),
  ee_applause_zone: A([4, 0, -16.75], 0, 'studio_a', { rect: T.ee.applauseZone }),
  ee_weather_map: wall([17.5, 2.0, -5.9], PI, 'newsroom', { size: [3, 2] }),
  ee_vtr2: A([26.75, 0, -2.6], 0, 'master_control', { size: [1.3, 1.9, 1.0], monitor: [26.75, 2.3, -2.4] }),
  vtr_1: A([25.25, 0, -2.6], 0, 'master_control', { size: [1.3, 1.9, 1.0] }),
  vtr_3: A([28.25, 0, -2.6], 0, 'master_control', { size: [1.3, 1.9, 1.0] }),
  ee_tracking_knob: A([26.75, 1.1, -3.15], 0, 'master_control', { detents: 13 }),
  ee_rundown_board: wall([23.1, 1.6, -11.0], -PI / 2, 'master_control', { slots: 6 }),
  ee_kill_switch: A([45, 0, -9.7], PI, 'yard', { stand: [45, 0, -9.0] }),

  // Hidden toys (§13)
  toy_desk_bell: A([1.2, 1.1, -0.4], 0, 'lobby'),
  toy_exhibit_camera: A([5.6, 1.2, 4.6], 0, 'lobby'),
  toy_lava_lamp: A([-4.0, 0.9, -11.3], 0, 'green_room'),
  toy_payphone: wall([-6.8, 1.4, -7.5], -PI / 2, 'green_room'),
  toy_typewriter: A([11.0, 0.8, -3.6], 0, 'newsroom'),
  toy_globe: A([19.0, 1.1, 1.5], 0, 'newsroom'),
  toy_teletype: A([8.2, 0.9, -5.3], 0, 'newsroom'),
  toy_laff_o_matic: A([30.2, 1.0, -8.3], 0, 'master_control'),
  toy_switcher: A([28.0, 1.0, -8.3], 0, 'master_control'),
  toy_ghost_light: A([6.8, 0.6, -27.0], 0, 'studio_a'),
  toy_prize_wheel: A([5.8, 0.6, -28.8], 0, 'studio_a'),
  toy_train: A([19.0, 0.5, -19.0], 0, 'studio_b'),
  toy_xylophone: A([24.0, 0.6, -25.0], 0, 'studio_b'),
  toy_van_radio: A([41.0, 1.0, -4.9], 0, 'yard'),

  // Shot cameras for art review (§5.6)
  cam_lobby: cam([0, 1.7, 5.5], [0, 1.8, -2], 'lobby'),
  cam_hero: cam([0, 1.3, 1.8], [0, 1.0, 4], 'lobby'),
  cam_chimes: cam([-4.2, 1.6, -4.5], [-6.7, 1.8, -4.5], 'lobby'),
  cam_newsroom: cam([8.5, 2.2, 3.5], [20, 1.2, -1], 'newsroom'),
  cam_green_room: cam([-6, 2.0, -7], [16, 1.0, -9], 'green_room'),
  cam_telly: cam([13.6, 1.3, -9.0], [16.2, 0.8, -9.0], 'green_room'),
  cam_studio_a: cam([13.5, 4.5, -13], [2, 1.5, -25], 'studio_a'),
  cam_studio_b: cam([28, 3.5, -15], [18, 1.5, -25], 'studio_b'),
  cam_master_control: cam([24, 2.2, -3], [31, 1.5, -12], 'master_control'),
  cam_yard: cam([36, 3.0, -3], [45, 5, -15], 'yard'),
  cam_uplink: cam([38.5, 1.8, -11.5], [38.5, 2.5, -17.5], 'yard'),

  // Prop positions quoted in §5.7 (room agents build them; tests keep them clear of walls)
  prop_reception_desk: A([0, 0, -0.5], PI, 'lobby', { rect: [-2, -1.0, 2, 0.0], height: 1.1 }),
  prop_logo_partition: A([0, 0, -1.35], 0, 'lobby', { rect: [-2, -1.5, 2, -1.2], height: 2.4, neonY: [1.5, 2.3] }),
  prop_announce_booth: A([-5.75, 0, -4.5], -PI / 2, 'lobby', { rect: [-7, -6, -4.5, -3] }),
  prop_lobby_clock: wall([0, 3.1, -5.85], PI, 'lobby'),
  prop_reporter_desks_n: A([13, 0, -3.6], 0, 'newsroom', { rect: [10, -4.2, 16, -3.0], count: 3 }),
  prop_reporter_desks_s: A([13, 0, 1.0], 0, 'newsroom', { rect: [10, 0.4, 16, 1.6], count: 3 }),
  prop_skyline_backdrop: wall([22.85, 0, 1.0], PI / 2, 'newsroom', { span: [-1.5, 3.5] }),
  prop_vending: A([-5.9, 0, -11.4], PI, 'green_room', { span: [-6.6, -5.2] }),
  prop_dressing_doors: wall([-4.05, 0, -6.15], 0, 'green_room', { span: [-6.5, -1.6], count: 5 }),
  prop_throne: A([-1.5, 0.6, -28.3], PI, 'studio_a'),
  prop_carousel: A([4, 0, -21], 0, 'studio_a', { radius: 2.0, height: 1.0, phones: 12 }),
  prop_disco_ball: A([4, 6.5, -21], 0, 'studio_a'),
  prop_lighting_grid: A([4, 6.5, -21], 0, 'studio_a', { rect: [-7, -30, 15, -12] }),
  prop_rocket: A([22, 0, -21], 0, 'studio_b', { radius: 1.4, height: 5.5 }),
  prop_treehouse: A([25.5, 0, -27.6], 0, 'studio_b', { rect: [23, -28, 28, -27.2] }),
  prop_cyclorama: wall([28.85, 0, -25.5], PI / 2, 'studio_b', { span: [-27.5, -23.5] }),
  prop_alpha_block_1: A([18.5, 0, -22.5], 0, 'studio_b', { size: 1 }),
  prop_alpha_block_2: A([25.5, 0, -24.0], 0, 'studio_b', { size: 1 }),
  prop_alpha_block_3: A([26.5, 0, -23.2], 0, 'studio_b', { size: 1 }),
  prop_rainbow_arch: A([24.5, 0, -15.5], 0, 'studio_b'),
  prop_monitor_wall: wall([31.4, 0.6, -13.85], PI, 'master_control', { span: [28.2, 34.6], y: [0.6, 3.4], grid: [4, 3] }),
  prop_perpetua_crate: A([33.8, 0, -4.0], 0, 'master_control'),
  prop_hut: A([37.1, 0, -3.7], 0, 'yard', { rect: [35.4, -5.0, 38.8, -2.4] }),
  prop_van: A([43.0, 0, -3.7], -PI / 2, 'yard', { rect: [40.5, -4.8, 45.5, -2.6] }),
  prop_lamp_post_1: A([41.5, 0, -19.5], 0, 'yard'),
  prop_lamp_post_2: A([50.5, 0, -10], 0, 'yard'),
};

export const APPLAUSE_ZONE = { rect: T.ee.applauseZone };
