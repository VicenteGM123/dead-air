// Weapon data table (GDD §9.1–§9.5, §6.2, §18.7) — owned by the weapons engineer.
//
// WEAPON_DEFS: id -> base definition; weaponDef(id, upgraded) -> the merged definition (upgraded fields override the
// base, nested objects merged one level deep) or null. Every number below is GDD-verbatim unless marked "feel".
//
// Stat fields (base / upgraded):
//   id, name, cls ('pistol'|'shotgun'|'smg'|'rifle'|'lmg'|'wonder'|'tactical'|'lethal'|'melee')
//   fire        'hitscan' (weapons.js traces it) | 'custom' (wonder weapons: game.wonder.fire(id, ctx) every frame)
//   dmg, head (multiplier), rpm, mode ('semi'|'auto'|'burst'|'pump'|'special'), burst (rounds), burstGap (s between bursts)
//   pellets, mag, reserve, reload (s; pump: start time), shellReload (s per shell), reloadKind
//   ('speedloader'|'shell'|'mag'|'belt'|'battery'|'reel'|'goo'), spread [hip, ads] (degrees; pellets: cone half-angle),
//   falloff [fullTo m, minAt m, minMul], pierce (extra zombies; each 70% of the previous), move (speed multiplier),
//   range (m; hitscan max 80), channel (Telly), upgradedName, upgraded: { overrides }
//   splash { dmg, r, min } (flashbulb splash on every direct hit: SPECIAL REPORT), every13 { dmg, r } (24-HOUR MARATHON),
//   launch (m: SEASON FINALE kills tumble away), pageHits (BREAKING NEWS newspaper-page particles)
// Wonder fields (read by game.wonder; weapons.js only uses mag/reserve/reload/rpm/move): see each entry, GDD §9.4/§9.5.
// Feel fields (tuned for a punchy cartoon read; not GDD numbers):
//   hold 'pistol'|'rifle'|'lmg'|'remote'|'pole'|'cannon' (two-handed aim pose), scale (held model scale)
//   kick [pitch rad, yaw jitter rad] (cam.kick), shake (cam.shake trauma per shot), recoil [back m, rise rad] (model
//   spring), flash { size, color, rays } (muzzle), tracer { color, width, len, speed, style } (style: 'bullet'|'pellet'|
//   'stars'|'scratch'|'news'|'heavy'), smoke (puffs per shot), eject ('brass'|'shell'|null, at shot or pump),
//   fireCue (audio id; audio.js also voices weapon:fire), reloadCue.
// Equipment: tube_grenade { carry, start, perRound, fuse, radius, dmgBase, dmgPerRound, edgeMul, selfMax, wobbleSelf },
//   tiny_tele { carry, lure, arc, fuse, killR, killUpTo, dmgAfter }, melee (T.player.melee: dmg, cd, reach, lunge).

import { T, PAL } from '../core/config.js';

const R = T.player;
export const GHOST_MUL = T.perks.doubleVision.ghost;   // Double Vision: ghost image deals +50% of the bullet
export const PIERCE_MUL = 0.7;                         // GDD §9.1: each pierced zombie takes 70% of the previous
export const MAX_RANGE = 80;                           // GDD §9.1

export const SIGNAL_COLORS = { hot_mic: PAL.hotMic || '#FF5A3C', laugh_track: PAL.laughTrack || '#52E04A', cold_open: PAL.coldOpen || '#7FD4FF' };

