// Interactable registry + focus selection (ARCHITECTURE §10/§12, GDD §14/§16).
// register({ id, pos:Vector3|[x,y,z], radius=1.6, height?, enabled:()=>bool, prompt:()=>({cost?, plug?, hold?,
//   denied?}|null), use:()=>void, hold?:seconds, onHold?:(t 0..1)=>void,
//   facing?:rotY | normal?:Vector3|[x,y,z]   front side of a wall-mounted item (rotY uses the anchor convention:
//                                            front = (-sin rotY, 0, -cos rotY)); the player must stand in front
//   facingSlack?=0.25 (m the feet may sit behind the item's plane), los?=true (false: skip the wall test),
//   losIgnore?:[colliderId]                  architecture colliders that belong to the item itself }) -> item;
// unregister(id).
// Focus = the best enabled item that is (a) within its radius of the player (horizontal) and height band,
// (b) in front of the camera (or right under the player), (c) on the item's front side when it declares a facing,
// and (d) in line of sight from the player's head against ARCHITECTURE only (walls, glass, fences, closed doors,
// boarded windows, the tower base — props never block, so an item's own prop is ignored): nothing is usable
// through a wall. E tap uses it; items with `hold` need E held (progress 0..1, reset on release or focus change,
// one completion per press). Drives hud.setPrompt({ ...prompt, key:'E' | 'X' (input.glyph(): X while the Xbox pad is
// the last device), progress, denied }) every frame (null when nothing is focused). `current` is the focused item. Emits interact:use {id}.
// check(itemOrId) -> { ok, dist, dy, inRadius, inHeight, front, los } geometry only (no camera facing, no
//   enabled/prompt), for tests and debugging.

import * as THREE from 'three';

const _f = new THREE.Vector3();
const _eye = new THREE.Vector3();
const _o = new THREE.Vector3();
const _d = new THREE.Vector3();
const _t = new THREE.Vector3();

// Collider tags that stop an interaction (shell.js); everything else (props, machines, platforms, floor) is ignored.
const ARCH_TAGS = ['wall', 'glass', 'fence', 'door', 'window', 'lattice'];
const EYE = 1.5;          // m above the feet: the player's head
const LOS_TOL = 0.12;     // a hit this close to the target still counts as reaching it (points on / in a wall face)
const FRONT_LIFT = 0.1;   // faced items: the sight target is pulled this far out of their plane

export class Interact {
  constructor(game) {
    this.game = game;
    this.items = new Map();
    this.current = null;
    this.prompt = null;
    this.progress = 0;
    this._holdItem = null;
    this._holdDone = false;
    this._shown = { item: null, prompt: {} };
    this._col = null;
    this._losOpts = { camera: true, ignoreTags: 0 };
  }

  register(def) {
    const pos = def.pos && def.pos.isVector3 ? def.pos.clone() : new THREE.Vector3(...(def.pos || [0, 0, 0]));
    const item = { radius: 1.6, height: null, enabled: () => true, prompt: () => ({}), use: () => {}, hold: 0,
      los: true, losIgnore: null, facingSlack: 0.25, ...def, pos };
    let n = null;
    if (def.normal) n = def.normal.isVector3 ? def.normal.clone() : new THREE.Vector3(...def.normal);
    else if (typeof def.facing === 'number') n = new THREE.Vector3(-Math.sin(def.facing), 0, -Math.cos(def.facing));
    if (n) { n.y = 0; if (n.lengthSq() > 1e-8) n.normalize(); else n = null; }
    item.normal = n;
    this.items.set(item.id, item);
    return item;
  }

  unregister(id) {
    this.items.delete(id);
    if (this.current && this.current.id === id) this.current = null;
  }

  reset() {
    this.current = null;
    this.prompt = null;
    this.progress = 0;
    this._holdItem = null;
  }

  // Player on the item's front side (items without a facing: always).
  _front(it, p) {
    const n = it.normal;
    if (!n) return true;
    return (p.pos.x - it.pos.x) * n.x + (p.pos.z - it.pos.z) * n.z > -it.facingSlack;
  }

