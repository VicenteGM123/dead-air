#!/usr/bin/env node
// DEAD AIR — tools/audio/render.mjs
// Offline renderer of the game's sound (SPEC §7). The web build synthesises every sound live with WebAudio; the Godot
// port plays files instead. This script runs the ORIGINAL recipes — src/audio/sfx.js (synth toolkit + SFX_CUES),
// src/audio/music.js (Player sequencer, songs, MUSIC_CUES) and the cues src/game/wonder.js registers at runtime —
// on node-web-audio-api's OfflineAudioContext and writes Ogg Vorbis files (wasm-media-encoders) plus
// godot/assets/audio/index.json, which godot/scripts/audio/audio.gd reads.
//
// What is rendered (see README.md, in Spanish, for the full description):
//   sfx/<id>/v<k>_p<pitch>_<n>.ogg  every cue id at the VOICE level: the recipe output as it reaches the voice's
//       output chain (after the per-voice TV-speaker filter when the cue is heard through a TV), before volume,
//       panner/distance, bus, reverb, duck and master chain (audio.gd does those live). Several random variations
//       per cue (`n`), every parameter variant the game uses (`v<k>`: upgraded, rhythm, base, dur, syllables, …)
//       and, for recipes that read opts.pitch, the pitches (rate · 2^(detune/1200)) the call sites use.
//   loops/<id>.ogg  every cue the game runs through audio.loop(), rendered in loop mode exactly like audio.js
//       (endless recipes driven by their sequencers, one-shots retriggered back to back) and cut into
//       [intro | seamless loop] with a crossfaded seam; loop start/end in index.json.
//   music/<state>[_<stem>].ogg  every music state as [intro | bar-aligned loop] at its BPM, with the adaptive
//       layers as separate, sample-aligned stems (round/morning clav, boss base per phase + p2 + p3).
//   parts/<id>/…  per-note parts of the cues that the game plays note by note (telly_surf_arp step(),
//       toy_xylophone opts.notes) and the 440 Hz sine of ee_tracking_tones.
//
// Usage: node tools/audio/render.mjs [--only=id,id] [--no-music] [--no-sfx] [--no-loops] [--quick] [--wav]
//        [--jobs=N] [--q=4]          (npm run audio)
// Math.random is replaced by a seeded generator per rendered file, so a run is reproducible.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { OfflineAudioContext, AudioBufferSourceNode } from 'node-web-audio-api';
import { createOggEncoder } from 'wasm-media-encoders';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '../..');
const SRC = path.join(ROOT, 'src');
const OUT = path.join(ROOT, 'godot/assets/audio');
const SR = 44100;
const T0 = 0;                   // recipe start time inside every render
const DISPOSE = 0.15;           // audio.js disposes a voice 0.15 s after its end
const LOOKAHEAD = 0.4, START_LAG = 0.012;   // audio.js loop retrigger constants

// ------------------------------------------------------------------------------------------------ CLI
const ARGS = Object.fromEntries(process.argv.slice(2).map((a) => {
  const m = /^--([^=]+)(?:=(.*))?$/.exec(a);
  return m ? [m[1], m[2] ?? true] : [a, true];
}));
const ONLY = ARGS.only ? new Set(String(ARGS.only).split(',')) : null;
const QUICK = !!ARGS.quick;
const WAV = !!ARGS.wav;
const EXT = WAV ? 'wav' : 'ogg';
const JOBS = Math.max(1, +ARGS.jobs || 6);
const Q_SFX = ARGS.q != null ? +ARGS.q : 4;
const Q_MUSIC = ARGS.q != null ? +ARGS.q : 5;

