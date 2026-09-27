// Third-person over-the-shoulder camera, PvZ Garden Warfare style (ARCHITECTURE §9, GDD §3.7/§16).
// Pivot at head height; offset 0.75 m right, 0.35 m up, 3.4 m back, FOV 70. ADS (hold RMB): 1.6 m back,
// 0.55 m right, FOV 52 in 0.12 s. C swaps the shoulder (critically damped, no snap). +4 deg FOV while sprinting.
// The crosshair is the exact screen center (the camera looks along the player's yaw/pitch; the hero sits left of
// center).
// Collision: a 0.25 m sphere is swept from the pivot along the boom against ARCHITECTURE only (collider tags in
// ARCH: walls, glass, doors, boarded windows, the ground, platforms, fence, tower lattice). Props (desks, chairs,
// pedestal cameras, globes, machines...) never pull the camera: their small boxes made the probe hit and miss on
// alternate frames, and the snap-in / ease-out sawtooth read as a rapid left/right shake. The collision limit snaps
// in at once (never see through a wall), holds for HOLD s after the last pull-in, then eases back out
// (EASE_OUT time constant, at most MAX_OUT m/s). The limit is separate from the boom length, so ADS in/out
// stays instant. CEILINGS count as walls (ceilingClamp): the boom stops CEIL_GAP under the ceiling of the room it
// is in (pivot and boom end), so aiming down in the 3.5-4 m rooms keeps the camera inside instead of on the roof
// (the gravel roof used to fill the whole screen, hiding the hero).
// OCCLUSION (cam.occ, see materials.js / render.js): whatever stands between the camera and the hero dither-fades
// (screen door) instead of hiding the hero. Walls never do: they pull the camera in (above), so they are never in
// front of the hero. Two parts, both limited to what is closer to the camera than the hero and above its feet:
//   - a see-through window: an ellipse around the hero's projected silhouette (feet to head, shoulder width),
//     always on while this camera drives the view (nothing else is ever in front of the hero there);
//   - whole-object fades: collision boxes the camera ignores (props, machines, rails, the tower lattice; never
//     walls / glass / doors / windows / floors) crossed by the lines from the lens to the hero (head, chest, hips,
//     shoulders) or by the view rays right in front of the lens (< OCC_NEAR: the lobby letter board when the
//     camera backs against the south wall), up to OCC_BOXES at a time, each ramping in over OCC_IN s and out over
//     OCC_OUT s after OCC_HOLD s without a hit (no flicker when a line grazes an edge).
//   Actors never fade (zombies, the boss: mats.noOcclusion on spawn), nor does the hero (hero-fade materials).
//   Nothing inside the walls / doors / windows / glass / fences / platforms nearest the camera (occ.walls, up to 4)
//   ever fades: the window's soft rim can reach a wall beside a hero standing close to the camera, and a prop box
//   can touch a wall.
//   occ = { amt, cx, cy, rx, ry (NDC ellipse), zFull, zSoft (view depths), feetY, boxes: [{ min, max, level }], n,
//           walls: [{ min, max, level: 1 }], nw },
//   occValid(camera) = computed for that camera exactly as it is now (render.js skips it otherwise).
// API: shake(amount 0..1 trauma, duration=0.4; >= 0.18 also rumbles the gamepad via input.shakeRumble), kick(pitch, yaw=0) (recoil: shifts the aim, recovers at
// 8 deg/s, plus a quick visual punch), heroDistance (m, for the hero fade), enabled (debug cameras turn it off),
// fovBase (options, 60..90), side (+1 right shoulder / -1 left), occ, occValid(camera), occlusion (bool, default
// true: false turns the fade off), ceilingClamp (bool, default true).

import * as THREE from 'three';
import { Spring } from '../core/rig.js';
import { noise1 } from '../core/rng.js';

