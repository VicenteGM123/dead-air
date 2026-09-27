// Room dressing: GREEN ROOM HALL (GDD §5.7 "Green Room", §3.3 lighting, §2 story props, §13 toys, §18.13 ids).
// Owner: rooms-green-mc. build(game, area, root) runs once from level.build() after the graybox; static meshes are
// merged per material by the level afterwards, animated / switchable parts are flagged noMerge. Uses the room kit
// exported by lobby.js (roomKit: colliders, power-wave switches, frame hook) and a few local builders (ids gm_*).
//
// Layout (world metres; inner wall faces x -6.85 / 16.85, z -11.85 (north) / -6.15 (south); ceiling 3.5):
//   west end   cigarette + Fizz-Up vending machines (north wall x -6.8..-4.9), trash can, lava lamp on a drum table
//              (toy_lava_lamp), coat rail + plant hanger (west wall), rotary payphone with a hanging phone book and
//              a stool (toy_payphone, west wall z -7.5), moonlight slats through the boarded B6 window
//   south wall five dressing-room doors x -6.8..-1.8 (Baron / Penny / Roxy / Skip / Duke; the Baron's has the
//              porthole and leaks a purple Channel-0 glow under it) under a backstage clock at 11:59; EXIT boxes over
//              D2 / D3; the Hollywood vanity x 2.9..7.7 (4.8 m, clear of D2's swinging east leaf)
//              (3 bulb-ringed mirrors, wig head + afro, cucumber plate, make-up kit, boa) with Duke's reclining
//              make-up chair and two director's chairs; call board + ash urn + fern east of D3
//   north wall ss_green built-in wall TV at [-0.8, 1.2] (screen spawn), garment rack of costumes + steamer trunk
//              with the Hootie costume head beside D4, QUIET PLEASE sign, water cooler + Hootie poster, hi-fi
//              console behind the T1 couch; framed test card above the Telly home (east wall)
//   kept clear Tube-O-Matic (wb_grenades, economy), Jump Cut set x 8..11 (sponsors), T1 Telly home x 12.4..16.85
//              (telly), 2 m in front of B6 / D2 / D3 / D4 / the wall-buy.
//
// Power (GDD §3.3): before Sign-On only the lava lamp, the vending machines, the EXIT boxes and the moonlight;
// when the colour wave reaches them the make-up mirror bulbs + dressing-room sconces switch on (one merged
// switchable mesh, 3-flash flicker) with their light anchors / floor pools.
//
// game.level.objects entries (world space):
//   ss_green      { group, screen }                        the screen-spawn wall TV (screen id 'ss_green', scr_decor)
//   gr_vanity     { group, parts:{ bulbs } , setBulbs(on) } bulbs = every switchable bulb of the room (vanity + doors)
//   gr_makeup_chair { group }   gr_dressing_doors { doors:[Group], baron:Group }   gr_clock { group, parts }
//   toy_lava_lamp { group, parts:{ blobs, glow }, play() }  toy_payphone { group, play() }
// Toys (GDD §13, key-only [E]): toy_lava_lamp ('toy_lava': the wax bloops 4x faster for 10 s),
//   toy_payphone ('toy_payphone': busy tone, the phone rattles on the wall). Each emits 'toy:use' {id}.

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import * as K from '../../props/kit.js';
import { PAL } from '../../props/kit.js';
import { roomKit, atlasMats, cellPlane, decal, exitSign, moonSlats } from './lobby.js';
import { stdMats, tc, ribbon } from './newsroom.js';
import { ANCHORS } from '../layout.js';

const PI = Math.PI;
const HP = PI / 2;
const TAU = PI * 2;
const WALL = { n: -11.85, s: -6.15, w: -6.85, e: 16.85 };
const sph = (r, ws = 14, hs = 10) => new THREE.SphereGeometry(r, ws, hs);
const hash = (n) => { const s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); };

// ================================================================================================ gm atlas
// 512² print atlas (4 x 4 cells of 128 px) for the green room's own printed bits: chair backs, phone book,
// LP sleeves, notes, lipstick doodles, hi-fi plate. cell(name) -> [u0, v0, u1, v1].
const GCELLS = {
  chair_duke: [0, 0, 2, 1], chair_talent: [2, 0, 2, 1], chair_roxy: [0, 1, 2, 1], phonebook: [2, 1], note: [3, 1],
  lp1: [0, 2], lp2: [1, 2], lp3: [2, 2], lp4: [3, 2], doodle: [0, 3], lipstick: [1, 3], hifi: [2, 3, 2, 1],
};
function gmAtlasTex() {
  return K.tex.canvas('rooms.gm.atlas.v1', 512, 512, (ctx, W, H, rand) => {
    ctx.clearRect(0, 0, W, H);
    const C = 128;
    const at = (n) => { const c = GCELLS[n]; return [c[0] * C, c[1] * C, (c[2] ?? 1) * C, (c[3] ?? 1) * C]; };
    const rr = (x, y, w, h, r) => { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); };
    const text = (s, x, y, size, font, fill, o = {}) => {
      ctx.save();
      ctx.translate(x, y);
      if (o.rot) ctx.rotate(o.rot);
      let sz = size;
      ctx.font = `${sz}px ${font}`;
      if (o.max) while (ctx.measureText(s).width > o.max && sz > 6) { sz *= 0.93; ctx.font = `${sz}px ${font}`; }
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      if (o.stroke) { ctx.lineWidth = o.lw || size * 0.12; ctx.strokeStyle = o.stroke; ctx.lineJoin = 'round'; ctx.strokeText(s, 0, 0); }
      ctx.fillStyle = fill; ctx.fillText(s, 0, 0);
      ctx.restore();
    };
    const SIGN = '"Bungee", Impact, "Arial Black", sans-serif';
    const ROUND = '"Titan One", "Arial Rounded MT Bold", "Arial Black", sans-serif';
    const GROOVY = '"Shrikhand", "Cooper Black", Georgia, serif';
    // director's chair backs (canvas stripe + stencil name)
    for (const [n, name, bg, fg] of [['chair_duke', 'DUKE', '#E3662B', '#FFF4DA'], ['chair_talent', 'TALENT', '#2F5BD3', '#FFE3A3'], ['chair_roxy', 'ROXY', '#6B3A6E', '#FFD23A']]) {
      const [x, y, w, h] = at(n);
      ctx.fillStyle = bg; ctx.fillRect(x, y, w, h);
      ctx.fillStyle = 'rgba(0,0,0,0.12)'; for (let i = 0; i < w; i += 6) ctx.fillRect(x + i, y, 2, h);
      ctx.fillStyle = fg; ctx.fillRect(x, y + 8, w, 6); ctx.fillRect(x, y + h - 14, w, 6);
      text(name, x + w / 2, y + h / 2 + 3, 62, SIGN, fg, { max: w - 30 });
    }
    // phone book
    { const [x, y, w, h] = at('phonebook');
      ctx.fillStyle = '#F4D23A'; ctx.fillRect(x, y, w, h);
      ctx.fillStyle = '#2A2231'; ctx.fillRect(x, y + 12, w, 4);
      text('YELLOW', x + w / 2, y + 40, 26, SIGN, '#2A2231');
      text('PAGES', x + w / 2, y + 70, 26, SIGN, '#2A2231');
      ctx.fillStyle = '#2A2231'; ctx.beginPath(); ctx.ellipse(x + w / 2, y + 102, 16, 10, 0, 0, TAU); ctx.fill();
      text('TRI-COUNTY 1977', x + w / 2, y + 120, 11, ROUND, '#5A3A22'); }
    // pinned note
    { const [x, y, w, h] = at('note');
      ctx.fillStyle = '#FFF0A0'; rr(x + 8, y + 8, w - 16, h - 16, 4); ctx.fill();
      text('CALL', x + w / 2, y + 36, 24, ROUND, '#2A2A8A', { rot: -0.06 });
      text('555-1313', x + w / 2, y + 66, 20, ROUND, '#E23B3B', { rot: -0.05 });
      text('ASK 4 STU', x + w / 2, y + 96, 15, ROUND, '#2A2A8A', { rot: -0.04 }); }
    // LP sleeves
    const lp = (n, bg, draw) => { const [x, y, w, h] = at(n); ctx.fillStyle = bg; ctx.fillRect(x, y, w, h); ctx.save(); ctx.translate(x, y); draw(w, h); ctx.restore(); };
    lp('lp1', '#E3662B', (w, h) => { for (let i = 0; i < 5; i++) { ctx.fillStyle = ['#FFD23A', '#E23B3B', '#6B3A6E', '#2F5BD3', '#52E04A'][i]; ctx.beginPath(); ctx.arc(w / 2, h + 10, 110 - i * 20, PI, TAU); ctx.fill(); } text('FUNK', w / 2, 30, 30, GROOVY, '#FFF4DA'); });
    lp('lp2', '#1E1530', (w, h) => { ctx.fillStyle = '#FF5FA2'; ctx.beginPath(); ctx.arc(w / 2, h / 2, 40, 0, TAU); ctx.fill(); ctx.fillStyle = '#FFD23A'; ctx.beginPath(); ctx.arc(w / 2, h / 2, 14, 0, TAU); ctx.fill(); text('DISCO', w / 2, 22, 22, SIGN, '#7FE7FF'); });
    lp('lp3', '#F6E7C8', (w, h) => { ctx.fillStyle = '#8C9A3A'; ctx.fillRect(0, h * 0.55, w, h); ctx.fillStyle = '#E8A92E'; ctx.beginPath(); ctx.arc(w * 0.7, h * 0.45, 22, 0, TAU); ctx.fill(); text('Country Hits', w / 2, 24, 18, GROOVY, '#5A3A22'); });
    lp('lp4', '#2F5BD3', (w, h) => { ctx.strokeStyle = '#FFF4DA'; ctx.lineWidth = 6; for (let i = 0; i < 6; i++) { ctx.beginPath(); ctx.moveTo(0, 30 + i * 16); ctx.bezierCurveTo(w * 0.3, 10 + i * 16, w * 0.7, 50 + i * 16, w, 30 + i * 16); ctx.stroke(); } text('SMOOTH', w / 2, h - 20, 22, SIGN, '#FFD23A'); });
    // phone-wall doodles (transparent)
    { const [x, y] = at('doodle');
      ctx.strokeStyle = 'rgba(40,30,70,0.8)'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.moveTo(x + 30, y + 40); ctx.bezierCurveTo(x + 10, y + 10, x + 50, y + 5, x + 30, y + 40); ctx.stroke();
      for (let i = 0; i < 3; i++) { const cx = x + 70 + i * 16, cy = y + 30 + i * 22; ctx.beginPath(); for (let k = 0; k < 10; k++) { const a = -HP + k * PI / 5, r = k % 2 ? 4 : 10; ctx.lineTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r); } ctx.closePath(); ctx.stroke(); }
      text('555-0113', x + 50, y + 92, 18, ROUND, 'rgba(40,30,70,0.85)', { rot: -0.15 });
      text('B.V.S.', x + 88, y + 116, 14, ROUND, 'rgba(150,30,60,0.85)', { rot: 0.1 }); }
    // lipstick on the mirror (transparent)
    { const [x, y] = at('lipstick');
      ctx.fillStyle = '#E2234A';
      ctx.beginPath(); ctx.moveTo(x + 64, y + 58); ctx.bezierCurveTo(x + 64, y + 30, x + 24, y + 30, x + 24, y + 54); ctx.bezierCurveTo(x + 24, y + 74, x + 50, y + 84, x + 64, y + 100);
      ctx.bezierCurveTo(x + 78, y + 84, x + 104, y + 74, x + 104, y + 54); ctx.bezierCurveTo(x + 104, y + 30, x + 64, y + 30, x + 64, y + 58); ctx.lineWidth = 6; ctx.strokeStyle = '#E2234A'; ctx.stroke();
      text('BREAK A LEG!', x + 64, y + 118, 15, GROOVY, '#E2234A', { rot: -0.08 }); }
    // hi-fi faceplate
    { const [x, y, w, h] = at('hifi');
      ctx.fillStyle = '#D8D2C2'; ctx.fillRect(x, y, w, h);
      ctx.fillStyle = '#2A2231'; rr(x + 10, y + 12, w - 20, 46, 8); ctx.fill();
      ctx.fillStyle = '#FFB347'; ctx.fillRect(x + 20, y + 20, w - 40, 30);
      ctx.fillStyle = '#5A3A22'; for (let i = 0; i < 18; i++) ctx.fillRect(x + 26 + i * 11.5, y + 22, 2, i % 3 ? 10 : 18);
      ctx.fillStyle = '#E23B3B'; ctx.fillRect(x + 120, y + 20, 3, 30);
      text('STEREO-MATIC 8000', x + w / 2, y + 84, 22, SIGN, '#5A3A22', { max: w - 30 });
      text('AM · FM · PHONO', x + w / 2, y + 110, 14, ROUND, '#7A4A2A'); }
    void W; void H; void rand;
  }, { repeat: false, fonts: true });
}
function gmAtlas(game) {
  const map = gmAtlasTex();
  map.anisotropy = 8;
  const cell = (name) => { const c = GCELLS[name]; return [c[0] / 4, 1 - (c[1] + (c[3] ?? 1)) / 4, (c[0] + (c[2] ?? 1)) / 4, 1 - c[1] / 4]; };
  return {
    map, cell,
    mat: K.mat(game, 'paint', '#ffffff', { map, rim: 0.12 }),
    decal: K.mat(game, 'plastic', '#ffffff', { map, alphaTest: 0.5, side: THREE.DoubleSide }),
  };
}
// Plane w x h facing -z (prop front) with the UVs of a gm atlas cell.
function gPlane(ga, name, w, h, face = '-z') {
  const [u0, v0, u1, v1] = ga.cell(name);
  const g = new THREE.PlaneGeometry(w, h);
  K.uvRect(g, u0, v0, u1, v1);
  if (face === '-z') g.rotateY(PI);
  else if (face === '+y') g.rotateX(-HP);
  return g;
}