// ------------------------------------------------------------------------------------------------ seeded Math.random
function mulberry32(a) {
  return () => {
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), a | 1);
    t = (t + Math.imul(t ^ (t >>> 7), t | 61)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function hashStr(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}
let rng = mulberry32(1);
let randomCalls = 0;
Math.random = () => { randomCalls++; return rng(); };
const reseed = (key) => { rng = mulberry32(hashStr(String(key))); };

// Counts AudioBufferSourceNode.start(t, offset) calls: the noise / clap sources start at a random offset, which is
// the only randomness of "noise-only" recipes (their variations are near-identical, so they get fewer files).
let offsetStarts = 0;
{
  const start = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function (...a) { if (a.length >= 2) offsetStarts++; return start.apply(this, a); };
}

// ------------------------------------------------------------------------------------------------ the original modules
process.removeAllListeners('warning');   // src/*.js are ES modules in a package without "type": "module"
const sfxUrl = pathToFileURL(path.join(SRC, 'audio/sfx.js')).href;
const { SFX_CUES, synth } = await import(sfxUrl);
// music.js imports synth from './audio.js' (which re-exports sfx.js's); load it as-is from a data: URL with that one
// import pointed at sfx.js and its private songs / Player / plate exported (the recipes are untouched).
let musicSrc = fs.readFileSync(path.join(SRC, 'audio/music.js'), 'utf8');
const IMPORT_LINE = "import { synth } from './audio.js';";
if (!musicSrc.includes(IMPORT_LINE)) throw new Error('music.js import line changed');
musicSrc = musicSrc.replace(IMPORT_LINE, `import { synth } from '${sfxUrl}';`)
  + '\nexport { Player, STATES, TITLE, SELECT, ROUND, MORNING, BOSSA, HULLABALOO, BOSS, CREDITS, engines, plate, clack,'
  + ' LOOKAHEAD as MUSIC_LOOKAHEAD, CLAV_ZOMBIES, SURF_ARP, xylo, slap, hat, HYMN };\n';
const M = await import('data:text/javascript;base64,' + Buffer.from(musicSrc).toString('base64'));

// The cue table exactly as audio.js ends up with it: SFX_CUES (constructor), MUSIC_CUES (createMusic: default bus
// 'music', later registrations win) and wonder.js's _registerCues() (default bus 'sfx', only ids not yet taken).
const CUES = Object.create(null);
const CUE_DEF = Object.create(null);
function registerCues(table, defaults = null) {
  for (const id of Object.keys(table)) {
    if (typeof table[id] !== 'function') continue;
    CUES[id] = table[id];
    CUE_DEF[id] = defaults;
  }
}
registerCues(SFX_CUES);
registerCues(M.MUSIC_CUES, { bus: 'music' });
{
  const src = fs.readFileSync(path.join(SRC, 'game/wonder.js'), 'utf8');
  const m = /\n {2}_registerCues\(\) \{\n([\s\S]*?)\n {2}\}\n/.exec(src);
  if (!m) throw new Error('wonder.js _registerCues() not found');
  const shim = { cues: CUES, registerCues };
  new Function(m[1]).call({ game: { audio: shim } });
}
const WONDER_IDS = Object.keys(CUES).filter((id) => id.startsWith('wonder_'));
const MUSIC_IDS = new Set(Object.keys(M.MUSIC_CUES));

// ------------------------------------------------------------------------------------------------ usage tables
// Everything below is read from the call sites of the web build (grep src/ for audio.play / loop / speaker).

// Pitches (= opts.rate · 2^(opts.detune/1200)) each pitch-reading recipe is played at: numbers and [lo, hi] ranges
// (random rates). Pitch 1 is always rendered; audio.gd picks the nearest rendered pitch and applies the small
// remainder as pitch_scale, so any other rate still works.
const RATE_USE = {
  zmb_hit: [1.35, 1.5, 1.7, 1.8, 0.55, [0.9, 1.15], [1.9, 2.3]],        // forecaster, sock_hopper, zombies 1.5+0.2·bounces
  zmb_groan: [[0.9, 1.15], 1.1, 0.7, 2],                              // tuned_in, zombies, wonder
  zmb_groan_chase: [0.9, [0.95, 1.15]],
  zmb_head_pop: [1.3],
  fc_hum: [[0.95, 1.05]],
  fc_sob: [1.08],
  grenade_bounce: [[1.1, 1.5], 1.6, 0.6, 0.5, 1.9, [2.15, 2.9]],      // economy tubes, wonder, sock_hopper 1.9+0.25·b
  sock_giggle: [[0.9, 1.25]],
  sock_boing: [[0.9, 1.2], 1.3, [1.6, 2.1]],
  boss_hurt: [1.4],
  telly_boing: [1.15, 1.3],
  baron_laugh: [1.07 * 2 ** (40 / 1200), 1.14 * 2 ** (80 / 1200), 1.21 * 2 ** (120 / 1200), 1.28 * 2 ** (160 / 1200),
    1.35 * 2 ** (200 / 1200), 1.45],                                  // easteregg 1+0.07n / 40n cents, telly cameo
  melee_whoosh: [0.6],
  telly_clonk: [0.7, 0.85, 0.94, 1.08],
  telly_nuh_uh: [0.8, 0.85],
  telly_clack: [0.8, [0.7, 0.9], [0.95, 1.05]],
  telly_drum: [1.05],
  telly_giggle: [0.9],
  telly_aww: [0.75],
  telly_ploop: [1.8],
  wonder_yeowch: [[1, 1.3]],
  // audio.js footsteps: rate 0.93–1.07, and the recipes' own ×0.95 on the second foot (o.foot)
  step_carpet: [[0.88, 1.07]], step_tile: [[0.88, 1.07]], step_wood: [[0.88, 1.07]], step_gravel: [[0.88, 1.07]],
  step_metal: [[0.88, 1.07]],
};

// Parameter variants (opts the recipe reads besides pitch). {} = the default call. `rates` overrides RATE_USE.
const HERO_VOICE = { skip: 210, roxy: 260, penny: 240, duke: 120 };
const PU_RHYTHM = { cancelled: [1.1, 0.9], full_reel: [1, 0.85], one_take: [1.15, 0.9], sweeps_week: [1, 1.1, 0.85], gaffer_tape: [1.1, 0.95, 1.05, 0.85], please_stand_by: [1.05, 1, 0.95, 1.12, 0.8] };
const WAH = { replay_ade: [1.1, 0.95, 1.05, 0.85], wobble_up: [0.9, 1.05, 0.8], jump_cut: [1.15, 1, 1.1, 0.9], roller_boogie: [1, 1.2, 0.95, 1.1, 0.85], double_vision: [1.05, 1.15, 0.9] };
const CLAP_BEATS = [0.16, 0.36, 0.56, 0.76, 0.96, 1.16];              // easteregg.js CLAP.beats
const VARIANTS = {
  hurt_grunt: [{}, ...Object.values(HERO_VOICE).map((base) => ({ base }))],                // audio.js _hurt (default 200)
  announcer_wahwah: [{}, ...[...Object.values(PU_RHYTHM), ...Object.values(WAH)].map((rhythm) => ({ rhythm }))],
  boss_voice: [{}, { syllables: 3 }, { syllables: 5 }],
  pu_sweeps_week: [{}, { flip: true }],
  ee_applause_near: [{}, { claps: CLAP_BEATS }, { dur: 3.8, claps: [] }],
  crowd_applause: [{}, { dur: 2.2 }],
  crowd_laugh: [{}, { dur: 2.5 }, { opts: { dur: 0.45 }, rates: [[1.15, 1.4]] }],              // wonder, powerups
  tone_1khz: [{}, { dur: 0.8 }, { dur: 0.9 }],                                            // signon TL.power-TL.bars, uplink
  tele_tick: [{}, { dur: 5 }],                                                             // tiny tele fuse 6 = default, uplink 15-10
  uplink_motor: [{}, { dur: 0.5 }, { dur: 0.9 }],                                          // uplink FULL.swivel+0.1
  ee_alarm_bell: [{ dur: 10 }],
  telly_surf_arp: [{ auto: true }],                                                        // step() notes are parts
};
// Cues heard through a TV at some call sites (screens.speaker / tv:true) although the recipe has no static tv.
const TV_EXTRA = new Set(['zmb_death_static', 'tone_1khz', 'crowd_ooh']);
// Frequently repeated voices get more random variations.
const MANY = new Set(['zmb_groan', 'zmb_groan_chase', 'hurt_grunt', 'boss_voice', 'zmb_clap', 'sock_giggle', 'ee_puppet_giggle',
  'zmb_hit', 'wpn_mp7', 'wpn_m60', 'grenade_bounce', 'board_repair', 'telly_clonk', 'wpn_boom_playback', 'toy_teletype']);
// Cues whose per-note parts the runtime assembles (see PARTS below): no whole-cue files needed besides variants.
const PART_CUES = new Set(['toy_xylophone', 'ee_tracking_tones']);

// audio.loop() users and the loop cut of each: pre = loop start (after the recipe's own fade-in / first cycle),
// L = loop length (whole periods of the free-running oscillators, LFOs and sequencer patterns where possible),
// xf = seam crossfade (short for pitched / event content, longer for noise beds).
const LOOPS = {
  telly_hum: { pre: 0.5, L: 8.1, xf: 0.25 },             // 60/120 Hz, LFO 0.37 Hz (3 cycles)
  amb_lobby: { pre: 2, L: 16, xf: 0.05 },               // 8 s bossa pattern ×2
  amb_newsroom: { pre: 2, L: 30, xf: 0.3 },
  amb_green_room: { pre: 2, L: 30, xf: 0.3 },
  amb_studio_a: { pre: 2.5, L: 42, xf: 0.5 },           // phone pattern lcm(12,14) half-seconds
  amb_studio_b: { pre: 2, L: 44, xf: 0.3 },             // music-box tune 11 s ×4
  amb_master_control: { pre: 2, L: 30, xf: 0.3 },
  amb_yard: { pre: 2.5, L: 60, xf: 0.5 },               // 120/121.5/240 Hz: multiple of 2/3 s
  amb_hum: { pre: 1.2, L: 2, xf: 0.1 },
  pu_idle: { pre: 0.8, L: 20, xf: 0.1 },                // 523.25/784/1318.5 Hz, LFO 0.8 Hz
  bs_roll: { pre: 0.4, L: 4, xf: 0.1 },
  skate_roll: { pre: 0.28, L: 5.6, xf: 0.1 },
  wpn_boom_record: { pre: 3.6, L: 4.5, xf: 0.03 },      // after the 3 s hiss ramp, 10 groans (0.45 s grid)
  ee_storm_loop: { pre: 1.2, L: 20, xf: 0.3 },
  dish_crank: { pre: 0.266, L: 6.65, xf: 0.02 },        // 50 clicks of 0.133 s, 80 Hz saw
  uplink_motor: { pre: 1, L: 2, xf: 0.02 },
  boss_static_ball: { pre: 0.1, L: 2, xf: 0.05 },
  heartbeat: { pre: 0, L: 0.86, xf: 0, retrig: true },  // one-shot chained every o.period (0.86 s)
  sting_signoff_hymn: { retrig: true, tv: true },         // easteregg.js: the hymn looping from the VTR deck (tv)
  tele_cartoon: { pre: 3.2, L: 3.2, xf: 0.01 },         // 2 bars at 150 BPM
};

// Music states (music.js STATES) and how each is cut: cycle = bars of the song's pattern; stems = layer groups
// rendered as separate aligned files (audio.gd crossfades them like music.js's setLayer / setIntensity).
const STATE_SONGS = {
  title: { song: 'TITLE', bars: 8 },
  'select:skip': { song: ['SELECT', 'skip'], bars: 2 },
  'select:roxy': { song: ['SELECT', 'roxy'], bars: 2 },
  'select:penny': { song: ['SELECT', 'penny'], bars: 2 },
  'select:duke': { song: ['SELECT', 'duke'], bars: 2 },
  round: { song: 'ROUND', bars: 4, stems: { base: ['main', 'hats'], clav: ['clav'] } },
  intermission: { song: 'BOSSA', bars: 8 },
  hullabaloo: { song: 'HULLABALOO', bars: 8 },
  boss: { song: 'BOSS', bars: 4, boss: true },
  credits: { song: 'CREDITS', bars: 8 },
  morning: { song: 'MORNING', bars: 4, stems: { base: ['main', 'hats', 'keys'], clav: ['clav'] } },
};
const MUSIC_INTRO = 3.0;     // s of intro before the loop starts (longest tails: plate 1.7 s, strings/crash ~2 s)

// ------------------------------------------------------------------------------------------------ render helpers
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
function softCurve(drive) {   // sfx.js softCurve (the TV chain's shaper)
  const c = new Float32Array(1024), norm = Math.tanh(drive);
  for (let i = 0; i < 1024; i++) { const x = (i / 1023) * 2 - 1; c[i] = Math.tanh(drive * x) / norm; }
  return c;
}
const TV_CURVE = softCurve(1.8);

// Caches that the original code fills with Math.random on first use (noise buffers, the clap texture, the music
// plate) are filled once here with fixed seeds, so every later render is independent of render order.
let PLATE = null;
{
  const ctx = new OfflineAudioContext({ numberOfChannels: 2, length: 128, sampleRate: SR });
  const g = ctx.createGain();
  g.connect(ctx.destination);
  for (const c of ['white', 'pink', 'brown']) { reseed('noise:' + c); synth.noiseBuffer(ctx, c); }
  reseed('claps');
  synth.applause(g, 0, { dur: 0.1 });
  reseed('plate');
  PLATE = M.plate(ctx);
}

function newCtx(seconds) {
  return new OfflineAudioContext({ numberOfChannels: 2, length: Math.max(128, Math.ceil(seconds * SR)), sampleRate: SR });
}

// music.js's engine hooks for cues: wet() taps the voice into the plate send, sting_gameover asks for tapeStop.
function attachEngine(ctx, dest = ctx.destination) {
  const verb = ctx.createConvolver();
  verb.buffer = PLATE;
  verb.connect(dest);
  const stingSend = synth.gain(verb, 0.14);
  M.engines.set(ctx, { tapeStop() {}, stingSend });
  return verb;
}

// Voice input (audio.js _chain up to the panner): gain (TV voices ×1.35) → [TV speaker: HP 300 / peak 2.2 k +3 dB /
// LP 4 k / soft clip 1.8] → destination.
function voiceInput(ctx, tv) {
  const input = ctx.createGain();
  input.gain.value = tv ? 1.35 : 1;
  let tail = input;
  const link = (n) => { tail.connect(n); tail = n; return n; };
  if (tv) {
    const hp = link(ctx.createBiquadFilter()); hp.type = 'highpass'; hp.frequency.value = 300; hp.Q.value = 0.7;
    const pk = link(ctx.createBiquadFilter()); pk.type = 'peaking'; pk.frequency.value = 2200; pk.Q.value = 1; pk.gain.value = 3;
    const lp = link(ctx.createBiquadFilter()); lp.type = 'lowpass'; lp.frequency.value = 4000; lp.Q.value = 0.9;
    const sh = link(ctx.createWaveShaper()); sh.curve = TV_CURVE;
  }
  tail.connect(ctx.destination);
  return input;
}

function drive(handle, from, until, step = 0.025) {
  if (!handle || typeof handle.update !== 'function') return;
  for (let vt = from; vt <= until + 1e-9; vt += step) handle.update(vt);
}

const cueProps = (id) => {
  const r = CUES[id], d = CUE_DEF[id];
  return {
    bus: r.bus || (d && d.bus) || 'sfx', tv: !!r.tv, zombie: !!r.zombie, range: r.range ?? null, ref: r.ref ?? null,
    wet: r.wet ?? null, limit: r.limit ?? 10, gap: r.gap ?? 0.03, loopable: !!r.loopable,
  };
};

// Calls the recipe of `id` once in a throw-away context: which opts it reads, what it returns, how random it is.
function probe(id, opts = {}) {
  const ctx = newCtx(0.01);
  attachEngine(ctx);
  const input = voiceInput(ctx, false);
  const reads = new Set();
  const ro = new Proxy({ ...opts, t: T0, ac: ctx, loop: false, pitch: 1 }, {
    get(t, k) { if (typeof k === 'string') reads.add(k); return t[k]; },
  });
  reseed('probe:' + id);
  const r0 = randomCalls, s0 = offsetStarts;
  let ret;
  try { ret = CUES[id](synth, input, ro); } catch (e) { return { error: e }; }
  const rnd = randomCalls - r0, offs = offsetStarts - s0;
  const handle = ret && typeof ret === 'object' ? ret : null;
  const end = typeof ret === 'number' ? ret : handle ? (handle.end ?? Infinity) : T0 + 4;
  for (const k of ['t', 'ac', 'loop']) reads.delete(k);
  return { reads, handle: !!handle, end, random: rnd > offs ? 'random' : rnd > 0 ? 'noise' : 'none' };
}

// One-shot render of `id` with `opts` (+ pitch, tv). Returns { chans, end } (end relative to the start).
async function renderShot(id, opts, { pitch = 1, tv = false, seed }) {
  const once = (ctx) => {
    const input = voiceInput(ctx, tv);
    attachEngine(ctx);
    reseed(seed);
    const ro = { ...opts, t: T0, ac: ctx, loop: false, pitch };
    return CUES[id](synth, input, ro);
  };
  let r = once(newCtx(0.01));   // probe the end time with the same seed
  let end = typeof r === 'number' ? r : r && typeof r === 'object' ? (r.end ?? Infinity) : T0 + 4;
  if (!Number.isFinite(end)) throw new Error(`${id}: endless under play()`);
  const len = end - T0 + DISPOSE;
  const ctx = newCtx(len);
  r = once(ctx);
  if (r && typeof r === 'object') drive(r, T0, T0 + len);
  const buf = await ctx.startRendering();
  return { chans: [buf.getChannelData(0), buf.getChannelData(1)], end: end - T0 };
}

// audio.loop() render: the recipe in loop mode for pre + L + xf seconds (endless handles driven like audio.js's
// 25 ms ticker; one-shot recipes retriggered back to back like Voice.update), then [intro | loop] with the seam
// crossfaded (the loop's head fades from the render's continuation into itself).
async function renderLoop(id, cfg, { tv, seed, opts = {} }) {
  let { pre = 0, L, xf = 0 } = cfg;
  const build = (ctx, total) => {
    const input = voiceInput(ctx, tv);
    attachEngine(ctx);
    reseed(seed);
    const ro = { ...opts, t: T0, ac: ctx, loop: true, pitch: 1 };
    const r = CUES[id](synth, input, ro);
    if (r && typeof r === 'object') { drive(r, T0, total); return { first: null }; }
    // Voice.update retrigger
    let end = typeof r === 'number' && r > ro.t ? r : ro.t + 1;
    const first = end - T0;
    for (let now = T0; now < total; now += 0.025) {
      if (now + LOOKAHEAD >= end) {
        ro.t = Math.max(end, now + START_LAG);
        const r2 = CUES[id](synth, input, ro);
        end = typeof r2 === 'number' && r2 > ro.t ? r2 : ro.t + 1;
      }
    }
    return { first };
  };
  if (cfg.retrig && L == null) {
    // one period = the recipe's end (deterministic one-shots: the loop is exactly one period)
    const probeCtx = newCtx(0.01);
    const { first } = build(probeCtx, 0);
    L = first;
    pre = 0;
  }
  const total = pre + L + xf + 0.05;
  const ctx = newCtx(total);
  build(ctx, total);
  const buf = await ctx.startRendering();
  const src = [buf.getChannelData(0), buf.getChannelData(1)];
  const nPre = Math.round(pre * SR), nL = Math.round(L * SR), nX = Math.round(xf * SR);
  const chans = src.map((d) => {
    const o = new Float32Array(nPre + nL);
    o.set(d.subarray(0, nPre + nL));
    for (let i = 0; i < nX; i++) {       // equal-gain seam: continuation (d[pre+L+i]) → head (d[pre+i])
      const k = (i + 0.5) / nX;
      o[nPre + i] = d[nPre + i] * k + d[nPre + nL + i] * (1 - k);
    }
    return o;
  });
  return { chans, start: nPre / SR, end: (nPre + nL) / SR };
}

// A music.js song rendered by its own Player, all layers committed (so every stem shares one random performance)
// and only `solo` layers audible; dry + the song's plate send, like createMusic's start().
async function renderSong(song, { total, vars = {}, solo = null, seed }) {
  const ctx = newCtx(total);
  const verb = ctx.createConvolver();
  verb.buffer = PLATE;
  verb.connect(ctx.destination);
  reseed(seed);
  const p = new M.Player(ctx, song, ctx.destination, { t0: T0, vars: { intensity: 1, ...vars }, level: song.gain ?? 0.5 });
  p.out.connect(synth.gain(verb, song.verb ?? 0.1));
  for (const name of Object.keys(p.L)) {
    const L = p.L[name];
    L.on = true;
    L.offAt = Infinity;
    L.node.gain.value = !solo || solo.includes(name) ? L.level : 0;
  }
  p.pump(T0 + total + 1);
  const buf = await ctx.startRendering();
  return { chans: [buf.getChannelData(0), buf.getChannelData(1)], barDur: p.barDur, sd: p.sd };
}

// ------------------------------------------------------------------------------------------------ output
let encoder = null;
const written = [];
let totalBytes = 0;

function finish(chans, { trim = true } = {}) {
  let n = chans[0].length;
  if (trim) {
    let last = 0;
    for (const d of chans) for (let i = n - 1; i > last; i--) if (Math.abs(d[i]) > 3e-5) { last = i; break; }
    n = Math.min(n, last + 1 + Math.round(0.005 * SR));
  }
  const out = chans.map((d) => d.slice(0, Math.max(n, 32)));
  if (trim) {   // 3 ms fade at the cut (audio.js disposes the voice there)
    const f = Math.min(out[0].length, Math.round(0.003 * SR));
    for (const d of out) for (let i = 0; i < f; i++) d[d.length - 1 - i] *= i / f;
  }
  let mono = true, peak = 0;
  for (let i = 0; i < out[0].length; i++) {
    if (Math.abs(out[0][i] - out[1][i]) > 1e-5) mono = false;
    peak = Math.max(peak, Math.abs(out[0][i]), Math.abs(out[1][i]));
  }
  let k = 1;
  if (peak > 0.985) {       // keep the encoder input in [-1, 1]; audio.gd multiplies back by k
    k = peak / 0.985;
    for (const d of out) for (let i = 0; i < d.length; i++) d[i] /= k;
  }
  return { chans: mono ? [out[0]] : out, k, peak, len: out[0].length / SR };
}

function wavBytes(chans) {
  const n = chans[0].length, nc = chans.length, b = Buffer.alloc(44 + n * nc * 2);
  b.write('RIFF', 0); b.writeUInt32LE(36 + n * nc * 2, 4); b.write('WAVE', 8); b.write('fmt ', 12);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(nc, 22); b.writeUInt32LE(SR, 24);
  b.writeUInt32LE(SR * nc * 2, 28); b.writeUInt16LE(nc * 2, 32); b.writeUInt16LE(16, 34); b.write('data', 36);
  b.writeUInt32LE(n * nc * 2, 40);
  for (let i = 0, o = 44; i < n; i++) for (let c = 0; c < nc; c++, o += 2) b.writeInt16LE(Math.round(clamp(chans[c][i], -1, 1) * 32767), o);
  return b;
}

function oggBytes(chans, quality) {
  encoder.configure({ sampleRate: SR, channels: chans.length, vbrQuality: quality });
  const parts = [];
  const CH = 1 << 16;
  for (let i = 0; i < chans[0].length; i += CH) {
    const d = encoder.encode(chans.map((c) => c.subarray(i, Math.min(i + CH, c.length))));
    if (d.length) parts.push(Buffer.from(d));
  }
  const f = encoder.finalize();
  if (f.length) parts.push(Buffer.from(f));
  return Buffer.concat(parts);
}

function writeAudio(rel, fin, quality) {
  const file = path.join(OUT, rel);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const bytes = WAV ? wavBytes(fin.chans) : oggBytes(fin.chans, quality);
  fs.writeFileSync(file, bytes);
  totalBytes += bytes.length;
  written.push(rel);
  return rel;
}

// Small concurrency pool: graph building (seeded, synchronous) happens in order, the renders themselves run in
// parallel inside node-web-audio-api.
async function pool(tasks, n = JOBS) {
  const res = new Array(tasks.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(n, tasks.length) }, async () => {
    while (next < tasks.length) { const i = next++; res[i] = await tasks[i](); }
  }));
  return res;
}

