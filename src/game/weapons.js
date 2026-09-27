// Weapons: arsenal, firing, reload, swap, melee, tube grenades, shootables, held-weapon pose + gun FX
// (ARCHITECTURE §4/§10/§12, GDD §6.2, §9.1–§9.3, §9.5, §11 perk hooks, §14 no-hint UI, §15 cues, §16 controls).
// Owned by the weapons engineer. Data: weaponDefs.js; models: weaponModels.js (prop library wrapper).
//
// FIELDS  defs (WEAPON_DEFS) · slots [{ id, upgraded, signal, mag, reserve, fired }] · current (index; -1 = melee only)
//   maxSlots (2) · grenades (0..4) · teles (0..3) · reloading (bool) · swapping (bool) · spread (current crosshair
//   spread in degrees, hip/ADS + bloom) · aimPoint (Vector3: where the crosshair ray lands) · aimDist
//   hit (while zombies.damage runs from a weapon: { weaponId, upgraded, signal, cause, primary, head } else null;
//   signal-colour listeners on zombie:hit read it) · lastShot { weaponId, upgraded, signal, time, hits, kills }
// ARSENAL API
//   give(id, { upgraded=false, source='debug', signal=null }) -> bool   emits weapon:acquire {weaponId, upgraded, source}.
//       Guns: a free slot, else replaces the held one; owning it already = full ammo refill (keeps an upgrade).
//       'tube_grenade' refills grenades to 4, 'tiny_tele' sets teles to 3. Equips with a quick raise.
//   has(id) · currentDef() · currentSlot() · slotOf(id) -> slot|null · refill(id) -> bool (mag + reserve full)
//   refillAll() (FULL REEL: every slot full, grenades 4, Tiny Teles 3 if ever owned) · addGrenades(n)
//   upgradeCurrent(signal | { signal, source }) -> bool (Chromacast model, full upgraded ammo; emits weapon:acquire
//       source 'uplink') · upgrade(id, signal) · setSignal(id, signal)
//   remove(id) / take(id) -> removed slot data | null (the Uplink yank: auto-switches to the other weapon, or to
//       melee only) · takeCurrent()
//   buildModel(id, upgraded=false, signal=null) -> Group (fresh clone, HAND convention, see weaponModels.js)
//   switchTo(index) (animated swap) · cancelReload()
// SHOOTABLES (ARCHITECTURE §10) — non-zombie things that react to bullets/melee:
//   registerShootable({ id, raycast(origin, dir, maxDist) -> { dist, point } | null, onHit(info), blocksBullet=true,
//       melee=true, bullets=true }) -> entry · unregisterShootable(id)
//   info = { id, point, dir, weaponId, upgraded, melee:bool, damage, head:false, cause }. Every bullet ray (pellets,
//   pierce), the aim ray and every melee sweep test zombies + shootables + level and hit the nearest. Emits
//   weapon:hit_shootable {id, ...info}. A non-blocking shootable is hit and the bullet flies on.
//   traceRay(origin, dir, maxDist, { zombies=true, shootables=true, level=true, melee=false, blockingOnly=false }) -> nearest
//       { kind:'zombie'|'shootable'|'level', dist, point, normal?, z?, head?, zone?, entry?, tag? } | null (helper)
//   damageZombie(z, amount, opts) -> killed   zombies.damage + the points fallback below (other systems may reuse;
//       it passes hitmarker:false unless opts.hitmarker is true). Hit zones: each ray's zone multiplier (limb ×0.8,
//       custom zones) is applied per pellet and the aggregate is passed with its dominant zone, so zombies.damage
//       ends with exactly sum(ray damage × zone mul).
// HUD: currentSpread() (degrees, for the crosshair ticks). Economy helpers: defOf(id, upgraded), refillAmmo(id),
//   refillGrenades(max).
// POINTS (GDD §6.3): one zombies.damage call per zombie per shot event (pellets / Double Vision ghost / pierce
//   aggregated), so the "+10 per zombie per shot event" rule holds whoever awards it (zombies.damage does today). If
//   it added no points (economy.points unchanged), weapons adds them: hit +10, kill 50 / head 100 / melee 130 /
//   grenade 50. hud.hitmarker(head, kill) once per shot event. The crosshair aim point ignores pass-through
//   shootables (traceRay blockingOnly): it is where the bullet stops.
// WONDER WEAPONS (def.fire === 'custom': zapper, boom_mic, chroma_key) are delegated to game.wonder (src/game/wonder.js,
//   installed by its install(game) hook):
//   game.wonder.fire(weaponId, ctx) every frame while the weapon is held and not swapping/meleeing/throwing/raising,
//     ctx = { def, upgraded, signal, slot, origin, dir (camera-centre ray, origin at the player's depth), muzzle (world),
//       aimPoint, aimDist, triggerDown, triggerPressed, triggerReleased, ads, dt, ready, model (held Group), weapons,
//       time }. The trigger flags are gated by "may fire now" (not sprinting, sprint-to-fire elapsed, not reloading;
//       a press made too early is buffered 0.22 s); triggerReleased is the raw release (Boom Mic playback).
//     The wonder system owns ammo (slot.mag--), empty-mag reloads, dry fire and emits its own weapon:fire; weapons
//     adds the held-model recoil spring + a little shake + crosshair bloom when it returns truthy (if it returns
//     truthy without emitting weapon:fire, weapons emits it and kicks the camera: { kick, shake, recoil, noEvent }).
//   game.wonder.reload(weaponId, ctx) on R -> seconds (0 / false = refused): the wonder system runs the reload
//     (timing, ammo, weapon:reload, cues, part animation); weapons mirrors wonder.reloading / reloadProgress for the
//     pose (weapons.reloading). Optional hooks: game.wonder.holster(weaponId, ctx) / equip(weaponId, ctx).
//   Without game.wonder: a hitscan fallback fires and weapons runs the reload itself (one console warning).
//   Q: weapons takes one Tiny Tele (teles--), plays the left-hand wind-up (a Tiny Tele model in the hand) and calls
//     game.wonder.throwTele(ctx) at the release, ctx = { origin (left hand), dir, velocity, aimPoint }; false gives
//     it back. weapons._handlesTele = true tells the wonder system not to read Q itself.
// PLAYER MODS read every frame (_eff()): fireRate (×rate), reloadSpeed / swapSpeed (time multipliers: 0.5 = twice as
//   fast; values > 1 are read as speeds), sprintToFire (s), damage, meleeDamage, ghostBullets. When a perk is owned
//   but its mod is untouched, the perk itself applies (perks.has): double_vision = fire rate ×1.2 + ghost bullets
//   (+50% on each zombie a bullet/pellet hits, doubled cyan/magenta tracers, a cyan/magenta ghost fringe on the held
//   gun), jump_cut = reload/swap ×0.5 + throws 30% faster + reloads skip frames (splice flash + jumpcut_snip),
//   roller_boogie = 0.10 s sprint-to-fire + reload while sprinting (also mods.reloadWhileSprinting / unlimitedSprint).
// CONTROLS (GDD §16): LMB fire (semi / pump / 3-round burst / auto; held auto keeps the exact rpm at any frame rate),
//   RMB aim (player+camera), R reload (firing interrupts the pump's shell-by-shell reload), 1/2(/3)/wheel/'weaponNext' (pad Y) swap
//   (T.player.swap 0.6 s), V melee (150, 0.7 s, 1.6 m reach, lunge up to 2.5 m to the zombie under the
//   crosshair), G hold to cook / release to throw a tube grenade (1.8 s fuse from the press), Q Tiny Tele.
//   No firing while sprinting; T.player.sprintToFire after it. +2 grenades at every round start after the first (max 4).
// POSE: the held model hangs on hero slots.handR (through a holder that applies def.scale); after the procedural
//   animation (animator.update is wrapped once per hero, skipped while another system owns animator.override) a
//   two-bone IK puts the grip in the right hand and the left hand on the weapon's leftHand point, aimed at the
//   crosshair point, with hip/ADS, recoil springs, reload/swap/sprint/melee/throw layers. Melee swings per hero
//   (MELEE_PROPS.swing: Duke chop, Skip/Penny bonk, Roxy slap) with a chest coil/whip and the hero prop in the left hand.
// EVENTS emitted: weapon:fire {weaponId, upgraded} · weapon:reload {weaponId} · weapon:empty {weaponId} (dry fire)
//   · weapon:switch {weaponId} · weapon:acquire {weaponId, upgraded, source} · weapon:melee {hit} ·
//   weapon:hit_shootable {id, ...info} · weapon:grenade {pos} (explosion).
// SOUNDS: audio.js voices fire / dry_fire / weapon_swap / melee / wallbuy from the events; this file plays reload_*,
//   wpn_pump_rack, grenade_throw / grenade_bounce / grenade_explode, jumpcut_snip, studio_flash (the wonder system
//   plays its own wonder cues and tele_throw).
// TESTS: tools/scenarios/weapons_test.cjs (end-to-end checks), weapons_poses.cjs / weapons_fx.cjs (visual review),
//   run on the private bundle (weapons_build.cjs + weapons_run.cjs, see their headers). Shots: _shots/weapons/.

import * as THREE from 'three';
import { T, PAL } from '../core/config.js';
import { WEAPON_DEFS, weaponDef, GHOST_MUL, PIERCE_MUL, MAX_RANGE, SIGNAL_COLORS, MELEE_PROPS, isGunDef } from './weaponDefs.js';
import { buildModel, buildMeleeProp, buildGrenadeModel, buildTeleModel, chromacast } from './weaponModels.js';

const P = T.player;
const V3 = THREE.Vector3;
const Q = THREE.Quaternion;
const clamp = THREE.MathUtils.clamp;
const lerp = THREE.MathUtils.lerp;
const smooth = (a, b, x) => THREE.MathUtils.smoothstep(x, a, b);
const easeOutBack = (x, s = 1.7) => 1 + (s + 1) * (x - 1) ** 3 + s * (x - 1) ** 2;
const easeInOut = (x) => x * x * (3 - 2 * x);
const UP = new V3(0, 1, 0);
const X_AXIS = new V3(1, 0, 0);
const Y_AXIS = new V3(0, 1, 0);
const Z_AXIS = new V3(0, 0, 1);
const ORIGIN = new V3();

// scratch (per-frame code allocates nothing)
const _a = new V3(), _b = new V3(), _c = new V3(), _d = new V3(), _o = new V3(), _n = new V3(), _r = new V3(), _u = new V3();
const _v1 = new V3(), _v2 = new V3(), _v3 = new V3(), _v4 = new V3(), _v5 = new V3();
const _q1 = new Q(), _q2 = new Q(), _q3 = new Q(), _q4 = new Q(), _q5 = new Q();
const _m4 = new THREE.Matrix4();
const _e = new THREE.Euler();
const _col = new THREE.Color();
const _hitList = [];

// ============================================================================================ two-bone IK
const _S = new V3(), _E = new V3(), _H = new V3(), _T = new V3(), _D = new V3(), _PP = new V3(), _U = new V3(), _F = new V3(),
  _W = new V3(), _X = new V3(), _Y = new V3(), _Z = new V3();
const _qs = new Q(), _qp = new Q(), _qe = new Q();

// Arm reach from the shoulder (world metres, current pose).
function armReach(sh, el, ha) {
  sh.getWorldPosition(_S); el.getWorldPosition(_E); ha.getWorldPosition(_H);
  return _S.distanceTo(_E) + _E.distanceTo(_H);
}

// Solves shoulder/elbow so the hand joint reaches `target` (world), elbow bent toward `pole` (world direction), then
// sets the hand's world rotation to handQ. The rig bends elbows around local +x (forward = -z), bones along -y.
function solveArm(sh, el, ha, target, pole, handQ) {
  sh.getWorldPosition(_S); el.getWorldPosition(_E); ha.getWorldPosition(_H);
  const a = _S.distanceTo(_E), b = _E.distanceTo(_H);
  if (a < 1e-4 || b < 1e-4) return;
  _D.subVectors(target, _S);
  let d = _D.length();
  if (d < 1e-5) return;
  _D.divideScalar(d);
  d = clamp(d, Math.abs(a - b) + 1e-3, (a + b) * 0.9995);
  const cosA = clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1), sinA = Math.sqrt(1 - cosA * cosA);
  _PP.copy(pole).addScaledVector(_D, -pole.dot(_D));
  if (_PP.lengthSq() < 1e-8) _PP.set(0, -1, 0).addScaledVector(_D, _D.y);
  _PP.normalize();
  _E.copy(_S).addScaledVector(_D, a * cosA).addScaledVector(_PP, a * sinA);
  _T.copy(_S).addScaledVector(_D, d);
  _U.subVectors(_E, _S).divideScalar(a);
  _F.subVectors(_T, _E).divideScalar(b);
  const cosT = clamp(_U.dot(_F), -1, 1);
  _W.copy(_F).addScaledVector(_U, -cosT);
  if (_W.lengthSq() < 1e-8) _W.copy(_PP).negate().addScaledVector(_U, _PP.dot(_U));
  _W.normalize();
  _Y.copy(_U).negate();
  _Z.copy(_W).negate();
  _X.crossVectors(_Y, _Z).normalize();
  _m4.makeBasis(_X, _Y, _Z);
  _qs.setFromRotationMatrix(_m4);
  sh.parent.getWorldQuaternion(_qp);
  sh.quaternion.copy(_qp.invert()).multiply(_qs);
  el.quaternion.setFromAxisAngle(X_AXIS, Math.acos(cosT));
  if (handQ) {
    _qe.copy(_qs).multiply(el.quaternion).invert();
    ha.quaternion.copy(_qe).multiply(handQ);
  }
}

// ============================================================================================ canvas textures
function canvasTex(size, draw) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  draw(c.getContext('2d'), size);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function starTex() {
  return canvasTex(128, (g, s) => {
    const h = s / 2;
    const rg = g.createRadialGradient(h, h, 0, h, h, h);
    rg.addColorStop(0, 'rgba(255,255,255,1)'); rg.addColorStop(0.18, 'rgba(255,250,230,1)');
    rg.addColorStop(0.45, 'rgba(255,220,150,0.55)'); rg.addColorStop(1, 'rgba(255,170,80,0)');
    g.fillStyle = rg;
    g.beginPath();
    const n = 8;
    for (let i = 0; i <= n * 2; i++) {
      const a = (i / (n * 2)) * Math.PI * 2, r = i % 2 ? h * 0.3 : h * (i % 4 === 0 ? 1 : 0.72);
      if (i === 0) g.moveTo(h + Math.cos(a) * r, h + Math.sin(a) * r); else g.lineTo(h + Math.cos(a) * r, h + Math.sin(a) * r);
    }
    g.fill();
    const core = g.createRadialGradient(h, h, 0, h, h, h * 0.35);
    core.addColorStop(0, 'rgba(255,255,255,1)'); core.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = core;
    g.fillRect(0, 0, s, s);
  });
}

function ringTex(rainbow) {
  return canvasTex(128, (g, s) => {
    const h = s / 2;
    if (rainbow && g.createConicGradient) {
      const cg = g.createConicGradient(0, h, h);
      const bars = PAL.BARS || ['#fff', '#ff0', '#0ff', '#0f0', '#f0f', '#f00', '#00f'];
      bars.forEach((c, i) => cg.addColorStop(i / bars.length, c));
      cg.addColorStop(1, bars[0]);
      g.fillStyle = cg;
    } else g.fillStyle = '#ffffff';
    g.fillRect(0, 0, s, s);
    g.globalCompositeOperation = 'destination-in';
    const rg = g.createRadialGradient(h, h, 0, h, h, h);
    rg.addColorStop(0, 'rgba(0,0,0,0)'); rg.addColorStop(0.62, 'rgba(0,0,0,0)'); rg.addColorStop(0.78, 'rgba(0,0,0,1)');
    rg.addColorStop(0.88, 'rgba(0,0,0,0.9)'); rg.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = rg;
    g.fillRect(0, 0, s, s);
  });
}

// Double Vision ghost: same screen position, depth pushed 12 cm back along the view ray.
const GHOST_PUSH = /* glsl */`#include <project_vertex>
gl_Position = projectionMatrix * vec4( mvPosition.xyz * ( 1.0 + 0.12 / max( 0.3, length( mvPosition.xyz ) ) ), 1.0 );`;

const additive = (map, vertexColors = false) => new THREE.MeshBasicMaterial({ color: 0xffffff, map: map || null, vertexColors, blending: THREE.AdditiveBlending,
  transparent: true, depthWrite: false, toneMapped: false, fog: false, side: THREE.DoubleSide });