// ============================================================================================ local builders
// Switchable bulbs: one geometry merged from bulb spheres (local positions), off/on materials swapped at Sign-On.
function mirrorMat(game) {
  const map = K.tex.canvas('rooms.gm.mirror.v1', 256, 256, (ctx, w, h) => {
    const g = ctx.createLinearGradient(0, 0, w * 0.3, h);
    g.addColorStop(0, '#C9DAE4'); g.addColorStop(0.55, '#8FA4B6'); g.addColorStop(1, '#5E6F84');
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
    ctx.save(); ctx.translate(w / 2, h / 2); ctx.rotate(-0.62);
    ctx.fillStyle = 'rgba(255,255,255,0.55)'; ctx.fillRect(-w, -64, w * 2, 26);
    ctx.fillStyle = 'rgba(255,255,255,0.32)'; ctx.fillRect(-w, -22, w * 2, 10);
    ctx.fillStyle = 'rgba(255,255,255,0.22)'; ctx.fillRect(-w, 58, w * 2, 16);
    ctx.restore();
  }, { repeat: false });
  return K.mat(game, 'lacquer', '#ffffff', { map, env: 0.22, rough: 0.12, rim: 0.1 });
}
function bulbMats(game) {
  return { on: K.glow(game, '#FFD08A', 2.3), off: K.mat(game, 'ceramic', '#E9DDC6', { rim: 0.35 }) };
}
function bulbGeo(points, r = 0.036) {
  const base = new THREE.SphereGeometry(r, 10, 7);
  const geos = points.map(([x, y, z]) => base.clone().translate(x, y, z));
  const g = mergeGeometries(geos, false);
  geos.forEach((x) => x.dispose());
  return g;
}