// ------------------------------------------------------------------------------------------------ planning
const r3 = (x) => Math.round(x * 1000) / 1000;
function pitchBuckets(list) {
  const out = [1];
  const add = (p) => { if (!out.some((q) => Math.abs(q / p - 1) < 0.02)) out.push(r3(p)); };
  for (const u of list || []) {
    if (Array.isArray(u)) {
      const [lo, hi] = u, n = Math.max(1, Math.ceil(Math.log(hi / lo) / Math.log(1.08)));
      for (let k = 0; k < n; k++) add(lo * Math.pow(hi / lo, (k + 0.5) / n));
    } else add(u);
  }
  return out.sort((a, b) => a - b);
}
// Canonical variant key (audio.gd builds the same from the play opts): "k=v;k=v" of the params in PARAMS order.
const PARAMS = ['upgraded', 'flip', 'base', 'rhythm', 'syllables', 'claps', 'dur', 'auto'];
const fmtNum = (x) => String(r3(+x));
function variantKey(opts) {
  const parts = [];
  for (const k of PARAMS) {
    if (!(k in opts) || opts[k] == null || opts[k] === false) continue;
    const v = opts[k];
    parts.push(k + '=' + (Array.isArray(v) ? (v.length ? v.map(fmtNum).join(',') : '[]') : v === true ? '1' : fmtNum(v)));
  }
  return parts.join(';');
}

