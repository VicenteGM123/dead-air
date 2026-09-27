// Lighting (ARCHITECTURE §5, GDD §3.3/§3.9):
//  - HemisphereLight lerping toward the current area's ambient (level.areas[id].ambient; before power its
//    ambientPre, or ambient x0.6 when an area has none),
//    plus the per-area fog (scene.fog always exists; "no fog" = pushed far away),
//  - one warm key DirectionalLight, the only shadow caster, its shadow camera following the player
//    (orthographic +-18 m, 2048 map, texel-snapped so shadows don't shimmer) + a cool shadowless fill,
//  - exactly 8 pooled PointLights, reassigned every 0.2 s to the anchors nearest the camera (same/adjacent area
//    first) with smooth fades. Lights are never added/removed at runtime (that would recompile programs).
// API: addAnchor({pos, color, intensity, distance, area, flicker?, id?}) -> anchor, setAnchor(id, {color,
//   intensity, enabled, flicker}), removeAnchor(id), flicker(id, amount, seconds), flash(pos, color, intensity,
//   seconds) (transient, takes a slot immediately; used by fx.flashLight).
// Point intensities are three.js candela with decay 1.5 (typical fixture 2..6, distance 6..14 m).

import * as THREE from 'three';
import { noise1, hash1 } from './rng.js';

const POOL = 8;
const REASSIGN = 0.2;
const FADE_OUT = 0.18;
const FADE_IN = 0.3;
const HEMI_SCALE = 1.35;    // area table intensities are artistic 0..1; scaled to renderer units here
const KEY = { powered: 1.7, dark: 1.3 }; // warm key; lit diffuse stays under the bloom threshold
const PRE_POWER = 0.6;      // GDD §3.3
const DEFAULT_AMBIENT = { sky: '#FFE2B8', ground: '#6B4226', intensity: 0.9 };

const _v = new THREE.Vector3();
const _right = new THREE.Vector3();
const _up = new THREE.Vector3();
const _c = new THREE.Color();

export class Lights {
  constructor(game) {
    this.game = game;
    const scene = game.scene;

    this.hemi = new THREE.HemisphereLight(DEFAULT_AMBIENT.sky, DEFAULT_AMBIENT.ground, DEFAULT_AMBIENT.intensity * HEMI_SCALE);
    this.hemi.layers.enableAll();
    scene.add(this.hemi);

    this.key = new THREE.DirectionalLight('#FFE4C2', KEY.powered);
    this.key.castShadow = true;
    this.key.layers.enableAll();
    const s = this.key.shadow;
    s.mapSize.set(2048, 2048);
    s.camera.left = -18; s.camera.right = 18; s.camera.top = 18; s.camera.bottom = -18;
    s.camera.near = 1; s.camera.far = 70;
    s.bias = -0.0005;
    s.normalBias = 0.035;
    s.radius = 3.5;
    this.keyDir = new THREE.Vector3(-0.42, 1, 0.32).normalize(); // toward the light: mostly overhead
    scene.add(this.key, this.key.target);

    this.fill = new THREE.DirectionalLight('#9FB6FF', 0.35);
    this.fill.position.set(0.6, 0.35, -0.7);
    this.fill.layers.enableAll();
    scene.add(this.fill);

    this.pool = [];
    for (let i = 0; i < POOL; i++) {
      const light = new THREE.PointLight('#ffffff', 0, 10, 1.5);
      light.layers.enableAll();
      scene.add(light);
      this.pool.push({ light, anchor: null, next: undefined, level: 0 });
    }

    this.anchors = new Map();
    this._pendingFlash = [];
    this._uid = 0;
    this._t = 0;
    this._reassignT = 0;
    this._ambient = { sky: new THREE.Color(DEFAULT_AMBIENT.sky), ground: new THREE.Color(DEFAULT_AMBIENT.ground), intensity: DEFAULT_AMBIENT.intensity };
    this._fog = { color: new THREE.Color('#150F1C'), near: 1000, far: 2000 };
    this._candidates = [];
  }

  reset() {
    for (const [id, a] of this.anchors) if (a.flash) this.anchors.delete(id);
    this._pendingFlash.length = 0;
    for (const slot of this.pool) {
      if (slot.anchor && slot.anchor.flash) { slot.anchor = null; slot.level = 0; }
    }
    this._reassignT = 0;
  }

