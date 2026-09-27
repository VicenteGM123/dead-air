// DEAD AIR — THE UPLINK, the pack-a-punch of the Transmitter Yard (GDD §10.4, §9.5, §15 Uplink cues, §18.15 events).
// Owned by the uplink-powerups engineer. Keeps the stub contract: aligned, busy, weaponId (+ reset()).
//
// BUILD (init, into level.areaRoots.yard, reusing props a room may already have placed): 'uplink_dish' (5 m dish on
//   its az-el turntable; parts yaw/tilt/rimBulbs) at uplink_dish, 'uplink_cradle' (feed horn + gun clamp + R/G/B lamps)
//   at uplink_cradle, 'uplink_crank' (hand wheel, glowing grip, elevation gauge) at uplink_crank, 'uplink_booth' (control
//   kiosk, blinking lamp panel) beside them, and the satellite 'skylark_13' crossing the northern sky on a 60 s pass
//   (118 m out, x5 so it reads; fades in and out of the Earth's shadow at both ends; red beacon, green once locked).
//   Plus the effect rigs: the braided SMPTE colour-bar beam, three downlink streams, lamp beams, the R/G/B weapon
//   copies, the colour-bar aurora ribbon (vertex-waved additive curtain across the north sky), flare + flash sprites.
// ALIGNMENT (once per game, needs power): the crank prompt is [E] + plug before power (E: bzzt + the grip jiggles),
//   then a key-only hold of T.uplink.alignHold s. Cranking spins the wheel, whirs (dish_crank) and swings the dish up
//   out of its droop, lighting the rim bulbs like a progress ring; the hold progress survives letting go but decays
//   0.5 s per second (the dish sags), and every hit taken while cranking halves it (clunk + sparks). Lock: the dish
//   overshoots into place, Skylark-13's beacon turns green, dish_lock pips, the rim chasers race, the horn lamps glow,
//   the droop collider under the rim goes away, emits machine:dish_aligned {}.
// UPGRADE (cradle prompt [E] 5000 with a normal weapon, [E] 2500 with an upgraded one = Re-Uplink; one at a time)
//   0.00 the weapon is yanked magnetically out of the hand into the clamp (weapons.takeCurrent: auto-switch / melee),
//        CLANG, the jaws snap shut; the magnet's kick shoves the hero a step back-left (the shoulder camera then sees
//        the clamp). 0.0-0.8 the dish swings round onto Skylark-13, motor whir, the rim chasers race in colour bars.
//   0.8-1.8 COLOUR SPLIT: the R/G/B lamps beam at the gun, which splits into three additive copies orbiting 0.3 m
//        apart (uplink_triad). 1.8-2.6 UPLINK: the copies stretch up and braid into the colour-bar beam that shoots to
//        the satellite (the dish glows in the beam's shifting colours); every TV cuts to LIVE VIA SATELLITE
//        (screens.override 'satellite' until the snap + screens.setInsert:
//        the weapon on the insert turntable, upgraded at the end), uplink_vwoom, crowd ooh, 1 kHz from the TVs.
//   2.6-5.0 Skylark-13 flares, the aurora unfurls across the sky (uplink_aurora), Yard zombies gawk up for 0.8 s.
//   4.3 the beam lifts off; 4.4 three thin streams race down, meet in the clamp and swell (the signal colour thickest
//        and brightest) until
//   5.00 DOWNLINK: they snap together in a white flash into the upgraded weapon in the clamp (Chromacast, signal
//        colour rolled at the start), sparkle burst, uplink_snap + uplink_fanfare, hud.chyron(upgraded name) (else
//        emits machine:uplink_ready with it), machine:uplink_ready {weaponId, signal}; the dish returns to park.
//   5-20 the upgraded weapon rises out of the horn onto a signal-coloured light cone and turns slowly; 15 s to take it
//        with E (weapons.give(id, {upgraded:true, signal, source:'uplink'}), full ammo,
//        machine:uplink_take {weaponId}); from 10 s it flickers like bad reception (uplink_flicker, accelerating
//        ticks); at 15 s it is beamed back up and lost (uplink_lost, machine:uplink_lost {weaponId}).
//   Re-Uplink: a 3.0 s split -> converge -> snap (no beam, aurora or LIVE card) rolling a DIFFERENT signal colour,
//   then the same collection window. Disabled during the boss fight (machine:boss_start: lamps dark; a weapon still in
//   the machine is handed back upgraded) until egg:complete / game:victory / game:over / a new game.
// API (game.uplink)
//   aligned, busy, weaponId, signal, phase ('idle'|'seq'|'ready'), seqT, readyT, reroll, disabled, align (hold s)
//   status() -> snapshot       satellitePos(out) -> Vector3 (world)      warmup() -> [] (effects live in the scene)
//   debugAlign()  debugUpgrade(weaponId?, { free=true })  debugTake()  debugSkip(t)  debugHit()
// EVENTS machine:dish_aligned {}, machine:uplink_start {weaponId}, machine:uplink_ready {weaponId, signal, name},
//   machine:uplink_take {weaponId}, machine:uplink_lost {weaponId}. Listens: player:hurt, machine:boss_start,
//   egg:complete, game:victory, game:over.
// TESTS tools/scenarios/uplink-powerups_uplink.cjs (params test=1&nozombies=1&god=1&power=1&doors=1&points=20000).

import * as THREE from 'three';
import { T, PAL, LAYERS } from '../core/config.js';
import { placeProp, buildProp } from '../props/index.js';
import { setUplinkPose, setCrankGlow, setBoothLamps } from '../props/machines.js';
import { SIGNAL_COLORS } from './weaponDefs.js';

const U = T.uplink;
const TAU = Math.PI * 2;
const DEG = Math.PI / 180;
const SIGNALS = ['hot_mic', 'laugh_track', 'cold_open'];
const RGB = ['#FF3B30', '#3BFF5A', '#3B7BFF'];
const LAMP_COL = [PAL.hotMic || '#FF5A3C', PAL.laughTrack || '#52E04A', PAL.coldOpen || '#7FD4FF'];
const BARS = ['#E8E8E8', '#F4E03A', '#3FD6E0', '#52D24A', '#D64FD6', '#E4473A', '#3A58E4'];
const FULL = { land: 0.24, swivel: 0.8, split: 0.8, beam: 1.8, beamTop: 2.25, flare: 2.6, retract: 4.3, streams: 4.4, streamsDown: 4.82, snap: 5.0 };
const RE = { land: 0.24, split: 0.45, converge: 2.2, snap: 3.0 };
const SAT = { period: 60, radius: 118, scale: 5, b0: 72, b1: -72, el0: 24, elPeak: 36, busyRate: 0.1 };
const BOOTH = { pos: [41.95, 0, -15.1], rotY: Math.PI / 2 };
const DISH_DEF = { droop: -0.33, aligned: 0.95, pivotY: 3.3 };
const AURORA = { radius: 100, span: 150 * DEG, base: 13 * DEG, arch: 9 * DEG, height: 21 * DEG, segS: 144, segV: 10 };
const DECAY = 0.5;
const GUN = { rest: 0.1, show: 0.3 };
const ORBIT_R = 0.22;

const _v = new THREE.Vector3();
const _w = new THREE.Vector3();
const _u = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _q2 = new THREE.Quaternion();
const _m = new THREE.Matrix4();
const _c = new THREE.Color();
const WHITE = new THREE.Color(1, 1, 1);
const _box = new THREE.Box3();
const UP = new THREE.Vector3(0, 1, 0);
const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (a, b, x) => { const t = clamp01((x - a) / (b - a)); return t * t * (3 - 2 * t); };
const easeOutBack = (x, s = 1.8) => { x = clamp01(x); return 1 + (s + 1) * (x - 1) ** 3 + s * (x - 1) ** 2; };
const easeOutCubic = (x) => 1 - (1 - clamp01(x)) ** 3;
const easeInCubic = (x) => clamp01(x) ** 3;
const wrapPi = (a) => Math.atan2(Math.sin(a), Math.cos(a));

// ============================================================================================== shaders
const BAR_GLSL = /* glsl */`
vec3 barCol(float i) {
  i = mod(i, 7.0);
  if (i < 1.0) return vec3(0.92, 0.92, 0.95);
  if (i < 2.0) return vec3(1.0, 0.86, 0.12);
  if (i < 3.0) return vec3(0.12, 0.86, 0.95);
  if (i < 4.0) return vec3(0.18, 0.92, 0.2);
  if (i < 5.0) return vec3(0.92, 0.18, 0.9);
  if (i < 6.0) return vec3(1.0, 0.18, 0.12);
  return vec3(0.16, 0.26, 1.0);
}`;

// Braided colour-bar beam: open cylinder along +y (0 = horn .. 1 = satellite), helical SMPTE stripes scrolling up,
// hot core, travelling pulses. uHead / uTail clip the visible stretch (shoot up / lift off).
const BEAM_VERT = /* glsl */`
varying vec2 vUv;
varying float vFace;
void main() {
  vUv = uv;
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  vec3 n = normalize(normalMatrix * normal);
  vFace = abs(dot(n, normalize(-mv.xyz)));
  gl_Position = projectionMatrix * mv;
}`;
const BEAM_FRAG = /* glsl */`
uniform float uTime, uLen, uHead, uTail, uAlpha;
varying vec2 vUv;
varying float vFace;
${BAR_GLSL}
void main() {
  if (vUv.y > uHead || vUv.y < uTail) discard;
  float m = vUv.y * uLen;
  float tw = vUv.x * 7.0 + m * 0.32 - uTime * 3.2;
  vec3 c = barCol(floor(tw));
  float f = fract(tw);
  c *= 0.82 + 0.18 * smoothstep(0.0, 0.1, f) * smoothstep(1.0, 0.9, f);
  float core = pow(clamp(vFace, 0.0, 1.0), 2.2);
  float soft = smoothstep(0.0, 0.45, vFace);
  float pulse = 0.8 + 0.35 * pow(clamp(0.5 + 0.5 * sin(m * 0.7 - uTime * 20.0), 0.0, 1.0), 3.0);
  vec3 col = c * (0.55 + 0.35 * core) * pulse + vec3(1.0) * pow(core, 5.0) * 0.18;
  float head = smoothstep(uHead - 0.03, uHead, vUv.y);
  col += vec3(0.9) * head;
  float base = 0.55 + 0.45 * smoothstep(0.0, 0.05, vUv.y);
  float fade = 1.0 - 0.45 * smoothstep(0.55, 1.0, vUv.y);
  gl_FragColor = vec4(col * soft * base * uAlpha * fade * 0.95, 1.0);
}`;