const HIP = { right: 0.75, up: 0.35, back: 3.4, fov: 70 };
const ADS = { right: 0.55, up: 0.3, back: 1.6, fov: 52 };
const ADS_TIME = 0.12;
const SPRINT_FOV = 4;
const PROBE_R = 0.25;
const MIN_DIST = 0.15;
const SKIN = 0.02;
const MAX_BOOM = 4;     // collision limit when nothing is in the way (longer than any boom)
const HOLD = 0.25;      // s the camera stays pulled in after the last pull-in (hysteresis)
const EASE_OUT = 0.25;  // s time constant of the ease back out
const MAX_OUT = 1.2;    // m/s cap on the ease-out (a long recovery glides instead of pumping, ~2 cm per frame)
const SIDE_TIME = 0.12; // s shoulder swap smoothing (critically damped)
const RECOVER = THREE.MathUtils.degToRad(8);
const CEIL_GAP = 0.3;   // m the camera stays under a ceiling
// Collider tags that block the camera (collision.js tag names; walls from shell.js, platforms/stairs, doors,
// boarded window openings). Every other tag (prop, machine, telly, rail, ...) is ignored by the camera.
const ARCH = new Set(['wall', 'glass', 'door', 'window', 'floor', 'platform', 'fence', 'lattice']);

// occlusion (see the header)
const OCC_MAX = 1;          // strength of the see-through window (1: clear over the hero, dithered towards its rim)
const OCC_BOX_MAX = 0.9;    // strongest whole-object fade: fraction of pixels dropped (14 of every 16 pixels)
const OCC_MARGIN = 0.45;    // m closer than the hero's nearest point (head top, back...) where the fade is full ...
const OCC_SOFT = 0.3;       // ... easing out over this range (nothing within 0.15 m of the hero fades: what it carries)
const OCC_FEET = 0.08;      // m above the feet: floors, rugs and decals below never fade
const OCC_W = 0.45;         // m half width of the hero silhouette (with the gun)
const OCC_ELL = 1.3;        // ellipse radii / projected half extents (the fade is full inside ~0.6 of the radii)
const OCC_NEAR = 0.75;      // m: a box the view rays cross this close to the lens fades whole
const OCC_IN = 0.12;        // s fade in (a box, the whole effect)
const OCC_OUT = 0.3;        // s fade out
const OCC_HOLD = 0.2;       // s a box keeps fading after its last hit
const OCC_BOXES = 4;        // boxes faded at once (materials.js uOccBox0/1)
const OCC_PAD = 0.05;       // m the faded region extends past the collision box (plus a 0.15 m soft edge)
const OCC_SKIP = new Set(['wall', 'glass', 'door', 'window', 'floor', 'platform']); // never faded whole
const OCC_KEEP = new Set(['wall', 'glass', 'door', 'window', 'platform', 'fence']);  // protected (floors: feetY)
const OCC_WALLS = 4;        // protected boxes (materials.js uOccWall0/1)
const OCC_RAYS = [[0, 0], [0.6, 0.55], [-0.6, 0.55], [0.6, -0.55], [-0.6, -0.55], [0, -0.7]]; // NDC view rays

const _pivot = new THREE.Vector3();
const _offset = new THREE.Vector3();
const _dir = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _e = new THREE.Euler(0, 0, 0, 'YXZ');
const _fwd = new THREE.Vector3();
const _right = new THREE.Vector3();
const _v = new THREE.Vector3();
const _pts = Array.from({ length: 5 }, () => new THREE.Vector3());
const _rays = OCC_RAYS.map(() => new THREE.Vector3());

const byLevel = (a, b) => b.level - a.level;

// Entry distance of the segment o + d * t, t in [0, len] (d unit), into box b, or -1 when it misses. 0 when o is
// inside the box.
function segBox(b, o, d, len) {
  let t0 = 0, t1 = len;
  for (let a = 0; a < 3; a++) {
    const oa = a === 0 ? o.x : a === 1 ? o.y : o.z;
    const da = a === 0 ? d.x : a === 1 ? d.y : d.z;
    const lo = a === 0 ? b.minX : a === 1 ? b.minY : b.minZ;
    const hi = a === 0 ? b.maxX : a === 1 ? b.maxY : b.maxZ;
    if (Math.abs(da) < 1e-9) { if (oa < lo || oa > hi) return -1; continue; }
    let ta = (lo - oa) / da, tb = (hi - oa) / da;
    if (ta > tb) { const t = ta; ta = tb; tb = t; }
    if (ta > t0) t0 = ta;
    if (tb < t1) t1 = tb;
    if (t0 > t1) return -1;
  }
  return t0;
}