// ---------------------------------------------------------------------------------------- Hollywood vanity
// Long make-up counter against a wall: drawer banks + knee holes, harvest-gold top, three bulb-ringed mirrors on
// the wall, per-station clutter (Roxy's wig head + afro pick, Duke's cucumber plate + towel + make-up kit, a boa,
// brushes, tissue box, radio). Front -z, back (wall) at local z = +D/2. parts.bulbs (merged, noMerge).
function vanity(game, am, ga, { len = 6.0 } = {}) {
  const g = K.prop('gm_vanity');
  const mt = stdMats(game);
  const W = len, D = 0.56, H = 0.8, bz = D / 2;
  const cream = '#F3E6C8', choc = '#4A2E22', gold = '#E8A92E', orange = '#E3662B';
  const sp = Math.min(2.0, (W - 1.7) / 2);   // station spacing: 2.0 on a 6 m counter, tighter on a shorter one
  const st = [-sp, 0, sp];
  const knee = 0.74;
  // kick + banks
  g.add(K.m(tc(K.box(W - 0.08, 0.08, D - 0.1, 'sm'), choc), mt.paint, { pos: [0, 0.04, 0.03] }));
  const edges = [-W / 2];
  for (const x of st) edges.push(x - knee / 2, x + knee / 2);
  edges.push(W / 2);
  const pull = K.tube([[-0.07, 0, 0], [-0.06, 0, -0.022], [0.06, 0, -0.022], [0.07, 0, 0]], 0.0075, { seg: 8, radial: 5 });
  for (let i = 0; i < edges.length; i += 2) {
    const x0 = edges[i], x1 = edges[i + 1], w = x1 - x0, cx = (x0 + x1) / 2;
    g.add(K.m(tc(K.box(w - 0.01, H - 0.12, D - 0.04, 'md'), cream), mt.lacquer, { pos: [cx, 0.08 + (H - 0.12) / 2, 0.01] }));
    const n = w > 1.0 ? 2 : 1;
    for (let k = 0; k < n; k++) {
      const dx = n === 1 ? cx : cx + (k - 0.5) * (w / 2);
      const dw = w / n - 0.06;
      [0.2, 0.2, 0.26].reduce((y, h, j) => {
        const cy = y - h / 2;
        g.add(K.m(tc(K.box(dw, h - 0.02, 0.03, 'sm'), j === 2 ? orange : gold), mt.lacquer, { pos: [dx, cy, -D / 2 + 0.005] }));
        g.add(K.m(pull, mt.chrome, { pos: [dx, cy + h * 0.2, -D / 2 - 0.012] }));
        return y - h;
      }, H - 0.08);
    }
  }
  for (const x of st) {
    g.add(K.m(tc(K.box(knee, H - 0.2, 0.03, 'sm'), '#6A4A36'), mt.paint, { pos: [x, (H - 0.2) / 2 + 0.06, bz - 0.04] }));
    g.add(K.m(tc(K.box(knee - 0.02, 0.1, 0.03, 'sm'), gold), mt.lacquer, { pos: [x, H - 0.12, -D / 2 + 0.005] }));
    g.add(K.m(pull, mt.chrome, { pos: [x, H - 0.12, -D / 2 - 0.012] }));
  }
  // top: laminate slab with a chocolate bullnose band + low backsplash
  g.add(K.m(tc(K.box(W + 0.04, 0.045, D + 0.04, 'md'), gold), mt.lacquer, { pos: [0, H - 0.0225, 0] }));
  g.add(K.m(tc(K.box(W + 0.05, 0.03, 0.05, 'sm'), choc), mt.lacquer, { pos: [0, H - 0.035, -D / 2 - 0.01] }));
  g.add(K.m(tc(K.box(W, 0.14, 0.03, 'sm'), cream), mt.lacquer, { pos: [0, H + 0.07, bz - 0.015] }));
  // mirrors: cream frames with bulbs, mirror glass, lipstick + polaroids
  const mirror = K.mat(game, 'chrome', '#C6D4DC', { rough: 0.07, env: 0.85, rim: 0.1 });
  const bulbs = [];
  const MW = 1.14, MH = 0.94, my = 1.55;
  for (const x of st) {
    const fr = K.roundRect(MW + 0.2, MH + 0.2, 0.09);
    fr.holes.push(new THREE.Path(K.roundRect(MW, MH, 0.05).getPoints(6)));
    g.add(K.m(tc(K.extrude(fr, 0.05, { bevel: 0.015, curveSeg: 4, bevelSeg: 2 }), cream), mt.lacquer, { pos: [x, my, bz - 0.04] }));
    g.add(K.m(new THREE.PlaneGeometry(MW + 0.02, MH + 0.02).rotateY(PI), mirrorMat(game), { pos: [x, my, bz - 0.03] }));
    // bulbs: 7 across the top, 4 down each side, sockets on the frame
    const bx = (MW + 0.1) / 2, by = (MH + 0.1) / 2;
    for (let i = 0; i < 7; i++) bulbs.push([x - bx + (i / 6) * 2 * bx, my + by, bz - 0.095]);
    for (const s of [-1, 1]) for (let i = 0; i < 4; i++) bulbs.push([x + s * bx, my + by - 0.24 - i * 0.22, bz - 0.095]);
  }
  const bm = bulbMats(game);
  const socketGeo = K.cyl(0.024, 0.024, 0.03, { seg: 8 }).clone().rotateX(-HP);
  for (const [x, y, z] of bulbs) g.add(K.m(socketGeo, mt.brass, { pos: [x, y, z + 0.035] }));
  const bulbMesh = K.m(bulbGeo(bulbs, 0.037), bm.off, { cast: false });
  bulbMesh.name = 'bulbs';
  bulbMesh.userData.noMerge = true;
  bulbMesh.userData.noOcclude = true;
  g.add(bulbMesh);
  g.add(K.m(gPlane(ga, 'lipstick', 0.34, 0.34), ga.decal, { pos: [st[1] + 0.3, my + 0.12, bz - 0.036], rot: [0, 0, 0.05] }));
  for (const [x, y, r] of [[st[0] - 0.42, my + 0.28, 0.12], [st[1] - 0.44, my - 0.3, -0.1], [st[2] + 0.4, my + 0.25, -0.14], [st[2] - 0.38, my + 0.3, 0.08]]) {
    g.add(K.m(cellPlane('polaroid', 0.15, 0.15, { face: '-z' }), am.decal, { pos: [x, y, bz - 0.037], rot: [0, 0, r] }));
  }
  const T = H + 0.001;
  // --- station 1 (Roxy): wig head with an afro, afro pick, hairspray, lipsticks, hand mirror
  {
    const x = st[0];
    const foam = '#EEE6D8';
    g.add(K.m(tc(K.cyl(0.07, 0.085, 0.02, { seg: 16 }), '#2A2231'), mt.plastic, { pos: [x - 0.25, T, -0.02] }));
    g.add(K.m(tc(K.cyl(0.045, 0.05, 0.14, { seg: 12 }), foam), mt.paint, { pos: [x - 0.25, T + 0.02, -0.02] }));
    g.add(K.m(tc(sph(0.1, 16, 12), foam), mt.paint, { pos: [x - 0.25, T + 0.24, -0.02], scale: [0.9, 1.1, 0.95] }));
    g.add(K.m(tc(sph(0.02, 8, 6), '#E8D8C8'), mt.paint, { pos: [x - 0.25, T + 0.23, -0.115] }));
    const afro = new THREE.Group();
    const rnd = (i) => hash(i * 3.7 + 1.3);
    for (let i = 0; i < 26; i++) {
      const a = rnd(i) * TAU, e = 0.1 + rnd(i + 40) * 1.1;
      const r = 0.15;
      const px = Math.cos(a) * Math.sin(e) * r, py = Math.cos(e) * r * 0.95, pz = Math.sin(a) * Math.sin(e) * r;
      if (pz < -0.06 && py < 0.08) continue; // keep the face open
      afro.add(K.m(tc(sph(0.055 + rnd(i + 9) * 0.02, 10, 8), i % 3 ? '#2A1A12' : '#3E2618'), mt.fabric, { pos: [px, py, pz + 0.02] }));
    }
    afro.position.set(x - 0.25, T + 0.27, -0.02);
    g.add(afro);
    // afro pick (black fist handle + prongs)
    g.add(K.m(tc(K.box(0.05, 0.012, 0.07, 'xs'), '#1E1530'), mt.plastic, { pos: [x + 0.05, T + 0.006, -0.14], rot: [0, 0.4, 0] }));
    for (let i = 0; i < 6; i++) g.add(K.m(tc(K.box(0.006, 0.008, 0.07, 'xs'), '#1E1530'), mt.plastic, { pos: [x + 0.05 + Math.cos(0.4) * (i - 2.5) * 0.009 + Math.sin(0.4) * -0.06, T + 0.005, -0.14 + Math.cos(0.4) * -0.06 - Math.sin(0.4) * (i - 2.5) * 0.009] }));
    // hairspray + lipsticks + hand mirror
    g.add(K.m(tc(K.cyl(0.035, 0.035, 0.2, { seg: 14 }), '#FF5FA2'), mt.lacquer, { pos: [x + 0.2, T, 0.02] }));
    g.add(K.m(tc(K.cyl(0.036, 0.03, 0.05, { seg: 14 }), '#F4F1E8'), mt.plastic, { pos: [x + 0.2, T + 0.2, 0.02] }));
    for (let i = 0; i < 3; i++) g.add(K.m(tc(K.cyl(0.011, 0.011, 0.06, { seg: 8 }), ['#E2234A', '#C8963C', '#B5472A'][i]), mt.lacquer, { pos: [x + 0.32 + i * 0.03, T, -0.08 + (i % 2) * 0.02] }));
    const hm = new THREE.Group();
    hm.position.set(x - 0.02, T + 0.012, -0.05);
    hm.rotation.y = -0.5;
    hm.add(K.m(tc(K.cyl(0.07, 0.07, 0.014, { seg: 18 }), '#FF8CC0'), mt.lacquer));
    hm.add(K.m(K.cyl(0.058, 0.058, 0.004, { seg: 18 }), mirror, { pos: [0, 0.013, 0] }));
    hm.add(K.m(tc(K.box(0.03, 0.014, 0.12, 'xs'), '#FF8CC0'), mt.lacquer, { pos: [0, 0.007, -0.12] }));
    g.add(hm);
  }
  // --- station 2 (Duke, "in the make-up chair with cucumber slices over his eyes"): plate of cucumber slices,
  //     rolled towel, open make-up kit, powder puff, coffee mug, script
  {
    const x = st[1];
    g.add(K.m(tc(K.lathe([[0, 0], [0.09, 0], [0.12, 0.018], [0.125, 0.022], [0, 0.012]], { seg: 22 }), '#F8F4EC'), mt.plastic, { pos: [x - 0.3, T, -0.06] }));
    for (let i = 0; i < 5; i++) {
      const a = i * 1.26, r = i ? 0.055 : 0;
      g.add(K.m(tc(K.cyl(0.034, 0.034, 0.008, { seg: 14 }), '#3F7A2A'), mt.plastic, { pos: [x - 0.3 + Math.cos(a) * r, T + 0.016 + i * 0.002, -0.06 + Math.sin(a) * r] }));
      g.add(K.m(tc(K.cyl(0.028, 0.028, 0.009, { seg: 14 }), '#CFE8A0'), mt.plastic, { pos: [x - 0.3 + Math.cos(a) * r, T + 0.0165 + i * 0.002, -0.06 + Math.sin(a) * r] }));
    }
    g.add(K.m(tc(K.cyl(0.06, 0.06, 0.34, { seg: 14 }), '#F4F1E8'), mt.fabric, { pos: [x + 0.02, T + 0.06, 0.1], rot: [0, 0, HP] }));
    g.add(K.m(tc(K.cyl(0.061, 0.061, 0.03, { seg: 14 }), PAL.burntOrange), mt.fabric, { pos: [x - 0.05, T + 0.06, 0.1], rot: [0, 0, HP] }));
    // make-up kit: tackle box with the lid swung open and colour pans
    const kit = new THREE.Group();
    kit.position.set(x + 0.3, T, -0.02);
    kit.rotation.y = -0.15;
    kit.add(K.m(tc(K.box(0.3, 0.1, 0.18, 'sm'), '#2F5BD3'), mt.lacquer, { pos: [0, 0.05, 0] }));
    kit.add(K.m(tc(K.box(0.3, 0.02, 0.18, 'xs'), '#2A3A8A'), mt.lacquer, { pos: [0, 0.14, 0.14], rot: [-1.2, 0, 0] }));
    for (let i = 0; i < 8; i++) kit.add(K.m(tc(K.cyl(0.018, 0.018, 0.012, { seg: 10 }), ['#E2234A', '#FFB6C8', '#E3662B', '#6B3A6E', '#7FD4FF', '#FFD23A', '#8C9A3A', '#F4F1E8'][i]), mt.plastic, { pos: [-0.105 + (i % 4) * 0.07, 0.1, -0.045 + Math.floor(i / 4) * 0.08] }));
    g.add(kit);
    g.add(K.m(tc(sph(0.045, 12, 8), '#FFD0DC'), mt.fabric, { pos: [x + 0.08, T + 0.02, -0.16], scale: [1, 0.45, 1] }));
    g.add(K.m(tc(K.lathe([[0, 0], [0.036, 0], [0.04, 0.09], [0.036, 0.09], [0.032, 0.008], [0, 0.008]], { seg: 14 }), PAL.harvestGold), mt.lacquer, { pos: [x + 0.52, T, 0.1] }));
    g.add(K.m(new THREE.TorusGeometry(0.024, 0.007, 6, 12, PI * 1.2), mt.lacquer, { pos: [x + 0.56, T + 0.05, 0.1], rot: [0, 0, -PI * 0.6] }));
    g.add(K.m(cellPlane('script', 0.2, 0.26, { flat: true }), am.paper, { pos: [x - 0.1, T + 0.004, -0.13], rot: [0, 0.25, 0] }));
  }
  // --- station 3: boa draped over the mirror corner and the counter, brush jar, tissue box, transistor radio
  {
    const x = st[2];
    const boaPts = [[x + 0.62, my + 0.5, bz - 0.1], [x + 0.72, my + 0.2, bz - 0.13], [x + 0.66, my - 0.2, bz - 0.16], [x + 0.54, T + 0.3, -0.05], [x + 0.36, T + 0.04, -0.14], [x + 0.12, T + 0.03, -0.2]];
    const curve = new THREE.CatmullRomCurve3(boaPts.map((p) => new THREE.Vector3(...p)));
    g.add(K.m(boaGeo(curve, 64), mt.fabric, { cast: false }));
    g.add(K.m(K.lathe([[0, 0], [0.04, 0], [0.042, 0.12], [0.038, 0.12], [0.036, 0.004], [0, 0.004]], { seg: 16 }), game.mats.glass('#CFE0E8', { opacity: 0.45 }), { pos: [x - 0.3, T, 0.08] }));
    for (let i = 0; i < 5; i++) g.add(K.m(tc(K.cyl(0.006, 0.004, 0.2, { seg: 6 }), ['#5A3A22', '#E23B3B', '#1E1530', '#C8963C', '#5A3A22'][i]), mt.lacquer, { pos: [x - 0.3 + (i - 2) * 0.012, T + 0.02, 0.08 + (i % 2) * 0.012], rot: [(i - 2) * 0.08, 0, (i - 2) * 0.1] }));
    g.add(K.m(tc(K.box(0.2, 0.1, 0.12, 'sm'), '#8C9A3A'), mt.lacquer, { pos: [x - 0.02, T + 0.05, -0.02], rot: [0, 0.2, 0] }));
    g.add(K.m(tc(sph(0.045, 10, 8), '#FBF8F1'), mt.fabric, { pos: [x - 0.02, T + 0.12, -0.02], scale: [1.2, 0.7, 0.9] }));
    const radio = new THREE.Group();
    radio.position.set(x + 0.3, T, 0.05);
    radio.rotation.y = -0.25;
    radio.add(K.m(tc(K.box(0.24, 0.15, 0.08, 'md'), '#E23B3B'), mt.lacquer, { pos: [0, 0.075, 0] }));
    radio.add(K.m(tc(K.box(0.13, 0.1, 0.01, 'sm'), '#F4F1E8'), mt.plastic, { pos: [-0.04, 0.075, -0.042] }));
    radio.add(K.m(K.cyl(0.02, 0.02, 0.012, { seg: 12 }), mt.chrome, { pos: [0.075, 0.1, -0.046], rot: [HP, 0, 0] }));
    radio.add(K.m(K.cyl(0.004, 0.004, 0.32, { seg: 5 }), mt.chrome, { pos: [0.09, 0.15, 0.02], rot: [0, 0, -0.35] }));
    g.add(radio);
  }
  const u = g.userData;
  u.parts = { bulbs: bulbMesh };
  u.lampMats = bm;
  u.colliders = [{ min: [-W / 2 - 0.02, 0, -D / 2 - 0.03], max: [W / 2 + 0.02, H + 0.05, D / 2] }];
  return K.finish(game, g, { ao: { res: 56 } });
}

