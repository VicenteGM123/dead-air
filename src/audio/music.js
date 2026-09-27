// DEAD AIR — music.js
// The music of WZTV Channel 13 (GDD §15): a lookahead step sequencer, every music state of
// audio.music(stateId) with crossfades and adaptive layers, and MUSIC_CUES — the recipe of every musical
// cue: stings, the station-ID bells and the EE chime bars, the Sign-Off hymn and its music-box phrases,
// Telly's show jingles and spin arpeggio, the sponsor teasers/jingles, the Uplink cues, the bossa bed,
// the kazoo trio, the Tiny Tele cartoon loop, the van radio and the toy xylophone.
//
// createMusic(audio) -> { setState(id), setIntensity(n), update(dt), stop(), tapeStop(t, dur), beat() }
//   Called by audio.js once the AudioContext exists; registers MUSIC_CUES (music bus by default, diegetic
//   cues carry static `bus`/`tv`/`wet` props) and is ticked by audio.js every 25 ms.
//   States: title, select, ambient, round, intermission, hullabaloo, boss, credits, morning, silence.
//     'select:<heroId>' picks that hero's 2-bar show intro (plain 'select' keeps the last hero).
//     'boss:<n>' (or setIntensity(n), n = boss phase 1..3) raises the boss arrangement without a restart.
//     round/morning fade a wah-clav layer in while more than 16 zombies are alive (audio.game.zombies).
//     ambient fades the music out (ambience and hum belong to audio.js); silence cuts it (dead air).
//   tapeStop(t, dur=1.2): pitch-glides whatever plays down to a stop (sting_gameover calls it).
//   beat(): { bpm, beat } of the current state (fractional beats since it started) or null; `state` is the
//   current state id.
//
// Sequencer: a song is data plus bar(player, barIndex, vars). A Player writes one bar of note events at
// a time into a sorted queue and, on every tick, commits the events that start before now + LOOKAHEAD
// to the audio graph, so layer switches, intensity changes and stops land within ~0.15 s.
//
// Cue handles: telly_surf_arp returns { step() } — one funk-bass note per dial detent, a semitone higher
// every 4 detents ({ auto: true } plays the standard 20-detent spin by itself). The sequenced cues
// (sting_sign_on_theme, tele_cartoon, toy_radio, pu_bossa_bed) return { update, stop, end } handles that
// audio.js drives. toy_xylophone plays opts.notes (MIDI numbers) or a random 3-note tune.
//
// Instruments come from the shared `synth` toolkit; the few a score needs that it lacks are built below
// from its primitives. The station bell is local on purpose: synth.fmBell's modulation index decays over
// half the note, which smears pitch in a 0.2 s motif, so the round-start motif and the four chime bars
// share one bell whose index falls in ~0.1 s — G4-C5-E5-G5 reads instantly, identically, in both places.

import { synth } from './audio.js';

const LOOKAHEAD = 0.15;          // seconds of note events committed ahead of the audio clock
const CLAV_ZOMBIES = 16;         // round/morning: the clav layer joins above this many living zombies
const VEL = { X: 1, x: 0.75, o: 0.4, '-': 0.22 };
const NOTE_IDX = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
const engines = new WeakMap();   // AudioContext -> { tapeStop, stingSend } for cues that reach the engine

// ------------------------------------------------------------------------------------------------
// Notation
// ------------------------------------------------------------------------------------------------

const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);

