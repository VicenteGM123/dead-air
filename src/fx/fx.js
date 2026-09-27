// FX (ARCHITECTURE §10/§12, GDD §3.7): big readable cartoon VFX, all pooled (no allocation per effect).
//   burst(pos, {count, color|colors, speed, size, life, gravity, shape, dir, cone, drag}) — shapes:
//     'spark' (additive streaks along velocity), 'puff' (lit toon sphere clouds), 'confetti' (tumbling bars
//     colors), 'goo' (glossy blobs), 'static' (TV-snow chips), 'star' (spinning glow stars).
//   tracer(from, to, color, width), muzzle(pos, dir, color), impact(point, normal, kind), decal(point, normal,
//   kind, size) (kinds: 'hole' | 'scorch' | 'splat' | 'goo'), lightPool(pos, radius, color, intensity) -> handle
//   ({set({pos, radius, color, intensity}), remove()}), blob(object3d, radius) -> handle ({remove(), visible}),
//   text3d(pos, str, color), flashLight(pos, color, intensity, duration) (pooled light slot), shake(amount, dur).
// Every pool is an InstancedMesh (one draw call each, none while empty: pools hide themselves). Particles use
// world dt (they freeze with time.scale=0); blobs follow their objects every frame regardless.

import * as THREE from 'three';
import { PAL } from '../core/config.js';
import { radial, staticNoise, text as textTex } from '../core/textures.js';
import { extrudeShape } from '../core/geo.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

const _m = new THREE.Matrix4();
const _p = new THREE.Vector3();
const _s = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _q2 = new THREE.Quaternion();
const _e = new THREE.Euler();
const _c = new THREE.Color();
const _v = new THREE.Vector3();
const _z = new THREE.Vector3(0, 0, 1);
const _up = new THREE.Vector3(0, 1, 0);
const ZERO = new THREE.Matrix4().makeScale(0, 0, 0);

const DEFAULTS = {
  spark: { count: 10, speed: 7, size: 0.05, life: 0.35, gravity: 14, drag: 2, colors: ['#FFE8A0', '#FFC23A', '#FFFFFF'] },
  puff: { count: 7, speed: 1.6, size: 0.22, life: 0.7, gravity: -0.6, drag: 3, colors: ['#F4F1E8', '#E6DCCB'] },
  confetti: { count: 16, speed: 4.5, size: 0.07, life: 1.4, gravity: 7, drag: 1.4, colors: PAL.BARS },
  goo: { count: 8, speed: 3.5, size: 0.09, life: 0.8, gravity: 12, drag: 1, colors: [PAL.chromaBlue, '#4F86FF'] },
  static: { count: 14, speed: 2.8, size: 0.1, life: 0.9, gravity: 2, drag: 2, colors: ['#ffffff'] },
  star: { count: 5, speed: 2.4, size: 0.14, life: 0.8, gravity: 1, drag: 2, colors: [PAL.marqueeGold, '#FFF3B0'] },
};

// One particle shape = one InstancedMesh + struct-of-arrays simulation.
class ParticlePool {
  constructor(scene, geometry, material, cap, { align = false, fade = false, bounce = true } = {}) {
    this.cap = cap;
    this.n = 0;
    this.align = align;
    this.fade = fade;
    this.bounce = bounce;
    this.mesh = new THREE.InstancedMesh(geometry, material, cap);
    this.mesh.frustumCulled = false;
    this.mesh.castShadow = false;
    this.mesh.receiveShadow = false;
    this.mesh.count = 0;
    this.mesh.visible = false;
    this.mesh.setColorAt(0, _c.set(1, 1, 1));
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    scene.add(this.mesh);
    const f = (k) => new Float32Array(cap * k);
    this.pos = f(3); this.vel = f(3); this.col = f(3);
    this.life = f(1); this.max = f(1); this.size = f(1); this.rot = f(1); this.spin = f(1);
    this.grav = f(1); this.drag = f(1); this.floor = f(1);
    this._vec3 = [this.pos, this.vel, this.col];
    this._vec1 = [this.life, this.max, this.size, this.rot, this.spin, this.grav, this.drag, this.floor];
  }

