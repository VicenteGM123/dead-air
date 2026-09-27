// TUNED-IN (`tuned_in`, the studio audience) type module — GDD §8.1. Owned by the zombies agent.
// Contract: see the TYPE MODULE CONTRACT in src/actors/zombieTypes.js. The ZombieManager does the heavy lifting
// (window entry, flow-field chase, the two-arm swipe with T.zombies.tunedIn numbers, hit reactions, the topple +
// static dissolve death, head cork-pop); this module adds the model (sculpted variants z_crew / z_reporter / z_disco /
// z_mom when baked, else the placeholder, pooled), the HP / speed rules and the Tuned-In flavour: formant groans at
// random, a louder chase groan when it first spots you, and a clap of the hands on every 4th step.

import { T } from '../../core/config.js';
import { zombieHp, rollSpeed } from '../../game/rounds.js';
import { acquireModel, releaseModel, humanoidHitZones } from '../zombieTypes.js';

const TI = T.zombies.tunedIn;
const HEAR = 16;          // m: groans/claps farther than this are skipped (the audio engine has a voice budget)
let clapBudget = 0;       // global limiter: claps per second across the crowd
let clapT = 0;

export default {
  id: 'tuned_in',
  height: 1.62,
  radius: 0.36,
  dmg: TI.dmg,
  range: TI.range,
  windup: TI.windup,
  cd: TI.cd,
  spawnMode: 'window',

  hp(round) {
    return zombieHp(Math.max(1, round));
  },

  // GDD §7.3 tier roll; Rounds applies the per-round 60 % super-sprint cap.
  speed(round, game) {
    const r = game && game.rounds;
    if (r && typeof r.rollTunedInSpeed === 'function') return r.rollTunedInSpeed();
    return rollSpeed(Math.max(1, round), game ? game.rand : Math.random);
  },

  build(game, z) {
    const m = acquireModel(game, 'tuned_in', z.artVariant ?? -1);
    z.model = m;
    z.group = m.group;
    z.rig = m.rig;
    z.animator = m.animator;
    z.head = m.head;
    z.headR = m.headR;
    z.hitZones = humanoidHitZones(m);
    const h = m.rig && m.rig.dims ? m.rig.dims.height : 1.62;
    z.height = h;
    // Crowd variety: a little size jitter per spawn (the manager keeps it in z.scale).
    z.scale = 0.94 + Math.random() * 0.12;
    z.flags.groanT = 2 + Math.random() * 5;
    z.flags.step = 0;
    z.flags.lastPhase = 0;
    z.flags.clapT = 0;
  },

  release(game, z) {
    releaseModel(z.model);
    z.model = null;
  },

  // Flavour only: returns false so the manager steers and swipes.
  update(game, z, dt) {
    const f = z.flags;
    const p = game.player;
    const d = Math.hypot(p.pos.x - z.pos.x, p.pos.z - z.pos.z);
    // Global clap limiter (~3 per second).
    clapT += dt;
    if (clapT > 0.33) { clapT = 0; clapBudget = Math.min(1, clapBudget + 1); }

    f.groanT -= dt;
    if (f.groanT <= 0) {
      f.groanT = 3 + Math.random() * 5;
      if (d < HEAR) game.audio.play('zmb_groan', { pos: z.pos, rate: 0.9 + Math.random() * 0.25, vol: 0.8 });
    }
    // Spotted: the first time it gets line of sight within 12 m -> a louder chase groan.
    if (!f.spotted && z.los && d < 12) {
      f.spotted = true;
      game.audio.play('zmb_groan_chase', { pos: z.pos, rate: 0.95 + Math.random() * 0.2 });
      if (z.animator && z.animator.kick) z.animator.kick(0.35);
    }
    // Every 4th footstep (half gait cycle) the hands clap together.
    const a = z.animator;
    if (a && typeof a.phase === 'number') {
      const half = Math.floor(a.phase / Math.PI);
      if (half !== f.lastPhase) {
        f.lastPhase = half;
        if (z.anim.speed > 0.4 && ++f.step % 4 === 0) {
          f.clapT = 0.22;
          if (d < HEAR * 0.75 && clapBudget > 0) {
            clapBudget--;
            game.audio.play('zmb_clap', { pos: z.pos, vol: 0.7 });
          }
        }
      }
    }
    if (f.clapT > 0) f.clapT = Math.max(0, f.clapT - dt);
    z.anim.clap = f.clapT > 0 ? Math.sin((1 - f.clapT / 0.22) * Math.PI) : 0;
    return false;
  },
};