// Distance along the unit dir d from o at which a sphere of radius r first touches an enabled, camera-blocking
// architecture box (box expanded by r: square corners, slightly conservative), or Infinity within max.
// Boxes already containing o are skipped (the probe may leave a volume), like collision.raycast.
// ~285 boxes in the whole station: a flat loop with an AABB reject is cheaper than the hash here.
function sphereCast(boxes, o, d, max, r) {
  const ex = o.x + d.x * max, ey = o.y + d.y * max, ez = o.z + d.z * max;
  const sx0 = Math.min(o.x, ex) - r, sx1 = Math.max(o.x, ex) + r;
  const sy0 = Math.min(o.y, ey) - r, sy1 = Math.max(o.y, ey) + r;
  const sz0 = Math.min(o.z, ez) - r, sz1 = Math.max(o.z, ez) + r;
  let best = max;
  let hit = false;
  for (let i = 0; i < boxes.length; i++) {
    const b = boxes[i];
    if (!b.enabled || !b.camera || b.ramp || !ARCH.has(b.tag)) continue;
    if (b.maxX < sx0 || b.minX > sx1 || b.maxY < sy0 || b.minY > sy1 || b.maxZ < sz0 || b.minZ > sz1) continue;
    const x0 = b.minX - r, x1 = b.maxX + r, y0 = b.minY - r, y1 = b.maxY + r, z0 = b.minZ - r, z1 = b.maxZ + r;
    if (o.x > x0 && o.x < x1 && o.y > y0 && o.y < y1 && o.z > z0 && o.z < z1) continue;
    let t0 = 0, t1 = best;
    let ok = true;
    for (let a = 0; a < 3 && ok; a++) {
      const oa = a === 0 ? o.x : a === 1 ? o.y : o.z;
      const da = a === 0 ? d.x : a === 1 ? d.y : d.z;
      const lo = a === 0 ? x0 : a === 1 ? y0 : z0;
      const hi = a === 0 ? x1 : a === 1 ? y1 : z1;
      if (Math.abs(da) < 1e-9) { ok = oa >= lo && oa <= hi; continue; }
      let ta = (lo - oa) / da, tb = (hi - oa) / da;
      if (ta > tb) { const t = ta; ta = tb; tb = t; }
      if (ta > t0) t0 = ta;
      if (tb < t1) t1 = tb;
      ok = t0 <= t1;
    }
    if (ok && t0 < best) { best = t0; hit = true; }
  }
  return hit ? best : Infinity;
}

export class ThirdPersonCamera {
  constructor(game) {
    this.game = game;
    this.camera = game.camera;
    this.enabled = true;
    this.side = 1;
    this.fovBase = HIP.fov;
    this.heroDistance = 3;
    this._side = 1;
    this._sideVel = 0;
    this._ads = 0;
    this._sprintFov = 0;
    this._dist = HIP.back;
    this._clip = MAX_BOOM;  // smoothed collision limit (m along the boom)
    this._holdT = 0;
    this._pivotY = null;
    this._trauma = 0;
    this._traumaDecay = 2.5;
    this._kickP = 0;
    this._kickY = 0;
    this._punch = new Spring(300, 20);
    this._t = 0;
    this.ceilingClamp = true;
    this.occlusion = true;
    this.occ = {
      amt: 0, cx: 0, cy: 0, rx: 0, ry: 0, zFull: 0, zSoft: OCC_SOFT, feetY: 0, n: 0,
      boxes: Array.from({ length: OCC_BOXES }, () => ({ min: new THREE.Vector3(), max: new THREE.Vector3(), level: 0 })),
      walls: Array.from({ length: OCC_WALLS }, () => ({ min: new THREE.Vector3(), max: new THREE.Vector3(), level: 1, d: 0 })),
      nw: 0,
      cam: new Float64Array(9), // camera position, quaternion, fov, aspect it was computed for (occValid)
    };
    this._occState = new Map(); // collision box -> { level, hold }
    this._occList = [];
    // actors never fade (materials.js noOcclusion): every spawned zombie, the boss when its fight starts
    const ev = game.events, M = () => game.mats;
    if (ev) {
      ev.on('zombie:spawn', (e) => { if (e && e.z && M()) M().noOcclusion(e.z.group); });
      ev.on('machine:boss_start', () => { if (game.boss && M()) M().noOcclusion(game.boss.root); });
    }
  }