  // Line of sight from the player's head to the item against architecture colliders.
  _los(it, p) {
    if (it.los === false) return true;
    const col = this.game.level && this.game.level.col;
    if (!col || !col.raycast) return true;
    if (this._col !== col) {
      // ignore every tag bit except the architecture ones (tags registered later get non-architecture bits)
      this._col = col;
      this._losOpts.ignoreTags = ~col.maskOf(ARCH_TAGS) & 0x7fffffff;
    }
    _eye.set(p.pos.x, p.pos.y + Math.min(EYE, (p.height || 1.75) * 0.86), p.pos.z);
    _t.copy(it.pos);
    if (it.normal) _t.addScaledVector(it.normal, FRONT_LIFT);
    _o.copy(_eye);
    _d.subVectors(_t, _o);
    let left = _d.length();
    if (left < 0.25) return true;
    _d.divideScalar(left);
    for (let i = 0; i < 4; i++) {
      const hit = col.raycast(_o, _d, left, this._losOpts);
      if (!hit || hit.dist >= left - LOS_TOL) return true;
      if (!it.losIgnore || !it.losIgnore.includes(hit.id)) return false;
      // the item's own architecture (e.g. its door blocker): continue from just inside that box
      _o.addScaledVector(_d, hit.dist + 0.01);
      left -= hit.dist + 0.01;
    }
    return false;
  }

  check(itemOrId) {
    const it = typeof itemOrId === 'string' ? this.items.get(itemOrId) : itemOrId;
    const p = this.game.player;
    if (!it || !p) return null;
    const dist = Math.hypot(it.pos.x - p.pos.x, it.pos.z - p.pos.z);
    const dy = it.pos.y - p.pos.y;
    const inRadius = dist <= it.radius;
    const inHeight = it.height !== null ? Math.abs(dy) <= it.height : dy >= -1.2 && dy <= 2.8;
    const front = this._front(it, p);
    const los = this._los(it, p);
    return { ok: inRadius && inHeight && front && los, dist, dy, inRadius, inHeight, front, los };
  }

  update(dt) {
    const g = this.game;
    const p = g.player;
    let best = null, bestPrompt = null, bestScore = Infinity;
    if (p && p.alive && !p.downed) {
      g.camera.getWorldDirection(_f);
      _f.y = 0;
      _f.normalize();
      for (const it of this.items.values()) {
        const dx = it.pos.x - p.pos.x, dz = it.pos.z - p.pos.z;
        const d = Math.hypot(dx, dz);
        if (d > it.radius) continue;
        const dy = it.pos.y - p.pos.y;
        if (it.height !== null ? Math.abs(dy) > it.height : dy < -1.2 || dy > 2.8) continue;
        const facing = d < 0.8 ? 1 : (dx * _f.x + dz * _f.z) / d;
        if (facing < 0.3) continue;
        if (!this._front(it, p)) continue;
        const score = d * (1.6 - facing);
        if (score >= bestScore) continue;
        if (!it.enabled()) continue;
        const pr = it.prompt ? it.prompt() : {};
        if (pr === null) continue;
        if (!this._los(it, p)) continue;
        bestScore = score; best = it; bestPrompt = pr;
      }
    }
    if (best !== this._holdItem) { this.progress = 0; this._holdItem = null; }
    this.current = best;
    this.prompt = bestPrompt;

    const input = g.input;
    if (!input.down('interact')) this._holdDone = false;
    if (best && dt > 0) {
      if (best.hold > 0) {
        if (input.down('interact') && !this._holdDone) {
          this._holdItem = best;
          this.progress = Math.min(1, this.progress + dt / best.hold);
          if (best.onHold) best.onHold(this.progress);
          if (this.progress >= 1) { this._use(best); this.progress = 0; this._holdDone = true; }
        } else {
          this.progress = 0;
        }
      } else if (input.pressed('interact')) {
        this._use(best);
      }
    }
    this._updateHud(best, bestPrompt);
  }

  _use(it) {
    it.use();
    this.game.events.emit('interact:use', { id: it.id });
  }

  _updateHud(item, prompt) {
    const hud = this.game.hud;
    if (!hud || !hud.setPrompt) return;
    if (!item) {
      if (this._shown.item) hud.setPrompt(null);
      this._shown.item = null;
      return;
    }
    const pts = this.game.economy ? this.game.economy.points : Infinity;
    const out = {
      ...prompt,
      key: this.game.input && this.game.input.glyph ? this.game.input.glyph() : 'E', // 'X' while playing with the pad
      hold: prompt.hold ?? (item.hold || undefined),
      progress: this.progress,
      denied: prompt.denied ?? (prompt.cost !== undefined && prompt.cost > pts),
    };
    this._shown.item = item;
    hud.setPrompt(out);
  }
}
