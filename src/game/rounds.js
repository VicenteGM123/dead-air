// Round flow (ARCHITECTURE §10, GDD §7 entirely, §13 step 3 spawn override). Owned by the zombies agent.
//
// Fields: round, special (false | 'hullabaloo'), phase ('pregame' | 'active' | 'intermission'), count (zombies in
//   this round, specials included), toSpawn (left to spawn), killsThisRound, totalKills, paused, timer (seconds
//   left in pregame/intermission), hullabalooIndex (k of the last Hullabaloo Hour), nextHullabaloo (round number),
//   token (id of the current round's spawns: zombies carry it as z.fromRound).
// Methods: startRound(n), pauseSpawning(bool), onZombieKilled(z), requeue(z | typeId) (anti-stuck despawns),
//   rollTunedInSpeed() (GDD §7.3 roll with the 60 % super-sprint cap of this round), isHullabaloo(r), nextSpecial
//   (getter: false | 'hullabaloo' for round + 1), forceForecaster() (spawn one now, counting toward the round: EE
//   step 3 override / 'egg:need_forecaster'). startRound(n) in the middle of a round (debug.setRound) first clears
//   the old round's zombies (static puff, no points, no kills).
// Exported formulas: zombieCount(r), zombieHp(r), spawnInterval(r), rollSpeed(r, rand), hullabalooCount(k),
//   hullabalooHp(k, r), forecasterCount(r), bigShotScheduled(r).
// Flow: game start -> round 1 (or params.round) after T.rounds.firstRoundDelay; each round opens with the round sting
//   (sting_round_start, minor sting_round_start_13 on round 13 + event round:thirteen), the first spawn comes
//   T.rounds.firstSpawnDelay later, then one spawn per spawnInterval(r) (0.8 s in Hullabaloo) while fewer than
//   T.rounds.maxAlive (10 in Hullabaloo) are alive. The round ends when `count` of its zombies were killed (anti-stuck
//   despawns are requeued), then a T.rounds.intermission (12 s after a Hullabaloo Hour) break: sting_round_end,
//   music 'intermission'. The decorative TVs (right_back / hullabaloo) are switched by screens.js on round:end /
//   round:start (it reads nextSpecial). Tube grenades +T.player.grenadesPerRound from round 2 (weapons.addGrenades,
//   skipped when weapons.js already granted them on round:start).
// Specials: Hullabaloo Hour (first on round 5 or 6, then every 4–5 rounds; Sock Hoppers only; count
//   min(8 + 4(k−1), 24), HP 350 then max(350, 0.4·HP(r)); telegraphed during the intermission before it (round:end
//   next.special, round:telegraph), lilac lights over 2 s, sting_hullabaloo_intro; the last sock drops FULL REEL then
//   sting_hullabaloo_end). Mix-ins: Forecasters from r7 at 20–70 % of the queue (max 2 alive, 3 from r15), Big Shots
//   on rounds 10, 13, 16… at 50 % / 75 % (2 from r20, +10 % extra chance from r12, pushed off Hullabaloo rounds),
//   Sock Hoppers 10 % of spawns from r12 (15 % from r20). EE: while game.egg.forceForecaster, every round has at least
//   one Forecaster and, past 60 % of the queue with none alive and no Stray Storm (egg.stormActive / egg.storm), one
//   spawns immediately.
// Music: 'hullabaloo' in Hullabaloo Hour, 'round' from round 10 once powered, 'ambient' otherwise; 'intermission'
//   bossa between rounds once powered. Nothing is changed while game.boss is active.
// Events: round:start {round, special}, round:end {round, special, intermission, next:{round, special}},
//   round:telegraph {round, special:'hullabaloo', seconds} (the Hullabaloo telegraph starts), round:thirteen {round}.

import * as THREE from 'three';
import { T } from '../core/config.js';

const R = T.rounds;
const H = R.hullabaloo;
const LILAC = new THREE.Color('#C9A7FF');
const LILAC_GROUND = new THREE.Color('#5A3F7A');
const WARM_LILAC = -1.6;          // render.post.warmth at full Hullabaloo tint (default 1 = warm 70s)

export function zombieCount(r) {
  if (r <= R.early.length) return R.early[Math.max(1, r) - 1];
  const k = r - R.early.length;
  return Math.min(R.countCap, Math.floor(R.early[R.early.length - 1] + R.countA * k + R.countB * k * k));
}