// Feather boa: dense jittered puffs along a curve (reads fluffy, one merged geometry).
function boaGeo(curve, n = 60, r = 0.04) {
  const out = [];
  const p = new THREE.Vector3();
  for (let i = 0; i < n; i++) {
    curve.getPoint(i / (n - 1), p);
    for (let k = 0; k < 2; k++) {
      const h = hash(i * 7.3 + k * 1.9), a = hash(i * 3.1 + k * 5.7) * TAU, b = hash(i * 1.3 + k * 9.1) * PI;
      const s = r * (0.55 + h * 0.5);
      const o = r * 0.6;
      out.push(tc(new THREE.IcosahedronGeometry(s, 1).translate(p.x + Math.cos(a) * Math.sin(b) * o, p.y + Math.cos(b) * o, p.z + Math.sin(a) * Math.sin(b) * o),
        (i + k) % 3 === 0 ? '#FF8CC0' : (i + k) % 3 === 1 ? '#FF5FA2' : '#FFB0D2'));
    }
  }
  const g = mergeGeometries(out, false);
  out.forEach((x) => x.dispose());
  return g;
}

// ----------------------------------------------------------------------------------- reclining make-up chair
// Chrome hydraulic pedestal, orange vinyl seat, reclined back + headrest with a towel, chrome arms, footrest.
// Front (sitter faces) -z.
function makeupChair(game) {
  const g = K.prop('gm_makeup_chair');
  const mt = stdMats(game);
  const vinyl = K.mat(game, 'vinyl', '#ffffff', { map: K.tex.pebble('#E3662B') });
  g.add(K.m(K.lathe([[0, 0], [0.3, 0], [0.31, 0.02], [0.26, 0.05], [0.09, 0.08], [0, 0.085]], { seg: 28, round: 0.01 }), mt.chrome));
  g.add(K.m(K.cyl(0.06, 0.07, 0.34, { seg: 18, bevel: 0.01 }), mt.chrome, { pos: [0, 0.08, 0] }));
  g.add(K.m(tc(K.box(0.08, 0.03, 0.16, 'sm'), '#2A2231'), mt.plastic, { pos: [0.2, 0.05, -0.18], rot: [0.15, 0.6, 0] }));
  g.add(K.m(K.box(0.5, 0.06, 0.46, 'md'), mt.chrome, { pos: [0, 0.44, 0] }));
  g.add(K.m(K.cushion(0.56, 0.14, 0.52, { puff: 0.03 }), vinyl, { pos: [0, 0.53, -0.01] }));
  const back = new THREE.Group();
  back.position.set(0, 0.56, 0.24);
  back.rotation.x = 0.38;
  back.add(K.m(K.cushion(0.54, 0.66, 0.13, { puff: 0.03 }), vinyl, { pos: [0, 0.36, 0.02] }));
  back.add(K.m(K.box(0.5, 0.62, 0.04, 'sm'), mt.chrome, { pos: [0, 0.36, 0.1] }));
  back.add(K.m(K.cyl(0.016, 0.016, 0.16, { seg: 8 }), mt.chrome, { pos: [0, 0.68, 0.04] }));
  back.add(K.m(K.cushion(0.32, 0.14, 0.12, { puff: 0.03 }), vinyl, { pos: [0, 0.86, 0.02] }));
  back.add(K.m(tc(K.box(0.36, 0.06, 0.2, 'md'), '#F4F1E8'), mt.fabric, { pos: [0, 0.96, -0.02], rot: [0.3, 0, 0] }));
  back.add(K.m(tc(K.box(0.37, 0.018, 0.2, 'sm'), PAL.burntOrange), mt.fabric, { pos: [0, 0.99, -0.03], rot: [0.3, 0, 0] }));
  g.add(back);
  for (const s of [-1, 1]) {
    g.add(K.m(K.tube([[s * 0.29, 0.46, 0.2], [s * 0.32, 0.72, 0.16], [s * 0.32, 0.72, -0.22], [s * 0.29, 0.46, -0.24]], 0.016, { seg: 12, radial: 6 }), mt.chrome));
    g.add(K.m(K.cushion(0.09, 0.06, 0.44, { puff: 0.015 }), vinyl, { pos: [s * 0.32, 0.75, -0.03] }));
  }
  g.add(K.m(K.tube([[-0.2, 0.44, -0.24], [-0.2, 0.22, -0.46], [0.2, 0.22, -0.46], [0.2, 0.44, -0.24]], 0.014, { seg: 12, radial: 6 }), mt.chrome));
  g.add(K.m(K.box(0.44, 0.02, 0.16, 'sm'), mt.chrome, { pos: [0, 0.22, -0.46], rot: [0.3, 0, 0] }));
  // two cucumber slices dropped on the seat
  for (const [x, z, r] of [[-0.08, -0.12, 0.2], [0.1, -0.02, 0.9]]) {
    g.add(K.m(tc(K.cyl(0.034, 0.034, 0.008, { seg: 14 }), '#3F7A2A'), mt.plastic, { pos: [x, 0.61, z], rot: [0.04, r, 0.06] }));
    g.add(K.m(tc(K.cyl(0.028, 0.028, 0.009, { seg: 14 }), '#CFE8A0'), mt.plastic, { pos: [x, 0.6105, z], rot: [0.04, r, 0.06] }));
  }
  g.userData.colliders = [{ min: [-0.36, 0, -0.5], max: [0.36, 1.2, 0.5] }];
  return K.finish(game, g, { ao: { res: 40 } });
}

// ---------------------------------------------------------------------------------------- director's chair
function directorChair(game, ga, cellName, fabric) {
  const g = K.prop('gm_director_chair');
  const mt = stdMats(game);
  const W = 0.56, SH = 0.46;
  for (const s of [-1, 1]) {
    // X legs on each side
    for (const d of [-1, 1]) g.add(K.m(K.tube([[s * W / 2, 0.02, -0.22 * d], [s * W / 2, SH - 0.02, 0.2 * d]], 0.018, { seg: 2, radial: 7 }), mt.teak));
    g.add(K.m(K.box(0.04, 0.04, 0.46, 'sm'), mt.teak, { pos: [s * W / 2, SH, 0] }));
    g.add(K.m(K.box(0.04, 0.04, 0.44, 'sm'), mt.teak, { pos: [s * W / 2, 0.66, 0.0] }));
    g.add(K.m(K.box(0.04, 0.5, 0.04, 'sm'), mt.teak, { pos: [s * W / 2, 0.66, 0.22] }));
    g.add(K.m(K.box(0.04, 0.22, 0.04, 'sm'), mt.teak, { pos: [s * W / 2, SH + 0.1, -0.2] }));
  }
  g.add(K.m(tc(K.box(W - 0.02, 0.025, 0.42, 'xs'), fabric), mt.fabric, { pos: [0, SH + 0.01, 0] }));
  g.add(K.m(tc(K.box(W - 0.02, 0.2, 0.02, 'xs'), fabric), mt.fabric, { pos: [0, 0.8, 0.22] }));
  g.add(K.m(gPlane(ga, cellName, W - 0.06, 0.18, '+z'), ga.mat, { pos: [0, 0.8, 0.232] }));
  g.userData.colliders = [{ min: [-W / 2 - 0.03, 0, -0.26], max: [W / 2 + 0.03, 0.92, 0.26] }];
  return K.finish(game, g, { ao: { res: 32 } });
}

