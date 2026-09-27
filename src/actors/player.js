// Player controller (ARCHITECTURE §9/§12, GDD §6.2/§16): movement, health, stamina, hero model & animation.
//
// Fields: pos (feet), vel, yaw, pitch, radius, height, health, maxHealth, alive, downed, heroId, hero (buildHero
//   result), rig, animator, model, sprinting, ads, grounded, area, stamina, god, invulnerable (external: set by
//   commercials / Instant Replay), controlLocked (no look/move input: debug cameras, cutscenes), mods (perks & power-ups write these; read every frame), anim (animator state:
//   weapons write recoil/reload/melee 0..1), history (4 s ring buffer, 0.1 s samples: get(i), at(secondsAgo, out)).
// Methods: setHero(id), setWeaponModel(group|null) (attached to hero slots.handR), hurt(dmg, fromPos) -> bool,
//   heal(n), knockback(vec), down(), revive(selfRevive), aimRay(outOrigin, outDir), muzzle(out), forward(out),
//   teleport(x, z, yaw?).
// setHero turns a placeholder hero's static meshes into one rigid-skinned mesh per material (geo.skinRig: the
// draw-call budget); parts that must stay addressable (springs, swappable pieces) carry userData.dynamic / noMerge.
// Baked (src/art) heroes are never merged.
// Lethal damage asks game.perks.onLethal() first (true = handled, e.g. Instant Replay), else game.gameOver().
// Also owns render.post.damage (GDD §14 "signal loss" = 1 - HP/max, eased).
// Movement uses world dt (frozen at time.scale 0); look, the hero animation and the model use real dt.
// Move input comes from input.move() (keyboard digital axes or the gamepad's analog left stick: a light push walks
// slower, sprint is always full speed); look adds input.lookDelta().snapYaw/snapPitch (pad aim assist) unscaled.
// Sounds: player:step {foot, sprint, surface} / jump / land / hurt are voiced by audio.js's event hookups.

import * as THREE from 'three';
import { T, PAL } from '../core/config.js';
import { Spring } from '../core/rig.js';
import { buildHero } from './heroes.js';
import { skinRig } from '../core/geo.js';

const P = T.player;
const JUMP_V = Math.sqrt(2 * P.gravity * P.jump);
const ACCEL = 42;
const DECEL = 34;
const AIR = 0.3;
const STEP_UP = 0.45;

const _fwd = new THREE.Vector3();
const _right = new THREE.Vector3();
const _wish = new THREE.Vector3();
const _delta = new THREE.Vector3();
const _hv = new THREE.Vector3();
const _look = { yaw: 0, pitch: 0, snapYaw: 0, snapPitch: 0 };
const _move = { x: 0, y: 0 };
const SPRINT_FWD = 0.35; // forward axis needed to sprint (keyboard W = 1; the stick may sprint ~70 deg off-axis)

const wrapAngle = (a) => Math.atan2(Math.sin(a), Math.cos(a));

// ARCHITECTURE §5: only meshes bigger than ~0.3 m cast shadows (eyes, lids, buttons would each add a shadow-pass
// draw call for nothing). Skinned bodies always cast. Nothing on the player receives shadows (noisy on toys).
function setShadowCasting(root, minRadius) {
  root.updateMatrixWorld(true);
  root.traverse((o) => {
    if (!o.isMesh) return;
    o.receiveShadow = false;
    if (o.isSkinnedMesh) { o.castShadow = true; return; }
    const g = o.geometry;
    if (!g.boundingSphere) g.computeBoundingSphere();
    const e = o.matrixWorld.elements;
    const scale = Math.sqrt(Math.max(e[0] * e[0] + e[1] * e[1] + e[2] * e[2], e[4] * e[4] + e[5] * e[5] + e[6] * e[6], e[8] * e[8] + e[9] * e[9] + e[10] * e[10]));
    o.castShadow = g.boundingSphere.radius * scale >= minRadius;
  });
}