export function zombieHp(r) {
  if (r <= 9) return R.hpEarlyBase + R.hpEarlyStep * (Math.max(1, r) - 1);
  return Math.min(R.hpCap, Math.round((R.hpEarlyBase + R.hpEarlyStep * 8) * R.hpMul ** (r - 9)));
}

export function spawnInterval(r) {
  return Math.max(R.interval.min, R.interval.base * R.interval.mul ** (r - 1));
}

// Tuned-In speed tier roll (GDD §7.3) -> m/s (no cap; Rounds.rollTunedInSpeed applies the 60 % super cap).
export function rollSpeed(r, rand) {
  const s = R.speedRoll;
  const v = s.perRound * r + (rand() * 2 - 1) * s.jitter;
  if (v < s.jog) return R.speeds.walk;
  if (v < s.sprint) return R.speeds.jog;
  if (v < s.super) return R.speeds.sprint;
  return R.speeds.super;
}

export function hullabalooCount(k) {
  const [base, step, cap] = H.count;
  return Math.min(base + step * (k - 1), cap);
}

export function hullabalooHp(k, r) {
  return k <= 1 ? H.hpFirst : Math.max(H.hpFirst, Math.round(H.hpMul * zombieHp(r)));
}

export function forecasterCount(r) {
  return r < R.forecasterFrom ? 0 : Math.min(1 + Math.floor((r - R.forecasterFrom) / 4), 3);
}

export function bigShotScheduled(r) {
  if (r < R.bigShotFrom || (r - R.bigShotFrom) % R.bigShotEvery !== 0) return 0;
  return r >= 20 ? 2 : 1;
}

const between = (rand, a, b) => a + Math.floor(rand() * (b - a + 1));

export class Rounds {
  constructor(game) {
    this.game = game;
    this.round = 0;
    this.special = false;
    this.toSpawn = 0;
    this.count = 0;
    this.killsThisRound = 0;
    this.totalKills = 0;
    this.phase = 'pregame';
    this.paused = false;
    this.timer = 0;
    this.token = 0;
    this.hullabalooIndex = 0;
    this.nextHullabaloo = 5;
    this.queue = [];
    this._spawnT = 0;
    this._bigShotCarry = 0;
    this._tunedIn = 0;
    this._superCap = 0;
    this._superUsed = 0;
    this._spawned = 0;
    this._eeForcedT = 0;
    this._tint = null;
    this._thirteenT = 0;
  }

  init() {
    const ev = this.game.events;
    ev.on('egg:need_forecaster', () => this.forceForecaster());
    ev.on('power:on', () => { if (this.phase === 'active') this._music(); });
    // The hemisphere light is recomputed by lights.js every frame after the systems ran: tint it right before the
    // render instead.
    const r = this.game.render;
    if (r && typeof r.addPrePass === 'function') r.addPrePass(() => this._tintHemi());
  }

  _tintHemi() {
    const t = this._tint, L = this.game.lights;
    if (!t || !L || !L.hemi) return;
    const k = t.k * t.k * (3 - 2 * t.k);
    L.hemi.color.lerp(LILAC, k * 0.6);
    L.hemi.groundColor.lerp(LILAC_GROUND, k * 0.45);
  }

  reset() {
    const g = this.game;
    this.round = 0;
    this.special = false;
    this.toSpawn = this.count = this.killsThisRound = this.totalKills = 0;
    this.phase = 'pregame';
    this.paused = false;
    this.timer = R.firstRoundDelay;
    this.token = 0;
    this.hullabalooIndex = 0;
    this.nextHullabaloo = between(g.rand, H.first[0], H.first[1]);
    this.queue = [];
    this._bigShotCarry = 0;
    this._spawned = 0;
    this._eeForcedT = 0;
    this._restoreTint(true);
    if (g.zombies) g.zombies.maxAlive = R.maxAlive;
  }

  isHullabaloo(r) {
    return r === this.nextHullabaloo;
  }

  // The special of the next round (false | 'hullabaloo'); screens.js reads it on round:end.
  get nextSpecial() {
    return this.isHullabaloo(this.round + 1) ? 'hullabaloo' : false;
  }