export const WEAPON_DEFS = {
  // ------------------------------------------------------------------------------------------ normal weapons (§9.2)
  revolver_38: {
    id: 'revolver_38', name: '.38 Detective Special', show: 'Precinct 13', cls: 'pistol', fire: 'hitscan',
    dmg: 90, head: 3.0, rpm: 240, mode: 'semi', mag: 6, reserve: 36, reload: 2.0, reloadKind: 'speedloader',
    spread: [2.5, 0.4], falloff: [20, 40, 0.6], pierce: 1, move: 1, channel: 2,
    hold: 'pistol', scale: 1.4, kick: [0.034, 0.008], shake: 0.12, recoil: [0.07, 0.42],
    flash: { size: 0.5, color: '#FFD27A', rays: 5 }, tracer: { color: '#FFF2B8', width: 0.05, len: 3.2, speed: 170, style: 'bullet' },
    smoke: 2, eject: null, fireCue: 'wpn_revolver_38', reloadCue: 'reload_speedloader',
    upgradedName: 'SPECIAL REPORT',
    upgraded: { dmg: 450, head: 3, rpm: 300, mag: 8, reserve: 80, reload: 1.6, splash: { dmg: 300, r: 2.5, min: 0.3 },
      flash: { size: 0.75, color: '#EAF6FF', rays: 8 }, tracer: { color: '#FFFFFF', width: 0.06, len: 3.6, speed: 190, style: 'bullet' } },
  },
  pump_37: {
    id: 'pump_37', name: 'Model 37 Pump', show: 'Dusty Trails', cls: 'shotgun', fire: 'hitscan',
    dmg: 60, pellets: 8, head: 1.5, rpm: 70, mode: 'pump', pumpTime: 0.85, mag: 6, reserve: 42,
    reload: 0.4, shellReload: 0.45, reloadKind: 'shell', spread: [7, 5], falloff: [6, 15, 0.4], pierce: 0, move: 1, channel: 4,
    hold: 'rifle', scale: 1.12, kick: [0.06, 0.012], shake: 0.28, recoil: [0.12, 0.3],
    flash: { size: 0.95, color: '#FFB347', rays: 8 }, tracer: { color: '#FFD07A', width: 0.03, len: 1.4, speed: 120, style: 'pellet' },
    smoke: 5, eject: 'shell', fireCue: 'wpn_pump_37', reloadCue: 'reload_shell',
    upgradedName: 'SEASON FINALE',
    upgraded: { dmg: 170, pellets: 10, mag: 10, reserve: 80, rpm: 90, pumpTime: 0.6, reload: 0.3, shellReload: 0.35, launch: 3,
      tracer: { color: '#FFE14D', width: 0.035, len: 1.6, speed: 130, style: 'stars' } },
  },
  mp7: {
    id: 'mp7', name: 'MP7', show: 'Agent Thirteen', cls: 'smg', fire: 'hitscan',
    dmg: 60, head: 2.5, rpm: 900, mode: 'auto', mag: 40, reserve: 240, reload: 2.1, reloadKind: 'mag',
    spread: [3.5, 0.8], falloff: [15, 30, 0.7], pierce: 0, move: 1, channel: 5,
    hold: 'rifle', scale: 1.18, kick: [0.0085, 0.006], shake: 0.045, recoil: [0.03, 0.09],
    flash: { size: 0.36, color: '#FFE08A', rays: 4 }, tracer: { color: '#FFE9A8', width: 0.028, len: 2.2, speed: 160, style: 'bullet' },
    smoke: 0.34, eject: 'brass', fireCue: 'wpn_mp7', reloadCue: 'reload_mag',
    upgradedName: 'LATE LATE SHOW',
    upgraded: { dmg: 160, head: 2.5, rpm: 1000, mag: 60, reserve: 360, reload: 1.8,
      tracer: { color: '#FF9A3C', width: 0.022, len: 3.0, speed: 150, style: 'scratch' } },
  },
  m16a1: {
    id: 'm16a1', name: 'M16A1', show: 'Commando Club', cls: 'rifle', fire: 'hitscan',
    dmg: 110, head: 3.0, rpm: 800, mode: 'burst', burst: 3, burstGap: 0.3, mag: 30, reserve: 270, reload: 2.4, reloadKind: 'mag',
    spread: [3.0, 0.3], falloff: [30, 60, 0.8], pierce: 2, move: 1, channel: 7,
    hold: 'rifle', scale: 1.1, kick: [0.016, 0.006], shake: 0.07, recoil: [0.045, 0.12],
    flash: { size: 0.48, color: '#FFE3A0', rays: 3 }, tracer: { color: '#DDFBFF', width: 0.034, len: 3.0, speed: 185, style: 'bullet' },
    smoke: 0.7, eject: 'brass', fireCue: 'wpn_m16a1', reloadCue: 'reload_mag',
    upgradedName: 'BREAKING NEWS',
    upgraded: { dmg: 300, head: 3.5, rpm: 900, burstGap: 0.18, mag: 45, reserve: 405, reload: 2.0, pierce: 4, pageHits: true,
      tracer: { color: '#F4F1E8', width: 0.04, len: 3.2, speed: 190, style: 'news' } },
  },
  m60: {
    id: 'm60', name: 'M60', show: 'Truckers!', cls: 'lmg', fire: 'hitscan',
    dmg: 130, head: 2.0, rpm: 550, mode: 'auto', mag: 100, reserve: 400, reload: 5.0, reloadKind: 'belt',
    spread: [5.0, 1.2], falloff: [30, 60, 0.8], pierce: 3, move: 0.9, channel: 8,
    hold: 'lmg', scale: 1.05, kick: [0.016, 0.012], shake: 0.1, recoil: [0.05, 0.1],
    flash: { size: 0.72, color: '#FFB347', rays: 6 }, tracer: { color: '#FFB347', width: 0.055, len: 3.4, speed: 165, style: 'heavy' },
    smoke: 0.8, eject: 'brass', fireCue: 'wpn_m60', reloadCue: 'reload_mag',
    upgradedName: '24-HOUR MARATHON',
    upgraded: { dmg: 320, head: 2.5, rpm: 650, mag: 150, reserve: 600, reload: 3.8, pierce: 4, move: 1, every13: { dmg: 600, r: 2 } },
  },

  // ------------------------------------------------------------------------------------------ wonder weapons (§9.4)
  zapper: {
    id: 'zapper', name: 'The Zapper', show: 'Space Patrol 3000', cls: 'wonder', fire: 'custom',
    dmg: 6000, head: 1, rpm: 60 / 0.45, clickGap: 0.45, mode: 'special', mag: 13, reserve: 52, reload: 1.6, reloadKind: 'battery',
    spread: [5, 2], range: [25, 40], cone: [5, 2], chain: 3, chainR: 4, killUpTo: 25, stun: 1, bossDmg: 2000, move: 1, channel: 11,
    gags: ['gag_cartoon', 'gag_western', 'gag_cooking', 'gag_nature', 'gag_signoff'],
    hold: 'remote', scale: 1.15, kick: [0.02, 0.004], shake: 0.06, recoil: [0.03, 0.5], fireCue: 'wpn_zapper', reloadCue: 'reload_battery',
    upgradedName: 'CHANNEL SURFER',
    upgraded: { chain: 6, range: [35, 50], mag: 21, reserve: 126, killUpTo: 35, dmg: 12000, stunPulse: { r: 2.5, s: 1.5 } },
  },
  boom_mic: {
    id: 'boom_mic', name: 'The Boom Mic', show: 'The Groove Hour', cls: 'wonder', fire: 'custom',
    dmg: 500, head: 1, rpm: 60 / 0.8, recovery: 0.8, mode: 'special', mag: 2, reserve: 12, reload: 2.5, reloadKind: 'reel',
    spread: [40, 40], range: [15, 15], killUpTo: 30, move: 1, channel: 12,
    record: { max: 3, range: 12, cone: 40, slow: 0.35, chargeBase: 1, chargePerZombie: 2, chargeMax: 10, bossCounts: 3, rate: 1 },
    playback: { range: 15, cone: 50, killCharge: 3, dmgAfter: 8000, weakDmg: 500, knock: 4, stun: 1.5, bossPerCharge: 700 },
    hold: 'pole', scale: 1.0, kick: [0.03, 0.0], shake: 0.2, recoil: [0.08, 0.2], fireCue: 'wpn_boom_playback', reloadCue: 'reload_reel',
    upgradedName: 'QUADRAPHONIC',
    upgraded: { mag: 3, reserve: 18, killUpTo: 40, record: { rate: 2 }, playback: { quad: true, halfCones: 3 } },
  },
  chroma_key: {
    id: 'chroma_key', name: 'The Chroma-Key Cannon', show: 'Weather Watch 13', cls: 'wonder', fire: 'custom',
    dmg: 6000, head: 1, rpm: 60 / 0.7, shotGap: 0.7, mode: 'special', mag: 6, reserve: 36, reload: 2.2, reloadKind: 'goo',
    spread: [0, 0], splash: { r: 3.0 }, killUpTo: 25, bossDmg: 3000, move: 1, channel: 13,
    blob: { r: 0.18, speed: 22, gravity: 6, life: 2, bounces: 0, color: PAL.chromaBlue || '#1E5BFF' },
    puddle: { r: 3, life: 4, keys: 6 }, worlds: ['world_space', 'world_beach', 'world_volcano', 'world_underwater'], selfDamage: 0,
    hold: 'cannon', scale: 1.0, kick: [0.04, 0.006], shake: 0.16, recoil: [0.09, 0.25], fireCue: 'wpn_chroma_fire', reloadCue: 'reload_goo',
    upgradedName: 'THE GREEN SCREEN',
    upgraded: { splash: { r: 4.5 }, mag: 10, reserve: 60, killUpTo: 35, blob: { bounces: 1, color: '#39E75F' }, puddle: { life: 8, keys: 10 },
      worlds: ['world_space', 'world_beach', 'world_volcano', 'world_underwater', 'world_desert', 'world_moon'] },
  },

  // ------------------------------------------------------------------------------------------ equipment + melee (§9.3)
  tiny_tele: {
    id: 'tiny_tele', name: 'Tiny Tele', cls: 'tactical', fire: 'custom', carry: R.teleMax, lure: 15, arc: 2.2, fuse: 6, killR: 4,
    killUpTo: 30, dmgAfter: 20000, channel: 9,
  },
  tube_grenade: {
    id: 'tube_grenade', name: 'Tube Grenade', cls: 'lethal', carry: R.grenadesMax, start: R.grenadesStart, perRound: R.grenadesPerRound,
    fuse: 1.8, radius: 5, dmgBase: 300, dmgPerRound: 60, edgeMul: 0.25, selfMax: 40, wobbleSelf: 0.5,
    throwSpeed: 15, throwUp: 4.5, gravity: 18, restitution: 0.42, friction: 0.72, radiusBody: 0.07, // feel
  },
  melee: { id: 'melee', name: 'Melee', cls: 'melee', ...R.melee, time: 0.5, hitAt: 0.42, cone: 0.9 },
};