function variationCount(id, info, pitch) {
  if (QUICK || MUSIC_IDS.has(id) || info.random === 'none') return 1;
  if (info.random === 'noise') return pitch === 1 ? 2 : 1;
  const base = MANY.has(id) ? 6 : 4;
  return pitch === 1 ? base : Math.min(3, base);
}

// ------------------------------------------------------------------------------------------------ main
encoder = WAV ? null : await createOggEncoder();
fs.mkdirSync(OUT, { recursive: true });
const index = { version: 1, sampleRate: SR, format: EXT, generator: 'tools/audio/render.mjs', cues: {}, parts: {}, music: null };
const prevIndexFile = path.join(OUT, 'index.json');
if (ONLY && fs.existsSync(prevIndexFile)) Object.assign(index, JSON.parse(fs.readFileSync(prevIndexFile, 'utf8')));

const t0 = performance.now();
const ids = Object.keys(CUES).filter((id) => !ONLY || ONLY.has(id));
const failures = [];

if (!ARGS['no-sfx']) {
  for (const id of ids) {
    const props = cueProps(id);
    const info = probe(id);
    if (info.error) { failures.push(id + ': ' + info.error.message); console.warn('[audio] probe failed', id, info.error); continue; }
    const pitchy = info.reads.has('pitch');
    const entry = {
      ...props, music: MUSIC_IDS.has(id), wonder: WONDER_IDS.includes(id), pitch: pitchy,
      reads: [...info.reads].sort(), inherent: info.handle && !Number.isFinite(info.end),
      params: PARAMS.filter((k) => info.reads.has(k)), variants: [], loop: null,
    };
    index.cues[id] = entry;
    const tvs = props.tv ? [true] : TV_EXTRA.has(id) ? [false, true] : [false];
    const vlist = (VARIANTS[id] || [{}]).map((v) => (v.opts ? v : { opts: v }));
    if (info.reads.has('upgraded')) vlist.push({ opts: { upgraded: true } });
    const tasks = [];
    if (!entry.inherent && !PART_CUES.has(id)) {
      vlist.forEach((v, vi) => {
        for (const tv of tvs) {
          const buckets = pitchy ? pitchBuckets(v.rates || RATE_USE[id]) : [1];
          const ve = { k: variantKey(v.opts), o: v.opts, tv, sets: [] };
          entry.variants.push(ve);
          for (const p of buckets) {
            const set = { p, f: [] };
            ve.sets.push(set);
            const nv = variationCount(id, info, p);
            for (let n = 0; n < nv; n++) {
              const rel = `sfx/${id}/v${vi}${tv ? 't' : ''}_p${Math.round(p * 100)}_${n}.${EXT}`;
              const seed = `${id}|${ve.k}|${tv}|${p}|${n}`;
              tasks.push(async () => {
                const r = await renderShot(id, v.opts, { pitch: p, tv, seed });
                const fin = finish(r.chans);
                writeAudio(rel, fin, Q_SFX);
                set.f.push({ f: rel, e: r3(r.end), l: r3(fin.len), k: fin.k === 1 ? undefined : r3(fin.k), ch: fin.chans.length });
              });
            }
          }
        }
      });
    }
    // loops
    const lc = LOOPS[id];
    if (lc) {
      const tv = lc.tv ?? props.tv;
      tasks.push(async () => {
        const r = await renderLoop(id, lc, { tv, seed: id + '|loop' });
        const fin = finish(r.chans, { trim: false });
        const rel = writeAudio(`loops/${id}${tv ? '_tv' : ''}.${EXT}`, fin, Q_SFX);
        entry.loop = { f: rel, s: r3(r.start), e: r3(r.end), tv, k: fin.k === 1 ? undefined : r3(fin.k) };
      });
    }
    await pool(tasks);
    for (const ve of entry.variants) for (const s of ve.sets) s.f.sort((a, b) => a.f.localeCompare(b.f));
    process.stdout.write(`\r[audio] ${Object.keys(index.cues).length}/${ids.length} ${id}                    `);
  }
  process.stdout.write('\n');
}