  // ---------------------------------------------------------------------------------------------- rounds
  startRound(n) {
    const g = this.game;
    const r = Math.max(1, Math.floor(n));
    // Jumping ahead (params.round / debug.setRound): the skipped Hullabaloo Hours count (k grows as if they had been
    // played) and the schedule moves into the future.
    while (this.nextHullabaloo < r) {
      if (this.nextHullabaloo > this.round) this.hullabalooIndex++;
      this.nextHullabaloo += between(g.rand, H.every[0], H.every[1]);
    }
    const first = this.round === 0;
    // A jump in the middle of a round (debug.setRound): the leftovers of the old round leave in a static puff.
    const Zs = g.zombies;
    if (this.phase === 'active' && Zs && Zs.alive.length && typeof Zs.despawnAll === 'function') Zs.despawnAll({ fx: true, requeue: false });
    this.round = r;
    this.token++;
    this.special = this.isHullabaloo(r) ? 'hullabaloo' : false;
    if (this.special) this.hullabalooIndex++;
    this.queue = this._buildQueue(r);
    this.count = this.toSpawn = this.queue.length;
    this.killsThisRound = 0;
    this._spawned = 0;
    this.phase = 'active';
    this.timer = 0;
    this._spawnT = R.firstSpawnDelay;
    this._lastSockPos = null;
    if (g.zombies) g.zombies.maxAlive = this.special ? H.maxAlive : R.maxAlive;
    // Tuned-In speed cap for this round (GDD §7.3: at most 60 % super-sprinters).
    this._tunedIn = this.queue.filter((t) => t === 'tuned_in').length;
    this._superCap = Math.floor(R.speedRoll.superCap * this._tunedIn);
    this._superUsed = 0;
    if (this.special && !this._tint) this._startTint();
    // Grenades: +2 per round from round 2 (the start kit covers round 1). weapons.js may grant them itself on
    // round:start; then the count already moved and we leave it alone.
    const w = g.weapons;
    const nades = w && typeof w.grenades === 'number' ? w.grenades : null;
    g.events.emit('round:start', { round: r, special: this.special });
    if (!first && (nades === null || w.grenades === nades)) this._grantGrenades();
    if (!this._bossActive()) {
      g.audio.play(r === 13 ? 'sting_round_start_13' : 'sting_round_start');
      this._music();
    }
    if (r === 13) {
      g.events.emit('round:thirteen', { round: r });
      this._thirteenT = 6;
    }
  }

  // Spawn queue of type ids (specials count toward N, GDD §7.1/§7.6).
  _buildQueue(r) {
    const g = this.game, rand = g.rand;
    if (this.special === 'hullabaloo') {
      // A Big Shot scheduled on a Hullabaloo round moves to the next round.
      this._bigShotCarry += bigShotScheduled(r);
      return new Array(hullabalooCount(this.hullabalooIndex)).fill('sock_hopper');
    }
    const n = zombieCount(r);
    const q = new Array(n).fill('tuned_in');
    const taken = new Set([0]);
    const place = (type, at) => {
      let i = THREE.MathUtils.clamp(Math.round(at), 1, n - 1);
      for (let k = 0; k < n && taken.has(i); k++) i = (i + 1) % n || 1;
      if (taken.has(i)) return;
      taken.add(i);
      q[i] = type;
    };
    // Big Shots: 50 % / 75 % of the queue.
    let bs = bigShotScheduled(r) + this._bigShotCarry;
    this._bigShotCarry = 0;
    if (!bs && r >= 12 && rand() < R.bigShotExtra) bs = 1;
    bs = Math.min(bs, 3);
    [0.5, 0.75, 0.9].slice(0, bs).forEach((f) => place('big_shot', n * f));
    // Forecasters: random points 20–70 % of the queue (EE step 3 override: at least one).
    let fc = forecasterCount(r);
    if (this._eeForce() && fc < 1) fc = 1;
    for (let k = 0; k < fc; k++) place('forecaster', n * (0.2 + rand() * 0.5));
    // Sock Hoppers mixed in from round 12.
    if (r >= R.sockMixFrom) {
      const p = r >= 20 ? R.sockMix[1] : R.sockMix[0];
      for (let i = 1; i < n; i++) if (!taken.has(i) && rand() < p) { taken.add(i); q[i] = 'sock_hopper'; }
    }
    return q;
  }

  pauseSpawning(on) {
    this.paused = !!on;
  }

  // GDD §7.3 per-zombie tier roll with the round's 60 % super-sprint cap (excess become sprinters).
  rollTunedInSpeed() {
    const g = this.game;
    const v = rollSpeed(Math.max(1, this.round || 1), g.rand);
    if (v >= R.speeds.super) {
      if (this._superUsed >= this._superCap) return R.speeds.sprint;
      this._superUsed++;
    }
    return v;
  }