  spawn(x, y, z, vx, vy, vz, color, size, life, grav, drag, floor) {
    let i = this.n;
    if (i >= this.cap) i = Math.floor(Math.random() * this.cap); // recycle a random live particle
    else this.n++;
    this.pos[i * 3] = x; this.pos[i * 3 + 1] = y; this.pos[i * 3 + 2] = z;
    this.vel[i * 3] = vx; this.vel[i * 3 + 1] = vy; this.vel[i * 3 + 2] = vz;
    this.col[i * 3] = color.r; this.col[i * 3 + 1] = color.g; this.col[i * 3 + 2] = color.b;
    this.size[i] = size; this.life[i] = life; this.max[i] = life;
    this.rot[i] = Math.random() * Math.PI * 2; this.spin[i] = (Math.random() - 0.5) * 16;
    this.grav[i] = grav; this.drag[i] = drag; this.floor[i] = floor;
    this.mesh.setColorAt(i, color);
    this.mesh.instanceColor.needsUpdate = true;
  }

  _kill(i) {
    const j = --this.n;
    if (i === j) return;
    for (const a of this._vec3) { a[i * 3] = a[j * 3]; a[i * 3 + 1] = a[j * 3 + 1]; a[i * 3 + 2] = a[j * 3 + 2]; }
    for (const a of this._vec1) a[i] = a[j];
  }

  update(dt, scaleCurve) {
    const P = this.pos, V = this.vel;
    for (let i = 0; i < this.n; i++) {
      this.life[i] -= dt;
      if (this.life[i] <= 0) { this._kill(i); i--; continue; }
      const i3 = i * 3;
      const k = Math.max(0, 1 - this.drag[i] * dt);
      V[i3] *= k; V[i3 + 2] *= k;
      V[i3 + 1] = V[i3 + 1] * k - this.grav[i] * dt;
      P[i3] += V[i3] * dt; P[i3 + 1] += V[i3 + 1] * dt; P[i3 + 2] += V[i3 + 2] * dt;
      if (this.bounce && P[i3 + 1] < this.floor[i]) {
        P[i3 + 1] = this.floor[i];
        V[i3 + 1] = Math.abs(V[i3 + 1]) * 0.3;
        V[i3] *= 0.6; V[i3 + 2] *= 0.6;
        this.spin[i] *= 0.5;
      }
      this.rot[i] += this.spin[i] * dt;
      const t = 1 - this.life[i] / this.max[i];
      const sc = this.size[i] * scaleCurve(t);
      _p.set(P[i3], P[i3 + 1], P[i3 + 2]);
      if (this.align) {
        _v.set(V[i3], V[i3 + 1], V[i3 + 2]);
        const sp = _v.length();
        if (sp > 1e-4) _q.setFromUnitVectors(_z, _v.divideScalar(sp)); else _q.identity();
        _s.set(sc, sc, sc * (1 + Math.min(sp, 12) * 0.9));
      } else {
        _q.setFromEuler(_e.set(this.rot[i], this.rot[i] * 0.7, this.rot[i] * 0.3));
        _s.set(sc, sc, sc);
      }
      _m.compose(_p, _q, _s);
      this.mesh.setMatrixAt(i, _m);
      if (this.fade) {
        const f = 1 - t * t;
        this.mesh.setColorAt(i, _c.setRGB(this.col[i3] * f, this.col[i3 + 1] * f, this.col[i3 + 2] * f));
      }
    }
    this.mesh.count = this.n;
    this.mesh.visible = this.n > 0; // an empty InstancedMesh still costs a draw call + state changes
    this.mesh.instanceMatrix.needsUpdate = true;
    if (this.fade && this.n) this.mesh.instanceColor.needsUpdate = true;
  }
}

// Simple ring of instanced flat quads (decals / light pools / blobs / tracers / flashes).
function instanced(scene, geometry, material, cap) {
  const mesh = new THREE.InstancedMesh(geometry, material, cap);
  mesh.frustumCulled = false;
  mesh.castShadow = false;
  mesh.receiveShadow = false;
  mesh.setColorAt(0, _c.set(1, 1, 1));
  for (let i = 0; i < cap; i++) mesh.setMatrixAt(i, ZERO);
  mesh.count = cap;
  mesh.userData.cap = cap;
  scene.add(mesh);
  return mesh;
}