// 4 s position ring buffer for Instant Replay (GDD §11: 40 samples every 0.1 s).
class History {
  constructor(n = 40, step = 0.1) {
    this.n = n;
    this.step = step;
    this.samples = Array.from({ length: n }, () => ({ x: 0, y: 0, z: 0, yaw: 0, area: null }));
    this.head = -1;
    this.count = 0;
    this._acc = 0;
  }
  clear() { this.head = -1; this.count = 0; this._acc = 0; }
  push(pos, yaw, area) {
    this.head = (this.head + 1) % this.n;
    const s = this.samples[this.head];
    s.x = pos.x; s.y = pos.y; s.z = pos.z; s.yaw = yaw; s.area = area;
    this.count = Math.min(this.n, this.count + 1);
  }
  tick(dt, pos, yaw, area) {
    this._acc += dt;
    while (this._acc >= this.step) { this._acc -= this.step; this.push(pos, yaw, area); }
  }
  // i-th newest sample (0 = newest) or null.
  get(i) {
    if (i < 0 || i >= this.count) return null;
    return this.samples[(this.head - i + this.n) % this.n];
  }
  // Sample about `seconds` ago (clamped to the oldest); copies the position into `out`. Returns the sample.
  at(seconds, out) {
    if (!this.count) return null;
    const s = this.get(Math.min(this.count - 1, Math.round(seconds / this.step)));
    if (out) out.set(s.x, s.y, s.z);
    return s;
  }
}

export class Player {
  constructor(game) {
    this.game = game;
    this.pos = new THREE.Vector3();
    this.vel = new THREE.Vector3();
    this.knock = new THREE.Vector3();
    this.yaw = 0;
    this.pitch = 0;
    this.radius = 0.38;
    this.height = 1.75;
    this.health = P.hp;
    this.maxHealth = P.hp;
    this.alive = true;
    this.downed = false;
    this.heroId = null;
    this.hero = null;
    this.rig = null;
    this.animator = null;
    this.model = new THREE.Group();
    this.model.name = 'player';
    this.sprinting = false;
    this.ads = false;
    this.grounded = true;
    this.area = null;
    this.stamina = P.stamina;
    this.god = false;
    this.invulnerable = false;
    this.controlLocked = false;
    this.mods = this._defaultMods();
    this.anim = { speed: 0, sprint: false, grounded: true, aimPitch: 0, aimYaw: 0, aiming: true, recoil: 0, reload: 0,
      melee: 0, hurt: 0, climb: 0, attack: 0, dance: 0, down: false, dead: 0, back: false, turn: 0, legYaw: 0 };
    this.history = new History(40, 0.1);
    this.weaponModel = null;
    this._muzzle = null;
    this._iframes = 0;
    this._sinceHurt = 99;
    this._sinceSprint = 99;
    this._exhausted = false;
    this._modelYaw = new Spring(170, 17);
    this._faceYaw = 0;
    this._stepIndex = 0;
    this._damage = 0;
    this._hidden = false;
  }

  _defaultMods() {
    return { moveSpeed: 1, sprintSpeed: 1, reloadSpeed: 1, fireRate: 1, damage: 1, maxHealth: P.hp,
      regenDelay: P.regenDelay, regenRate: P.regenRate, adsSpeed: 1, meleeDamage: 1,
      knockback: 1, unlimitedSprint: false, sprintToFire: P.sprintToFire, swapSpeed: 1 };
  }

  init() {
    this.game.scene.add(this.model);
    this.blob = this.game.fx.blob(this.model, 0.42);
  }

  reset() {
    const g = this.game;
    this.mods = this._defaultMods();
    this.maxHealth = this.health = this.mods.maxHealth;
    this.alive = true;
    this.downed = false;
    this.god = !!g.params.god;
    this.invulnerable = false;
    this.stamina = P.stamina;
    this._exhausted = false;
    this._iframes = 0;
    this._sinceHurt = 99;
    this.vel.set(0, 0, 0);
    this.knock.set(0, 0, 0);
    this.sprinting = this.ads = false;
    Object.assign(this.anim, { recoil: 0, reload: 0, melee: 0, hurt: 0, climb: 0, attack: 0, dance: 0, down: false, dead: 0 });
    this._spawn();
    this.history.clear();
    this._damage = 0;
  }