function instanced(scene, geo, mat, cap, name) {
  const m = new THREE.InstancedMesh(geo, mat, cap);
  m.name = name;
  m.frustumCulled = false;
  m.castShadow = m.receiveShadow = false;
  m.count = 0;
  m.visible = false;
  m.setColorAt(0, _col.set(1, 1, 1));
  m.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
  scene.add(m);
  return m;
}

// ============================================================================================ gun FX pools
// Moving tracer streaks, muzzle stars (camera-facing card + side flame), expanding rings (rainbow / tinted) and
// ejected casings / shells with a little bounce physics. Every pool is one InstancedMesh, hidden while empty.
class GunFX {
  constructor(game) {
    this.game = game;
    const scene = game.scene;
    // streaks: tapered cylinder along +z, dark tail -> bright head (vertex colours) x instance colour
    const sg = new THREE.CylinderGeometry(0.5, 0.5, 1, 6, 1, true).rotateX(Math.PI / 2).translate(0, 0, 0.5);
    const sp = sg.attributes.position, scol = new Float32Array(sp.count * 3);
    for (let i = 0; i < sp.count; i++) { const k = 0.08 + 0.92 * sp.getZ(i); scol[i * 3] = scol[i * 3 + 1] = scol[i * 3 + 2] = k * k; }
    sg.setAttribute('color', new THREE.BufferAttribute(scol, 3));
    this.streakMesh = instanced(scene, sg, additive(null, true), 128, 'wpn:streaks');
    this.streaks = [];
    for (let i = 0; i < 128; i++) this.streaks.push({ on: false, from: new V3(), dir: new V3(), dist: 0, t: 0, speed: 0, len: 0, width: 0, color: new THREE.Color(), flicker: 0, wob: 0, life: 0, still: false });
    // muzzle / hit stars
    const star = starTex();
    this.cardMesh = instanced(scene, new THREE.PlaneGeometry(1, 1), additive(star), 32, 'wpn:cards');
    const fg = new THREE.PlaneGeometry(1, 1).translate(0, 0, 0);
    const cross = new THREE.BufferGeometry();
    const a = fg.clone().rotateY(Math.PI / 2), b = fg.clone().rotateY(Math.PI / 2).rotateZ(Math.PI / 2);
    cross.setAttribute('position', new THREE.BufferAttribute(new Float32Array([...a.attributes.position.array, ...b.attributes.position.array]), 3));
    cross.setAttribute('uv', new THREE.BufferAttribute(new Float32Array([...a.attributes.uv.array, ...b.attributes.uv.array]), 2));
    cross.setIndex([...a.index.array, ...Array.from(b.index.array, (i) => i + 4)]);
    cross.translate(0, 0, -0.5);
    this.flameMesh = instanced(scene, cross, additive(star), 32, 'wpn:flames');
    this.cards = [];
    for (let i = 0; i < 32; i++) this.cards.push({ life: 0, max: 1, pos: new V3(), dir: new V3(), size: 0, spin: 0, color: new THREE.Color(), flame: false, grow: 0 });
    // rings
    const rg = new THREE.PlaneGeometry(1, 1);
    this.ringMesh = { rainbow: instanced(scene, rg, additive(ringTex(true)), 16, 'wpn:rings_rainbow'), white: instanced(scene, rg, additive(ringTex(false)), 24, 'wpn:rings') };
    this.rings = { rainbow: [], white: [] };
    for (const k of ['rainbow', 'white']) for (let i = 0; i < this.ringMesh[k].instanceMatrix.count; i++) this.rings[k].push({ life: 0, max: 1, pos: new V3(), q: new Q(), r0: 0, r1: 1, color: new THREE.Color(), face: false });
    // casings
    const M = game.mats;
    const brassGeo = new THREE.CylinderGeometry(0.014, 0.014, 0.045, 8).rotateX(Math.PI / 2);
    const shellA = new THREE.CylinderGeometry(0.022, 0.022, 0.06, 10).translate(0, 0.012, 0);
    const shellB = new THREE.CylinderGeometry(0.0235, 0.0235, 0.024, 10).translate(0, -0.03, 0);
    const shellGeo = mergeColored([[shellA, '#D8322B'], [shellB, '#E2A93A']]).rotateX(Math.PI / 2);
    this.casing = {
      brass: this._phys(scene, brassGeo, M.toon('#E2A93A', { metal: 0.8, rough: 0.28, keepColor: true, name: 'wpn:brass' }), 40),
      shell: this._phys(scene, shellGeo, M.toon('#ffffff', { vertexColors: true, rough: 0.35, keepColor: true, name: 'wpn:shell' }), 24),
    };
  }

  _phys(scene, geo, mat, cap) {
    const mesh = instanced(scene, geo, mat, cap, 'wpn:casings');
    const list = [];
    for (let i = 0; i < cap; i++) list.push({ life: 0, pos: new V3(), vel: new V3(), q: new Q(), axis: new V3(1, 0, 0), spin: 0, floor: 0, bounced: 0 });
    return { mesh, list, head: 0 };
  }

  // Materials used by the pools (precompile samples).
  samples() {
    const out = [];
    for (const m of [this.streakMesh, this.cardMesh, this.flameMesh, this.ringMesh.rainbow, this.ringMesh.white, this.casing.brass.mesh, this.casing.shell.mesh]) {
      const s = new THREE.InstancedMesh(m.geometry, m.material, 1);
      s.setMatrixAt(0, new THREE.Matrix4());
      s.setColorAt(0, new THREE.Color(1, 1, 1));
      out.push(s);
    }
    return out;
  }

  reset() {
    for (const s of this.streaks) s.on = false;
    for (const c of this.cards) c.life = 0;
    for (const k in this.rings) for (const r of this.rings[k]) r.life = 0;
    for (const k in this.casing) for (const c of this.casing[k].list) c.life = 0;
  }

  // Bullet streak from `from` to `to`: flies at style.speed, length style.len; delay (s) staggers pellets.
  streak(from, to, style, color, delay = 0, offset = null) {
    const s = this.streaks.find((x) => !x.on) || this.streaks[(Math.random() * this.streaks.length) | 0];
    s.on = true;
    s.from.copy(from);
    if (offset) s.from.add(offset);
    s.dir.subVectors(to, s.from);
    s.dist = s.dir.length();
    if (s.dist < 0.05) { s.on = false; return; }
    s.dir.divideScalar(s.dist);
    s.speed = style.speed || 160;
    s.len = style.len || 2.5;
    s.width = style.width || 0.03;
    s.color.set(color || style.color || '#FFE9A8').multiplyScalar(style.boost || 2.6);
    s.flicker = style.style === 'scratch' ? 1 : 0;
    s.wob = style.style === 'scratch' ? 0.02 : 0;
    s.t = -delay;
    s.still = false;
  }

  // A short static bar (film-splice line, flashbulb glints): lives `life` s.
  bar(from, to, width, color, life = 0.06) {
    const s = this.streaks.find((x) => !x.on) || this.streaks[0];
    s.on = true;
    s.from.copy(from);
    s.dir.subVectors(to, from);
    s.dist = s.dir.length();
    if (s.dist < 1e-3) { s.on = false; return; }
    s.dir.divideScalar(s.dist);
    s.len = s.dist; s.width = width; s.color.set(color).multiplyScalar(2.5); s.flicker = 0; s.wob = 0;
    s.still = true; s.t = 0; s.life = life;
  }

  // Muzzle flash: camera-facing star + a flame cross along the barrel.
  flash(pos, dir, size, color, life = 0.06) {
    this._card(pos, dir, size, color, false, life, 0);
    this._card(pos, dir, size * 1.25, color, true, life * 0.9, 0);
  }

  // Hit spark card (white pop at the impact).
  pop(pos, size, color, life = 0.07) {
    this._card(pos, UP, size, color, false, life, 1.6);
  }

  _card(pos, dir, size, color, flame, life, grow) {
    let c = this.cards[0];
    for (const x of this.cards) if (x.life <= 0) { c = x; break; } else if (x.life < c.life) c = x;
    c.life = c.max = life;
    c.pos.copy(pos);
    c.dir.copy(dir);
    c.size = size;
    c.spin = Math.random() * Math.PI * 2;
    c.color.set(color).multiplyScalar(flame ? 2.2 : 2.8);
    c.flame = flame;
    c.grow = grow;
  }

  // Expanding ring: normal = facing direction; face = true -> faces the camera instead.
  ring(pos, normal, r0, r1, life, color, rainbow = false) {
    const list = this.rings[rainbow ? 'rainbow' : 'white'];
    let r = list[0];
    for (const x of list) if (x.life <= 0) { r = x; break; } else if (x.life < r.life) r = x;
    r.life = r.max = life;
    r.pos.copy(pos);
    r.q.setFromUnitVectors(Z_AXIS, _v5.copy(normal).normalize());
    r.r0 = r0; r.r1 = r1;
    r.color.set(color || '#ffffff').multiplyScalar(rainbow ? 2.2 : 2.4);
  }

  eject(kind, pos, vel) {
    const P = this.casing[kind];
    if (!P) return;
    const c = P.list[P.head];
    P.head = (P.head + 1) % P.list.length;
    c.life = 1.6;
    c.pos.copy(pos);
    c.vel.copy(vel);
    c.q.setFromEuler(_e.set(Math.random() * 6, Math.random() * 6, Math.random() * 6));
    c.axis.set(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5).normalize();
    c.spin = 14 + Math.random() * 16;
    const col = this.game.level && this.game.level.col;
    const f = col ? col.floorAt(pos.x, pos.z, pos.y) : -Infinity;
    c.floor = f > -Infinity ? f + 0.015 : pos.y - 1.4;
    c.bounced = 0;
  }

  update(dt, camera) {
    // streaks
    const SM = this.streakMesh;
    let n = 0;
    for (const s of this.streaks) {
      if (!s.on) continue;
      let tail, head;
      if (s.still) {
        s.life -= dt;
        if (s.life <= 0) { s.on = false; continue; }
        tail = 0; head = s.dist;
      } else {
        s.t += dt;
        if (s.t < 0) continue;
        head = Math.min(s.dist, s.t * s.speed);
        tail = Math.max(0, s.t * s.speed - s.len);
        if (tail >= s.dist) { s.on = false; continue; }
      }
      const len = head - tail;
      if (len <= 1e-3) continue;
      _a.copy(s.from).addScaledVector(s.dir, tail);
      if (s.wob) _a.x += (Math.random() - 0.5) * s.wob, _a.y += (Math.random() - 0.5) * s.wob;
      _q1.setFromUnitVectors(Z_AXIS, s.dir);
      const w = s.width * (s.flicker ? 0.6 + Math.random() * 0.8 : 1);
      _m4.compose(_a, _q1, _b.set(w, w, len));
      SM.setMatrixAt(n, _m4);
      _col.copy(s.color);
      if (s.flicker) _col.multiplyScalar(0.5 + Math.random() * 0.9);
      SM.setColorAt(n, _col);
      n++;
    }
    SM.count = n;
    SM.visible = n > 0;
    if (n) { SM.instanceMatrix.needsUpdate = true; SM.instanceColor.needsUpdate = true; }

    // cards + flames
    let nc = 0, nf = 0;
    const CM = this.cardMesh, FM = this.flameMesh;
    for (const c of this.cards) {
      if (c.life <= 0) continue;
      c.life -= dt;
      if (c.life <= 0) continue;
      const k = 1 - c.life / c.max;
      const pop = k < 0.25 ? 0.7 + k * 1.6 : 1.1 - (k - 0.25) * 0.6;
      const s = c.size * pop * (1 + c.grow * k);
      _col.copy(c.color).multiplyScalar(1 - k * k);
      if (c.flame) {
        _q1.setFromUnitVectors(Z_AXIS, _a.copy(c.dir).negate());
        _q1.multiply(_q2.setFromAxisAngle(Z_AXIS, c.spin));
        _m4.compose(c.pos, _q1, _b.set(s * 0.55, s * 0.55, s * 1.3));
        FM.setMatrixAt(nf, _m4);
        FM.setColorAt(nf, _col);
        nf++;
      } else {
        _q1.copy(camera.quaternion).multiply(_q2.setFromAxisAngle(Z_AXIS, c.spin));
        _m4.compose(c.pos, _q1, _b.set(s, s, s));
        CM.setMatrixAt(nc, _m4);
        CM.setColorAt(nc, _col);
        nc++;
      }
    }
    for (const [m, cnt] of [[CM, nc], [FM, nf]]) {
      m.count = cnt;
      m.visible = cnt > 0;
      if (cnt) { m.instanceMatrix.needsUpdate = true; m.instanceColor.needsUpdate = true; }
    }

    // rings
    for (const key of ['rainbow', 'white']) {
      const RM = this.ringMesh[key];
      let nr = 0;
      for (const r of this.rings[key]) {
        if (r.life <= 0) continue;
        r.life -= dt;
        if (r.life <= 0) continue;
        const k = 1 - r.life / r.max;
        const e = 1 - (1 - k) ** 3;
        const s = (r.r0 + (r.r1 - r.r0) * e) * 2;
        _m4.compose(r.pos, r.q, _b.set(s, s, s));
        RM.setMatrixAt(nr, _m4);
        RM.setColorAt(nr, _col.copy(r.color).multiplyScalar((1 - k) ** 1.5));
        nr++;
      }
      RM.count = nr;
      RM.visible = nr > 0;
      if (nr) { RM.instanceMatrix.needsUpdate = true; RM.instanceColor.needsUpdate = true; }
    }

    // casings
    for (const key in this.casing) {
      const C = this.casing[key];
      let nn = 0;
      for (const c of C.list) {
        if (c.life <= 0) continue;
        c.life -= dt;
        if (c.life <= 0) continue;
        c.vel.y -= 16 * dt;
        c.pos.addScaledVector(c.vel, dt);
        if (c.pos.y < c.floor) {
          c.pos.y = c.floor;
          if (c.vel.y < -1.2 && c.bounced < 3) {
            c.vel.y = -c.vel.y * 0.38; c.vel.x *= 0.55; c.vel.z *= 0.55; c.spin *= 0.6; c.bounced++;
          } else { c.vel.set(0, 0, 0); c.spin *= 0.8; }
        }
        c.q.premultiply(_q1.setFromAxisAngle(c.axis, c.spin * dt));
        const s = c.life < 0.3 ? c.life / 0.3 : 1;
        _m4.compose(c.pos, c.q, _b.set(1.3 * s, 1.3 * s, 1.3 * s));
        C.mesh.setMatrixAt(nn, _m4);
        nn++;
      }
      C.mesh.count = nn;
      C.mesh.visible = nn > 0;
      if (nn) C.mesh.instanceMatrix.needsUpdate = true;
    }
  }
}