// ------------------------------------------------------------------------------------- ss_green wall TV
// A walnut built-in wall TV (the screen sits ~0.28 m off the wall so screen-spawn zombies crawl out of the
// glass): silver face, bevelled bezel, CRT (screens id ss_green), dials + speaker cloth, rabbit ears, a little
// shelf below with a TV WEEKLY and a cactus. Wall at local z = 0, front -z, origin = the screen centre.
function wallTV(game) {
  const g = K.prop('gm_wall_tv');
  const mt = stdMats(game);
  const W = 1.08, H = 0.86, D = 0.25, cx = -0.15;
  const SW = 0.62, SH = 0.47;
  g.add(K.m(K.box(W, H, D, 0.07, { uv: 1.4 }), mt.walnut, { pos: [cx, 0, -D / 2] }));
  g.add(K.m(tc(K.box(W - 0.08, H - 0.08, 0.02, 0.03), '#C9C2B2'), mt.metal, { pos: [cx, 0, -D - 0.005] }));
  const fr = K.roundRect(SW + 0.1, SH + 0.1, 0.07);
  fr.holes.push(new THREE.Path(K.roundRect(SW, SH, 0.06).getPoints(6)));
  g.add(K.m(tc(K.extrude(fr, 0.04, { bevel: 0.012, curveSeg: 4, bevelSeg: 2 }), '#2A2231'), mt.plastic, { pos: [0, 0, -D - 0.02] }));
  g.add(K.m(tc(new THREE.PlaneGeometry(SW + 0.02, SH + 0.02).rotateY(PI), '#1E1822'), mt.plastic, { pos: [0, 0, -D - 0.012] }));
  const screen = K.screen(game, SW, SH, { card: 'snow', group: 'scr_decor', dome: 0.03 });
  screen.position.set(0, 0, -D - 0.02);
  g.add(screen);
  // controls column (viewer's right = local -x after the room's rotY pi)
  const kx = cx - W / 2 + 0.13;
  for (const [y, r, c] of [[0.24, 0.05, '#2A2231'], [0.08, 0.038, '#C8963C']]) {
    g.add(K.m(tc(K.cyl(r + 0.012, r + 0.012, 0.01, { seg: 22 }), '#F4F1E8'), mt.plastic, { pos: [kx, y, -D - 0.018], rot: [HP, 0, 0] }));
    g.add(K.m(tc(K.lathe([[0, 0], [r * 0.8, 0], [r * 0.75, 0.03], [r * 0.5, 0.045], [0, 0.046]], { seg: 16, round: 0.004 }), c), mt.lacquer, { pos: [kx, y, -D - 0.02], rot: [-HP, 0, 0] }));
  }
  g.add(K.m(K.box(0.16, 0.2, 0.012, 'sm'), K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave('#8A6A4A', { pattern: 'cord' }) }), { pos: [kx, -0.18, -D - 0.018] }));
  g.add(K.m(tc(K.cyl(0.035, 0.035, 0.012, { seg: 18 }), PAL.wztvBlue), mt.lacquer, { pos: [kx, -0.33, -D - 0.02], rot: [HP, 0, 0] }));
  g.add(K.m(new THREE.TorusGeometry(0.036, 0.006, 6, 18), mt.plastic, { pos: [kx, -0.33, -D - 0.026] }));
  g.add(K.m(K.tube(K.roundRectPath(W - 0.03, H - 0.03, 0.06, 0).map(([x, , z]) => [x + cx, z, 0]), 0.008, { seg: 40, radial: 5, closed: true }), mt.chrome, { pos: [0, 0, -D - 0.003] }));
  // rabbit ears
  const top = H / 2;
  g.add(K.m(tc(K.lathe([[0, 0], [0.07, 0], [0.072, 0.015], [0.05, 0.04], [0, 0.045]], { seg: 16, round: 0.006 }), '#2A2231'), mt.plastic, { pos: [cx + 0.12, top, -D / 2] }));
  for (const s of [-1, 1]) {
    g.add(K.m(K.cyl(0.005, 0.004, 0.62, { seg: 6 }), mt.chrome, { pos: [cx + 0.12 + s * 0.012, top + 0.035, -D / 2], rot: [0.2, 0, s * 0.55] }));
    g.add(K.m(sph(0.012, 8, 6), mt.chrome, { pos: [cx + 0.12 + s * 0.33, top + 0.56, -D / 2 - 0.11] }));
  }
  // shelf below: walnut slab on brass brackets, TV WEEKLY, doily, cactus
  const sy = -H / 2 - 0.1;
  g.add(K.m(K.box(0.9, 0.035, 0.28, 0.012, { uv: 1.5 }), mt.walnut, { pos: [cx, sy, -0.14] }));
  for (const s of [-1, 1]) g.add(K.m(K.tube([[cx + s * 0.32, sy - 0.18, 0], [cx + s * 0.32, sy - 0.05, -0.12], [cx + s * 0.32, sy - 0.02, -0.22]], 0.01, { seg: 8, radial: 5 }), mt.brass));
  const mag = game.cards?.get?.('magazine_tv_weekly');
  g.add(K.m(new THREE.PlaneGeometry(0.2, 0.27).rotateX(-HP), K.mat(game, 'paint', '#ffffff', { map: mag || null }), { pos: [cx - 0.15, sy + 0.02, -0.15], rot: [0, 0.3, 0] }));
  g.add(K.m(tc(K.cyl(0.05, 0.04, 0.08, { seg: 14 }), PAL.burntOrange), mt.lacquer, { pos: [cx + 0.25, sy + 0.018, -0.14] }));
  g.add(K.m(tc(K.cyl(0.03, 0.028, 0.12, { seg: 10 }), '#5E8C3A'), mt.plastic, { pos: [cx + 0.25, sy + 0.08, -0.14] }));
  g.add(K.m(tc(sph(0.02, 8, 6), '#5E8C3A'), mt.plastic, { pos: [cx + 0.28, sy + 0.16, -0.14] }));
  g.add(K.m(tc(sph(0.012, 6, 5), '#FF5FA2'), mt.plastic, { pos: [cx + 0.25, sy + 0.22, -0.14] }));
  g.userData.colliders = [{ min: [cx - W / 2, -H / 2 - 0.15, -D - 0.06], max: [cx + W / 2, H / 2 + 0.05, 0] }];
  return K.finish(game, g, { ao: { floor: false, height: 0, res: 40 } });
}

// --------------------------------------------------------------------------------------------- coat rail
function coatRail(game) {
  const g = K.prop('gm_coat_rail');
  const mt = stdMats(game);
  const L = 1.0;
  g.add(K.m(K.box(L, 0.12, 0.03, 0.012, { uv: 1.5 }), mt.walnut, { pos: [0, 0, -0.015] }));
  const hooks = [-0.375, -0.125, 0.125, 0.375];
  for (const x of hooks) {
    g.add(K.m(K.tube([[x, 0.01, -0.03], [x, 0.0, -0.1], [x, 0.05, -0.13]], 0.009, { seg: 8, radial: 5 }), mt.brass));
    g.add(K.m(sph(0.014, 8, 6), mt.brass, { pos: [x, 0.05, -0.13] }));
  }
  // fedora on hook 1
  g.add(K.m(tc(K.lathe([[0, 0], [0.16, 0], [0.165, 0.012], [0.1, 0.02], [0.09, 0.1], [0.07, 0.13], [0, 0.12]], { seg: 20, round: 0.006 }), '#5A3A22'), mt.fabric, { pos: [hooks[0], -0.05, -0.12], rot: [-1.35, 0, 0] }));
  g.add(K.m(tc(K.cyl(0.093, 0.1, 0.03, { seg: 20 }), '#E3662B'), mt.fabric, { pos: [hooks[0], -0.06, -0.14], rot: [-1.35, 0, 0] }));
  // mustard scarf on hook 2 (two hanging ribbons)
  for (const dx of [-0.03, 0.035]) g.add(K.m(ribbon([[hooks[1] + dx, 0.03, -0.12], [hooks[1] + dx * 1.3, -0.25, -0.1], [hooks[1] + dx * 1.6, -0.55, -0.08]], 0.09, { seg: 10, up: [0, 0, 1] }), K.mat(game, 'fabric', PAL.mustard, { side: THREE.DoubleSide }), { cast: false }));
  // pink boa on hook 3
  const hx = hooks[2];
  const boaCurve = new THREE.CatmullRomCurve3([[hx - 0.1, -0.7, -0.1], [hx - 0.07, -0.3, -0.11], [hx - 0.02, 0.03, -0.13], [hx + 0.04, 0.03, -0.13], [hx + 0.09, -0.35, -0.11], [hx + 0.12, -0.62, -0.1]].map((q) => new THREE.Vector3(...q)));
  g.add(K.m(boaGeo(boaCurve, 44, 0.036), mt.fabric, { cast: false }));
  // tote bag on hook 4
  g.add(K.m(K.tube([[hooks[3] - 0.08, -0.2, -0.12], [hooks[3], 0.04, -0.13], [hooks[3] + 0.08, -0.2, -0.12]], 0.008, { seg: 10, radial: 4 }), K.mat(game, 'fabric', '#5A3A22')));
  g.add(K.m(tc(K.box(0.26, 0.28, 0.07, 'md'), '#8C9A3A'), mt.fabric, { pos: [hooks[3], -0.34, -0.1] }));
  g.add(K.m(tc(K.box(0.18, 0.08, 0.072, 'sm'), '#E8A92E'), mt.fabric, { pos: [hooks[3], -0.3, -0.105] }));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0, res: 32 } });
}

// ---------------------------------------------------------------------------------------- garment rack
// Rolling chrome rack with costumes fanned on hangers (sequin jacket, the Baron's spare cape, a cowboy shirt, a
// giant Sock Hopper costume, a white disco suit, a plaid blazer). Front -z.
function jacketShape(w, h, sleeve = true) {
  const s = new THREE.Shape();
  s.moveTo(-0.05, 0);
  s.lineTo(-w / 2, -0.06);
  if (sleeve) { s.lineTo(-w / 2 - 0.08, -h * 0.72); s.lineTo(-w / 2 + 0.03, -h * 0.74); }
  s.lineTo(-w / 2 + 0.04, -h);
  s.lineTo(w / 2 - 0.04, -h);
  if (sleeve) { s.lineTo(w / 2 - 0.03, -h * 0.74); s.lineTo(w / 2 + 0.08, -h * 0.72); }
  s.lineTo(w / 2, -0.06);
  s.lineTo(0.05, 0);
  s.lineTo(0, -0.08);
  s.closePath();
  return s;
}
function garmentRack(game) {
  const g = K.prop('gm_garment_rack');
  const mt = stdMats(game);
  const L = 1.7, H = 1.75;
  for (const s of [-1, 1]) {
    g.add(K.m(K.cyl(0.018, 0.018, H - 0.1, { seg: 10 }), mt.chrome, { pos: [s * L / 2, 0.08, 0] }));
    g.add(K.m(K.box(0.05, 0.04, 0.5, 'sm'), mt.chrome, { pos: [s * L / 2, 0.08, 0] }));
    for (const d of [-1, 1]) {
      g.add(K.m(tc(sph(0.035, 10, 8), '#2A2231'), mt.rubber, { pos: [s * L / 2, 0.035, d * 0.23] }));
    }
  }
  g.add(K.m(K.cyl(0.016, 0.016, L + 0.06, { seg: 10 }), mt.chrome, { pos: [-L / 2 - 0.03, H - 0.02, 0], rot: [0, 0, -HP] }));
  const cloth = [
    { c: '#E8A92E', w: 0.44, h: 0.66, sleeve: true, trim: '#FFE3A3' },
    { c: '#6B3A6E', w: 0.5, h: 1.15, sleeve: false, trim: '#E23B3B' },
    { c: '#E23B3B', w: 0.42, h: 0.62, sleeve: true, trim: '#F4F1E8' },
    { c: 'sock', w: 0.34, h: 1.0 },
    { c: '#F4F1E8', w: 0.44, h: 1.2, sleeve: true, trim: '#FFC23A' },
    { c: '#B5472A', w: 0.44, h: 0.7, sleeve: true, trim: '#E8A92E' },
  ];
  cloth.forEach((k, i) => {
    const x = -L / 2 + 0.2 + i * ((L - 0.4) / (cloth.length - 1));
    const grp = new THREE.Group();
    grp.position.set(x, H - 0.03, 0);
    grp.rotation.y = (i % 2 ? -1 : 1) * (0.7 + hash(i * 5.1) * 0.25);
    // hanger
    grp.add(K.m(new THREE.TorusGeometry(0.03, 0.005, 5, 10, PI * 1.4), mt.chrome, { pos: [0, 0.01, 0], rot: [0, HP, 0.3] }));
    grp.add(K.m(K.tube([[-0.2, -0.1, 0], [0, -0.03, 0], [0.2, -0.1, 0]], 0.008, { seg: 8, radial: 4 }), mt.teak));
    if (k.c === 'sock') {
      // giant striped sock costume (Sockette)
      const stripes = ['#E23B3B', '#F4E03A', '#3A58E4', '#F4F1E8'];
      for (let j = 0; j < 7; j++) grp.add(K.m(tc(K.cyl(0.16, 0.16, 0.13, { seg: 16 }), stripes[j % 4]), mt.fabric, { pos: [0, -0.12 - (j + 1) * 0.13, 0] }));
      grp.add(K.m(tc(sph(0.17, 16, 10), '#F4F1E8'), mt.fabric, { pos: [0.06, -1.07, -0.05], scale: [1.3, 0.8, 1] }));
      for (const s of [-1, 1]) {
        grp.add(K.m(tc(sph(0.05, 10, 8), '#FBF8F1'), mt.plastic, { pos: [s * 0.06, -0.3, -0.15] }));
        grp.add(K.m(tc(sph(0.025, 8, 6), '#1E1530'), mt.plastic, { pos: [s * 0.06 + 0.01, -0.31, -0.19] }));
      }
      grp.add(K.m(tc(sph(0.04, 10, 8), '#E23B3B'), mt.plastic, { pos: [0, -0.42, -0.16], scale: [1.4, 0.6, 0.6] }));
    } else {
      grp.add(K.m(tc(K.extrude(jacketShape(k.w, k.h, k.sleeve), 0.07, { bevel: 0.025, curveSeg: 2, bevelSeg: 2 }), k.c), mt.fabric, { pos: [0, -0.08, 0] }));
      // lapels / trim stripes on the front face (-z)
      for (const s of [-1, 1]) grp.add(K.m(tc(K.box(0.035, k.h * 0.78, 0.02, 'xs'), k.trim), mt.plastic, { pos: [s * 0.045, -0.12 - k.h * 0.39, -0.055], rot: [0, 0, s * 0.08] }));
      if (k.sleeve) for (let j = 0; j < 3; j++) grp.add(K.m(tc(sph(0.014, 8, 6), k.trim), mt.plastic, { pos: [0.075, -0.3 - j * 0.12, -0.06] }));
    }
    g.add(grp);
  });
  // price-tag style costume tags
  g.userData.colliders = [{ min: [-L / 2 - 0.05, 0, -0.34], max: [L / 2 + 0.05, H + 0.05, 0.34] }];
  return K.finish(game, g, { ao: { res: 40 } });
}