  _spawn() {
    const level = this.game.level;
    const want = this.game.params.area;
    let x = 0, z = 4, yaw = 0;
    const spawn = level.anchors.player_spawn;
    if (want && level.areas[want]) {
      const r = level.areas[want].rect;
      [x, z] = this._walkableNear((r[0] + r[2]) / 2, (r[1] + r[3]) / 2);
    } else if (spawn) {
      x = spawn.pos.x; z = spawn.pos.z; yaw = spawn.rotY;
    }
    this.teleport(x, z, yaw);
    this.pitch = -0.08;
  }

  // Nearest nav-walkable point to (x, z) on growing rings (0.5 m steps, up to 8 m); (x, z) if none.
  _walkableNear(x, z) {
    const nav = this.game.nav;
    for (let r = 0; r <= 8; r += 0.5) {
      const n = r === 0 ? 1 : Math.ceil((2 * Math.PI * r) / 0.5);
      for (let i = 0; i < n; i++) {
        const a = (i / n) * Math.PI * 2, px = x + Math.cos(a) * r, pz = z + Math.sin(a) * r;
        if (nav.walkable(px, pz)) return [px, pz];
      }
    }
    return [x, z];
  }

  teleport(x, z, yaw) {
    const col = this.game.level.col;
    const f = col.floorAt(x, z, 50);
    this.pos.set(x, f > -Infinity ? f : 0, z);
    if (yaw !== undefined) { this.yaw = yaw; this._faceYaw = yaw; this._modelYaw.reset(yaw); }
    this.vel.set(0, 0, 0);
    this.area = this.game.level.areaAt(x, z) || this.area;
    this.model.position.copy(this.pos);
    this.model.rotation.y = this._modelYaw.x;
  }

  setHero(heroId) {
    const g = this.game;
    if (this.hero) this.model.remove(this.hero.group);
    this.heroId = heroId;
    this.hero = buildHero(heroId, g);
    this.rig = this.hero.rig;
    this.animator = this.hero.animator;
    setShadowCasting(this.hero.group, 0.12);
    g.mats.applyHeroFade(this.hero.group);
    // Placeholder heroes: one rigid-skinned mesh per material (was ~45 draws + 45 shadow draws per frame).
    // Baked (src/art) heroes are already one SkinnedMesh + face attachments whose lids/pupils animate.
    if (!this.hero.baked) {
      const recolor = g.mats.toon('#ffffff', { vertexColors: true, rough: 0.55, wrap: 0.6, rim: 0.35, rimColor: PAL.rimHero, keepColor: true, heroFade: true });
      skinRig(this.rig, { recolor });
    }
    this.model.add(this.hero.group);
    if (this.weaponModel) this.setWeaponModel(this.weaponModel);
  }

  setWeaponModel(group) {
    if (this.weaponModel && this.weaponModel.parent) this.weaponModel.parent.remove(this.weaponModel);
    this.weaponModel = group || null;
    this._muzzle = null;
    if (!group || !this.hero) return;
    this.game.mats.applyHeroFade(group);
    setShadowCasting(group, 0.08);
    this.hero.slots.handR.add(group);
    this._muzzle = group.getObjectByName('muzzle') || null;
  }

  forward(out = new THREE.Vector3()) {
    return out.set(-Math.sin(this.yaw), 0, -Math.cos(this.yaw));
  }

  aimRay(outOrigin, outDir) {
    const cam = this.game.camera;
    cam.updateMatrixWorld();
    if (outOrigin) cam.getWorldPosition(outOrigin);
    if (outDir) cam.getWorldDirection(outDir);
  }