function mergeColored(parts) {
  const pos = [], nor = [], col = [], idx = [];
  let base = 0;
  for (const [g, hex] of parts) {
    const c = new THREE.Color(hex);
    const p = g.attributes.position, nn = g.attributes.normal;
    for (let i = 0; i < p.count; i++) {
      pos.push(p.getX(i), p.getY(i), p.getZ(i));
      nor.push(nn.getX(i), nn.getY(i), nn.getZ(i));
      col.push(c.r, c.g, c.b);
    }
    for (const i of g.index.array) idx.push(i + base);
    base += p.count;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(nor, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.setIndex(idx);
  return g;
}

// ============================================================================================ holds (pose data)
// Offsets in the aim frame (x right, y up, -z forward) from the midpoint of the shoulders, metres at 1.8 m hero
// height. 'grip' places the grip; 'butt' places the stock end. chest: bladed stance yaw (rad); lh: left-hand frame.
const HOLDS = {
  pistol: { mode: 'grip', hip: [0.1, -0.05, -0.43], ads: [0.07, -0.01, -0.42], chest: -0.12, poleR: [0.8, -1, 0.3], poleL: [-0.6, -1, 0.2], lh: 'cup' },
  rifle: { mode: 'butt', hip: [0.17, -0.08, 0.02], ads: [0.12, -0.02, 0.0], chest: -0.42, poleR: [1, -0.75, 0.35], poleL: [-0.25, -1, 0.1], lh: 'under' },
  lmg: { mode: 'butt', hip: [0.19, -0.2, 0.08], ads: [0.14, -0.1, 0.04], chest: -0.4, poleR: [1, -0.6, 0.4], poleL: [-0.2, -1, 0.1], lh: 'under' },
  remote: { mode: 'grip', hip: [0.13, -0.06, -0.45], ads: [0.09, -0.02, -0.46], chest: -0.1, poleR: [0.8, -1, 0.3], poleL: [-0.6, -1, 0.2], lh: 'cup' },
  pole: { mode: 'grip', hip: [0.16, -0.2, -0.12], ads: [0.13, -0.13, -0.14], chest: -0.35, poleR: [1, -0.6, 0.4], poleL: [-0.25, -1, 0.1], lh: 'under', pitch: 0.1 },
  cannon: { mode: 'grip', hip: [0.16, -0.17, -0.22], ads: [0.12, -0.1, -0.24], chest: -0.3, poleR: [1, -0.6, 0.4], poleL: [-0.4, -1, 0.1], lh: 'side' },
};
const LH_FRAMES = {
  cup: new Q().setFromEuler(new THREE.Euler(0.55, 0, 0.35)),
  under: new Q().setFromEuler(new THREE.Euler(0, 0.35, Math.PI / 2)),
  side: new Q().setFromEuler(new THREE.Euler(0, 0, 0.15)),
};
const RH_FRAME = new Q().setFromEuler(new THREE.Euler(0, 0, 0));
// Melee swings of the left hand, aim frame from the shoulders' midpoint (x right, y up, -z forward), 1.8 m hero:
// wind-up point, arc control point, hit point; hand euler at wind-up / hit. twist = chest yaw (wind, hit).
const SWINGS = {
  chop: { wind: [-0.36, 0.32, 0.1], ctrl: [-0.22, 0.2, -0.5], hit: [0.12, -0.14, -0.6], rotW: [-0.9, 0, 1.2], rotH: [0.4, 0, 1.2], twist: [0.35, -0.3] },
  bonk: { wind: [-0.16, 0.46, 0.1], ctrl: [-0.1, 0.42, -0.42], hit: [0.02, -0.1, -0.62], rotW: [-1.5, 0, 0.3], rotH: [0.5, 0, 0.3], twist: [0.2, -0.2] },
  slap: { wind: [-0.52, 0.08, 0.02], ctrl: [-0.25, 0.06, -0.62], hit: [0.3, -0.02, -0.48], rotW: [0, 0.9, 1.4], rotH: [0, -0.6, 1.4], twist: [0.45, -0.4] },
};
const BELT_L = new V3(-0.14, -0.62, -0.02);      // left hip pouch, body frame from the shoulders' midpoint

// ============================================================================================ the system
export class Weapons {
  constructor(game) {
    this.game = game;
    this.defs = WEAPON_DEFS;
    this.slots = [];
    this.current = -1;
    this.maxSlots = 2;
    this.grenades = 0;
    this.teles = 0;
    this.teleOwned = false;
    this.reloading = false;
    this.swapping = false;
    this.spread = 2.5;
    this.aimPoint = new V3();
    this.aimDist = 20;
    this.aimOrigin = new V3();
    this.aimDir = new V3(0, 0, -1);
    this.hit = null;
    this.lastShot = { weaponId: null, upgraded: false, signal: null, time: 0, hits: 0, kills: 0 };
    this.shootables = new Map();
    this.fx = null;

    this._held = new Map();          // model cache key -> { holder, model, def }
    this._heldKey = null;
    this._cool = 0;
    this._burst = 0;
    this._pumpT = 0;                 // pump action animation 0..1 (after a shot)
    this._pumpRacked = true;
    this._autoReloadT = -1;
    this._sinceSprint = 99;
    this._bloom = 0;
    this._adsW = 0;
    this._sprintW = 0;
    this._busyW = 0;                 // gun pulled back (melee / throw)
    this._reload = { t: 0, total: 1, kind: 'mag', shells: 0, shellT: 0, started: false, cues: 0, snips: 0, stage: 0 };
    this._swap = { t: 0, total: 0.6, to: -1, swapped: true };
    this._raise = 1;                 // 0..1 raise-in after equip
    this._melee = { t: -1, hit: false, cd: 0, lungeDist: 0, target: null, prop: null, propHero: null };
    this._nade = { state: 'none', t: 0, cook: 0, released: false, model: null };
    this._tele = { t: -1, thrown: false, model: null };
    this._recoil = { back: 0, vb: 0, rise: 0, vr: 0, roll: 0, vroll: 0 };
    this._fireHeld = false;
    this._grenadeRound = 0;
    this._roundsSeen = 0;
    this._grenadesAtEnd = null;
    this._projectiles = [];
    this._agg = new Map();
    this._aggPool = [];
    this._hitSet = new Set();
    this._warned = new Set();
    this._wrapped = new WeakSet();
    this._poseFn = (rig, dt) => this._poseSafe(rig, dt);
    this._ctx = { def: null, upgraded: false, signal: null, slot: null, origin: new V3(), dir: new V3(), muzzle: new V3(), aimPoint: new V3(), aimDist: 0,
      triggerDown: false, triggerPressed: false, triggerReleased: false, ads: false, dt: 0, ready: false, model: null, weapons: this, time: 0, duration: 0,
      velocity: new V3() };
    this._teleCtx = { origin: new V3(), dir: new V3(), velocity: new V3(), aimPoint: new V3(), weapons: this };
    this._handPole = new V3();
    this._gripW = new V3();
    this._gunQ = new Q();
    this._leftW = new V3();
    this._pressBuf = 0;              // trigger press buffered while not ready (sprint-to-fire, cooldown, raise)
    this._inWonder = false;          // inside game.wonder.fire(): detects the wonder system's own weapon:fire
    this._wonderEmitted = false;
    this._handlesTele = true;        // tells game.wonder that Q is read here (its self-drive skips it)

    game.events.on('round:start', (e) => this._onRoundStart(e || {}));
    game.events.on('round:end', () => { this._grenadesAtEnd = this.grenades; });
    game.events.on('weapon:fire', () => { if (this._inWonder) this._wonderEmitted = true; });
    if (game.mats && !game.mats.chromacast) game.mats.chromacast = (signal) => chromacast(game, signal);
  }

  // ------------------------------------------------------------------------------------------ lifecycle
  init() {
    this.fx = new GunFX(this.game);
  }

  warmup() {
    const out = [];
    try {
      out.push(buildModel('revolver_38', true, null, this.game));
      out.push(buildGrenadeModel(this.game));
      if (this.fx) out.push(...this.fx.samples());
    } catch (err) {
      console.warn('[weapons] warmup', err);
    }
    return out;
  }

  reset() {
    this.slots.length = 0;
    this.current = -1;
    this.maxSlots = 2;
    this.grenades = WEAPON_DEFS.tube_grenade.start;
    this.teles = 0;
    this.teleOwned = false;
    this.reloading = false;
    this.swapping = false;
    this.hit = null;
    this._cool = this._burst = 0;
    this._pumpT = 0;
    this._pumpRacked = true;
    this._autoReloadT = -1;
    this._bloom = 0;
    this._raise = 1;
    this._swap.t = 0; this._swap.to = -1; this._swap.swapped = true;
    this._melee.t = -1; this._melee.cd = 0;
    this._nade.state = 'none';
    this._tele.t = -1;
    if (this._tele.model) this._tele.model.visible = false;
    this._grenadeRound = 0;
    this._roundsSeen = 0;
    this._grenadesAtEnd = null;
    for (const pr of this._projectiles) this._removeProjectile(pr);
    this._projectiles.length = 0;
    if (this.fx) this.fx.reset();
    if (this._melee.prop) { this._melee.prop.removeFromParent(); this._melee.prop = null; this._melee.propHero = null; }
    if (this._nade.model) this._nade.model.visible = false;
    this.game.player.setWeaponModel(null);
    this._heldKey = null;
    this.give('revolver_38', { source: 'start' });
    this._raise = 1;
  }

  _onRoundStart(e) {
    const r = e.round || 0;
    this._roundsSeen++;
    if (this._roundsSeen <= 1 || r === this._grenadeRound) { this._grenadeRound = r; return; }
    this._grenadeRound = r;
    const g = WEAPON_DEFS.tube_grenade;
    const base = this._grenadesAtEnd ?? this.grenades;
    this.grenades = Math.max(this.grenades, Math.min(g.carry, base + g.perRound));
    this._grenadesAtEnd = null;
  }

  // ------------------------------------------------------------------------------------------ arsenal API
  currentSlot() { return this.slots[this.current] || null; }

  currentDef() {
    const s = this.slots[this.current];
    return s ? weaponDef(s.id, s.upgraded) : null;
  }

  has(id) { return this.slots.some((s) => s.id === id); }

  slotOf(id) { return this.slots.find((s) => s.id === id) || null; }

  buildModel(id, upgraded = false, signal = null) {
    return buildModel(id, upgraded, signal, this.game);
  }

  give(id, { upgraded = false, source = 'debug', signal = null } = {}) {
    const g = this.game;
    const base = WEAPON_DEFS[id];
    if (!base) return false;
    if (id === 'tube_grenade') {
      this.grenades = base.carry;
      g.events.emit('weapon:acquire', { weaponId: id, upgraded: false, source });
      return true;
    }
    if (id === 'tiny_tele') {
      this.teles = base.carry;
      this.teleOwned = true;
      g.events.emit('weapon:acquire', { weaponId: id, upgraded: false, source });
      return true;
    }
    if (!isGunDef(base)) return false;
    let i = this.slots.findIndex((s) => s.id === id);
    const up = !!upgraded || (i >= 0 && this.slots[i].upgraded);
    const def = weaponDef(id, up);
    const sig = up ? (signal || (i >= 0 ? this.slots[i].signal : null)) : null;
    if (i < 0) {
      if (this.slots.length < this.maxSlots) i = this.slots.push(null) - 1;
      else i = Math.max(0, this.current);
      if (this.slots[i] && i === this.current) this._holster();
    }
    const prev = this.slots[i];
    this._swap.t = 0;
    this.swapping = false;
    this.slots[i] = { id, upgraded: up, signal: sig, mag: def.mag, reserve: def.reserve, fired: prev && prev.id === id ? prev.fired : 0 };
    this._equip(i, true);
    g.events.emit('weapon:acquire', { weaponId: id, upgraded: up, source });
    return true;
  }

  refill(id) {
    const s = this.slotOf(id);
    if (!s) return false;
    const def = weaponDef(s.id, s.upgraded);
    s.mag = def.mag;
    s.reserve = def.reserve;
    return true;
  }

  refillAll() {
    for (const s of this.slots) {
      const def = weaponDef(s.id, s.upgraded);
      s.mag = def.mag;
      s.reserve = def.reserve;
    }
    this.grenades = WEAPON_DEFS.tube_grenade.carry;
    if (this.teleOwned) this.teles = WEAPON_DEFS.tiny_tele.carry;
    if (this.reloading) this.cancelReload();
  }

  addGrenades(n = 1) {
    this.grenades = clamp(this.grenades + n, 0, WEAPON_DEFS.tube_grenade.carry);
    return this.grenades;
  }

  refillGrenades(max = WEAPON_DEFS.tube_grenade.carry) {
    this.grenades = clamp(max, 0, WEAPON_DEFS.tube_grenade.carry);
    return this.grenades;
  }

  refillAmmo(id) { return this.refill(id); }

  defOf(id, upgraded = false) { return weaponDef(id, upgraded); }

  // Crosshair spread in degrees (hip/ADS lerp + bloom + movement), read by the HUD ticks.
  currentSpread() { return this.spread; }

  upgradeCurrent(arg = null) {
    const opts = typeof arg === 'string' ? { signal: arg } : (arg || {});
    const s = this.slots[this.current];
    if (!s) return false;
    return this.upgrade(s.id, opts.signal ?? s.signal ?? null, opts.source || 'uplink');
  }

  upgrade(id, signal = null, source = 'uplink') {
    const i = this.slots.findIndex((s) => s.id === id);
    if (i < 0 || !weaponDef(id, true).isUpgraded) return false;
    const def = weaponDef(id, true);
    Object.assign(this.slots[i], { upgraded: true, signal: signal || null, mag: def.mag, reserve: def.reserve });
    if (i === this.current) this._equip(i, true);
    this.game.events.emit('weapon:acquire', { weaponId: id, upgraded: true, source });
    return true;
  }

  setSignal(id, signal) {
    const s = this.slotOf(id);
    if (!s || !s.upgraded) return false;
    s.signal = signal || null;
    if (this.slots[this.current] === s) this._equip(this.current, false);
    return true;
  }

  remove(id) {
    const i = this.slots.findIndex((s) => s.id === id);
    if (i < 0) return null;
    const s = this.slots[i];
    const wasCurrent = i === this.current;
    if (wasCurrent) this._holster();
    this.slots.splice(i, 1);
    this._swap.t = 0;
    this.swapping = false;
    if (this.slots.length === 0) {
      this.current = -1;
      this.cancelReload();
      this.game.player.setWeaponModel(null);
      this._heldKey = null;
    } else if (wasCurrent) {
      const next = Math.min(i, this.slots.length - 1);
      this.current = -1;
      this._equip(next, true);
      this.game.events.emit('weapon:switch', { weaponId: this.slots[next].id });
    } else if (this.current > i) this.current--;
    return { ...s };
  }

  take(id) { return this.remove(id); }

  takeCurrent() {
    const s = this.slots[this.current];
    return s ? this.remove(s.id) : null;
  }

  switchTo(index) {
    if (!this.slots[index] || index === this.current || this._swap.t > 0) return false;
    const p = this.game.player;
    this.cancelReload();
    this._burst = 0;
    this._swap.total = P.swap * this._eff().swap;
    this._swap.t = 1e-4;
    this._swap.to = index;
    this._swap.swapped = false;
    this.swapping = true;
    this.game.events.emit('weapon:switch', { weaponId: this.slots[index].id });
    return true;
  }

  cancelReload() {
    if (this.reloading) this._restoreParts();
    this.reloading = false;
    this._reload.t = 0;
    const a = this.game.player.anim;
    if (a) a.reload = 0;
  }

  // Held model for slot i (cached per id / upgrade / signal).
  _equip(i, raise) {
    const g = this.game, p = g.player;
    const s = this.slots[i];
    if (!s) return;
    if (this.current !== i && this.slots[this.current]) this._holster();
    this.current = i;
    this.cancelReload();
    this._burst = 0;
    this._cool = Math.max(this._cool, 0.05);
    const key = `${s.id}|${s.upgraded ? 1 : 0}|${s.signal || ''}`;
    let h = this._held.get(key);
    if (!h) {
      const def = weaponDef(s.id, s.upgraded);
      const model = buildModel(s.id, s.upgraded, s.signal, g);
      const holder = new THREE.Group();
      holder.name = 'weaponHolder';
      holder.quaternion.copy(RH_FRAME).invert();
      holder.scale.setScalar(def.scale || 1);
      holder.add(model);
      const u = model.userData;
      h = { holder, model, def, leftHand: new V3().fromArray(u.leftHand || [0, 0, -0.15]), butt: new V3().fromArray(u.butt || [0, 0.08, 0.05]),
        muzzle: (model.getObjectByName('muzzle') || { position: new V3(0, 0.08, -0.3) }).position.clone(), parts: u.parts || {}, rest: new Map() };
      for (const k in h.parts) {
        const o = h.parts[k];
        if (o && o.isObject3D) h.rest.set(o, { pos: o.position.clone(), rot: o.rotation.clone(), scale: o.scale.clone(), visible: o.visible });
      }
      this._held.set(key, h);
    }
    h.def = weaponDef(s.id, s.upgraded);
    this._heldKey = key;
    this._restoreParts();
    p.setWeaponModel(h.holder);
    if (raise) this._raise = 0;
    this._pumpRacked = true;
    this._pumpT = 0;
    if (h.def.fire === 'custom') this._wonderCall('equip', s.id);
  }

  _holder() { return this._heldKey ? this._held.get(this._heldKey) : null; }

  // Double Vision (GDD §11): a faint cyan / magenta duplicate of the held weapon trails 3 cm to each side (they lag
  // the recoil a little, like a TV ghost). Built lazily per held model, additive, hidden without the perk.
  _updateGhosts(on) {
    const h = this._holder();
    for (const hh of this._held.values()) if (hh.ghosts && (hh !== h || !on)) for (const gm of hh.ghosts) gm.visible = false;
    if (!h || !on || !this.slots[this.current]) return;
    if (!h.ghosts) {
      const s = this.slots[this.current];
      h.ghosts = ['#5FF4FF', '#FF5FD2'].map((c) => {
        let gm;
        try { gm = buildModel(s.id, s.upgraded, s.signal, this.game); } catch (err) { this._warnOnce('ghost', err); return null; }
        // depth pushed 12 cm back along the view ray (same screen position): where it overlaps the real gun it fails
        // the depth test, so only the offset fringe around the gun's silhouette glows (the TV ghosting look)
        const mat = new THREE.MeshBasicMaterial({ color: c, transparent: true, opacity: 0.55, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false, fog: false });
        mat.onBeforeCompile = (sh) => {
          sh.vertexShader = sh.vertexShader.replace('#include <project_vertex>', GHOST_PUSH);
        };
        mat.customProgramCacheKey = () => 'wpn-ghost-push';
        gm.traverse((o) => {
          if (o.name === 'muzzle') o.name = 'muzzle_ghost';
          if (o.isMesh) { o.material = mat; o.castShadow = o.receiveShadow = false; }
        });
        gm.name = 'weaponGhost';
        h.holder.add(gm);
        return gm;
      }).filter(Boolean);
    }
    const t = this.game.time.now, sc = h.holder.scale.x || 1, R = this._recoil;
    h.ghosts.forEach((gm, i) => {
      const side = i ? -1 : 1;
      gm.visible = true;
      gm.position.copy(h.model.position);
      gm.position.x += side * (0.032 + 0.008 * Math.sin(t * 3.1 + i * 2)) / sc;
      gm.position.y += side * 0.006 / sc;
      gm.position.z += (-R.back * 0.55 + 0.004 * Math.sin(t * 2.3 + i)) / sc;
      gm.quaternion.copy(h.model.quaternion);
    });
  }

  _holster() {
    const s = this.slots[this.current];
    if (!s) return;
    const d = weaponDef(s.id, s.upgraded);
    if (d && d.fire === 'custom') this._wonderCall('holster', s.id);
  }

  _restoreParts() {
    const h = this._holder();
    if (!h) return;
    for (const [o, r] of h.rest) { o.position.copy(r.pos); o.rotation.copy(r.rot); o.scale.copy(r.scale); o.visible = r.visible; }
  }

  // ------------------------------------------------------------------------------------------ shootables
  registerShootable(entry) {
    if (!entry || !entry.id || typeof entry.raycast !== 'function') return null;
    const e = { blocksBullet: true, melee: true, bullets: true, onHit: () => {}, ...entry };
    this.shootables.set(e.id, e);
    return e;
  }

  unregisterShootable(id) {
    return this.shootables.delete(id && id.id ? id.id : id);
  }

  // Nearest shootable along a ray (kind 'bullets' | 'melee'); skip = entry to ignore (non-blocking pass-through).
  // blockingOnly: ignore pass-through entries (the crosshair aim point is where the bullet stops).
  _castShootables(o, d, maxDist, kind = 'bullets', skip = null, blockingOnly = false) {
    let best = null, bestD = maxDist;
    for (const e of this.shootables.values()) {
      if (e === skip || e[kind] === false || (blockingOnly && e.blocksBullet === false)) continue;
      let h = null;
      try { h = e.raycast(o, d, bestD); } catch (err) { this._warnOnce('shootable:' + e.id, err); }
      if (h && h.dist >= 0 && h.dist <= bestD) {
        bestD = h.dist;
        best = { entry: e, dist: h.dist, point: h.point ? _v4.copy(h.point) : _v4.copy(o).addScaledVector(d, h.dist) };
      }
    }
    if (best) best.point = best.point.clone();
    return best;
  }

  _hitShootable(e, point, dir, weaponId, upgraded, damage, melee, cause) {
    const info = { id: e.id, point: point.clone(), dir: dir.clone(), weaponId, upgraded: !!upgraded, melee: !!melee, damage, head: false, cause };
    try { e.onHit(info); } catch (err) { this._warnOnce('shootable-hit:' + e.id, err); }
    this.game.events.emit('weapon:hit_shootable', { ...info });
  }

  traceRay(origin, dir, maxDist = MAX_RANGE, { zombies = true, shootables = true, level = true, melee = false, blockingOnly = false } = {}) {
    const g = this.game;
    let best = null;
    if (level) {
      const w = g.level.col.raycast(origin, dir, maxDist);
      if (w) best = { kind: 'level', dist: w.dist, point: w.point.clone(), normal: w.normal.clone(), tag: w.tag };
    }
    const lim = best ? best.dist : maxDist;
    if (zombies && g.zombies && g.zombies.raycast) {
      const z = g.zombies.raycast(origin, dir, lim);
      if (z && z.dist <= lim) best = { kind: 'zombie', dist: z.dist, point: z.point.clone(), z: z.z, head: !!z.head, zone: z.zone || (z.head ? 'head' : 'torso') };
    }
    if (shootables && this.shootables.size) {
      const s = this._castShootables(origin, dir, best ? best.dist : maxDist, melee ? 'melee' : 'bullets', null, blockingOnly);
      if (s) best = { kind: 'shootable', dist: s.dist, point: s.point, entry: s.entry };
    }
    return best;
  }

  // zombies.damage + the points fallback (GDD §6.3) + hit info for listeners. Returns killed.
  damageZombie(z, amount, opts = {}) {
    const g = this.game;
    if (!z || !g.zombies || !g.zombies.damage) return false;
    const econ = g.economy;
    const before = econ ? econ.points : 0;
    this.hit = { weaponId: opts.weaponId || null, upgraded: !!opts.upgraded, signal: opts.signal || null, cause: opts.cause || 'bullet',
      primary: opts.primary !== false, head: !!opts.head };
    let killed = false;
    try {
      // hitmarker: weapons shows one hud.hitmarker per shot event itself (pass hitmarker:true to let zombies do it).
      // zone: always explicit, or zombies.damage would take the zone of this frame's crosshair ray on that zombie.
      const o = { hitmarker: false, ...opts };
      if (o.zone === undefined) o.zone = o.head ? 'head' : 'torso';
      killed = !!g.zombies.damage(z, amount, o);
    } finally {
      this.hit = null;
    }
    if (econ && opts.points !== false && econ.points === before) {
      const pts = T.points;
      if (!killed) econ.add(pts.hit, 'hit');
      else {
        const c = opts.cause;
        econ.add(c === 'melee' ? pts.melee : (c === 'grenade' || c === 'explosive') ? pts.special : opts.head ? pts.head : pts.kill, 'kill');
      }
    }
    return killed;
  }

  // ------------------------------------------------------------------------------------------ update
  update(dt) {
    const g = this.game, p = g.player, input = g.input;
    this._wrapAnimator();
    if (dt <= 0) return;
    const a = p.anim;
    a.recoil = Math.max(0, a.recoil - dt * 6);
    this._cool = Math.max(-dt, this._cool - dt);      // may dip one frame below 0: the carry keeps auto fire rates exact
    this._melee.cd = Math.max(0, this._melee.cd - dt);
    this._sinceSprint = p.sprinting ? 0 : this._sinceSprint + dt;
    this._raise = Math.min(1, this._raise + dt / 0.28);
    this._updateRecoil(dt);
    this._updateAim();
    this._updateProjectiles(dt);
    this._updateGhosts(this._eff().ghost);

    const control = p.alive && !p.downed && !p.controlLocked && g.state === 'playing';
    const fireDown = control && input.down('fire');
    const firePressed = control && input.pressed('fire');
    const fireReleased = this._fireHeld && !fireDown;
    this._fireHeld = fireDown;
    // a press made while the gun can't fire yet (sprint-to-fire, cooldown, raise) fires as soon as it can
    this._pressBuf = firePressed ? 0.22 : control ? Math.max(0, this._pressBuf - dt) : 0;

    // smoothed pose weights
    const k = 1 - Math.exp(-dt / 0.06);
    this._adsW += ((p.ads ? 1 : 0) - this._adsW) * k;
    this._sprintW += ((p.sprinting ? 1 : 0) - this._sprintW) * (1 - Math.exp(-dt / 0.09));
    const busy = this._melee.t >= 0 || this._nade.state !== 'none' || this._tele.t >= 0;
    this._busyW += ((busy ? 1 : 0) - this._busyW) * (1 - Math.exp(-dt / 0.05));

    this._updateSwap(dt);
    this._updateMelee(dt, control && input.pressed('melee'));
    this._updateGrenade(dt, control && input.down('grenade'), control && input.pressed('grenade'));
    this._updateTele(dt, control && input.pressed('tactical'));
    if (control && !busy && this._swap.t <= 0) this._readSwapInput(input);
    this._updateReload(dt, control && input.pressed('reload'), firePressed);
    this._updatePump(dt);

    const s = this.slots[this.current];
    const def = this.currentDef();
    this._updateSpread(dt, def, p);
    if (!s || !def) return;
    const blocked = !control || this._swap.t > 0 || busy || this._raise < 0.6;
    const ready = !blocked && !p.sprinting && this._sinceSprint >= Math.max(0, this._eff().sprintToFire) && !this.reloading;

    const press = this._pressBuf > 0;
    if (def.fire === 'custom') {
      this._updateWonder(dt, s, def, fireDown, press, fireReleased, ready, blocked);
      return;
    }
    if (this._autoReloadT >= 0) {
      this._autoReloadT -= dt;
      if (this._autoReloadT < 0 && s.mag === 0 && s.reserve > 0 && !this.reloading && !busy && this._swap.t <= 0) this._startReload(s, def);
    }
    if (p.sprinting || blocked) this._burst = 0;
    if (!ready || this._cool > 0) return;
    const pumpBusy = def.mode === 'pump' && !this._pumpRacked;
    if (pumpBusy) return;
    let pull = false;
    if (def.mode === 'auto') pull = fireDown || press;
    else if (def.mode === 'burst') { if (this._burst > 0) pull = true; else if (press) { this._burst = def.burst; pull = true; } }
    else pull = press;
    if (!pull) return;
    this._pressBuf = 0;
    if (s.mag <= 0) {
      this._burst = 0;
      if (s.reserve > 0) this._startReload(s, def);
      else if (press) this._dryFire(s);
      return;
    }
    this._fire(s, def);
  }

  lateUpdate(dt) {
    if (this.fx) this.fx.update(dt, this.game.camera);
  }

  _warnOnce(key, err) {
    if (this._warned.has(key)) return;
    this._warned.add(key);
    console.warn(`[weapons] ${key}`, err);
  }

  _wonderCall(fn, id, ctx = null) {
    const W = this.game.wonder;
    if (!W || typeof W[fn] !== 'function') return undefined;
    try { return W[fn](id, ctx || this._fillCtx(0)); } catch (err) { this._warnOnce('wonder.' + fn, err); return undefined; }
  }

  // ------------------------------------------------------------------------------------------ aim
  // Crosshair ray: camera position (last frame) + this frame's look direction; starts at the player's depth so
  // nothing between the camera and the hero is hit. aimPoint = nearest of level / zombies / shootables (80 m).
  _updateAim() {
    const g = this.game, p = g.player, cam = g.camera, cc = g.cam;
    const yaw = p.yaw + (cc && cc._kickY ? cc._kickY : 0);
    const pitch = clamp(p.pitch + (cc && cc._kickP ? cc._kickP : 0), -1.35, 1.25);
    this.aimDir.set(-Math.sin(yaw) * Math.cos(pitch), Math.sin(pitch), -Math.cos(yaw) * Math.cos(pitch));
    cam.getWorldPosition(_a);
    _b.copy(p.pos).setY(p.pos.y + 1.35);
    const t0 = Math.max(0, _c.subVectors(_b, _a).dot(this.aimDir));
    this.aimOrigin.copy(_a).addScaledVector(this.aimDir, t0);
    const hit = this.traceRay(this.aimOrigin, this.aimDir, MAX_RANGE, { blockingOnly: true });
    const dist = hit ? Math.max(0.05, hit.dist) : MAX_RANGE;
    this.aimPoint.copy(this.aimOrigin).addScaledVector(this.aimDir, dist);
    this.aimDist = dist;
    this.aimHit = hit;
  }

  _updateSpread(dt, def, p) {
    if (!def) { this.spread = 1; return; }
    this._bloom = Math.max(0, this._bloom - dt * 1.6);
    const base = lerp(def.spread[0], def.spread[1], this._adsW);
    const moving = Math.hypot(p.vel.x, p.vel.z) > 0.6 ? 1 : 0;
    const air = p.grounded ? 1 : 1.6;
    this.spread = base * air * (1 + this._bloom * 0.6 + moving * 0.12 * (1 - this._adsW));
  }

  // ------------------------------------------------------------------------------------------ swapping
  _readSwapInput(input) {
    if (this.slots.length < 2) return;
    let want = -1;
    if (input.pressed('weapon1')) want = 0;
    else if (input.pressed('weapon2')) want = 1;
    else if (input.pressed('weapon3')) want = 2;
    else if (input.pressed('weaponNext')) want = (this.current + 1) % this.slots.length; // gamepad Y
    else if (input.mouse.wheel) want = (this.current + (input.mouse.wheel > 0 ? 1 : this.slots.length - 1)) % this.slots.length;
    if (want >= 0 && want !== this.current && this.slots[want]) this.switchTo(want);
  }

  _updateSwap(dt) {
    const S = this._swap;
    if (S.t <= 0) return;
    S.t += dt;
    if (!S.swapped && S.t >= S.total * 0.45) {
      S.swapped = true;
      if (this.slots[S.to]) this._equip(S.to, false);
      this.game.audio.play('reload_mag', { vol: 0.35, rate: 1.4 });
    }
    if (S.t >= S.total) { S.t = 0; this.swapping = false; }
  }

  // ------------------------------------------------------------------------------------------ firing
  _dryFire(s) {
    this._cool = 0.28;
    this._recoil.vr += 1.2;
    this.game.events.emit('weapon:empty', { weaponId: s.id });
  }

  _fire(s, def) {
    const g = this.game, p = g.player;
    const eff = this._eff();
    const rate = Math.max(0.1, eff.fireRate);
    s.mag--;
    s.fired = (s.fired || 0) + 1;
    const interval = 60 / def.rpm / rate;
    // held auto / mid-burst: keep the time already overdue this frame (frame-rate independent rpm)
    const carry = (def.mode === 'auto' && this._fireHeld) || (def.mode === 'burst' && this._burst < def.burst) ? Math.min(0, this._cool) : 0;
    if (def.mode === 'burst') {
      this._burst--;
      this._cool = (this._burst > 0 ? interval : def.burstGap / rate) + carry;
    } else if (def.mode === 'pump') {
      this._cool = def.pumpTime / rate;
      this._pumpT = 0;
      this._pumpRacked = false;
      this._pumpDur = Math.max(0.3, def.pumpTime / rate - 0.12);
    } else {
      this._cool = interval + carry;
    }
    this._bloom = Math.min(1, this._bloom + (def.mode === 'auto' ? 0.12 : 0.3));

    // muzzle -> crosshair point, with a muzzle obstruction check (gun poking through a wall)
    p.muzzle(_o);
    const muzzle = _v1.copy(_o);
    _b.copy(p.pos).setY(p.pos.y + 1.3);
    let origin = muzzle;
    const blockD = _c.subVectors(muzzle, _b).length();
    if (blockD > 1e-3) {
      _c.divideScalar(blockD);
      const w = g.level.col.raycast(_b, _c, blockD);
      if (w) origin = _v2.copy(w.point).addScaledVector(_c, -0.05);
    }
    _d.subVectors(this.aimPoint, origin);
    const toAim = _d.length();
    if (toAim < 0.4 || this.aimDist < 0.6) _d.copy(this.aimDir); else _d.divideScalar(toAim);
    const baseDir = _v3.copy(_d);
    _r.crossVectors(baseDir, UP);
    if (_r.lengthSq() < 1e-6) _r.set(1, 0, 0);
    _r.normalize();
    _u.crossVectors(_r, baseDir).normalize();

    const pellets = def.pellets || 1;
    const spreadRad = THREE.MathUtils.degToRad(this.spread);
    const ghost = eff.ghost;
    const shot = this._beginShot(s, def);
    const style = def.tracer || {};
    const col = this._tracerColor(s, def);
    for (let i = 0; i < pellets; i++) {
      let rr, phi;
      if (pellets > 1) {
        phi = (i / pellets) * Math.PI * 2 + g.rand() * 0.7;
        rr = i === 0 ? g.rand() * 0.25 : 0.45 + 0.55 * g.rand();
      } else {
        phi = g.rand() * Math.PI * 2;
        rr = Math.sqrt(g.rand());
      }
      const t = Math.tan(spreadRad) * rr;
      _n.copy(baseDir).addScaledVector(_r, Math.cos(phi) * t).addScaledVector(_u, Math.sin(phi) * t).normalize();
      const end = this._traceBullet(origin, _n, def, s, shot, ghost);
      this.fx.streak(muzzle, end, style, col, pellets > 1 ? i * 0.004 : 0);
      if (style.style === 'scratch') this.fx.streak(muzzle, end, { ...style, width: style.width * 0.5, len: style.len * 0.6 }, '#FFD8A0', 0.01, _a.copy(_u).multiplyScalar(0.03));
      if (ghost) {
        this.fx.streak(muzzle, end, style, '#5FF4FF', 0.012, _a.copy(_r).multiplyScalar(0.035));
        this.fx.streak(muzzle, end, style, '#FF5FD2', 0.018, _a.copy(_r).multiplyScalar(-0.035));
      }
      if (style.style === 'stars') {
        for (let k = 0; k < 2; k++) {
          _a.copy(muzzle).lerp(end, 0.25 + g.rand() * 0.7);
          g.fx.burst(_a, { shape: 'star', count: 1, speed: 0.6, size: 0.07, life: 0.45, gravity: 0.5, colors: [PAL.marqueeGold, '#FFF3B0'] });
        }
      }
    }
    this._endShot(shot, s, def);

    // feel: muzzle, smoke, casing, recoil, camera
    this._muzzleFX(s, def, muzzle, baseDir);
    this._kick(def, 1);
    if (def.eject === 'brass') this._eject('brass', 0.8);
    p.anim.recoil = 1;
    g.events.emit('weapon:fire', { weaponId: s.id, upgraded: !!s.upgraded });
    if (s.mag === 0 && s.reserve > 0) this._autoReloadT = def.mode === 'pump' ? 0.3 : 0.18;
  }

  _tracerColor(s, def) {
    if (s.upgraded && s.signal && SIGNAL_COLORS[s.signal]) return SIGNAL_COLORS[s.signal];
    if (s.upgraded && !def.tracer?.color) return PAL.perpetua;
    return def.tracer ? def.tracer.color : '#FFE9A8';
  }

  _kick(def, mul = 1) {
    const g = this.game;
    const ads = this._adsW;
    const kick = def.kick || [0.02, 0.005];
    if (g.cam && g.cam.kick) g.cam.kick(kick[0] * mul * (1 - 0.35 * ads), (g.rand() - 0.5) * 2 * kick[1] * mul);
    if (g.cam && g.cam.shake && def.shake) g.cam.shake(def.shake * mul * (1 - 0.4 * ads), 0.16);
    const rc = def.recoil || [0.04, 0.15];
    const R = this._recoil;
    R.vb += rc[0] * 30 * mul;
    R.vr += rc[1] * 28 * mul;
    R.vroll += (g.rand() - 0.5) * rc[1] * 18 * mul;
    const an = this.game.player.animator;
    if (an && an.kick) an.kick(Math.min(0.22, rc[0] * 1.5) * mul);
  }

  _updateRecoil(dt) {
    const R = this._recoil;
    const k = 420, d = 26;
    const n = Math.max(1, Math.ceil(dt / (1 / 120))), h = dt / n;
    for (let i = 0; i < n; i++) {
      R.vb += (-k * R.back - d * R.vb) * h; R.back += R.vb * h;
      R.vr += (-k * 0.8 * R.rise - d * R.vr) * h; R.rise += R.vr * h;
      R.vroll += (-k * R.roll - d * R.vroll) * h; R.roll += R.vroll * h;
    }
  }

  _muzzleFX(s, def, pos, dir) {
    const g = this.game;
    const f = def.flash || { size: 0.45, color: '#FFD27A' };
    const up = !!s.upgraded;
    const sig = up && s.signal ? SIGNAL_COLORS[s.signal] : null;
    const color = sig || f.color;
    this.fx.flash(pos, dir, f.size * (0.9 + g.rand() * 0.25), color, def.mode === 'auto' ? 0.045 : 0.065);
    if (up) {
      this.fx.ring(pos, dir, f.size * 0.18, f.size * 0.75, 0.2, '#ffffff', !sig);
      if (sig) this.fx.ring(pos, dir, f.size * 0.12, f.size * 0.55, 0.16, sig, false);
    }
    if (s.id === 'revolver_38' && up) {
      // SPECIAL REPORT: the muzzle is a flashbulb pop
      this.fx.pop(pos, 0.9, '#EAF6FF', 0.1);
      g.fx.burst(pos, { shape: 'star', count: 3, speed: 2, size: 0.07, life: 0.4, colors: ['#FFFFFF', '#BFE8FF'] });
    }
    g.fx.flashLight(pos, color, def.pellets ? 9 : 6, 0.06);
    const smoke = def.smoke || 0;
    const nSmoke = Math.floor(smoke) + (g.rand() < smoke % 1 ? 1 : 0);
    if (nSmoke) g.fx.burst(pos, { shape: 'puff', count: nSmoke, size: def.pellets ? 0.13 : 0.08, speed: 0.9, life: 0.55, gravity: -1.2, drag: 3,
      dir, cone: 0.5, colors: ['#EDE6DA', '#D8CFC2'] });
  }

  _eject(kind, speed = 1) {
    const g = this.game, h = this._holder();
    if (!h) return;
    h.model.updateWorldMatrix(true, false);
    _a.set(0.03, h.muzzle.y * 0.9, h.butt.z * 0.1 - 0.06);
    h.model.localToWorld(_a);
    h.model.getWorldQuaternion(_q1);
    _b.set(1.6 + g.rand() * 0.8, 1.6 + g.rand() * 1.2, 0.4 + g.rand() * 0.6).multiplyScalar(speed).applyQuaternion(_q1);
    const pv = g.player.vel;
    _b.x += pv.x * 0.8; _b.z += pv.z * 0.8;
    this.fx.eject(kind, _a, _b);
  }

  // Shot event: aggregates damage per zombie (pellets / pierce / splash / ghost) so each zombie is damaged once.
  _beginShot(s, def) {
    for (const v of this._agg.values()) this._aggPool.push(v);
    this._agg.clear();
    return { s, def, hits: 0, kills: 0, anyHead: false, splashes: 0 };
  }

  // dmg is already multiplied by the ray's zone multiplier (see _zoneMulOf); zone = the ray's zone name.
  _aggAdd(z, dmg, head, point, dir, cause, zone = 'torso') {
    let a = this._agg.get(z);
    if (!a) {
      a = this._aggPool.pop() || { dmg: 0, head: 0, body: 0, point: new V3(), dir: new V3(), cause: 'bullet', n: 0, zones: new Map() };
      a.dmg = 0; a.head = 0; a.body = 0; a.n = 0; a.cause = cause;
      a.zones.clear();
      a.point.copy(point); a.dir.copy(dir);
      this._agg.set(z, a);
    }
    a.dmg += dmg;
    a.zones.set(zone, (a.zones.get(zone) || 0) + dmg);
    if (cause === 'bullet') { if (head) a.head++; else a.body++; }
    if (cause === 'bullet' && a.cause !== 'bullet') { a.cause = 'bullet'; a.point.copy(point); }
    a.n++;
  }

  // Zone multiplier of the zombie raycast hit zh (zombies.raycast leaves it on the zombie for this frame).
  _zoneMulOf(zh) {
    if (Number.isFinite(zh.mul)) return zh.mul;
    const z = zh.z;
    if (z && z._rayFrame === this.game.time.frame && Number.isFinite(z._rayMul)) return z._rayMul;
    return this._explicitZoneMul(z, zh.zone);
  }

  // The multiplier zombies.damage applies for an explicitly passed zone (limb 0.8, else z.hitZones, else 1).
  _explicitZoneMul(z, zone) {
    if (zone === 'limb') return 0.8;
    if (z && Array.isArray(z.hitZones)) for (const hz of z.hitZones) if (hz.zone === zone) return Number.isFinite(hz.mul) ? hz.mul : 1;
    return 1;
  }

  _endShot(shot, s, def) {
    const g = this.game;
    let anyHead = false, anyKill = false, hits = 0;
    const upgraded = !!s.upgraded;
    for (const [z, a] of this._agg) {
      const head = a.head > 0 && a.head >= a.body;
      const knock = def.pellets ? 0.25 * a.n : 0.5;
      // dominant zone (most damage); divide by what zombies.damage multiplies for it -> total = sum(ray dmg × zone mul)
      let zone = head ? 'head' : 'torso', zd = -1;
      for (const [k, v] of a.zones) if (v > zd) { zd = v; zone = k; }
      if (head) zone = a.zones.has('head') ? 'head' : zone;
      const zm = this._explicitZoneMul(z, zone);
      if (!(zm > 0)) continue;
      const killed = this.damageZombie(z, a.dmg / zm, { head, zone, weaponId: s.id, point: a.point, dir: a.dir, knockback: knock, cause: a.cause,
        upgraded, signal: s.signal || null, pellets: a.n, launch: def.launch || 0 });
      hits++;
      if (head) anyHead = true;
      if (killed) {
        anyKill = true;
        if (def.launch && g.fx) g.fx.burst(a.point, { shape: 'star', count: 4, speed: 3, size: 0.1, colors: [PAL.marqueeGold, '#FFF3B0'] });
      }
      // hit read: white pop + sparks; head = gold stars
      this.fx.pop(a.point, head ? 0.42 : 0.3, head ? '#FFE27A' : '#FFFFFF', 0.07);
      g.fx.burst(a.point, { shape: 'spark', count: head ? 7 : 4, dir: _a.copy(a.dir).negate(), cone: 0.9, speed: 5, life: 0.2, size: 0.035 });
      if (head) g.fx.burst(a.point, { shape: 'star', count: 2, speed: 2.2, size: 0.08, life: 0.5 });
      if (def.pageHits) g.fx.burst(a.point, { shape: 'confetti', count: 7, speed: 3, size: 0.11, life: 1.2, colors: ['#F4F1E8', '#E6DCCB', '#FFFFFF', '#D9D2C2'], dir: _a, cone: 1.3 });
    }
    if (hits && g.hud && g.hud.hitmarker) g.hud.hitmarker(anyHead, anyKill);
    const L = this.lastShot;
    L.weaponId = s.id; L.upgraded = upgraded; L.signal = s.signal || null; L.time = g.time.now; L.hits = hits; L.kills = anyKill ? 1 : 0;
    for (const v of this._agg.values()) this._aggPool.push(v);
    this._agg.clear();
  }

  // One bullet / pellet: zombies (pierce), shootables, level. Returns the end point (for the tracer).
  _traceBullet(origin, dir, def, s, shot, ghost) {
    const g = this.game, Z = g.zombies;
    const wall = g.level.col.raycast(origin, dir, MAX_RANGE);
    const maxD = wall ? wall.dist : MAX_RANGE;
    let dmg = def.dmg * (g.player.mods.damage || 1) * (ghost ? 1 + GHOST_MUL : 1);
    let pierce = def.pierce || 0;
    const hitSet = this._hitSet;
    hitSet.clear();
    let from = 0, skipEntry = null;
    const pos = _v4;
    for (let iter = 0; iter < 12; iter++) {
      _a.copy(origin).addScaledVector(dir, from);
      const left = maxD - from;
      if (left <= 0) break;
      const zh = Z && Z.raycast ? Z.raycast(_a, dir, left) : null;
      const zd = zh ? from + zh.dist : Infinity;
      const sh = this.shootables.size ? this._castShootables(_a, dir, Math.min(left, zh ? zh.dist : left), 'bullets', skipEntry) : null;
      const sd = sh ? from + sh.dist : Infinity;
      if (sd <= zd && sh) {
        this._hitShootable(sh.entry, sh.point, dir, s.id, s.upgraded, dmg * this._falloff(def, sd), false, 'bullet');
        this.fx.pop(sh.point, 0.22, '#FFFFFF', 0.06);
        if (sh.entry.blocksBullet !== false) { this._bulletEnd(sh.point, s, def, shot, null); return pos.copy(sh.point); }
        skipEntry = sh.entry;
        from = sd + 0.02;
        continue;
      }
      if (zh) {
        if (hitSet.has(zh.z)) { from = zd + 0.08; continue; }
        hitSet.add(zh.z);
        const head = !!zh.head;
        const d = dmg * this._falloff(def, zd) * (head ? def.head : 1) * this._zoneMulOf(zh);
        this._aggAdd(zh.z, d, head, zh.point, dir, 'bullet', zh.zone || (head ? 'head' : 'torso'));
        if (pierce > 0) {
          pierce--;
          dmg *= PIERCE_MUL;
          from = zd + 0.08;
          continue;
        }
        this._bulletEnd(zh.point, s, def, shot, zh.z);
        return pos.copy(zh.point);
      }
      break;
    }
    if (wall) {
      g.fx.impact(wall.point, wall.normal, this._surfaceKind(wall));
      this._bulletEnd(wall.point, s, def, shot, null);
      return pos.copy(wall.point);
    }
    return pos.copy(origin).addScaledVector(dir, Math.min(MAX_RANGE, 60));
  }

  _falloff(def, dist) {
    const f = def.falloff;
    if (!f) return 1;
    const k = clamp((dist - f[0]) / Math.max(1e-3, f[1] - f[0]), 0, 1);
    return lerp(1, f[2], k);
  }

  _surfaceKind(hit) {
    const tag = hit.tag;
    if (tag === 'glass') return 'glass';
    if (tag === 'door' || tag === 'platform' || tag === 'prop') return 'wood';
    if (tag === 'rail' || tag === 'lattice' || tag === 'fence') return 'metal';
    if (tag === 'floor' && this.game.level.surfaceAt) {
      const s = this.game.level.surfaceAt(hit.point.x, hit.point.z, hit.point.y);
      if (s === 'wood') return 'wood';
      if (s === 'metal') return 'metal';
    }
    return 'wall';
  }

  // Bullet end effects: SPECIAL REPORT flashbulb splash, 24-HOUR MARATHON 13th-round explosive.
  _bulletEnd(point, s, def, shot, directZ) {
    if (def.splash && def.splash.dmg) this._splash(point, def.splash.dmg * (this.game.player.mods.damage || 1), def.splash.r, def.splash.min, directZ, 'splash', '#EAF6FF');
    if (def.every13 && s.fired % 13 === 0 && !shot.every13) {
      shot.every13 = true;
      this._splash(point, def.every13.dmg * (this.game.player.mods.damage || 1), def.every13.r, 1, null, 'explosive', '#FFE08A');
    }
  }

  _splash(point, dmg, r, minMul, skipZ, cause, color) {
    const g = this.game;
    _hitList.length = 0;
    const list = g.zombies && g.zombies.inRadius ? g.zombies.inRadius(point, r + 0.6, _hitList) : [];
    for (const z of list) {
      if (z === skipZ) continue;
      _a.copy(z.pos).setY(z.pos.y + (z.height || 1.7) * 0.5);
      const d = Math.max(0, _a.distanceTo(point) - (z.radius || 0.35));
      if (d > r) continue;
      this._aggAdd(z, dmg * lerp(1, minMul, d / r), false, _a, _b.subVectors(_a, point).normalize(), cause);
    }
    this.fx.pop(point, r * 0.9, color, 0.12);
    this.fx.ring(point, _a.subVectors(this.game.camera.position, point).normalize(), 0.15, r * 0.7, 0.22, color, false);
    g.fx.burst(point, { shape: 'star', count: 6, speed: 3.5, size: 0.08, life: 0.5, colors: ['#FFFFFF', color] });
    g.fx.flashLight(point, color, 10, 0.12);
    g.audio.play('studio_flash', { pos: point, vol: 0.8 });
  }

  // ------------------------------------------------------------------------------------------ pump action
  _updatePump(dt) {
    if (this._pumpRacked) return;
    const def = this.currentDef();
    if (!def || def.mode !== 'pump') { this._pumpRacked = true; return; }
    const prev = this._pumpT;
    this._pumpT += dt / (this._pumpDur || 0.6);
    if (prev < 0.25 && this._pumpT >= 0.25) {
      this.game.audio.play('wpn_pump_rack', { vol: 0.9 });
      this._eject('shell', 0.9);
    }
    if (this._pumpT >= 1) { this._pumpT = 1; this._pumpRacked = true; }
  }

  // ------------------------------------------------------------------------------------------ reload
  // Effective weapon modifiers: player.mods as written by perks / power-ups, falling back to the perk itself when a
  // perk is owned but its mod was left untouched (Double Vision x1.2 rate + ghost bullets, Jump Cut x0.5 reload / swap,
  // Roller Boogie 0.10 s sprint-to-fire), so either convention works and nothing applies twice.
  _eff() {
    const g = this.game, m = g.player.mods, E = this._effMods || (this._effMods = {});
    const has = (id) => !!(g.perks && typeof g.perks.has === 'function' && g.perks.has(id));
    const TP = T.perks;
    E.fireRate = Number.isFinite(m.fireRate) && m.fireRate > 0 ? m.fireRate : 1;
    if (E.fireRate === 1 && has('double_vision')) E.fireRate = TP.doubleVision.fireRate;
    E.ghost = !!m.ghostBullets || has('double_vision');
    E.reload = timeMul(m.reloadSpeed);
    if (E.reload === 1 && has('jump_cut')) E.reload = TP.jumpCut.reload;
    E.swap = timeMul(m.swapSpeed);
    if (E.swap === 1 && has('jump_cut')) E.swap = TP.jumpCut.swap;
    E.sprintToFire = Number.isFinite(m.sprintToFire) ? m.sprintToFire : P.sprintToFire;
    if (E.sprintToFire === P.sprintToFire && has('roller_boogie')) E.sprintToFire = TP.roller.sprintToFire;
    return E;
  }

  _reloadAllowedWhileSprinting() {
    const g = this.game, m = g.player.mods;
    return !!(m.reloadWhileSprinting || m.unlimitedSprint || m.unlimitedStamina || (g.perks && g.perks.has && g.perks.has('roller_boogie')));
  }

  _updateReload(dt, pressedR, firePressed) {
    const g = this.game, p = g.player;
    const s = this.slots[this.current];
    const def = this.currentDef();
    if (!s || !def) return;
    if (!this.reloading) {
      if (pressedR && s.mag < def.mag && s.reserve > 0 && this._swap.t <= 0 && this._melee.t < 0 && this._nade.state === 'none') {
        if (def.fire === 'custom' && this._fireHeld) return;
        this._startReload(s, def);
      }
      return;
    }
    if (this._reload.wonder) { this._syncWonderReload(s, def); return; }
    // interrupt a shell-by-shell reload by firing
    if (def.reloadKind === 'shell' && firePressed && s.mag > 0) { this.cancelReload(); this._pumpRacked = true; return; }
    if (p.sprinting && !this._reloadAllowedWhileSprinting()) return; // paused while sprinting
    const R = this._reload;
    const mul = this._eff().reload;
    R.t += dt;
    if (def.reloadKind === 'shell') {
      const start = def.reload * mul, per = def.shellReload * mul;
      if (R.t >= start) {
        const k = Math.floor((R.t - start) / per);
        while (R.shells < k && s.mag < def.mag && s.reserve > 0) {
          s.mag++; s.reserve--; R.shells++;
          g.audio.play(def.reloadCue || 'reload_shell', { vol: 0.9, rate: 0.95 + g.rand() * 0.1 });
        }
        if (s.mag >= def.mag || s.reserve <= 0) {
          if (R.shells > 0 && (R.t - start) - R.shells * per > -per * 0.05) this._finishReload(s, def, false);
        }
      }
      p.anim.reload = clamp(R.t / R.total, 0, 0.999);
      this._jumpCutSnips(R.t / R.total);
      return;
    }
    const u = R.t / R.total;
    p.anim.reload = Math.min(0.999, u);
    this._reloadParts(def, u);
    this._reloadCues(def, u);
    this._jumpCutSnips(u);
    if (u >= 1) this._finishReload(s, def, true);
  }

  _startReload(s, def) {
    if (this.reloading || s.mag >= def.mag || s.reserve <= 0) return false;
    const g = this.game, p = g.player;
    const mul = this._eff().reload;
    const R = this._reload;
    R.t = 0; R.shells = 0; R.cues = 0; R.snips = 0; R.kind = def.reloadKind; R.wonder = false;
    R.total = def.reloadKind === 'shell' ? (def.reload + def.shellReload * (def.mag - s.mag)) * mul : def.reload * mul;
    if (def.fire === 'custom') {
      const ctx = this._fillCtx(0);
      ctx.duration = R.total;
      const r = this._wonderCall('reload', s.id, ctx);
      if (r === false || r === 0) return false;
      if (typeof r === 'number' && r > 0) {
        // game.wonder owns this reload (timing, ammo, weapon:reload, cues, part animation); weapons mirrors it for the pose
        R.wonder = true;
        R.total = r;
        this.reloading = true;
        this._autoReloadT = -1;
        this._burst = 0;
        return true;
      }
    }
    this.reloading = true;
    this._autoReloadT = -1;
    this._burst = 0;
    g.events.emit('weapon:reload', { weaponId: s.id });
    if (def.reloadKind === 'speedloader') g.audio.play('reload_speedloader', { vol: 0.5, rate: 1.3 });
    return true;
  }

  // Mirrors a reload run by game.wonder (started by us or by the wonder system on an empty trigger pull).
  _syncWonderReload(s, def) {
    const W = this.game.wonder, R = this._reload;
    const on = !!(W && W.reloading && W.reloadId === s.id);
    if (on) {
      if (!this.reloading || !R.wonder) {
        this.reloading = true;
        R.wonder = true;
        R.t = 0; R.cues = 0; R.snips = 0; R.kind = def.reloadKind;
        R.total = (def.reload || 1) * this._eff().reload;
        this._autoReloadT = -1;
      }
      const k = clamp(Number.isFinite(W.reloadProgress) ? W.reloadProgress : R.t / R.total, 0, 1);
      R.t = k * R.total;
      this._jumpCutSnips(k);
    } else if (this.reloading && R.wonder) {
      this.reloading = false;
      R.wonder = false;
      R.t = 0;
      this._raise = Math.min(this._raise, 0.75);
    }
  }

  _finishReload(s, def, full) {
    if (full) {
      const n = Math.min(def.mag - s.mag, s.reserve);
      s.mag += n;
      s.reserve -= n;
    }
    this.cancelReload();
    this._pumpRacked = true;
    this._raise = Math.min(this._raise, 0.75);
  }

  // Sounds at the right beats of each reload kind.
  _reloadCues(def, u) {
    const g = this.game, R = this._reload;
    const beats = { mag: [0.18, 0.66], belt: [0.12, 0.45, 0.8], speedloader: [0.2, 0.62], battery: [0.15, 0.62], reel: [0.2, 0.7], goo: [0.2, 0.68] }[def.reloadKind] || [0.5];
    while (R.cues < beats.length && u >= beats[R.cues]) {
      const i = R.cues++;
      const cue = def.reloadCue || 'reload_mag';
      g.audio.play(cue, { vol: 0.9, rate: i === 0 ? 0.9 : 1.1 });
      if (def.reloadKind === 'speedloader' && i === 0) for (let k = 0; k < 6; k++) this._ejectDrum(k);
      if (def.reloadKind === 'mag' && i === 0) this._dropMagFX();
    }
  }

  _ejectDrum(k) {
    const g = this.game, h = this._holder();
    if (!h) return;
    h.model.updateWorldMatrix(true, false);
    _a.set(-0.04, 0.09, -0.05 + (k % 3) * 0.01);
    h.model.localToWorld(_a);
    _b.set((g.rand() - 0.5) * 1.2, -0.5 - g.rand(), (g.rand() - 0.5) * 1.2);
    this.fx.eject('brass', _a, _b);
  }

  _dropMagFX() {
    const g = this.game, h = this._holder();
    if (!h) return;
    h.model.updateWorldMatrix(true, false);
    _a.set(0, -0.12, -0.08);
    h.model.localToWorld(_a);
    g.fx.burst(_a, { shape: 'puff', count: 2, size: 0.05, speed: 0.4, life: 0.3, colors: ['#D8CFC2'] });
  }

  // Jump Cut Coffee: reloads visibly skip frames (a white splice flash + "snip-tk").
  _jumpCutSnips(u) {
    const g = this.game;
    if (!g.perks || !g.perks.has || !g.perks.has('jump_cut')) return;
    const R = this._reload;
    const at = [0.3, 0.62];
    while (R.snips < at.length && u >= at[R.snips]) {
      R.snips++;
      g.audio.play('jumpcut_snip', { vol: 0.8 });
      const h = this._holder();
      if (!h) continue;
      h.model.updateWorldMatrix(true, false);
      _a.set(-0.12, 0.18, -0.1); _b.set(0.12, -0.12, -0.1);
      h.model.localToWorld(_a); h.model.localToWorld(_b);
      this.fx.bar(_a, _b, 0.012, '#FFFFFF', 0.07);
      this.fx.pop(h.model.getWorldPosition(_c), 0.35, '#FFFFFF', 0.05);
    }
  }

  // Part animation for the current reload (u 0..1): mag drop/insert, drum swing, cover, battery, reels, goo.
  _reloadParts(def, u) {
    const h = this._holder();
    if (!h) return;
    const P2 = h.parts;
    const rest = (o) => h.rest.get(o);
    const inOut = (a, b, c, d) => smooth(a, b, u) * (1 - smooth(c, d, u));
    if (P2.mag && rest(P2.mag)) {
      const r = rest(P2.mag);
      const out = smooth(0.15, 0.3, u), back = smooth(0.52, 0.72, u);
      const drop = out < 1 ? out * 0.3 : (1 - back) * 0.3;
      P2.mag.position.copy(r.pos);
      P2.mag.position.y -= drop;
      P2.mag.visible = !(u > 0.3 && u < 0.52);
    }
    if (P2.drum && rest(P2.drum)) {
      const r = rest(P2.drum), k = inOut(0.08, 0.2, 0.74, 0.84);
      P2.drum.position.copy(r.pos);
      P2.drum.position.x -= 0.045 * k;
      P2.drum.rotation.z = r.rot.z + (u > 0.74 ? (u - 0.74) * 40 : 0);
    }
    if (P2.cover && rest(P2.cover)) { const r = rest(P2.cover); P2.cover.rotation.x = r.rot.x - 1.1 * inOut(0.05, 0.16, 0.82, 0.92); }
    if (P2.battery && rest(P2.battery)) {
      const r = rest(P2.battery), k = inOut(0.08, 0.16, 0.55, 0.7);
      P2.battery.position.copy(r.pos); P2.battery.position.z += 0.09 * k; P2.battery.position.y += 0.03 * Math.sin(k * Math.PI);
      P2.battery.visible = !(u > 0.3 && u < 0.5);
    }
    if (P2.goo && rest(P2.goo)) { const r = rest(P2.goo), k = inOut(0.1, 0.25, 0.6, 0.75); P2.goo.position.copy(r.pos); P2.goo.position.y += 0.12 * k; P2.goo.visible = !(u > 0.3 && u < 0.5); }
    for (const nm of ['reelL', 'reelR']) if (P2[nm] && rest(P2[nm])) { const r = rest(P2[nm]); P2[nm].rotation.y = r.rot.y + u * 30; }
  }

  // ------------------------------------------------------------------------------------------ wonder weapons
  _fillCtx(dt) {
    const g = this.game, p = g.player;
    const c = this._ctx;
    const s = this.slots[this.current] || null;
    const h = this._holder();
    c.def = s ? weaponDef(s.id, s.upgraded) : null;
    c.upgraded = !!(s && s.upgraded);
    c.signal = s ? s.signal || null : null;
    c.slot = s;
    c.origin.copy(this.aimOrigin);
    c.dir.copy(this.aimDir);
    p.muzzle(c.muzzle);
    c.aimPoint.copy(this.aimPoint);
    c.aimDist = this.aimDist;
    c.ads = !!p.ads;
    c.dt = dt;
    c.model = h ? h.model : null;
    c.time = g.time.now;
    return c;
  }

  // Wonder weapons: game.wonder.fire every frame while held (not while swapping / meleeing / throwing / raising).
  // The trigger reaches it only when the weapon may fire (not sprinting, sprint-to-fire elapsed, not reloading);
  // a press made while not ready is buffered (0.22 s). Wonder owns ammo, empty-mag reloads, dry fire and its
  // own weapon:fire / weapon:reload events (the header of src/game/wonder.js); weapons mirrors its reload for the
  // pose and adds the held-model recoil spring.
  _updateWonder(dt, s, def, down, pressed, released, ready, blocked) {
    const g = this.game, W = g.wonder;
    const hasW = !!(W && typeof W.fire === 'function');
    if (hasW) this._syncWonderReload(s, def);
    if (hasW) {
      if (blocked) return;
      const ctx = this._fillCtx(dt);
      const pr = ready && pressed;
      ctx.triggerDown = ready && (down || pr);
      ctx.triggerPressed = pr;
      ctx.triggerReleased = released;
      ctx.ready = ready;
      if (pr) this._pressBuf = 0;
      this._inWonder = true;
      this._wonderEmitted = false;
      let r = null;
      try { r = W.fire(s.id, ctx); } catch (err) { this._warnOnce('wonder.fire', err); } finally { this._inWonder = false; }
      if (r) this._wonderFired(s, def, r, this._wonderEmitted);
      this._syncWonderReload(s, def);
      // an emptied battery / reel / cartridge reloads by itself shortly after the trigger is let go (like the guns)
      if (s.mag === 0 && s.reserve > 0 && !this.reloading && !down && ready) {
        this._autoReloadT = this._autoReloadT < 0 ? 0.35 : this._autoReloadT - dt;
        if (this._autoReloadT <= 0) { this._autoReloadT = -1; this._startReload(s, def); }
      } else if (s.mag > 0) this._autoReloadT = -1;
      return;
    }
    // Fallback while game.wonder is not installed: a plain hitscan zap (weapons runs its reload).
    if (this._autoReloadT >= 0) {
      this._autoReloadT -= dt;
      if (this._autoReloadT < 0 && s.mag === 0 && s.reserve > 0 && !this.reloading && !down) this._startReload(s, def);
    }
    if (!ready || this._cool > 0 || !pressed) return;
    this._pressBuf = 0;
    if (s.mag <= 0) { if (s.reserve > 0) this._startReload(s, def); else this._dryFire(s); return; }
    this._warnOnce('wonder-missing', 'game.wonder is not installed: wonder weapons use a hitscan fallback');
    const fb = { ...def, pellets: 1, pierce: 2, falloff: null, head: 1, dmg: def.dmg || 1000, spread: [2, 1], tracer: { color: '#9CFF57', width: 0.06, len: 4, speed: 150 }, flash: { size: 0.6, color: '#9CFF57' }, mode: 'semi', smoke: 0, eject: null };
    this._fire(s, fb);
  }

  // r: true | { kick, shake, recoil, noEvent }. emitted: the wonder system already emitted weapon:fire (and kicked
  // the camera itself), so only the held-model spring, a touch of shake and the crosshair bloom are added here.
  _wonderFired(s, def, r, emitted = false) {
    const g = this.game;
    const o = typeof r === 'object' ? r : {};
    const mul = o.kick ?? 1;
    if (emitted) {
      const rc = o.recoil ?? def.recoil ?? [0.04, 0.15];
      const R = this._recoil;
      R.vb += rc[0] * 30 * mul;
      R.vr += rc[1] * 22 * mul;
      R.vroll += (g.rand() - 0.5) * rc[1] * 14 * mul;
      const sh = o.shake ?? def.shake;
      if (sh && g.cam && g.cam.shake) g.cam.shake(sh * 0.6 * mul * (1 - 0.4 * this._adsW), 0.16);
    } else {
      this._kick({ ...def, shake: o.shake ?? def.shake, recoil: o.recoil ?? def.recoil }, mul);
      if (!o.noEvent) g.events.emit('weapon:fire', { weaponId: s.id, upgraded: !!s.upgraded });
    }
    g.player.anim.recoil = 1;
    this._bloom = Math.min(1, this._bloom + 0.3);
  }

  // ------------------------------------------------------------------------------------------ melee
  _updateMelee(dt, pressed) {
    const g = this.game, p = g.player, M = this._melee, D = WEAPON_DEFS.melee;
    if (M.t < 0) {
      if (!pressed || M.cd > 0 || this._nade.state !== 'none' || this._tele.t >= 0 || this._swap.t > 0) return;
      this.cancelReload();
      this._burst = 0;
      M.t = 0;
      M.hit = false;
      M.cd = D.cd;
      M.target = null;
      // lunge toward the zombie under the crosshair (GDD §6.2: up to 2.5 m)
      const z = this._meleeTarget(D.reach + D.lunge);
      if (z) {
        const dx = z.pos.x - p.pos.x, dz = z.pos.z - p.pos.z, dist = Math.hypot(dx, dz);
        const need = clamp(dist - (z.radius || 0.35) - 0.55, 0, D.lunge);
        if (need > 0.15 && p.knock) p.knock.addScaledVector(_a.set(dx / dist, 0, dz / dist), need * 6.2);
        M.target = z;
      }
      this._attachMeleeProp(true);
      p.anim.melee = 1e-4;
      return;
    }
    M.t += dt;
    const u = M.t / D.time;
    p.anim.melee = 1e-4;
    if (!M.hit && u >= D.hitAt) {
      M.hit = true;
      const hit = this._meleeStrike();
      g.events.emit('weapon:melee', { hit });
    }
    if (u >= 1) {
      M.t = -1;
      p.anim.melee = 0;
      this._attachMeleeProp(false);
      this._raise = Math.min(this._raise, 0.7);
    }
  }

  _meleeTarget(range) {
    const g = this.game, p = g.player;
    if (!g.zombies || !g.zombies.alive) return null;
    const fx = this.aimDir.x, fz = this.aimDir.z, fl = Math.hypot(fx, fz) || 1;
    let best = null, bestScore = Infinity;
    for (const z of g.zombies.alive) {
      if (z.state === 'dying') continue;
      const dx = z.pos.x - p.pos.x, dz = z.pos.z - p.pos.z, dy = z.pos.y - p.pos.y;
      const d = Math.hypot(dx, dz);
      if (d > range + (z.radius || 0.35) || Math.abs(dy) > 1.6) continue;
      const cos = d > 1e-3 ? (dx * fx + dz * fz) / (d * fl) : 1;
      if (cos < (d < 1.4 ? 0.35 : 0.88)) continue;
      _a.set(p.pos.x, p.pos.y + 1.1, p.pos.z);
      _b.set(z.pos.x, z.pos.y + 1.1, z.pos.z);
      if (!g.level.col.lineOfSight(_a, _b)) continue;
      const score = d * (1.6 - cos);
      if (score < bestScore) { bestScore = score; best = z; }
    }
    return best;
  }

  _meleeStrike() {
    const g = this.game, p = g.player, D = WEAPON_DEFS.melee;
    const z = this._meleeTarget(D.reach + 0.25) || (this._melee.target && this._melee.target.state !== 'dying' && Math.hypot(this._melee.target.pos.x - p.pos.x, this._melee.target.pos.z - p.pos.z) < D.reach + (this._melee.target.radius || 0.35) + 0.3 ? this._melee.target : null);
    _c.set(this.aimDir.x, 0, this.aimDir.z).normalize();
    if (z) {
      _a.set(z.pos.x, z.pos.y + (z.height || 1.7) * 0.62, z.pos.z);
      const killed = this.damageZombie(z, D.dmg * (p.mods.meleeDamage || 1), { head: false, weaponId: 'melee', point: _a, dir: _c, knockback: 2.5, cause: 'melee', melee: true });
      if (g.hud && g.hud.hitmarker) g.hud.hitmarker(false, killed);
      this.fx.pop(_a, 0.6, '#FFFFFF', 0.09);
      this.fx.ring(_a, _b.subVectors(g.camera.position, _a).normalize(), 0.1, 0.55, 0.18, '#FFE27A', false);
      g.fx.burst(_a, { shape: 'star', count: 5, speed: 3, size: 0.1, life: 0.5 });
      g.fx.burst(_a, { shape: 'spark', count: 8, dir: _c, cone: 0.8, speed: 6, life: 0.2 });
      if (g.cam && g.cam.shake) g.cam.shake(0.22, 0.2);
      g.hitStop(killed ? 0.06 : 0.04);
      return true;
    }
    // shootables (Telly bump, toys): a small fan of rays at chest height
    _o.copy(p.pos).setY(p.pos.y + 1.2);
    let best = null;
    for (let i = -2; i <= 2; i++) {
      _d.copy(_c).applyAxisAngle(UP, i * 0.3);
      _d.y = clamp(this.aimDir.y, -0.5, 0.5);
      _d.normalize();
      const wall = g.level.col.raycast(_o, _d, D.reach + 0.5);
      const sh = this._castShootables(_o, _d, wall ? wall.dist : D.reach + 0.5, 'melee');
      if (sh && (!best || sh.dist < best.dist)) best = { ...sh, dir: _d.clone() };
    }
    if (best) {
      this._hitShootable(best.entry, best.point, best.dir, 'melee', false, D.dmg * (p.mods.meleeDamage || 1), true, 'melee');
      this.fx.pop(best.point, 0.5, '#FFFFFF', 0.08);
      g.fx.burst(best.point, { shape: 'star', count: 4, speed: 2.5, size: 0.09, life: 0.45 });
      if (g.cam && g.cam.shake) g.cam.shake(0.18, 0.18);
      g.hitStop(0.04);
      return true;
    }
    return false;
  }

  _attachMeleeProp(on) {
    const g = this.game, p = g.player, M = this._melee;
    if (!p.hero) return;
    if (on) {
      if (M.propHero !== p.heroId) {
        if (M.prop) M.prop.removeFromParent();
        M.prop = buildMeleeProp(p.heroId, g);
        M.propHero = p.heroId;
        if (M.prop) {
          M.prop.scale.setScalar(1.15);
          M.prop.quaternion.setFromEuler(_e.set(0, Math.PI, 0));
          g.mats.applyHeroFade(M.prop);
        }
      }
      if (M.prop && M.prop.parent !== p.hero.slots.handL) p.hero.slots.handL.add(M.prop);
      if (M.prop) M.prop.visible = true;
    } else if (M.prop) M.prop.visible = false;
  }

  // ------------------------------------------------------------------------------------------ grenades
  _jumpCutMul() {
    const g = this.game;
    return g.perks && g.perks.has && g.perks.has('jump_cut') ? 0.7 : 1;
  }

  _updateGrenade(dt, down, pressed) {
    const g = this.game, p = g.player, N = this._nade, G = WEAPON_DEFS.tube_grenade;
    if (N.state === 'none') {
      if (!pressed || this.grenades <= 0 || this._melee.t >= 0 || this._tele.t >= 0 || this._swap.t > 0) return;
      this.cancelReload();
      this._burst = 0;
      N.state = 'cook';
      N.t = 0;
      N.cook = 0;
      this.grenades--;
      this._showNade(true);
      g.audio.play('reload_mag', { vol: 0.4, rate: 1.6 });
      return;
    }
    N.cook += dt;
    if (N.state === 'cook') {
      N.t += dt;
      if (N.cook >= G.fuse) {            // cooked too long: it goes off in the hand
        this._showNade(false);
        p.hero.slots.handL.getWorldPosition(_a);
        this._explode(_a, true);
        N.state = 'recover'; N.t = 0;
        return;
      }
      if (!down && N.t > 0.12) { N.state = 'throw'; N.t = 0; N.released = false; }
      this._animateNadeModel(N.cook / G.fuse);
      return;
    }
    if (N.state === 'throw') {
      const dur = 0.36 * this._jumpCutMul();
      N.t += dt;
      this._animateNadeModel(N.cook / G.fuse);
      if (!N.released && N.t >= dur * 0.42) {
        N.released = true;
        this._showNade(false);
        this._launchGrenade(N.cook);
      }
      if (N.t >= dur) { N.state = 'recover'; N.t = 0; }
      return;
    }
    if (N.state === 'recover') {
      N.t += dt;
      if (N.t >= 0.16) { N.state = 'none'; this._raise = Math.min(this._raise, 0.7); }
    }
  }

  _showNade(on) {
    const g = this.game, p = g.player, N = this._nade;
    if (!p.hero) return;
    if (!N.model) {
      N.model = buildGrenadeModel(g);
      N.model.scale.setScalar(1.25);
      g.mats.applyHeroFade(N.model);
    }
    if (on && N.model.parent !== p.hero.slots.handL) p.hero.slots.handL.add(N.model);
    N.model.visible = on;
  }

  // Tiny Tele in the left hand during the Q wind-up (hidden at release: the wonder system spawns the live one).
  _showTele(on) {
    const g = this.game, p = g.player, TT = this._tele;
    if (!p.hero) return;
    if (!TT.model && on) {
      TT.model = buildTeleModel(g);
      TT.model.scale.setScalar(0.9);
      TT.model.quaternion.setFromEuler(_e.set(0, Math.PI, 0));
      g.mats.applyHeroFade(TT.model);
    }
    if (!TT.model) return;
    if (on && TT.model.parent !== p.hero.slots.handL) p.hero.slots.handL.add(TT.model);
    TT.model.visible = on;
  }

  _animateNadeModel(k) {
    const m = this._nade.model;
    if (!m || !m.userData.parts) return;
    const fil = m.userData.parts.filament;
    if (fil) fil.visible = Math.sin(this.game.time.now * (18 + k * 60)) > -0.3;
  }

  _launchGrenade(cooked) {
    const g = this.game, p = g.player, G = WEAPON_DEFS.tube_grenade;
    const origin = p.hero.slots.handL.getWorldPosition(new V3());
    _a.subVectors(this.aimPoint, origin);
    const d = _a.length();
    const dir = d > 0.5 ? _a.divideScalar(d) : _a.copy(this.aimDir);
    const speed = G.throwSpeed;
    const vel = new V3().copy(dir).multiplyScalar(speed).addScaledVector(UP, G.throwUp);
    vel.x += p.vel.x * 0.5; vel.z += p.vel.z * 0.5;
    const model = buildGrenadeModel(g);
    model.scale.setScalar(1.25);
    model.position.copy(origin);
    g.scene.add(model);
    const pool = g.fx.lightPool ? g.fx.lightPool(origin, 0.8, '#FF8A2E', 0.35) : null;
    this._projectiles.push({ kind: 'grenade', pos: origin, vel, fuse: G.fuse - cooked, model, spin: new V3(g.rand() * 14 - 7, g.rand() * 10 + 6, g.rand() * 8 - 4), rest: false, pool, bounceT: 0 });
    g.audio.play('grenade_throw', { pos: origin });
  }

  _updateProjectiles(dt) {
    const g = this.game, G = WEAPON_DEFS.tube_grenade;
    for (let i = this._projectiles.length - 1; i >= 0; i--) {
      const pr = this._projectiles[i];
      pr.fuse -= dt;
      pr.bounceT -= dt;
      if (!pr.rest) {
        pr.vel.y -= G.gravity * dt;
        const step = pr.vel.length() * dt;
        if (step > 1e-5) {
          _d.copy(pr.vel).divideScalar(pr.vel.length());
          const w = g.level.col.raycast(pr.pos, _d, step + G.radiusBody);
          const zh = g.zombies && g.zombies.raycast ? g.zombies.raycast(pr.pos, _d, step + G.radiusBody) : null;
          if (w && (!zh || w.dist <= zh.dist)) this._bounce(pr, w.point, w.normal, w.dist, _d);
          else if (zh) {
            _n.set(pr.pos.x - zh.z.pos.x, 0.3, pr.pos.z - zh.z.pos.z).normalize();
            this._bounce(pr, zh.point, _n, zh.dist, _d, 0.25);
          } else pr.pos.addScaledVector(pr.vel, dt);
        }
        pr.model.rotation.x += pr.spin.x * dt;
        pr.model.rotation.y += pr.spin.y * dt;
        pr.model.rotation.z += pr.spin.z * dt;
        if (pr.pos.y < -20) pr.fuse = 0;
      }
      pr.model.position.copy(pr.pos);
      const fil = pr.model.userData.parts && pr.model.userData.parts.filament;
      if (fil) fil.visible = Math.sin(g.time.now * (30 + (1 - pr.fuse / G.fuse) * 70)) > -0.2;
      if (pr.pool) pr.pool.set({ pos: _a.set(pr.pos.x, g.level.col.floorAt(pr.pos.x, pr.pos.z, pr.pos.y + 0.1) + 0.02, pr.pos.z), intensity: 0.25 + 0.2 * Math.random() });
      if (pr.fuse <= 0) {
        this._explode(pr.pos, false);
        this._removeProjectile(pr);
        this._projectiles.splice(i, 1);
      }
    }
  }

  _bounce(pr, point, normal, dist, dir, rest = null) {
    const g = this.game, G = WEAPON_DEFS.tube_grenade;
    pr.pos.copy(point).addScaledVector(normal, G.radiusBody + 0.005);
    const vn = pr.vel.dot(normal);
    _v5.copy(normal).multiplyScalar(vn);
    pr.vel.sub(_v5).multiplyScalar(G.friction).addScaledVector(_v5, -(rest ?? G.restitution));
    pr.spin.multiplyScalar(0.7);
    const sp = pr.vel.length();
    if (Math.abs(vn) > 1.6 && pr.bounceT <= 0) {
      g.audio.play('grenade_bounce', { pos: pr.pos, vol: clamp(Math.abs(vn) / 8, 0.25, 1) });
      pr.bounceT = 0.08;
    }
    if (normal.y > 0.6 && sp < 1.2) { pr.rest = true; pr.vel.set(0, 0, 0); pr.model.rotation.set(Math.PI / 2, pr.model.rotation.y, 0); }
  }

  _removeProjectile(pr) {
    if (pr.model) pr.model.removeFromParent();
    if (pr.pool) pr.pool.remove();
  }

  _explode(pos, inHand) {
    const g = this.game, p = g.player, G = WEAPON_DEFS.tube_grenade;
    const r = G.radius;
    const round = Math.max(1, (g.rounds && g.rounds.round) || 1);
    const base = (G.dmgBase + G.dmgPerRound * round) * (p.mods.damage || 1);
    const center = new V3().copy(pos);
    _hitList.length = 0;
    const list = g.zombies && g.zombies.inRadius ? g.zombies.inRadius(center, r + 0.8, _hitList).slice() : [];
    let hits = 0, kills = 0;
    for (const z of list) {
      _a.copy(z.pos).setY(z.pos.y + (z.height || 1.7) * 0.5);
      const d = _a.distanceTo(center);
      if (d > r + (z.radius || 0.35)) continue;
      _b.copy(center).setY(center.y + 0.15);
      if (!g.level.col.lineOfSight(_b, _a)) continue;
      const k = clamp(d / r, 0, 1);
      const dmg = base * lerp(1, G.edgeMul, k);
      const dir = _c.subVectors(_a, center).setY(0.4).normalize();
      if (this.damageZombie(z, dmg, { head: false, weaponId: 'tube_grenade', point: _a.clone(), dir: dir.clone(), knockback: 4 * (1 - k) + 1, cause: 'grenade' })) kills++;
      hits++;
    }
    if (hits && g.hud && g.hud.hitmarker) g.hud.hitmarker(false, kills > 0);
    // bosses and anything else that wants blast damage
    const boss = g.boss;
    const bp = boss && (boss.pos || (boss.group && boss.group.position));
    if (boss && bp && (boss.active || boss.alive) && typeof boss.damage === 'function' && bp.distanceTo(center) < r + 2) {
      try { boss.damage(base * 0.5, { weaponId: 'tube_grenade', point: center.clone(), cause: 'grenade' }); } catch (err) { this._warnOnce('boss.damage', err); }
    }
    // self damage (GDD §9.3: at most 40, x0.5 with Wobble-Up)
    _a.copy(p.pos).setY(p.pos.y + 0.9);
    const pd = _a.distanceTo(center);
    if (pd < r) {
      const wob = g.perks && g.perks.has && g.perks.has('wobble_up') ? G.wobbleSelf : 1;
      const dmg = Math.min(G.selfMax, base * lerp(1, G.edgeMul, pd / r)) * wob;
      p.hurt(dmg, center.clone());
      if (p.knockback) p.knockback(_b.subVectors(_a, center).setY(0).normalize().multiplyScalar(5 * (1 - pd / r)));
    }
    // FX: orange puff cloud of spheres, sparks, glass shards, scorch, shockwave ring, light, shake
    g.fx.burst(center, { shape: 'puff', count: 16, size: 0.5, speed: 4.2, life: 0.8, gravity: -1.5, drag: 3.2, colors: ['#FF8A2E', '#FFB347', '#FFD27A', '#E3662B'] });
    g.fx.burst(center, { shape: 'puff', count: 9, size: 0.55, speed: 2.2, life: 1.5, gravity: -1.2, drag: 2.5, colors: ['#6A5A68', '#8A7A80', '#5A4A5A'] });
    g.fx.burst(center, { shape: 'spark', count: 34, speed: 13, life: 0.45, size: 0.05 });
    g.fx.burst(center, { shape: 'star', count: 8, speed: 5, size: 0.06, life: 0.7, colors: ['#DDF3FF', '#FFFFFF', '#BFE8FF'] });
    this.fx.pop(center, 2.6, '#FFB347', 0.14);
    this.fx.ring(_a.copy(center).setY(g.level.col.floorAt(center.x, center.z, center.y + 0.3) + 0.08), UP, 0.4, r, 0.4, '#FF9A3C', false);
    const fy = g.level.col.floorAt(center.x, center.z, center.y + 0.3);
    if (fy > -Infinity && center.y - fy < 1.5) g.fx.decal(_b.set(center.x, fy + 0.01, center.z), UP, 'scorch', 2.6);
    g.fx.flashLight(center, '#FF9A3C', 22, 0.28);
    if (g.cam && g.cam.shake) g.cam.shake(clamp(0.75 * (1 - pd / 16), 0.1, 0.75), 0.5);
    g.audio.play('grenade_explode', { pos: center });
    g.events.emit('weapon:grenade', { pos: center.clone(), inHand: !!inHand });
  }

  // ------------------------------------------------------------------------------------------ Tiny Tele (Q)
  _updateTele(dt, pressed) {
    const g = this.game, p = g.player, TT = this._tele;
    if (TT.t < 0) {
      if (!pressed || this.teles <= 0 || this._melee.t >= 0 || this._nade.state !== 'none' || this._swap.t > 0) return;
      if (!g.wonder || typeof g.wonder.throwTele !== 'function') return;
      this.cancelReload();
      TT.t = 0;
      TT.thrown = false;
      this._showTele(true);
      return;
    }
    TT.t += dt;
    const dur = 0.42 * this._jumpCutMul();
    if (!TT.thrown && TT.t >= dur * 0.45) {
      TT.thrown = true;
      this._showTele(false);
      const c = this._teleCtx;
      p.hero.slots.handL.getWorldPosition(c.origin);
      c.dir.subVectors(this.aimPoint, c.origin).normalize();
      c.velocity.copy(c.dir).multiplyScalar(11 / this._jumpCutMul()).addScaledVector(UP, 3.5);
      c.aimPoint.copy(this.aimPoint);
      // take it first: the wonder system then sees the count already dropped and does not consume a second one
      const before = this.teles;
      this.teles = Math.max(0, this.teles - 1);
      let ok;
      try { ok = g.wonder.throwTele(c); } catch (err) { this._warnOnce('wonder.throwTele', err); ok = false; }
      if (ok === false) this.teles = before;      // (the wonder system plays tele_throw itself)
    }
    if (TT.t >= dur) { TT.t = -1; this._raise = Math.min(this._raise, 0.7); }
  }

  // ------------------------------------------------------------------------------------------ pose (IK)
  // Wraps the hero animator once so the weapon pose runs after the procedural animation (and after the baked-art
  // rest offsets). Skipped while another system drives animator.override (commercial pantomimes, replays).
  _wrapAnimator() {
    const a = this.game.player.animator;
    if (!a || this._wrapped.has(a)) return;
    this._wrapped.add(a);
    const orig = a.update.bind(a);
    const self = this;
    a.update = function (dt, st) {
      orig(dt, st);
      if (!a.override) self._poseFn(a.rig, dt);
    };
  }

  _poseSafe(rig, dt) {
    try {
      this._pose(rig, dt);
    } catch (err) {
      this._warnOnce('pose', err);
    }
  }

  _pose(rig, dt) {
    const g = this.game, p = g.player;
    if (!p.hero || !p.alive || p.downed) return;
    const J = rig.joints;
    const h = this._holder();
    const hasGun = !!(h && p.weaponModel === h.holder && this.slots[this.current]);
    const leftBusy = this._melee.t >= 0 || this._nade.state !== 'none' || this._tele.t >= 0;
    if (!hasGun && !leftBusy) return;
    const def = hasGun ? h.def : null;
    const hold = HOLDS[(def && def.hold) || 'pistol'] || HOLDS.pistol;
    const hs = (rig.dims && rig.dims.height ? rig.dims.height : 1.8) / 1.8;
    const ads = this._adsW, sprint = this._sprintW, busy = this._busyW;

    // upper body: bladed stance for long guns, extra pitch follow
    const pitch = p.pitch;
    const blade = hold.chest * (1 - sprint) * (hasGun ? 1 : 0);
    J.chest.rotation.y += blade + this._meleeTwist();
    J.head.rotation.y -= blade * 0.8;
    J.spine.rotation.x += pitch * 0.12 * (1 - sprint);
    p.model.updateMatrixWorld(true);

    // frames: body yaw + aim (toward the crosshair point, at least 4 m out)
    J.shoulderR.getWorldPosition(_v1);
    J.shoulderL.getWorldPosition(_v2);
    const M = _v3.addVectors(_v1, _v2).multiplyScalar(0.5);
    const qBody = _q4.setFromAxisAngle(UP, p.model.rotation.y);
    _a.subVectors(this.aimPoint, M);
    if (_a.lengthSq() < 16 || _a.dot(this.aimDir) < 0) _a.copy(this.aimOrigin).addScaledVector(this.aimDir, Math.max(this.aimDist, 4) + 2).sub(M);
    _m4.lookAt(ORIGIN, _a.normalize(), UP);
    const qAim = _q1.setFromRotationMatrix(_m4);

    if (hasGun) {
      // grip / butt anchor
      const off = _b.fromArray(hold.hip).lerp(_c.fromArray(hold.ads), ads).multiplyScalar(hs);
      const qGun = this._gunQ.copy(qAim);
      if (hold.pitch) qGun.multiply(_q2.setFromAxisAngle(X_AXIS, hold.pitch * (1 - ads)));
      const grip = this._gripW;
      if (hold.mode === 'butt') {
        const sc = h.holder.scale.x;
        _c.copy(h.butt).multiplyScalar(sc).applyQuaternion(qGun);
        grip.copy(M).add(off.applyQuaternion(qAim)).sub(_c);
      } else grip.copy(M).add(off.applyQuaternion(qAim));

      // layers: recoil, reload tilt, pump, swap/raise, sprint low-ready, busy (melee / throw)
      const R = this._recoil;
      _c.set(0, 0, R.back * hs).applyQuaternion(qGun);
      grip.add(_c);
      qGun.multiply(_q2.setFromEuler(_e.set(R.rise, 0, R.roll)));
      const rl = this.reloading ? this._reloadPoseWeight() : 0;
      if (rl > 0) {
        grip.add(_c.set(-0.08, -0.07, 0.1).multiplyScalar(rl * hs).applyQuaternion(qAim));
        qGun.multiply(_q2.setFromEuler(_e.set(0.45 * rl, 0.25 * rl, -0.55 * rl)));
      }
      const lower = this._swapLower();
      if (lower > 0) {
        grip.add(_c.set(0.04, -0.32, 0.14).multiplyScalar(lower * hs).applyQuaternion(qAim));
        qGun.multiply(_q2.setFromEuler(_e.set(-1.15 * lower, 0.35 * lower, 0)));
      }
      if (sprint > 0.001) {
        _c.set(0.12, -0.36, -0.2).multiplyScalar(hs).applyQuaternion(qBody).add(M);
        _q3.copy(qBody).multiply(_q2.setFromEuler(_e.set(-0.55, 0.75, 0.25)));
        grip.lerp(_c, sprint);
        qGun.slerp(_q3, sprint);
      }
      if (busy > 0.001) {
        _c.set(0.2, -0.28, -0.06).multiplyScalar(hs).applyQuaternion(qBody).add(M);
        _q3.copy(qAim).multiply(_q2.setFromEuler(_e.set(-0.6, 0.55, 0.2)));
        grip.lerp(_c, busy);
        qGun.slerp(_q3, busy);
      }

      // right arm: palm centre (slot) on the grip
      const qHand = _q2.copy(qGun).multiply(RH_FRAME);
      const slotR = p.hero.slots.handR.position;
      _c.copy(slotR).applyQuaternion(qHand);
      _d.copy(grip).sub(_c);
      this._handPole.fromArray(hold.poleR).applyQuaternion(qBody);
      solveArm(J.shoulderR, J.elbowR, J.handR, _d, this._handPole, qHand);
      J.shoulderR.updateMatrixWorld(true);
    }

    // left arm: on the weapon (clamped to reach), or melee / throw / reload paths
    this._poseLeft(J, hasGun ? h : null, hold, M, qAim, qBody, hs);
  }

  _swingStyle() {
    const hp = MELEE_PROPS[this.game.player.heroId];
    return (hp && hp.swing) || 'chop';
  }

  // Chest yaw for the melee swing: coil on the wind-up, whip through on the strike.
  _meleeTwist() {
    if (this._melee.t < 0) return 0;
    const u = this._melee.t / WEAPON_DEFS.melee.time;
    const S = SWINGS[this._swingStyle()] || SWINGS.chop;
    const wind = smooth(0, 0.28, u), strike = smooth(0.28, 0.46, u), back = smooth(0.62, 1, u);
    return lerp(S.twist[0] * wind, S.twist[1], strike) * (1 - back);
  }

  _reloadPoseWeight() {
    const R = this._reload;
    const u = R.total > 0 ? R.t / R.total : 0;
    return smooth(0, 0.14, u) * (1 - smooth(0.86, 1, u));
  }

  _swapLower() {
    const S = this._swap;
    let lower = 0;
    if (S.t > 0) {
      const u = S.t / S.total;
      lower = u < 0.45 ? easeInOut(u / 0.45) : 1 - easeOutBack(clamp((u - 0.45) / 0.55, 0, 1), 1.4);
    }
    if (this._raise < 1) lower = Math.max(lower, 1 - easeOutBack(this._raise, 1.6));
    return clamp(lower, -0.15, 1);
  }

  _poseLeft(J, h, hold, M, qAim, qBody, hs) {
    const g = this.game, p = g.player;
    const target = this._leftW;
    const qL = _q3;
    const reach = armReach(J.shoulderL, J.elbowL, J.handL) * 0.985;
    J.shoulderL.getWorldPosition(_v4);
    const shoulderL = _v4;
    let wOnGun = h ? 1 : 0;

    // point on the weapon (slides back along the gun when the support point is out of reach)
    if (h) {
      h.model.updateWorldMatrix(true, false);
      _a.copy(h.leftHand);
      h.model.localToWorld(_a);
      if (_a.distanceTo(shoulderL) > reach + 0.02) {
        _b.set(h.leftHand.x, h.leftHand.y, Math.max(h.leftHand.z, -0.02));
        let lo = 0, hi = 1;
        for (let i = 0; i < 8; i++) {
          const m = (lo + hi) / 2;
          _c.copy(_b).lerp(h.leftHand, m);
          h.model.localToWorld(_c);
          if (_c.distanceTo(shoulderL) <= reach) lo = m; else hi = m;
        }
        _a.copy(_b).lerp(h.leftHand, lo);
        h.model.localToWorld(_a);
      }
      target.copy(_a);
      h.model.getWorldQuaternion(qL);
      qL.multiply(LH_FRAMES[hold.lh] || LH_FRAMES.under);
    }

    // reload path: weapon -> belt pouch -> magwell -> weapon
    if (h && this.reloading) {
      const R = this._reload, u = R.total > 0 ? R.t / R.total : 0;
      let belt = 0;
      if (R.kind === 'shell') {
        const def = h.def, start = def.reload * this._eff().reload, per = def.shellReload * this._eff().reload;
        const tt = R.t - start;
        belt = tt < 0 ? smooth(0, start, R.t) * 0.6 : Math.sin(clamp((tt % per) / per, 0, 1) * Math.PI);
      } else belt = smooth(0.14, 0.32, u) * (1 - smooth(0.5, 0.72, u));
      _b.copy(BELT_L).multiplyScalar(hs).applyQuaternion(qBody).add(M);
      target.lerp(_b, belt);
      if (belt > 0.01) qL.slerp(_q2.copy(qBody), belt * 0.8);
    }

    // melee: hero swing with the left hand (per hero: Duke chops bare-handed, Skip / Penny bonk, Roxy slaps the LP)
    const Mw = WEAPON_DEFS.melee;
    if (this._melee.t >= 0) {
      const u = this._melee.t / Mw.time;
      const S = SWINGS[this._swingStyle()] || SWINGS.chop;
      const wind = smooth(0, 0.28, u), back = smooth(0.62, 1, u);
      const k = smooth(0.28, 0.46, u), strike = k < 1 ? k * k * (3 - 2 * k) : 1;     // snappy strike
      _b.fromArray(S.wind).multiplyScalar(hs);
      _c.fromArray(S.ctrl).multiplyScalar(hs);
      _d.fromArray(S.hit).multiplyScalar(hs);
      // quadratic arc wind -> ctrl -> hit, a small follow-through overshoot after the hit
      const o = strike + 0.12 * Math.sin(Math.PI * smooth(0.46, 0.7, u));
      const a0 = (1 - o) * (1 - o), a1 = 2 * (1 - o) * o, a2 = o * o;
      _v5.set(_b.x * a0 + _c.x * a1 + _d.x * a2, _b.y * a0 + _c.y * a1 + _d.y * a2, _b.z * a0 + _c.z * a1 + _d.z * a2).applyQuaternion(qAim).add(M);
      const w = Math.max(wind, strike) * (1 - back);
      if (h) target.lerp(_v5, w); else target.copy(_v5);
      wOnGun = h ? 1 : w;
      _q2.copy(qAim).multiply(_q5.setFromEuler(_e.set(lerp(S.rotW[0], S.rotH[0], strike), lerp(S.rotW[1], S.rotH[1], strike), lerp(S.rotW[2], S.rotH[2], strike))));
      qL.slerp(_q2, h ? w : 1);
    }

    // grenade / Tiny Tele: hold near the chest, wind up overhand, throw forward
    const N = this._nade;
    const throwing = N.state !== 'none' || this._tele.t >= 0;
    if (throwing) {
      let wind = 0, fwd = 0, hold2 = 1;
      if (N.state === 'cook') { hold2 = smooth(0, 0.12, N.t); wind = 0.35 * hold2; }
      else if (N.state === 'throw' || this._tele.t >= 0) {
        const dur = (N.state === 'throw' ? 0.36 : 0.42) * this._jumpCutMul();
        const u = (N.state === 'throw' ? N.t : this._tele.t) / dur;
        wind = u < 0.3 ? lerp(0.35, 1, smooth(0, 0.3, u)) : 1 - smooth(0.3, 0.5, u);
        fwd = smooth(0.28, 0.55, u) * (1 - smooth(0.8, 1, u));
        hold2 = 1 - smooth(0.85, 1, u);
      } else if (N.state === 'recover') hold2 = 1 - smooth(0, 0.16, N.t);
      _b.set(-0.24, -0.02, -0.26).multiplyScalar(hs).applyQuaternion(qAim).add(M);           // hold
      _c.set(-0.32, 0.34, 0.24).multiplyScalar(hs).applyQuaternion(qAim).add(M);             // wind-up
      _d.set(-0.06, 0.1, -0.6).multiplyScalar(hs).applyQuaternion(qAim).add(M);              // release
      _b.lerp(_c, wind).lerp(_d, fwd);
      if (h) target.lerp(_b, hold2); else target.copy(_b);
      wOnGun = h ? 1 : hold2;
      _q2.copy(qAim).multiply(_q5.setFromEuler(_e.set(0.4 - fwd * 0.9, 0, 0.3)));
      qL.slerp(_q2, h ? hold2 : 1);
    }
    if (wOnGun <= 0.001) return;

    const slotL = this.game.player.hero.slots.handL.position;
    _c.copy(slotL).applyQuaternion(qL);
    _d.copy(target).sub(_c);
    this._handPole.fromArray(hold.poleL).applyQuaternion(qBody);
    solveArm(J.shoulderL, J.elbowL, J.handL, _d, this._handPole, qL);
    J.shoulderL.updateMatrixWorld(true);
  }
}

// reloadSpeed / swapSpeed: time multipliers (0.5 = twice as fast, T.perks.jumpCut); values > 1 are read as speeds.
function timeMul(v) {
  if (!Number.isFinite(v) || v <= 0) return 1;
  return v <= 1 ? v : 1 / v;
}