  onZombieKilled(z) {
    const g = this.game;
    this.totalKills++;
    if (this.phase !== 'active' || !z || z.fromRound !== this.token) return;
    this.killsThisRound++;
    if (z.type === 'sock_hopper') this._lastSockPos = z.pos.clone();
    if (this.killsThisRound >= this.count) {
      if (this.special === 'hullabaloo') {
        // The last Sock Hopper always drops FULL REEL, then "…and now back to our program".
        const pos = this._lastSockPos || z.pos.clone();
        const pu = g.powerups;
        try {
          if (pu && typeof pu.dropGuaranteed === 'function') pu.dropGuaranteed('full_reel', pos);
          else if (pu && typeof pu.drop === 'function') pu.drop('full_reel', pos);
        } catch (err) { console.warn('[rounds] full reel drop failed', err); }
        g.audio.play('sting_hullabaloo_end');
      }
      this._endRound();
    }
  }

  // Anti-stuck despawn / straggler: the zombie goes back into this round's queue.
  requeue(zOrType) {
    const z = typeof zOrType === 'object' ? zOrType : null;
    const type = z ? z.type : zOrType;
    if (this.phase !== 'active' || (z && z.fromRound !== this.token)) return;
    this.queue.unshift(type || 'tuned_in');
    this.toSpawn++;
    this._spawnT = Math.min(this._spawnT, 1);
  }

  // EE step 3 override: one Forecaster right now, counting toward the round.
  forceForecaster() {
    const g = this.game;
    if (this.phase !== 'active' || this._bossActive() || !g.zombies) return null;
    const z = g.zombies.spawn('forecaster', null, null, { fromRound: this.token });
    if (z) { this.count++; this._spawned++; }
    return z;
  }

  _endRound() {
    const g = this.game;
    const wasSpecial = this.special;
    this.phase = 'intermission';
    this.timer = wasSpecial ? H.intermission : R.intermission;
    const next = { round: this.round + 1, special: this.isHullabaloo(this.round + 1) ? 'hullabaloo' : false };
    g.events.emit('round:end', { round: this.round, special: wasSpecial, intermission: this.timer, next });
    if (g.zombies) g.zombies.maxAlive = R.maxAlive;
    if (wasSpecial) this._restoreTint();
    // The decorative TVs (WE'LL BE RIGHT BACK / Hootie's intro) are switched by screens.js on round:end/start.
    if (!this._bossActive()) {
      if (!wasSpecial) g.audio.play('sting_round_end');
      if (next.special) this._telegraphHullabaloo(next.round);
      else g.audio.music(this._powered() ? 'intermission' : 'ambient');
    }
  }

  // The intermission before a Hullabaloo Hour: every decorative TV on Hootie's intro, lilac lights, organ + hoots.
  _telegraphHullabaloo(round) {
    const g = this.game;
    this._startTint();
    g.audio.play('sting_hullabaloo_intro');
    g.audio.music('hullabaloo');
    g.events.emit('round:telegraph', { round, special: 'hullabaloo', seconds: this.timer });
  }

  update(dt) {
    const g = this.game;
    this._updateTint(dt);
    if (this._thirteenT > 0) this._thirteenT -= dt;
    if (this._bossActive()) return;
    if (this.phase !== 'active') {
      this.timer -= dt;
      if (this.timer <= 0) {
        const first = g.params.round;
        this.startRound(this.round === 0 && Number.isFinite(first) && first >= 1 ? first : this.round + 1);
      }
      return;
    }
    if (this.paused) return;
    // EE step 3 override: past 60 % of the queue with no Forecaster and no Stray Storm -> one now.
    if (this._eeForce()) {
      this._eeForcedT -= dt;
      const Zs = g.zombies;
      if (this._eeForcedT <= 0 && this._spawned >= 0.6 * this.count && Zs && Zs.count('forecaster') === 0 && !this.queue.includes('forecaster') && !this._stormActive()) {
        this._eeForcedT = 20;
        this.forceForecaster();
      }
    }
    if (this.toSpawn <= 0) return;
    this._spawnT -= dt;
    if (this._spawnT > 0) return;
    const Zs = g.zombies;
    if (!Zs || Zs.alive.length >= Zs.maxAlive) { this._spawnT = 0.1; return; }
    const i = this._nextIndex();
    if (i < 0) { this._spawnT = 0.25; return; }
    const type = this.queue[i];
    const opts = { fromRound: this.token };
    if (this.special === 'hullabaloo' && type === 'sock_hopper') opts.hp = hullabalooHp(this.hullabalooIndex, this.round);
    const z = Zs.spawn(type, null, null, opts);
    if (!z) { this._spawnT = 0.2; return; }
    this.queue.splice(i, 1);
    this.toSpawn = this.queue.length;
    this._spawned++;
    this._spawnT = this.special === 'hullabaloo' ? H.interval : spawnInterval(this.round);
  }