// Downlink stream: thin solid-colour line from the satellite (y = 1) down to the clamp (y = 0).
const STREAM_FRAG = /* glsl */`
uniform float uTime, uHead, uAlpha, uLen;
uniform vec3 uColor;
varying vec2 vUv;
varying float vFace;
void main() {
  if (vUv.y < 1.0 - uHead) discard;
  float m = vUv.y * uLen;
  float pulse = 0.75 + 0.3 * pow(clamp(0.5 + 0.5 * sin(m * 1.4 + uTime * 30.0), 0.0, 1.0), 4.0);
  float tip = smoothstep(1.0 - uHead + 0.02, 1.0 - uHead, vUv.y);
  float soft = smoothstep(0.0, 0.5, vFace);
  vec3 col = mix(uColor, vec3(1.0), pow(clamp(vFace, 0.0, 1.0), 6.0) * 0.25) * (0.5 + 0.45 * vFace) * pulse + vec3(1.0) * tip * 0.5;
  gl_FragColor = vec4(col * soft * uAlpha, 1.0);
}`;

// Colour-bar aurora: a curtain across the north sky. Folds and ripples in the vertex shader; smooth SMPTE colours
// along the ribbon, a hot lower hem fading upward, fine vertical rays; unfurls from the satellite's bearing (uS0).
const AURORA_VERT = /* glsl */`
attribute float aS;
attribute float aV;
uniform float uTime;
varying float vS;
varying float vV;
void main() {
  vS = aS; vV = aV;
  vec3 p = position;
  float w = sin(aS * 34.0 + uTime * 0.8) * 0.65 + sin(aS * 83.0 - uTime * 1.55) * 0.35;
  p += normal * w * (2.5 + aV * 7.0);
  // the whole curtain billows up and down along its length (an undulating hem), the top sways more
  float hem = sin(aS * 9.0 + uTime * 0.55) * 4.5 + sin(aS * 23.0 - uTime * 0.9) * 1.8 + sin(aS * 57.0 + uTime * 1.7) * 0.6;
  p.y += hem + sin(aS * 21.0 + uTime * 1.2) * 2.6 * aV;
  vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), normal));
  p += side * sin(aS * 15.0 + uTime * 0.7) * 3.0 * aV;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
}`;
const AURORA_FRAG = /* glsl */`
uniform float uTime, uAlpha, uReveal, uS0;
varying float vS;
varying float vV;
${BAR_GLSL}
vec3 bars(float x) {
  x = fract(x) * 7.0;
  float i = floor(x), f = fract(x);
  return mix(barCol(i), barCol(i + 1.0), smoothstep(0.55, 1.0, f));
}
void main() {
  float d = abs(vS - uS0);
  float rev = smoothstep(uReveal * 0.62, uReveal * 0.62 - 0.07, d);
  vec3 c = bars(vS * 2.2 - uTime * 0.04);
  float band = smoothstep(0.0, 0.07, vV) * (1.0 - smoothstep(0.05, 1.0, vV));
  float rays = 0.6 + 0.4 * sin(vS * 520.0 + uTime * 2.2) * sin(vS * 190.0 - uTime * 1.3);
  float hem = exp(-vV * 10.0) * smoothstep(0.0, 0.02, vV);
  float ends = smoothstep(0.0, 0.1, vS) * smoothstep(1.0, 0.9, vS);
  vec3 col = c * (band * band * rays * 1.1 + hem * 1.25) + vec3(1.0) * hem * 0.25;
  gl_FragColor = vec4(col * uAlpha * rev * ends, 1.0);
}`;