// ------------------------------------------------------------------------ steamer trunk + Hootie costume head
function trunkAndHead(game) {
  const g = K.prop('gm_trunk_hootie');
  const mt = stdMats(game);
  const TW = 0.86, TH = 0.46, TD = 0.5;
  g.add(K.m(tc(K.box(TW, TH, TD, 'md'), '#2A3A8A'), mt.lacquer, { pos: [0, TH / 2, 0] }));
  g.add(K.m(tc(K.box(TW + 0.01, 0.03, TD + 0.01, 'sm'), '#5A3A22'), mt.lacquer, { pos: [0, TH - 0.08, 0] }));
  for (const x of [-0.26, 0.26]) g.add(K.m(tc(K.box(0.06, TH + 0.012, TD + 0.012, 'sm'), '#6A4A30'), mt.paint, { pos: [x, TH / 2, 0] }));
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) for (const y of [0.03, TH - 0.03]) g.add(K.m(K.box(0.07, 0.07, 0.07, 'sm'), mt.brass, { pos: [x * (TW / 2 - 0.025), y, z * (TD / 2 - 0.025)] }));
  g.add(K.m(K.box(0.08, 0.07, 0.02, 'sm'), mt.brass, { pos: [0, TH - 0.12, -TD / 2 - 0.008] }));
  for (const [x, y, c, r] of [[-0.12, 0.2, '#E23B3B', 0.06], [0.12, 0.28, '#F4E03A', 0.05], [0.1, 0.12, '#52D24A', 0.045]]) {
    g.add(K.m(tc(K.cyl(r, r, 0.006, { seg: 16 }), c), mt.paint, { pos: [x, y, -TD / 2 - 0.003], rot: [HP, 0, 0] }));
  }
  // Hootie the owl costume head: round brown head, heart-shaped cream face discs, huge amber-ringed eyes, V brow,
  // little orange beak, feather tufts, a chevron bib and an orange collar ring. It sits on the trunk.
  const head = new THREE.Group();
  head.position.set(0.02, TH, 0);
  head.rotation.y = -0.35;
  const brown = '#8A5530', light = '#F6E2B8';
  head.add(K.m(tc(sph(0.3, 22, 16), brown), mt.fabric, { pos: [0, 0.3, 0], scale: [1.05, 0.95, 0.95] }));
  for (const s of [-1, 1]) {
    head.add(K.m(tc(sph(0.15, 18, 12), light), mt.fabric, { pos: [s * 0.1, 0.33, -0.17], scale: [1, 1.05, 0.5] }));
    head.add(K.m(tc(sph(0.1, 16, 12), '#FBF8F1'), mt.plastic, { pos: [s * 0.1, 0.34, -0.23] }));
    head.add(K.m(tc(sph(0.07, 14, 10), '#F2A23A'), mt.plastic, { pos: [s * 0.1, 0.34, -0.285] }));
    head.add(K.m(tc(sph(0.045, 12, 10), '#1E1530'), mt.plastic, { pos: [s * 0.1 + s * 0.008, 0.34, -0.33] }));
    head.add(K.m(tc(sph(0.015, 8, 6), '#FFFFFF'), mt.plastic, { pos: [s * 0.1 - 0.015, 0.36, -0.37] }));
    head.add(K.m(tc(K.box(0.14, 0.032, 0.05, 'sm'), '#4A2A14'), mt.fabric, { pos: [s * 0.105, 0.475, -0.26], rot: [0.25, 0, -s * 0.18] }));
    head.add(K.m(tc(K.cyl(0.0, 0.055, 0.13, { seg: 10 }), brown), mt.fabric, { pos: [s * 0.2, 0.52, -0.02], rot: [-0.2, 0, s * 0.62] }));
  }
  head.add(K.m(tc(K.cyl(0.0, 0.045, 0.1, { seg: 10 }), '#FF8A2A'), mt.plastic, { pos: [0, 0.25, -0.33], rot: [-HP - 0.5, 0, 0] }));
  for (let j = 0; j < 3; j++) head.add(K.m(tc(K.box(0.07, 0.025, 0.03, 'xs'), '#C8864A'), mt.fabric, { pos: [0, 0.14 - j * 0.035, -0.27 + j * 0.02], rot: [0, 0, j % 2 ? 0.5 : -0.5] }));
  head.add(K.m(tc(K.cyl(0.26, 0.28, 0.06, { seg: 20 }), '#E3662B'), mt.fabric, { pos: [0, 0.0, 0] }));
  head.add(K.m(tc(K.cyl(0.14, 0.14, 0.01, { seg: 18 }), '#2A1A12'), mt.fabric, { pos: [0, 0.061, 0] }));
  g.add(head);
  g.userData.colliders = [{ min: [-TW / 2, 0, -TD / 2], max: [TW / 2, TH + 0.6, TD / 2] }];
  return K.finish(game, g, { ao: { res: 40 } });
}

// ------------------------------------------------------------------------------------------- hi-fi console
function hifi(game, ga) {
  const g = K.prop('gm_hifi');
  const mt = stdMats(game);
  const W = 1.6, H = 0.62, D = 0.44;
  const grille = K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave('#7A5A3A', { pattern: 'cord' }) });
  g.add(K.m(K.box(W, H - 0.1, D, 0.03, { uv: 1.5 }), mt.walnut, { pos: [0, 0.1 + (H - 0.1) / 2, 0] }));
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) g.add(K.m(K.cyl(0.018, 0.012, 0.12, { seg: 8 }), mt.walnut, { pos: [x * (W / 2 - 0.08), 0, z * (D / 2 - 0.06)] }));
  for (const s of [-1, 1]) g.add(K.m(K.box(0.44, 0.38, 0.01, 'sm'), grille, { pos: [s * 0.54, 0.36, -D / 2 - 0.004] }));
  g.add(K.m(gPlane(ga, 'hifi', 0.56, 0.28), ga.mat, { pos: [0, 0.4, -D / 2 - 0.006] }));
  for (let i = 0; i < 3; i++) g.add(K.m(tc(K.cyl(0.02, 0.022, 0.03, { seg: 12 }), '#2A2231'), mt.plastic, { pos: [-0.16 + i * 0.16, 0.22, -D / 2 - 0.012], rot: [HP, 0, 0] }));
  // turntable on top
  const tt = new THREE.Group();
  tt.position.set(-0.2, H, 0);
  tt.add(K.m(tc(K.box(0.5, 0.06, 0.38, 'sm'), '#D8D2C2'), mt.plastic, { pos: [0, 0.03, 0] }));
  tt.add(K.m(K.cyl(0.15, 0.15, 0.02, { seg: 28 }), mt.chrome, { pos: [-0.05, 0.06, 0] }));
  tt.add(K.m(tc(K.cyl(0.148, 0.148, 0.006, { seg: 28 }), '#1E1822'), mt.plastic, { pos: [-0.05, 0.08, 0] }));
  tt.add(K.m(tc(K.cyl(0.05, 0.05, 0.007, { seg: 16 }), '#E23B3B'), mt.plastic, { pos: [-0.05, 0.081, 0] }));
  tt.add(K.m(K.tube([[0.18, 0.1, 0.12], [0.16, 0.11, -0.04], [0.05, 0.1, -0.1]], 0.007, { seg: 8, radial: 5 }), mt.chrome));
  g.add(tt);
  // record sleeves leaning against the side + a snake plant on top
  ['lp1', 'lp2', 'lp3', 'lp4'].forEach((n, i) => {
    const grp = new THREE.Group();
    grp.position.set(W / 2 + 0.06 + i * 0.012, 0, -0.05 + i * 0.01);
    grp.rotation.set(0, -HP + 0.2, -0.18 + i * 0.04);
    grp.add(K.m(tc(K.box(0.3, 0.3, 0.006, 'xs'), '#F4F1E8'), mt.paint, { pos: [0, 0.15, 0] }));
    grp.add(K.m(gPlane(ga, n, 0.29, 0.29), ga.mat, { pos: [0, 0.15, -0.0035] }));
    g.add(grp);
  });
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2], max: [W / 2 + 0.2, H + 0.12, D / 2] }];
  return K.finish(game, g, { ao: { res: 40 } });
}