  muzzle(out = new THREE.Vector3()) {
    const m = this._muzzle || (this.hero && this.hero.slots.handR);
    if (!m) return out.copy(this.pos).setY(this.pos.y + 1.3);
    m.updateWorldMatrix(true, false);
    return m.getWorldPosition(out);
  }

  hurt(dmg, fromPos = null) {
    const g = this.game;
    if (!this.alive || this.downed || this.god || this.invulnerable || this._iframes > 0) return false;
    if (g.state !== 'playing') return false;
    this.health -= dmg;
    this._iframes = P.iframes;
    this._sinceHurt = 0;
    this.anim.hurt = 1;
    g.events.emit('player:hurt', { dmg, from: fromPos });
    if (g.cam) g.cam.shake(Math.min(0.5, 0.15 + dmg / 200), 0.35);
    if (this.health <= 0) {
      this.health = 0;
      const handled = g.perks && g.perks.onLethal ? g.perks.onLethal() : false;
      if (!handled) {
        this.alive = false;
        g.gameOver();
      }
    }
    return true;
  }

  heal(n) {
    if (!this.alive) return;
    this.health = Math.min(this.maxHealth, this.health + n);
    this.game.events.emit('player:heal', {});
  }

  knockback(vec) {
    this.knock.addScaledVector(vec, this.mods.knockback);
  }

  down() {
    if (this.downed) return;
    this.downed = true;
    this.anim.down = true;
    this.game.setState('down');
    this.game.events.emit('player:down', {});
  }

  revive(selfRevive = false) {
    this.downed = false;
    this.alive = true;
    this.anim.down = false;
    this.anim.dead = 0;
    this.health = this.maxHealth;
    this._sinceHurt = 99;
    if (this.game.state === 'down') this.game.setState('playing');
    this.game.events.emit('player:revive', { selfRevive });
  }

  update(dt) {
    const g = this.game;
    const rdt = g.time.realDt;
    if (this.maxHealth !== this.mods.maxHealth) {
      this.maxHealth = this.mods.maxHealth;
      this.health = Math.min(this.health, this.maxHealth);
    }
    const control = this.alive && !this.downed && !this.controlLocked;
    if (control && !g.render.cameraOverride && g.state === 'playing') this._look();
    if (dt > 0 && control) this._move(dt);
    if (dt > 0) this._vitals(dt);
    this._animate(rdt);
  }

  _look() {
    const d = this.game.input.lookDelta(_look);
    const k = this.ads ? 0.65 : 1;
    // snapYaw / snapPitch: the gamepad aim-assist snap (already an exact angle, not scaled by ADS)
    this.yaw = wrapAngle(this.yaw + d.yaw * k + (d.snapYaw || 0));
    this.pitch = THREE.MathUtils.clamp(this.pitch + d.pitch * k + (d.snapPitch || 0), -1.25, 1.1);
  }