function nm(name) {
  const m = /^([A-G])([#b]?)(-?\d)$/.exec(name);
  return 12 * (+m[3] + 1) + NOTE_IDX[m[1]] + (m[2] === '#' ? 1 : m[2] === 'b' ? -1 : 0);
}
const ch = (s) => s.trim().split(/\s+/).map(nm);

// 'E2@0:1.5! G2@8:1~' -> [[midi, step, lengthInSteps, velocity]]; '!' accents, '~' ghosts.
function seq(s) {
  return s.trim().split(/\s+/).map((tok) => {
    const m = /^([A-G][#b]?-?\d)@([\d.]+):([\d.]+)([!~]?)$/.exec(tok);
    return [nm(m[1]), +m[2], +m[3], m[4] === '!' ? 1 : m[4] === '~' ? 0.45 : 0.78];
  });
}

const horizon = () => (typeof document !== 'undefined' && document.hidden ? 1.2 : LOOKAHEAD);

function holdAt(param, t) {
  if (param.cancelAndHoldAtTime) param.cancelAndHoldAtTime(t);
  else { param.cancelScheduledValues(t); param.setValueAtTime(param.value, t); }
}

// ------------------------------------------------------------------------------------------------
// Instruments: every builder is synth-style (dest, t, { f, dur, peak, ... }) -> end time
// ------------------------------------------------------------------------------------------------

const kick = (d, t, p) => synth.kick(d, t, p);
const snare = (d, t, p) => synth.snare(d, t, p);
const hat = (d, t, p) => synth.hat(d, t, p);
const hatOpen = (d, t, p) => synth.hat(d, t, { ...p, open: true });
const clap = (d, t, p) => synth.clap(d, t, p);
const rim = (d, t, p) => synth.rim(d, t, p);
const block = (d, t, p) => synth.woodblock(d, t, p);
const slap = (d, t, p) => synth.slapBass(d, t, p);
const clav = (d, t, p) => synth.clav(d, t, p);
const brass = (d, t, p) => synth.brass(d, t, p);
const strings = (d, t, p) => synth.strings(d, t, p);
const vibes = (d, t, p) => synth.vibraphone(d, t, p);
const epiano = (d, t, p) => synth.epiano(d, t, p);
const mbox = (d, t, p) => synth.musicBox(d, t, p);
const kazoo = (d, t, p) => synth.kazoo(d, t, p);
const theremin = (d, t, p) => synth.theremin(d, t, p);
const whistle = (d, t, p) => synth.slideWhistle(d, t, p);
const organDrive = (d, t, p) => synth.organ(synth.shaper(synth.filter(d, 'lowpass', 3200, 0.7), 2.2), t, p);
const shaker = (d, t, p) => synth.noise(d, t, { type: 'bandpass', f: 6500, q: 1.1, a: 0.01, dur: 0.07, peak: p.peak, curve: 'fast' });
const swoosh = (d, t, p) => synth.noise(d, t, { type: 'bandpass', f: 350, f1: 5500, q: 1.3, a: p.dur - 0.02, dur: p.dur, peak: p.peak, curve: 'lin' });
const swell = (d, t, p) => synth.noise(d, t, { type: 'highpass', f: 2000, f1: 7500, q: 0.5, a: p.dur - 0.02, dur: p.dur, peak: p.peak, curve: 'lin' });
const brush = (d, t, p) => synth.noise(d, t, { type: 'bandpass', f: 4200, q: 0.8, a: 0.03, dur: 0.16, peak: p.peak, curve: 'fast' });
const sqLead = (d, t, p) => synth.tone(synth.filter(d, 'lowpass', 2800, 0.7), t, {
  type: 'square', f: p.f, dur: Math.max(0.06, p.dur), peak: p.peak, a: 0.004, hold: p.dur * 0.55, curve: 'fast', vib: p.vib, vibRate: 6,
});
const sqBass = (d, t, p) => synth.tone(synth.filter(d, 'lowpass', 1000, 1), t, {
  type: 'square', f: p.f, dur: Math.max(0.08, p.dur), peak: p.peak, a: 0.003, hold: p.dur * 0.4, curve: 'fast',
});

// The WZTV station bell: FM tubular bell (modulator ratio 3.5, index 2.2 -> 0.1 in ~0.1 s) over its
// fundamental and a faint octave, 4 s ring. Shared by the round-start motif, the Uplink fanfare and
// the chime bars.
function stationBell(dest, t, p) {
  const ac = dest.context, f = p.f, pk = p.peak ?? 0.3, dur = 4;
  const g = synth.gain(dest, 0), mg = ac.createGain();
  const car = ac.createOscillator(), mod = ac.createOscillator();
  car.frequency.value = f;
  mod.frequency.value = f * 3.5;
  mg.gain.setValueAtTime(f * 3.5 * 2.2, t);
  mg.gain.setTargetAtTime(f * 3.5 * 0.1, t + 0.003, 0.08);
  mod.connect(mg); mg.connect(car.frequency); car.connect(g);
  const end = synth.env(g.gain, t, { a: 0.002, dur, peak: pk * 0.5, curve: 'exp' });
  car.start(t); mod.start(t); car.stop(end + 0.02); mod.stop(end + 0.02);
  synth.tone(dest, t, { f, dur: dur * 0.9, peak: pk * 0.5, a: 0.003 });
  synth.tone(dest, t, { f: f * 2, dur: dur * 0.4, peak: pk * 0.1, a: 0.002 });
  synth.tone(dest, t, { f: f * 5.43, dur: 0.1, peak: pk * 0.07, a: 0.0005, curve: 'fast' });
  return end;
}

function upright(dest, t, p) {
  const lp = synth.filter(dest, 'lowpass', 900, 0.8), dur = Math.max(0.12, p.dur);
  synth.tone(lp, t, { type: 'triangle', f: p.f * 1.03, f1: p.f, glide: 0.04, dur, peak: p.peak, a: 0.004, hold: dur * 0.2, curve: 'fast' });
  synth.noise(dest, t, { lp: 350, dur: 0.05, peak: p.peak * 0.25, curve: 'fast' });
  return synth.tone(lp, t, { f: p.f, dur, peak: p.peak * 0.8, a: 0.004, hold: dur * 0.2, curve: 'fast' });
}

function fuzzBass(dest, t, p) {
  const sh = synth.shaper(synth.filter(synth.gain(dest, p.peak), 'lowpass', 1400, 1.2), 5);
  const dur = Math.max(0.1, p.dur), hold = dur * 0.6;
  synth.tone(sh, t, { type: 'sawtooth', f: p.f, dur, peak: 0.7, a: 0.004, hold, curve: 'fast' });
  return synth.tone(sh, t, { type: 'square', f: p.f * 1.006, dur, peak: 0.45, a: 0.004, hold, curve: 'fast' });
}

function timpani(dest, t, p) {
  const dur = p.dur ?? 1.8;
  synth.tone(dest, t, { f: p.f * 1.5, dur: dur * 0.4, peak: p.peak * 0.22, a: 0.005 });
  synth.noise(dest, t, { lp: 450, dur: 0.1, peak: p.peak * 0.35, curve: 'fast' });
  return synth.tone(dest, t, { f: p.f * 1.04, f1: p.f, glide: 0.08, dur, peak: p.peak, a: 0.005 });
}

function crash(dest, t, p) {
  synth.noise(dest, t, { type: 'bandpass', f: 3400, q: 0.7, dur: 0.3, peak: p.peak * 0.5, curve: 'fast' });
  return synth.noise(dest, t, { hp: 5000, dur: p.dur ?? 1.6, peak: p.peak, a: 0.002, curve: 'exp' });
}

function bongo(dest, t, p) {
  synth.click(dest, t, { f: 2600, peak: p.peak * 0.3, dur: 0.008 });
  return synth.tone(dest, t, { f: p.f * 1.3, f1: p.f, glide: 0.025, dur: 0.16, peak: p.peak, a: 0.001, curve: 'fast' });
}

function tuba(dest, t, p) {
  const lp = synth.filter(dest, 'lowpass', 480, 1), dur = Math.max(0.12, p.dur);
  const q = { f: p.f, dur, a: 0.035, hold: dur * 0.6, curve: 'fast', vib: p.wobble ?? 10, vibRate: p.wobbleRate ?? 5.5 };
  synth.tone(dest, t, { ...q, peak: p.peak * 0.5 });
  return synth.tone(lp, t, { ...q, type: 'sawtooth', peak: p.peak });
}

function harmonica(dest, t, p) {
  const bp = synth.filter(synth.filter(dest, 'highpass', 380, 0.7), 'bandpass', 1400, 1.2), dur = Math.max(0.1, p.dur);
  const q = { f: p.f * Math.pow(2, -(p.bend ?? 0) / 1200), f1: p.f, glide: 0.09, dur, a: 0.03, hold: dur * 0.6, curve: 'fast', vib: 14, vibRate: 5.2, vibDelay: 0.12 };
  synth.tone(bp, t, { ...q, type: 'square', peak: p.peak * 0.6 });
  synth.noise(bp, t, { dur, peak: p.peak * 0.08, a: 0.03, curve: 'fast' });
  return synth.tone(bp, t, { ...q, type: 'sawtooth', peak: p.peak });
}

// Harmon-muted trumpet; `wah` sweeps the nasal formant open over the note.
function mute(dest, t, p) {
  const bp = synth.filter(dest, 'bandpass', 1500, 2.8), dur = Math.max(0.1, p.dur);
  if (p.wah) { bp.frequency.setValueAtTime(650, t); bp.frequency.linearRampToValueAtTime(2100, t + dur * 0.7); }
  return synth.tone(synth.filter(bp, 'highpass', 550, 0.7), t, {
    type: 'sawtooth', f: p.f, dur, peak: p.peak, a: 0.018, hold: dur * 0.65, curve: 'fast', vib: 14, vibRate: 5.6, vibDelay: 0.14,
  });
}

// Two-tone truck air horn (a major third), overdriven, drooping at the end.
function airHorn(dest, t, p) {
  const sh = synth.shaper(synth.filter(synth.gain(dest, p.peak), 'lowpass', 1700, 0.8), 2.5), dur = p.dur;
  const q = { type: 'sawtooth', dur, a: 0.02, hold: dur * 0.75, curve: 'fast', glideDelay: dur * 0.7, peak: 0.45 };
  synth.tone(sh, t, { ...q, f: p.f * 1.26, f1: p.f * 1.22 });
  return synth.tone(sh, t, { ...q, f: p.f, f1: p.f * 0.97 });
}

// Twangy guitar pluck: bright attack, pitch settling from slightly sharp, optional delayed vibrato.
function twang(dest, t, p) {
  const lp = synth.filter(dest, 'lowpass', 5000, 1.6), dur = Math.max(0.12, p.dur);
  lp.frequency.setValueAtTime(5200, t);
  lp.frequency.setTargetAtTime(700 + p.f * 1.5, t, 0.1);
  synth.click(dest, t, { f: 3200, peak: p.peak * 0.2, dur: 0.006 });
  return synth.tone(lp, t, { type: 'sawtooth', f: p.f * 1.025, f1: p.f, glide: 0.06, dur, peak: p.peak, a: 0.002, curve: 'exp', vib: p.vib, vibRate: 6, vibDelay: 0.2 });
}

// Warbly nursery organ (GDD: square wave with a pitch LFO), two squares a few cents apart.
function organSq(dest, t, p) {
  const lp = synth.filter(dest, 'lowpass', 2400, 0.7), dur = Math.max(0.08, p.dur);
  const q = { type: 'square', dur, a: 0.01, hold: dur - 0.05, curve: 'fast', vib: 30, vibRate: 6.3 };
  synth.tone(lp, t, { ...q, f: p.f * 1.004, peak: p.peak * 0.5 });
  return synth.tone(lp, t, { ...q, f: p.f, peak: p.peak });
}

function mallet(parts, clickHz) {
  return (dest, t, p) => {
    let end = t;
    for (const [r, a, d] of parts) end = Math.max(end, synth.tone(dest, t, { f: p.f * r, dur: d, peak: p.peak * a, a: 0.001 }));
    synth.click(dest, t, { f: clickHz, peak: p.peak * 0.3, dur: 0.006 });
    return end;
  };
}
const xylo = mallet([[1, 1, 0.45], [3, 0.3, 0.12], [6.2, 0.1, 0.04]], 3500);
const glock = mallet([[1, 1, 1.3], [2.76, 0.28, 0.4], [5.4, 0.12, 0.15]], 6000);
const ding = mallet([[1, 1, 1.1], [2, 0.3, 0.6], [3.01, 0.14, 0.35], [4.23, 0.1, 0.18]], 5000);

function clack(dest, t, p) {
  synth.click(dest, t, { f: 2400, peak: p.peak, dur: 0.012 });
  synth.noise(dest, t + 0.008, { type: 'bandpass', f: 3200, q: 0.7, dur: 0.1, peak: p.peak * 0.3, curve: 'fast' });
  return synth.tone(dest, t, { f: 180, f1: 110, dur: 0.07, peak: p.peak * 0.8, a: 0.001, curve: 'fast' });
}

function snip(dest, t, p) {
  synth.click(dest, t, { f: 4800, peak: p.peak, dur: 0.008 });
  return synth.click(dest, t + 0.028, { f: 2100, peak: p.peak * 0.7, dur: 0.01 });
}

function hoot(dest, t, p) {
  synth.noise(dest, t, { type: 'bandpass', f: 600, q: 6, a: 0.06, dur: p.dur, peak: p.peak * 0.25, curve: 'fast' });
  return synth.tone(dest, t, { f: 600, f1: 450, glide: p.dur, dur: p.dur, peak: p.peak, a: 0.06, hold: p.dur * 0.4, curve: 'fast', vib: 12, vibRate: 5 });
}

// Rising string swoop into `f`: three detuned saws gliding up an octave while the filter opens.
function swoop(dest, t, p) {
  const lp = synth.filter(dest, 'lowpass', 900, 0.7), dur = p.dur;
  lp.frequency.setValueAtTime(900, t);
  lp.frequency.exponentialRampToValueAtTime(4200, t + dur * 0.6);
  let end = t;
  for (const dt of [-10, 0, 9]) {
    end = synth.tone(lp, t, { type: 'sawtooth', f: p.f / 2, f1: p.f, glide: dur * 0.55, dur, detune: dt, peak: p.peak, a: dur * 0.3, hold: dur * 0.3 });
  }
  return end;
}

// Helpers shared by one-shot cues.
function line(fn, dest, t, sq, sd, peak, extra, tr = 0, gate = 1) {
  let end = t;
  for (const [m, s, l, v] of sq) end = Math.max(end, fn(dest, t + s * sd, { ...extra, f: mtof(m + tr), dur: l * sd * gate, peak: peak * v }));
  return end;
}
function chordAt(fn, dest, t, midis, dur, peak, extra) {
  let end = t;
  for (const m of midis) end = Math.max(end, fn(dest, t, { ...extra, f: mtof(m), dur, peak }));
  return end;
}
function strum(fn, dest, t, midis, dur, peak, gap = 0.022) {
  let end = t;
  midis.forEach((m, i) => { end = Math.max(end, fn(dest, t + i * gap, { f: mtof(m), dur: dur - i * gap, peak })); });
  return end;
}
// A crescendo roll of `fn` strokes spread over p.dur seconds.
function roll(fn, dest, t, p) {
  const n = Math.max(2, Math.round(p.dur / (p.rate ?? 0.05)));
  let end = t;
  for (let i = 0; i < n; i++) {
    end = Math.max(end, fn(dest, t + (i * p.dur) / n, { f: p.f, dur: p.stroke, peak: p.peak * (0.25 + (0.75 * i) / (n - 1)) }));
  }
  return end;
}
// Tremolo-picked note (surf guitar): repeated short plucks for p.dur seconds.
function tremolo(fn, dest, t, p, rate = 0.055) {
  let end = t;
  for (let x = 0; x < p.dur - 0.01; x += rate) end = Math.max(end, fn(dest, t + x, { f: p.f, dur: rate * 1.8, peak: p.peak * (x ? 0.8 : 1) }));
  return end;
}

// ------------------------------------------------------------------------------------------------
// Sequencer
// ------------------------------------------------------------------------------------------------

const byTime = (a, b) => a[0] - b[0];

class Player {
  constructor(ac, song, dest, o = {}) {
    this.ac = ac;
    this.song = song;
    this.vars = o.vars || {};
    this.sd = 60 / song.bpm / 4;               // one 16th step, seconds
    this.barDur = this.sd * 16;
    this.swing = (song.swing ?? 0) * this.sd;  // delay of every odd 16th
    this.t0 = o.t0 ?? ac.currentTime + 0.04;
    this.out = ac.createGain();
    this.out.connect(dest);
    const level = o.level ?? song.gain ?? 0.5, g = this.out.gain;
    if (o.fade > 0) { g.setValueAtTime(0, this.t0); g.linearRampToValueAtTime(level, this.t0 + o.fade); } else g.value = level;
    this.L = Object.create(null);
    this.layer('main');
    if (song.setup) song.setup(this);
    this.bar = 0;
    this.next = this.t0;
    this.maxBars = o.bars ?? Infinity;
    this.endAt = Infinity;
    this.q = [];
    this.qi = 0;
    this.cur = 0;
    this.dead = false;
  }

  layer(name, { pan = 0, level = 1, on = true } = {}) {
    const g = this.ac.createGain();
    g.gain.value = on ? level : 0;
    if (pan) { const sp = this.ac.createStereoPanner(); sp.pan.value = pan; g.connect(sp); sp.connect(this.out); } else g.connect(this.out);
    return (this.L[name] = { node: g, on, level, offAt: on ? Infinity : -1 });
  }

  setLayer(name, on, fade = 1.5) {
    const L = this.L[name];
    if (!L || L.on === on) return;
    const t = this.ac.currentTime, g = L.node.gain;
    holdAt(g, t);
    g.linearRampToValueAtTime(on ? L.level : 0, t + fade);
    L.on = on;
    L.offAt = on ? Infinity : t + fade;
  }

  // ---- bar writers (valid inside song.bar) ----
  at(step) { return this.cur + step * this.sd + ((step | 0) & 1 ? this.swing : 0); }
  ev(layer, fn, step, p) {
    if (!this.song.tight) p.peak *= 0.93 + Math.random() * 0.14;
    this.q.push([this.at(step) + (this.song.tight ? 0 : (Math.random() - 0.5) * 0.004), this.L[layer], fn, p]);
  }
  hit(layer, fn, step, peak, extra) { this.ev(layer, fn, step, { ...extra, peak }); }
  note(layer, fn, step, midi, len, peak, extra) { this.ev(layer, fn, step, { ...extra, f: mtof(midi), dur: len * this.sd, peak }); }
  pat(layer, fn, str, peak, extra) {
    for (let i = 0; i < str.length; i++) { const v = VEL[str[i]]; if (v) this.ev(layer, fn, i, { ...extra, peak: peak * v }); }
  }
  seq(layer, fn, sq, tr, peak, extra) { for (const [m, s, l, v] of sq) this.note(layer, fn, s, m + tr, l, peak * v, extra); }
  chord(layer, fn, step, midis, len, peak, extra) { for (const m of midis) this.note(layer, fn, step, m, len, peak, extra); }
  chords(layer, fn, rhythm, midis, len, peak, extra) {
    for (let i = 0; i < rhythm.length; i++) { const v = VEL[rhythm[i]]; if (v) this.chord(layer, fn, i, midis, len, peak * v, extra); }
  }
  // One legato phrase (theremin, kazoo line) from a step sequence, as a single event at its first step.
  phrase(layer, fn, sq, tr, peak, extra) {
    const s0 = sq[0][1];
    this.ev(layer, fn, s0, { ...extra, peak, notes: sq.map(([m, , l]) => [mtof(m + tr), l * this.sd]) });
  }

  // ---- clock ----
  pump(h) {
    if (this.dead) return false;
    const now = this.ac.currentTime;
    if (now > this.endAt + 0.1) { this.dispose(); return false; }
    while (this.next < h + 0.02 && this.bar < this.maxBars && this.next < this.endAt) {
      if (this.qi) { this.q.splice(0, this.qi); this.qi = 0; }
      this.cur = this.next;
      this.song.bar(this, this.bar, this.vars);
      this.bar++;
      this.next = this.cur + this.barDur;
      this.q.sort(byTime);
      if (this.bar >= this.maxBars) this.endAt = Math.min(this.endAt, this.next + (this.song.tail ?? 1.5));
    }
    const q = this.q;
    while (this.qi < q.length && q[this.qi][0] < h) {
      const [t, L, fn, p] = q[this.qi++];
      if (t >= this.endAt || t < now - 0.05 || (!L.on && t > L.offAt)) continue;
      fn(L.node, Math.max(t, now), p);
    }
    return true;
  }

  stopAt(t, fade = 0.1) {
    if (this.dead || this.endAt <= t + fade) return;
    holdAt(this.out.gain, t);
    this.out.gain.linearRampToValueAtTime(0, t + fade);
    this.endAt = t + fade;
  }

  dispose() {
    this.dead = true;
    this.out.disconnect();
  }

  beat(now) { return Math.max(0, (now - this.t0) / (this.sd * 4)); }
}

// ------------------------------------------------------------------------------------------------
// Songs (music states and sequenced cues)
// ------------------------------------------------------------------------------------------------

// title: 100 BPM E-minor funk. Em7 vamp, Am7, C9 (horns quote the station motif), B7#9 turnaround.
const TITLE_ROOT = [0, 0, 0, 0, 5, 5, 8, 7];
const TITLE_BASS = [
  seq('E2@0:1.5! E3@3:.5! E2@6:.5 E2@7:.5~ G2@8:1 A2@10:1.5 B2@13:.5 D3@14:.5! E3@15:.5'),
  seq('E2@0:1! E2@2:.5~ E3@3:.5! D3@5:.5 B2@6:.5 A2@8:.5 G2@9:.5 E2@10:1! E3@12:.5! E2@13:.5~ G2@14:.5 A2@15:.5'),
];
const TITLE_CLAV = [ch('B3 D4 F#4'), ch('B3 D4 F#4'), ch('B3 D4 F#4'), ch('B3 D4 F#4'), ch('C4 E4 G4'), ch('C4 E4 G4'), ch('E4 Bb4 D5'), ch('D#4 A4 D5')];
const TITLE_HORN_A = seq('B4@0:2 D5@2:1 E5@3:3 G5@6:1 E5@7:1 D5@8:2 B4@10:1 A4@11:1 B4@12:4');
const TITLE_HORN_B = seq('E5@0:1.5 D5@2:1 B4@3:1 A4@4:2 G4@6:2 A4@8:1 B4@9:1 E4@10:5');
const TITLE_MOTIF = seq('G4@0:1.5! C5@2:1.5! E5@4:1.5! G5@6:4!');
const EM7_HORN = ch('E4 G4 B4 D5'), C9_HORN = ch('E4 Bb4 D5'), B7S9_HORN = ch('D#4 A4 D5');
const TITLE = {
  bpm: 100, swing: 0.14, gain: 0.55, verb: 0.12,
  setup(p) { p.layer('hats', { pan: 0.28 }); p.layer('clav', { pan: -0.32 }); p.layer('horns', { pan: 0.14 }); },
  bar(p, b) {
    const i = b % 8, turn = i === 3 || i === 7;
    if (i === 0) p.hit('main', crash, 0, 0.1);
    p.pat('main', kick, i & 1 ? 'x.x....x..x..x..' : 'x......x..x.....', 0.8);
    p.pat('main', snare, i === 7 ? '....X..o.o..XxXX' : '....X..o.o..X..o', 0.4);
    p.pat('hats', hat, turn ? 'xoxoxoxoxoxoxo.o' : 'xoxoxoxoxoxoxoxo', 0.13);
    if (turn) p.hit('hats', hatOpen, 14, 0.1);
    p.seq('main', slap, TITLE_BASS[i & 1], TITLE_ROOT[i], 0.42);
    p.chords('clav', clav, '.x.x..x..x.x..x.', TITLE_CLAV[i], 0.9, 0.13, { wahRate: 3.4 });
    if (i === 1 || i === 3 || i === 5) p.chord('horns', brass, 14, EM7_HORN, 1.6, 0.06);
    if (i === 4) { p.seq('horns', brass, TITLE_HORN_A, 0, 0.1); p.seq('horns', brass, TITLE_HORN_A, -12, 0.06); }
    if (i === 5) { p.seq('horns', brass, TITLE_HORN_B, 0, 0.1); p.seq('horns', brass, TITLE_HORN_B, -12, 0.06); }
    if (i === 6) { p.seq('horns', brass, TITLE_MOTIF, 0, 0.1); p.seq('horns', brass, TITLE_MOTIF, -12, 0.06); p.chord('horns', brass, 12, C9_HORN, 1, 0.06); p.chord('horns', brass, 14, C9_HORN, 1, 0.06); }
    if (i === 7) for (const s of [0, 3, 6]) p.chord('horns', brass, s, B7S9_HORN, s === 6 ? 3 : 1, 0.07);
  },
};

// select: each hero's 2-bar show intro with a 3-note leitmotif (GDD §4), after a channel clack.
const SELECT = {
  // Skip, "Behind the Scenes": bouncy G major, xylophone leitmotif D5-G5-E5.
  skip: {
    bpm: 118, swing: 0.1, gain: 0.5, verb: 0.1,
    setup(p) { p.layer('hi', { pan: 0.25 }); p.layer('clav', { pan: -0.25 }); },
    bass: [seq('G2@0:3 D3@4:3 G2@8:3 B2@12:3'), seq('C3@0:3 G2@4:3 D3@8:3 D2@12:2 F#2@14:2')],
    lead: [seq('D5@0:2! G5@2:2! E5@4:4! D5@10:1 E5@12:1 G5@14:2'), seq('A5@0:2 G5@4:2 E5@6:1 D5@8:6')],
    comp: [[ch('B3 D4 G4'), ch('B3 D4 G4')], [ch('C4 E4 G4'), ch('A3 D4 F#4')]],
    bar(p, b) {
      const i = b & 1, S = SELECT.skip;
      p.pat('main', kick, 'x...x...x...x...', 0.6);
      p.pat('main', snare, '....x.......x..o', 0.3);
      p.pat('hi', shaker, 'x.o.x.o.x.o.x.o.', 0.12);
      p.seq('main', upright, S.bass[i], 0, 0.5);
      p.seq('hi', xylo, S.lead[i], 0, 0.3);
      p.chords('clav', clav, '..x...x.........', S.comp[i][0], 1, 0.1);
      p.chords('clav', clav, '..........x...x.', S.comp[i][1], 1, 0.1);
    },
  },
  // Roxy, "Boogie Down Saturday": A-minor disco, strings leitmotif A4-C5-E5 after a swoop.
  roxy: {
    bpm: 120, gain: 0.5, verb: 0.14,
    setup(p) { p.layer('hats', { pan: 0.3 }); p.layer('str', { pan: -0.2 }); },
    bass: [seq('A2@0:1 A3@2:1 A2@4:1 A3@6:1 A2@8:1 A3@10:1 G2@12:1 G3@14:1'), seq('F2@0:1 F3@2:1 F2@4:1 F3@6:1 E2@8:1 E3@10:1 E2@12:1 G#2@14:1')],
    lead: [seq('A4@0:2! C5@2:2! E5@4:10!'), seq('D5@0:2 C5@2:2 B4@4:5 G#4@10:6')],
    bar(p, b) {
      const i = b & 1, R = SELECT.roxy;
      p.pat('main', kick, 'x...x...x...x...', 0.72);
      p.pat('main', clap, '....x.......x...', 0.3);
      p.pat('hats', hat, 'xo.oxo.oxo.oxo.o', 0.1);
      p.pat('hats', hatOpen, '..x...x...x...x.', 0.08);
      p.seq('main', slap, R.bass[i], 0, 0.36);
      if (i === 0) { p.note('str', swoop, 0, 69, 3, 0.05); p.chord('str', strings, 0, ch('A3 C4 E4'), 15, 0.06); }
      else { p.chord('str', strings, 0, ch('F3 A3 C4'), 8, 0.06); p.chord('str', strings, 8, ch('E3 G#3 B3'), 8, 0.06); }
      p.seq('str', strings, R.lead[i], 12, 0.08, { a: 0.05 });
    },
  },
  // Penny, "Engineering Report": D-dorian library music, square arpeggios, vibes leitmotif D5-A4-F5.
  penny: {
    bpm: 104, gain: 0.5, verb: 0.12,
    setup(p) { p.layer('arp', { pan: -0.3 }); p.layer('hats', { pan: 0.25 }); },
    bass: [seq('D2@0:2 D2@3:1 D3@6:1 D2@8:2 C3@11:1 A2@14:2'), seq('G2@0:2 G2@3:1 G3@6:1 G2@8:2 F3@11:1 D3@14:2')],
    lead: [seq('D5@0:3! A4@3:3! F5@6:8!'), seq('E5@0:3 C5@3:3 G5@6:8')],
    arp: [ch('D4 F4 A4 C5'), ch('D4 G4 B4 F5')],
    bar(p, b) {
      const i = b & 1, P = SELECT.penny;
      p.pat('main', kick, 'x.......x.x.....', 0.62);
      p.pat('main', rim, '....x.......x...', 0.28);
      p.pat('hats', hat, 'x.x.x.x.x.x.x.x.', 0.11);
      for (let s = 0; s < 16; s++) p.note('arp', sqLead, s, P.arp[i][s % 4] + (s >= 8 ? 12 : 0), 0.7, 0.035);
      p.seq('main', sqBass, P.bass[i], 0, 0.16);
      p.seq('main', vibes, P.lead[i], 0, 0.26);
      if (i === 1) { p.note('hats', sqLead, 14, 83, 0.4, 0.03); p.note('hats', sqLead, 15, 83, 0.4, 0.03); }
    },
  },
  // Duke, "Precinct 13": C-minor cop funk, brass leitmotif G4-Bb4-C5 over bongos and wah-clav.
  duke: {
    bpm: 108, swing: 0.1, gain: 0.5, verb: 0.12,
    setup(p) { p.layer('hats', { pan: 0.25 }); p.layer('clav', { pan: -0.3 }); p.layer('horns', { pan: 0.1 }); },
    bass: [seq('C2@0:1! C3@2:.5! Bb2@3:.5 G2@4:1 C2@6:.5 Eb2@8:1 F2@10:1 F#2@12:.5 G2@14:1'), seq('C2@0:1! C3@2:.5! Bb2@3:.5 G2@4:1 C2@6:.5 Eb3@8:1 D3@10:.5 C3@11:.5 Bb2@12:1 G2@14:1')],
    lead: [seq('G4@0:1! Bb4@1:1! C5@2:6!'), seq('Eb5@0:1 D5@1:1 C5@2:2 G4@4:4')],
    bar(p, b) {
      const i = b & 1, D = SELECT.duke;
      p.pat('main', kick, 'x..x..x...x.....', 0.78);
      p.pat('main', snare, '....X..o....X..o', 0.38);
      p.pat('hats', hat, 'xoxoxoxoxoxoxoxo', 0.12);
      p.pat('hats', bongo, 'x..x.x..x.x..x..', 0.18, { f: 320 });
      p.seq('main', slap, D.bass[i], 0, 0.4);
      p.chords('clav', clav, '.x..x.x..x..x.x.', ch('Eb4 G4 Bb4'), 0.9, 0.12, { wahRate: 3.6 });
      p.seq('horns', brass, D.lead[i], 0, 0.11);
      p.seq('horns', brass, D.lead[i], -12, 0.06);
      p.chord('horns', brass, i ? 10 : 12, ch('Eb4 G4 Bb4 C5'), 1.5, 0.05);
      if (i) p.chord('horns', brass, 14, ch('D4 F4 Ab4 B4'), 1.5, 0.05);
    },
  },
};

// round (rounds 10+): D-minor 4-bar bass-and-hats loop; wah-clav joins above 16 living zombies.
const ROUND_BASS = [
  seq('D2@0:1! D2@3:.5~ D3@4:.5 C3@6:.5 D2@7:1 A2@10:1 C3@12:.5 D3@14:1'),
  seq('D2@0:1! D2@2:.5~ F2@3:1 G2@6:.5 A2@8:1 C3@10:.5 A2@11:.5 G2@12:1 F2@14:1'),
  seq('Bb1@0:1! Bb2@3:.5 Bb1@6:.5 F2@7:1 Bb2@10:.5 A2@12:.5 F2@14:1'),
  seq('A1@0:1! A2@3:.5 G2@4:.5 E2@6:.5 A1@8:1 C#2@10:.5 E2@12:.5 G2@14:.5 A2@15:.5'),
];
const ROUND_CLAV = [ch('D4 F4 A4'), ch('D4 F4 A4'), ch('D4 F4 Bb4'), ch('C#4 E4 G4')];
const ROUND = {
  bpm: 104, swing: 0.08, gain: 0.3, verb: 0.08, adaptive: true,
  setup(p) { p.layer('hats', { pan: 0.25 }); p.layer('clav', { pan: -0.3, on: false }); },
  bar(p, b) {
    const i = b % 4;
    p.pat('hats', hat, 'xoxoxoxoxoxoxo' + (i === 3 ? '..' : 'xo'), 0.13);
    if (i === 3) p.hit('hats', hatOpen, 14, 0.09);
    p.seq('main', slap, ROUND_BASS[i], 0, 0.5, { bright: 0.55 });
    p.chords('clav', clav, '.x..x.x..x..x.x.', ROUND_CLAV[i], 1.1, 0.24, { wahRate: 3.5 });
  },
};

// morning (the Morning Show): the round loop re-voiced in D major with vibes, shaker and the same clav.
const MORNING_BASS = [
  seq('D2@0:1! D2@3:.5~ D3@4:.5 A2@6:.5 D2@7:1 F#2@10:1 A2@12:.5 B2@14:1'),
  seq('D2@0:1! D2@2:.5~ F#2@3:1 G2@6:.5 A2@8:1 B2@10:.5 A2@11:.5 F#2@12:1 E2@14:1'),
  seq('G1@0:1! G2@3:.5 G1@6:.5 D2@7:1 G2@10:.5 F#2@12:.5 D2@14:1'),
  seq('A1@0:1! A2@3:.5 G2@4:.5 E2@6:.5 A1@8:1 C#2@10:.5 E2@12:.5 G2@14:.5 A2@15:.5'),
];
const MORNING_CHORDS = [ch('F#4 A4 D5'), ch('F#4 A4 D5'), ch('G4 B4 D5'), ch('G4 C#5 E5')];
const MORNING = {
  bpm: 104, swing: 0.08, gain: 0.34, verb: 0.12, adaptive: true,
  setup(p) { p.layer('hats', { pan: 0.25 }); p.layer('keys', { pan: -0.15 }); p.layer('clav', { pan: -0.3, on: false }); },
  bar(p, b) {
    const i = b % 4;
    p.pat('hats', hat, 'xoxoxoxoxoxoxo' + (i === 3 ? '..' : 'xo'), 0.13);
    p.pat('hats', shaker, '..x...x...x...x.', 0.1);
    if (i === 3) p.hit('hats', hatOpen, 14, 0.09);
    p.seq('main', slap, MORNING_BASS[i], 0, 0.48, { bright: 0.8 });
    p.chord('keys', vibes, 0, MORNING_CHORDS[i], 8, 0.12);
    p.chord('keys', vibes, 10, MORNING_CHORDS[i], 6, 0.07);
    p.chords('clav', clav, '.x..x.x..x..x.x.', MORNING_CHORDS[i].map((m) => m - 12), 1.1, 0.24, { wahRate: 3.5 });
  },
};

// intermission (and pu_bossa_bed): quiet elevator bossa — Rhodes, rim clave, shaker, a lazy vibes tune.
const BOSSA_ROOT = ch('F2 Bb1 A1 D2 G1 C2 F2 C2');
const BOSSA_KEYS = [ch('A3 C4 E4 G4'), ch('Ab3 C4 D4 F4'), ch('G3 C4 E4 G4'), ch('F#3 C4 Eb4 A4'), ch('Bb3 D4 F4 A4'), ch('E3 Bb3 D4 A4'), ch('A3 C4 E4 G4'), ch('E3 Bb3 Db4 G4')];
const BOSSA_TUNE = [
  seq('A4@0:6 C5@6:2 E5@8:6'), seq('D5@0:6 C5@6:2 Ab4@8:8'), seq('G4@0:4 A4@4:2 C5@6:2 E5@8:8'), seq('Eb5@0:6 D5@6:2 C5@8:4 A4@12:4'),
  seq('Bb4@0:6 A4@6:2 F4@8:8'), seq('E4@0:4 G4@4:2 Bb4@6:2 D5@8:8'), seq('C5@0:6 A4@6:2 E5@8:8'), seq('G4@0:8 E4@8:6'),
];
const BOSSA = {
  bpm: 128, gain: 0.42, verb: 0.16,
  setup(p) { p.layer('perc', { pan: 0.3 }); p.layer('keys', { pan: -0.18 }); p.layer('tune', { pan: 0.12 }); },
  bar(p, b) {
    const i = b % 8, r = BOSSA_ROOT[i];
    p.pat('perc', rim, i & 1 ? '....x.....x.....' : 'x.....x.....x...', 0.22);
    p.pat('perc', shaker, 'x.o.x.o.x.o.x.o.', 0.07);
    p.note('main', upright, 0, r, 5.5, 0.45);
    p.note('main', upright, 6, r + 7, 1.8, 0.35);
    p.note('main', upright, 8, r + 7, 5.5, 0.4);
    p.note('main', upright, 14, r, 1.8, 0.33);
    for (const [s, l] of i & 1 ? [[2, 3], [6, 3], [12, 4]] : [[0, 5], [6, 3], [10, 5]]) p.chord('keys', epiano, s, BOSSA_KEYS[i], l, 0.07);
    p.seq('tune', vibes, BOSSA_TUNE[i], 0, 0.09);
  },
};

// hullabaloo: warbly organ nursery tune in F with oom-pah tuba, woodblock and a toy glockenspiel.
const HULLA_TUNE = [
  seq('C5@0:4 C5@4:4 A4@8:4 C5@12:4'), seq('D5@0:4 C5@4:4 A4@8:6 F4@14:2'), seq('G4@0:4 A4@4:4 Bb4@8:4 G4@12:4'), seq('A4@0:4 C5@4:4 C5@8:8'),
  seq('C5@0:4 C5@4:4 A4@8:4 C5@12:4'), seq('D5@0:4 F5@4:4 E5@8:4 D5@12:4'), seq('C5@0:4 A4@4:4 G4@8:4 E4@12:4'), seq('F4@0:8 F5@8:4'),
];
const HULLA_BASS = [[41, 48], [46, 41], [48, 43], [41, 48], [41, 48], [46, 41], [48, 43], [41, 36]];
const HULLA_PAH = [ch('A3 C4 F4'), ch('Bb3 D4 F4'), ch('Bb3 C4 E4'), ch('A3 C4 F4'), ch('A3 C4 F4'), ch('Bb3 D4 F4'), ch('Bb3 C4 E4'), ch('A3 C4 F4')];
const HULLABALOO = {
  bpm: 124, gain: 0.46, verb: 0.12,
  setup(p) { p.layer('lead', { pan: -0.1 }); p.layer('toys', { pan: 0.3 }); },
  bar(p, b) {
    const i = b % 8;
    p.seq('lead', organSq, HULLA_TUNE[i], 0, 0.07);
    if (i >= 4) p.seq('toys', glock, HULLA_TUNE[i], 12, 0.1);
    p.note('main', tuba, 0, HULLA_BASS[i][0], 3.5, 0.34);
    p.note('main', tuba, 8, HULLA_BASS[i][1], 3.5, 0.3);
    p.chord('lead', organSq, 4, HULLA_PAH[i], 1.5, 0.028);
    p.chord('lead', organSq, 12, HULLA_PAH[i], 1.5, 0.028);
    p.pat('toys', block, '....x.......x...', 0.2, { f: 1050 });
    p.pat('toys', shaker, '..x...x...x...x.', 0.08);
    if (i === 3) p.ev('toys', whistle, 12, { from: 500, to: 1500, dur: 0.45, peak: 0.1 });
    if (i === 7) p.ev('toys', whistle, 12, { from: 1500, to: 450, dur: 0.45, peak: 0.1 });
  },
};

// boss: 128 BPM C-minor funk — fuzz bass, overdriven organ stabs; phase 2 adds the theremin lead and
// busier drums, phase 3 a four-on-the-floor kick, horn stabs, tension strings, crashes and fills. The
// rhythm section also digs in harder with every phase.
const BOSS_BASS = [
  seq('C2@0:1 C2@2:.5 C3@3:.5 Bb2@4:.5 G2@6:1 C2@8:.5 Eb2@10:1 F2@12:.5 F#2@13:.5 G2@14:1'),
  seq('C2@0:1 C2@2:.5 C3@3:.5 Eb3@5:.5 D3@6:.5 C3@8:.5 Bb2@10:1 G2@12:1 Bb2@14:.5 B2@15:.5'),
  seq('Ab1@0:1 Ab1@2:.5 Ab2@3:.5 Gb2@4:.5 Eb2@6:1 Ab1@8:.5 C2@10:1 Eb2@12:.5 Gb2@14:1'),
  seq('G1@0:1 G1@2:.5 G2@3:.5 F2@4:.5 D2@6:1 G1@8:.5 B1@10:1 D2@12:.5 F2@13:.5 Ab2@14:.5 B2@15:.5'),
];
const BOSS_STAB = [ch('G3 C4 Eb4'), ch('G3 C4 Eb4'), ch('Gb3 C4 Eb4'), ch('F3 B3 D4')];
const BOSS_PAD = [ch('C4 Eb4 G4 B4'), ch('C4 Eb4 G4 B4'), ch('C4 Eb4 Gb4 Ab4'), ch('B3 D4 F4 Ab4')];
const BOSS_THEREMIN = seq('G4@0:6 Ab4@6:2 G4@8:8 Eb5@16:6 D5@22:2 C5@24:8 C5@32:4 Bb4@36:4 Ab4@40:8 G4@48:4 B4@52:4 D5@56:4 F5@60:4');
const BOSS = {
  bpm: 128, gain: 0.5, verb: 0.1,
  setup(p) {
    p.layer('hats', { pan: 0.25 }); p.layer('stab', { pan: -0.25 });
    p.layer('p2', { pan: 0.1, on: p.vars.intensity >= 2 }); p.layer('p3', { on: p.vars.intensity >= 3 });
  },
  bar(p, b, v) {
    const i = b % 4, n = v.intensity, lift = 1 + 0.1 * (n - 1);
    p.pat('main', kick, n >= 3 ? 'x...x...x...x.x.' : 'x..x..x...x..x..', 0.82 * lift);
    p.pat('main', snare, n >= 2 && i === 3 ? '....X..o....XXXX' : '....X..o....X.o.', 0.4 * lift);
    p.pat('hats', hat, n >= 2 ? 'xoxoxoxoxoxoxoxo' : 'x.x.x.x.x.x.x.x.', 0.13);
    p.seq('main', fuzzBass, BOSS_BASS[i], 0, 0.2 * lift);
    p.chords('stab', organDrive, n >= 2 ? '..x...x...x...x.' : '......x.......x.', BOSS_STAB[i], 0.8, 0.07);
    if (i === 0) p.phrase('p2', theremin, BOSS_THEREMIN, 0, 0.13, { porta: 0.09, vib: 30 });
    p.pat('p2', shaker, '....x.......x...', 0.12);
    p.chord('p3', strings, 0, BOSS_PAD[i], 15, 0.045, { a: 0.35 });
    p.chord('p3', brass, 0, BOSS_STAB[i].map((m) => m + 12), 1.5, 0.05);
    p.chord('p3', brass, 10, BOSS_STAB[i].map((m) => m + 12), 2, 0.05);
    if (i % 2 === 0) p.hit('p3', crash, 0, 0.07);
    if (i === 3) p.pat('p3', snare, '........oooxxxXX', 0.3);
  },
};

// credits: 112 BPM disco-funk in F — the strings sing the Sign-Off hymn over slap octaves and wah-clav.
const HYMN = ch('G4 C5 E5 D5 C5 A4 B4 G4 E5 F5 E5 C5 A4 D5 B4 C5');
const CREDITS_ROOT = [[41, 34], [41, 36], [38, 34], [33, 36], [41, 31], [38, 34], [31, 36], [36, 41]];
const V_F = ch('A3 C4 F4'), V_BB = ch('Bb3 D4 F4'), V_C = ch('G3 C4 E4'), V_DM = ch('A3 D4 F4'), V_AM = ch('A3 C4 E4'), V_GM = ch('Bb3 D4 G4'), V_C7 = ch('Bb3 C4 E4');
const CREDITS_VOX = [[V_F, V_BB], [V_F, V_C], [V_DM, V_BB], [V_AM, V_C], [V_F, V_GM], [V_DM, V_BB], [V_GM, V_C], [V_C7, V_F]];
const CREDITS = {
  bpm: 112, swing: 0.06, gain: 0.5, verb: 0.14,
  setup(p) { p.layer('hats', { pan: 0.3 }); p.layer('clav', { pan: -0.3 }); p.layer('str', { pan: 0.08 }); },
  bar(p, b) {
    const i = b % 8;
    p.pat('main', kick, 'x...x...x...x...', 0.72);
    p.pat('main', clap, '....x.......x...', 0.28);
    p.pat('hats', hat, 'xo.oxo.oxo.oxo.o', 0.1);
    p.pat('hats', hatOpen, '..x...x...x...x.', 0.07);
    CREDITS_ROOT[i].forEach((r, h) => { for (let s = 0; s < 8; s += 2) p.note('main', slap, h * 8 + s, r + (s & 2 ? 12 : 0), 1.2, 0.36); });
    CREDITS_VOX[i].forEach((v, h) => p.chords('clav', clav, h ? '.........x.x..x.' : '.x.x..x.', v, 0.9, 0.11, { wahRate: 3.7 }));
    const m1 = HYMN[i * 2] + 5, m2 = HYMN[i * 2 + 1] + 5;
    p.note('str', strings, 0, m1, 6, 0.075, { a: 0.06 });
    p.note('str', strings, 6, m2, 10, 0.075, { a: 0.06 });
    p.note('str', strings, 0, m1 - 12, 6, 0.045, { a: 0.06 });
    p.note('str', strings, 6, m2 - 12, 10, 0.045, { a: 0.06 });
    if (i === 3 || i === 5) p.chord('str', brass, 14, CREDITS_VOX[i + 1][0].map((m) => m + 12), 1.4, 0.05);
    if (i === 7) { p.chord('str', brass, 0, V_C7.map((m) => m + 12), 1, 0.06); p.chord('str', brass, 3, V_C7.map((m) => m + 12), 1, 0.06); p.hit('main', crash, 0, 0.08); }
  },
};

// sting_sign_on_theme: 8 s of full funk band in C (4 bars at 120 BPM) and a final hit; the horns play
// the station motif in bar 4.
const SIGNON_BASS = seq('C2@0:1! C3@3:.5! C2@6:.5 Bb1@7:.5~ C2@8:1 E2@10:.5 G2@11:.5 Bb2@12:1 C3@14:.5! G2@15:.5');
const C9_FULL = ch('C4 E4 Bb4 D5'), F9_HORN = ch('Eb4 A4 C5');
const SIGNON = {
  bpm: 120, swing: 0.1, gain: 1, tail: 2.2,
  setup(p) { p.layer('hats', { pan: 0.28 }); p.layer('clav', { pan: -0.3 }); p.layer('horns', { pan: 0.12 }); },
  bar(p, b) {
    if (b === 4) {
      p.hit('main', kick, 0, 0.8); p.hit('main', crash, 0, 0.12);
      p.note('main', slap, 0, 36, 5, 0.45);
      p.chord('horns', brass, 0, C9_FULL.concat(79), 6, 0.08);
      return;
    }
    if (b === 0) { p.hit('main', crash, 0, 0.12); p.chord('horns', brass, 0, C9_FULL, 2, 0.08); }
    p.pat('main', kick, b & 1 ? 'x.x....x..x..x..' : 'x......x..x.....', 0.8);
    p.pat('main', snare, b === 3 ? '....X..o.o..XxXX' : '....X..o.o..X..o', 0.4);
    p.pat('hats', hat, 'xoxoxoxoxoxoxoxo', 0.13);
    p.seq('main', slap, SIGNON_BASS, b === 2 ? 5 : 0, 0.42);
    p.chords('clav', clav, '.x.x..x..x.x..x.', b === 2 ? F9_HORN : C9_HORN, 0.9, 0.13, { wahRate: 4 });
    if (b === 1) for (const s of [6, 14]) p.chord('horns', brass, s, C9_HORN, 1, 0.07);
    if (b === 2) for (const s of [6, 14]) p.chord('horns', brass, s, F9_HORN, 1, 0.07);
    if (b === 3) {
      p.seq('horns', brass, TITLE_MOTIF, 0, 0.1); p.seq('horns', brass, TITLE_MOTIF, -12, 0.06);
      p.chord('horns', brass, 12, C9_HORN, 1, 0.07); p.chord('horns', brass, 14, C9_HORN, 1, 0.07);
    }
  },
};

// tele_cartoon: the Tiny Tele's bouncy square-wave cartoon theme (2-bar loop, 150 BPM, C major).
const CARTOON_LEAD = [seq('C5@0:1 E5@2:1 G5@4:1 E5@6:1 A5@8:2 G5@10:2 E5@12:2 C5@14:2'), seq('D5@0:1 F5@2:1 A5@4:1 F5@6:1 G5@8:2 F5@10:1 D5@11:1 B4@12:2 G4@14:2')];
const CARTOON_BASS = [seq('C3@0:2 G3@4:2 C3@8:2 G3@12:2'), seq('G3@0:2 D4@4:2 G3@8:2 B3@12:2')];
const CARTOON = {
  bpm: 150, gain: 1, tight: true,
  bar(p, b) {
    const i = b & 1;
    p.seq('main', sqLead, CARTOON_LEAD[i], 0, 0.11, { vib: 12 });
    p.seq('main', sqBass, CARTOON_BASS[i], 0, 0.14);
    p.pat('main', snare, '....x.......x...', 0.22);
    p.pat('main', hat, 'x.x.x.x.x.x.x.x.', 0.1);
  },
};

// toy_radio: 20 s of A-minor funk (8 bars at 96 BPM) for the news van's radio.
const RADIO_ROOT = [0, 0, 5, 5, 0, 0, 8, 7];
const RADIO_BASS = seq('A2@0:1! A3@3:.5! A2@6:.5 C3@8:1 D3@10:1 E3@12:.5 G3@14:.5 A3@15:.5');
const RADIO_CLAV = [ch('C4 E4 G4'), ch('C4 E4 G4'), ch('C4 E4 F#4'), ch('C4 E4 F#4'), ch('C4 E4 G4'), ch('C4 E4 G4'), ch('Eb4 A4 C5'), ch('D4 G#4 B4')];
const RADIO_HORNS = [seq('E5@0:2 D5@2:1 C5@3:2 A4@6:2 C5@8:1 D5@9:1 E5@10:6'), seq('G5@0:3 E5@3:1 D5@4:2 C5@6:2 A4@8:8'), seq('A4@0:1 C5@2:1 Eb5@4:2 C5@6:2 A4@8:4')];
const RADIO = {
  bpm: 96, swing: 0.12, gain: 1, tail: 0.6,
  setup(p) { p.layer('clav', { pan: -0.2 }); p.layer('horns', { pan: 0.15 }); },
  bar(p, b) {
    const i = b % 8;
    p.pat('main', kick, i & 1 ? 'x.x....x..x.....' : 'x......x..x..x..', 0.7);
    p.pat('main', snare, '....X..o.o..X..o', 0.36);
    p.pat('main', hat, 'xoxoxoxoxoxoxoxo', 0.12);
    p.seq('main', slap, RADIO_BASS, RADIO_ROOT[i], 0.4);
    p.chords('clav', clav, '.x..x.x..x.x..x.', RADIO_CLAV[i], 0.9, 0.12, { wahRate: 3.2 });
    if (i < 4 && i & 1) p.chord('horns', brass, 14, ch('E4 G4 C5'), 1.4, 0.06);
    if (i >= 4 && i < 7) p.seq('horns', brass, RADIO_HORNS[i - 4], 0, 0.1);
    if (i === 7) for (const s of [0, 3, 6]) p.chord('horns', brass, s, ch('D4 G#4 D5'), s === 6 ? 3 : 1, 0.07);
  },
};

// ------------------------------------------------------------------------------------------------
// The Sign-Off hymn: 16 notes, harmonized once into four voices by a small voice-leading search
// ------------------------------------------------------------------------------------------------

const HYMN_BASS = ch('C3 F2 E2 G2 A2 F2 E2 G2 C3 D3 A2 F2 D2 G2 G2 C2');
const HYMN_PCS = [[0, 4, 7], [5, 9, 0], [0, 4, 7], [7, 11, 2], [9, 0, 4], [5, 9, 0], [4, 7, 11], [7, 11, 2],
  [0, 4, 7], [2, 5, 9], [9, 0, 4], [5, 9, 0], [2, 5, 9], [7, 11, 2], [7, 11, 2, 5], [0, 4, 7]];

// For each melody note pick alto and tenor chord tones that move least, keep the third (and the 7th of
// G7), keep voices within an octave of each other and never double the leading tone.
function harmonize() {
  const out = [];
  let pa = 64, pt = 55;
  for (let i = 0; i < HYMN.length; i++) {
    const s = HYMN[i], b = HYMN_BASS[i], pcs = HYMN_PCS[i];
    let best = null, bestScore = Infinity;
    for (let a = s - 1; a >= Math.max(55, s - 12); a--) {
      if (!pcs.includes(a % 12)) continue;
      for (let tn = a - 1; tn >= Math.max(b + 1, 48); tn--) {
        if (!pcs.includes(tn % 12) || a - tn > 12) continue;
        const pcsNow = [s, a, tn, b].map((x) => x % 12);
        let score = Math.abs(a - pa) + Math.abs(tn - pt);
        if (!pcsNow.includes(pcs[1])) score += 12;
        if (!pcsNow.includes(pcs[0])) score += 8;
        if (pcs.length > 3 && !pcsNow.includes(pcs[3])) score += 4;
        if (pcsNow.filter((x) => x === 11).length > 1) score += 6;
        if (score < bestScore) { bestScore = score; best = [a, tn]; }
      }
    }
    [pa, pt] = best;
    out.push([s, pa, pt, b]);
  }
  return out;
}
const HYMN_SATB = harmonize();

// Brass choir (GDD: sting_signoff_hymn, 16 bars), optionally with timpani and strings doubling the
// soprano and alto an octave up (victory; the tenor stays brass-only to keep the render cost down).
function hymn(dest, t, { note, last, bright, strings: withStrings, timp }) {
  let tt = t, end = t;
  HYMN_SATB.forEach((voices, i) => {
    const d = i >= 14 ? note * 1.25 : note, len = i === 15 ? last : d + 0.04;
    voices.forEach((m, v) => {
      const pk = [0.11, 0.075, 0.075, 0.1][v];
      end = Math.max(end, brass(dest, tt, { f: mtof(m), dur: len, peak: pk, a: 0.07, bright }));
      if (withStrings && v < 2) strings(dest, tt, { f: mtof(m + 12), dur: len + 0.3, peak: v ? 0.06 : 0.07, a: 0.12 });
    });
    if (timp && (i === 0 || i === 8)) timpani(dest, tt, { f: mtof(voices[3] >= 43 ? voices[3] - 12 : voices[3]), dur: 2, peak: 0.4 });
    if (timp && i === 14) roll(timpani, dest, tt, { f: mtof(31), dur: d, rate: 0.06, stroke: 0.4, peak: 0.35 });
    if (timp && i === 15) { timpani(dest, tt, { f: mtof(36), dur: 2.5, peak: 0.5 }); crash(dest, tt, { peak: 0.1, dur: 2.5 }); }
    if (timp && i === 8) crash(dest, tt, { peak: 0.07 });
    tt += d;
  });
  return end;
}

// ------------------------------------------------------------------------------------------------
// Cue recipes (a = synth, dest = voice input, o = play opts + { t, ac })
// ------------------------------------------------------------------------------------------------

const MOTIF = ch('G4 C5 E5 G5');
const MOTIF_13 = ch('G4 C5 Eb5 G5');
const MOTIF_STEP = 0.21;
const CHIMES = { red: 'G4', yellow: 'C5', green: 'E5', blue: 'G5' };

// Music-bus stings also feed the music plate reverb (post fader: the voice input itself is tapped).
function wet(dest, o) {
  const e = engines.get(o.ac);
  if (e) dest.connect(e.stingSend);
}

function bells(dest, t, notes, peak) {
  let end = t;
  notes.forEach((m, i) => { end = Math.max(end, stationBell(dest, t + i * MOTIF_STEP, { f: mtof(m), peak: i === 3 ? peak * 1.1 : peak })); });
  return end;
}

function roundSting(dest, o, notes, hitChord) {
  const t = o.t, hit = t + 4 * MOTIF_STEP;
  wet(dest, o);
  const end = bells(dest, t, notes, 0.34);
  swell(dest, t + 0.12, { dur: hit - t - 0.12, peak: 0.06 });
  chordAt(brass, dest, hit, hitChord, 0.75, 0.08);
  brass(dest, hit, { f: mtof(48), dur: 0.8, peak: 0.1 });
  timpani(dest, hit, { f: mtof(36), dur: 1.6, peak: 0.45 });
  crash(dest, hit, { peak: 0.09, dur: 2 });
  return end;
}

// A one-shot sequenced song (or an endless loop when bars is undefined) behind a cue handle.
function songCue(song, { bars, len } = {}) {
  return (a, dest, o) => {
    const p = new Player(o.ac, song, dest, { t0: o.t, bars });
    if (len) p.stopAt(o.t + len - 0.8, 0.8);
    p.pump(o.t + LOOKAHEAD);
    const end = len ? o.t + len + 0.1 : bars ? o.t + bars * p.barDur + (song.tail ?? 1.5) : Infinity;
    return { end, update(now) { p.pump(now + horizon()); }, stop(t) { p.stopAt(t, 0.05); } };
  };
}

// Telly's spin: one slap-bass note per detent (root, fifth, octave, flat seventh), a semitone higher
// every 4 detents, with a hat tick. { auto: true } plays GDD §10.2's 20 detents easing 0.07 -> 0.5 s.
const SURF_ARP = [0, 7, 12, 10];
function tellySurfArp(a, dest, o) {
  const ac = o.ac;
  let i = 0;
  const step = (t = ac.currentTime + 0.005) => {
    const m = 52 + SURF_ARP[i % 4] + Math.floor(i / 4);
    slap(dest, t, { f: mtof(m), dur: 0.22, peak: 0.4, bright: 1.3 });
    hat(dest, t, { peak: 0.08 });
    i++;
  };
  let end = o.t + 12;
  if (o.auto) {
    let t = o.t;
    for (let k = 0; k < 20; k++) { step(t); const x = (k + 1) / 20; t += 0.07 + 0.43 * (1 - Math.pow(1 - x, 3)); }
    end = t + 0.4;
  }
  return { end, step: () => step() };
}

function withProps(fn, props) { return Object.assign(fn, props); }

const TV = { bus: 'tv', tv: true };
const WORLD = { bus: 'sfx' };
const WORLD_TV = { bus: 'sfx', tv: true };

export const MUSIC_CUES = {
  // ---- stings (music bus unless noted) ----
  sting_round_start: (a, dest, o) => roundSting(dest, o, MOTIF, ch('C4 E4 G4 C5')),
  sting_round_start_13: (a, dest, o) => roundSting(dest, o, MOTIF_13, ch('C4 Eb4 G4 C5')),

  // "We'll be right back": vibraphone E5-C5-A4 plus an upright bass pluck.
  sting_round_end: (a, dest, o) => {
    const t = o.t;
    wet(dest, o);
    vibes(dest, t, { f: mtof(76), dur: 1.4, peak: 0.26 });
    vibes(dest, t + 0.24, { f: mtof(72), dur: 1.4, peak: 0.26 });
    brush(dest, t + 0.48, { peak: 0.12 });
    upright(dest, t + 0.48, { f: mtof(45), dur: 1.1, peak: 0.5 });
    return vibes(dest, t + 0.48, { f: mtof(69), dur: 2, peak: 0.3 });
  },

  sting_sign_on_theme: songCue(SIGNON, { bars: 5 }),

  // Hootie's organ jingle, then three owl hoots (sine glides 600 -> 450 Hz).
  sting_hullabaloo_intro: (a, dest, o) => {
    const t = o.t, sd = 0.1;
    wet(dest, o);
    line(organSq, dest, t, seq('C5@0:2 C5@2:2 A4@4:2 C5@6:2 D5@8:2 Bb4@10:2 G4@12:2 F4@14:4'), sd, 0.12);
    line(tuba, dest, t, seq('F2@0:3 C3@4:3 F2@8:3 C2@12:3 F2@14:4'), sd, 0.4);
    for (const s of [4, 12]) block(dest, t + s * sd, { f: 1050, peak: 0.25 });
    hoot(dest, t + 2.1, { dur: 0.32, peak: 0.3 });
    hoot(dest, t + 2.5, { dur: 0.32, peak: 0.3 });
    return hoot(dest, t + 2.9, { dur: 0.6, peak: 0.32 });
  },

  // "…and now back to our program": a jaunty swing brass lick resolving on C.
  sting_hullabaloo_end: (a, dest, o) => {
    const t = o.t, sd = 0.1;
    wet(dest, o);
    line(brass, dest, t, seq('G4@0:1 A4@1:1 C5@2:2 E5@4:1 D5@5:1 C5@6:1 A4@7:1 G4@8:3'), sd, 0.11);
    for (const s of [8, 9, 10, 11]) snare(dest, t + s * sd, { peak: 0.2 + s * 0.02 });
    kick(dest, t + 1.2, { peak: 0.7 });
    crash(dest, t + 1.2, { peak: 0.08 });
    brass(dest, t + 1.2, { f: mtof(48), dur: 0.6, peak: 0.1 });
    return chordAt(brass, dest, t + 1.2, ch('E4 G4 C5 E5'), 0.6, 0.07);
  },

  // "…and we're back!": a triplet pickup into a bright F-major hit.
  sting_back: (a, dest, o) => {
    const t = o.t;
    wet(dest, o);
    for (const x of [0, 0.09, 0.18]) chordAt(brass, dest, t + x, ch('A4 C5'), 0.08, 0.07);
    kick(dest, t + 0.3, { peak: 0.55 });
    crash(dest, t + 0.3, { peak: 0.08 });
    upright(dest, t + 0.3, { f: mtof(41), dur: 0.7, peak: 0.42 });
    return chordAt(brass, dest, t + 0.3, ch('F4 A4 C5 F5'), 0.7, 0.08);
  },

  // Music box phrases of the Sign-Off hymn from every TV: 2/4/6/8/16 notes (EE progress).
  ...Object.fromEntries([2, 4, 6, 8, 16].map((n, k) => [`sting_ee_${k + 1}`, withProps((a, dest, o) => {
    let tt = o.t, end = o.t;
    for (let i = 0; i < n; i++) {
      end = Math.max(end, mbox(dest, tt, { f: mtof(HYMN[i] + 12), dur: 1.4, peak: 0.34 }));
      if (i === 0 || HYMN_BASS[i] !== HYMN_BASS[i - 1]) mbox(dest, tt, { f: mtof(HYMN_BASS[i] + 24), dur: 1.2, peak: 0.12 });
      tt += i === 7 ? 0.7 : 0.34;
    }
    return end;
  }, TV)])),

  // Game-show "correct!": ding-DING with a sparkle.
  sting_ee_correct: (a, dest, o) => {
    const t = o.t;
    wet(dest, o);
    ding(dest, t, { f: mtof(84), peak: 0.26 });
    for (let k = 0; k < 5; k++) synth.tone(dest, t + 0.2 + k * 0.045, { f: 3000 + k * 450, dur: 0.07, peak: 0.04, a: 0.001, curve: 'fast' });
    return ding(dest, t + 0.13, { f: mtof(91), peak: 0.3 });
  },

  // Baron Von Static forms: a sub boom, a distorted noise roar and a detuned organ cluster swelling in.
  sting_boss_intro: (a, dest, o) => {
    const t = o.t, sw = synth.gain(dest, 0);
    wet(dest, o);
    synth.tone(dest, t, { f: 58, f1: 28, glide: 1.4, dur: 1.8, peak: 0.55, a: 0.005 });
    synth.noise(synth.shaper(synth.gain(dest, 0.9), 3), t, { color: 'brown', type: 'lowpass', f: 160, f1: 2600, glide: 3.4, q: 2, a: 3.1, dur: 3.4, peak: 0.5, curve: 'lin' });
    sw.gain.setValueAtTime(0, t);
    sw.gain.linearRampToValueAtTime(1, t + 2.8);
    sw.gain.setValueAtTime(1, t + 3.3);
    sw.gain.linearRampToValueAtTime(0, t + 3.45);
    for (const m of ch('C3 F#3 C4 Eb4 F#4 G4')) {
      organDrive(sw, t, { f: mtof(m) * 1.012, dur: 3.45, peak: 0.07 });
      organDrive(sw, t, { f: mtof(m) * 0.988, dur: 3.45, peak: 0.07 });
    }
    kick(dest, t + 3.45, { peak: 0.9 });
    crash(dest, t + 3.45, { peak: 0.12, dur: 2 });
    return chordAt(organDrive, dest, t + 3.45, ch('C3 C4 Eb4 F#4'), 0.9, 0.09);
  },

  // The Sign-Off film's slow brass choir, from every TV.
  sting_signoff_hymn: withProps((a, dest, o) => hymn(dest, o.t, { note: 1.154, last: 3.4, bright: 0.55 }), TV),

  // Game over: tape-stops the music (engine) and plays its own tape-stopped chord, a hum, silence,
  // then the test card's 1 kHz tone.
  sting_gameover: (a, dest, o) => {
    const t = o.t, e = engines.get(o.ac);
    if (e) e.tapeStop(t, 1.2);
    const lp = synth.filter(dest, 'lowpass', 2200, 0.8);
    lp.frequency.setValueAtTime(2200, t);
    lp.frequency.exponentialRampToValueAtTime(180, t + 1.25);
    for (const m of ch('E2 B2 E3 G3')) synth.tone(lp, t, { type: 'sawtooth', f: mtof(m), f1: mtof(m) * 0.22, glide: 1.2, dur: 1.3, hold: 0.9, peak: 0.07, a: 0.01 });
    synth.tone(dest, t + 1.15, { f: 60, dur: 1.1, peak: 0.16, a: 0.02 });
    synth.tone(dest, t + 1.15, { f: 120, dur: 0.9, peak: 0.06, a: 0.02 });
    return synth.tone(dest, t + 2.9, { f: 1000, dur: 3, hold: 2.8, peak: 0.13, a: 0.01, curve: 'lin' });
  },

  // The full hymn on brass and strings with timpani: the ending's swell.
  sting_victory: (a, dest, o) => {
    wet(dest, o);
    return hymn(dest, o.t, { note: 0.952, last: 3.2, bright: 0.85, strings: true, timp: true });
  },

  // ---- easter-egg chime bars: the station bell, positional ----
  ...Object.fromEntries(Object.entries(CHIMES).map(([bar, n]) => [`ee_chime_${bar}`,
    withProps((a, dest, o) => stationBell(dest, o.t, { f: mtof(nm(n)), peak: 0.5 }), { ...WORLD, wet: 0.25 })])),

  // ---- Telly (from Telly's speaker) ----
  telly_lullaby: withProps((a, dest, o) => {
    let end = o.t;
    [79, 76, 72, 67].forEach((m, i) => { end = Math.max(end, mbox(dest, o.t + [0, 0.62, 1.26, 1.95][i], { f: mtof(m), dur: i === 3 ? 1.4 : 1.1, peak: 0.34 })); });
    return end;
  }, WORLD_TV),
  telly_surf_arp: withProps(tellySurfArp, WORLD_TV),

  // Precinct 13: muted-trumpet cop sting over bongos.
  jingle_revolver_38: withProps((a, dest, o) => {
    const t = o.t, sd = 0.1136;
    line(mute, dest, t, seq('G4@0:1 Bb4@1:1 C5@2:4 Eb5@6:1 D5@7:1 C5@8:6'), sd, 0.34, { wah: true });
    line(bongo, dest, t, seq('C4@0:1 G4@2:1 G4@4:1 C4@5:1 G4@6:1'), sd, 0.3);
    line(upright, dest, t, seq('C3@0:3 G2@6:2 C3@8:5'), sd, 0.6);
    rim(dest, t + 8 * sd, { peak: 0.4 });
    return chordAt(brass, dest, t + 8 * sd, ch('Eb4 G4 Bb4 D5'), 0.6, 0.05);
  }, WORLD_TV),

  // Dusty Trails: twangy western guitar and clip-clop, ending on a strummed E minor.
  jingle_pump_37: withProps((a, dest, o) => {
    const t = o.t, sd = 0.134, sp = synth.echo(dest, { time: 0.036, feedback: 0.55, wet: 0.35, lp: 3000 });
    line(twang, sp, t, seq('E3@0:2 A3@2:1 B3@3:1 E4@4:4 D4@8:1 B3@9:1 A3@10:1'), sd, 0.2, { vib: 18 });
    for (let s = 0; s < 12; s += 2) block(dest, t + s * sd, { f: s & 2 ? 700 : 900, peak: 0.22 });
    return strum(twang, sp, t + 11 * sd, ch('E3 B3 E4 G4'), 1, 0.13);
  }, WORLD_TV),

  // Agent Thirteen: tremolo-picked spy surf guitar through a spring, ending on Em(maj9).
  jingle_mp7: withProps((a, dest, o) => {
    const t = o.t, sd = 0.1, sp = synth.echo(dest, { time: 0.04, feedback: 0.5, wet: 0.4, lp: 3200 });
    for (const [m, s, l] of seq('E3@0:2 E3@2:1 F#3@3:1 G3@4:2 F#3@6:2 E3@8:2 D3@10:1 E3@11:1')) tremolo(twang, sp, t + s * sd, { f: mtof(m), dur: l * sd, peak: 0.16 });
    for (let s = 0; s < 12; s += 2) hat(dest, t + s * sd, { peak: 0.09 });
    let end = t;
    ch('E3 G3 B3 D#4 F#4').forEach((m, k) => { end = Math.max(end, tremolo(twang, sp, t + 12 * sd + k * 0.02, { f: mtof(m), dur: 0.8, peak: 0.08 }, 0.07)); });
    return end + 0.5;
  }, WORLD_TV),

  // Commando Club: a crescendo snare roll into a bugle call.
  jingle_m16a1: withProps((a, dest, o) => {
    const t = o.t;
    roll(snare, dest, t, { dur: 0.66, rate: 0.045, peak: 0.34 });
    [[67, 0.7, 0.1], [67, 0.82, 0.1], [72, 0.94, 0.2], [67, 1.18, 0.1], [76, 1.3, 0.6]].forEach(([m, x, d]) => brass(dest, t + x, { f: mtof(m), dur: d, peak: 0.14, bright: 1.2 }));
    timpani(dest, t + 1.3, { f: mtof(48), dur: 1, peak: 0.4 });
    return crash(dest, t + 1.3, { peak: 0.08, dur: 1.2 });
  }, WORLD_TV),

  // Truckers!: a bluesy harmonica lick, then HONK-HONK.
  jingle_m60: withProps((a, dest, o) => {
    const t = o.t, sd = 0.125;
    line(harmonica, dest, t, seq('A4@0:2 C5@2:1 D5@3:1 Eb5@4:1 E5@5:3 C5@8:1 A4@9:2'), sd, 0.2, { bend: 90 });
    line(kick, dest, t, seq('C2@0:1 C2@4:1 C2@8:1'), sd, 0.6);
    line(snare, dest, t, seq('C2@2:1 C2@6:1 C2@10:1'), sd, 0.25);
    airHorn(dest, t + 12 * sd, { f: 220, dur: 0.2, peak: 0.3 });
    return airHorn(dest, t + 14.5 * sd, { f: 220, dur: 0.45, peak: 0.3 });
  }, WORLD_TV),

  // Saturday Morning Cartoons: a square-wave run, a slide-whistle boing and a "ta-da".
  jingle_tiny_tele: withProps((a, dest, o) => {
    const t = o.t;
    ch('C5 D5 E5 G5 A5 C6').forEach((m, k) => sqLead(dest, t + k * 0.05, { f: mtof(m), dur: 0.06, peak: 0.12 }));
    whistle(dest, t + 0.34, { from: 700, to: 1600, dur: 0.26, peak: 0.14 });
    chordAt(sqLead, dest, t + 0.66, ch('C5 E5 G5'), 0.1, 0.07);
    snare(dest, t + 0.8, { peak: 0.3 });
    return chordAt(sqLead, dest, t + 0.8, ch('C5 E5 G5 C6'), 0.5, 0.07);
  }, WORLD_TV),

  // Space Patrol 3000: a theremin "woo-ooo" over sci-fi blips.
  jingle_zapper: withProps((a, dest, o) => {
    const t = o.t;
    for (let k = 0; k < 7; k++) synth.tone(dest, t + 0.1 + k * 0.19, { f: 1800 + ((k * 677) % 1500), f1: 3600, dur: 0.07, peak: 0.05, a: 0.001, curve: 'fast' });
    chordAt(strings, dest, t, ch('C4 E4 F#4 B4'), 1.8, 0.04, { a: 0.4 });
    return theremin(dest, t, { notes: [[mtof(67), 0.15], [mtof(79), 0.4], [mtof(76), 0.25], [mtof(84), 0.8]], porta: 0.12, vib: 40, peak: 0.26 });
  }, WORLD_TV),

  // The Groove Hour: disco kick and hats, string stabs, a run up and an Am9 stab.
  jingle_boom_mic: withProps((a, dest, o) => {
    const t = o.t, sd = 0.125;
    for (let s = 0; s < 16; s += 4) kick(dest, t + s * sd, { peak: 0.7 });
    for (let s = 2; s < 16; s += 4) hatOpen(dest, t + s * sd, { peak: 0.12 });
    line(slap, dest, t, seq('A2@0:1 A3@2:1 A2@4:1 A3@6:1 G2@8:1 G3@10:1 E2@12:1 E3@14:1'), sd, 0.4);
    chordAt(strings, dest, t, ch('A4 C5 E5'), 0.18, 0.08, { a: 0.01 });
    chordAt(strings, dest, t + 3 * sd, ch('A4 C5 E5'), 0.18, 0.08, { a: 0.01 });
    line(strings, dest, t, seq('A4@6:1 B4@7:1 C5@8:1 D5@9:1 E5@10:1 G5@11:1'), sd, 0.1, { a: 0.02 });
    return chordAt(strings, dest, t + 12 * sd, ch('G4 A4 C5 E5 B5'), 0.9, 0.07, { a: 0.02 });
  }, WORLD_TV),

  // Weather Watch 13: a smooth jazzy vibraphone line over brushes and bass.
  jingle_chroma_key: withProps((a, dest, o) => {
    const t = o.t, sd = 0.139;
    line(vibes, dest, t, seq('E4@0:2 G4@2:2 B4@4:2 D5@6:2 C5@8:1 A4@9:1 B4@10:6'), sd, 0.3);
    line(upright, dest, t, seq('C3@0:4 A2@4:4 D3@8:2 G2@10:4'), sd, 0.6);
    for (const s of [4, 12]) brush(dest, t + s * sd, { peak: 0.1 });
    return chordAt(vibes, dest, t + 10 * sd, ch('E4 G4 D5'), 1.4, 0.12);
  }, WORLD_TV),

  // ---- sponsors: 1 s positional teasers from each set, 3 s commercial jingles ----
  sponsor_teaser_replay_ade: withProps((a, dest, o) => {
    swoosh(dest, o.t, { dur: 0.4, peak: 0.16 });
    timpani(dest, o.t + 0.4, { f: mtof(46), dur: 0.6, peak: 0.4 });
    return chordAt(brass, dest, o.t + 0.4, ch('Bb4 D5 F5'), 0.5, 0.08);
  }, WORLD),
  sponsor_jingle_replay_ade: (a, dest, o) => {
    const t = o.t, sd = 0.114, f0 = t + 0.35;
    wet(dest, o);
    swoosh(dest, t, { dur: 0.35, peak: 0.16 });
    line(brass, dest, f0, seq('Bb4@0:1 D5@1:1 F5@2:1 Bb5@3:5'), sd, 0.12);
    line(brass, dest, f0, seq('F4@0:1 Bb4@1:1 D5@2:1 F5@3:5'), sd, 0.08);
    roll(snare, dest, f0, { dur: 0.34, rate: 0.04, peak: 0.25 });
    timpani(dest, f0 + 3 * sd, { f: mtof(46), dur: 1, peak: 0.4 });
    swoosh(dest, t + 1.62, { dur: 0.36, peak: 0.14 });
    chordAt(brass, dest, t + 2, ch('Eb5 G5 Bb5'), 0.26, 0.08);
    timpani(dest, t + 2.3, { f: mtof(46), dur: 0.8, peak: 0.45 });
    crash(dest, t + 2.3, { peak: 0.08, dur: 1 });
    return chordAt(brass, dest, t + 2.3, ch('D5 F5 Bb5'), 0.62, 0.09);
  },

  sponsor_teaser_wobble_up: withProps((a, dest, o) => {
    tuba(dest, o.t, { f: mtof(41), dur: 0.3, peak: 0.5, wobble: 40 });
    tuba(dest, o.t + 0.34, { f: mtof(36), dur: 0.26, peak: 0.5, wobble: 40 });
    whistle(dest, o.t + 0.66, { from: 400, to: 900, dur: 0.3, peak: 0.08 });
    return tuba(dest, o.t + 0.64, { f: mtof(41), dur: 0.36, peak: 0.55, wobble: 130, wobbleRate: 9 });
  }, WORLD),
  sponsor_jingle_wobble_up: (a, dest, o) => {
    const t = o.t, sd = 0.125;
    wet(dest, o);
    line(tuba, dest, t, seq('F2@0:2 C2@2:2 F2@4:2 A2@6:2 Bb2@8:2 A2@10:2 G2@12:2 C2@14:2'), sd, 0.45, { wobble: 30 });
    line(glock, dest, t, seq('F5@0:2 A5@2:2 C6@4:4 A5@8:2 G5@10:2 C6@12:4'), sd, 0.14);
    for (let s = 2; s < 16; s += 4) block(dest, t + s * sd, { f: 1000, peak: 0.2 });
    tuba(dest, t + 16 * sd, { f: mtof(41), dur: 0.2, peak: 0.5, wobble: 40 });
    tuba(dest, t + 18 * sd, { f: mtof(41), dur: 0.2, peak: 0.5, wobble: 40 });
    whistle(dest, t + 20 * sd, { from: 400, to: 1100, dur: 0.4, peak: 0.09 });
    return tuba(dest, t + 20 * sd, { f: mtof(53), dur: 0.5, peak: 0.55, wobble: 150, wobbleRate: 9 });
  },

  sponsor_teaser_jump_cut: withProps((a, dest, o) => {
    const t = o.t, gate = synth.gain(dest, 1);
    line(upright, gate, t, seq('D3@0:2 F3@2:2 A3@4:2 C4@6:2'), 0.107, 0.6);
    brush(gate, t, { peak: 0.1 });
    brush(gate, t + 0.43, { peak: 0.1 });
    cut(gate.gain, t + 0.43);
    snip(dest, t + 0.43, { peak: 0.3 });
    return t + 1;
  }, WORLD),
  // Jazzy upright bass and brushes, abruptly jump-cut three times.
  sponsor_jingle_jump_cut: (a, dest, o) => {
    const t = o.t, sd = 0.1, gate = synth.gain(dest, 1);
    wet(dest, o);
    line(upright, gate, t, seq('D2@0:4 F2@4:4 A2@8:4 C3@12:4 B2@16:4 G2@20:4 E2@24:4 A2@28:4'), sd, 0.7);
    for (let s = 4; s < 32; s += 8) brush(gate, t + s * sd, { peak: 0.12 });
    for (let s = 0; s < 32; s += 4) hat(gate, t + s * sd, { peak: 0.07 });
    chordAt(vibes, gate, t, ch('F4 A4 C5 E5'), 1.2, 0.1);
    chordAt(vibes, gate, t + 24 * sd, ch('G4 C#5 E5'), 1.2, 0.1);
    for (const x of [0.8, 1.6, 2.3]) { cut(gate.gain, t + x); snip(dest, t + x, { peak: 0.3 }); }
    return chordAt(vibes, gate, t + 28 * sd, ch('F4 A4 D5'), 0.9, 0.1);
  },

  sponsor_teaser_roller_boogie: withProps((a, dest, o) => {
    const t = o.t;
    for (let s = 0; s < 8; s++) hat(dest, t + s * 0.06, { peak: s & 1 ? 0.06 : 0.1 });
    kick(dest, t, { peak: 0.6 });
    kick(dest, t + 0.48, { peak: 0.6 });
    swoop(dest, t + 0.05, { f: mtof(79), dur: 0.5, peak: 0.05 });
    return chordAt(strings, dest, t + 0.5, ch('G4 B4 D5'), 0.5, 0.07, { a: 0.02 });
  }, WORLD),
  sponsor_jingle_roller_boogie: (a, dest, o) => {
    const t = o.t, sd = 0.121;
    wet(dest, o);
    for (let s = 0; s < 24; s += 4) kick(dest, t + s * sd, { peak: 0.72 });
    for (let s = 4; s < 24; s += 8) clap(dest, t + s * sd, { peak: 0.3 });
    for (let s = 0; s < 24; s++) (s % 4 === 2 ? hatOpen : hat)(dest, t + s * sd, { peak: s % 4 === 2 ? 0.1 : 0.07 });
    line(slap, dest, t, seq('G2@0:1 G3@2:1 G2@4:1 G3@6:1 C3@8:1 C4@10:1 C3@12:1 C4@14:1 D3@16:1 D4@18:1 D3@20:1 F#3@22:1'), sd, 0.4);
    swoop(dest, t, { f: mtof(79), dur: 0.5, peak: 0.05 });
    swoop(dest, t + 16 * sd, { f: mtof(81), dur: 0.5, peak: 0.05 });
    chordAt(strings, dest, t + 4 * sd, ch('G4 B4 D5'), 0.5, 0.06, { a: 0.03 });
    chordAt(strings, dest, t + 12 * sd, ch('G4 C5 E5'), 0.5, 0.06, { a: 0.03 });
    line(glock, dest, t + 22 * sd, seq('G5@0:1 B5@1:1 D6@2:1 G6@3:2'), 0.06, 0.12);
    return chordAt(strings, dest, t + 20 * sd, ch('F#4 A4 D5'), 0.9, 0.06, { a: 0.03 });
  },

  sponsor_teaser_double_vision: withProps((a, dest, o) => {
    const t = o.t, e = synth.echo(dest, { time: 0.08, feedback: 0.3, wet: 0.45 });
    duet(e, t, [[73, 0.15], [81, 0.34]], [[69, 0.15], [76, 0.34]], 0.24);
    return glock(dest, t + 0.62, { f: mtof(93), peak: 0.16 });
  }, WORLD),
  // A bright two-voice harmony "ba-da-ba" with an 80 ms echo, finishing on the smile "ting".
  sponsor_jingle_double_vision: (a, dest, o) => {
    const t = o.t, sd = 0.125, e = synth.echo(dest, { time: 0.08, feedback: 0.32, wet: 0.45 });
    wet(dest, o);
    const top = seq('E5@0:2 A5@2:2 G#5@4:2 E5@6:2 F#5@8:2 E5@10:2 C#5@12:4');
    const low = seq('C#5@0:2 F#5@2:2 E5@4:2 C#5@6:2 D5@8:2 C#5@10:2 A4@12:4');
    duet(e, t, top.map(([m, , l]) => [m, l * sd]), low.map(([m, , l]) => [m, l * sd]), 0.24);
    line(upright, dest, t, seq('A2@0:4 E2@4:4 D3@8:4 A2@12:4'), sd, 0.42);
    for (const s of [4, 12]) clap(dest, t + s * sd, { peak: 0.18 });
    glock(dest, t + 2.35, { f: mtof(93), peak: 0.16 });
    return synth.tone(dest, t + 2.38, { f: 5200, dur: 0.5, peak: 0.04, a: 0.001, trem: 0.6, tremRate: 18 });
  },

  // ---- the Uplink (from the dish) ----
  // R, G and B oscillators rise into a C-E-G triad.
  uplink_triad: withProps((a, dest, o) => {
    const t = o.t, lp = synth.filter(dest, 'lowpass', 2400, 0.7);
    let end = t;
    ch('C4 E4 G4').forEach((m, k) => {
      const t0 = t + k * 0.25, f = mtof(m), q = { f: f / 2, f1: f, glide: 0.42, dur: 1.35 - k * 0.25, hold: 0.8 - k * 0.25, a: 0.08, vib: 8, vibRate: 5 };
      synth.tone(lp, t0, { ...q, type: 'sawtooth', peak: 0.06 });
      end = Math.max(end, synth.tone(dest, t0, { ...q, peak: 0.1 }));
    });
    return end;
  }, WORLD),
  // A theremin melody over a funk bass line and soft strings while the aurora unfurls.
  uplink_aurora: withProps((a, dest, o) => {
    const t = o.t, sd = 0.15;
    line(slap, dest, t, seq('C2@0:1.5! C3@3:.5! Bb2@4:1 G2@6:1 C2@8:1 Eb2@10:1 E2@11:1 G2@12:2 C3@14:1'), sd, 0.42);
    for (let s = 2; s < 16; s += 2) hat(dest, t + s * sd, { peak: 0.07 });
    chordAt(strings, dest, t, ch('E4 G4 B4 D5'), 2.4, 0.04, { a: 0.5 });
    return theremin(dest, t + 0.05, { notes: [[mtof(67), 0.3], [mtof(72), 0.5], [mtof(76), 0.45], [mtof(74), 0.35], [mtof(79), 0.7]], porta: 0.1, vib: 32, peak: 0.24 });
  }, WORLD),
  // The downlink: the station motif on the bells over applause.
  uplink_fanfare: withProps((a, dest, o) => {
    synth.applause(dest, o.t + 0.25, { dur: 3.6, peak: 0.22, a: 0.5 });
    return bells(dest, o.t, MOTIF, 0.34);
  }, WORLD),

  // ---- loops and beds ----
  pu_bossa_bed: songCue({ ...BOSSA, gain: 0.3 }, { len: 8 }),
  tele_cartoon: withProps(songCue(CARTOON), WORLD_TV),
  toy_radio: withProps(songCue(RADIO, { bars: 8 }), WORLD_TV),

  // Three puppets sing a 6 s kazoo trio (melody, a third below, and an oom-pah bass kazoo).
  ee_kazoo_song: withProps((a, dest, o) => {
    const t = o.t, sd = 0.1;
    line(kazoo, dest, t, seq('F4@0:4 A4@4:4 C5@8:4 A4@12:4 Bb4@16:4 G4@20:4 E4@24:4 G4@28:4 A4@32:2 Bb4@34:2 C5@36:4 D5@40:2 C5@42:2 A4@44:4 C5@48:3 F5@51:9'), sd, 0.28, { vib: 22 }, 0, 0.9);
    line(kazoo, dest, t, seq('C4@0:4 F4@4:4 A4@8:4 F4@12:4 G4@16:4 E4@20:4 C4@24:4 E4@28:4 F4@32:2 G4@34:2 A4@36:4 Bb4@40:2 A4@42:2 F4@44:4 A4@48:3 C5@51:9'), sd, 0.2, { vib: 18, formant: 1100 }, 0, 0.9);
    line(kazoo, dest, t, seq('F3@0:3 C3@4:3 F3@8:3 C3@12:3 C3@16:3 G3@20:3 C3@24:3 G3@28:3 F3@32:3 C3@36:3 Bb2@40:3 C3@44:3 F3@48:3 F3@51:9'), sd, 0.2, { vib: 14, formant: 900 }, 0, 0.9);
    for (let s = 4; s < 48; s += 8) clap(dest, t + s * sd, { peak: 0.12, f: 2200 });
    return t + 6.1;
  }, WORLD),

  // A random 3-note tune (opts.notes to force MIDI notes) on the Studio B xylophone.
  toy_xylophone: withProps((a, dest, o) => {
    const pool = ch('C5 D5 E5 G5 A5 C6'), notes = o.notes || [0, 1, 2].map(() => pool[(Math.random() * pool.length) | 0]);
    let end = o.t;
    notes.forEach((m, k) => { end = Math.max(end, xylo(dest, o.t + k * 0.18, { f: mtof(m), peak: k === 2 ? 0.4 : 0.34 })); });
    return end;
  }, WORLD),
};

// Hard edit: the cue drops out for 70 ms (3 ms ramps keep it click-free but abrupt).
function cut(g, tc) {
  g.setValueAtTime(1, tc);
  g.linearRampToValueAtTime(0, tc + 0.003);
  g.setValueAtTime(0, tc + 0.07);
  g.linearRampToValueAtTime(1, tc + 0.073);
}

// Two formant "ba-da" voices singing parallel lines ([midi, seconds] each).
function duet(dest, t, top, low, peak) {
  const sing = (notes, pk, v) => synth.formant(dest, t, {
    base: mtof(notes[0][0]), peak: pk, v, vib: 16, wahLo: 700, wahHi: 3000, gap: 0.02,
    syl: notes.map(([m, d], k) => ({ d: d - 0.02, p: mtof(m) / mtof(notes[0][0]), v: k & 1 ? 'oo' : 'a' })),
  });
  sing(low, peak * 0.8, 'a');
  return sing(top, peak, 'a');
}

// ------------------------------------------------------------------------------------------------
// Music states
// ------------------------------------------------------------------------------------------------

// fade: fade-in of the new state and fade-out of the previous one (seconds); no song = music off.
const STATES = {
  title: { song: TITLE, fade: 1.5 },
  select: { fade: 0.25, delay: 0.14 },
  ambient: { fade: 2.5 },
  round: { song: ROUND, fade: 2 },
  intermission: { song: BOSSA, fade: 1.2 },
  hullabaloo: { song: HULLABALOO, fade: 0.8 },
  boss: { song: BOSS, fade: 0.6 },
  credits: { song: CREDITS, fade: 0.5 },
  morning: { song: MORNING, fade: 2.5 },
  silence: { fade: 0.04 },
};

// Procedural plate for the music bus (the area reverb of audio.js is for the world only).
function plate(ac) {
  const sr = ac.sampleRate, len = Math.floor(sr * 1.7), buf = ac.createBuffer(2, len, sr);
  for (let c = 0; c < 2; c++) {
    const d = buf.getChannelData(c);
    let lp = 0;
    for (let i = 0; i < len; i++) {
      const tt = i / sr;
      lp += ((Math.random() * 2 - 1) - lp) * (0.75 - 0.5 * Math.min(1, tt / 1.7));
      d[i] = lp * Math.exp((-6.9 * tt) / 1.6) * (i < sr * 0.01 ? i / (sr * 0.01) : 1);
    }
  }
  return buf;
}

export function createMusic(audio) {
  const ac = audio.ctx;
  const tapeIn = ac.createGain(), tape = ac.createDelay(1), tapeOut = ac.createGain();
  tape.delayTime.value = 0;
  tapeIn.connect(tape); tape.connect(tapeOut); tapeOut.connect(audio.bus.music);
  const verb = ac.createConvolver();
  verb.buffer = plate(ac);
  verb.connect(audio.bus.music);
  const stingSend = synth.gain(verb, 0.14);
  const fading = new Set();
  let cur = null;          // { id, key, player }
  let hero = 'duke';       // GDD §4: Duke is the default / preselected hero
  let intensity = 1;
  let clavWant = false, clavSince = 0;

  function start(song, fade, delay, vars) {
    const now = ac.currentTime;
    const p = new Player(ac, song, tapeIn, { t0: now + delay, fade, vars });
    p.out.connect(synth.gain(verb, song.verb ?? 0.1));
    p.pump(now + horizon());
    return p;
  }

  function setState(id) {
    const [base, arg] = String(id).split(':');
    const def = STATES[base];
    if (!def) return;
    if (base === 'boss' && cur && cur.id === 'boss') { if (arg) setIntensity(+arg); return; }
    if (base === 'select' && SELECT[arg]) hero = arg;
    const key = base === 'select' ? 'select:' + hero : base;
    if (cur && cur.key === key) return;
    const now = ac.currentTime;
    if (cur && cur.player) { cur.player.stopAt(now, def.fade); fading.add(cur.player); }
    if (base === 'boss') intensity = Math.min(3, Math.max(1, +arg || 1));
    const song = base === 'select' ? SELECT[hero] : def.song;
    if (base === 'select') clack(tapeIn, now + 0.005, { peak: 0.3 });
    clavWant = false;
    cur = { id: base, key, player: song ? start(song, def.fade, def.delay ?? 0.03, { intensity }) : null };
  }

  function setIntensity(n) {
    intensity = Math.min(3, Math.max(1, Math.round(+n) || 1));
    const p = cur && cur.id === 'boss' ? cur.player : null;
    if (!p) return;
    p.vars.intensity = intensity;
    p.setLayer('p2', intensity >= 2, 1);
    p.setLayer('p3', intensity >= 3, 1);
  }

  // round/morning: follow the living-zombie count with a little hysteresis.
  function adapt(p, now) {
    const z = audio.game && audio.game.zombies, n = z && z.alive ? z.alive.length : 0;
    const want = n > CLAV_ZOMBIES;
    if (want !== clavWant) { clavWant = want; clavSince = now; }
    if (p.L.clav.on !== want && now - clavSince > (want ? 0.4 : 4)) p.setLayer('clav', want, want ? 1.5 : 3);
  }

  function update() {
    const now = ac.currentTime, h = now + horizon();
    const p = cur && cur.player;
    if (p) {
      if (p.song.adaptive) adapt(p, now);
      if (!p.pump(h)) cur.player = null;
    }
    for (const f of fading) if (!f.pump(h)) fading.delete(f);
  }

  function stop() {
    const now = ac.currentTime;
    for (const f of fading) f.stopAt(now, 0.05);
    if (cur && cur.player) { cur.player.stopAt(now, 0.05); fading.add(cur.player); }
    cur = null;
  }

  // Tape stop: a delay line whose delay grows as t²/2D slows playback linearly to zero over `dur`.
  function tapeStop(t, dur = 1.2) {
    const p = cur && cur.player;
    if (!p) return;
    const n = 48, curve = new Float32Array(n);
    for (let i = 0; i < n; i++) { const x = (i / (n - 1)) * dur; curve[i] = (x * x) / (2 * dur); }
    tape.delayTime.cancelScheduledValues(t);
    tape.delayTime.setValueCurveAtTime(curve, t, dur);
    holdAt(tapeOut.gain, t);
    tapeOut.gain.setValueAtTime(1, t + dur * 0.5);
    tapeOut.gain.linearRampToValueAtTime(0, t + dur);
    tape.delayTime.setValueAtTime(0, t + dur + 0.08);
    tapeOut.gain.setValueAtTime(1, t + dur + 0.12);
    p.stopAt(t + dur, 0.02);
    fading.add(p);
    cur = { id: 'silence', key: 'silence', player: null };
  }

  function beat() {
    const p = cur && cur.player;
    return p ? { bpm: p.song.bpm, beat: p.beat(ac.currentTime) } : null;
  }

  engines.set(ac, { tapeStop, stingSend });
  audio.registerCues(MUSIC_CUES);
  return { setState, setIntensity, update, stop, tapeStop, beat, get state() { return cur ? cur.id : null; } };
}