// ------------------------------------------------------------------------------ payphone shelf + phone book
function phoneShelf(game, ga) {
  const g = K.prop('gm_phone_shelf');
  const mt = stdMats(game);
  g.add(K.m(tc(K.box(0.42, 0.03, 0.26, 'sm'), '#9EA4AE'), mt.metal, { pos: [0, 0, -0.13] }));
  for (const s of [-1, 1]) g.add(K.m(tc(K.box(0.02, 0.16, 0.2, 'xs'), '#9EA4AE'), mt.metal, { pos: [s * 0.2, -0.08, -0.1] }));
  // phone book hanging on a chain + lying ajar
  const book = new THREE.Group();
  book.position.set(0.05, -0.36, -0.06);
  book.rotation.set(0.05, 0, 0.08);
  book.add(K.m(tc(K.box(0.2, 0.26, 0.06, 'sm'), '#F4D23A'), mt.paint));
  book.add(K.m(gPlane(ga, 'phonebook', 0.18, 0.2), ga.mat, { pos: [0, 0, -0.0305] }));
  book.add(K.m(tc(K.box(0.19, 0.25, 0.052, 'xs'), '#FBF4E0'), mt.paint, { pos: [0.006, 0, 0.002] }));
  g.add(book);
  g.add(K.m(K.tube([[0.12, -0.02, -0.04], [0.14, -0.12, -0.05], [0.12, -0.22, -0.06]], 0.005, { seg: 8, radial: 4 }), mt.chrome));
  g.add(K.m(cellPlane('memo', 0.14, 0.14, { face: '-z' }), atlasMats(game).decal, { pos: [-0.3, 0.52, -0.005], rot: [0, 0, 0.1] }));
  g.add(K.m(gPlane(ga, 'note', 0.14, 0.14), ga.decal, { pos: [0.34, 0.66, -0.005], rot: [0, 0, -0.08] }));
  g.add(K.m(gPlane(ga, 'doodle', 0.34, 0.34), ga.decal, { pos: [-0.36, 0.1, -0.004] }));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { floor: false, height: 0, res: 28 } });
}

// ----------------------------------------------------------------------------------------------- bar stool
function barStool(game) {
  const g = K.prop('gm_stool');
  const mt = stdMats(game);
  const vinyl = K.mat(game, 'vinyl', '#ffffff', { map: K.tex.pebble('#E23B3B') });
  g.add(K.m(K.lathe([[0, 0], [0.2, 0], [0.205, 0.015], [0.14, 0.03], [0, 0.035]], { seg: 22, round: 0.006 }), mt.chrome));
  g.add(K.m(K.cyl(0.03, 0.035, 0.62, { seg: 12 }), mt.chrome, { pos: [0, 0.03, 0] }));
  g.add(K.m(new THREE.TorusGeometry(0.15, 0.012, 6, 22), mt.chrome, { pos: [0, 0.28, 0], rot: [HP, 0, 0] }));
  g.add(K.m(K.cushion(0.36, 0.1, 0.36, { puff: 0.04, r: 0.05 }), vinyl, { pos: [0, 0.7, 0] }));
  g.userData.colliders = [{ min: [-0.2, 0, -0.2], max: [0.2, 0.75, 0.2] }];
  return K.finish(game, g, { ao: { res: 28 } });
}


// Meshes added straight under the room (not through K.finish) whose material wants vertex colours get a white
// colour attribute (else the toon shader reads black where the level merge leaves a mesh alone).
function ensureColors(root) {
  root.traverse((o) => {
    if (!o.isMesh || !o.material || Array.isArray(o.material) || !o.material.vertexColors) return;
    const g = o.geometry;
    if (!g || g.attributes.color) return;
    const c = g.clone();
    c.setAttribute('color', new THREE.BufferAttribute(new Float32Array(c.attributes.position.count * 3).fill(1), 3));
    o.geometry = c;
  });
}