  _move(dt) {
    const g = this.game, input = g.input;
    // keyboard: digital -1/0/1 axes; gamepad: the analog left stick (magnitude <= 1 scales the speed)
    const mv = input.move ? input.move(_move) : null;
    const fwdIn = mv ? mv.y : (input.down('forward') ? 1 : 0) - (input.down('back') ? 1 : 0);
    const strIn = mv ? mv.x : (input.down('right') ? 1 : 0) - (input.down('left') ? 1 : 0);
    const mag = Math.hypot(fwdIn, strIn);
    this.ads = input.down('aim');

    // Sprint + stamina (GDD §6.2: 4 s, refill 1 s after stopping, full in 3 s).
    const unlimited = this.mods.unlimitedSprint;
    const canSprint = unlimited || (!this._exhausted && this.stamina > 0);
    this.sprinting = input.down('sprint') && fwdIn > SPRINT_FWD && !this.ads && canSprint;
    if (this.sprinting) {
      this._sinceSprint = 0;
      if (!unlimited) {
        this.stamina -= dt;
        if (this.stamina <= 0) { this.stamina = 0; this._exhausted = true; }
      }
    } else {
      this._sinceSprint += dt;
      if (this._sinceSprint >= P.staminaDelay) this.stamina = Math.min(P.stamina, this.stamina + dt * (P.stamina / P.staminaRefill));
      if (this._exhausted && this.stamina >= P.stamina * 0.25) this._exhausted = false;
    }

    // Target speed.
    const def = g.weapons && g.weapons.currentDef ? g.weapons.currentDef() : null;
    const weaponMul = def && def.move ? def.move : 1;
    let speed;
    if (this.ads) speed = P.ads * this.mods.moveSpeed;
    else if (this.sprinting) speed = P.sprint * this.mods.sprintSpeed;
    else {
      // backpedal share: 1 whenever a keyboard move includes S (as before); the stick blends by its angle
      const back = mag > 1e-4 ? THREE.MathUtils.clamp((-fwdIn / Math.min(1, mag)) * 1.5, 0, 1) : 0;
      speed = THREE.MathUtils.lerp(P.run, P.backpedal, back) * this.mods.moveSpeed;
    }
    speed *= weaponMul;

    this.forward(_fwd);
    _right.set(-_fwd.z, 0, _fwd.x);
    _wish.set(0, 0, 0).addScaledVector(_fwd, fwdIn).addScaledVector(_right, strIn);
    // analog sticks keep their magnitude (walk slower with a light push); sprint is always full speed
    if (_wish.lengthSq() > 1 || (this.sprinting && _wish.lengthSq() > 1e-6)) _wish.normalize();
    _wish.multiplyScalar(speed);

    // Acceleration-based horizontal motion (air control 0.3).
    const air = this.grounded ? 1 : AIR;
    const rate = (_wish.lengthSq() > 0 ? ACCEL : DECEL) * air;
    _hv.set(_wish.x - this.vel.x, 0, _wish.z - this.vel.z);
    const dl = _hv.length();
    const maxStep = rate * dt;
    if (dl > maxStep) _hv.multiplyScalar(maxStep / dl);
    this.vel.x += _hv.x;
    this.vel.z += _hv.z;

    if (input.pressed('jump') && this.grounded) {
      this.vel.y = JUMP_V;
      this.grounded = false;
      g.events.emit('player:jump', {});
    }
    // Exact constant-acceleration step: the 1.1 m apex holds at any frame rate.
    const vy0 = this.vel.y;
    this.vel.y -= P.gravity * dt;
    this.knock.multiplyScalar(Math.exp(-dt * 6));

    _delta.set((this.vel.x + this.knock.x) * dt, (vy0 + this.vel.y) * 0.5 * dt, (this.vel.z + this.knock.z) * dt);
    const col = g.level.col;
    const wasGrounded = this.grounded;
    const expectY = this.pos.y + _delta.y;
    const res = col.moveCircle(this.pos, _delta, this.radius, this.height, STEP_UP);
    let onGround = res.onGround;
    if (!onGround && wasGrounded && this.vel.y <= 0) {
      // Walk down steps/ramps instead of hopping off them.
      const f = col.floorAt(this.pos.x, this.pos.z, this.pos.y);
      if (f > -Infinity && this.pos.y - f <= STEP_UP) { this.pos.y = f; onGround = true; }
    }
    if (onGround) {
      if (!wasGrounded && this.vel.y < -2) g.events.emit('player:land', { speed: -this.vel.y });
      this.vel.y = Math.max(this.vel.y, -1);
    } else if (this.vel.y > 0 && this.pos.y < expectY - 1e-4) {
      this.vel.y = 0; // head bump
    }
    this.grounded = onGround;
    this.area = g.level.areaAt(this.pos.x, this.pos.z) || this.area;
    this.history.tick(dt, this.pos, this.yaw, this.area);
  }