function glowTexture(rays = 0) {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const x = c.getContext('2d');
  const g = x.createRadialGradient(128, 128, 0, 128, 128, 128);
  g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.18, 'rgba(255,255,255,0.75)');
  g.addColorStop(0.45, 'rgba(255,255,255,0.18)'); g.addColorStop(1, 'rgba(255,255,255,0)');
  x.fillStyle = g; x.fillRect(0, 0, 256, 256);
  if (rays) {
    x.translate(128, 128);
    for (let i = 0; i < rays; i++) {
      x.rotate(TAU / rays);
      const lg = x.createLinearGradient(0, 0, 0, -124);
      lg.addColorStop(0, 'rgba(255,255,255,0.9)'); lg.addColorStop(1, 'rgba(255,255,255,0)');
      x.fillStyle = lg;
      x.beginPath(); x.moveTo(-5, 0); x.lineTo(0, -124); x.lineTo(5, 0); x.closePath(); x.fill();
    }
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function spring(s, target, k, zeta, dt) {
  const a = k * (target - s.x) - 2 * zeta * Math.sqrt(k) * s.v;
  s.v += a * dt;
  s.x += s.v * dt;
}

export class Uplink {
  constructor(game) {
    this.game = game;
    this.aligned = false;
    this.busy = false;
    this.weaponId = null;
    this.signal = null;
    this.phase = 'idle';
    this.seqT = 0;
    this.readyT = 0;
    this.reroll = false;
    this.disabled = false;
    this.align = 0;
    this.built = false;
    this._satT = 0;
    this._tilt = { x: DISH_DEF.droop, v: 0 };
    this._yaw = { x: 0, v: 0 };
    this._cranking = false;
    this._crankLoop = null;
    this._lockT = -1;
    this._cues = [];
    this._cue = 0;
    this._t = 0;
    this._gun = null;
    this._fly = null;
    this._take = null;
    this._lost = null;
    this._jaw = { x: 1, v: 0, target: 1 };
    this._copies = [];
    this._glowCache = new Map();
    this._mats = {};
  }

  // ============================================================================================ lifecycle
  init() {
    const g = this.game;
    try {
      this._build();
      this.built = true;
    } catch (err) {
      console.error('[uplink] build failed', err);
    }
    const ev = g.events;
    ev.on('player:hurt', () => this._onHurt());
    ev.on('machine:boss_start', () => this._setDisabled(true));
    for (const e of ['egg:complete', 'game:victory', 'game:over']) ev.on(e, () => this._setDisabled(false));
    this._toIdle(true);
  }

  reset() {
    this.disabled = false;
    this.aligned = false;
    this.align = 0;
    this._lockT = -1;
    this._satT = this.game.rand ? this.game.rand() * SAT.period * 0.6 : 0;
    this._toIdle(true);
    this._tilt.x = DISH_DEF.droop; this._tilt.v = 0;
    this._yaw.x = 0; this._yaw.v = 0;
    if (this.dish) setUplinkPose(this.dish, { tilt: this._tilt.x, yaw: 0 });
    this.game.level?.col?.setEnabled?.('uplink_droop', true);
    if (this._droopWasOff && this.game.nav?.built) this.game.nav.build();
    this._droopWasOff = false;
    this._stopCrank();
  }

  // The beam, streams, aurora, cone and sprites live (hidden) in the scene and compile with it; these samples cover
  // the materials only attached at runtime (the R/G/B copies, the energised dish variants).
  warmup() {
    if (this._warm) return this._warm;
    const out = [];
    const box = new THREE.BoxGeometry(0.1, 0.1, 0.1);
    for (const m of this._copyMats || []) out.push(new THREE.Mesh(box, m));
    for (const m of this._dishGlowMats || []) out.push(new THREE.Mesh(box, m));
    this._warm = out;
    return out;
  }

  // ============================================================================================ build
  _build() {
    const g = this.game, L = g.level;
    const root = L?.areaRoots?.yard;
    const A = L?.anchors || {};
    if (!root || !A.uplink_dish || !A.uplink_cradle || !A.uplink_crank) throw new Error('yard / uplink anchors missing');
    this.root = root;
    const found = {};
    root.traverse((o) => { const id = o.userData && o.userData.id; if (typeof id === 'string' && /^uplink_|^skylark_13$/.test(id) && !found[id]) found[id] = o; });

    // --- props
    const a = A.uplink_dish;
    this.dish = found.uplink_dish || placeProp(g, root, 'uplink_dish', { pos: [a.pos.x, 0, a.pos.z], rotY: a.rotY ?? Math.PI, area: 'yard', colliders: false, tag: 'machine' });
    if (!found.uplink_dish) this._dishColliders();
    const c = A.uplink_cradle;
    this.cradle = found.uplink_cradle || placeProp(g, root, 'uplink_cradle', { pos: [c.pos.x, 0, c.pos.z], rotY: c.rotY ?? Math.PI, area: 'yard', tag: 'machine' });
    const k = A.uplink_crank;
    this.crank = found.uplink_crank || placeProp(g, root, 'uplink_crank', { pos: [k.pos.x, 0, k.pos.z], rotY: k.rotY ?? Math.PI, area: 'yard', tag: 'machine' });
    this.booth = found.uplink_booth || placeProp(g, root, 'uplink_booth', { pos: BOOTH.pos, rotY: BOOTH.rotY, area: 'yard', lights: false, tag: 'machine' });
    for (const o of [this.dish, this.cradle, this.crank, this.booth]) o.updateMatrixWorld(true);
    // draw-call diet: only the big pieces cast into the (player-following) shadow map
    this._trimShadows(this.dish, 0.7);
    for (const o of [this.cradle, this.crank, this.booth]) this._trimShadows(o, 0.42);
    this.dishRig = { ...DISH_DEF, ...(this.dish.userData.rig || {}) };
    this.cradleRig = this.cradle.userData.rig || { slotY: 1.3, jawOpenF: -0.5, jawOpenB: 0.5, jawClosed: 0, beamFrom: [0, 1.5, 0.08] };
    this.crankRig = this.crank.userData.rig || { hubY: 1.0, needleMin: -1.05, needleMax: 1.05 };
    this.P = { dish: this.dish.userData.parts || {}, cradle: this.cradle.userData.parts || {}, crank: this.crank.userData.parts || {}, booth: this.booth.userData.parts || {} };
    this.pivot = new THREE.Vector3(0, this.dishRig.pivotY, 0).applyMatrix4(this.dish.matrixWorld);
    this.hornPos = new THREE.Vector3().fromArray(this.cradleRig.beamFrom || [0, 1.5, 0.08]).applyMatrix4(this.cradle.matrixWorld);
    this.gunSlot = this.P.cradle.gunSlot || this.cradle;
    this.holder = new THREE.Group();
    this.holder.name = 'uplink_gun_holder';
    this.holder.position.set(0, GUN.rest, 0);
    this.gunSlot.add(this.holder);
    this.holder.updateMatrixWorld(true);
    this.slotPos = this.holder.getWorldPosition(new THREE.Vector3());
    this.slotQuat = this.holder.getWorldQuaternion(new THREE.Quaternion());
    this._bulbBase = [];
    const bulbs = this.P.dish.rimBulbs;
    if (bulbs && !bulbs.instanceColor) bulbs.setColorAt(0, _c.set(1, 1, 1));
    // booth light (enabled with power) + horn light (after alignment) + a warm pool under the rim
    const lights = g.lights;
    const bp = new THREE.Vector3(0, 1.2, -1.2).applyMatrix4(this.booth.matrixWorld);
    lights?.addAnchor?.({ pos: bp.toArray(), color: '#7FE7FF', intensity: 1.3, distance: 4.5, area: 'yard', id: 'uplink_booth' });
    lights?.addAnchor?.({ pos: [this.hornPos.x, this.hornPos.y + 0.4, this.hornPos.z - 0.2], color: '#FFFFFF', intensity: 1.8, distance: 8, area: 'yard', id: 'uplink_horn' });
    lights?.setAnchor?.('uplink_booth', { enabled: false });
    lights?.setAnchor?.('uplink_horn', { enabled: false });
    try { this._pool = g.fx?.lightPool?.(new THREE.Vector3(this.pivot.x, 0.02, this.pivot.z + 0.8), 3.6, PAL.marqueeGold || '#FFD23A', 0) || null; } catch (err) { this._pool = null; }

    this._buildDishGlow();
    this._buildSatellite();
    this._buildFx();
    this._registerInteract();
    if (g.nav?.built) g.nav.build();
  }

  // Energised dish: emissive variants of the dish's toon materials (unique to it), swapped in during the uplink so
  // the rainbow of the beam washes over it (its back faces the camera once it swings onto the satellite).
  _buildDishGlow() {
    const g = this.game;
    this._dishGlow = [];
    this._dishGlowOn = false;
    this._dishGlowK = 0;
    const cache = new Map();
    const root = this.P.dish.tilt || this.dish;
    root.traverse((o) => {
      if (!o.isMesh || o.isInstancedMesh || !o.material || !o.material.userData || !o.material.userData.daToon) return;
      let lit = cache.get(o.material);
      if (!lit) {
        lit = g.mats.variant(o.material, { emissive: '#000000', emissiveIntensity: 1, name: 'uplink_dish_glow:' + cache.size });
        cache.set(o.material, lit);
      }
      if (lit !== o.material) this._dishGlow.push({ mesh: o, base: o.material, lit });
    });
    this._dishGlowMats = [...new Set(this._dishGlow.map((d) => d.lit))];
  }

  _setDishGlow(k, color) {
    const on = k > 0.004;
    if (on !== this._dishGlowOn) {
      this._dishGlowOn = on;
      for (const d of this._dishGlow) d.mesh.material = on ? d.lit : d.base;
    }
    if (!on) return;
    _c.set(color).lerp(WHITE, 0.5).multiplyScalar(k);
    for (const m of this._dishGlowMats) m.emissive.copy(_c);
  }

  _trimShadows(root, minR) {
    root.traverse((o) => {
      if (!o.isMesh || !o.castShadow || !o.geometry) return;
      if (!o.geometry.boundingSphere) o.geometry.computeBoundingSphere();
      const s = o.getWorldScale(_v);
      if (o.geometry.boundingSphere.radius * Math.max(s.x, s.y, s.z) < minR) o.castShadow = false;
    });
  }

  // The dish's local colliders, placed by hand so the one under the drooped rim can be switched off once aligned.
  _dishColliders() {
    const g = this.game, col = g.level?.col;
    if (!col) return;
    this.dish.updateMatrixWorld(true);
    const bb = new THREE.Box3();
    for (const cl of this.dish.userData.colliders || []) {
      bb.makeEmpty();
      for (let i = 0; i < 8; i++) {
        _v.set(i & 1 ? cl.max[0] : cl.min[0], i & 2 ? cl.max[1] : cl.min[1], i & 4 ? cl.max[2] : cl.min[2]).applyMatrix4(this.dish.matrixWorld);
        bb.expandByPoint(_v);
      }
      const droop = cl.opts && cl.opts.tag === 'uplink_droop';
      col.addBox(bb.min.toArray(), bb.max.toArray(), droop ? { tag: 'machine', id: 'uplink_droop' } : { tag: 'machine', id: 'uplink_dish' });
    }
  }

  _buildSatellite() {
    const g = this.game;
    const sat = buildProp('skylark_13', g, { beacon: 'red' });
    // 118 m out, past the Yard fog: every material needs fog off (toon ones through mats.variant, which keeps the
    // cartoon shader patch; plain glows are cloned)
    const cache = new Map();
    sat.traverse((o) => {
      if (!o.isMesh) return;
      o.castShadow = false; o.receiveShadow = false;
      const src = o.material;
      if (!cache.has(src)) {
        let m = src && src.userData && src.userData.daToon ? g.mats.variant(src, { fog: false }) : null;
        if (!m || m === src) { m = src.clone(); m.fog = false; }
        cache.set(src, m);
      }
      o.material = cache.get(src);
    });
    this._beaconMats = {
      red: new THREE.MeshBasicMaterial({ color: new THREE.Color(PAL.onAirRed || '#FF3B30').multiplyScalar(3), fog: false }),
      green: new THREE.MeshBasicMaterial({ color: new THREE.Color(PAL.laughTrack || '#52E04A').multiplyScalar(3), fog: false }),
      flare: new THREE.MeshBasicMaterial({ color: new THREE.Color(6, 6, 6), fog: false }),
      off: new THREE.MeshBasicMaterial({ color: '#3A1A1A', fog: false }),
    };
    this.satParts = sat.userData.parts || {};
    if (this.satParts.beacon) this.satParts.beacon.material = this._beaconMats.red;
    const holder = new THREE.Group();
    holder.name = 'skylark_13_orbit';
    sat.scale.setScalar(SAT.scale);
    sat.position.y = -0.7 * SAT.scale;
    holder.add(sat);
    // the blinking beacon halo that makes it read at 118 m
    const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTexture(4), color: '#FF5A4A', blending: THREE.AdditiveBlending, depthWrite: false, fog: false, transparent: true }));
    halo.scale.setScalar(7);
    halo.position.y = 0.46 * SAT.scale;
    holder.add(halo);
    const flare = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTexture(8), color: '#FFFFFF', blending: THREE.AdditiveBlending, depthWrite: false, fog: false, transparent: true, opacity: 0 }));
    flare.scale.setScalar(1);
    flare.visible = false;
    holder.add(flare);
    this.root.add(holder);
    this.sat = holder;
    this.satModel = sat;
    this.satHalo = halo;
    this.satFlare = flare;
    this.satPos = new THREE.Vector3();
    this._satAlpha = 1;
    this._updateSatellite(0);
  }

  _buildFx() {
    const g = this.game;
    const U0 = g.mats.uniforms?.uTime;
    const time = { value: 0 };
    this._time = time;
    // beam
    const cyl = new THREE.CylinderGeometry(1, 1, 1, 20, 1, true).translate(0, 0.5, 0);
    const beamMat = new THREE.ShaderMaterial({
      uniforms: { uTime: time, uLen: { value: 100 }, uHead: { value: 0 }, uTail: { value: 0 }, uAlpha: { value: 1 } },
      vertexShader: BEAM_VERT, fragmentShader: BEAM_FRAG, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false, side: THREE.DoubleSide,
    });
    beamMat.name = 'uplink:beam';
    this.beam = new THREE.Mesh(cyl, beamMat);
    this.beam.name = 'uplink_beam';
    this.beam.visible = false;
    this.beam.renderOrder = 4;
    this.root.add(this.beam);
    const head = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTexture(6), color: '#FFFFFF', blending: THREE.AdditiveBlending, depthWrite: false, fog: false, transparent: true }));
    head.visible = false;
    this.root.add(head);
    this.beamHead = head;
    // downlink streams
    this.streams = RGB.map((col, i) => {
      const m = new THREE.ShaderMaterial({
        uniforms: { uTime: time, uHead: { value: 0 }, uAlpha: { value: 1 }, uLen: { value: 100 }, uColor: { value: new THREE.Color(LAMP_COL[i]) } },
        vertexShader: BEAM_VERT, fragmentShader: STREAM_FRAG, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false, side: THREE.DoubleSide,
      });
      m.name = `uplink:stream${i}`;
      const s = new THREE.Mesh(cyl, m);
      s.visible = false;
      s.renderOrder = 4;
      this.root.add(s);
      return s;
    });
    // lamp beams (colour split)
    const thin = new THREE.CylinderGeometry(1, 1, 1, 8, 1, true).translate(0, 0.5, 0);
    this.lampBeams = LAMP_COL.map((col, i) => {
      const m = new THREE.MeshBasicMaterial({ color: new THREE.Color(col).multiplyScalar(2.2), transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false, fog: false });
      const b = new THREE.Mesh(thin, m);
      b.visible = false;
      this.root.add(b);
      return b;
    });
    // R/G/B copy materials
    this._copyMats = RGB.map((col) => {
      const m = new THREE.MeshBasicMaterial({ color: new THREE.Color(col).multiplyScalar(1.25), transparent: true, opacity: 1, blending: THREE.AdditiveBlending, depthWrite: false, fog: false });
      m.name = 'uplink:copy';
      return m;
    });
    this.splitRoot = new THREE.Group();
    this.splitRoot.name = 'uplink_split';
    this.gunSlot.add(this.splitRoot);
    this.splitRoot.position.copy(this.holder.position);
    // flash at the clamp
    const flash = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTexture(10), color: '#FFFFFF', blending: THREE.AdditiveBlending, depthWrite: false, fog: false, transparent: true, opacity: 0 }));
    flash.visible = false;
    flash.position.copy(this.slotPos);
    this.root.add(flash);
    this.flash = flash;
    // aurora
    this.aurora = this._buildAurora(time);
    // showcase light cone rising out of the horn while the upgraded weapon waits (signal colour)
    const cone = new THREE.Mesh(new THREE.CylinderGeometry(0.46, 0.3, 0.95, 24, 1, true).translate(0, 0.475, 0), new THREE.MeshBasicMaterial({
      map: this._coneTexture(), color: '#FFFFFF', transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false, fog: false, side: THREE.DoubleSide }));
    cone.position.set(this.slotPos.x, this.slotPos.y - 0.02, this.slotPos.z);
    cone.visible = false;
    cone.renderOrder = 5;
    this.root.add(cone);
    this.cone = cone;
    this.root.add(this.aurora);
    void U0;
  }

  _coneTexture() {
    const c = document.createElement('canvas');
    c.width = 64; c.height = 128;
    const x = c.getContext('2d');
    const gr = x.createLinearGradient(0, 128, 0, 0);
    gr.addColorStop(0, 'rgba(255,255,255,0.95)'); gr.addColorStop(0.35, 'rgba(255,255,255,0.35)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
    x.fillStyle = gr; x.fillRect(0, 0, 64, 128);
    x.globalCompositeOperation = 'destination-out';
    for (let i = 0; i < 64; i += 8) { x.fillStyle = 'rgba(0,0,0,0.45)'; x.fillRect(i, 0, 3, 128); }
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.wrapS = THREE.RepeatWrapping;
    return t;
  }

  _buildAurora(time) {
    const { radius: R, span, base, arch, height, segS, segV } = AURORA;
    const n = (segS + 1) * (segV + 1);
    const pos = new Float32Array(n * 3), nor = new Float32Array(n * 3), aS = new Float32Array(n), aV = new Float32Array(n);
    const C = this.pivot;
    let k = 0;
    for (let j = 0; j <= segV; j++) {
      for (let i = 0; i <= segS; i++) {
        const s = i / segS, v = j / segV;
        const b = (s - 0.5) * span;
        const e = base + arch * Math.sin(Math.PI * s) + v * height * (0.75 + 0.25 * Math.sin(Math.PI * s));
        const ce = Math.cos(e);
        pos[k * 3] = C.x + R * Math.sin(b) * ce;
        pos[k * 3 + 1] = C.y + R * Math.sin(e);
        pos[k * 3 + 2] = C.z - R * Math.cos(b) * ce;
        nor[k * 3] = Math.sin(b); nor[k * 3 + 1] = 0; nor[k * 3 + 2] = -Math.cos(b);
        aS[k] = s; aV[k] = v;
        k++;
      }
    }
    const idx = [];
    for (let j = 0; j < segV; j++) {
      for (let i = 0; i < segS; i++) {
        const a = j * (segS + 1) + i, b = a + 1, c = a + segS + 1, d = c + 1;
        idx.push(a, c, b, b, c, d);
      }
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
    geo.setAttribute('aS', new THREE.BufferAttribute(aS, 1));
    geo.setAttribute('aV', new THREE.BufferAttribute(aV, 1));
    geo.setIndex(idx);
    const mat = new THREE.ShaderMaterial({
      uniforms: { uTime: time, uAlpha: { value: 0 }, uReveal: { value: 0 }, uS0: { value: 0.5 } },
      vertexShader: AURORA_VERT, fragmentShader: AURORA_FRAG, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false, side: THREE.DoubleSide,
    });
    mat.name = 'uplink:aurora';
    const m = new THREE.Mesh(geo, mat);
    m.name = 'uplink_aurora';
    m.frustumCulled = false;
    m.visible = false;
    m.renderOrder = -5;
    return m;
  }

  _registerInteract() {
    const g = this.game, I = g.interact;
    if (!I) return;
    const kp = new THREE.Vector3().fromArray((this.crank.userData.interact && this.crank.userData.interact.point) || [0, 1, -0.55]).applyMatrix4(this.crank.matrixWorld);
    this._crankItem = I.register({
      id: 'machine_uplink_crank', pos: kp, radius: 1.35,
      enabled: () => this.built && !this.aligned && !this.disabled,
      prompt: () => (this._powered() ? { hold: U.alignHold } : { plug: true }),
      hold: 0,
      use: () => { if (this._powered()) this._lock(); else this._unpoweredPoke(); },
      onHold: (p) => { this.align = p * U.alignHold; this._crankHeldAt = g.time.realNow; },
    });
    const cp = new THREE.Vector3().fromArray((this.cradle.userData.interact && this.cradle.userData.interact.point) || [0, 1.3, -0.55]).applyMatrix4(this.cradle.matrixWorld);
    this._cradleItem = I.register({
      id: 'machine_uplink', pos: cp, radius: 1.4,
      enabled: () => this.built && this.aligned && !this.disabled && this._powered() && (this.phase === 'ready' || (this.phase === 'idle' && !!this._upgradable())),
      prompt: () => {
        if (this.phase === 'ready') return {};
        const s = this._upgradable();
        return s ? { cost: s.upgraded ? U.reroll : U.cost } : null;
      },
      use: () => { if (this.phase === 'ready') this._takeWeapon(); else if (this.phase === 'idle') this._start(false); },
    });
  }

  // ============================================================================================ helpers
  _powered() { return !!this.game.machines?.powerOn; }

  _lit(pos) {
    if (!this._powered()) return false;
    const so = this.game.signon;
    try { return so && typeof so.waveReached === 'function' ? so.waveReached(pos) : true; } catch (err) { return true; }
  }

  _upgradable() {
    const W = this.game.weapons;
    const s = W && W.slots ? W.slots[W.current] : null;
    if (!s) return null;
    const d = W.defOf ? W.defOf(s.id, true) : null;
    return d && d.isUpgraded ? s : null;
  }

  _glow(color, intensity) {
    const q = Math.round(intensity * 5) / 5;
    const key = `${color}|${q}`;
    let m = this._glowCache.get(key);
    if (!m) {
      m = q > 0 ? this.game.mats.glow(color, q) : this.game.mats.toon('#3A3440', { rough: 0.4 });
      this._glowCache.set(key, m);
    }
    return m;
  }

  satellitePos(out = new THREE.Vector3()) { return out.copy(this.satPos || this.pivot || _v.set(0, 50, 0)); }

  _satDir(u, out) {
    const b = lerp(SAT.b0, SAT.b1, u) * DEG;
    const e = (SAT.el0 + SAT.elPeak * Math.sin(Math.PI * u)) * DEG;
    return out.set(Math.sin(b) * Math.cos(e), Math.sin(e), -Math.cos(b) * Math.cos(e));
  }

  // ============================================================================================ per frame
  update(dt) {
    if (!this.built) return;
    const g = this.game;
    this._t += dt;
    this._time.value += dt;
    this._updateSatellite(dt);
    this._updateCrank(dt);
    if (this.phase === 'seq') this._updateSeq(dt);
    else if (this.phase === 'ready') this._updateReady(dt);
    this._updateFly(dt);
    this._updateDish(dt);
    this._updateLights(dt);
    this._updateAurora(dt);
    this._updateFlash(dt);
    void g;
  }

  _updateSatellite(dt) {
    const rate = this.busy && this.phase === 'seq' ? SAT.busyRate : 1;
    this._satT = (this._satT + dt * rate) % SAT.period;
    const u = this._satT / SAT.period;
    this._satDir(u, _v);
    this.satPos.copy(this.pivot).addScaledVector(_v, SAT.radius);
    this.sat.position.copy(this.satPos);
    // local -y faces the Earth (the dish); wings roughly along the pass
    _w.copy(_v).negate();
    _q.setFromUnitVectors(_u.set(0, -1, 0), _w);
    this.sat.quaternion.copy(_q);
    this.satModel.rotation.y = 0.35 + Math.sin(this._t * 0.2) * 0.1;
    const alpha = smooth(0, 0.07, u) * (1 - smooth(0.93, 1, u));
    this._satAlpha = alpha;
    this.sat.visible = alpha > 0.02;
    // beacon: red blink (1 Hz) until locked, then green double-blink; flare during the uplink
    const flare = this.phase === 'seq' && !this.reroll && this.seqT >= FULL.flare && this.seqT < FULL.flare + 0.7;
    const locked = this.aligned;
    const ph = this._t % 1;
    const on = locked ? (ph < 0.12 || (ph > 0.24 && ph < 0.36)) : ph < 0.45;
    const beacon = this.satParts.beacon;
    if (beacon) beacon.material = flare ? this._beaconMats.flare : on ? (locked ? this._beaconMats.green : this._beaconMats.red) : this._beaconMats.off;
    const hm = this.satHalo.material;
    hm.color.set(flare ? '#FFFFFF' : locked ? (PAL.laughTrack || '#52E04A') : '#FF5A4A');
    hm.opacity = alpha * (flare ? 1 : on ? 1 : 0.3);
    this.satHalo.scale.setScalar(flare ? 18 : on ? 10 : 6);
  }

  // --- alignment crank ---------------------------------------------------------------------------------------
  _updateCrank(dt) {
    const g = this.game, I = g.interact, item = this._crankItem;
    const powered = this._powered();
    if (item) item.hold = powered && !this.aligned ? U.alignHold : 0;
    const focused = !!I && I.current === item;
    const down = !!g.input?.down?.('interact');
    const holding = focused && down && powered && !this.aligned && !this.disabled && dt > 0 && !(I._holdDone);
    if (holding && !this._wasHolding) {
      // resume from the (decayed) progress instead of zero: interact adds dt / hold on top of this and calls onHold
      I._holdItem = item;
      I.progress = clamp01(this.align / U.alignHold);
    }
    this._wasHolding = holding;
    if (holding) {
      if (!this._cranking) this._startCrank();
    } else {
      if (this._cranking) this._stopCrank();
      if (!this.aligned && this.align > 0 && dt > 0) this.align = Math.max(0, this.align - DECAY * dt);
    }
    // wheel + gauge + grip glow
    const P = this.P.crank;
    if (P.wheel) {
      this._wheelV = lerp(this._wheelV || 0, this._cranking ? 7.5 : 0, Math.min(1, dt * 8));
      if (!this._cranking && !this.aligned && this.align > 0) this._wheelV = lerp(this._wheelV, -DECAY * 2.2, Math.min(1, dt * 4));
      P.wheel.rotation.z += this._wheelV * dt;
      if (this._jiggle > 0) { this._jiggle -= dt; P.wheel.rotation.z += Math.sin(this._jiggle * 60) * 0.02; }
    }
    if (P.needle) {
      const k = this.aligned ? 1 : clamp01(this.align / U.alignHold);
      const want = lerp(this.crankRig.needleMax ?? 1.05, this.crankRig.needleMin ?? -1.05, k) + (this._cranking ? Math.sin(this._t * 40) * 0.03 : 0);
      P.needle.rotation.z += (want - P.needle.rotation.z) * Math.min(1, dt * 12);
    }
    if (P.handle) {
      const lit = this._lit(this.crank.position);
      const level = !lit || this.disabled ? 0 : this.aligned ? 0.25 : this._cranking ? 1 : 0.35 + 0.65 * (0.5 + 0.5 * Math.sin(this._t * 5.2));
      if (level !== this._gripLevel) {
        this._gripLevel = level;
        try { setCrankGlow(g, this.crank, level); } catch (err) { /* prop helper */ }
      }
    }
  }

  _startCrank() {
    const g = this.game;
    this._cranking = true;
    try { this._crankLoop = g.audio?.loop?.('dish_crank', { pos: this.crank.position.clone().setY(1), vol: 0.9 }) || null; } catch (err) { this._crankLoop = null; }
  }

  _stopCrank() {
    this._cranking = false;
    try { this._crankLoop?.stop?.(0.15); } catch (err) { /* audio */ }
    this._crankLoop = null;
  }

  _onHurt() {
    if (!this._cranking || this.aligned) return;
    this._penalty();
  }

  _penalty() {
    const g = this.game, I = g.interact;
    this.align *= 0.5;
    if (I && I._holdItem === this._crankItem) I.progress = clamp01(this.align / U.alignHold);
    this._tilt.v -= 1.6;
    this._jiggle = 0.25;
    _v.copy(this.pivot).setY(this.pivot.y - 1.1);
    g.fx?.burst?.(_v, { shape: 'spark', count: 12, speed: 5, life: 0.4 });
    g.audio?.play?.('uplink_clang', { pos: _v, vol: 0.5, rate: 1.4 });
  }

  _unpoweredPoke() {
    const g = this.game;
    this._jiggle = 0.3;
    g.audio?.play?.('sponsor_denied', { pos: this.crank.position });
    _v.set(0, this.crankRig.hubY ?? 1, -0.1).applyMatrix4(this.crank.matrixWorld);
    g.fx?.burst?.(_v, { shape: 'spark', count: 4, speed: 2.5, life: 0.25, colors: ['#7FE7FF', '#FFFFFF'] });
  }

  _lock() {
    const g = this.game;
    if (this.aligned) return;
    this.aligned = true;
    this.align = U.alignHold;
    this._stopCrank();
    this._lockT = 0;
    this._tilt.v += 2.4;
    g.level?.col?.setEnabled?.('uplink_droop', false);
    this._droopWasOff = true;
    if (g.nav?.built) g.nav.build();
    g.audio?.play?.('dish_lock', { pos: this.pivot });
    g.audio?.play?.('uplink_clang', { pos: this.pivot, vol: 0.6, rate: 0.8, delay: 0.05 });
    _v.copy(this.pivot);
    g.fx?.burst?.(_v, { shape: 'star', count: 14, speed: 4, life: 0.9, colors: [PAL.marqueeGold || '#FFD23A', '#FFFFFF', PAL.laughTrack || '#52E04A'] });
    g.fx?.flashLight?.(_v, PAL.marqueeGold || '#FFD23A', 8, 0.3);
    g.cam?.shake?.(0.12, 0.25);
    g.events.emit('machine:dish_aligned', {});
  }

  // --- the upgrade ---------------------------------------------------------------------------------------------
  _start(free = false) {
    const g = this.game, W = g.weapons;
    if (this.phase !== 'idle' || !this.aligned || this.disabled) return false;
    const s = this._upgradable();
    if (!s) return false;
    const reroll = !!s.upgraded;
    const cost = reroll ? U.reroll : U.cost;
    if (!free && !g.economy?.spend?.(cost, 'uplink')) return false;
    // where the gun leaves from: the hand, facing where the hero faces
    const hand = new THREE.Vector3();
    const slot = g.player?.hero?.slots?.handR;
    if (slot && slot.getWorldPosition) slot.getWorldPosition(hand); else hand.copy(g.player.pos).setY(g.player.pos.y + 1.2);
    // the holder turns the model's barrel (-z) toward -x: pre-rotate so it leaves pointing where the hero faces
    const fromQ = new THREE.Quaternion().setFromAxisAngle(UP, (g.player?.yaw || 0) - Math.PI / 2);
    const data = W.takeCurrent ? W.takeCurrent() : W.remove?.(s.id);
    if (!data) return false;
    this.weaponId = data.id;
    this.reroll = reroll;
    this._prevSignal = data.signal || null;
    const pool = reroll ? SIGNALS.filter((x) => x !== data.signal) : SIGNALS;
    this.signal = pool[Math.floor(g.rand() * pool.length) % pool.length];
    this.busy = true;
    this.phase = 'seq';
    this.seqT = 0;
    this.readyT = 0;
    this._cue = 0;
    this._cues = reroll ? this._rerollCues() : this._fullCues();
    this._clearGun();
    this._gun = this._makeGun(data.id, !!data.upgraded, data.signal || null);
    this._makeCopies(data.id, !!data.upgraded, data.signal || null);
    // the flight into the clamp
    this._flyer = this._flyer || new THREE.Group();
    this.game.scene.add(this._flyer);
    this._flyer.position.copy(hand);
    this._flyer.quaternion.copy(fromQ);
    this._flyer.add(this._gun);
    this._fly = { t: 0, dur: FULL.land, from: hand, fromQ, prev: hand.clone() };
    this._jaw.target = 1;
    // the magnet's kick: the hero stumbles a step back (and the camera gets the clamp in view)
    const p = g.player;
    if (p && p.knockback) {
      _v.set(p.pos.x - this.slotPos.x, 0, p.pos.z - this.slotPos.z);
      const d = _v.length();
      if (d < 2.6 && d > 1e-3) {
        // back and a little to the hero's left, so the right-shoulder camera sees the clamp past the hero
        _v.divideScalar(d).add(_w.set(-Math.cos(p.yaw || 0), 0, Math.sin(p.yaw || 0)).multiplyScalar(0.55)).normalize();
        p.knockback(_v.multiplyScalar(7));
      }
    }
    g.cam?.shake?.(0.1, 0.18);
    g.events.emit('machine:uplink_start', { weaponId: this.weaponId });
    return true;
  }

  _fullCues() {
    const g = this.game, A = g.audio;
    return [
      [0.0, () => { A?.play?.('uplink_motor', { pos: this.pivot, dur: FULL.swivel + 0.1 }); }],
      [FULL.split, () => this._beginSplit()],
      [FULL.beam, () => this._beginBeam()],
      [FULL.beam + 0.2, () => { this._speaker('crowd_ooh', { vol: 0.8 }); }],
      [FULL.flare, () => this._beginFlare()],
      [FULL.retract, () => { this._retractT = 0; }],
      [FULL.streams, () => this._beginStreams()],
      [FULL.snap - 1.1, () => this._swapInsert()],
      [FULL.snap, () => this._snap()],
    ];
  }

  _rerollCues() {
    const g = this.game, A = g.audio;
    return [
      [0.0, () => { A?.play?.('uplink_motor', { pos: this.pivot, dur: 0.5 }); }],
      [RE.split, () => this._beginSplit()],
      [RE.converge, () => { A?.play?.('uplink_vwoom', { pos: this.slotPos, vol: 0.55, rate: 1.5 }); }],
      [RE.snap, () => this._snap()],
    ];
  }

  _updateSeq(dt) {
    this.seqT += dt;
    const t = this.seqT;
    while (this._cue < this._cues.length && t >= this._cues[this._cue][0]) {
      const fn = this._cues[this._cue++][1];
      try { fn(); } catch (err) { console.error('[uplink] cue failed', err); }
    }
    if (this.phase !== 'seq') return;
    this._animCopies(t);
    this._animBeam(dt, t);
    this._animStreams(t);
  }

  _speaker(id, opts = {}) {
    const g = this.game;
    try {
      if (g.screens && typeof g.screens.speaker === 'function') return g.screens.speaker(id, opts);
    } catch (err) { /* screens is someone else's */ }
    return g.audio?.play?.(id, opts);
  }

  // Gun model in the HAND convention, centred and scaled for the clamp (barrel toward the cradle's -x).
  _makeGun(id, upgraded, signal) {
    const g = this.game, W = g.weapons;
    let model;
    try { model = W.buildModel(id, upgraded, signal); } catch (err) { model = null; }
    if (!model) model = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.12, 0.08), g.mats.toon('#888888'));
    const def = W.defOf ? W.defOf(id, upgraded) : null;
    const wrap = new THREE.Group();
    wrap.name = `uplink_gun:${id}`;
    const inner = new THREE.Group();
    inner.rotation.y = Math.PI / 2;
    inner.add(model);
    wrap.add(inner);
    const s = (def && def.scale) || 1;
    model.updateMatrixWorld(true);
    _box.setFromObject(model);
    if (!_box.isEmpty()) {
      _box.getCenter(_v);
      model.position.sub(_v);
      const size = _box.getSize(_w);
      const len = Math.max(size.x, size.y, size.z) * s;
      inner.scale.setScalar(s * (len > 1.05 ? 1.05 / len : 1));
    } else inner.scale.setScalar(s);
    model.traverse((o) => { if (o.isMesh) { o.castShadow = true; } });
    return wrap;
  }

  _makeCopies(id, upgraded, signal) {
    for (const c of this._copies) c.removeFromParent();
    this._copies = [];
    for (let i = 0; i < 3; i++) {
      const c = this._makeGun(id, upgraded, signal);
      c.traverse((o) => { if (o.isMesh) { o.material = this._copyMats[i]; o.castShadow = false; o.renderOrder = 6; } });
      c.visible = false;
      this.splitRoot.add(c);
      this._copies.push(c);
    }
    this.splitRoot.scale.set(1, 1, 1);
    this.splitRoot.position.copy(this.holder.position);
  }

  _clearGun() {
    if (this._gun) { this._gun.removeFromParent(); this._gun = null; }
  }

  _updateFly(dt) {
    const f = this._fly;
    if (f) {
      f.t += dt;
      const k = clamp01(f.t / f.dur);
      const e = k * k * (3 - 2 * k);
      const P0 = f.from, P2 = this.slotPos;
      _u.lerpVectors(P0, P2, 0.5).setY(Math.max(P0.y, P2.y) + 0.9);
      const a = (1 - e) * (1 - e), b = 2 * (1 - e) * e, c = e * e;
      _v.set(a * P0.x + b * _u.x + c * P2.x, a * P0.y + b * _u.y + c * P2.y, a * P0.z + b * _u.z + c * P2.z);
      this.game.fx?.tracer?.(f.prev, _v, '#9FE8FF', 0.05);
      f.prev.copy(_v);
      this._flyer.position.copy(_v);
      this._flyer.quaternion.slerpQuaternions(f.fromQ, this.slotQuat, e);
      _q.setFromAxisAngle(_w.set(1, 0, 0), Math.sin(e * Math.PI) * 1.2);
      this._flyer.quaternion.multiply(_q);
      const st = 1 + Math.sin(k * Math.PI) * 0.25;
      this._flyer.scale.set(1 / Math.sqrt(st), 1 / Math.sqrt(st), st);
      if (k >= 1) this._land();
    }
    const t = this._take;
    if (t) {
      t.t += dt;
      const k = clamp01(t.t / 0.2);
      const hand = this.game.player?.hero?.slots?.handR;
      if (hand) hand.getWorldPosition(_w); else _w.copy(this.game.player.pos).setY(1.2);
      _v.lerpVectors(this.slotPos, _w, k * k);
      _v.y += Math.sin(k * Math.PI) * 0.35;
      t.obj.position.copy(_v);
      t.obj.scale.setScalar(1 - 0.6 * k);
      if (k >= 1) { t.obj.removeFromParent(); this._take = null; }
    }
    // jaws: spring toward open (1) / closed (0)
    spring(this._jaw, this._jaw.target, 260, 0.35, Math.min(dt, 1 / 30));
    const P = this.P.cradle, R = this.cradleRig;
    if (P.jawF) P.jawF.rotation.x = lerp(R.jawClosed ?? 0, R.jawOpenF ?? -0.5, this._jaw.x);
    if (P.jawB) P.jawB.rotation.x = lerp(R.jawClosed ?? 0, R.jawOpenB ?? 0.5, this._jaw.x);
  }

  _land() {
    const g = this.game;
    this._fly = null;
    this._flyer.scale.set(1, 1, 1);
    if (this._gun) { this._gun.position.set(0, 0, 0); this._gun.quaternion.identity(); this.holder.add(this._gun); }
    this._flyer.removeFromParent();
    this._jaw.target = 0;
    this._jaw.v = -6;
    g.audio?.play?.('uplink_clang', { pos: this.slotPos });
    g.fx?.burst?.(this.slotPos, { shape: 'spark', count: 14, speed: 4.5, life: 0.35, colors: ['#9FE8FF', '#FFFFFF', '#FFE8A0'] });
    g.fx?.flashLight?.(this.slotPos, '#9FE8FF', 5, 0.15);
    if (g.player && g.player.pos.distanceTo(this.slotPos) < 6) g.cam?.shake?.(0.14, 0.2);
    this._lampFlash = 0.25;
  }

  _beginSplit() {
    const g = this.game;
    this._splitT = 0;
    if (this._gun) this._gun.visible = false;
    for (const c of this._copies) c.visible = true;
    g.audio?.play?.('uplink_triad', { pos: this.slotPos });
    g.fx?.burst?.(this.slotPos, { shape: 'star', count: 6, speed: 1.6, life: 0.5, colors: RGB });
    for (const b of this.lampBeams) b.visible = true;
  }

  _lampWorld(i, out) {
    const key = ['lampR', 'lampG', 'lampB'][i];
    const l = this.P.cradle[key];
    if (l && l.getWorldPosition) return l.getWorldPosition(out);
    return out.copy(this.hornPos);
  }

  _orient(mesh, from, to, radius) {
    _w.subVectors(to, from);
    const len = Math.max(1e-3, _w.length());
    mesh.position.copy(from);
    mesh.quaternion.setFromUnitVectors(UP, _w.divideScalar(len));
    mesh.scale.set(radius, len, radius);
    return len;
  }

  // R/G/B copies: overlap (white) -> drift 0.3 m apart orbiting the barrel axis -> (full) stretch up the beam and fade,
  // (Re-Uplink) spiral back in, the signal colour brightest, until the snap.
  _animCopies(t) {
    const R = this.reroll ? RE : FULL;
    if (!this._copies.length || t < R.split) return;
    const ts = t - R.split;
    const orbitEnd = this.reroll ? RE.converge : FULL.beam;
    let r, spin, fade = 1, up = 0, stretch = 1;
    const spinRate = 1.6 + ts * 2.2;
    spin = ts * spinRate;
    r = ORBIT_R * easeOutBack(ts / 0.45, 2.2);
    if (t >= orbitEnd) {
      const k = this.reroll ? clamp01((t - RE.converge) / (RE.snap - RE.converge)) : clamp01((t - FULL.beam) / 0.55);
      if (this.reroll) {
        r = ORBIT_R * (1 - easeInCubic(k));
        spin += k * k * 18;
      } else {
        r = ORBIT_R * (1 - k * 0.8);
        up = easeInCubic(k) * 4.5;
        stretch = 1 + easeInCubic(k) * 5;
        fade = 1 - smooth(0.45, 1, k);
      }
    }
    this.splitRoot.position.set(this.holder.position.x, this.holder.position.y + up, this.holder.position.z);
    this.splitRoot.scale.set(1, stretch, 1);
    const sig = SIGNALS.indexOf(this.signal);
    for (let i = 0; i < 3; i++) {
      const c = this._copies[i];
      const a = spin + (i * TAU) / 3;
      c.position.set(0, Math.cos(a) * r, Math.sin(a) * r);
      c.rotation.x = Math.sin(spin * 0.5 + i) * 0.25;
      const bright = this.reroll && t >= RE.converge ? (i === sig ? 1.35 : 0.7) : 1;
      this._copyMats[i].opacity = fade * (0.85 + 0.15 * Math.sin(t * 30 + i * 2)) * bright;
    }
    // lamp beams while splitting
    const on = t < orbitEnd + (this.reroll ? 0.6 : 0.1);
    for (let i = 0; i < 3; i++) {
      const b = this.lampBeams[i];
      b.visible = on;
      if (!on) continue;
      this._lampWorld(i, _u);
      this._orient(b, _u, this.slotPos, 0.028 + 0.012 * Math.sin(t * 40 + i));
      b.material.opacity = smooth(R.split, R.split + 0.15, t) * (0.6 + 0.4 * Math.sin(t * 55 + i * 1.7));
    }
  }

  _beginBeam() {
    const g = this.game;
    this.beam.visible = true;
    this.beamHead.visible = true;
    this._retractT = -1;
    g.audio?.play?.('uplink_vwoom', { pos: this.slotPos });
    this._speaker('tone_1khz', { dur: 0.9, vol: 0.7 });
    try {
      this._insertObj = this._insertModel(this.weaponId, false, null);
      g.screens?.setInsert?.(this._insertObj);
      // world-time sequence vs. the screens' own clock (a commercial could pause us): hold it until the snap cancels it
      this._override = g.screens?.override?.('satellite', ['scr_decor', 'scr_mc_canned', 'scr_feed_*'], 20) || null;
    } catch (err) { console.warn('[uplink] satellite override failed', err); }
  }

  _insertModel(id, upgraded, signal) {
    const W = this.game.weapons;
    let model;
    try { model = W.buildModel(id, upgraded, signal); } catch (err) { return null; }
    const wrap = new THREE.Group();
    const inner = new THREE.Group();
    inner.rotation.y = Math.PI / 2;
    inner.add(model);
    wrap.add(inner);
    model.updateMatrixWorld(true);
    _box.setFromObject(model);
    if (!_box.isEmpty()) {
      _box.getCenter(_v);
      model.position.sub(_v);
      const size = _box.getSize(_w);
      inner.scale.setScalar(0.62 / Math.max(0.1, size.x, size.y, size.z));
    }
    wrap.position.y = 0.16;
    wrap.rotation.z = 0.12;
    return wrap;
  }

  _swapInsert() {
    const g = this.game;
    try {
      const up = this._insertModel(this.weaponId, true, this.signal);
      if (up) { g.screens?.setInsert?.(up); this._insertObj = up; }
    } catch (err) { /* screens is someone else's */ }
  }

  _animBeam(dt, t) {
    if (!this.beam.visible) return;
    const from = this.hornPos, to = this.satPos;
    const len = this._orient(this.beam, from, to, 1);
    const U0 = this.beam.material.uniforms;
    U0.uLen.value = len;
    const shoot = clamp01((t - FULL.beam - 0.08) / (FULL.beamTop - FULL.beam - 0.08));
    U0.uHead.value = Math.max(0.001, easeOutCubic(shoot) ** 1.3);
    const rad = 0.26 * easeOutBack(clamp01((t - FULL.beam) / 0.3), 2) * (1 + 0.08 * Math.sin(t * 24));
    this.beam.scale.x = this.beam.scale.z = Math.max(0.01, rad);
    if (this._retractT >= 0) {
      this._retractT += dt;
      U0.uTail.value = easeInCubic(this._retractT / 0.3);
      if (this._retractT >= 0.3) { this.beam.visible = false; this.beamHead.visible = false; U0.uTail.value = 0; this._retractT = -1; return; }
    } else U0.uTail.value = 0;
    U0.uAlpha.value = 1;
    // head sprite at the tip
    const hk = this._retractT >= 0 ? 1 : U0.uHead.value;
    this.beamHead.position.lerpVectors(from, to, hk);
    const d = this.game.camera.position.distanceTo(this.beamHead.position);
    this.beamHead.scale.setScalar(Math.max(0.8, d * 0.06) * (shoot < 1 ? 1.4 : 0.8 + 0.2 * Math.sin(t * 20)));
    this.beamHead.material.opacity = shoot < 1 ? 1 : 0.7;
  }

  _beginFlare() {
    const g = this.game;
    this._flareT = 0;
    this.satFlare.visible = true;
    g.audio?.play?.('uplink_aurora', {});
    this.aurora.visible = true;
    this._auroraT = 0;
    const b = Math.atan2(this.satPos.x - this.pivot.x, -(this.satPos.z - this.pivot.z));
    this.aurora.material.uniforms.uS0.value = clamp01(b / AURORA.span + 0.5);
    // Yard zombies stop and gawk up at the sky for 0.8 s
    for (const z of g.zombies?.alive || []) {
      if (!z || z.dead) continue;
      const area = z.area || g.level?.areaAt?.(z.pos.x, z.pos.z);
      if (area !== 'yard') continue;
      if (z.state && !['chase', 'attack', 'approach'].includes(z.state)) continue;
      z.gawkT = 0.8 + Math.random() * 0.15;
      z.gawkAt = this.satPos.clone();
    }
  }

  _beginStreams() {
    this._streamT = 0;
    this._streamSpark = false;
    for (const s of this.streams) s.visible = true;
    this.game.audio?.play?.('uplink_vwoom', { pos: this.slotPos, vol: 0.4, rate: 0.7 });
  }

  // Three thin streams race down from around the satellite, meet in the clamp, then brighten (the signal colour
  // swelling thickest) until the snap.
  _animStreams(t) {
    if (!this.streams[0].visible) return;
    const k = clamp01((t - FULL.streams) / (FULL.streamsDown - FULL.streams));
    const hold = clamp01((t - FULL.streamsDown) / (FULL.snap - FULL.streamsDown));
    const sig = SIGNALS.indexOf(this.signal);
    for (let i = 0; i < 3; i++) {
      const s = this.streams[i];
      const a = (i / 3) * TAU + t * 1.4;
      const spread = 9 * (1 - 0.6 * hold);
      _u.set(Math.cos(a) * spread, Math.sin(a) * spread * 0.6, Math.sin(a + 1) * spread * 0.4);
      _v.copy(this.satPos).add(_u);
      const lead = i === sig;
      const r = (lead ? 0.13 : 0.06) * (1 + hold * (lead ? 1.0 : 0.3)) * (1 + 0.15 * Math.sin(t * 50 + i));
      const len = this._orient(s, this.slotPos, _v, r);
      const U0 = s.material.uniforms;
      U0.uLen.value = len;
      U0.uHead.value = Math.max(0.001, k * k * (3 - 2 * k));
      U0.uAlpha.value = (lead ? 0.9 : 0.5) * (1 + hold * 0.4);
    }
    if (hold > 0 && !this._streamSpark) {
      this._streamSpark = true;
      this.game.fx?.burst?.(this.slotPos, { shape: 'spark', count: 10, speed: 3, life: 0.3, colors: [...LAMP_COL, '#FFFFFF'] });
    }
  }

  _snap() {
    const g = this.game;
    const id = this.weaponId, sig = this.signal;
    for (const s of this.streams) s.visible = false;
    for (const b of this.lampBeams) b.visible = false;
    for (const c of this._copies) c.visible = false;
    this.beam.visible = false;
    this.beamHead.visible = false;
    this.splitRoot.scale.set(1, 1, 1);
    this.splitRoot.position.copy(this.holder.position);
    this._clearGun();
    this._gun = this._makeGun(id, true, sig);
    this._gun.scale.setScalar(0.01);
    this.holder.add(this._gun);
    this._popT = 0;
    this._jaw.target = 1;
    this.cone.visible = true;
    this.cone.material.color.set(SIGNAL_COLORS[sig] || '#FFFFFF');
    // the flash
    this._flashT = 0;
    this.flash.visible = true;
    const col = SIGNAL_COLORS[sig] || '#FFFFFF';
    g.fx?.flashLight?.(this.slotPos, '#FFFFFF', 12, 0.3);
    g.fx?.burst?.(this.slotPos, { shape: 'star', count: 16, speed: 4.2, life: 0.9, size: 0.12, colors: [col, '#FFFFFF', PAL.marqueeGold || '#FFD23A'] });
    g.fx?.burst?.(this.slotPos, { shape: 'confetti', count: 22, speed: 4.5, life: 1.3, colors: [col, ...BARS] });
    g.fx?.burst?.(this.slotPos, { shape: 'spark', count: 14, speed: 6, life: 0.4, colors: [col, '#FFFFFF'] });
    if (g.player && g.player.pos.distanceTo(this.slotPos) < 12) { g.cam?.shake?.(0.22, 0.3); g.hud?.whiteout?.(0.5, 0.22); }
    g.audio?.play?.('uplink_snap', { pos: this.slotPos });
    g.audio?.play?.('uplink_fanfare', { pos: this.slotPos, delay: 0.1 });
    const name = this._nameOf(id);
    let shown = false;
    try { if (g.hud && typeof g.hud.chyron === 'function') { g.hud.chyron(name); shown = true; } } catch (err) { shown = false; }
    try {
      g.screens?.setInsert?.(null);
      if (this._override && this._override.active !== false) this._override.cancel?.();
    } catch (err) { /* ignore */ }
    this._override = null;
    this._insertObj = null;
    this.phase = 'ready';
    this.readyT = 0;
    this._flickT = 0;
    this._tickPlayed = false;
    g.events.emit('machine:uplink_ready', { weaponId: id, signal: sig, name, chyron: shown });
  }

  _nameOf(id) {
    const W = this.game.weapons;
    const d = W && W.defOf ? W.defOf(id, true) : null;
    return (d && (d.upgradedName || d.displayName || d.name)) || String(id).toUpperCase();
  }

  // --- ready: 15 s to take it -----------------------------------------------------------------------------------
  _updateReady(dt) {
    const g = this.game;
    this.readyT += dt;
    const t = this.readyT;
    const gun = this._gun;
    if (gun) {
      if (this._popT >= 0) {
        this._popT += dt;
        gun.scale.setScalar(Math.max(0.01, easeOutBack(this._popT / 0.3, 3)));
        if (this._popT >= 0.3) this._popT = -1;
      }
      // presented: it rises out of the horn onto the light cone and turns slowly so the finish reads from all sides
      const lift = easeOutBack(t / 0.7, 1.4) * (GUN.show - GUN.rest);
      gun.position.y = lift + Math.sin(t * 2.4) * 0.018;
      gun.rotation.y = t * 0.9;
      gun.rotation.z = Math.sin(t * 1.7) * 0.06;
      // glints
      this._glintT = (this._glintT || 0) - dt;
      if (this._glintT <= 0 && t < U.flickerAt) {
        this._glintT = 0.55 + Math.random() * 0.4;
        _v.copy(this.slotPos).add(_w.set((Math.random() - 0.5) * 0.5, (Math.random() - 0.3) * 0.18, (Math.random() - 0.5) * 0.2));
        g.fx?.burst?.(_v, { shape: 'star', count: 1, speed: 0.2, life: 0.5, size: 0.1, colors: ['#FFFFFF', SIGNAL_COLORS[this.signal] || '#FFFFFF'] });
      }
      // bad reception from flickerAt: drop-outs + sideways tearing + static
      if (t >= U.flickerAt) {
        const f = clamp01((t - U.flickerAt) / (U.collect - U.flickerAt));
        this._flickT -= dt;
        if (this._flickT <= 0) {
          const off = Math.random() < 0.3 + 0.45 * f;
          this._flickOff = off;
          this._flickT = off ? 0.04 + Math.random() * (0.05 + 0.12 * f) : 0.06 + Math.random() * (0.3 - 0.2 * f);
          this._jx = (Math.random() - 0.5) * 0.12 * (0.4 + f);
          if (off && Math.random() < 0.5) g.fx?.burst?.(this.slotPos, { shape: 'static', count: 4, speed: 1.2, size: 0.05, life: 0.3 });
        }
        gun.visible = !this._flickOff;
        gun.position.x = this._jx;
        this._snd = (this._snd ?? 0) - dt;
        if (this._snd <= 0) { this._snd = 0.85; g.audio?.play?.('uplink_flicker', { pos: this.slotPos, vol: 0.7 }); }
        if (!this._tickPlayed) { this._tickPlayed = true; g.audio?.play?.('tele_tick', { pos: this.slotPos, dur: U.collect - U.flickerAt, vol: 0.6 }); }
      } else { gun.visible = true; gun.position.x = 0; }
    }
    if (this.cone && this.cone.visible) {
      this.cone.material.opacity = smooth(0, 0.5, t) * (0.38 + 0.08 * Math.sin(t * 7)) * (gun && !gun.visible ? 0.25 : 1);
      if (this.cone.material.map) this.cone.material.map.offset.x = t * 0.08;
    }
    if (t >= U.collect) this._loseWeapon();
  }

  _takeWeapon() {
    const g = this.game, W = g.weapons;
    if (this.phase !== 'ready' || !this.weaponId) return;
    const id = this.weaponId, sig = this.signal;
    let ok = false;
    try { ok = !!W.give(id, { upgraded: true, signal: sig, source: 'uplink' }); } catch (err) { console.error('[uplink] give failed', err); }
    if (!ok) return;
    if (this._gun) {
      const obj = this._gun;
      obj.getWorldPosition(_v);
      obj.getWorldQuaternion(_q);
      const s = obj.getWorldScale(_w).x;
      this.game.scene.add(obj);
      obj.position.copy(_v); obj.quaternion.copy(_q); obj.scale.setScalar(s);
      obj.visible = true;
      this._take = { obj, t: 0 };
      this._gun = null;
    }
    this._jaw.target = 1;
    g.audio?.play?.('wallbuy_boing', { pos: g.player.pos });
    g.fx?.burst?.(this.slotPos, { shape: 'star', count: 6, speed: 2, life: 0.5, colors: [SIGNAL_COLORS[sig] || '#FFFFFF', '#FFFFFF'] });
    g.events.emit('machine:uplink_take', { weaponId: id });
    this._toIdle(false);
  }

  _loseWeapon() {
    const g = this.game;
    const id = this.weaponId;
    // beamed back up: a thin white stream shoots up out of the clamp, the gun dissolves into static
    g.fx?.burst?.(this.slotPos, { shape: 'static', count: 26, speed: 2.4, size: 0.08, life: 0.8 });
    g.fx?.burst?.(this.slotPos, { shape: 'star', count: 5, speed: 5, life: 0.5, dir: UP, cone: 0.3, colors: ['#FFFFFF'] });
    this._lost = { t: 0 };
    const s = this.streams[SIGNALS.indexOf(this.signal)] || this.streams[0];
    s.visible = true;
    this._lostStream = s;
    g.audio?.play?.('uplink_lost', { pos: this.slotPos });
    this._jaw.target = 1;
    g.events.emit('machine:uplink_lost', { weaponId: id });
    this._toIdle(false);
  }

  _toIdle(hard) {
    const g = this.game;
    this.phase = 'idle';
    this.busy = false;
    this.weaponId = null;
    this.signal = null;
    this.seqT = 0;
    this.readyT = 0;
    this._cues = [];
    this._cue = 0;
    this._clearGun();
    for (const c of this._copies) c.removeFromParent();
    this._copies = [];
    if (this._fly) { this._fly = null; this._flyer?.removeFromParent(); }
    if (hard) {
      if (this._take) { this._take.obj.removeFromParent(); this._take = null; }
      this._lost = null;
      this._flashT = -1;
      if (this.flash) this.flash.visible = false;
      if (this.aurora) { this.aurora.visible = false; this._auroraT = -1; }
      this._jaw.target = 1; this._jaw.x = 1; this._jaw.v = 0;
    }
    if (this.beam) { this.beam.visible = false; this.beamHead.visible = false; this._retractT = -1; }
    for (const s of this.streams || []) if (s !== this._lostStream || hard) s.visible = false;
    for (const b of this.lampBeams || []) b.visible = false;
    if (this.satFlare) this.satFlare.visible = false;
    if (this.cone) { this.cone.visible = false; this.cone.material.opacity = 0; }
    try {
      if (this._override && this._override.active !== false) this._override.cancel?.();
      if (this._insertObj) g.screens?.setInsert?.(null);
    } catch (err) { /* screens */ }
    this._override = null;
    this._insertObj = null;
    this.reroll = false;
    if (hard && this._dishGlow) { this._dishGlowK = 0; this._setDishGlow(0, '#000000'); }
  }

  _setDisabled(on) {
    const g = this.game;
    if (this.disabled === on) return;
    this.disabled = on;
    if (!on) return;
    // hand back whatever is in the machine (upgraded: it was paid for)
    if (this.weaponId && (this.phase === 'seq' || this.phase === 'ready')) {
      try { g.weapons?.give?.(this.weaponId, { upgraded: true, signal: this.signal, source: 'uplink' }); } catch (err) { /* ignore */ }
      g.events.emit('machine:uplink_take', { weaponId: this.weaponId });
    }
    this._toIdle(true);
    this._stopCrank();
  }

  // ============================================================================================ visuals
  _updateDish(dt) {
    if (!this.dish) return;
    const R = this.dishRig;
    let tilt, yaw, k = 18, zeta = 0.45, ky = 10, zy = 0.8;
    if (!this.aligned) {
      const p = clamp01(this.align / U.alignHold);
      tilt = lerp(R.droop, R.aligned, p * p * (3 - 2 * p)) + (this._cranking ? Math.sin(this._t * 23) * 0.012 : 0);
      yaw = 0;
      k = this._cranking ? 30 : 14; zeta = 0.5;
    } else if (this.phase === 'seq' && (this.reroll ? this.seqT < RE.snap : this.seqT < FULL.snap)) {
      // swivel onto Skylark-13 (the Re-Uplink only nudges)
      _v.subVectors(this.satPos, this.pivot);
      const want = Math.atan2(-_v.x, -_v.z) - this.dish.rotation.y;
      const el = Math.atan2(_v.y, Math.hypot(_v.x, _v.z));
      if (this.reroll) { tilt = R.aligned + 0.08 * Math.sin(Math.min(1, this.seqT / 0.5) * Math.PI); yaw = 0; }
      else { tilt = THREE.MathUtils.clamp(el, R.droop, 1.25); yaw = this._yaw.x + wrapPi(want - this._yaw.x); }
      k = 26; zeta = 0.55; ky = 16; zy = 0.62;
      if (this.seqT > 0.8) { k = 40; ky = 30; zy = 0.9; }
    } else {
      tilt = R.aligned + (this.disabled ? -0.25 : 0);
      yaw = 0;
      k = 10; zeta = 0.55; ky = 5.5; zy = 0.85;
    }
    const h = Math.min(dt, 1 / 30);
    if (h > 0) {
      spring(this._tilt, tilt, k, zeta, h);
      spring(this._yaw, yaw, ky, zy, h);
    }
    setUplinkPose(this.dish, { tilt: this._tilt.x, yaw: this._yaw.x });
    if (this._lockT >= 0) { this._lockT += dt; if (this._lockT > 2) this._lockT = -1; }
  }

  _updateLights(dt) {
    const g = this.game;
    const lit = this._lit(this.pivot) && !this.disabled;
    const boothLit = this._lit(this.booth.position) && !this.disabled;
    // rim bulbs
    const bulbs = this.P.dish.rimBulbs;
    if (bulbs && bulbs.instanceColor) {
      const n = bulbs.count;
      const t = this._t;
      let mode = 'off', speed = 12, color = PAL.marqueeGold || '#FFD23A';
      if (lit && !this.aligned) mode = 'progress';
      else if (lit && this.phase === 'seq') { mode = 'rainbow'; speed = 40; }
      else if (lit && this.phase === 'ready') { mode = 'chase'; speed = 28; color = SIGNAL_COLORS[this.signal] || color; }
      else if (lit) mode = this._lockT >= 0 ? 'lock' : 'chase';
      const p = clamp01(this.align / U.alignHold);
      const head = Math.floor(t * speed);
      for (let i = 0; i < n; i++) {
        let v = 0.03, col = color;
        if (mode === 'progress') {
          const f = i / n;
          v = f < p ? 0.9 : 0.06;
          if (f < p && f > p - 1 / n) v = 1.6;
          if (p <= 0) v = 0.06 + 0.1 * (0.5 + 0.5 * Math.sin(t * 5.2));
        } else if (mode === 'chase' || mode === 'rainbow') {
          const kk = ((i - head) % 4 + 4) % 4;
          v = kk === 0 ? 1.4 : kk === 1 ? 0.45 : 0.14;
          if (mode === 'rainbow') col = BARS[(i + Math.floor(t * 6)) % 7];
        } else if (mode === 'lock') {
          v = Math.sin(this._lockT * 18 + i * 0.5) > 0 ? 1.6 : 0.3;
          col = '#FFFFFF';
        }
        _c.set(col).multiplyScalar(v);
        bulbs.setColorAt(i, _c);
      }
      bulbs.instanceColor.needsUpdate = true;
    }
    // horn lamps: dark before alignment; steady after; flashing during the split; the signal lamp leads when ready
    const P = this.P.cradle;
    if (this._lampFlash > 0) this._lampFlash -= dt;
    ['lampR', 'lampG', 'lampB'].forEach((key, i) => {
      const m = P[key];
      if (!m) return;
      let lv = 0;
      if (lit && this.aligned) {
        lv = 0.45;
        if (this.phase === 'seq') lv = this.seqT >= (this.reroll ? RE.split : FULL.split) ? 0.9 + 0.1 * Math.sin(this._t * 40 + i) : 0.7;
        if (this.phase === 'ready') lv = SIGNALS[i] === this.signal ? 1 : 0.2;
        if (this._lampFlash > 0) lv = 1;
      }
      m.material = this._glow(LAMP_COL[i], lv > 0 ? 0.4 + 2.8 * lv : 0);
    });
    // light anchors + floor pool
    const L = g.lights;
    if (L && L.setAnchor) {
      const hornOn = lit && this.aligned;
      const hc = this.phase === 'ready' ? (SIGNAL_COLORS[this.signal] || '#FFFFFF') : this.phase === 'seq' ? BARS[Math.floor(this._t * 8) % 7] : '#E8F4FF';
      const key = `${hornOn}|${hc}|${boothLit}`;
      if (key !== this._lightKey) {
        this._lightKey = key;
        L.setAnchor('uplink_horn', { enabled: hornOn, color: hc, intensity: this.phase === 'idle' ? 1.1 : this.phase === 'seq' ? 5.5 : 3 });
        L.setAnchor('uplink_booth', { enabled: boothLit });
      }
    }
    // the energised dish (rainbow wash while uplinking, the signal colour as it winds down)
    if (this._dishGlow) {
      let want = 0;
      if (lit && this.phase === 'seq') {
        const t = this.seqT;
        want = this.reroll ? 0.06 * smooth(RE.split, RE.split + 0.4, t) : 0.07 * smooth(0.5, 1.8, t) + 0.09 * smooth(1.8, 2.3, t) * (0.85 + 0.15 * Math.sin(this._t * 18));
      } else if (lit && this.phase === 'ready') want = 0.05 * (1 - smooth(0, 2.5, this.readyT));
      this._dishGlowK += (want - this._dishGlowK) * Math.min(1, dt * 5);
      if (this._dishGlowK < 0.004 && want === 0) this._dishGlowK = 0;
      const col = this.phase === 'ready' ? (SIGNAL_COLORS[this.signal] || '#FFFFFF') : BARS[Math.floor(this._t * 8) % 7];
      this._setDishGlow(this._dishGlowK, col);
    }
    if (this._pool && this._pool.set) {
      const want = lit && this.aligned ? 0.22 + (this.phase === 'seq' ? 0.12 * (0.5 + 0.5 * Math.sin(this._t * 20)) : 0) : 0;
      if (Math.abs(want - (this._poolI ?? -1)) > 0.01) { this._poolI = want; this._pool.set({ intensity: want }); }
    }
    // booth: dark before power, then its lamp panel blinks and the roof beacon flashes
    const B = this.P.booth;
    if (B.lamps) {
      if (boothLit) setBoothLamps(this.booth, this._t);
      else if (this._boothDark !== true) {
        const inst = B.lamps;
        for (let i = 0; i < inst.count; i++) { inst.getColorAt(i, _c); inst.setColorAt(i, _c.multiplyScalar(0.06)); }
        if (inst.instanceColor) inst.instanceColor.needsUpdate = true;
      }
      this._boothDark = !boothLit;
    }
    if (B.beacon) {
      const on = boothLit && (this._t % 1.2) < 0.5;
      B.beacon.material = this._glow(PAL.onAirRed || '#FF3B30', on ? 2.6 : 0);
    }
    if (B.console) {
      if (!this._consoleOn) { this._consoleOn = B.console.material; this._consoleOff = this.game.mats.toon('#1A2230', { rough: 0.3 }); }
      B.console.material = boothLit ? this._consoleOn : this._consoleOff;
    }
  }

  _updateAurora(dt) {
    const a = this.aurora;
    if (!a || !a.visible) {
      if (this._lost) this._updateLost(dt);
      return;
    }
    this._auroraT += dt;
    const t = this._auroraT;
    const U0 = a.material.uniforms;
    U0.uReveal.value = easeOutCubic(t / 2.4) * 1.9;
    U0.uAlpha.value = smooth(0, 0.6, t) * (1 - smooth(3.2, 7.2, t)) * 1.15;
    if (t > 7.3) { a.visible = false; this._auroraT = -1; }
    if (this._lost) this._updateLost(dt);
  }

  _updateLost(dt) {
    const L = this._lost;
    L.t += dt;
    const s = this._lostStream;
    if (s) {
      _v.copy(this.slotPos).setY(this.slotPos.y + 60);
      _v.x += 0.001;
      const len = this._orient(s, this.slotPos, _v, 0.05 * (1 - clamp01(L.t / 0.6)) + 0.005);
      const U0 = s.material.uniforms;
      U0.uLen.value = len;
      U0.uHead.value = 1;
      U0.uAlpha.value = 1.4 * (1 - clamp01(L.t / 0.6));
    }
    if (L.t > 0.6) { if (s) s.visible = false; this._lostStream = null; this._lost = null; }
  }

  _updateFlash(dt) {
    if (this._flashT >= 0 && this.flash.visible) {
      this._flashT += dt;
      const k = this._flashT / 0.45;
      this.flash.scale.setScalar(0.3 + 3.2 * easeOutCubic(k));
      this.flash.material.opacity = Math.max(0, 1 - k * k);
      if (k >= 1) { this.flash.visible = false; this._flashT = -1; }
    }
    if (this._flareT >= 0 && this.satFlare.visible) {
      this._flareT += dt;
      const k = this._flareT / 1.2;
      this.satFlare.scale.setScalar(6 + 60 * easeOutCubic(k));
      this.satFlare.material.opacity = Math.max(0, 1 - k) * this._satAlpha;
      this.satFlare.material.rotation = k * 0.8;
      if (k >= 1) { this.satFlare.visible = false; this._flareT = -1; }
    }
  }

  // ============================================================================================ debug / status
  status() {
    return {
      built: this.built, powered: this._powered(), aligned: this.aligned, align: +this.align.toFixed(2), busy: this.busy, phase: this.phase,
      seqT: +this.seqT.toFixed(2), readyT: +this.readyT.toFixed(2), weaponId: this.weaponId, signal: this.signal, reroll: this.reroll,
      disabled: this.disabled, cranking: this._cranking, tilt: +this._tilt.x.toFixed(3), yaw: +this._yaw.x.toFixed(3),
      sat: this.satPos ? this.satPos.toArray().map((v) => +v.toFixed(1)) : null, satVisible: !!(this.sat && this.sat.visible),
      beam: !!(this.beam && this.beam.visible), aurora: !!(this.aurora && this.aurora.visible), copies: this._copies.length,
      gun: !!this._gun,
    };
  }

  debugAlign() { if (!this.aligned) this._lock(); return this.aligned; }

  debugUpgrade(weaponId = null, { free = true } = {}) {
    const g = this.game, W = g.weapons;
    if (!this.aligned) this._lock();
    if (weaponId && !W.has?.(weaponId)) W.give?.(weaponId, { source: 'debug' });
    if (weaponId) { const i = W.slots.findIndex((s) => s.id === weaponId); if (i >= 0 && i !== W.current) W._equip ? W._equip(i, false) : W.switchTo?.(i); }
    return this._start(free);
  }

  debugTake() { this._takeWeapon(); return this.phase; }

  debugSkip(t) {
    if (this.phase === 'seq') { const dtt = Math.max(0, t - this.seqT); this.update(0); this._updateSeq(dtt); }
    else if (this.phase === 'ready') this.readyT = Math.max(this.readyT, t);
    return this.status();
  }

  debugHit() { this._penalty(); return this.align; }
}
