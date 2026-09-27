// Debug / test API (ARCHITECTURE §11): window.__game.debug.
//   teleport(x, z, yaw?), look(yaw, pitch), mouseDelta(dx, dy), god(bool), addPoints(n), setRound(n), power(bool),
//   openAllDoors(), give(weaponId, upgraded?), perk(perkId), spawn(typeId, x?, z?), killAll(), freeze(bool),
//   shotCam(camIdOrPos|null, target?) (named 'cam_*' anchor or explicit [x,y,z]/Vector3 + target; hides the HUD;
//   null restores), freeCam(bool) (fly with WASD, Q/E down/up, Shift fast, mouse look), state() (JSON
//   snapshot), egg(step), showCard(cardId) (a CRT 1.8 m in front of the player showing that gfx card through
//   game.screens group 'scr_preview'; false for unknown ids).
// ?shot=<camId> places the shot camera at boot and freezes gameplay (art screenshots).

import * as THREE from 'three';

const _v = new THREE.Vector3();
const _look = { yaw: 0, pitch: 0 };
const _eul = new THREE.Euler(0, 0, 0, 'YXZ');

export class Debug {
  constructor(game) {
    this.game = game;
    this.active = null; // null | 'shot' | 'free'
    this._yaw = 0;
    this._pitch = 0;
  }

  init() {
    const g = this.game;
    if (g.params.shot) {
      g.events.once('game:start', () => {
        this.shotCam(String(g.params.shot));
        g.time.scale = 0;
        this.freeze(true);
      });
    }
  }

  _vec(v) {
    if (!v) return null;
    return v.isVector3 ? v.clone() : new THREE.Vector3(v[0], v[1], v[2]);
  }

  teleport(x, z, yaw) {
    this.game.player.teleport(x, z, yaw);
    return this.state().player;
  }

  look(yaw, pitch = 0) {
    const p = this.game.player;
    p.yaw = yaw;
    p.pitch = pitch;
  }

  mouseDelta(dx, dy) {
    this.game.input.injectMouse(dx, dy);
  }

  god(on = true) {
    this.game.player.god = !!on;
  }

  addPoints(n) {
    this.game.economy.add(n, 'debug');
    return this.game.economy.points;
  }

  setRound(n) {
    this.game.rounds.startRound(n);
  }

  power(on = true) {
    this.game.machines.setPower(!!on);
  }

  openAllDoors() {
    this.game.level.openAllDoors();
  }

  give(weaponId, upgraded = false) {
    return this.game.weapons.give(weaponId, { upgraded });
  }

  perk(perkId) {
    return this.game.perks.give(perkId);
  }

  spawn(typeId = 'tuned_in', x, z) {
    const g = this.game;
    let pos = null;
    if (x !== undefined && z !== undefined) {
      const f = g.level.col.floorAt(x, z, 50);
      pos = new THREE.Vector3(x, f > -Infinity ? f : 0, z);
    }
    const zz = g.zombies.spawn(typeId, null, pos);
    return zz ? zz.id : null;
  }

  killAll() {
    this.game.zombies.killAll('debug');
  }

  freeze(on = true) {
    this.game.zombies.freezeAll(!!on);
  }

  shotCam(camIdOrPos, target) {
    const g = this.game;
    if (camIdOrPos === null || camIdOrPos === undefined || camIdOrPos === false) {
      this._release();
      return true;
    }
    let pos, look;
    if (typeof camIdOrPos === 'string') {
      const a = g.level.anchors[camIdOrPos];
      if (!a) { console.warn(`[debug] unknown shot camera '${camIdOrPos}'`); return false; }
      pos = a.pos.clone();
      look = a.target ? a.target.clone()
        : pos.clone().add(_v.set(-Math.sin(a.rotY || 0), 0, -Math.cos(a.rotY || 0)));
    } else {
      pos = this._vec(camIdOrPos);
      look = this._vec(target) || pos.clone().add(_v.set(0, 0, -1));
    }
    this._take('shot');
    g.camera.position.copy(pos);
    g.camera.lookAt(look);
    g.camera.updateMatrixWorld();
    return true;
  }