  // First queue entry whose type is not at its alive cap (Forecasters 2 / 3 from r15, Big Shots 1 / 2 from r20).
  _nextIndex() {
    const Zs = this.game.zombies, r = this.round;
    const capF = r >= 15 ? 3 : 2, capB = r >= 20 ? 2 : 1;
    for (let i = 0; i < this.queue.length; i++) {
      const t = this.queue[i];
      if (t === 'forecaster' && Zs.count('forecaster') >= capF) continue;
      if (t === 'big_shot' && Zs.count('big_shot') >= capB) continue;
      return i;
    }
    return -1;
  }

  // ------------------------------------------------------------------------------------------ helpers
  _music() {
    const g = this.game;
    if (this._bossActive()) return;
    if (this.special === 'hullabaloo') g.audio.music('hullabaloo');
    else g.audio.music(this.round >= 10 && this._powered() ? 'round' : 'ambient');
  }

  _powered() {
    const g = this.game;
    return !!((g.machines && g.machines.powerOn) || (g.level && g.level.powered));
  }

  _bossActive() {
    const b = this.game.boss;
    return !!(b && (b.active || b.running || b.fighting));
  }

  _eeForce() {
    const e = this.game.egg;
    return !!(e && e.forceForecaster);
  }

  _stormActive() {
    const e = this.game.egg;
    return !!(e && (e.stormActive || (e.storm && e.storm.active !== false)));
  }

  _grantGrenades() {
    const w = this.game.weapons;
    const n = T.player.grenadesPerRound;
    if (!w) return;
    try {
      if (typeof w.addGrenades === 'function') w.addGrenades(n, 'round');
      else if (typeof w.grenades === 'number') w.grenades = Math.min(T.player.grenadesMax, w.grenades + n);
    } catch (err) { console.warn('[rounds] grenades', err); }
  }

  // Lilac light shift (GDD §7.5): every point-light anchor, the key light and the hemisphere (see _tintHemi) lerp
// toward #C9A7FF over 2 s.
  _startTint() {
    if (this._tint) { this._tint.dir = 1; return; }      // still fading back: turn around (keeps the true originals)
    const L = this.game.lights;
    if (!L || !L.anchors) return;
    const saved = [];
    for (const a of L.anchors.values()) if (!a.flash) saved.push({ a, orig: a.color.clone(), last: a.color.clone() });
    this._tint = { saved, key: L.key ? L.key.color.clone() : null, k: 0, dir: 1 };
  }

  _restoreTint(instant = false) {
    const t = this._tint;
    if (!t) return;
    if (instant) { t.k = 0; this._applyTint(); this._tint = null; return; }
    t.dir = -1;
  }

  _updateTint(dt) {
    const t = this._tint;
    if (!t) return;
    t.k = THREE.MathUtils.clamp(t.k + (t.dir * dt) / 2, 0, 1);
    this._applyTint();
    if (t.dir < 0 && t.k <= 0) this._tint = null;
  }

  _applyTint() {
    const t = this._tint, L = this.game.lights;
    if (!t || !L) return;
    const k = t.k * t.k * (3 - 2 * t.k) * 0.8;
    for (const s of t.saved) {
      // Somebody else changed this light meanwhile (power on, EE): let go of it.
      if (!s.a.color.equals(s.last)) { s.orig.copy(s.a.color); }
      s.a.color.copy(s.orig).lerp(LILAC, k);
      s.last.copy(s.a.color);
    }
    if (t.key && L.key) L.key.color.copy(t.key).lerp(LILAC, k * 0.7);
    // The station's lighting is mostly image-based, so the light colours alone barely read: the grade's warm 70s
    // tint also swings to a cool lilac (render.post.warmth; someone else writing it meanwhile becomes the new base).
    const P = this.game.render && this.game.render.post;
    if (P && typeof P.warmth === 'number') {
      if (t.warm === undefined || (t.lastWarm !== undefined && P.warmth !== t.lastWarm)) t.warm = P.warmth;
      P.warmth = t.warm + (WARM_LILAC - t.warm) * (k / 0.8);
      t.lastWarm = P.warmth;
    }
  }
}