  // cam.occ was computed for `camera` exactly as it is now (render.js calls it before the main render).
  occValid(camera) {
    const s = this.occ.cam, p = camera.position, q = camera.quaternion;
    return s[0] === p.x && s[1] === p.y && s[2] === p.z && s[3] === q.x && s[4] === q.y && s[5] === q.z && s[6] === q.w
      && s[7] === camera.fov && s[8] === camera.aspect;
  }

  reset() {
    this.side = 1;
    this._side = 1;
    this._sideVel = 0;
    this._ads = 0;
    this._trauma = 0;
    this._kickP = this._kickY = 0;
    this._punch.reset();
    this._pivotY = null;
    this._dist = HIP.back;
    this._clip = MAX_BOOM;
    this._holdT = 0;
    this._occState.clear();
    this.occ.n = 0;
    this.occ.amt = 0;
  }

  shake(amount = 0.3, duration = 0.4) {
    this._trauma = Math.min(1, this._trauma + amount);
    this._traumaDecay = 1 / Math.max(0.05, duration);
    this.game.input?.shakeRumble?.(amount, duration); // big shakes rumble the Xbox pad (input.js)
  }

  kick(pitch = 0.02, yaw = 0) {
    this._kickP += pitch;
    this._kickY += yaw;
    this._punch.kick(pitch * 30);
  }

  update(dt) {
    const g = this.game;
    const p = g.player;
    this._t += dt;
    if (g.input.pressed('shoulder')) this.side = -this.side;
    if (!this.enabled || !p) {
      this.occ.amt = 0;
      return;
    }

    // Blend factors. Shoulder: critically damped spring (smooth start and stop, no overshoot).
    {
      const w = 2 / SIDE_TIME, x = w * dt;
      const e = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x);
      const change = this._side - this.side;
      const tmp = (this._sideVel + w * change) * dt;
      this._sideVel = (this._sideVel - w * tmp) * e;
      this._side = this.side + (change + tmp) * e;
    }
    const adsRate = dt / ADS_TIME * (p.mods ? p.mods.adsSpeed : 1);
    this._ads = THREE.MathUtils.clamp(this._ads + (p.ads ? adsRate : -adsRate), 0, 1);
    const a = this._ads * this._ads * (3 - 2 * this._ads);
    this._sprintFov += ((p.sprinting ? SPRINT_FOV : 0) - this._sprintFov) * (1 - Math.exp(-dt * 6));

    // Recoil recovery (aim-affecting) and the visual punch.
    this._kickP = Math.sign(this._kickP) * Math.max(0, Math.abs(this._kickP) - RECOVER * dt);
    this._kickY = Math.sign(this._kickY) * Math.max(0, Math.abs(this._kickY) - RECOVER * dt);
    const punch = this._punch.update(dt, 0);

    // Pivot at head height; vertical steps are smoothed, horizontal follow is exact (responsive aim).
    const headH = p.rig ? p.rig.dims.height - p.rig.dims.headH * 0.55 : 1.5;
    const ty = p.pos.y + headH;
    this._pivotY = this._pivotY === null ? ty : this._pivotY + (ty - this._pivotY) * (1 - Math.exp(-dt * 14));
    _pivot.set(p.pos.x, this._pivotY, p.pos.z);