  addAnchor({ pos, color = '#FFC98A', intensity = 6, distance = 10, area = null, flicker = 0, id = null }) {
    const anchor = {
      id: id || `light_${++this._uid}`,
      pos: pos && pos.isVector3 ? pos.clone() : new THREE.Vector3(pos[0], pos[1], pos[2]),
      color: new THREE.Color(color),
      intensity, distance, area, flicker,
      enabled: true,
      cur: intensity,       // eased intensity (setAnchor transitions)
      boost: 0, boostT: 0,  // temporary flicker()
      seed: hash1(this._uid * 7.3) * 100,
      flash: false,
    };
    this.anchors.set(anchor.id, anchor);
    return anchor;
  }

  setAnchor(id, { color, intensity, enabled, flicker } = {}) {
    const a = this.anchors.get(id);
    if (!a) return;
    if (color !== undefined) a.color.set(color);
    if (intensity !== undefined) a.intensity = intensity;
    if (enabled !== undefined) a.enabled = enabled;
    if (flicker !== undefined) a.flicker = flicker;
  }

  removeAnchor(id) {
    const a = this.anchors.get(id);
    if (!a) return;
    this.anchors.delete(id);
    for (const slot of this.pool) {
      if (slot.next === a) slot.next = null;
      if (slot.anchor === a && slot.next === undefined) slot.next = null;
    }
  }

  flicker(id, amount = 0.8, seconds = 0.6) {
    const a = this.anchors.get(id);
    if (!a) return;
    a.boost = amount;
    a.boostT = seconds;
  }

  // Transient light (muzzle flashes, explosions): grabs a pool slot right away, fades over `seconds`.
  flash(pos, color = '#FFD08A', intensity = 8, seconds = 0.08, distance = 8) {
    const a = this.addAnchor({ pos, color, intensity, distance });
    a.flash = true;
    a.ttl = seconds;
    a.life = seconds;
    this._pendingFlash.push(a);
    return a;
  }

  update(dt) {
    this._t += dt;
    this._updateAmbient(dt);
    this._updateKey();
    this._updateFlashes(dt);
    this._reassignT -= dt;
    if (this._reassignT <= 0) {
      this._reassignT = REASSIGN;
      this._reassign();
    }
    this._updateSlots(dt);
  }

  _currentArea() {
    const g = this.game;
    const level = g.level;
    if (!level || !level.areas) return null;
    const id = (g.player && g.player.area) || (level.areaAt && level.areaAt(g.camera.position.x, g.camera.position.z));
    return id ? level.areas[id] || null : null;
  }

  _updateAmbient(dt) {
    const area = this._currentArea();
    const powered = this.game.machines ? !!this.game.machines.powerOn : true;
    // Before Sign-On: the area's emergency-power ambient (layout ambientPre), else the post ambient x0.6.
    const pre = !powered && area && area.ambientPre;
    const amb = pre || (area && area.ambient) || DEFAULT_AMBIENT;
    const scale = powered || pre ? 1 : PRE_POWER;
    const k = 1 - Math.exp(-dt * 2.5);
    const A = this._ambient;
    A.sky.lerp(_c.set(amb.sky), k);
    A.ground.lerp(_c.set(amb.ground), k);
    A.intensity += ((amb.intensity ?? 0.8) * scale - A.intensity) * k;
    this.hemi.color.copy(A.sky);
    this.hemi.groundColor.copy(A.ground);
    this.hemi.intensity = A.intensity * HEMI_SCALE;
    this.key.intensity = powered ? KEY.powered : KEY.dark;
    if (this.game.mats) this.game.mats.uniforms.uRimAmbient.value = THREE.MathUtils.clamp(0.45 + A.intensity * 0.65, 0.5, 1.2);

    const fog = area && area.fog;
    const F = this._fog;
    F.color.lerp(_c.set(fog ? fog.color : '#150F1C'), k);
    F.near += ((fog ? fog.near : 1000) - F.near) * k;
    F.far += ((fog ? fog.far : 2000) - F.far) * k;
    const sf = this.game.scene.fog;
    sf.color.copy(F.color);
    sf.near = F.near;
    sf.far = F.far;
  }

  _updateKey() {
    const g = this.game;
    const focus = g.player && g.player.pos ? g.player.pos : g.camera.position;
    const d = this.keyDir;
    const texel = (this.key.shadow.camera.right - this.key.shadow.camera.left) / this.key.shadow.mapSize.x;
    // Snap the focus to shadow-map texels in light space (stable shadows while moving).
    _right.set(0, 0, 1).cross(d).normalize();
    _up.copy(d).cross(_right).normalize();
    const r = Math.round(focus.dot(_right) / texel) * texel;
    const u = Math.round(focus.dot(_up) / texel) * texel;
    const f = focus.dot(d);
    _v.copy(_right).multiplyScalar(r).addScaledVector(_up, u).addScaledVector(d, f);
    this.key.target.position.copy(_v);
    this.key.position.copy(_v).addScaledVector(d, 30);
    this.key.target.updateMatrixWorld();
  }