// Hero melee props + hit cues (GDD §4, §18.1).
export const MELEE_PROPS = {
  skip: { prop: 'melee_walkie', cue: 'melee_hit_skip', swing: 'bonk' },
  roxy: { prop: 'melee_lp', cue: 'melee_hit_roxy', swing: 'slap' },
  penny: { prop: 'melee_wrench', cue: 'melee_hit_penny', swing: 'bonk' },
  duke: { prop: null, cue: 'melee_hit_duke', swing: 'chop' },
};

export const HITSCAN_IDS = ['revolver_38', 'pump_37', 'mp7', 'm16a1', 'm60'];
export const WONDER_IDS = ['zapper', 'boom_mic', 'chroma_key'];
export const GUN_IDS = [...HITSCAN_IDS, ...WONDER_IDS];

const isObj = (v) => v && typeof v === 'object' && !Array.isArray(v);
const UPGRADED = {};
for (const id in WEAPON_DEFS) {
  const d = WEAPON_DEFS[id];
  if (!d.upgraded) continue;
  const u = { ...d, isUpgraded: true, displayName: d.upgradedName };
  for (const k in d.upgraded) u[k] = isObj(d.upgraded[k]) && isObj(d[k]) ? { ...d[k], ...d.upgraded[k] } : d.upgraded[k];
  UPGRADED[id] = u;
}
for (const id in WEAPON_DEFS) WEAPON_DEFS[id].displayName = WEAPON_DEFS[id].name;

export function weaponDef(id, upgraded = false) {
  return (upgraded && UPGRADED[id]) || WEAPON_DEFS[id] || null;
}

export const isGunDef = (d) => !!d && d.mag > 0;