    const yaw = p.yaw + this._kickY;
    const pitch = THREE.MathUtils.clamp(p.pitch + this._kickP, -1.35, 1.25);
    _q.setFromEuler(_e.set(pitch + punch * 0.02, yaw, 0));

    const right = THREE.MathUtils.lerp(HIP.right, ADS.right, a) * this._side;
    const up = THREE.MathUtils.lerp(HIP.up, ADS.up, a);
    const back = THREE.MathUtils.lerp(HIP.back, ADS.back, a);
    _offset.set(right, up, back).applyQuaternion(_q);
    const want = _offset.length();
    _dir.copy(_offset).divideScalar(want);

    // Collision: sweep a 0.25 m sphere from the pivot along the boom against architecture only. The limit
    // snaps in, holds HOLD s after the last pull-in, then eases out; the boom itself (ADS blend) stays exact.
    const col = g.level && g.level.col;
    let hit = col ? sphereCast(col.boxes, _pivot, _dir, want, PROBE_R) : Infinity;
    if (this.ceilingClamp && _dir.y > 1e-3) hit = Math.min(hit, this._ceiling(g, want));
    const free = hit === Infinity ? MAX_BOOM : Math.max(MIN_DIST, hit - SKIN);
    if (free < this._clip - 1e-3) {
      this._clip = free;
      this._holdT = HOLD;
    } else if (this._holdT > 0) {
      this._holdT -= dt;
    } else {
      this._clip += Math.min((free - this._clip) * (1 - Math.exp(-dt / EASE_OUT)), MAX_OUT * dt);
    }
    this._dist = Math.min(want, this._clip);

    const cam = this.camera;
    cam.position.copy(_pivot).addScaledVector(_dir, this._dist);
    cam.quaternion.copy(_q);

    // Trauma shake (squared falloff, smooth noise).
    this._trauma = Math.max(0, this._trauma - this._traumaDecay * dt);
    const s = this._trauma * this._trauma;
    if (s > 0) {
      const t = this._t * 22;
      cam.position.x += noise1(t) * 0.12 * s;
      cam.position.y += noise1(t + 31.7) * 0.1 * s;
      _e.set(noise1(t + 71.3) * 0.03 * s, noise1(t + 11.1) * 0.03 * s, noise1(t + 53.9) * 0.05 * s);
      cam.quaternion.multiply(_q.setFromEuler(_e));
    }