  _updateFlashes(dt) {
    for (const a of this._pendingFlash) {
      let best = this.pool[0], bestScore = Infinity;
      for (const slot of this.pool) {
        const score = !slot.anchor ? -1 : slot.anchor.flash ? 1e9 - slot.anchor.ttl : slot.level * slot.anchor.cur;
        if (score < bestScore) { bestScore = score; best = slot; }
      }
      best.anchor = a; best.next = undefined; best.level = 1;
      this._place(best);
    }
    this._pendingFlash.length = 0;
    for (const [id, a] of this.anchors) {
      if (!a.flash) continue;
      a.ttl -= dt;
      if (a.ttl <= 0) {
        this.anchors.delete(id);
        for (const slot of this.pool) if (slot.anchor === a) { slot.anchor = null; slot.level = 0; }
      }
    }
  }

  _reassign() {
    const cam = this.game.camera.position;
    const area = this._currentArea();
    const areaId = area ? area.id : null;
    const adj = area && area.adjacent ? area.adjacent : [];
    const list = this._candidates;
    list.length = 0;
    for (const a of this.anchors.values()) {
      if (a.flash || (!a.enabled && a.cur < 0.01) || a.intensity <= 0) continue;
      const d2 = a.pos.distanceToSquared(cam);
      const reach = a.distance + 18;
      if (d2 > reach * reach) continue;
      const w = !areaId || !a.area || a.area === areaId ? 1 : adj.includes(a.area) ? 2.5 : 9;
      a._score = d2 * w;
      list.push(a);
    }
    list.sort((x, y) => x._score - y._score);
    const free = POOL - this.pool.reduce((n, s) => n + (s.anchor && s.anchor.flash ? 1 : 0), 0);
    const desired = list.slice(0, Math.max(0, free));
    const taken = new Set();
    for (const slot of this.pool) {
      if (slot.anchor && (slot.anchor.flash || desired.includes(slot.anchor))) {
        taken.add(slot.anchor);
        if (slot.next !== undefined && !slot.anchor.flash) slot.next = undefined;
      }
    }
    const pending = desired.filter((a) => !taken.has(a));
    for (const slot of this.pool) {
      if (!pending.length) break;
      if (slot.anchor && taken.has(slot.anchor)) continue;
      const a = pending.shift();
      if (!slot.anchor || slot.level <= 0.01) { slot.anchor = a; slot.next = undefined; slot.level = 0; this._place(slot); }
      else slot.next = a;
    }
    for (const slot of this.pool) {
      if (slot.anchor && !taken.has(slot.anchor) && slot.next === undefined) slot.next = null;
    }
  }

  _place(slot) {
    const a = slot.anchor;
    if (!a) return;
    slot.light.position.copy(a.pos);
    slot.light.color.copy(a.color);
    slot.light.distance = a.distance;
  }

  _updateSlots(dt) {
    const t = this._t;
    for (const a of this.anchors.values()) {
      const target = a.enabled ? a.intensity : 0;
      a.cur += (target - a.cur) * (1 - Math.exp(-dt * 10));
      if (a.boostT > 0) a.boostT -= dt;
    }
    for (const slot of this.pool) {
      if (slot.next !== undefined) {
        slot.level -= dt / FADE_OUT;
        if (slot.level <= 0) {
          slot.level = 0;
          slot.anchor = slot.next;
          slot.next = undefined;
          this._place(slot);
        }
      } else if (slot.anchor) {
        slot.level = Math.min(1, slot.level + dt / FADE_IN);
      }
      const a = slot.anchor;
      if (!a) { slot.light.intensity = 0; continue; }
      let k = a.flash ? Math.max(0, a.ttl / a.life) ** 2 * a.intensity : a.cur;
      const f = a.flicker + (a.boostT > 0 ? a.boost : 0);
      if (f > 0) {
        const buzz = 0.5 + 0.5 * noise1(t * 14 + a.seed);
        const drop = hash1(Math.floor(t * 18) + a.seed) > 0.86 ? 0.7 : 0;
        k *= 1 - Math.min(1, f) * Math.min(1, buzz * 0.5 + drop);
      }
      slot.light.color.copy(a.color);
      slot.light.intensity = k * slot.level;
    }
  }
}