  freeCam(on = true) {
    const g = this.game;
    if (!on) { this._release(); return; }
    this._take('free');
    _v.set(0, 0, -1).applyQuaternion(g.camera.quaternion);
    this._yaw = Math.atan2(-_v.x, -_v.z);
    this._pitch = Math.asin(THREE.MathUtils.clamp(_v.y, -1, 1));
  }

  _take(mode) {
    const g = this.game;
    this.active = mode;
    g.cam.enabled = false;
    g.player.controlLocked = true;
    if (g.hud && g.hud.hide) g.hud.hide();
  }

  _release() {
    const g = this.game;
    if (!this.active) return;
    this.active = null;
    g.cam.enabled = true;
    g.player.controlLocked = false;
    if (g.hud && g.hud.show) g.hud.show();
  }

  showCard(id) {
    const g = this.game;
    if (!g.cards.ids().includes(id)) return false;
    if (!this._card) {
      this._card = new THREE.Mesh(g.mats.screenGeometry(1.2, 0.9), g.mats.screen(null, { w: 1.2, h: 0.9 }));
      this._card.name = 'debug_card';
      g.scene.add(this._card);
      g.screens.register(this._card, 'scr_preview', { id: 'debug_card' });
    }
    const { w, h } = g.cards.info(id);
    const p = g.player;
    p.forward(_v).setY(0).normalize();
    this._card.scale.set(1, (h / w) / 0.75, 1);
    this._card.position.copy(p.pos).addScaledVector(_v, 1.8).setY(p.pos.y + 1.5);
    this._card.lookAt(p.pos.x, p.pos.y + 1.5, p.pos.z);
    g.screens.setSource('scr_preview', id);
    return true;
  }

  egg(step) {
    const e = this.game.egg;
    if (e.setStep) e.setStep(step); else e.step = step;
    return e.step;
  }

  state() {
    const g = this.game, p = g.player;
    return JSON.parse(JSON.stringify({
      state: g.state,
      player: { pos: [p.pos.x, p.pos.y, p.pos.z], yaw: p.yaw, pitch: p.pitch, health: p.health, maxHealth: p.maxHealth,
        area: p.area, grounded: p.grounded, sprinting: p.sprinting, ads: p.ads, stamina: p.stamina, heroId: p.heroId, alive: p.alive },
      round: g.rounds.round, points: g.economy.points, zombies: g.zombies.alive.length,
      perks: g.perks.list.slice(), weapons: g.weapons.slots.map((s) => ({ id: s.id, upgraded: s.upgraded, mag: s.mag, reserve: s.reserve })),
      power: g.machines.powerOn, egg: g.egg.step,
      camera: { pos: g.camera.position.toArray(), fov: g.camera.fov, side: g.cam.side },
      interact: g.interact.current ? g.interact.current.id : null,
    }));
  }

  // Runs every frame (real dt) in every state.
  update(dt) {
    if (this.active !== 'free') return;
    const g = this.game, input = g.input, cam = g.camera;
    const d = input.lookDelta(_look);
    this._yaw += d.yaw;
    this._pitch = THREE.MathUtils.clamp(this._pitch + d.pitch, -1.5, 1.5);
    cam.quaternion.setFromEuler(_eul.set(this._pitch, this._yaw, 0));
    const speed = (input.key('ShiftLeft') ? 18 : 6) * dt;
    _v.set((input.key('KeyD') ? 1 : 0) - (input.key('KeyA') ? 1 : 0), (input.key('KeyE') ? 1 : 0) - (input.key('KeyQ') ? 1 : 0),
      (input.key('KeyS') ? 1 : 0) - (input.key('KeyW') ? 1 : 0));
    if (_v.lengthSq() > 0) cam.position.add(_v.normalize().multiplyScalar(speed).applyQuaternion(cam.quaternion));
    cam.updateMatrixWorld();
  }
}
