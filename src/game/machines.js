// Machines aggregator (ARCHITECTURE §3/§10; the screens agent owns the full version, keeping this API).
// Constructs the machine sub-systems and exposes them as game.screens, game.signon, game.telly, game.sponsors,
// game.uplink. Game drives each sub-system's lifecycle (init/reset/update/lateUpdate) as its own isolated system
// right after `machines`; Machines must not call those methods itself.
// powerOn is the single power flag. setPower(on) switches it: the pre-power grade of every toon material
// (mats.uniforms.uSatEnv 0.70 -> 1.0, uAmber 0.08 -> 0, GDD §3.3), opens the doors with requiresPower and emits
// power:on {}. reset() restores the unpowered station (game params power=1 is applied by Game after reset).
// Machine events (GDD §18.15) are emitted by the sub-systems: machine:sign_on, machine:telly_*,
// machine:commercial_start/end, machine:dish_aligned, machine:uplink_*, machine:boss_*, machine:screen_override.

import { ScreenManager } from './screens.js';
import { SignOn } from './signon.js';
import { Telly } from './telly.js';
import { Sponsors } from './sponsors.js';
import { Uplink } from './uplink.js';

const PRE_POWER = { sat: 0.7, amber: 0.08 };

export class Machines {
  constructor(game) {
    this.game = game;
    this.powerOn = false;
    game.screens = this.screens = new ScreenManager(game);
    game.signon = this.signon = new SignOn(game);
    game.telly = this.telly = new Telly(game);
    game.sponsors = this.sponsors = new Sponsors(game);
    game.uplink = this.uplink = new Uplink(game);
  }

  reset() {
    this.powerOn = false;
    this._grade(false);
  }

  setPower(on) {
    const g = this.game;
    if (this.powerOn === on) return;
    this.powerOn = on;
    this._grade(on);
    if (!on) return;
    const doors = g.level.doors || {};
    for (const id in doors) if (doors[id].requiresPower) g.level.openDoor(id);
    g.events.emit('power:on', {});
  }

  _grade(on) {
    const u = this.game.mats.uniforms;
    u.uSatEnv.value = on ? 1 : PRE_POWER.sat;
    u.uAmber.value = on ? 0 : PRE_POWER.amber;
    u.uWaveRadius.value = -1;
  }
}