    const fov = THREE.MathUtils.lerp(this.fovBase, ADS.fov + (this.fovBase - HIP.fov) * 0.5, a) + this._sprintFov;
    if (Math.abs(cam.fov - fov) > 1e-3) {
      cam.fov = fov;
      cam.updateProjectionMatrix();
    }
    cam.updateMatrixWorld();
    this.heroDistance = cam.position.distanceTo(_pivot);
    this._occlusion(dt, p, cam, col);
  }

  // Boom length at which the camera reaches CEIL_GAP under the lowest ceiling of the rooms at the pivot and at the
  // boom end (Infinity: no ceiling there, e.g. the yard). _pivot / _dir are this frame's.
  _ceiling(g, want) {
    const lv = g.level;
    if (!lv || !lv.areas || !lv.areaAt) return Infinity;
    let ceil = Infinity;
    for (let i = 0; i < 2; i++) {
      const t = i ? want : 0;
      const id = lv.areaAt(_pivot.x + _dir.x * t, _pivot.z + _dir.z * t);
      const a = id ? lv.areas[id] : null;
      if (a && a.ceilY != null && a.ceilY < ceil) ceil = a.ceilY;
    }
    // no ceiling above the hero (or the hero above it: debug teleports onto the roof)
    if (ceil === Infinity || _pivot.y > ceil - CEIL_GAP) return Infinity;
    return (ceil - CEIL_GAP - _pivot.y) / _dir.y + SKIN;
  }

  // Keeps the OCC_WALLS protected boxes nearest the lens in occ.walls (insertion by distance).
  _occWall(o, b, d) {
    const W = o.walls;
    let i = o.nw < OCC_WALLS ? o.nw++ : OCC_WALLS;
    if (i === OCC_WALLS) { if (d >= W[OCC_WALLS - 1].d) return; i = OCC_WALLS - 1; }
    const slot = W[i];
    for (; i > 0 && W[i - 1].d > d; i--) W[i] = W[i - 1];
    W[i] = slot;
    slot.d = d;
    slot.min.set(b.minX - OCC_PAD, b.minY - OCC_PAD, b.minZ - OCC_PAD);
    slot.max.set(b.maxX + OCC_PAD, b.maxY + OCC_PAD, b.maxZ + OCC_PAD);
  }

  // cam.occ for this frame (see the header). cam's matrices are up to date.
  _occlusion(dt, p, cam, col) {
    const o = this.occ;
    const on = this.occlusion !== false;
    o.amt = on ? Math.min(OCC_MAX, o.amt + dt * OCC_MAX / OCC_IN) : Math.max(0, o.amt - dt * OCC_MAX / OCC_OUT);
    const s = o.cam;
    s[0] = cam.position.x; s[1] = cam.position.y; s[2] = cam.position.z;
    s[3] = cam.quaternion.x; s[4] = cam.quaternion.y; s[5] = cam.quaternion.z; s[6] = cam.quaternion.w;
    s[7] = cam.fov; s[8] = cam.aspect;
    if (o.amt <= 0) { o.n = 0; o.nw = 0; this._occState.clear(); return; }

    const C = cam.position;
    cam.getWorldDirection(_fwd);
    _right.setFromMatrixColumn(cam.matrixWorld, 0).normalize();
    const feet = p.pos.y;
    const h = p.rig && p.rig.dims ? p.rig.dims.height : p.height || 1.75;
    o.feetY = feet + OCC_FEET;
    // hero samples: head (pivot), chest, hips, both shoulders
    _pts[0].copy(_pivot);
    _pts[1].set(p.pos.x, feet + h * 0.58, p.pos.z);
    _pts[2].set(p.pos.x, feet + h * 0.32, p.pos.z);
    _pts[3].copy(_pts[1]).addScaledVector(_right, OCC_W * 0.55);
    _pts[4].copy(_pts[1]).addScaledVector(_right, -OCC_W * 0.55);
    // depth of the hero's nearest point: the samples, the head top and the back (what it carries: the reel...)
    let heroZ = Infinity;
    for (let i = 0; i < _pts.length; i++) heroZ = Math.min(heroZ, _v.copy(_pts[i]).sub(C).dot(_fwd));
    heroZ = Math.min(heroZ, _v.set(p.pos.x, feet + h + 0.05, p.pos.z).sub(C).dot(_fwd));
    _v.set(C.x - p.pos.x, 0, C.z - p.pos.z);
    if (_v.lengthSq() > 1e-6) {
      _v.normalize().multiplyScalar(0.25).add(_pts[1]);
      heroZ = Math.min(heroZ, _v.sub(C).dot(_fwd));
    }
    o.zFull = heroZ - OCC_MARGIN;
    o.zSoft = OCC_SOFT;

    // see-through window: the hero's feet-to-head, shoulder-wide quad projected to NDC
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity, ok = true;
    for (let i = 0; i < 4 && ok; i++) {
      _v.set(p.pos.x, i < 2 ? feet : feet + h + 0.08, p.pos.z).addScaledVector(_right, i & 1 ? OCC_W : -OCC_W);
      const vz = (_v.x - C.x) * _fwd.x + (_v.y - C.y) * _fwd.y + (_v.z - C.z) * _fwd.z;
      if (vz < cam.near * 2) { ok = false; break; }
      _v.project(cam);
      if (_v.x < x0) x0 = _v.x; if (_v.x > x1) x1 = _v.x;
      if (_v.y < y0) y0 = _v.y; if (_v.y > y1) y1 = _v.y;
    }
    if (ok) {
      o.cx = (x0 + x1) / 2; o.cy = (y0 + y1) / 2;
      o.rx = (x1 - x0) / 2 * OCC_ELL; o.ry = (y1 - y0) / 2 * OCC_ELL;
    } else {
      o.rx = o.ry = 0;
    }

    // whole-object fades
    const st = this._occState;
    for (const e of st.values()) e.hit = false;
    const boxes = col && col.boxes;
    o.nw = 0;
    if (boxes) {
      // view rays near the lens
      for (let i = 0; i < _rays.length; i++) _rays[i].set(OCC_RAYS[i][0], OCC_RAYS[i][1], 0.5).unproject(cam).sub(C).normalize();
      let ax0 = C.x - OCC_NEAR, ax1 = C.x + OCC_NEAR, ay0 = C.y - OCC_NEAR, ay1 = C.y + OCC_NEAR, az0 = C.z - OCC_NEAR, az1 = C.z + OCC_NEAR;
      for (const q of _pts) {
        if (q.x < ax0) ax0 = q.x; if (q.x > ax1) ax1 = q.x;
        if (q.y < ay0) ay0 = q.y; if (q.y > ay1) ay1 = q.y;
        if (q.z < az0) az0 = q.z; if (q.z > az1) az1 = q.z;
      }
      const chest = _pts[1];
      const reach = heroZ + 0.5; // protected boxes: only those that can be closer to the lens than the hero
      for (let i = 0; i < boxes.length; i++) {
        const b = boxes[i];
        if (b.enabled && OCC_KEEP.has(b.tag)) {
          const dx = Math.max(b.minX - C.x, 0, C.x - b.maxX), dy = Math.max(b.minY - C.y, 0, C.y - b.maxY), dz = Math.max(b.minZ - C.z, 0, C.z - b.maxZ);
          const d = Math.sqrt(dx * dx + dy * dy + dz * dz);
          if (d < reach) this._occWall(o, b, d);
          continue;
        }
        if (!b.enabled || b.ramp || OCC_SKIP.has(b.tag) || (b.camera && ARCH.has(b.tag))) continue;
        if (b.maxX < ax0 || b.minX > ax1 || b.maxY < ay0 || b.minY > ay1 || b.maxZ < az0 || b.minZ > az1) continue;
        if (b.maxY < o.feetY + 0.1) continue;
        // around the hero (a volume it stands in), not between
        if (chest.x > b.minX && chest.x < b.maxX && chest.y > b.minY && chest.y < b.maxY && chest.z > b.minZ && chest.z < b.maxZ) continue;
        let hit = false;
        for (let k = 0; k < _pts.length && !hit; k++) {
          const q = _pts[k];
          _dir.copy(q).sub(C);
          const len = _dir.length();
          if (len < 0.35) continue;
          _dir.divideScalar(len);
          const t = segBox(b, C, _dir, len);
          hit = t >= 0 && t < len - 0.3;
        }
        for (let k = 0; k < _rays.length && !hit; k++) hit = segBox(b, C, _rays[k], OCC_NEAR) >= 0;
        if (!hit) continue;
        let e = st.get(b);
        if (!e) st.set(b, (e = { box: b, level: 0, hold: 0, hit: false }));
        e.hit = true;
      }
    }
    const list = this._occList;
    list.length = 0;
    for (const e of st.values()) {
      if (e.hit) e.hold = OCC_HOLD;
      else e.hold -= dt;
      e.level = e.hold > 0 ? Math.min(1, e.level + dt / OCC_IN) : e.level - dt / OCC_OUT;
      if (e.level <= 0 && e.hold <= 0) { st.delete(e.box); continue; }
      if (e.level > 0) list.push(e);
    }
    if (list.length > OCC_BOXES) list.sort(byLevel);
    o.n = Math.min(OCC_BOXES, list.length);
    for (let i = 0; i < o.n; i++) {
      const e = list[i], b = e.box, d = o.boxes[i];
      d.min.set(b.minX - OCC_PAD, b.minY - OCC_PAD, b.minZ - OCC_PAD);
      d.max.set(b.maxX + OCC_PAD, b.maxY + OCC_PAD, b.maxZ + OCC_PAD);
      d.level = e.level * OCC_BOX_MAX;
    }
  }
}