// ================================================================================================== build
export function build(game, area, root) {
  const kit = roomKit(game, area, root);
  const am = atlasMats(game);
  const ga = gmAtlas(game);
  const mt = stdMats(game);
  const A = (id) => ANCHORS[id];
  const bm = bulbMats(game);
  const switchable = [];                     // bulb meshes merged into one switchable draw at the end
  const add = (m) => { root.add(m); return m; };

  // ---------------------------------------------------------------------------------- west end: vending corner
  kit.place('vending_cigarette', [-6.38, 0, WALL.n + 0.24], PI, {}, { lightMul: 1.1 });
  kit.place('vending_soda', [-5.4, 0, WALL.n + 0.4], PI - 0.035, {}, { lightMul: 1.15 });
  kit.pool([-5.85, 0.02, -10.7], 1.5, '#FFD2B0', 0.2, 0.12);
  kit.place('trash_can', [-4.62, 0, WALL.n + 0.3], 0.4, { color: PAL.channelRed });
  for (const [x, z, r, c] of [[-4.95, -10.6, 0.4, '#D8342C'], [-4.35, -10.35, 1.8, '#E3662B'], [-5.6, -10.3, 2.6, '#D8342C']]) {
    add(K.m(tc(K.cyl(0.032, 0.03, 0.05, { seg: 12 }), c), mt.lacquer, { pos: [x, 0.032, z], rot: [HP, r, 0], scale: [1, 0.55, 1], cast: false }));
  }
  // lava lamp on a drum table (toy_lava_lamp) — the pink key light before power
  const lp = A('toy_lava_lamp').pos;
  kit.place('table_side_drum', [lp[0] - 0.05, 0, lp[2] - 0.05], 0.2);
  const lava = kit.place('lamp_lava', [lp[0] - 0.05, 0.53, lp[2] - 0.05], 0.3, { color: '#FF5FA2' }, { lightMul: 1.6, post: 0.7, noMerge: true });
  kit.anchor({ pos: [lp[0] + 0.1, 1.2, lp[2] + 0.5], color: '#FF5FA2', intensity: 1.4, distance: 5.5, pre: 1, post: 0.45 });
  kit.pool([lp[0], 0.02, lp[2] + 0.35], 1.9, '#FF5FA2', 0.24, 0.1);
  add(decal(am.paper, 'boa', 0.16, 0.16, [lp[0] + 0.5, 0, lp[2] + 0.55], 0.6));
  // frame above the lava lamp
  kit.place('frame_picture', [-4.1, 1.48, WALL.n], PI, { card: 'poster_boogie_down', style: 'chrome', h: 0.62 }, { colliders: false, tilt: [0, 0.02] });
  kit.place('macrame_hanger', [-6.25, 3.5, -10.65], 0.6, { drop: 1.05 }, { colliders: false });

  // ------------------------------------------------------------------------------------ west wall: coats, phone
  kit.put(coatRail(game), [WALL.w, 1.68, -10.5], -HP, { colliders: false });
  const pay = kit.place('payphone_rotary', [WALL.w, 0.95, A('toy_payphone').pos[2]], -HP, {}, { noMerge: true });
  kit.put(phoneShelf(game, ga), [WALL.w, 0.8, A('toy_payphone').pos[2]], -HP, { colliders: false });
  kit.put(barStool(game), [-6.25, 0, -7.05], 0.5);
  moonSlats(game, kit, [WALL.w, 0, -9], -HP, { w: 1.6, d: 2.5, shear: 0.2, pre: 0.42, post: 0.2 });
  kit.anchor({ pos: [-5.9, 1.7, -9.0], color: '#9FB6FF', intensity: 1.1, distance: 5, pre: 1, post: 0.35 });

  // ------------------------------------------------------------------------ south wall: five dressing-room doors
  const doors = [];
  ['baron', 'penny', 'roxy', 'skip', 'duke'].forEach((who, i) => {
    const d = kit.place('dressing_room_door', [-6.3 + i * 1.0, 0, WALL.s], 0, { who }, { scale: 0.87, lights: false });
    if (!d) return;
    doors.push(d);
    d.traverse((o) => { if (o.isMesh && o.material === K.glow(game, '#FFD08A', 2.4)) switchable.push(o); });
  });
  kit.obj('gr_dressing_doors', { doors, baron: doors[0] || null });
  {
    // additive: brightness lives in RGB (black = nothing), fading away from the door and at the sides
    const leak = K.tex.canvas('rooms.gm.leak.v2', 128, 64, (ctx, w, h) => {
      ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, h);
      for (let x = 0; x < w; x++) {
        const k = Math.sin((x / (w - 1)) * Math.PI) ** 1.5;
        const g = ctx.createLinearGradient(0, 0, 0, h);
        g.addColorStop(0, `rgba(255,255,255,${k})`); g.addColorStop(0.35, `rgba(255,255,255,${k * 0.35})`); g.addColorStop(1, 'rgba(255,255,255,0)');
        ctx.fillStyle = g; ctx.fillRect(x, 0, 1, h);
      }
    }, { repeat: false });
    const lm = game.mats.glow('#B070FF', 1.25, { map: leak, additive: true, fog: false });
    const strip = new THREE.Mesh(new THREE.PlaneGeometry(0.95, 0.55).rotateX(-HP).translate(0, 0, -0.275), lm);
    strip.position.set(-6.3, 0.011, WALL.s - 0.06);
    strip.renderOrder = 2;
    strip.userData.noMerge = true;
    add(strip);
    kit.anchor({ pos: [-6.3, 0.35, -6.6], color: '#B070FF', intensity: 0.8, distance: 2.6 });
  }
  for (const x of [-5.8, -3.0]) {
    kit.anchor({ pos: [x, 2.3, -6.7], color: '#FFD08A', intensity: 1.4, distance: 4.2, pre: 0, post: 1 });
    kit.pool([x, 0.02, -6.75], 1.5, '#FFD08A', 0, 0.12);
  }
  const clock = kit.place('clock_wall', [-4.3, 2.74, WALL.s], 0, { label: 'WZTV', size: 0.36 }, { colliders: false });
  if (clock) {
    for (const k of ['hour', 'minute', 'second']) if (clock.userData.parts[k]) clock.userData.parts[k].userData.noMerge = k === 'second';
    kit.obj('gr_clock', { group: clock, parts: clock.userData.parts });
    const sec = clock.userData.parts.second;
    kit.ticks.push((dt, t, rdt) => {
      if (!sec) return;
      const ph = (game.time?.realNow ?? 0) % 1.6;
      const s = ph < 0.8 ? 58 + Math.min(1, ph / 0.06) : 59 - Math.min(1, (ph - 0.8) / 0.08);
      sec.rotation.z = (s / 60) * TAU;
      void dt; void t; void rdt;
    });
  }
  // EXIT boxes over D2 / D3 (emergency circuit) + their red floor glow
  for (const x of [0, 12]) {
    kit.put(exitSign(game, am), [x, 2.74, WALL.s], 0, { colliders: false });
    kit.pool([x, 0.02, -6.7], 1.1, '#FF4A3A', 0.1, 0.04);
  }

  // ---------------------------------------------------------------------------- south wall: Hollywood vanity
  // 4.8 m counter centred at VX: its collider spans x 2.88..7.72. D2's east leaf swings into the room and rests
  // along this wall out to x 2.39 (hinge x 1.2, leaf 1.19 m), so the counter keeps 0.49 m to the swing and 1.54 m
  // to the D2 casing; the talent chair keeps 1.6 m to the Jump Cut tally camera (x 9.16) — everything shifted as one.
  const VX = 5.3;
  const van = kit.put(vanity(game, am, ga, { len: 4.8 }), [VX, 0, WALL.s - 0.3], 0);
  if (van?.userData.parts.bulbs) switchable.push(van.userData.parts.bulbs);
  kit.place('rug_shag_oval', [VX, 0, -7.55], 0, { len: 4.1, w: 1.5, rings: ['#E8A92E', '#E3662B', '#B5472A', '#D9A520'] });
  const chair = kit.put(makeupChair(game), [VX, 0, -7.25], PI + 0.12);
  kit.obj('gr_makeup_chair', { group: chair });
  kit.put(directorChair(game, ga, 'chair_roxy', '#6B3A6E'), [VX - 1.68, 0, -7.2], PI - 0.35);
  kit.put(directorChair(game, ga, 'chair_talent', '#2F5BD3'), [VX + 1.75, 0, -7.35], PI + 0.5);
  add(decal(am.paper, 'cucumber', 0.07, 0.07, [VX - 0.35, 0, -7.95], 0.2));
  add(decal(am.paper, 'cucumber', 0.07, 0.07, [VX + 0.4, 0, -8.1], 1.4));
  add(decal(am.paper, 'towel', 0.4, 0.2, [VX + 0.9, 0, -7.9], 0.5));
  add(decal(am.paper, 'fan', 0.24, 0.24, [VX - 2.3, 0, -8.0], -0.4));
  const mk = new THREE.Mesh(cellPlane('makeup', 1.7, 0.425), am.decal);
  mk.position.set(VX, 2.62, WALL.s - 0.045);
  mk.rotation.y = PI;
  add(mk);
  add(K.m(tc(K.box(1.84, 0.52, 0.03, 'sm'), '#4A2E22'), mt.lacquer, { pos: [VX, 2.62, WALL.s - 0.012] }));
  kit.anchor({ pos: [VX - 1.4, 2.0, -7.0], color: '#FFD08A', intensity: 2.3, distance: 5.5, pre: 0, post: 1 });
  kit.anchor({ pos: [VX + 1.4, 2.0, -7.0], color: '#FFD08A', intensity: 2.3, distance: 5.5, pre: 0, post: 1 });
  kit.pool([VX, 0.02, -7.2], 2.9, '#FFD08A', 0, 0.2);

  // ------------------------------------------------------------------------- north wall: ss_green wall TV
  const tv = kit.put(wallTV(game), [-0.8, 1.2, WALL.n], PI, { screenGroup: 'scr_decor', screenIds: ['ss_green'] });
  if (tv) kit.obj('ss_green', { group: tv, screen: tv.userData.screens[0]?.mesh || null });
  kit.pool([-0.8, 0.02, -10.9], 1.2, '#9FDCFF', 0.07, 0.1);

  // ---------------------------------------------------------------- north wall: costumes beside D4, QUIET PLEASE
  kit.put(garmentRack(game), [6.8, 0, WALL.n + 0.42], PI + 0.03);
  kit.put(trunkAndHead(game), [6.3, 0, -10.55], PI - 0.45);
  const quiet = new THREE.Mesh(cellPlane('quiet', 1.2, 0.3), am.decal);
  quiet.position.set(6.8, 2.62, WALL.n + 0.04);
  add(quiet);
  add(K.m(tc(K.box(1.28, 0.36, 0.03, 'sm'), '#2A2231'), mt.lacquer, { pos: [6.8, 2.62, WALL.n + 0.004] }));
  add(decal(am.paper, 'script2', 0.2, 0.26, [6.2, 0, -10.2], 0.7));
  add(decal(am.paper, 'sheet', 0.2, 0.26, [7.9, 0, -9.7], -0.4));

  // -------------------------------------------------------------- east of the Jump Cut set: cooler, poster, hi-fi
  kit.place('water_cooler', [11.72, 0, WALL.n + 0.2], PI);
  kit.place('frame_picture', [11.72, 1.62, WALL.n], PI, { card: 'poster_hootie', style: 'walnut', h: 0.7 }, { colliders: false, tilt: [0, -0.02] });
  add(K.m(tc(new THREE.CylinderGeometry(0.028, 0.02, 0.07, 10, 1, true), '#F4F1E8'), mt.plastic, { pos: [11.4, 0.02, -11.2], rot: [HP, 0, 0.6] }));
  kit.put(hifi(game, ga), [13.75, 0, WALL.n + 0.25], PI);
  kit.place('plant_snake', [13.1, 0.62, WALL.n + 0.25], 0.3, { seed: 7 }, { colliders: false });
  kit.place('macrame_hanger', [12.55, 3.5, -11.15], 1.2, { drop: 0.95 }, { colliders: false });
  // framed WZTV test card above the Telly home (the mascot's own portrait)
  kit.place('frame_picture', [WALL.e, 2.08, -9.0], HP, { card: 'test_card', style: 'gold', h: 0.62 }, { colliders: false });

  // ------------------------------------------------------------------------ south wall east of D3: call board
  kit.place('cork_board', [15.05, 1.1, WALL.s], 0, { w: 1.2, h: 0.8, seed: 11 }, { colliders: false });
  const cb = new THREE.Mesh(cellPlane('callboard', 1.2, 0.3), am.decal);
  cb.position.set(15.05, 2.12, WALL.s - 0.02);
  cb.rotation.y = PI;
  add(cb);
  kit.place('ash_urn', [13.8, 0, -6.48], 0.3, { color: PAL.avocado });
  kit.place('plant_fern', [16.3, 0, -6.62], 0.9, { seed: 6 });

  // ------------------------------------------------------------------------------------- floor clutter
  for (const [name, x, z, r, s] of [
    ['script', -3.9, -8.3, 0.5, 0.24], ['pledge', 0.4, -9.9, -0.6, 0.18], ['sheet2', 1.6, -9.0, 1.1, 0.24],
    ['cup', 2.3, -10.8, 0, 0.1], ['memo', -2.2, -7.2, 0.9, 0.14], ['ticket', 13.1, -7.0, -0.3, 0.14],
  ]) add(decal(am.paper, name, s, s * (name.startsWith('script') || name.startsWith('sheet') ? 1.3 : 1), [x, 0, z], r));
  // make-up station cable (moves with the vanity; its wall end stays 0.45 m clear of D2's swing)
  const cable = K.m(K.tube([[VX - 1.2, 0.02, -6.6], [VX - 1.05, 0.02, -7.4], [VX - 2.05, 0.02, -8.15], [VX - 2.5, 0.03, -7.3], [VX - 2.46, 0.1, -6.35]], 0.012, { seg: 20, radial: 5 }), K.mat(game, 'rubber', '#2A2230'));
  add(cable);

  // --------------------------------------------------------------------------------- switchable bulbs (power)
  const bulbMesh = kit.mergeInto(switchable, bm.off, 'green_room_bulbs');
  const vanObj = kit.obj('gr_vanity', {
    group: van, parts: { bulbs: bulbMesh }, lit: false,
    setBulbs(on) { this.lit = !!on; if (bulbMesh) bulbMesh.material = on ? bm.on : bm.off; },
  });
  kit.onPower([VX, 1.6, -6.4], (on) => vanObj.setBulbs(on));
  kit.hook(bulbMesh || van?.userData.parts.bulbs);

  // ------------------------------------------------------------------------------------------------ toys
  if (lava) {
    const parts = lava.userData.parts;
    const blobs = parts.blobs ? parts.blobs.children.slice() : [];
    const base = blobs.map((b) => ({ y: b.position.y, s: b.scale.clone() }));
    const st = { fast: 0, phase: 0 };
    const play = () => { st.fast = 10; kit.sound('toy_lava', lp); };
    kit.toy('toy_lava_lamp', lp, play, 1.5);
    kit.obj('toy_lava_lamp', { group: lava, parts, play });
    kit.ticks.push((dt, t, rdt) => {
      const k = st.fast > 0 ? 4 : 1;
      if (st.fast > 0) st.fast = Math.max(0, st.fast - rdt);
      st.phase += rdt * 0.35 * k;
      blobs.forEach((b, i) => {
        const ph = st.phase * (1 + i * 0.37) + i * 1.7;
        const u = 0.5 + 0.5 * Math.sin(ph);
        b.position.y = i === 0 ? base[i].y + Math.sin(ph * 0.5) * 0.008 : 0.05 + u * 0.24;
        const wob = 1 + Math.sin(ph * 2.3) * 0.12;
        b.scale.set(base[i].s.x * wob, base[i].s.y / wob, base[i].s.z * wob);
      });
      void dt; void t;
    });
  }
  if (pay) {
    const p0 = pay.position.clone(), r0 = pay.rotation.clone();
    const st = { t: -1 };
    const play = () => { st.t = 0; kit.sound('toy_payphone', A('toy_payphone').pos); };
    kit.toy('toy_payphone', A('toy_payphone').pos, play, 1.5);
    kit.obj('toy_payphone', { group: pay, play });
    kit.ticks.push((dt, t, rdt) => {
      if (st.t < 0) return;
      st.t += rdt;
      const k = st.t;
      // busy tone: three rattles (0.25 s on / 0.25 s off), fading
      const on = k < 1.5 && (k % 0.5) < 0.25;
      const a = on ? Math.sin(k * 90) * 0.035 * (1 - k / 1.6) : 0;
      pay.rotation.set(r0.x + a, r0.y, r0.z + a * 0.6);
      pay.position.set(p0.x + (on ? 0.004 : 0), p0.y + (on ? Math.abs(Math.sin(k * 45)) * 0.006 : 0), p0.z);
      if (k > 1.6) { st.t = -1; pay.rotation.copy(r0); pay.position.copy(p0); }
      void dt; void t;
    });
  }
  ensureColors(root);
  return kit;
}