// ------------------------------------------------------------------------------------------------ parts
if (!ARGS['no-sfx'] && (!ONLY || ONLY.has('telly_surf_arp') || ONLY.has('toy_xylophone') || ONLY.has('ee_tracking_tones'))) {
  const tasks = [];
  // telly_surf_arp step(): one slap-bass note (m = 52 + SURF_ARP[i%4] + ⌊i/4⌋) + a hat tick per detent, from Telly's
  // TV speaker (the cue is WORLD_TV). 40 detents are covered; audio.gd pitch-shifts beyond.
  const arp = { f: {}, tv: true };
  index.parts.telly_surf_arp = arp;
  const notes = new Set();
  for (let i = 0; i < 40; i++) notes.add(52 + M.SURF_ARP[i % 4] + Math.floor(i / 4));
  for (const m of notes) {
    tasks.push(async () => {
      const ctx = newCtx(0.22 + DISPOSE + 0.1);
      const input = voiceInput(ctx, true);
      reseed('arp' + m);
      M.slap(input, T0, { f: 440 * Math.pow(2, (m - 69) / 12), dur: 0.22, peak: 0.4, bright: 1.3 });
      M.hat(input, T0, { peak: 0.08 });
      const buf = await ctx.startRendering();
      const fin = finish([buf.getChannelData(0), buf.getChannelData(1)]);
      arp.f[m] = writeAudio(`parts/telly_surf_arp/n${m}.${EXT}`, fin, Q_SFX);
    });
  }
  // toy_xylophone (music.js): xylo mallet notes at peak 0.34 (the third note of a tune is 0.4: audio.gd scales).
  // Pool = the cue's pentatonic C5 D5 E5 G5 A5 C6 + studio_b.js's MIDI bars 72..84.
  const xy = { f: {}, peak: 0.34, step: 0.18, pool: [72, 74, 76, 79, 81, 84] };
  index.parts.toy_xylophone = xy;
  for (const m of [72, 74, 76, 77, 79, 81, 83, 84]) {
    tasks.push(async () => {
      const ctx = newCtx(0.45 + DISPOSE + 0.1);
      const input = voiceInput(ctx, false);
      reseed('xylo' + m);
      M.xylo(input, T0, { f: 440 * Math.pow(2, (m - 69) / 12), peak: 0.34 });
      const buf = await ctx.startRendering();
      const fin = finish([buf.getChannelData(0), buf.getChannelData(1)]);
      xy.f[m] = writeAudio(`parts/toy_xylophone/n${m}.${EXT}`, fin, Q_SFX);
    });
  }
  // ee_tracking_tones: 0.18-peak sines, 440 Hz reference + 440 + 2.5·d Hz (audio.gd pitch_scale); 1 s = 440 cycles.
  tasks.push(async () => {
    const ctx = newCtx(1);
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.frequency.value = 440; g.gain.value = 0.18;
    o.connect(g).connect(ctx.destination);
    o.start(0);
    const buf = await ctx.startRendering();
    const fin = finish([buf.getChannelData(0), buf.getChannelData(1)], { trim: false });
    index.parts.ee_tracking_tones = { f: writeAudio(`parts/ee_tracking_tones/sine440.${EXT}`, fin, Q_SFX), hz: 440, fade: 0.15 };
  });
  await pool(tasks);
}