// Per-instance alpha: instanceColor.r scales opacity instead of tinting (blob shadows).
function alphaFromInstance(mat) {
  mat.onBeforeCompile = (s) => {
    s.fragmentShader = s.fragmentShader.replace('#include <color_fragment>', '#if defined( USE_COLOR ) || defined( USE_INSTANCING_COLOR )\n diffuseColor.a *= vColor.r;\n#endif');
  };
  mat.customProgramCacheKey = () => 'fxAlphaInst';
  return mat;
}

function starShape(r = 1, inner = 0.45, n = 5) {
  const s = new THREE.Shape();
  for (let i = 0; i <= n * 2; i++) {
    const a = (i / (n * 2)) * Math.PI * 2 + Math.PI / 2;
    const rr = i % 2 ? r * inner : r;
    if (i === 0) s.moveTo(Math.cos(a) * rr, Math.sin(a) * rr); else s.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
  }
  return s;
}

function decalTexture(kind) {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  const rg = (stops) => { const r = g.createRadialGradient(64, 64, 0, 64, 64, 64); stops.forEach(([o, col]) => r.addColorStop(o, col)); return r; };
  if (kind === 'hole') {
    g.fillStyle = rg([[0, 'rgba(40,24,48,1)'], [0.22, 'rgba(58,42,90,0.95)'], [0.32, 'rgba(255,240,220,0.35)'], [0.42, 'rgba(58,42,90,0.25)'], [1, 'rgba(58,42,90,0)']]);
    g.fillRect(0, 0, 128, 128);
  } else if (kind === 'scorch') {
    g.fillStyle = rg([[0, 'rgba(40,26,40,0.85)'], [0.5, 'rgba(58,42,90,0.45)'], [1, 'rgba(58,42,90,0)']]);
    g.fillRect(0, 0, 128, 128);
  } else {
    // Splat / goo: blobby cartoon puddle drawn white, tinted per instance.
    g.fillStyle = '#ffffff';
    g.beginPath(); g.arc(64, 64, 34, 0, Math.PI * 2); g.fill();
    for (let i = 0; i < 9; i++) {
      const a = (i / 9) * Math.PI * 2 + Math.random() * 0.4, d = 30 + Math.random() * 18, r = 8 + Math.random() * 10;
      g.beginPath(); g.arc(64 + Math.cos(a) * d, 64 + Math.sin(a) * d, r, 0, Math.PI * 2); g.fill();
    }
    g.globalCompositeOperation = 'source-atop';
    g.fillStyle = 'rgba(255,255,255,0.6)';
    g.beginPath(); g.ellipse(50, 48, 14, 8, -0.6, 0, Math.PI * 2); g.fill();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

export class FX {
  constructor(game) {
    this.game = game;
    const scene = game.scene;
    const M = game.mats;
    this._rand = Math.random;

    // Particles.
    const additive = (color) => new THREE.MeshBasicMaterial({ color, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, toneMapped: false, fog: false });
    const sparkGeo = new THREE.OctahedronGeometry(1, 0);
    const starGeo = extrudeShape(starShape(1, 0.45), 0.25, 0.08);
    const staticMat = new THREE.MeshBasicMaterial({ map: staticNoise(), side: THREE.DoubleSide });
    this.pools = {
      spark: new ParticlePool(scene, sparkGeo, additive(new THREE.Color(3, 3, 3)), 400, { align: true, fade: true }),
      puff: new ParticlePool(scene, new THREE.IcosahedronGeometry(1, 2), M.toon('#ffffff', { rough: 0.8, rim: 0.4, keepColor: true, wrap: 0.8, name: 'fx:puff' }), 300, { bounce: false }),
      confetti: new ParticlePool(scene, new THREE.PlaneGeometry(1, 1.7), new THREE.MeshBasicMaterial({ side: THREE.DoubleSide }), 500),
      goo: new ParticlePool(scene, new THREE.IcosahedronGeometry(1, 2), M.toon('#ffffff', { rough: 0.15, rim: 0.5, keepColor: true, name: 'fx:goo' }), 200),
      static: new ParticlePool(scene, new THREE.PlaneGeometry(1, 1), staticMat, 300),
      star: new ParticlePool(scene, starGeo, additive(new THREE.Color(2.4, 2.4, 2.4)), 150, { fade: true }),
    };
    this._curves = {
      spark: (t) => 1 - t,
      puff: (t) => (0.35 + 0.9 * (1 - (1 - t) ** 3)) * (1 - t ** 4),
      confetti: (t) => (t > 0.85 ? (1 - t) / 0.15 : 1),
      goo: (t) => (1 - t ** 3) * (t < 0.1 ? t / 0.1 : 1),
      static: (t) => 1 - t * 0.6,
      star: (t) => (t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85) * 1.1,
    };

    // Tracers: unit box along +z scaled per shot.
    const tracerGeo = new THREE.BoxGeometry(1, 1, 1).translate(0, 0, 0.5);
    this.tracers = { mesh: instanced(scene, tracerGeo, additive(new THREE.Color(2.5, 2.5, 2.5)), 32), life: new Float32Array(32), max: new Float32Array(32), col: [], head: 0 };
    for (let i = 0; i < 32; i++) this.tracers.col.push(new THREE.Color());

    // Muzzle flashes: crossed star cards.
    const flashTex = this._flashTexture();
    const flashGeo = new THREE.PlaneGeometry(1, 1);
    const cross = mergeGeometries([flashGeo, flashGeo.clone().rotateY(Math.PI / 2), flashGeo.clone().rotateX(Math.PI / 2)]);
    const flashMat = new THREE.MeshBasicMaterial({ map: flashTex, color: new THREE.Color(3, 3, 3), blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, side: THREE.DoubleSide, toneMapped: false, fog: false });
    this.flashes = { mesh: instanced(scene, cross, flashMat, 12), life: new Float32Array(12), head: 0, data: [] };
    for (let i = 0; i < 12; i++) this.flashes.data.push({ pos: new THREE.Vector3(), q: new THREE.Quaternion(), size: 0.3 });

    // Decals.
    const decalGeo = new THREE.PlaneGeometry(1, 1);
    this.decals = {};
    for (const kind of ['hole', 'scorch', 'splat', 'goo']) {
      const mat = new THREE.MeshBasicMaterial({ map: decalTexture(kind), transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4 });
      this.decals[kind] = { mesh: instanced(scene, decalGeo, mat, 96), head: 0 };
      this.decals[kind].mesh.visible = false; // until the first decal of this kind
    }

    // Light pools (additive floor glow) and blob shadows.
    const poolGeo = new THREE.PlaneGeometry(2, 2).rotateX(-Math.PI / 2);
    const poolMat = new THREE.MeshBasicMaterial({ map: radial([[0, 'rgba(255,255,255,1)'], [0.35, 'rgba(255,255,255,0.55)'], [1, 'rgba(255,255,255,0)']]), blending: THREE.AdditiveBlending, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2, fog: false });
    this.pools2 = { light: { mesh: instanced(scene, poolGeo, poolMat, 256), handles: [] } };
    this.pools2.light.mesh.count = 0; // count = live handles (swap-remove keeps them packed)
    this.pools2.light.mesh.visible = false;
    const blobMat = alphaFromInstance(new THREE.MeshBasicMaterial({ color: PAL.shadow, alphaMap: radial([[0, 'rgba(255,255,255,1)'], [0.5, 'rgba(255,255,255,0.6)'], [1, 'rgba(255,255,255,0)']]), transparent: true, depthWrite: false, opacity: 0.5, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -3 }));
    this.blobs = { mesh: instanced(scene, poolGeo, blobMat, 64), list: [] };

    // Floating text sprites.
    this.texts = [];
    for (let i = 0; i < 8; i++) {
      const s = new THREE.Sprite(new THREE.SpriteMaterial({ transparent: true, depthWrite: false, depthTest: false, fog: false }));
      s.visible = false;
      s.renderOrder = 10;
      scene.add(s);
      this.texts.push({ sprite: s, life: 0, max: 1, base: new THREE.Vector3(), scale: 1 });
    }
    this._textHead = 0;
  }

  reset() {
    for (const k in this.pools) { this.pools[k].n = 0; this.pools[k].mesh.count = 0; }
    this.tracers.life.fill(0);
    this.flashes.life.fill(0);
    for (const k in this.decals) {
      const m = this.decals[k].mesh;
      for (let i = 0; i < m.count; i++) m.setMatrixAt(i, ZERO);
      m.instanceMatrix.needsUpdate = true;
      m.visible = false;
      this.decals[k].head = 0;
    }
    for (const t of this.texts) { t.life = 0; t.sprite.visible = false; }
  }

  _flashTexture() {
    const c = document.createElement('canvas');
    c.width = c.height = 128;
    const g = c.getContext('2d');
    const r = g.createRadialGradient(64, 64, 0, 64, 64, 64);
    r.addColorStop(0, 'rgba(255,255,255,1)'); r.addColorStop(0.25, 'rgba(255,230,160,0.9)'); r.addColorStop(1, 'rgba(255,160,60,0)');
    g.fillStyle = r;
    g.beginPath();
    for (let i = 0; i <= 16; i++) {
      const a = (i / 16) * Math.PI * 2, rr = i % 2 ? 22 : 62;
      if (i === 0) g.moveTo(64 + Math.cos(a) * rr, 64 + Math.sin(a) * rr); else g.lineTo(64 + Math.cos(a) * rr, 64 + Math.sin(a) * rr);
    }
    g.fill();
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    return t;
  }

  _floorBelow(pos) {
    const col = this.game.level && this.game.level.col;
    const f = col ? col.floorAt(pos.x, pos.z, pos.y + 0.1) : 0;
    return f > -Infinity ? f + 0.03 : -1e3;
  }

  burst(pos, opts = {}) {
    const shape = opts.shape || 'puff';
    const pool = this.pools[shape] || this.pools.puff;
    const d = DEFAULTS[shape] || DEFAULTS.puff;
    const count = opts.count ?? d.count;
    const speed = opts.speed ?? d.speed;
    const size = opts.size ?? d.size;
    const life = opts.life ?? d.life;
    const grav = opts.gravity ?? d.gravity;
    const drag = opts.drag ?? d.drag;
    const colors = opts.colors || (opts.color ? [opts.color] : d.colors);
    const dir = opts.dir || null;
    const cone = opts.cone ?? 0.7;
    const floor = this._floorBelow(pos);
    const r = this._rand;
    for (let i = 0; i < count; i++) {
      _v.set(r() * 2 - 1, r() * 2 - 1, r() * 2 - 1);
      if (_v.lengthSq() < 1e-4) _v.set(0, 1, 0);
      _v.normalize();
      if (dir) _v.multiplyScalar(cone).add(dir).normalize();
      else if (shape === 'confetti' || shape === 'star') _v.y = Math.abs(_v.y) * 1.3 + 0.3;
      const sp = speed * (0.45 + r() * 0.75);
      _c.set(colors[Math.floor(r() * colors.length)]);
      pool.spawn(pos.x, pos.y, pos.z, _v.x * sp, _v.y * sp, _v.z * sp, _c,
        size * (0.7 + r() * 0.6), life * (0.7 + r() * 0.6), grav, drag, floor);
    }
  }

  tracer(from, to, color = '#FFE9A8', width = 0.025) {
    const T = this.tracers;
    const i = T.head;
    T.head = (T.head + 1) % T.life.length;
    const len = from.distanceTo(to);
    if (len < 1e-3) return;
    T.life[i] = 0.08; T.max[i] = 0.08;
    T.mesh.visible = true;
    T.col[i].set(color);
    _v.subVectors(to, from).divideScalar(len);
    _q.setFromUnitVectors(_z, _v);
    _m.compose(from, _q, _s.set(width, width, len));
    T.mesh.setMatrixAt(i, _m);
    T.mesh.setColorAt(i, T.col[i]);
    T.mesh.instanceMatrix.needsUpdate = true;
    T.mesh.instanceColor.needsUpdate = true;
  }

  muzzle(pos, dir, color = '#FFD27A') {
    const F = this.flashes;
    const i = F.head;
    F.head = (F.head + 1) % F.life.length;
    F.life[i] = 0.055;
    F.mesh.visible = true;
    const d = F.data[i];
    d.pos.copy(pos);
    _q.setFromUnitVectors(_z, _v.copy(dir).normalize());
    d.q.copy(_q).multiply(_q2.setFromAxisAngle(_z, Math.random() * Math.PI));
    d.size = 0.32 + Math.random() * 0.12;
    F.mesh.setColorAt(i, _c.set(color));
    F.mesh.instanceColor.needsUpdate = true;
    this.burst(pos, { shape: 'spark', count: 4, dir: _v, cone: 0.35, speed: 6, life: 0.12, size: 0.03, colors: [color, '#ffffff'] });
    this.flashLight(pos, color, 6, 0.06);
  }

  impact(point, normal, kind = 'wall') {
    const n = normal || _up;
    switch (kind) {
      case 'zombie':
        this.burst(point, { shape: 'confetti', count: 10, dir: n, cone: 1.2, speed: 3.5 });
        this.burst(point, { shape: 'puff', count: 3, size: 0.1, colors: ['#DDF3E4', '#BFE3CC'], life: 0.4 });
        break;
      case 'metal':
        this.burst(point, { shape: 'spark', count: 12, dir: n, cone: 0.9, speed: 8 });
        this.decal(point, n, 'hole', 0.12);
        break;
      case 'wood':
        this.burst(point, { shape: 'confetti', count: 6, dir: n, cone: 0.9, speed: 3, size: 0.05, colors: [PAL.teak, PAL.walnut, PAL.cream] });
        this.burst(point, { shape: 'puff', count: 3, size: 0.09, life: 0.45, colors: ['#E8D6B8'] });
        this.decal(point, n, 'hole', 0.14);
        break;
      case 'glass':
        this.burst(point, { shape: 'star', count: 4, dir: n, speed: 2, size: 0.07 });
        break;
      case 'goo':
        this.burst(point, { shape: 'goo', count: 10, dir: n, cone: 1 });
        this.decal(point, n, 'goo', 0.8);
        break;
      default:
        this.burst(point, { shape: 'puff', count: 4, size: 0.1, life: 0.5, dir: n, cone: 1, speed: 1.4, colors: ['#EFE6D6', '#D9CDB8'] });
        this.burst(point, { shape: 'spark', count: 5, dir: n, cone: 0.8, speed: 6, life: 0.2 });
        this.decal(point, n, 'hole', 0.14);
    }
  }

  decal(point, normal, kind = 'hole', size = 0.15, color = '#ffffff') {
    const D = this.decals[kind] || this.decals.hole;
    const i = D.head;
    D.head = (D.head + 1) % D.mesh.userData.cap;
    D.mesh.visible = true;
    const n = normal || _up;
    _q.setFromUnitVectors(_z, n);
    _q.multiply(_q2.setFromAxisAngle(_z, Math.random() * Math.PI * 2));
    _p.copy(point).addScaledVector(n, 0.006);
    _m.compose(_p, _q, _s.set(size, size, size));
    D.mesh.setMatrixAt(i, _m);
    D.mesh.setColorAt(i, _c.set(kind === 'goo' ? PAL.chromaBlue : color));
    D.mesh.instanceMatrix.needsUpdate = true;
    D.mesh.instanceColor.needsUpdate = true;
  }

  // Additive floor glow under fixtures. Returns a handle: { set({pos, radius, color, intensity}), remove() }.
  lightPool(pos, radius = 2, color = '#FFC98A', intensity = 0.3) {
    const P = this.pools2.light;
    if (P.handles.length >= P.mesh.userData.cap) return { set() {}, remove() {} };
    const fx = this;
    const h = {
      index: P.handles.length,
      pos: pos.isVector3 ? pos.clone() : new THREE.Vector3(pos[0], pos[1], pos[2]), radius, color: new THREE.Color(color), intensity,
      set(o = {}) {
        if (o.pos) this.pos.copy(o.pos);
        if (o.radius !== undefined) this.radius = o.radius;
        if (o.color !== undefined) this.color.set(o.color);
        if (o.intensity !== undefined) this.intensity = o.intensity;
        fx._writePool(this);
      },
      remove() {
        const last = P.handles.pop();
        if (last !== this) { P.handles[this.index] = last; last.index = this.index; fx._writePool(last); }
        P.mesh.setMatrixAt(P.handles.length, ZERO);
        P.mesh.count = P.handles.length;
        P.mesh.visible = P.mesh.count > 0;
        P.mesh.instanceMatrix.needsUpdate = true;
      },
    };
    P.handles.push(h);
    P.mesh.count = P.handles.length;
    P.mesh.visible = true;
    this._writePool(h);
    return h;
  }

  _writePool(h) {
    const mesh = this.pools2.light.mesh;
    _m.compose(h.pos, _q.identity(), _s.set(h.radius, 1, h.radius));
    mesh.setMatrixAt(h.index, _m);
    mesh.setColorAt(h.index, _c.copy(h.color).multiplyScalar(h.intensity));
    mesh.instanceMatrix.needsUpdate = true;
    mesh.instanceColor.needsUpdate = true;
  }

  // Soft tinted shadow that follows `object3d` on the floor. Handle: { remove(), visible }.
  blob(object3d, radius = 0.45) {
    const B = this.blobs;
    if (B.list.length >= B.mesh.userData.cap) return { remove() {}, visible: false };
    const h = { object: object3d, radius, visible: true, remove: () => { const i = B.list.indexOf(h); if (i >= 0) B.list.splice(i, 1); } };
    B.list.push(h);
    return h;
  }

  text3d(pos, str, color = '#FFE14D') {
    const t = this.texts[this._textHead];
    this._textHead = (this._textHead + 1) % this.texts.length;
    const tex = textTex(str, { font: 'Titan One', size: 96, color, w: 512, h: 128 });
    t.sprite.material.map = tex;
    t.sprite.material.needsUpdate = true;
    t.base.copy(pos);
    t.life = t.max = 0.9;
    t.sprite.visible = true;
  }

  flashLight(pos, color = '#FFD08A', intensity = 8, duration = 0.08) {
    return this.game.lights.flash(pos, color, intensity, duration);
  }

  shake(amount = 0.3, duration = 0.4) {
    if (this.game.cam) this.game.cam.shake(amount, duration);
  }

  update(dt) {
    for (const k in this.pools) this.pools[k].update(dt, this._curves[k]);
    // Tracers fade out.
    const T = this.tracers;
    let dirty = false;
    for (let i = 0; i < T.life.length; i++) {
      if (T.life[i] <= 0) continue;
      T.life[i] -= dt;
      dirty = true;
      if (T.life[i] <= 0) { T.mesh.setMatrixAt(i, ZERO); continue; }
      const f = T.life[i] / T.max[i];
      T.mesh.setColorAt(i, _c.copy(T.col[i]).multiplyScalar(f));
    }
    if (dirty) { T.mesh.instanceMatrix.needsUpdate = true; T.mesh.instanceColor.needsUpdate = true; }
    T.mesh.visible = dirty;
    // Muzzle flashes.
    const F = this.flashes;
    let fd = false;
    for (let i = 0; i < F.life.length; i++) {
      if (F.life[i] <= 0) continue;
      F.life[i] -= dt;
      fd = true;
      const d = F.data[i];
      if (F.life[i] <= 0) { F.mesh.setMatrixAt(i, ZERO); continue; }
      const s = d.size * (0.6 + 0.4 * (F.life[i] / 0.055));
      _m.compose(d.pos, d.q, _s.set(s, s, s * 1.6));
      F.mesh.setMatrixAt(i, _m);
    }
    if (fd) F.mesh.instanceMatrix.needsUpdate = true;
    F.mesh.visible = fd;
    // Floating texts: pop, rise, fade.
    for (const t of this.texts) {
      if (t.life <= 0) continue;
      t.life -= dt;
      const k = 1 - t.life / t.max;
      if (t.life <= 0) { t.sprite.visible = false; continue; }
      const pop = k < 0.15 ? k / 0.15 * 1.2 : 1.2 - Math.min(0.2, (k - 0.15));
      t.sprite.position.copy(t.base).y += k * 0.8;
      t.sprite.scale.set(1.2 * pop, 0.3 * pop, 1);
      t.sprite.material.opacity = k > 0.7 ? (1 - k) / 0.3 : 1;
    }
  }

  lateUpdate() {
    const B = this.blobs;
    const col = this.game.level && this.game.level.col;
    B.mesh.count = B.list.length;
    B.mesh.visible = B.list.length > 0;
    for (let i = 0; i < B.list.length; i++) {
      const h = B.list[i];
      h.object.getWorldPosition(_p);
      const f = col ? col.floorAt(_p.x, _p.z, _p.y + 0.2) : 0;
      if (!h.visible || !h.object.visible || f === -Infinity) { B.mesh.setMatrixAt(i, ZERO); continue; }
      const height = Math.max(0, _p.y - f);
      const k = Math.max(0, 1 - height / 3);
      const r = h.radius * (1 + height * 0.25);
      _m.compose(_s.set(_p.x, f + 0.015, _p.z), _q.identity(), _v.set(r, 1, r));
      B.mesh.setMatrixAt(i, _m);
      B.mesh.setColorAt(i, _c.setRGB(k, k, k));
    }
    B.mesh.instanceMatrix.needsUpdate = true;
    B.mesh.instanceColor.needsUpdate = true;
  }
}