  _vitals(dt) {
    this._iframes = Math.max(0, this._iframes - dt);
    this._sinceHurt += dt;
    if (this.alive && !this.downed && this._sinceHurt >= this.mods.regenDelay && this.health < this.maxHealth) {
      this.health = Math.min(this.maxHealth, this.health + this.mods.regenRate * dt);
    }
    // Signal-loss post effect follows missing health (eased so hits read as a pulse).
    const target = this.alive ? 1 - this.health / this.maxHealth : 1;
    this._damage += (target - this._damage) * (1 - Math.exp(-dt * (target > this._damage ? 14 : 3)));
    this.game.render.post.damage = this._damage;
  }

  _animate(rdt) {
    const g = this.game;
    if (!this.animator) return;
    this.model.position.copy(this.pos);

    // Facing: aim direction while moving/aiming/firing; idle free-look turns the body past ~60 degrees.
    const hs = Math.hypot(this.vel.x, this.vel.z);
    const firing = this.anim.recoil > 0.05 || this.anim.melee > 0;
    if (this.sprinting && hs > 0.5) this._faceYaw = Math.atan2(-this.vel.x, -this.vel.z);
    else if (hs > 0.4 || this.ads || firing) this._faceYaw = this.yaw;
    else if (Math.abs(wrapAngle(this.yaw - this._faceYaw)) > 1.05) this._faceYaw = this.yaw;
    const cur = this._modelYaw.x;
    const target = cur + wrapAngle(this._faceYaw - cur);
    this._modelYaw.update(rdt, target);
    this.model.rotation.y = this._modelYaw.x;
    const turn = rdt > 0 ? this._modelYaw.v : 0;

    // Movement relative to the body for strafing legs / backpedal.
    const my = this._modelYaw.x;
    const fx = -Math.sin(my), fz = -Math.cos(my);
    const lz = this.vel.x * fx + this.vel.z * fz;
    const lx = this.vel.x * -fz + this.vel.z * fx;
    const back = lz < -0.3 && hs > 0.5;
    const legYaw = hs > 0.5 && !this.sprinting ? THREE.MathUtils.clamp(back ? Math.atan2(lx, -lz) : Math.atan2(-lx, lz), -1.1, 1.1) * 0.75 : 0;

    const a = this.anim;
    a.speed = this.grounded ? hs : 0;
    a.sprint = this.sprinting;
    a.grounded = this.grounded;
    a.aimPitch = this.pitch;
    a.aimYaw = THREE.MathUtils.clamp(wrapAngle(this.yaw - my), -1.1, 1.1);
    a.aiming = !this.sprinting && !!this.weaponModel;
    a.back = back;
    a.turn = turn;
    a.legYaw = legYaw;
    a.hurt = Math.max(0, a.hurt - rdt / 0.3);
    if (!this.alive) a.dead = Math.min(1, a.dead + rdt / 0.9);
    this.animator.update(rdt, a);
    this._footsteps();
  }

  _footsteps() {
    const g = this.game;
    const idx = Math.floor(this.animator.phase / Math.PI);
    if (idx === this._stepIndex) return;
    this._stepIndex = idx;
    if (!this.grounded || this.anim.speed < 0.8) return;
    const level = g.level;
    const surface = (level.surfaceAt && level.surfaceAt(this.pos.x, this.pos.z, this.pos.y))
      || (level.areas[this.area] && level.areas[this.area].floor) || 'carpet';
    g.events.emit('player:step', { foot: idx & 1, sprint: this.sprinting, surface });
  }

  lateUpdate() {
    // Hero fade when the camera gets closer than 0.8 m (dithered via the global uHeroFade uniform).
    const g = this.game;
    if (!this.hero) return;
    const d = g.cam ? g.cam.heroDistance : 3;
    const fade = THREE.MathUtils.smoothstep(d, 0.35, 0.8);
    g.mats.uniforms.uHeroFade.value = fade;
    // Parts that cannot dither (glow eyes, glasses, art attachments) hide as soon as the dither starts.
    const hide = fade < 0.9;
    if (hide !== this._hidden) {
      this._hidden = hide;
      this.model.traverse((o) => { if (o.userData.daHideOnFade) o.visible = !hide; });
    }
  }
}