// ------------------------------------------------------------------------------------------------ music
if (!ARGS['no-music'] && (!ONLY || ONLY.has('music'))) {
  const music = { states: {}, clack: null, lookahead: M.MUSIC_LOOKAHEAD, clavZombies: M.CLAV_ZOMBIES };
  for (const [key, def] of Object.entries(M.STATES)) music.states[key] = { fade: def.fade, delay: def.delay ?? 0.03, song: !!def.song || key === 'select' };
  const tasks = [];
  for (const [state, plan] of Object.entries(STATE_SONGS)) {
    const song = Array.isArray(plan.song) ? M[plan.song[0]][plan.song[1]] : M[plan.song];
    const barDur = (60 / song.bpm / 4) * 16, cycle = plan.bars * barDur;
    const introBars = Math.max(1, Math.ceil(MUSIC_INTRO / barDur));
    const pre = introBars * barDur - 0.01, xf = 0.02;
    const total = pre + cycle + xf + 0.05;
    const st = { bpm: song.bpm, barDur: r3(barDur), beatDur: r3(barDur / 4), bars: plan.bars, gain: song.gain ?? 0.5, stems: {} };
    music.states[state] = { ...(music.states[state.split(':')[0]] || {}), ...st };
    const cut = (chans) => {
      const nPre = Math.round(pre * SR), nL = Math.round(cycle * SR), nX = Math.round(xf * SR);
      return chans.map((d) => {
        const o = new Float32Array(nPre + nL);
        o.set(d.subarray(0, nPre + nL));
        for (let i = 0; i < nX; i++) { const k = (i + 0.5) / nX; o[nPre + i] = d[nPre + i] * k + d[nPre + nL + i] * (1 - k); }
        return o;
      });
    };
    const stemJob = (stem, opts, fileKey) => tasks.push(async () => {
      const r = await renderSong(song, { total, ...opts, seed: 'music|' + state + '|' + (opts.seedKey || '') });
      const fin = finish(cut(r.chans), { trim: false });
      const rel = writeAudio(`music/${fileKey}.${EXT}`, fin, Q_MUSIC);
      music.states[state].stems[stem] = { f: rel, s: r3(Math.round(pre * SR) / SR), e: r3(fin.len), k: fin.k === 1 ? undefined : r3(fin.k) };
    });
    const fk = state.replace(':', '_');
    if (plan.boss) {
      // base (main + hats + stab) per phase: the kick / snare / hat / stab patterns and the lift change with it;
      // p2 (theremin + shaker) and p3 (strings, horn stabs, crashes, fills) do not depend on the phase.
      for (const n of [1, 2, 3]) stemJob('base' + n, { vars: { intensity: n }, solo: ['main', 'hats', 'stab'], seedKey: 'n' + n }, `${fk}_base${n}`);
      stemJob('p2', { vars: { intensity: 3 }, solo: ['p2'], seedKey: 'n3' }, `${fk}_p2`);
      stemJob('p3', { vars: { intensity: 3 }, solo: ['p3'], seedKey: 'n3' }, `${fk}_p3`);
    } else if (plan.stems) {
      for (const [stem, layers] of Object.entries(plan.stems)) stemJob(stem, { solo: layers }, `${fk}_${stem}`);
    } else stemJob('all', {}, fk);
  }
  // character select's channel clack (setState('select…') plays it on the music bus)
  tasks.push(async () => {
    const ctx = newCtx(0.1 + DISPOSE + 0.1);
    reseed('clack');
    const g = ctx.createGain();
    g.connect(ctx.destination);
    M.clack(g, T0, { peak: 0.3 });
    const buf = await ctx.startRendering();
    const fin = finish([buf.getChannelData(0), buf.getChannelData(1)]);
    music.clack = { f: writeAudio(`music/select_clack.${EXT}`, fin, Q_SFX), delay: 0.005 };
  });
  await pool(tasks, Math.min(JOBS, 4));
  index.music = music;
}

// ------------------------------------------------------------------------------------------------ index
index.stats = { files: written.length, bytes: totalBytes, seconds: r3((performance.now() - t0) / 1000) };
fs.writeFileSync(prevIndexFile, JSON.stringify(index, (k, v) => (v === undefined ? undefined : v), 1));
let dirBytes = 0;
const walk = (d) => { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); if (e.isDirectory()) walk(p); else if (!e.name.endsWith('.import')) dirBytes += fs.statSync(p).size; } };
walk(OUT);
console.log(`[audio] ${written.length} files, ${(totalBytes / 1048576).toFixed(1)} MB written this run, `
  + `${(dirBytes / 1048576).toFixed(1)} MB in godot/assets/audio, ${index.stats.seconds} s`);
if (failures.length) { console.warn('[audio] failures:\n  ' + failures.join('\n  ')); process.exitCode = 1; }
