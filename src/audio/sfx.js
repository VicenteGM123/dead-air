// DEAD AIR — sfx.js
// Owns two things:
//   1. `synth`: the WebAudio instrument / voice toolkit (GDD §15 instrument recipes). It is the `a`
//      argument every cue recipe receives, and audio.js re-exports it so music.js can
//      `import { synth } from './audio.js'` (it lives here, below every import cycle, so it is safe to
//      use even at music.js module top level).
//   2. `SFX_CUES`: the synthesized recipe of every non-musical cue id of GDD §15 / §18.16.
//
// synth conventions
//   - Voice builders are `(dest, t, p)`: dest = AudioNode to connect into (dest.context is used),
//     t = start time in context seconds, p = params. One-shot builders return their END time (s).
//   - `peak` is linear amplitude (0..1), frequencies are Hz, durations seconds. Every envelope starts
//     and ends at exactly 0 (click free) and every source node is stopped, so voices clean themselves up.
//   - Buffers (noise, applause) are cached per sample rate; PeriodicWaves per context.
//
// synth API
//   utils     mtof(midi) note('G4') rnd(a,b) pick(arr) db(dB) clamp(x,a,b) VOWELS
//   nodes     gain(dest,v)  filter(dest,type,f,q,gainDb)  shaper(dest,drive)  panner(dest,pan)
//             echo(dest,{time,feedback,wet,lp}) -> input node (dry + filtered feedback echo)
//             noiseBuffer(ac,'white'|'pink'|'brown')  pulseWave(ac,duty)  softCurve(drive)
//             osc(ac,type,f,t,end=Infinity)  noiseSrc(ac,color,t,end=Infinity,rate)  (started sources for loops)
//   params    env(param,t,{a,hold,dur,peak,curve:'exp'|'fast'|'lin'}) -> end
//             glide(param,t,f0,f1,dur,curve)  lfo(ac,param,t,end,{rate,depth,type,delay})
//             release(param,t,r)  (for sustained voices)
//   sources   tone(dest,t,{type|wave,f,f1,glide,glideDelay,dur,a,hold,curve,peak,detune,vib,vibRate,trem,tremRate})
//             noise(dest,t,{color,dur,a,hold,curve,peak,type,f,f1,q,glide,hp,lp,rate})
//             click(dest,t,{f,peak,dur})
//   voices    fmBell(dest,t,{f,dur,ratio=3.5,index,peak})
//             formant(dest,t,{base,syl:[{d,p,p1,v,g,gap,at,rl}],peak,ring,vib,vibRate,breath,wahLo,wahHi,buzz,q})
//               'wah-wah' voice: sawtooth (optionally ring-modulated) through vowel formants + a per-syllable
//               opening lowpass; syllable pitch = base·p gliding to base·p1, vowels in VOWELS
//             crowd(dest,t,{vowel:'oo'|'aw',dur,voices,peak,pitch})
//             applause(dest,t,{dur,peak,a,thick})   laughter(dest,t,{dur,voices,peak,pitch})
//             kazoo(dest,t,{f,f1,dur,peak,vib})      slideWhistle(dest,t,{from,to,dur,peak})
//             theremin(dest,t,{notes:[[f,dur],...],peak,porta,vib})   musicBox(dest,t,{f,dur,peak})
//   drums     kick snare hat({open}) clap woodblock rim     (dest,t,{peak,...})
//   pitched   slapBass clav brass strings organ({bars}) vibraphone epiano pluck   (dest,t,{f,dur,peak,...})
//             chord(builder,dest,t,freqs,p) -> end
//   timing    sequencer(t0,step,fn(tStep,i)->nextStep?,lookahead) -> { update(now), stop() }
//
// SFX_CUES conventions (recipe contract: audio.js registerCues)
//   - Every non-musical id of GDD §18.16 (the music-owned ones live in music.js) plus a fallback
//     telly_wonder_tada / toy_xylophone that music.js may override. Grouped per GDD §15 row below.
//   - Static routing props via cue(): bus ('ui' for UI, 'ambience' for amb_*, 'tv' for the studio audience
//     and the announcer), tv (TV-speaker filter: announcer, Baron, screen static, Laff-O-Matic), zombie
//     (HRTF candidates), range, ref, wet, limit, gap. `loopable` marks cues that honour audio.loop():
//     inherent loops (telly_hum, amb_*, pu_idle, bs_roll, skate_roll, wpn_boom_record, ee_storm_loop,
//     ee_tracking_tones) always return an endless handle; dish_crank, uplink_motor and boss_static_ball
//     are one-shots under play() (opts.dur) and endless under loop(). heartbeat is one beat period, which
//     audio.loop() chains.
//   - Extra play options: upgraded (fire cues), rhythm (announcer_wahwah: pitch per syllable), base
//     (hurt_grunt: hero voice Hz), foot (step_*), flip (pu_sweeps_week small ching), dur (tele_tick,
//     tone_1khz, ee_alarm_bell, crowd_applause/laugh), d (ee_tracking_tones start distance), syllables
//     (boss_voice), notes (toy_xylophone, MIDI), period (heartbeat), claps + dur (ee_applause_near: the EE
//     gloves' clap beats in s, [] = none). rate/detune scale the main pitches.
//   - EE step 3 applause (easteregg.js routing): per counted kill ee_applause_near (non-positional, sfx bus: the
//     close crowd + the gloves' claps) + ee_applause_burst at both bleachers (tv bus, linear rolloff to 45 m, extra
//     reverb send); ee_ovation / ee_tote_flip also roll off linearly (45 m / 30 m).
//   - ee_tracking_tones handle: setDistance(d) glides the second sine to 440 + 2.5·d Hz.
//   - Levels: peaks at the master input stay under ~0.95 (big hits ~0.9, guns ~0.8, voices ~0.6, UI and
//     footsteps 0.1–0.4, ambience ~0.1); staging/audio/test renders and checks every cue.

// ------------------------------------------------------------------------------------------------
// Toolkit
// ------------------------------------------------------------------------------------------------

const bufCache = new Map();        // sampleRate -> { key: AudioBuffer }
const waveCache = new WeakMap();   // context -> { key: PeriodicWave }
const curveCache = new Map();      // drive -> Float32Array

const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const rnd = (a = 0, b = 1) => a + Math.random() * (b - a);
const pick = (arr) => arr[(Math.random() * arr.length) | 0];
const db = (d) => Math.pow(10, d / 20);
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);
const NOTE_IDX = { c: 0, d: 2, e: 4, f: 5, g: 7, a: 9, b: 11 };
function note(name) {
  const m = /^([a-gA-G])(#|b)?(-?\d)$/.exec(name);
  if (!m) return 440;
  const semi = NOTE_IDX[m[1].toLowerCase()] + (m[2] === '#' ? 1 : m[2] === 'b' ? -1 : 0);
  return mtof((+m[3] + 1) * 12 + semi);
}

// Formants (F1, F2, F3) per vowel.
const VOWELS = {
  a: [800, 1200, 2500], aw: [700, 1100, 2400], o: [480, 850, 2400], oo: [300, 870, 2250],
  u: [350, 700, 2400], uh: [620, 1150, 2400], e: [450, 1900, 2600], eh: [560, 1720, 2500],
  i: [320, 2200, 2900], ee: [280, 2350, 3000], m: [260, 1100, 2300],
};

function bufStore(sr) {
  let s = bufCache.get(sr);
  if (!s) bufCache.set(sr, (s = Object.create(null)));
  return s;
}
function waveStore(ac) {
  let s = waveCache.get(ac);
  if (!s) waveCache.set(ac, (s = Object.create(null)));
  return s;
}

// Small node factories (internal).
function G(ac, v = 1, dest) {
  const g = ac.createGain();
  g.gain.value = v;
  if (dest) g.connect(dest);
  return g;
}
function F(ac, type, f, q, dest) {
  const n = ac.createBiquadFilter();
  n.type = type;
  n.frequency.value = f;
  if (q != null) n.Q.value = q;
  if (dest) n.connect(dest);
  return n;
}
function O(ac, type, f) {
  const o = ac.createOscillator();
  if (typeof type === 'string') o.type = type;
  else o.setPeriodicWave(type);
  o.frequency.value = f;
  return o;
}
function N(ac, color, t, end, rate = 1) {
  const s = ac.createBufferSource();
  s.buffer = noiseBuffer(ac, color);
  s.loop = true;
  s.playbackRate.value = rate;
  s.start(t, Math.random() * 2);
  if (end !== Infinity) s.stop(end + 0.02);
  return s;
}

// Started sources for loops (end = Infinity leaves them running until stopped).
function osc(ac, type, f, t, end = Infinity) {
  const o = O(ac, type, f);
  o.start(t);
  if (end !== Infinity) o.stop(end + 0.02);
  return o;
}
const noiseSrc = (ac, color, t, end = Infinity, rate = 1) => N(ac, color, t, end, rate);

function noiseBuffer(ac, color = 'white') {
  const s = bufStore(ac.sampleRate), key = 'noise_' + color;
  if (s[key]) return s[key];
  const sr = ac.sampleRate, len = Math.floor(sr * 2.5), fade = Math.floor(sr * 0.02);
  const tmp = new Float32Array(len + fade);
  let b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0, br = 0;
  for (let i = 0; i < tmp.length; i++) {
    const w = Math.random() * 2 - 1;
    if (color === 'pink') {
      b0 = 0.99886 * b0 + w * 0.0555179; b1 = 0.99332 * b1 + w * 0.0750759; b2 = 0.969 * b2 + w * 0.153852;
      b3 = 0.8665 * b3 + w * 0.3104856; b4 = 0.55 * b4 + w * 0.5329522; b5 = -0.7616 * b5 - w * 0.016898;
      tmp[i] = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362;
      b6 = w * 0.115926;
    } else if (color === 'brown') {
      br = (br + 0.02 * w) / 1.02;
      tmp[i] = br;
    } else tmp[i] = w;
  }
  // Crossfade the continuation into the head so the loop seam is inaudible.
  for (let i = 0; i < fade; i++) { const k = i / fade; tmp[i] = tmp[i] * k + tmp[len + i] * (1 - k); }
  let mean = 0, sum = 0;
  for (let i = 0; i < len; i++) mean += tmp[i];
  mean /= len;
  for (let i = 0; i < len; i++) sum += (tmp[i] - mean) * (tmp[i] - mean);
  const g = 0.3 / Math.sqrt(sum / len);
  const buf = ac.createBuffer(1, len, sr), d = buf.getChannelData(0);
  for (let i = 0; i < len; i++) d[i] = clamp((tmp[i] - mean) * g, -1, 1);
  return (s[key] = buf);
}

// Stereo clap texture (~45 claps/s per channel), synthesized sample by sample once per sample rate.
function clapBuffer(ac) {
  const s = bufStore(ac.sampleRate);
  if (s.claps) return s.claps;
  const sr = ac.sampleRate, len = Math.floor(sr * 3), fade = Math.floor(sr * 0.03);
  const buf = ac.createBuffer(2, len, sr);
  for (let c = 0; c < 2; c++) {
    const tmp = new Float32Array(len + fade);
    const count = Math.floor(3 * 45);
    for (let k = 0; k < count; k++) {
      const start = Math.floor(Math.random() * len), f = rnd(900, 2600), bw = rnd(500, 1200);
      const r = Math.exp(-Math.PI * bw / sr), a1 = -2 * r * Math.cos(2 * Math.PI * f / sr), a2 = r * r;
      const n = Math.floor(sr * rnd(0.008, 0.02)), tau = sr * rnd(0.002, 0.005), amp = rnd(0.4, 1);
      let y1 = 0, y2 = 0;
      for (let i = 0; i < n; i++) {
        const x = (Math.random() * 2 - 1) * Math.exp(-i / tau) * amp;
        const y = x * (1 - r) - a1 * y1 - a2 * y2;
        y2 = y1; y1 = y;
        tmp[start + i] += y;
      }
    }
    for (let i = 0; i < fade; i++) { const k = i / fade; tmp[i] = tmp[i] * k + tmp[len + i] * (1 - k); }
    let peak = 0;
    for (let i = 0; i < len; i++) peak = Math.max(peak, Math.abs(tmp[i]));
    const d = buf.getChannelData(c), g = 0.9 / (peak || 1);
    for (let i = 0; i < len; i++) d[i] = tmp[i] * g;
  }
  return (s.claps = buf);
}

function softCurve(drive = 2) {
  const key = Math.round(drive * 100);
  let c = curveCache.get(key);
  if (c) return c;
  c = new Float32Array(1024);
  const norm = Math.tanh(drive);
  for (let i = 0; i < 1024; i++) { const x = (i / 1023) * 2 - 1; c[i] = Math.tanh(drive * x) / norm; }
  curveCache.set(key, c);
  return c;
}

function pulseWave(ac, duty = 0.25) {
  const s = waveStore(ac), key = 'pulse' + duty;
  if (s[key]) return s[key];
  const n = 48, re = new Float32Array(n), im = new Float32Array(n);
  for (let k = 1; k < n; k++) re[k] = (2 * Math.sin(Math.PI * k * duty)) / (Math.PI * k);
  return (s[key] = ac.createPeriodicWave(re, im));
}

// Attack -> hold -> decay to silence, ending at exactly t + dur. Returns the end time.
function env(param, t, p = {}) {
  const peak = p.peak ?? 1, a = Math.max(0, p.a ?? 0.004);
  const dur = Math.max(p.dur ?? 0.3, a + 0.008);
  const hold = clamp(p.hold ?? 0, 0, dur - a - 0.006);
  const tA = t + a, tH = tA + hold, end = t + dur, curve = p.curve || 'exp';
  if (a > 0) { param.setValueAtTime(0, t); param.linearRampToValueAtTime(peak, tA); } else param.setValueAtTime(peak, t);
  if (hold > 0) param.setValueAtTime(peak, tH);
  if (peak <= 0 || curve === 'lin') param.linearRampToValueAtTime(0, end);
  else if (curve === 'exp') {
    param.exponentialRampToValueAtTime(peak * 1e-3, end - 0.004);
    param.linearRampToValueAtTime(0, end);
  } else {
    const tau = (end - tH) / 6.5, tS = end - 0.005;
    param.setTargetAtTime(0, tH, tau);
    param.setValueAtTime(peak * Math.exp(-(tS - tH) / tau), tS);
    param.linearRampToValueAtTime(0, end);
  }
  return end;
}

function glide(param, t, f0, f1, dur, curve = 'exp') {
  param.setValueAtTime(f0, t);
  if (curve === 'lin' || f0 <= 0 || f1 <= 0) param.linearRampToValueAtTime(f1, t + dur);
  else param.exponentialRampToValueAtTime(f1, t + dur);
}

function lfo(ac, param, t, end, p = {}) {
  const o = O(ac, p.type || 'sine', p.rate ?? 5);
  const g = G(ac, 0);
  const depth = p.depth ?? 10, delay = p.delay ?? 0;
  if (delay > 0) { g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(depth, t + delay); } else g.gain.value = depth;
  o.connect(g).connect(param);
  o.start(t);
  if (end !== Infinity) o.stop(end + 0.02);
  return o;
}

function release(param, t, r = 0.1) {
  if (param.cancelAndHoldAtTime) param.cancelAndHoldAtTime(t);
  else { param.cancelScheduledValues(t); param.setValueAtTime(param.value, t); }
  param.setTargetAtTime(0, t, r / 5);
}

// --- public node helpers ---
const gain = (dest, v = 1) => G(dest.context, v, dest);
const filter = (dest, type, f, q, gainDb) => {
  const n = F(dest.context, type, f, q, dest);
  if (gainDb != null) n.gain.value = gainDb;
  return n;
};
function shaper(dest, drive = 2) {
  const w = dest.context.createWaveShaper();
  w.curve = softCurve(drive);
  w.connect(dest);
  return w;
}
function panner(dest, pan = 0) {
  const p = dest.context.createStereoPanner();
  p.pan.value = pan;
  p.connect(dest);
  return p;
}
// Dry path + a lowpassed feedback echo. Returns the input node.
function echo(dest, p = {}) {
  const ac = dest.context, input = G(ac, 1, dest);
  const dl = ac.createDelay(2);
  dl.delayTime.value = p.time ?? 0.25;
  const lp = F(ac, 'lowpass', p.lp ?? 2600, 0.5);
  const fb = G(ac, p.feedback ?? 0.35);
  input.connect(dl); dl.connect(lp); lp.connect(fb); fb.connect(dl);
  lp.connect(G(ac, p.wet ?? 0.4, dest));
  return input;
}

// --- sources ---
function tone(dest, t, p = {}) {
  const ac = dest.context, dur = p.dur ?? 0.25, f0 = p.f ?? 440;
  const o = O(ac, p.wave || p.type || 'sine', f0);
  o.frequency.setValueAtTime(f0, t);
  if (p.f1 != null && p.f1 !== f0) glide(o.frequency, t + (p.glideDelay ?? 0), f0, p.f1, p.glide ?? dur - (p.glideDelay ?? 0), p.glideCurve);
  if (p.detune) o.detune.value = p.detune;
  const g = G(ac, 0, dest);
  let head = o;
  if (p.trem) {
    const tg = G(ac, 1 - p.trem / 2, g);
    lfo(ac, tg.gain, t, t + dur, { rate: p.tremRate ?? 6, depth: p.trem / 2 });
    o.connect(tg);
    head = null;
  }
  if (head) o.connect(g);
  const end = env(g.gain, t, { a: p.a ?? 0.004, hold: p.hold, dur, peak: p.peak ?? 0.5, curve: p.curve });
  if (p.vib) lfo(ac, o.detune, t, end, { rate: p.vibRate ?? 6, depth: p.vib, delay: p.vibDelay ?? 0 });
  o.start(t);
  o.stop(end + 0.02);
  return end;
}

function noise(dest, t, p = {}) {
  const ac = dest.context, dur = p.dur ?? 0.2;
  const g = G(ac, 0, dest);
  let into = g;
  if (p.lp) into = F(ac, 'lowpass', p.lp, 0.7, into);
  if (p.hp) into = F(ac, 'highpass', p.hp, 0.7, into);
  if (p.type) {
    const f = F(ac, p.type, p.f ?? 1000, p.q ?? 1, into);
    if (p.f1 != null) glide(f.frequency, t, p.f ?? 1000, p.f1, p.glide ?? dur, p.glideCurve);
    into = f;
  }
  const end = env(g.gain, t, { a: p.a ?? 0.002, hold: p.hold, dur, peak: p.peak ?? 0.5, curve: p.curve });
  N(ac, p.color || 'white', t, end, p.rate ?? 1).connect(into);
  return end;
}

function click(dest, t, p = {}) {
  return noise(dest, t, { type: 'bandpass', f: p.f ?? 3000, q: p.q ?? 1.5, dur: p.dur ?? 0.012, peak: p.peak ?? 0.5, a: 0.0005, curve: 'fast' });
}

// --- voices ---
function fmBell(dest, t, p = {}) {
  const ac = dest.context, f = p.f ?? 523.25, dur = p.dur ?? 2.5, ratio = p.ratio ?? 3.5, idx = p.index ?? 4;
  const car = O(ac, 'sine', f), mod = O(ac, 'sine', f * ratio), mg = G(ac, 0), g = G(ac, 0, dest);
  mg.gain.setValueAtTime(f * idx, t);
  mg.gain.exponentialRampToValueAtTime(f * idx * 0.06, t + dur * 0.55);
  mod.connect(mg).connect(car.frequency);
  car.connect(g);
  const end = env(g.gain, t, { a: 0.002, dur, peak: p.peak ?? 0.3, curve: 'exp' });
  const hum = O(ac, 'sine', f * 0.5), hg = G(ac, 0, dest);
  hum.connect(hg);
  env(hg.gain, t, { a: 0.01, dur: dur * 0.8, peak: (p.peak ?? 0.3) * 0.18, curve: 'exp' });
  for (const o of [car, mod, hum]) { o.start(t); o.stop(end + 0.02); }
  return end;
}

function formant(dest, t, p = {}) {
  const ac = dest.context, base = p.base ?? 140, syl = p.syl ?? [{ d: 0.25 }], q = p.q ?? 5;
  const out = G(ac, (p.peak ?? 0.4) * 3.2, dest);
  const amp = G(ac, 0, out);
  const wah = F(ac, 'lowpass', 900, p.wahQ ?? 2.2, amp);
  const sum = G(ac, 1, wah);
  const fa = F(ac, 'bandpass', 800, q, sum);
  const fb = F(ac, 'bandpass', 1200, q * 1.4, G(ac, 0.8, sum));
  const fc = F(ac, 'bandpass', 2500, 8, G(ac, 0.3, sum));
  const src = O(ac, p.wave || 'sawtooth', base);
  const pre = G(ac, 1);
  pre.connect(fa); pre.connect(fb); pre.connect(fc);
  pre.connect(G(ac, p.buzz ?? 0.08, sum));
  let tt = t, first = true;
  const wl = p.wahLo ?? 450, wh = p.wahHi ?? 2600;
  for (const s of syl) {
    const d = Math.max(0.04, s.d ?? 0.2), fm = VOWELS[s.v || p.v || 'a'] || VOWELS.a, lvl = s.g ?? 1;
    const f0 = base * (s.p ?? 1), f1 = base * (s.p1 ?? s.p ?? 1);
    src.frequency.setValueAtTime(f0, tt);
    src.frequency.exponentialRampToValueAtTime(f1, tt + d);
    if (first) { fa.frequency.setValueAtTime(fm[0], tt); fb.frequency.setValueAtTime(fm[1], tt); fc.frequency.setValueAtTime(fm[2], tt); }
    else { fa.frequency.setTargetAtTime(fm[0], tt, 0.02); fb.frequency.setTargetAtTime(fm[1], tt, 0.02); fc.frequency.setTargetAtTime(fm[2], tt, 0.02); }
    const at = s.at ?? Math.min(0.035, d * 0.3), rl = s.rl ?? Math.min(0.07, d * 0.35);
    amp.gain.setValueAtTime(0, tt);
    amp.gain.linearRampToValueAtTime(lvl, tt + at);
    amp.gain.setValueAtTime(lvl, tt + d - rl);
    amp.gain.linearRampToValueAtTime(0, tt + d);
    wah.frequency.setValueAtTime(wl, tt);
    wah.frequency.linearRampToValueAtTime(wh, tt + d * 0.3);
    wah.frequency.linearRampToValueAtTime(wl * 1.2, tt + d);
    tt += d + (s.gap ?? p.gap ?? 0.035);
    first = false;
  }
  const end = tt;
  if (p.ring) {
    const rg = G(ac, 0.3, pre), ro = O(ac, 'sine', p.ring);
    ro.connect(G(ac, 0.7, rg.gain));
    src.connect(rg);
    ro.start(t);
    ro.stop(end + 0.05);
  } else src.connect(pre);
  if (p.vib !== 0) lfo(ac, src.detune, t, end, { rate: p.vibRate ?? 5.5, depth: p.vib ?? 18 });
  if (p.breath) {
    const bg = G(ac, p.breath * 0.6);
    bg.connect(fa); bg.connect(fb);
    N(ac, 'pink', t, end).connect(bg);
  }
  src.start(t);
  src.stop(end + 0.05);
  return end;
}

function crowd(dest, t, p = {}) {
  const ac = dest.context, dur = p.dur ?? 1.4, n = p.voices ?? 5, aww = p.vowel === 'aw';
  const [F1, F2] = aww ? VOWELS.aw : VOWELS.oo;
  const amp = G(ac, 0, dest);
  const sum = G(ac, 2.6, F(ac, 'lowpass', 2800, 0.7, amp));
  const fa = F(ac, 'bandpass', F1, 4, sum), fb = F(ac, 'bandpass', F2, 5, G(ac, 0.7, sum));
  if (!aww) { fa.frequency.setValueAtTime(F1 * 0.9, t); fa.frequency.linearRampToValueAtTime(F1 * 1.3, t + dur * 0.5); }
  const mix = G(ac, 1 / Math.sqrt(n));
  mix.connect(fa); mix.connect(fb);
  const end = env(amp.gain, t, { a: dur * 0.28, hold: dur * 0.2, dur, peak: p.peak ?? 0.35, curve: 'exp' });
  const k = p.pitch ?? 1;
  for (let i = 0; i < n; i++) {
    const f = rnd(180, 260) * k, o = O(ac, 'sawtooth', f), d0 = t + rnd(0, 0.07);
    if (aww) { o.frequency.setValueAtTime(f * 1.12, d0); o.frequency.exponentialRampToValueAtTime(f * 0.8, end); }
    else {
      o.frequency.setValueAtTime(f * 0.9, d0);
      o.frequency.exponentialRampToValueAtTime(f * 1.12, t + dur * 0.45);
      o.frequency.exponentialRampToValueAtTime(f * 0.96, end);
    }
    o.detune.value = rnd(-12, 12);
    lfo(ac, o.detune, t, end, { rate: rnd(4.5, 6), depth: rnd(12, 24) });
    o.connect(G(ac, rnd(0.6, 1), mix));
    o.start(d0);
    o.stop(end + 0.02);
  }
  const bg = G(ac, 0.5);
  bg.connect(fa); bg.connect(fb);
  N(ac, 'pink', t, end).connect(bg);
  return end;
}

function applause(dest, t, p = {}) {
  const ac = dest.context, dur = p.dur ?? 2;
  const amp = G(ac, 0, dest);
  const lp = F(ac, 'lowpass', 3000, 0.7, amp);
  const end = env(amp.gain, t, { a: p.a ?? 0.12, hold: dur * (p.holdFrac ?? 0.45), dur, peak: (p.peak ?? 0.35) * 1.1, curve: 'exp' });
  const layers = p.thick ? 2 : 1;
  for (let i = 0; i < layers; i++) {
    const s = ac.createBufferSource();
    s.buffer = clapBuffer(ac);
    s.loop = true;
    s.playbackRate.value = i ? 1.09 : rnd(0.96, 1.02);
    s.connect(i ? G(ac, 0.8, lp) : lp);
    s.start(t, Math.random() * 2.5);
    s.stop(end + 0.02);
  }
  return end;
}

function laughter(dest, t, p = {}) {
  const ac = dest.context, dur = p.dur ?? 2, n = p.voices ?? 4, k = p.pitch ?? 1;
  const amp = G(ac, 0, dest);
  const sum = G(ac, 3.2, F(ac, 'lowpass', 3400, 0.7, amp));
  const fa = F(ac, 'bandpass', 800, 4, sum), fb = F(ac, 'bandpass', 1200, 6, G(ac, 0.8, sum));
  const fc = F(ac, 'bandpass', 2600, 8, G(ac, 0.25, sum));
  const mix = G(ac, 1 / Math.sqrt(n));
  mix.connect(fa); mix.connect(fb); mix.connect(fc);
  const end = env(amp.gain, t, { a: 0.08, hold: dur * 0.5, dur, peak: p.peak ?? 0.3, curve: 'exp' });
  for (let v = 0; v < n; v++) {
    let base = rnd(200, 300) * k;
    const o = O(ac, 'sawtooth', base), g = G(ac, 0, mix);
    o.connect(g);
    let tt = t + rnd(0, 0.15);
    g.gain.setValueAtTime(0, t);
    while (tt < end - 0.12) {
      const sd = rnd(0.8, 1.2) / rnd(5, 7), lv = rnd(0.6, 1);
      o.frequency.setValueAtTime(base * rnd(1, 1.12), tt);
      o.frequency.exponentialRampToValueAtTime(base * 0.88, tt + sd * 0.85);
      g.gain.setValueAtTime(0, tt);
      g.gain.linearRampToValueAtTime(lv, tt + 0.014);
      g.gain.setTargetAtTime(0, tt + 0.03, sd * 0.22);
      base *= 0.986;
      tt += sd;
    }
    g.gain.setValueAtTime(0, Math.max(tt, end - 0.1));
    o.start(t);
    o.stop(end + 0.02);
  }
  return end;
}

function kazoo(dest, t, p = {}) {
  const ac = dest.context, f = p.f ?? 440, dur = p.dur ?? 0.4;
  const g = G(ac, 0, dest);
  const hp = F(ac, 'highpass', 220, 0.7, g);
  const bp = F(ac, 'bandpass', p.formant ?? 1250, 3.5, G(ac, 2.4, hp));
  const pk = F(ac, 'bandpass', 2600, 5, G(ac, 1.2, hp));
  const sh = ac.createWaveShaper();
  sh.curve = softCurve(3);
  sh.connect(bp); sh.connect(pk); sh.connect(G(ac, 0.12, hp));
  const o = O(ac, 'sawtooth', f);
  if (p.f1) glide(o.frequency, t, f, p.f1, dur);
  o.connect(sh);
  const end = env(g.gain, t, { a: 0.018, hold: dur - 0.07, dur, peak: p.peak ?? 0.3, curve: 'exp' });
  lfo(ac, o.detune, t, end, { rate: 5.5, depth: p.vib ?? 20, delay: 0.1 });
  o.start(t);
  o.stop(end + 0.02);
  return end;
}

function slideWhistle(dest, t, p = {}) {
  const ac = dest.context, dur = p.dur ?? 0.6, from = p.from ?? 600, to = p.to ?? 1800;
  const g = G(ac, 0, dest);
  const o = O(ac, 'sine', from);
  glide(o.frequency, t, from, to, dur * 0.92, p.curve || 'exp');
  o.connect(g);
  const bp = F(ac, 'bandpass', from, 12, G(ac, 0.25, g));
  glide(bp.frequency, t, from, to, dur * 0.92, p.curve || 'exp');
  const end = env(g.gain, t, { a: 0.03, hold: dur * 0.7, dur, peak: p.peak ?? 0.35, curve: 'exp' });
  lfo(ac, o.detune, t, end, { rate: 7, depth: 12 });
  N(ac, 'white', t, end).connect(bp);
  o.start(t);
  o.stop(end + 0.02);
  return end;
}

function theremin(dest, t, p = {}) {
  const ac = dest.context, notes = p.notes ?? [[p.f ?? 440, p.dur ?? 1]], porta = p.porta ?? 0.07;
  const g = G(ac, 0, dest);
  const o = O(ac, 'sine', notes[0][0]), o2 = O(ac, 'sine', notes[0][0] * 2);
  o.connect(g);
  o2.connect(G(ac, 0.12, g));
  let tt = t;
  for (let i = 0; i < notes.length; i++) {
    const [f, d] = notes[i];
    if (i === 0) { o.frequency.setValueAtTime(f, tt); o2.frequency.setValueAtTime(f * 2, tt); }
    else { o.frequency.setTargetAtTime(f, tt, porta / 3); o2.frequency.setTargetAtTime(f * 2, tt, porta / 3); }
    tt += d;
  }
  const end = tt + 0.2;
  env(g.gain, t, { a: 0.09, hold: tt - t - 0.05, dur: end - t, peak: p.peak ?? 0.3, curve: 'exp' });
  for (const osc of [o, o2]) lfo(ac, osc.detune, t, end, { rate: 6, depth: p.vib ?? 28, delay: 0.25 });
  o.start(t); o2.start(t); o.stop(end + 0.02); o2.stop(end + 0.02);
  return end;
}

function musicBox(dest, t, p = {}) {
  const f = p.f ?? 1046.5, dur = p.dur ?? 1.1, pk = p.peak ?? 0.25;
  tone(dest, t, { f, dur, peak: pk, a: 0.002, curve: 'exp' });
  tone(dest, t, { f: f * 4, dur: dur * 0.4, peak: pk * 0.28, a: 0.001, curve: 'exp' });
  tone(dest, t, { f: f * 6.1, dur: 0.05, peak: pk * 0.15, a: 0.0005, curve: 'fast' });
  return t + dur;
}

// --- drums ---
function kick(dest, t, p = {}) {
  const pk = p.peak ?? 0.8, dur = p.dur ?? 0.35;
  tone(dest, t, { f: p.from ?? 150, f1: p.to ?? 45, glide: 0.12, dur, peak: pk, a: 0.001, curve: 'fast' });
  click(dest, t, { f: 3500, peak: pk * 0.25, dur: 0.006 });
  return t + dur;
}
function snare(dest, t, p = {}) {
  const pk = p.peak ?? 0.5, dur = p.dur ?? 0.18;
  noise(dest, t, { hp: 900, type: 'bandpass', f: 3200, q: 0.6, dur, peak: pk * 1.2, curve: 'fast' });
  tone(dest, t, { f: p.tone ?? 180, f1: (p.tone ?? 180) * 0.8, dur: 0.09, peak: pk * 0.7, a: 0.001, curve: 'fast' });
  tone(dest, t, { type: 'triangle', f: 330, dur: 0.05, peak: pk * 0.3, a: 0.001, curve: 'fast' });
  return t + dur;
}
function hat(dest, t, p = {}) {
  const dur = p.dur ?? (p.open ? 0.28 : 0.04);
  return noise(dest, t, { hp: 8000, type: 'peaking', f: 10000, dur, peak: (p.peak ?? 0.25) * 1.6, curve: p.open ? 'exp' : 'fast' });
}
function clap(dest, t, p = {}) {
  const pk = p.peak ?? 0.5, f = p.f ?? 1500;
  for (let i = 0; i < 3; i++) noise(dest, t + i * 0.01, { type: 'bandpass', f, q: 1.4, dur: 0.012, peak: pk * 1.6, a: 0.0005, curve: 'fast' });
  return noise(dest, t + 0.03, { type: 'bandpass', f, q: 1.2, dur: p.dur ?? 0.12, peak: pk * 1.3, a: 0.001, curve: 'fast' });
}
function woodblock(dest, t, p = {}) {
  const f = p.f ?? 900, pk = p.peak ?? 0.45;
  tone(dest, t, { f, f1: f * 0.97, dur: p.dur ?? 0.07, peak: pk, a: 0.0007, curve: 'fast' });
  click(dest, t, { f: f * 2.4, peak: pk * 0.5, dur: 0.01, q: 3 });
  return t + (p.dur ?? 0.07);
}
function rim(dest, t, p = {}) {
  const pk = p.peak ?? 0.35;
  tone(dest, t, { type: 'triangle', f: 820, dur: 0.03, peak: pk * 0.6, a: 0.0005, curve: 'fast' });
  return click(dest, t, { f: 1800, peak: pk, dur: 0.02, q: 2.5 });
}

// --- pitched instruments ---
function slapBass(dest, t, p = {}) {
  const ac = dest.context, f = p.f ?? 82.4, dur = p.dur ?? 0.35, pk = p.peak ?? 0.5;
  const g = G(ac, 0, dest);
  const lp = F(ac, 'lowpass', 2800, 5, g);
  lp.frequency.setValueAtTime(2800 * (p.bright ?? 1), t);
  lp.frequency.setTargetAtTime(260, t + 0.01, 0.06);
  const o = O(ac, 'sawtooth', f), sub = O(ac, 'sine', f);
  o.connect(lp);
  sub.connect(G(ac, 0.6, g));
  const end = env(g.gain, t, { a: 0.003, hold: dur * 0.35, dur, peak: pk * 0.8, curve: 'fast' });
  click(dest, t, { f: 2200, peak: pk * 0.35, dur: 0.01 });
  for (const osc of [o, sub]) { osc.start(t); osc.stop(end + 0.02); }
  return end;
}
function clav(dest, t, p = {}) {
  const ac = dest.context, f = p.f ?? 220, dur = p.dur ?? 0.25;
  const g = G(ac, 0, dest);
  const bp = F(ac, 'bandpass', 1200, 3, G(ac, 1.8, F(ac, 'highpass', 150, 0.7, g)));
  lfo(ac, bp.frequency, t, t + dur, { rate: p.wahRate ?? 5, depth: 700 * (p.wah ?? 1) });
  const o = O(ac, pulseWave(ac, 0.25), f);
  o.connect(bp);
  o.connect(G(ac, 0.25, g));
  const end = env(g.gain, t, { a: 0.002, hold: dur * 0.2, dur, peak: p.peak ?? 0.3, curve: 'fast' });
  o.start(t);
  o.stop(end + 0.02);
  return end;
}
function brass(dest, t, p = {}) {
  const ac = dest.context, f = p.f ?? 349.2, dur = p.dur ?? 0.5, a = p.a ?? 0.03, bright = p.bright ?? 1;
  const g = G(ac, 0, dest);
  const lp = F(ac, 'lowpass', 400, 1.4, g);
  lp.frequency.setValueAtTime(400, t);
  lp.frequency.linearRampToValueAtTime(3000 * bright, t + a + 0.05);
  lp.frequency.setTargetAtTime(1300 * bright, t + a + 0.06, 0.15);
  const end = env(g.gain, t, { a, hold: Math.max(0, dur - a - 0.09), dur, peak: (p.peak ?? 0.3) * 0.75, curve: 'exp' });
  for (const dt of [-8, 0, 7]) {
    const o = O(ac, 'sawtooth', f);
    o.detune.setValueAtTime(dt - 35, t);
    o.detune.linearRampToValueAtTime(dt, t + 0.045);
    o.connect(lp);
    o.start(t);
    o.stop(end + 0.02);
  }
  return end;
}
function strings(dest, t, p = {}) {
  const ac = dest.context, f = p.f ?? 440, dur = p.dur ?? 1.5, a = p.a ?? 0.25;
  const g = G(ac, 0, dest);
  const hp = F(ac, 'highpass', 180, 0.7, F(ac, 'lowpass', 3200, 0.7, g));
  const end = env(g.gain, t, { a, hold: Math.max(0, dur - a - 0.4), dur, peak: (p.peak ?? 0.2) * 0.6, curve: 'exp' });
  for (const dt of [-12, -4, 5, 13]) {
    const o = O(ac, 'sawtooth', f);
    o.detune.value = dt;
    lfo(ac, o.detune, t, end, { rate: rnd(4.6, 5.6), depth: 7 });
    o.connect(hp);
    o.start(t);
    o.stop(end + 0.02);
  }
  return end;
}
function organ(dest, t, p = {}) {
  const ac = dest.context, f = p.f ?? 261.6, dur = p.dur ?? 0.5, bars = p.bars ?? [1, 0.6, 0.4, 0.3];
  const g = G(ac, 0, dest);
  const end = env(g.gain, t, { a: 0.008, hold: Math.max(0, dur - 0.07), dur, peak: (p.peak ?? 0.2) * 0.7, curve: 'exp' });
  bars.forEach((w, i) => {
    if (!w) return;
    const o = O(ac, 'sine', f * (i + 1));
    o.connect(G(ac, w / bars.length * 1.6, g));
    o.start(t);
    o.stop(end + 0.02);
  });
  click(dest, t, { f: 2500, peak: (p.peak ?? 0.2) * 0.2, dur: 0.006 });
  return end;
}
function vibraphone(dest, t, p = {}) {
  const f = p.f ?? 659.3, dur = p.dur ?? 1.6, pk = p.peak ?? 0.3;
  tone(dest, t, { f, dur, peak: pk, a: 0.002, curve: 'exp', trem: 0.35, tremRate: 5.5 });
  tone(dest, t, { f: f * 4, dur: dur * 0.25, peak: pk * 0.15, a: 0.001, curve: 'exp' });
  return t + dur;
}
function epiano(dest, t, p = {}) {
  const ac = dest.context, f = p.f ?? 440, dur = p.dur ?? 1.2, pk = p.peak ?? 0.25;
  const car = O(ac, 'sine', f), mod = O(ac, 'sine', f), mg = G(ac, 0), g = G(ac, 0, dest);
  mg.gain.setValueAtTime(f * 1.6, t);
  mg.gain.exponentialRampToValueAtTime(f * 0.12, t + 0.35);
  mod.connect(mg).connect(car.frequency);
  car.connect(g);
  const end = env(g.gain, t, { a: 0.003, dur, peak: pk, curve: 'exp' });
  tone(dest, t, { f: f * 7, dur: 0.12, peak: pk * 0.08, a: 0.001, curve: 'fast' });
  for (const o of [car, mod]) { o.start(t); o.stop(end + 0.02); }
  return end;
}
function pluck(dest, t, p = {}) {
  const ac = dest.context, f = p.f ?? 440, dur = p.dur ?? 0.8, pk = p.peak ?? 0.3;
  const g = G(ac, 0, dest);
  const lp = F(ac, 'lowpass', f * 8 * (p.bright ?? 1), 1, g);
  lp.frequency.setTargetAtTime(f * 1.5, t, dur * 0.25);
  const o = O(ac, p.type || 'sawtooth', f);
  o.connect(lp);
  const end = env(g.gain, t, { a: 0.002, dur, peak: pk, curve: 'exp' });
  o.start(t);
  o.stop(end + 0.02);
  click(dest, t, { f: Math.min(6000, f * 6), peak: pk * 0.2, dur: 0.008 });
  return end;
}
function chord(builder, dest, t, freqs, p = {}) {
  let end = t;
  const pk = (p.peak ?? 0.3) / Math.sqrt(freqs.length);
  for (const f of freqs) end = Math.max(end, builder(dest, t, { ...p, f, peak: pk }));
  return end;
}

// Lookahead scheduler for loops/patterns: calls fn(tStep, i) for every step before now + lookahead.
// fn may return the time to the next step (variable rhythms); otherwise `step` is used.
function sequencer(t0, step, fn, lookahead = 0.35) {
  let next = t0, i = 0, stopped = false;
  return {
    update(now) {
      if (stopped) return;
      if (next < now - 1) next = now;
      while (next < now + lookahead) {
        const r = fn(next, i++);
        next += typeof r === 'number' && r > 0 ? r : step;
      }
    },
    stop() { stopped = true; },
  };
}

export const synth = {
  mtof, note, rnd, pick, db, clamp, VOWELS,
  gain, filter, shaper, panner, echo, noiseBuffer, pulseWave, softCurve, osc, noiseSrc,
  env, glide, lfo, release,
  tone, noise, click,
  fmBell, formant, crowd, applause, laughter, kazoo, slideWhistle, theremin, musicBox,
  kick, snare, hat, clap, woodblock, rim,
  slapBass, clav, brass, strings, organ, vibraphone, epiano, pluck, chord,
  sequencer,
};

// ------------------------------------------------------------------------------------------------
// Cue helpers
// ------------------------------------------------------------------------------------------------

const TELLY = 330, ANNOUNCER = 140, BARON = 110;   // wah-wah voice base pitches (GDD §15)
const HALO = 38;                                   // Baron's ring-modulation frequency

const cue = (props, fn) => Object.assign(fn, props);
const pit = (o) => o.pitch ?? 1;

// Handle of an endless cue: stops its free-running sources (and its pattern) at the fade end.
function loopHandle(sources, seq, methods) {
  return {
    update: seq ? (now) => seq.update(now) : undefined,
    stop(t) {
      if (seq) seq.stop();
      for (const s of sources) s.stop(t + 0.05);
    },
    ...methods,
  };
}

// Continuous cue body: a one-shot of `dur` s (o.dur overrides) or, under audio.loop() (o.loop) or when
// `loop` is set (inherently endless cues), a loop that fades in over `a`. build(out, t, end) starts the
// sources (end = Infinity when looping) and returns the free-running ones; every = [step, fn(out, t, i)]
// adds an event layer whose fn may return the time to its next event.
function sustain(dest, o, { dur = 2, peak = 1, a = 0.08, r = 0.2, loop = false, build, every }) {
  const ac = dest.context, t = o.t, out = G(ac, 0, dest);
  if (loop || o.loop) {
    out.gain.setValueAtTime(0, t);
    out.gain.linearRampToValueAtTime(peak, t + a);
    const srcs = build ? build(out, t, Infinity) : [];
    let seq = null;
    if (every) {
      seq = sequencer(t, every[0], (tt, i) => every[1](out, tt, i), 0.5);
      seq.update(ac.currentTime);
    }
    return loopHandle(srcs, seq);
  }
  const d = Math.max(o.dur ?? dur, a + r + 0.02);
  const end = env(out.gain, t, { a, hold: d - a - r, dur: d, peak, curve: 'exp' });
  if (build) build(out, t, end);
  if (every) {
    for (let tt = t, i = 0; tt < end - 0.05; i++) {
      const n = every[1](out, tt, i);
      tt += typeof n === 'number' && n > 0 ? n : every[0];
    }
  }
  return end;
}

// Square-wave amplitude chop (static flutter, rips, walkie squelch). Returns the input gain node.
function flutter(dest, t, end, rate = 30, depth = 0.9) {
  const g = G(dest.context, 1 - depth / 2, dest);
  lfo(dest.context, g.gain, t, end, { type: 'square', rate, depth: depth / 2 });
  return g;
}

// Cartoon spring: a sine (plus a soft octave) whose fast vibrato decays while the pitch rises.
function boing(dest, t, { f = 260, dur = 0.55, peak = 0.35, rate = 15, depth = 450, rise = 1.25 } = {}) {
  const ac = dest.context, o = O(ac, 'sine', f), o2 = O(ac, 'triangle', f * 2), lo = O(ac, 'sine', rate);
  glide(o.frequency, t, f * 0.85, f * rise, dur);
  glide(o2.frequency, t, f * 1.7, f * rise * 2, dur);
  const lg = G(ac, 0), g = G(ac, 0, dest);
  lg.gain.setValueAtTime(depth, t);
  lg.gain.exponentialRampToValueAtTime(depth * 0.04, t + dur);
  lo.connect(lg);
  lg.connect(o.detune);
  lg.connect(o2.detune);
  o.connect(g);
  o2.connect(G(ac, 0.16, g));
  const end = env(g.gain, t, { a: 0.004, dur, peak, curve: 'exp' });
  for (const s of [o, o2, lo]) { s.start(t); s.stop(end + 0.02); }
  return end;
}

// Bright bell "ding": fundamental, two inharmonic partials and a strike click.
function ding(dest, t, { f = 1318.5, dur = 1.2, peak = 0.3 } = {}) {
  tone(dest, t, { f, dur, peak, a: 0.001 });
  tone(dest, t, { f: f * 2.76, dur: dur * 0.35, peak: peak * 0.3, a: 0.001 });
  tone(dest, t, { f: f * 5.4, dur: dur * 0.12, peak: peak * 0.12, a: 0.001 });
  click(dest, t, { f: Math.min(9000, f * 3), peak: peak * 0.5, dur: 0.006 });
  return t + dur;
}

// Struck metal: inharmonic partials, the higher ones dying faster, plus a noise strike.
const METAL = [1, 1.59, 2.14, 2.83, 3.9, 5.1];
function metal(dest, t, { f = 400, dur = 0.8, peak = 0.3 } = {}) {
  METAL.forEach((r, i) => tone(dest, t, { f: f * r, dur: dur / (1 + i * 0.6), peak: (0.55 * peak) / (1 + i * 0.5), a: 0.001, detune: rnd(-8, 8) }));
  noise(dest, t, { type: 'bandpass', f: Math.min(9000, f * 4), q: 1.2, dur: 0.03, peak: peak * 1.2, curve: 'fast' });
  return t + dur;
}

// Scattered short high sine blips: glass tinkle, sparkle.
function tinkle(dest, t, { n = 8, span = 0.5, lo = 2800, hi = 6000, peak = 0.12, dur = 0.12 } = {}) {
  let end = t;
  for (let i = 0; i < n; i++) {
    const tt = t + Math.pow(Math.random(), 1.6) * span;
    end = Math.max(end, tone(dest, tt, { f: rnd(lo, hi), dur: dur * rnd(0.6, 1.4), peak: peak * rnd(0.5, 1), a: 0.001 }));
  }
  return end;
}

// Random static clicks.
function crackle(dest, t, { n = 10, span = 0.4, peak = 0.3, lo = 1500, hi = 6000 } = {}) {
  let end = t;
  for (let i = 0; i < n; i++) {
    end = Math.max(end, click(dest, t + Math.random() * span, { f: rnd(lo, hi), peak: peak * rnd(0.4, 1), dur: rnd(0.004, 0.012) }));
  }
  return end;
}

// Band-swept noise whoosh whose envelope peaks at `at` (fraction of dur).
function whoosh(dest, t, { f0 = 400, f1 = 2000, dur = 0.3, peak = 1, q = 1.2, color = 'pink', at = 0.4 } = {}) {
  return noise(dest, t, { color, type: 'bandpass', f: f0, f1, q, dur, a: dur * at, peak, curve: 'exp' });
}

// Quick sine glide: pops, bloops, bubbles.
function blip(dest, t, f0, f1, dur, peak, type = 'sine') {
  return tone(dest, t, { type, f: f0, f1, glide: dur * 0.8, dur, peak, a: 0.002 });
}

// Low thump with a falling pitch (kick-like body of hits and impacts).
function thump(dest, t, { f0 = 150, f1 = 50, dur = 0.2, peak = 0.8 } = {}) {
  return tone(dest, t, { f: f0, f1, glide: dur * 0.6, dur, peak, a: 0.001, curve: 'fast' });
}

// Two-finger audience whistle.
function whistle(dest, t, peak = 0.08) {
  tone(dest, t, { f: 1700, f1: 2600, glide: 0.18, dur: 0.24, peak, a: 0.02, vib: 20 });
  return tone(dest, t + 0.28, { f: 2600, f1: 1500, glide: 0.35, dur: 0.4, peak, a: 0.01, vib: 25 });
}

const tellyVoice = (dest, o, syl, x) => formant(dest, o.t, { base: TELLY * pit(o), syl, peak: 0.3, vib: 28, ...x });
const baronVoice = (dest, o, syl, x) => formant(dest, o.t, { base: BARON * pit(o), syl, peak: 0.16, ring: HALO, breath: 0.3, vib: 22, ...x });

// Every gun shot carries the friendly toy chirp; upgraded weapons add the sparkle (GDD §15).
function chirp(dest, t, peak = 0.16) {
  return tone(dest, t, { f: 1200, f1: 600, dur: 0.07, peak, a: 0.002 });
}
function sparkle(dest, t, peak = 0.07) {
  const scale = [2093, 2349, 2637, 3136, 3520, 4186];
  for (let i = 0; i < 3; i++) tone(dest, t + i * 0.035, { f: pick(scale), dur: 0.09, peak, a: 0.001 });
  tone(dest, t, { type: 'triangle', f: 1568, dur: 0.22, peak: peak * 0.7, detune: -12 });
  return tone(dest, t, { type: 'triangle', f: 1568, dur: 0.22, peak: peak * 0.7, detune: 12 });
}
function gunLayers(dest, t, o, peak) {
  chirp(dest, t + 0.003, peak);
  if (o.upgraded) sparkle(dest, t + 0.01);
}

// ------------------------------------------------------------------------------------------------
// Telly, crowd, sponsors, Uplink, Sign-On
// ------------------------------------------------------------------------------------------------

const TELLY_CUES = {
  telly_hum: cue({ range: 12, limit: 4, loopable: true }, (a, dest, o) => sustain(dest, o, {
    loop: true, peak: 0.36, a: 0.4,
    build: (out, t, end) => {
      const ac = dest.context, w = G(ac, 0.88, out);
      const s = [osc(ac, 'sine', 60, t, end), osc(ac, 'sine', 120, t, end), osc(ac, 'sawtooth', 60, t, end)];
      s[0].connect(G(ac, 0.5, w));
      s[1].connect(G(ac, 0.32, w));
      s[2].connect(F(ac, 'bandpass', 1100, 1.5, G(ac, 0.14, w)));
      s.push(lfo(ac, w.gain, t, end, { rate: 0.37, depth: 0.12 }));
      return s;
    },
  })),
  telly_wake: (a, dest, o) => {
    const t = o.t, b = TELLY * pit(o);
    tone(dest, t, { f: b * 2, f1: b * 2.1, dur: 0.11, peak: 0.06 });
    tone(dest, t + 0.14, { f: b * 3, f1: b * 3.56, dur: 0.22, peak: 0.06, vib: 25 });
    return tellyVoice(dest, o, [{ d: 0.11, p: 1, p1: 1.06, v: 'oo', gap: 0.03 }, { d: 0.2, p: 1.5, p1: 1.78, v: 'ee' }]);
  },
  telly_ooh: (a, dest, o) => {
    tone(dest, o.t, { f: TELLY * 1.9 * pit(o), f1: TELLY * 2.9 * pit(o), dur: 0.34, a: 0.03, peak: 0.05, vib: 30 });
    return tellyVoice(dest, o, [{ d: 0.34, p: 0.95, p1: 1.45, v: 'oo' }], { vib: 40 });
  },
  telly_zip: (a, dest, o) => noise(flutter(dest, o.t, o.t + 0.2, 55, 0.7), o.t, {
    type: 'bandpass', f: 500, f1: 7000, q: 2.5, dur: 0.2, a: 0.01, peak: 2.2, curve: 'lin',
  }),
  telly_clack: cue({ limit: 6 }, (a, dest, o) => {
    const t = o.t, k = pit(o);
    click(dest, t, { f: 2600 * k, q: 1.2, dur: 0.018, peak: 0.8 });
    return tone(dest, t, { f: 180 * k, f1: 140 * k, dur: 0.08, peak: 0.4, a: 0.001, curve: 'fast' });
  }),
  telly_clack_final: (a, dest, o) => {
    const t = o.t;
    click(dest, t, { f: 1800, q: 1, dur: 0.025, peak: 1.1 });
    noise(dest, t, { lp: 600, dur: 0.12, peak: 0.8, curve: 'fast' });
    metal(dest, t + 0.01, { f: 300, dur: 0.3, peak: 0.08 });
    return thump(dest, t, { f0: 130, f1: 80, dur: 0.22, peak: 0.65 });
  },
  telly_boing: (a, dest, o) => boing(dest, o.t, { f: 220 * pit(o), dur: 0.7, peak: 0.4 }),
  telly_bulge: (a, dest, o) => {
    const t = o.t, k = pit(o);
    tone(dest, t, { type: 'triangle', f: 400 * k, f1: 1000 * k, glide: 0.38, dur: 0.42, a: 0.03, peak: 0.07, vib: 70, vibRate: 9 });
    return tone(dest, t, { f: 200 * k, f1: 500 * k, glide: 0.38, dur: 0.42, a: 0.03, peak: 0.4, vib: 70, vibRate: 9 });
  },
  telly_ploop: (a, dest, o) => {
    const t = o.t, k = pit(o);
    tone(dest, t, { f: 600 * k, f1: 150 * k, glide: 0.06, dur: 0.09, peak: 0.6, a: 0.001 });
    click(dest, t, { f: 1500, peak: 0.3 });
    [2093, 2637, 3136, 4186].forEach((f, i) => tone(dest, t + 0.08 + i * 0.045, { f, dur: 0.25, peak: 0.1, a: 0.001 }));
    return t + 0.5;
  },
  telly_drum: (a, dest, o) => {
    const t = o.t, k = pit(o);
    for (let i = 0; i < 4; i++) woodblock(dest, t + i * 0.075, { f: (1250 - i * 90) * k, peak: 0.42 - i * 0.03 });
    return t + 0.36;
  },
  telly_nuh_uh: (a, dest, o) => tellyVoice(dest, o, [{ d: 0.13, p: 1.25, p1: 1.3, v: 'uh', gap: 0.06 }, { d: 0.22, p: 0.95, p1: 0.88, v: 'uh' }]),
  telly_slurp: (a, dest, o) => {
    const t = o.t;
    noise(flutter(dest, t, t + 0.3, 22, 0.6), t, { type: 'bandpass', f: 350, f1: 2600, q: 5, dur: 0.3, a: 0.05, peak: 3 });
    tone(dest, t, { f: 180, f1: 700, dur: 0.3, a: 0.03, peak: 0.25, vib: 120, vibRate: 22 });
    click(dest, t + 0.3, { f: 1800, peak: 0.4 });
    return blip(dest, t + 0.3, 300, 900, 0.05, 0.4);
  },
  telly_giggle: (a, dest, o) => tellyVoice(dest, o, [
    { d: 0.075, p: 1.5, v: 'ee', gap: 0.03 }, { d: 0.075, p: 1.62, v: 'i', gap: 0.03 },
    { d: 0.075, p: 1.5, v: 'ee', gap: 0.03 }, { d: 0.14, p: 1.7, p1: 1.4, v: 'i' },
  ], { breath: 0.4, vib: 20 }),
  telly_aww: (a, dest, o) => tellyVoice(dest, o, [{ d: 0.6, p: 1.15, p1: 0.72, v: 'aw' }], { vib: 35 }),
  telly_coin: (a, dest, o) => {
    const t = o.t, k = pit(o);
    ding(dest, t, { f: 1976 * k, dur: 0.1, peak: 0.22 });
    return ding(dest, t + 0.07, { f: 2637 * k, dur: 0.6, peak: 0.26 });
  },
  telly_clonk: cue({ limit: 4 }, (a, dest, o) => {
    const t = o.t, k = pit(o) * rnd(0.95, 1.05);
    noise(dest, t, { lp: 1800, dur: 0.035, peak: 0.5, curve: 'fast' });
    woodblock(dest, t, { f: 700 * k, peak: 0.2 });
    return tone(dest, t, { f: 300 * k, f1: 250 * k, dur: 0.05, peak: 0.4, a: 0.001, curve: 'fast' });
  }),
  telly_thwip: (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { type: 'bandpass', f: 4000, f1: 300, q: 2, dur: 0.25, peak: 0.9 });
    return tone(dest, t, { f: 2000, f1: 60, glide: 0.28, dur: 0.3, peak: 0.45, a: 0.002 });
  },
  telly_bwong: (a, dest, o) => {
    const ac = dest.context, t = o.t, end = t + 0.8, g = G(ac, 0, dest), am = G(ac, 0.5, g);
    const m = O(ac, 'sine', 22);
    glide(m.frequency, t, 22, 5, 0.8);
    m.connect(G(ac, 0.5, am.gain));
    for (const [f, v] of [[60, 0.9], [120, 0.6], [180, 0.3], [240, 0.12]]) osc(ac, 'sine', f, t, end).connect(G(ac, v, am));
    env(g.gain, t, { a: 0.005, dur: 0.8, peak: 0.55 });
    tone(dest, t, { f: 7800, dur: 0.8, peak: 0.02 });
    click(dest, t, { f: 900, peak: 0.4, dur: 0.01 });
    m.start(t);
    m.stop(end + 0.02);
    return end;
  },
  telly_ow: (a, dest, o) => tellyVoice(dest, o, [{ d: 0.1, p: 1.6, p1: 1.7, v: 'a', gap: 0 }, { d: 0.2, p: 1.65, p1: 1.05, v: 'oo' }], { peak: 0.38 }),
  telly_hey: (a, dest, o) => tellyVoice(dest, o, [{ d: 0.26, p: 1.2, p1: 1.5, v: 'eh' }], { breath: 0.6, peak: 0.36 }),
  telly_wonder_tada: (a, dest, o) => {
    const t = o.t, ta = [72, 76, 79].map(mtof);
    chord(brass, dest, t, ta, { dur: 0.13, peak: 0.28, a: 0.01 });
    hat(dest, t + 0.16, { open: true, dur: 0.9, peak: 0.12 });
    return chord(brass, dest, t + 0.16, [...ta, mtof(84)], { dur: 0.85, peak: 0.32, a: 0.015 });
  },
};

const CROWD_CUES = {
  crowd_ooh: cue({ bus: 'tv' }, (a, dest, o) => crowd(dest, o.t, { vowel: 'oo', dur: 1.5, voices: 8, peak: 0.4, pitch: pit(o) })),
  crowd_aww: cue({ bus: 'tv' }, (a, dest, o) => crowd(dest, o.t, { vowel: 'aw', dur: 1.6, voices: 8, peak: 0.4, pitch: pit(o) })),
  crowd_applause: cue({ bus: 'tv' }, (a, dest, o) => {
    whistle(dest, o.t + 0.35);
    return applause(dest, o.t, { dur: o.dur ?? 2.6, peak: 0.4, thick: true });
  }),
  crowd_laugh: cue({ bus: 'tv' }, (a, dest, o) => laughter(dest, o.t, { dur: o.dur ?? 2.2, voices: 6, peak: 0.35, pitch: pit(o) })),
};

const SPONSOR_CUES = {
  commercial_cut: (a, dest, o) => {
    const t = o.t;
    click(dest, t, { f: 3500, q: 1, dur: 0.01, peak: 1 });
    tone(dest, t, { f: 90, dur: 0.03, peak: 0.3, a: 0.0005, curve: 'fast' });
    noise(dest, t + 0.05, { hp: 3000, dur: 0.035, peak: 0.6, curve: 'fast' });
    return click(dest, t + 0.075, { f: 5000, q: 2, dur: 0.008, peak: 0.6 });
  },
  commercial_ding: (a, dest, o) => ding(dest, o.t, { f: 1318.5 * pit(o), dur: 1.4, peak: 0.3 }),
  // opts.rhythm: pitch multiplier per syllable (the power-up name's cadence).
  announcer_wahwah: cue({ bus: 'tv', tv: true }, (a, dest, o) => {
    const r = o.rhythm || [1.1, 0.95, 0.85], vowels = ['a', 'o', 'e', 'a', 'o'], last = r.length - 1;
    const syl = r.map((p, i) => ({ d: i === last ? 0.3 : 0.16, p: p * 1.05, p1: p * (i === last ? 0.88 : 0.98), v: vowels[i % 5], gap: 0.04 }));
    return formant(dest, o.t, { base: ANNOUNCER * pit(o), syl, peak: 0.17, vib: 14, wahLo: 380, wahHi: 2400 });
  }),
  star_wipe: (a, dest, o) => {
    const t = o.t, scale = [0, 2, 4, 7, 9];
    for (let i = 0; i < 15; i++) {
      tone(dest, t + i * 0.028, { type: 'triangle', f: mtof(72 + scale[i % 5] + 12 * Math.floor(i / 5)), dur: 0.3, peak: 0.1, a: 0.002 });
    }
    noise(dest, t, { hp: 5000, dur: 0.6, a: 0.35, peak: 0.25 });
    return t + 0.75;
  },
  costume_pop: (a, dest, o) => {
    const t = o.t;
    blip(dest, t, 350, 900, 0.05, 0.4);
    noise(dest, t, { type: 'bandpass', f: 1200, q: 1, dur: 0.06, peak: 1, curve: 'fast' });
    ding(dest, t + 0.03, { f: 1568, dur: 1, peak: 0.25 });
    return Math.max(t + 1.03, tinkle(dest, t + 0.08, { n: 7, span: 0.45, lo: 3000, hi: 6500, peak: 0.08 }));
  },
  sponsor_denied: cue({ bus: 'ui' }, (a, dest, o) => {
    const t = o.t, lp = F(dest.context, 'lowpass', 1400, 0.8, dest);
    tone(lp, t, { type: 'square', f: 98, dur: 0.38, hold: 0.3, peak: 0.15, curve: 'fast' });
    return tone(lp, t, { type: 'square', f: 103.5, dur: 0.38, hold: 0.3, peak: 0.12, curve: 'fast' });
  }),
  studio_flash: (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { hp: 1200, dur: 0.1, peak: 0.6, curve: 'fast' });
    tone(dest, t, { f: 1400, f1: 700, dur: 0.05, peak: 0.15, a: 0.001 });
    return thump(dest, t, { f0: 160, f1: 70, dur: 0.12, peak: 0.5 });
  },
  replay_wipe: (a, dest, o) => {
    const t = o.t;
    tone(dest, t, { f: 250, f1: 1000, dur: 0.45, a: 0.2, peak: 0.12 });
    return whoosh(dest, t, { f0: 300, f1: 3600, dur: 0.5, peak: 1.6, q: 1.5, at: 0.55 });
  },
  replay_rewind: (a, dest, o) => {
    const t = o.t;
    noise(flutter(dest, t, t + 1, 18, 0.5), t, { type: 'bandpass', f: 800, f1: 5000, q: 1, dur: 1, a: 0.7, hold: 0.2, peak: 0.6, curve: 'fast' });
    return tone(dest, t, { type: 'triangle', f: 260, f1: 1500, dur: 1, a: 0.7, hold: 0.2, peak: 0.25, vib: 110, vibRate: 7, curve: 'fast' });
  },
};

const UPLINK_CUES = {
  dish_crank: cue({ ref: 3, loopable: true }, (a, dest, o) => sustain(dest, o, {
    dur: 3, peak: 0.38, a: 0.15,
    build: (out, t, end) => {
      const ac = dest.context, s = osc(ac, 'sawtooth', 80, t, end), am = G(ac, 0.6, F(ac, 'lowpass', 520, 2, out));
      s.connect(am);
      return [s, lfo(ac, am.gain, t, end, { rate: 7.5, depth: 0.4 })];
    },
    every: [0.133, (out, tt, i) => { click(out, tt, { f: i % 2 ? 2200 : 1700, q: 3, dur: 0.012, peak: 0.5 }); }],
  })),
  dish_lock: (a, dest, o) => {
    const t = o.t;
    for (let i = 0; i < 3; i++) tone(dest, t + i * 0.16, { f: 1000, dur: 0.08, hold: 0.06, peak: 0.25, a: 0.003, curve: 'fast' });
    click(dest, t + 0.5, { f: 1600, peak: 0.6 });
    return thump(dest, t + 0.5, { f0: 140, f1: 90, dur: 0.15, peak: 0.5 });
  },
  uplink_clang: (a, dest, o) => {
    const t = o.t;
    thump(dest, t, { f0: 90, f1: 60, dur: 0.2, peak: 0.5 });
    return metal(dest, t, { f: 190, dur: 1.6, peak: 0.35 });
  },
  uplink_motor: cue({ loopable: true }, (a, dest, o) => sustain(dest, o, {
    dur: 0.8, peak: 0.45, a: 0.1, r: 0.15,
    build: (out, t, end) => {
      const ac = dest.context, s = osc(ac, 'sawtooth', 45, t, end), w = osc(ac, 'sine', 600, t, end);
      glide(s.frequency, t, 45, 70, 0.4, 'lin');
      glide(w.frequency, t, 600, 1400, 0.5);
      s.connect(F(ac, 'lowpass', 700, 1.5, out));
      w.connect(G(ac, 0.05, out));
      return [s, w];
    },
  })),
  uplink_vwoom: (a, dest, o) => {
    const t = o.t, lp = F(dest.context, 'lowpass', 300, 3, dest);
    lp.frequency.setValueAtTime(300, t);
    lp.frequency.exponentialRampToValueAtTime(5000, t + 1.1);
    tone(lp, t, { type: 'sawtooth', f: 100, f1: 1200, dur: 1.3, a: 0.5, hold: 0.5, peak: 0.35 });
    tone(lp, t, { type: 'sawtooth', f: 101.5, f1: 1212, dur: 1.3, a: 0.5, hold: 0.5, peak: 0.3 });
    return noise(dest, t, { type: 'bandpass', f: 400, f1: 6000, q: 1.2, dur: 1.3, a: 0.7, peak: 0.9 });
  },
  uplink_snap: (a, dest, o) => {
    const t = o.t;
    chord(brass, dest, t, [60, 64, 67, 72].map(mtof), { dur: 0.6, peak: 0.2, a: 0.008 });
    kick(dest, t, { peak: 0.45 });
    tinkle(dest, t + 0.05, { n: 8, span: 0.6, lo: 3000, hi: 7000, peak: 0.07 });
    return noise(dest, t, { hp: 4500, dur: 1.8, peak: 0.25, a: 0.002 });
  },
  uplink_flicker: (a, dest, o) => {
    const t = o.t;
    for (let i = 0; i < 4; i++) noise(dest, t + rnd(0, 0.6), { hp: 2000, dur: 0.03, peak: 0.5, curve: 'fast' });
    return Math.max(t + 0.7, crackle(dest, t, { n: 12, span: 0.8, peak: 0.5 }));
  },
  uplink_lost: (a, dest, o) => {
    const t = o.t;
    tone(dest, t, { type: 'triangle', f: 1240, f1: 380, dur: 0.55, peak: 0.06, vib: 30 });
    noise(dest, t + 0.5, { hp: 2000, dur: 0.25, peak: 0.3 });
    return tone(dest, t, { f: 620, f1: 190, dur: 0.55, peak: 0.35, vib: 30, a: 0.01 });
  },
};

const SIGNON_CUES = {
  signon_thunk: (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { lp: 900, dur: 0.12, peak: 1, curve: 'fast' });
    metal(dest, t, { f: 150, dur: 0.4, peak: 0.15 });
    return thump(dest, t, { f0: 110, f1: 45, dur: 0.3, peak: 0.75 });
  },
  signon_hum: (a, dest, o) => {
    const t = o.t, lp = F(dest.context, 'lowpass', 250, 1, dest);
    lp.frequency.setValueAtTime(250, t);
    lp.frequency.exponentialRampToValueAtTime(1800, t + 2.6);
    tone(lp, t, { type: 'sawtooth', f: 40, f1: 120, glide: 2.5, dur: 3.4, a: 2.4, hold: 0.4, peak: 0.32 });
    return tone(dest, t, { f: 40, f1: 120, glide: 2.5, dur: 3.4, a: 2.4, hold: 0.4, peak: 0.22 });
  },
  crt_ping: (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { hp: 1800, dur: 0.14, a: 0.01, peak: 0.5 });
    return tone(dest, t, { f: 5200, dur: 0.18, peak: 0.12, a: 0.001 });
  },
  tone_1khz: (a, dest, o) => {
    const dur = o.dur ?? 1.5;
    return tone(dest, o.t, { f: 1000, dur, a: 0.01, hold: dur - 0.06, peak: 0.12, curve: 'fast' });
  },
  onair_clack: (a, dest, o) => {
    const t = o.t, lp = F(dest.context, 'lowpass', 900, 1, dest);
    click(dest, t, { f: 2800, q: 1, dur: 0.015, peak: 1.1 });
    click(dest, t + 0.012, { f: 1500, q: 1.5, dur: 0.012, peak: 0.6 });
    tone(lp, t + 0.01, { type: 'square', f: 100, dur: 0.45, peak: 0.1 });
    return tone(dest, t + 0.01, { f: 100, dur: 0.45, peak: 0.2 });
  },
  light_thunk: (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { lp: 700, dur: 0.1, peak: 0.9, curve: 'fast' });
    tone(dest, t + 0.01, { f: 2600, dur: 0.15, peak: 0.03 });
    tone(dest, t, { f: 120, dur: 0.5, peak: 0.08, a: 0.02 });
    return thump(dest, t, { f0: 75, f1: 45, dur: 0.22, peak: 0.8 });
  },
  door_buzz: (a, dest, o) => {
    const t = o.t, lp = F(dest.context, 'lowpass', 2000, 0.8, dest);
    tone(lp, t, { type: 'square', f: 120, dur: 0.7, hold: 0.6, peak: 0.15, curve: 'fast', trem: 0.5, tremRate: 60 });
    click(dest, t + 0.72, { f: 1800, peak: 0.6 });
    return tone(dest, t + 0.72, { f: 300, dur: 0.05, peak: 0.3, a: 0.001, curve: 'fast' });
  },
};

// ------------------------------------------------------------------------------------------------
// Weapons, equipment, melee (fire cues take opts.upgraded)
// ------------------------------------------------------------------------------------------------

const WEAPON_CUES = {
  wpn_revolver_38: cue({ limit: 4 }, (a, dest, o) => {
    const t = o.t, k = pit(o), e = echo(dest, { time: 0.11, feedback: 0.12, wet: 0.28, lp: 2200 });
    noise(e, t, { hp: 1500, dur: 0.08, peak: 0.6, curve: 'fast' });
    noise(e, t, { type: 'bandpass', f: 600 * k, q: 0.8, dur: 0.07, peak: 0.7, curve: 'fast' });
    thump(e, t, { f0: 150 * k, f1: 50 * k, dur: 0.2, peak: 0.5 });
    gunLayers(dest, t, o, 0.18);
    return t + 0.45;
  }),
  wpn_pump_37: cue({ limit: 3 }, (a, dest, o) => {
    const t = o.t, k = pit(o);
    noise(dest, t, { lp: 3000, dur: 0.25, peak: 0.8, curve: 'fast' });
    noise(dest, t, { type: 'bandpass', f: 400 * k, q: 0.7, dur: 0.18, peak: 0.9, curve: 'fast' });
    thump(dest, t, { f0: 110 * k, f1: 40 * k, dur: 0.3, peak: 0.7 });
    gunLayers(dest, t, o, 0.2);
    return t + 0.35;
  }),
  wpn_pump_rack: (a, dest, o) => {
    const t = o.t, k = pit(o);
    for (const [dt, f] of [[0, 1900], [0.17, 1300]]) {
      noise(dest, t + dt, { type: 'bandpass', f: f * k, q: 3, dur: 0.045, peak: 2, curve: 'fast' });
      tone(dest, t + dt, { f: f * 0.18 * k, dur: 0.04, peak: 0.3, a: 0.001, curve: 'fast' });
      click(dest, t + dt + 0.012, { f: f * 2, peak: 0.4 });
    }
    return t + 0.25;
  },
  wpn_mp7: cue({ limit: 6 }, (a, dest, o) => {
    const t = o.t, k = pit(o) * rnd(0.92, 1.08);
    noise(dest, t, { type: 'bandpass', f: 2000 * k, q: 0.9, dur: 0.035, peak: 1.6, curve: 'fast' });
    click(dest, t, { f: 4000 * k, peak: 0.6, dur: 0.008 });
    thump(dest, t, { f0: 130 * k, f1: 70 * k, dur: 0.06, peak: 0.45 });
    gunLayers(dest, t, o, 0.1);
    return t + 0.12;
  }),
  // One cue = the whole 3-round burst (75 ms apart); per-round plays inside `gap` are merged.
  wpn_m16a1: cue({ limit: 3, gap: 0.2 }, (a, dest, o) => {
    const t = o.t, k = pit(o);
    for (let i = 0; i < 3; i++) {
      const tt = t + i * 0.075, j = k * (1 - i * 0.02);
      noise(dest, tt, { type: 'bandpass', f: 1300 * j, q: 0.8, dur: 0.06, peak: 1.6, curve: 'fast' });
      thump(dest, tt, { f0: 140 * j, f1: 60 * j, dur: 0.08, peak: 0.5 });
      tone(dest, tt, { f: 3200 * j, dur: 0.12, peak: 0.05, a: 0.001 });
      gunLayers(dest, tt, o, 0.12);
    }
    return t + 0.4;
  }),
  wpn_m60: cue({ limit: 6 }, (a, dest, o) => {
    const t = o.t, k = pit(o) * rnd(0.96, 1.04);
    noise(dest, t, { lp: 1400 * k, dur: 0.1, peak: 1, curve: 'fast' });
    noise(dest, t, { type: 'bandpass', f: 700 * k, q: 0.7, dur: 0.07, peak: 1, curve: 'fast' });
    thump(dest, t, { f0: 90 * k, f1: 55 * k, dur: 0.14, peak: 0.65 });
    click(dest, t + 0.035, { f: 3800, q: 4, peak: 0.25 });
    click(dest, t + 0.06, { f: 3100, q: 4, peak: 0.2 });
    gunLayers(dest, t, o, 0.12);
    return t + 0.2;
  }),
  wpn_toy_chirp: (a, dest, o) => chirp(dest, o.t, 0.3),
  wpn_upgraded_sparkle: (a, dest, o) => sparkle(dest, o.t, 0.14),
  wpn_zapper: cue({ limit: 3 }, (a, dest, o) => {
    const t = o.t, k = pit(o);
    fmBell(dest, t, { f: 1760 * k, ratio: 1.41, index: 3, dur: 0.3, peak: 0.25 });
    fmBell(dest, t + 0.05, { f: 2349 * k, ratio: 1.41, index: 3, dur: 0.3, peak: 0.2 });
    thump(dest, t, { f0: 160, f1: 70, dur: 0.1, peak: 0.6 });
    noise(flutter(dest, t, t + 0.2, 45), t + 0.03, { hp: 1800, dur: 0.15, peak: 0.6, curve: 'lin' });
    gunLayers(dest, t, o, 0.14);
    return t + 0.4;
  }),
  gag_cartoon: (a, dest, o) => slideWhistle(dest, o.t, { from: 1800, to: 350, dur: 0.75, peak: 0.28 }),
  gag_western: (a, dest, o) => {
    const x = { syl: [{ d: 0.12, p: 1, v: 'oo', gap: 0 }, { d: 0.45, p: 1, p1: 0.97, v: 'a' }], wave: 'square', vib: 14, buzz: 0.25, peak: 0.12, wahLo: 500, wahHi: 3000 };
    formant(dest, o.t, { base: 392, ...x });
    return formant(dest, o.t, { base: 494, ...x });
  },
  gag_cooking: (a, dest, o) => ding(dest, o.t, { f: 2489, dur: 1.4, peak: 0.3 }),
  gag_nature: (a, dest, o) => {
    const ac = dest.context, t = o.t, g = G(ac, 0, dest), fl = O(ac, 'sine', 1760);
    for (let i = 0; i < 9; i++) fl.frequency.setValueAtTime(i % 2 ? 1976 : 1760, t + i * 0.055);
    glide(fl.frequency, t + 0.5, 2349, 2637, 0.12);
    fl.connect(g);
    const end = env(g.gain, t, { a: 0.03, hold: 0.55, dur: 0.75, peak: 0.2 });
    noise(dest, t, { type: 'bandpass', f: 1900, q: 3, dur: 0.75, a: 0.03, hold: 0.55, peak: 0.18 });
    fl.start(t);
    fl.stop(end + 0.02);
    return end;
  },
  gag_signoff: (a, dest, o) => {
    tone(dest, o.t, { f: 2000, f1: 60, glide: 0.22, dur: 0.24, peak: 0.4, a: 0.002 });
    return tone(dest, o.t + 0.24, { f: 3000, dur: 0.04, peak: 0.1, a: 0.001 });
  },
  wpn_boom_record: cue({ limit: 2, loopable: true }, (a, dest, o) => sustain(dest, o, {
    loop: true, peak: 0.6, a: 0.25,
    build: (out, t, end) => {
      const ac = dest.context, hiss = noiseSrc(ac, 'white', t, end), hg = G(ac, 0, out), hp = F(ac, 'highpass', 3500, 0.7, hg);
      hiss.connect(hp);
      hg.gain.setValueAtTime(0.05, t);
      hg.gain.linearRampToValueAtTime(0.35, t + 3);
      glide(hp.frequency, t, 3500, 1200, 3);
      const reel = osc(ac, 'triangle', 70, t, end), rg = G(ac, 0.12, F(ac, 'lowpass', 400, 1, out));
      reel.connect(rg);
      return [hiss, reel, lfo(ac, rg.gain, t, end, { rate: 6, depth: 0.08 })];
    },
    every: [0.45, (out, tt) => {
      formant(out, tt, { base: rnd(95, 130), syl: [{ d: 0.3, p: 0.9, p1: 1.25, v: pick(['o', 'uh', 'aw']), at: 0.26, rl: 0.02 }], peak: 0.18, vib: 25 });
    }],
  })),
  wpn_boom_playback: cue({ limit: 2 }, (a, dest, o) => {
    const t = o.t;
    tone(dest, t, { f: 95, f1: 38, glide: 0.5, dur: 0.9, peak: 0.75, a: 0.003 });
    noise(dest, t, { lp: 700, dur: 0.35, peak: 0.9 });
    whoosh(dest, t, { f0: 300, f1: 1500, dur: 0.5, peak: 0.8, at: 0.1 });
    for (let i = 0; i < 5; i++) {
      formant(dest, t + 0.08 + i * 0.09, { base: rnd(220, 290), syl: [{ d: 0.16, p: 1, p1: rnd(0.75, 1.2), v: pick(['o', 'uh', 'aw']) }], peak: 0.14, vib: 30 });
    }
    gunLayers(dest, t, o, 0.16);
    return t + 1;
  }),
  wpn_chroma_fire: cue({ limit: 3 }, (a, dest, o) => {
    const t = o.t, k = pit(o);
    noise(dest, t, { type: 'lowpass', f: 2600, f1: 280, q: 7, glide: 0.2, dur: 0.24, peak: 1 });
    tone(dest, t, { f: 520 * k, f1: 140 * k, dur: 0.16, peak: 0.4, a: 0.002, vib: 80, vibRate: 30 });
    gunLayers(dest, t, o, 0.14);
    return t + 0.3;
  }),
  wpn_chroma_splat: cue({ limit: 4 }, (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { type: 'bandpass', f: 1400, f1: 250, q: 1.5, dur: 0.2, peak: 1.3 });
    thump(dest, t, { f0: 120, f1: 60, dur: 0.12, peak: 0.6 });
    for (let i = 0; i < 5; i++) { const f = rnd(350, 800); blip(dest, t + 0.05 + i * rnd(0.04, 0.08), f, f * 1.8, 0.05, 0.12); }
    return t + 0.5;
  }),
  wpn_chroma_key: cue({ limit: 4 }, (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { type: 'bandpass', f: 500, f1: 3500, q: 3, dur: 0.4, a: 0.1, peak: 0.9 });
    tone(dest, t, { f: 250, f1: 1400, dur: 0.4, a: 0.05, peak: 0.3, vib: 50, vibRate: 14 });
    return blip(dest, t + 0.4, 900, 1800, 0.04, 0.2);
  }),
  world_space: (a, dest, o) => {
    tone(dest, o.t, { f: 1600, f1: 180, dur: 0.8, peak: 0.15, vib: 60, vibRate: 8 });
    return whoosh(dest, o.t, { f0: 200, f1: 2200, dur: 0.8, peak: 1.4, q: 2, at: 0.3 });
  },
  world_beach: (a, dest, o) => {
    const ac = dest.context, t = o.t;
    let end = t;
    for (const [dt, k] of [[0, 1], [0.35, 1.1]]) {
      const s = O(ac, 'triangle', 1400 * k), g = G(ac, 0, dest), tt = t + dt;
      s.frequency.setValueAtTime(1400 * k, tt);
      s.frequency.exponentialRampToValueAtTime(2400 * k, tt + 0.07);
      s.frequency.exponentialRampToValueAtTime(1200 * k, tt + 0.3);
      s.connect(g);
      end = env(g.gain, tt, { a: 0.02, hold: 0.2, dur: 0.32, peak: 0.16 });
      s.start(tt);
      s.stop(end + 0.02);
    }
    noise(dest, t, { color: 'pink', lp: 1200, dur: 1, a: 0.4, peak: 0.4 });
    return Math.max(end, t + 1);
  },
  world_volcano: (a, dest, o) => {
    const t = o.t;
    blip(dest, t, 110, 360, 0.14, 0.45);
    blip(dest, t + 0.22, 150, 420, 0.14, 0.35);
    return noise(dest, t, { color: 'brown', lp: 200, dur: 0.9, a: 0.05, peak: 0.9 });
  },
  world_underwater: (a, dest, o) => {
    const t = o.t;
    for (let i = 0; i < 9; i++) { const f = rnd(350, 1100); blip(dest, t + rnd(0, 0.65), f, f * 1.7, 0.06, 0.18); }
    return noise(dest, t, { lp: 500, dur: 0.8, a: 0.1, peak: 0.4 });
  },
  world_desert: (a, dest, o) => {
    tone(dest, o.t, { f: 900, f1: 1100, dur: 1, a: 0.4, peak: 0.05, vib: 20 });
    return noise(dest, o.t, { color: 'pink', type: 'bandpass', f: 450, f1: 900, q: 2.5, dur: 1.1, a: 0.4, peak: 1.6 });
  },
  world_moon: (a, dest, o) => theremin(dest, o.t, { notes: [[660, 0.12], [990, 0.2], [880, 0.15]], peak: 0.2, porta: 0.05, vib: 35 }),
  reload_mag: (a, dest, o) => {
    const t = o.t;
    click(dest, t, { f: 2600, peak: 0.5 });
    noise(dest, t + 0.02, { type: 'bandpass', f: 1500, q: 2, dur: 0.05, peak: 1, curve: 'fast' });
    noise(dest, t + 0.35, { type: 'bandpass', f: 1100, q: 2, dur: 0.05, peak: 1.6, curve: 'fast' });
    tone(dest, t + 0.35, { f: 260, dur: 0.05, peak: 0.3, a: 0.001, curve: 'fast' });
    return click(dest, t + 0.37, { f: 3200, peak: 0.6 });
  },
  reload_shell: cue({ limit: 3 }, (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { type: 'bandpass', f: 1500, q: 1.5, dur: 0.06, peak: 1.4 });
    tone(dest, t + 0.05, { f: 900, f1: 800, dur: 0.05, peak: 0.18, a: 0.001 });
    return click(dest, t + 0.08, { f: 3000, peak: 0.9 });
  }),
  reload_speedloader: (a, dest, o) => {
    const t = o.t;
    click(dest, t, { f: 2000, peak: 0.6 });
    for (let i = 0; i < 6; i++) click(dest, t + 0.1 + i * 0.025, { f: rnd(3000, 5000), q: 4, peak: 0.3 });
    click(dest, t + 0.35, { f: 1500, peak: 0.8 });
    return tone(dest, t + 0.35, { f: 400, f1: 300, dur: 0.06, peak: 0.3, a: 0.001, curve: 'fast' });
  },
  reload_battery: (a, dest, o) => {
    const t = o.t;
    boing(dest, t, { f: 520, dur: 0.35, peak: 0.25, rate: 22, depth: 300 });
    click(dest, t, { f: 1600, peak: 0.5 });
    click(dest, t + 0.8, { f: 2200, peak: 0.6 });
    return tone(dest, t + 0.8, { f: 400, dur: 0.04, peak: 0.25, a: 0.001, curve: 'fast' });
  },
  reload_reel: (a, dest, o) => {
    const t = o.t;
    tone(flutter(dest, t, t + 0.5, 25, 0.6), t, { type: 'triangle', f: 300, f1: 1200, dur: 0.5, peak: 0.15, a: 0.03 });
    thump(dest, t + 0.6, { f0: 200, f1: 120, dur: 0.1, peak: 0.5 });
    click(dest, t + 0.6, { f: 1800, peak: 0.5 });
    return click(dest, t + 0.9, { f: 2600, peak: 0.5 });
  },
  reload_goo: (a, dest, o) => {
    const t = o.t;
    for (let i = 0; i < 3; i++) blip(dest, t + i * 0.12, 500 - i * 60, 260 - i * 30, 0.08, 0.3);
    noise(dest, t + 0.4, { hp: 3000, dur: 0.2, peak: 0.3 });
    return click(dest, t + 0.45, { f: 2000, peak: 0.6 });
  },
  dry_fire: cue({ limit: 3 }, (a, dest, o) => {
    tone(dest, o.t, { f: 1100, dur: 0.02, peak: 0.12, a: 0.001, curve: 'fast' });
    return click(dest, o.t, { f: 2400, q: 2, dur: 0.012, peak: 0.9 });
  }),
  weapon_swap: (a, dest, o) => {
    const t = o.t;
    whoosh(dest, t, { f0: 700, f1: 1500, dur: 0.14, peak: 0.8 });
    tone(dest, t + 0.11, { f: 350, dur: 0.03, peak: 0.2, a: 0.001, curve: 'fast' });
    return click(dest, t + 0.11, { f: 1800, peak: 0.6 });
  },
  jumpcut_snip: (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { hp: 5000, dur: 0.015, peak: 0.9, curve: 'fast' });
    noise(dest, t + 0.03, { hp: 5000, dur: 0.015, peak: 0.9, curve: 'fast' });
    tone(dest, t + 0.07, { f: 180, dur: 0.03, peak: 0.3, a: 0.001, curve: 'fast' });
    return click(dest, t + 0.07, { f: 3500, peak: 0.8 });
  },
  grenade_throw: (a, dest, o) => {
    tone(dest, o.t, { f: 880, dur: 0.3, peak: 0.04, trem: 0.5, tremRate: 12 });
    return whoosh(dest, o.t, { f0: 500, f1: 1500, dur: 0.3, peak: 0.9 });
  },
  grenade_bounce: cue({ limit: 4 }, (a, dest, o) => {
    const t = o.t, k = pit(o) * rnd(0.94, 1.06);
    tone(dest, t, { f: 2750 * k, dur: 0.05, peak: 0.12, a: 0.001 });
    click(dest, t, { f: 4000, peak: 0.3 });
    return tone(dest, t, { f: 1800 * k, dur: 0.08, peak: 0.25, a: 0.001 });
  }),
  grenade_explode: cue({ limit: 4 }, (a, dest, o) => {
    const t = o.t;
    tone(dest, t, { f: 110, f1: 55, glide: 0.2, dur: 0.7, peak: 0.75, a: 0.002 });
    noise(dest, t, { lp: 2400, dur: 0.35, peak: 0.85, curve: 'fast' });
    noise(dest, t, { type: 'bandpass', f: 500, f1: 250, q: 1, dur: 0.45, a: 0.01, peak: 0.9 });
    crackle(dest, t + 0.05, { n: 16, span: 0.5, peak: 0.28 });
    tinkle(dest, t + 0.08, { n: 10, span: 0.7, lo: 3000, hi: 7000, peak: 0.08 });
    return t + 0.9;
  }),
  tele_throw: (a, dest, o) => {
    const t = o.t;
    whoosh(dest, t, { f0: 400, f1: 1300, dur: 0.28, peak: 0.9 });
    for (let i = 0; i < 3; i++) click(dest, t + 0.35 + i * 0.05, { f: rnd(1200, 2400), q: 3, peak: 0.5 });
    tone(dest, t + 0.35, { f: 400, dur: 0.05, peak: 0.25, a: 0.001, curve: 'fast' });
    return tone(flutter(dest, t + 0.5, t + 0.8, 40, 0.6), t + 0.5, { type: 'triangle', f: 700, f1: 2600, dur: 0.3, peak: 0.12 });
  },
  // Accelerating ticks over opts.dur (default 6 s, the Tiny Tele fuse).
  tele_tick: (a, dest, o) => {
    const t = o.t, dur = o.dur ?? 6;
    for (let tt = t, i = 0; tt < t + dur - 0.05; i++) {
      const x = (tt - t) / dur;
      click(dest, tt, { f: i % 2 ? 3000 : 2400, q: 4, dur: 0.012, peak: 0.8 });
      tone(dest, tt, { f: i % 2 ? 1500 : 1200, dur: 0.03, peak: 0.14, a: 0.001, curve: 'fast' });
      tt += 0.5 - 0.42 * x * x;
    }
    return t + dur;
  },
  tele_implode: (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { type: 'lowpass', f: 3000, f1: 150, q: 2, glide: 0.25, dur: 0.35, a: 0.06, peak: 0.9 });
    tone(dest, t, { f: 400, f1: 40, glide: 0.3, dur: 0.45, a: 0.05, peak: 0.6 });
    tone(dest, t, { f: 7800, dur: 0.3, peak: 0.02 });
    return Math.max(t + 0.5, tinkle(dest, t + 0.12, { n: 12, span: 0.6, peak: 0.1 }));
  },
  melee_whoosh: (a, dest, o) => whoosh(dest, o.t, { f0: 350 * pit(o), f1: 1400 * pit(o), dur: 0.2, peak: 1.2, q: 1.5, at: 0.45 }),
  melee_hit_skip: (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { type: 'bandpass', f: 2200, q: 1.2, dur: 0.12, hold: 0.08, peak: 1.4, curve: 'fast' });
    tone(dest, t + 0.13, { f: 1850, dur: 0.05, peak: 0.12, a: 0.002, curve: 'fast' });
    noise(dest, t, { lp: 1500, dur: 0.04, peak: 0.9, curve: 'fast' });
    return thump(dest, t, { f0: 170, f1: 80, dur: 0.1, peak: 0.6 });
  },
  melee_hit_roxy: (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { lp: 1800, dur: 0.05, peak: 1, curve: 'fast' });
    tone(dest, t, { type: 'triangle', f: 640, f1: 280, dur: 0.2, peak: 0.1, a: 0.001 });
    return tone(dest, t, { f: 320, f1: 140, dur: 0.28, peak: 0.45, a: 0.001, vib: 150, vibRate: 18 });
  },
  melee_hit_penny: (a, dest, o) => {
    const t = o.t;
    thump(dest, t, { f0: 200, f1: 90, dur: 0.08, peak: 0.5 });
    return metal(dest, t, { f: 560, dur: 0.7, peak: 0.3 });
  },
  melee_hit_duke: (a, dest, o) => {
    const t = o.t;
    formant(dest, t, { base: 120, syl: [{ d: 0.09, p: 1.1, v: 'i', gap: 0.01 }, { d: 0.22, p: 1.45, p1: 1.15, v: 'a' }], breath: 0.5, peak: 0.4, vib: 12 });
    woodblock(dest, t + 0.05, { f: 520, peak: 0.5 });
    thump(dest, t + 0.05, { f0: 150, f1: 70, dur: 0.1, peak: 0.5 });
    return t + 0.4;
  },
  wallbuy_boing: (a, dest, o) => boing(dest, o.t, { f: 300, dur: 0.55, peak: 0.35 }),
};

// ------------------------------------------------------------------------------------------------
// Zombies (positional; the voices take the HRTF slots)
// ------------------------------------------------------------------------------------------------

const Z = { zombie: true, limit: 8 };

const ZOMBIE_CUES = {
  zmb_groan: cue(Z, (a, dest, o) => {
    const t = o.t, syl = [{ d: rnd(0.5, 0.85), p: 1, p1: rnd(0.8, 1.2), v: pick(['o', 'uh', 'aw', 'a']) }];
    if (Math.random() < 0.4) syl.push({ d: rnd(0.3, 0.5), p: rnd(0.9, 1.1), p1: rnd(0.7, 0.95), v: pick(['o', 'uh']) });
    const end = formant(dest, t, { base: rnd(90, 140) * pit(o), syl, peak: 0.3, vib: 22, vibRate: rnd(4, 6), breath: 0.25, q: 4 });
    noise(dest, t, { hp: 3000, dur: end - t, a: 0.1, peak: 0.05 });
    return end;
  }),
  zmb_groan_chase: cue(Z, (a, dest, o) => {
    const n = 2 + (Math.random() < 0.5 ? 1 : 0), syl = [];
    for (let i = 0; i < n; i++) syl.push({ d: rnd(0.16, 0.26), p: 1 + i * 0.12, p1: 1.1 + i * 0.12, v: pick(['a', 'aw', 'uh']), gap: 0.05 });
    return formant(dest, o.t, { base: rnd(120, 160) * pit(o), syl, peak: 0.32, vib: 30, vibRate: 7, breath: 0.35, q: 4 });
  }),
  zmb_clap: cue(Z, (a, dest, o) => {
    const f = rnd(1300, 1700);
    clap(dest, o.t, { f, peak: 0.8 });
    return clap(dest, o.t + 0.28, { f, peak: 0.7 });
  }),
  zmb_swipe: cue(Z, (a, dest, o) => whoosh(dest, o.t, { f0: 400, f1: 1800, dur: 0.22, peak: 1.2, at: 0.5 })),
  zmb_hit: cue({ limit: 6 }, (a, dest, o) => {
    const t = o.t, k = pit(o) * rnd(0.94, 1.06);
    noise(dest, t, { lp: 2500, dur: 0.03, peak: 0.6, curve: 'fast' });
    return tone(dest, t, { f: 300 * k, f1: 120 * k, dur: 0.12, peak: 0.45, a: 0.001 });
  }),
  zmb_head_pop: cue({ limit: 6 }, (a, dest, o) => {
    const t = o.t, k = pit(o);
    click(dest, t, { f: 3000, peak: 0.8 });
    noise(dest, t, { type: 'bandpass', f: 1500, q: 1, dur: 0.04, peak: 1, curve: 'fast' });
    return tone(dest, t, { f: 800 * k, f1: 200 * k, glide: 0.05, dur: 0.08, peak: 0.6, a: 0.001 });
  }),
  zmb_death_static: cue({ limit: 6 }, (a, dest, o) => {
    const t = o.t;
    tone(dest, t, { f: 900, f1: 150, dur: 0.35, peak: 0.1 });
    return noise(flutter(dest, t, t + 0.55, 32, 0.95), t, { hp: 1000, dur: 0.55, a: 0.01, peak: 0.7, curve: 'lin' });
  }),
  board_tear: cue({ limit: 6 }, (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { type: 'bandpass', f: 2400, q: 1.3, dur: 0.07, peak: 1.6, curve: 'fast' });
    noise(dest, t + 0.02, { type: 'bandpass', f: 900, q: 1.5, dur: 0.22, peak: 1.4 });
    tone(F(dest.context, 'lowpass', 900, 1, dest), t + 0.03, { type: 'sawtooth', f: 160, f1: 110, dur: 0.18, peak: 0.12, vib: 40, vibRate: 25 });
    return tone(dest, t, { f: 200, f1: 170, dur: 0.12, peak: 0.6, a: 0.001, curve: 'fast' });
  }),
  board_repair: cue({ limit: 6 }, (a, dest, o) => {
    const t = o.t, k = pit(o) * rnd(0.94, 1.06);
    woodblock(dest, t, { f: 1300 * k, peak: 0.25 });
    tone(dest, t, { f: 200 * k, dur: 0.08, peak: 0.22, a: 0.001, curve: 'fast' });
    tone(dest, t, { f: 3200 * k, dur: 0.1, peak: 0.04, a: 0.001 });
    return tone(dest, t, { f: 720 * k, f1: 680 * k, dur: 0.12, peak: 0.22, a: 0.001 });
  }),
  window_vault: cue({ limit: 4 }, (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { lp: 1200, dur: 0.2, a: 0.03, peak: 0.8 });
    noise(dest, t + 0.28, { lp: 600, dur: 0.06, peak: 0.8, curve: 'fast' });
    return thump(dest, t + 0.28, { f0: 120, f1: 70, dur: 0.12, peak: 0.6 });
  }),
  screen_telegraph: cue({ tv: true, limit: 6 }, (a, dest, o) => {
    const t = o.t;
    tone(F(dest.context, 'lowpass', 1500, 1, dest), t, { type: 'sawtooth', f: 150, f1: 600, dur: 1.25, a: 1.1, peak: 0.06, curve: 'fast' });
    crackle(dest, t + 0.9, { n: 6, span: 0.3, peak: 0.4 });
    return noise(dest, t, { hp: 600, dur: 1.25, a: 1.1, peak: 0.55, curve: 'fast' });
  }),
  screen_emerge: cue({ limit: 6 }, (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { type: 'lowpass', f: 400, f1: 2000, q: 8, dur: 0.35, peak: 1.4 });
    tone(dest, t, { f: 180, f1: 520, dur: 0.3, peak: 0.25, vib: 60, vibRate: 20 });
    return blip(dest, t + 0.33, 300, 900, 0.05, 0.35);
  }),
  sock_boing: cue(Z, (a, dest, o) => {
    const t = o.t, k = pit(o);
    tone(dest, t, { type: 'triangle', f: 600 * k, f1: 1900 * k, dur: 0.25, peak: 0.06, vib: 60, vibRate: 16 });
    return tone(dest, t, { f: 300 * k, f1: 950 * k, dur: 0.25, peak: 0.35, vib: 60, vibRate: 16 });
  }),
  sock_giggle: cue(Z, (a, dest, o) => formant(dest, o.t, {
    base: 440 * pit(o), syl: [{ d: 0.07, p: 1, v: 'ee', gap: 0.03 }, { d: 0.07, p: 1.12, v: 'i', gap: 0.03 }, { d: 0.12, p: 0.95, p1: 0.85, v: 'ee' }],
    breath: 0.5, peak: 0.28, vib: 20,
  })),
  sock_leap: cue(Z, (a, dest, o) => {
    whoosh(dest, o.t, { f0: 600, f1: 1600, dur: 0.25, peak: 0.6 });
    return slideWhistle(dest, o.t, { from: 500, to: 1600, dur: 0.3, peak: 0.25 });
  }),
  sock_deflate: cue(Z, (a, dest, o) => {
    const t = o.t;
    tone(dest, t, { f: 900, f1: 250, dur: 0.6, peak: 0.06 });
    tone(flutter(F(dest.context, 'lowpass', 600, 1, dest), t, t + 0.5, 25, 0.8), t, { type: 'sawtooth', f: 70, dur: 0.5, peak: 0.1 });
    return noise(dest, t, { type: 'bandpass', f: 3200, f1: 350, q: 3, dur: 0.7, a: 0.02, peak: 1.8 });
  }),
  fc_hum: cue(Z, (a, dest, o) => {
    const t = o.t, notes = ['G4', 'A4', 'B4', 'D5', 'B4'], k = pit(o);
    notes.forEach((n, i) => {
      tone(dest, t + i * 0.22, { f: note(n) * k, dur: 0.24, a: 0.03, hold: 0.14, peak: 0.2, vib: 30, vibRate: 5.5 });
      tone(dest, t + i * 0.22, { type: 'triangle', f: note(n) * k, dur: 0.24, a: 0.03, hold: 0.14, peak: 0.06 });
    });
    return t + notes.length * 0.22 + 0.05;
  }),
  fc_twirl: cue(Z, (a, dest, o) => {
    const t = o.t;
    for (const dt of [0, 0.22, 0.38]) whoosh(dest, t + dt, { f0: 500, f1: 1400, dur: 0.18, peak: 0.8 });
    return slideWhistle(dest, t, { from: 600, to: 1400, dur: 0.5, peak: 0.12 });
  }),
  fc_rumble: cue(Z, (a, dest, o) => {
    tone(dest, o.t, { f: 45, dur: 1.5, a: 0.25, peak: 0.25, trem: 0.5, tremRate: 5 });
    return noise(dest, o.t, { color: 'brown', lp: 200, dur: 1.6, a: 0.25, peak: 1 });
  }),
  fc_lightning: cue(Z, (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { hp: 2200, dur: 0.12, peak: 0.55, curve: 'fast' });
    crackle(dest, t, { n: 10, span: 0.15, peak: 0.25 });
    tone(dest, t, { f: 80, dur: 0.06, hold: 0.04, peak: 0.45, a: 0.001, curve: 'fast' });
    return noise(dest, t + 0.05, { color: 'brown', lp: 300, dur: 0.8, a: 0.03, peak: 0.5 });
  }),
  fc_cloud_pop: cue(Z, (a, dest, o) => {
    const t = o.t;
    blip(dest, t, 450, 1100, 0.06, 0.4);
    for (let i = 0; i < 3; i++) blip(dest, t + rnd(0.08, 0.3), 2500, 1800, 0.04, 0.08);
    return noise(dest, t, { type: 'bandpass', f: 900, q: 1, dur: 0.18, peak: 0.9 });
  }),
  fc_sob: cue(Z, (a, dest, o) => formant(dest, o.t, {
    base: 190 * pit(o), syl: [{ d: 0.12, p: 1.2, p1: 1.1, v: 'uh', gap: 0.05 }, { d: 0.12, p: 1.15, p1: 1, v: 'uh', gap: 0.05 }, { d: 0.45, p: 1.25, p1: 0.8, v: 'oo' }],
    breath: 0.6, vib: 45, vibRate: 7, peak: 0.35,
  })),
  fc_umbrella: cue(Z, (a, dest, o) => {
    const t = o.t;
    blip(dest, t, 400, 1000, 0.05, 0.4);
    noise(dest, t, { type: 'bandpass', f: 1200, q: 1, dur: 0.05, peak: 0.8, curve: 'fast' });
    [72, 76, 79, 84, 88, 91].forEach((m, i) => pluck(dest, t + 0.06 + i * 0.05, { type: 'triangle', f: mtof(m), dur: 0.6, peak: 0.14 }));
    return t + 0.95;
  }),
  bs_roll: cue({ ...Z, loopable: true }, (a, dest, o) => sustain(dest, o, {
    loop: true, peak: 0.35, a: 0.2,
    build: (out, t, end) => {
      const ac = dest.context, n = noiseSrc(ac, 'brown', t, end), rum = osc(ac, 'sine', 50, t, end), rg = G(ac, 0.25, out);
      n.connect(F(ac, 'lowpass', 200, 1.2, out));
      rum.connect(rg);
      return [n, rum, lfo(ac, rg.gain, t, end, { rate: 3, depth: 0.12 })];
    },
    every: [0.4, (out, tt) => { click(out, tt, { f: rnd(700, 1100), q: 3, dur: 0.012, peak: 0.25 }); }],
  })),
  bs_squeak: cue(Z, (a, dest, o) => {
    const t = o.t;
    tone(dest, t, { type: 'triangle', f: 1900, f1: 2400, dur: 0.22, peak: 0.18, vib: 50, vibRate: 25 });
    return tone(dest, t + 0.12, { type: 'triangle', f: 2100, f1: 1800, dur: 0.2, peak: 0.14, vib: 50, vibRate: 25 });
  }),
  bs_rush: cue(Z, (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { type: 'bandpass', f: 2500, q: 6, dur: 0.8, a: 0.05, peak: 1.2 });
    return tone(dest, t, { type: 'triangle', f: 2000, dur: 0.9, a: 0.05, hold: 0.6, peak: 0.14, vib: 60, vibRate: 11 });
  }),
  bs_wall_bonk: cue(Z, (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { lp: 1500, dur: 0.05, peak: 1, curve: 'fast' });
    metal(dest, t, { f: 330, dur: 0.5, peak: 0.15 });
    boing(dest, t + 0.03, { f: 160, dur: 0.5, peak: 0.18 });
    return tone(dest, t, { f: 240, f1: 90, glide: 0.2, dur: 0.3, peak: 0.8, a: 0.001 });
  }),
  bs_flash_charge: cue(Z, (a, dest, o) => {
    const t = o.t;
    tone(dest, t, { type: 'triangle', f: 400, f1: 4000, glide: 1, dur: 1.05, a: 0.05, hold: 0.95, peak: 0.035, curve: 'fast' });
    return tone(dest, t, { f: 400, f1: 4000, glide: 1, dur: 1.05, a: 0.05, hold: 0.95, peak: 0.11, curve: 'fast' });
  }),
  bs_flash_pop: cue(Z, (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { hp: 1200, dur: 0.1, peak: 0.5, curve: 'fast' });
    tone(dest, t, { f: 1500, dur: 0.08, peak: 0.2, a: 0.001 });
    return thump(dest, t, { f0: 150, f1: 60, dur: 0.08, peak: 0.4 });
  }),
  bs_death: cue(Z, (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { hp: 1200, dur: 0.1, peak: 0.6, curve: 'fast' });
    tone(dest, t, { f: 1500, dur: 0.1, peak: 0.2, a: 0.001 });
    thump(dest, t, { f0: 160, f1: 55, dur: 0.18, peak: 0.45 });
    crackle(dest, t + 0.1, { n: 8, span: 0.4, peak: 0.3 });
    return Math.max(t + 0.6, tinkle(dest, t + 0.05, { n: 12, span: 0.6, lo: 3000, hi: 7000, peak: 0.1 }));
  }),
};

// ------------------------------------------------------------------------------------------------
// Power-ups, player, UI, world
// ------------------------------------------------------------------------------------------------

const POWERUP_CUES = {
  pu_spawn: (a, dest, o) => {
    const t = o.t;
    [84, 88, 91, 96, 100].forEach((m, i) => {
      tone(dest, t + i * 0.055, { f: mtof(m), dur: 0.35, peak: 0.14, a: 0.001 });
      tone(dest, t + i * 0.055, { f: mtof(m) * 4, dur: 0.06, peak: 0.03, a: 0.001 });
    });
    return t + 0.6;
  },
  pu_idle: cue({ range: 10, limit: 6, loopable: true }, (a, dest, o) => sustain(dest, o, {
    loop: true, peak: 0.5, a: 0.6,
    build: (out, t, end) => {
      const ac = dest.context, w = G(ac, 0.75, out), s = [osc(ac, 'sine', 523.25, t, end), osc(ac, 'sine', 784, t, end), osc(ac, 'sine', 1318.5, t, end)];
      s[0].connect(G(ac, 0.2, w));
      s[1].connect(G(ac, 0.14, w));
      s[2].connect(G(ac, 0.05, w));
      s.push(lfo(ac, w.gain, t, end, { rate: 0.8, depth: 0.25 }), lfo(ac, s[2].detune, t, end, { rate: 5, depth: 12 }));
      return s;
    },
  })),
  pu_expire: (a, dest, o) => {
    const t = o.t;
    for (let i = 0; i < 3; i++) noise(dest, t + rnd(0, 0.5), { hp: 2000, dur: 0.06, peak: 0.5, curve: 'fast' });
    tone(dest, t, { f: 1200, f1: 300, dur: 0.3, peak: 0.06 });
    return Math.max(t + 0.6, crackle(dest, t, { n: 14, span: 0.6, peak: 0.4 }));
  },
  pu_cancelled: (a, dest, o) => {
    const t = o.t, c = t + 0.18;
    noise(dest, t, { type: 'bandpass', f: 2500, q: 1, dur: 0.05, peak: 1.5, curve: 'fast' });
    metal(dest, t, { f: 700, dur: 0.3, peak: 0.25 });
    noise(dest, c, { lp: 700, dur: 0.15, peak: 1.1, curve: 'fast' });
    metal(dest, c, { f: 180, dur: 0.5, peak: 0.3 });
    return tone(dest, c, { f: 95, f1: 40, glide: 0.15, dur: 0.4, peak: 0.75, a: 0.001, curve: 'fast' });
  },
  // Wah, wah, wah, wahhh: Bb3-A3-Ab3-G3 on two sawtooths with a per-note wah and vibrato on the last.
  pu_sad_trombone: (a, dest, o) => {
    const ac = dest.context, t = o.t, notes = [58, 57, 56, 55], lens = [0.42, 0.42, 0.42, 1.2], pk = 0.28;
    const g = G(ac, 0, dest), lp = F(ac, 'lowpass', 600, 2, g), s = [O(ac, 'sawtooth', mtof(58)), O(ac, 'sawtooth', mtof(58))];
    s[1].detune.value = 8;
    g.gain.setValueAtTime(0, t);
    let tt = t;
    notes.forEach((m, i) => {
      const f = mtof(m), d = lens[i], last = i === notes.length - 1;
      for (const v of s) glide(v.frequency, tt, f * 1.03, f, 0.06);
      g.gain.linearRampToValueAtTime(pk, tt + 0.04);
      g.gain.setValueAtTime(pk, tt + (last ? 0.35 : d - 0.08));
      g.gain.linearRampToValueAtTime(last ? 0 : 0.05, tt + d - 0.01);
      lp.frequency.setValueAtTime(500, tt);
      lp.frequency.linearRampToValueAtTime(1900, tt + 0.1);
      lp.frequency.linearRampToValueAtTime(900, tt + d);
      tt += d;
    });
    const vg = G(ac, 0), vo = O(ac, 'sine', 5.5);
    vg.gain.setValueAtTime(0, tt - 1.1);
    vg.gain.linearRampToValueAtTime(40, tt - 0.6);
    vo.connect(vg);
    for (const v of s) { vg.connect(v.detune); v.connect(lp); }
    for (const n of [...s, vo]) { n.start(t); n.stop(tt + 0.05); }
    return tt;
  },
  pu_full_reel: (a, dest, o) => {
    const t = o.t;
    for (let i = 0; i < 16; i++) click(dest, t + i / 24, { f: 1800 + (i % 2) * 500, q: 3, peak: 0.45 });
    tone(dest, t, { type: 'triangle', f: 200, f1: 320, dur: 0.65, peak: 0.05, trem: 0.6, tremRate: 24 });
    return ding(dest, t + 0.65, { f: 1568, dur: 1.2, peak: 0.3 });
  },
  pu_one_take: (a, dest, o) => {
    const t = o.t, h = t + 0.08;
    noise(dest, t, { type: 'bandpass', f: 2500, q: 1.5, dur: 0.03, peak: 1.4, curve: 'fast' });
    woodblock(dest, t, { f: 1600, peak: 0.45 });
    chord(brass, dest, h, [48, 55, 60, 64].map(mtof), { dur: 0.55, peak: 0.18, a: 0.006 });
    chord(strings, dest, h, [67, 72, 76].map(mtof), { dur: 0.5, peak: 0.1, a: 0.01 });
    thump(dest, h, { f0: 90, f1: 60, dur: 0.5, peak: 0.4 });
    return noise(dest, h, { hp: 5000, dur: 1, peak: 0.25 });
  },
  // opts.flip: the small per-point "ching" used by the points counter during SWEEPS WEEK.
  pu_sweeps_week: (a, dest, o) => {
    const t = o.t;
    if (o.flip) return ding(dest, t, { f: 2000 * rnd(0.98, 1.03), dur: 0.35, peak: 0.2 });
    noise(dest, t, { type: 'bandpass', f: 900, f1: 1600, q: 1.2, dur: 0.16, a: 0.03, peak: 1.2 });
    click(dest, t + 0.15, { f: 2500, peak: 0.6 });
    ding(dest, t + 0.16, { f: 2000, dur: 1.1, peak: 0.3 });
    return ding(dest, t + 0.16, { f: 3000, dur: 0.8, peak: 0.15 });
  },
  pu_gaffer_tape: (a, dest, o) => {
    const t = o.t;
    for (let i = 0; i < 3; i++) {
      const tt = t + i * 0.32;
      noise(flutter(dest, tt, tt + 0.26, rnd(35, 70), 0.8), tt, { type: 'bandpass', f: 2400, f1: 3600, q: 0.7, dur: 0.24, a: 0.01, peak: 1.8 });
    }
    return t + 0.9;
  },
  pu_stand_by: (a, dest, o) => {
    tone(dest, o.t, { f: 2000, dur: 0.25, hold: 0.18, peak: 0.03, curve: 'fast' });
    return tone(dest, o.t, { f: 1000, dur: 0.25, hold: 0.18, peak: 0.25, curve: 'fast' });
  },
};

const STEP = { limit: 4, gap: 0.05 };
const stepK = (o) => pit(o) * (o.foot ? 0.95 : 1);

const PLAYER_CUES = {
  step_carpet: cue(STEP, (a, dest, o) => {
    const k = stepK(o);
    noise(dest, o.t, { lp: 650 * k, dur: 0.08, a: 0.006, peak: 0.7, curve: 'fast' });
    return tone(dest, o.t, { f: 85 * k, dur: 0.06, peak: 0.25, a: 0.002, curve: 'fast' });
  }),
  step_tile: cue(STEP, (a, dest, o) => {
    const k = stepK(o);
    noise(dest, o.t, { type: 'bandpass', f: 2600 * k, q: 1.6, dur: 0.035, peak: 0.8, curve: 'fast' });
    click(dest, o.t, { f: 4200 * k, peak: 0.25 });
    return tone(dest, o.t, { f: 160 * k, dur: 0.03, peak: 0.2, a: 0.001, curve: 'fast' });
  }),
  step_wood: cue(STEP, (a, dest, o) => {
    const k = stepK(o);
    noise(dest, o.t, { type: 'bandpass', f: 900 * k, q: 1.2, dur: 0.05, peak: 0.6, curve: 'fast' });
    return tone(dest, o.t, { f: 190 * k, f1: 150 * k, dur: 0.07, peak: 0.25, a: 0.001, curve: 'fast' });
  }),
  step_gravel: cue(STEP, (a, dest, o) => {
    const k = stepK(o);
    crackle(dest, o.t, { n: 6, span: 0.1, peak: 0.25, lo: 1500 * k, hi: 5000 * k });
    return noise(dest, o.t, { type: 'bandpass', f: 1800 * k, q: 0.7, dur: 0.13, a: 0.01, peak: 0.8 });
  }),
  step_metal: cue(STEP, (a, dest, o) => {
    const k = stepK(o);
    tone(dest, o.t, { f: 1150 * k, dur: 0.12, peak: 0.08, a: 0.001 });
    tone(dest, o.t, { f: 1830 * k, dur: 0.08, peak: 0.05, a: 0.001 });
    noise(dest, o.t, { hp: 3000, dur: 0.03, peak: 0.3, curve: 'fast' });
    return tone(dest, o.t, { f: 140 * k, dur: 0.04, peak: 0.2, a: 0.001, curve: 'fast' });
  }),
  jump: (a, dest, o) => {
    tone(dest, o.t, { f: 280, f1: 560, dur: 0.13, peak: 0.2, a: 0.005 });
    return whoosh(dest, o.t, { f0: 500, f1: 1100, dur: 0.15, peak: 0.6 });
  },
  land: (a, dest, o) => {
    noise(dest, o.t, { lp: 400, dur: 0.08, peak: 0.9, curve: 'fast' });
    return boing(dest, o.t, { f: 140, dur: 0.28, peak: 0.35, rate: 12, depth: 300, rise: 1 });
  },
  // opts.base: the hero's voice pitch in Hz (GDD §4).
  hurt_grunt: cue({ limit: 2 }, (a, dest, o) => formant(dest, o.t, {
    base: (o.base ?? 200) * rnd(0.95, 1.05) * pit(o), syl: [{ d: rnd(0.16, 0.22), p: 1.15, p1: 0.85, v: pick(['uh', 'o', 'a']) }],
    breath: 0.5, peak: 0.32, vib: 15,
  })),
  hurt_static: cue({ bus: 'ui', limit: 2 }, (a, dest, o) => noise(flutter(dest, o.t, o.t + 0.3, 28, 0.7), o.t, {
    hp: 1500, dur: 0.28, a: 0.005, peak: 0.6, curve: 'lin',
  })),
  // One heartbeat period (opts.period, default 0.86 s); audio.loop() chains them.
  heartbeat: cue({ bus: 'ui', limit: 1 }, (a, dest, o) => {
    const t = o.t;
    for (const [dt, pk] of [[0, 0.65], [0.2, 0.45]]) {
      tone(dest, t + dt, { f: 58, f1: 44, dur: 0.16, peak: pk, a: 0.006, curve: 'fast' });
      tone(dest, t + dt, { f: 116, f1: 88, dur: 0.1, peak: pk * 0.35, a: 0.004, curve: 'fast' });
    }
    return t + (o.period ?? 0.86);
  }),
  skate_roll: cue({ limit: 1, loopable: true }, (a, dest, o) => sustain(dest, o, {
    loop: true, peak: 0.3, a: 0.15,
    build: (out, t, end) => {
      const ac = dest.context, n = noiseSrc(ac, 'pink', t, end);
      n.connect(F(ac, 'lowpass', 450, 1, out));
      return [n];
    },
    every: [0.28, (out, tt) => { click(out, tt, { f: rnd(900, 1300), q: 2, dur: 0.01, peak: 0.12 }); }],
  })),
  skate_push: (a, dest, o) => {
    tone(dest, o.t, { type: 'triangle', f: 220, f1: 300, dur: 0.35, peak: 0.06, trem: 0.5, tremRate: 30 });
    return noise(dest, o.t, { type: 'bandpass', f: 700, f1: 1300, q: 2, dur: 0.35, a: 0.1, peak: 1.8 });
  },
  jelly_bwoing: (a, dest, o) => boing(dest, o.t, { f: 150, dur: 0.6, peak: 0.35, rate: 9, depth: 700, rise: 1.4 }),
  smile_ting: (a, dest, o) => {
    tinkle(dest, o.t + 0.03, { n: 3, span: 0.2, lo: 4000, hi: 7000, peak: 0.05 });
    return ding(dest, o.t, { f: 3136, dur: 0.7, peak: 0.2 });
  },
};

const UI = { bus: 'ui' };

const UI_CUES = {
  ui_prompt: cue(UI, (a, dest, o) => {
    tone(dest, o.t, { f: 1500, dur: 0.03, peak: 0.12, a: 0.001, curve: 'fast' });
    return click(dest, o.t, { f: 2100, q: 2, dur: 0.008, peak: 0.9 });
  }),
  ui_buy: cue(UI, (a, dest, o) => {
    const t = o.t, c = t + 0.06;
    noise(dest, t, { type: 'bandpass', f: 3000, q: 1.2, dur: 0.035, peak: 1.4, curve: 'fast' });
    click(dest, t + 0.02, { f: 1800, peak: 0.5 });
    tone(dest, c, { f: 1600, dur: 0.55, peak: 0.16, a: 0.001 });
    tone(dest, c, { f: 2400, dur: 0.45, peak: 0.13, a: 0.001, detune: 6 });
    noise(dest, c, { hp: 5000, dur: 0.2, peak: 0.2 });
    return c + 0.56;
  }),
  ui_denied: cue(UI, (a, dest, o) => tone(F(dest.context, 'lowpass', 1600, 0.8, dest), o.t, {
    type: 'square', f: 120, dur: 0.2, hold: 0.15, peak: 0.18, curve: 'fast',
  })),
  ui_hit: cue({ ...UI, limit: 6, gap: 0.025 }, (a, dest, o) => {
    click(dest, o.t, { f: 2400, peak: 0.2 });
    return tone(dest, o.t, { f: 1200, dur: 0.03, peak: 0.3, a: 0.0008, curve: 'fast' });
  }),
  ui_hit_head: cue({ ...UI, limit: 6, gap: 0.025 }, (a, dest, o) => {
    tone(dest, o.t, { f: 3600, dur: 0.03, peak: 0.08, a: 0.0008, curve: 'fast' });
    return tone(dest, o.t, { f: 2400, dur: 0.045, peak: 0.25, a: 0.0008, curve: 'fast' });
  }),
  ui_kill: cue({ ...UI, limit: 4 }, (a, dest, o) => {
    tone(dest, o.t, { type: 'triangle', f: 1500, dur: 0.04, peak: 0.2, a: 0.001, curve: 'fast' });
    return tone(dest, o.t + 0.035, { f: 2250, dur: 0.12, peak: 0.18, a: 0.001 });
  }),
  ui_points_flip: cue({ ...UI, limit: 3 }, (a, dest, o) => {
    tone(dest, o.t, { f: 650, dur: 0.02, peak: 0.06, a: 0.001, curve: 'fast' });
    return noise(dest, o.t, { type: 'bandpass', f: 1400, q: 1, dur: 0.025, peak: 0.9, curve: 'fast' });
  }),
  ui_round_dial: cue(UI, (a, dest, o) => {
    click(dest, o.t, { f: 2600, q: 3, dur: 0.01, peak: 0.7 });
    click(dest, o.t + 0.018, { f: 1200, q: 2, dur: 0.01, peak: 0.25 });
    return tone(dest, o.t, { f: 560, dur: 0.025, peak: 0.2, a: 0.001, curve: 'fast' });
  }),
  ui_menu_clack: cue(UI, (a, dest, o) => {
    click(dest, o.t, { f: 2400, q: 1.2, dur: 0.016, peak: 1 });
    noise(dest, o.t, { lp: 900, dur: 0.03, peak: 0.5, curve: 'fast' });
    return tone(dest, o.t, { f: 150, f1: 120, dur: 0.07, peak: 0.45, a: 0.001, curve: 'fast' });
  }),
  ui_tune_in: cue(UI, (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { type: 'bandpass', f: 400, f1: 2600, q: 1, dur: 0.3, a: 0.02, peak: 1.5 });
    tone(dest, t + 0.26, { f: 1320, dur: 0.3, a: 0.04, peak: 0.1 });
    return tone(dest, t + 0.22, { f: 880, dur: 0.35, a: 0.05, peak: 0.2 });
  }),
};

const WORLD_CUES = {
  door_poof: (a, dest, o) => {
    const t = o.t;
    tone(dest, t, { f: 200, f1: 90, dur: 0.25, peak: 0.3 });
    tinkle(dest, t + 0.1, { n: 5, span: 0.3, peak: 0.06 });
    return noise(dest, t, { type: 'bandpass', f: 800, f1: 260, q: 0.9, dur: 0.4, a: 0.012, peak: 1.8 });
  },
  door_elephant: (a, dest, o) => {
    const t = o.t;
    tone(F(dest.context, 'lowpass', 180, 1, dest), t, { type: 'sawtooth', f: 42, dur: 1.4, a: 0.3, peak: 0.35, trem: 0.4, tremRate: 7 });
    kazoo(dest, t + 0.5, { f: 330, f1: 470, dur: 0.45, peak: 0.12 });
    return noise(dest, t, { color: 'brown', lp: 160, dur: 1.5, a: 0.3, peak: 0.85 });
  },
  // The station motif G4-C5-E5-G5 on square beeps (an easter-egg clue: pitches are exact).
  door_keypad_motif: (a, dest, o) => {
    const t = o.t, lp = F(dest.context, 'lowpass', 3000, 0.7, dest);
    ['G4', 'C5', 'E5', 'G5'].forEach((n, i) => tone(lp, t + i * 0.14, { type: 'square', f: note(n), dur: 0.11, hold: 0.08, peak: 0.2, a: 0.003, curve: 'fast' }));
    return click(dest, t + 0.62, { f: 1600, peak: 0.5 });
  },
  door_chain_snap: (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { type: 'bandpass', f: 3000, q: 1.2, dur: 0.04, peak: 1.6, curve: 'fast' });
    metal(dest, t, { f: 1500, dur: 0.3, peak: 0.2 });
    for (let i = 0, tt = t + 0.06; i < 8; i++, tt += 0.03 + i * 0.012) click(dest, tt, { f: rnd(2500, 4500), q: 4, peak: 0.4 });
    return metal(dest, t + 0.5, { f: 700, dur: 0.4, peak: 0.15 });
  },
  crt_power_off: (a, dest, o) => {
    const t = o.t;
    tone(dest, t, { f: 1200, f1: 90, glide: 0.12, dur: 0.16, peak: 0.3 });
    thump(dest, t + 0.02, { f0: 110, f1: 60, dur: 0.12, peak: 0.5 });
    crackle(dest, t, { n: 5, span: 0.3, peak: 0.2 });
    return tone(dest, t, { f: 7800, dur: 1.1, a: 0.01, peak: 0.03 });
  },
};

// ------------------------------------------------------------------------------------------------
// Easter egg and boss
// ------------------------------------------------------------------------------------------------

// EE step 3 "CUE THE APPLAUSE" (client pass: every counted kill must read clearly over the kill's own gunshot).
// A big studio audience: three loops of the clap texture at different rates (a denser, bigger crowd than
// applause()) + a pink-noise wash shimmering at ~18 Hz so the claps blur into a roar, band-limited 280 Hz-4.2 kHz,
// fast attack, hold, exponential tail. Returns the end time.
function crowdClaps(dest, t, p = {}) {
  const ac = dest.context, dur = p.dur ?? 1.4;
  const amp = G(ac, 0, dest);
  const lp = F(ac, 'lowpass', p.lp ?? 4200, 0.6, amp);
  const hp = F(ac, 'highpass', 280, 0.7, lp);
  const end = env(amp.gain, t, { a: p.a ?? 0.05, hold: dur * (p.holdFrac ?? 0.35), dur, peak: p.peak ?? 0.6, curve: 'exp' });
  (p.rates ?? [0.93, 1.0, 1.08]).forEach((r, i) => {
    const s = ac.createBufferSource();
    s.buffer = clapBuffer(ac);
    s.loop = true;
    s.playbackRate.value = r * rnd(0.98, 1.02);
    s.connect(G(ac, i ? 0.8 : 1, hp));
    s.start(t, Math.random() * 2.5);
    s.stop(end + 0.02);
  });
  const am = G(ac, 0.65, hp);
  lfo(ac, am.gain, t, end, { rate: rnd(15, 21), depth: 0.35 });
  N(ac, 'pink', t, end).connect(F(ac, 'bandpass', 1800, 0.6, G(ac, p.wash ?? 0.45, am)));
  return end;
}
// The gloves' clap beats (s after the kill); easteregg.js passes its own (CLAP.beats) so sound and hands agree.
const CLAP_BEATS = [0.16, 0.36, 0.56, 0.76, 0.96, 1.16];

const EE_CUES = {
  ee_chime_tunk: (a, dest, o) => {
    noise(dest, o.t, { lp: 800, dur: 0.04, peak: 0.6, curve: 'fast' });
    tone(dest, o.t, { f: 190, dur: 0.08, peak: 0.3, a: 0.001, curve: 'fast' });
    return woodblock(dest, o.t, { f: 380, dur: 0.12, peak: 0.5 });
  },
  ee_neon_stutter: (a, dest, o) => {
    const t = o.t, bp = F(dest.context, 'bandpass', 2400, 2, dest);
    for (const [s, e] of [[0, 0.08], [0.14, 0.2], [0.26, 0.29], [0.4, 0.62], [0.7, 0.74], [0.8, 1.05]]) {
      tone(bp, t + s, { type: 'sawtooth', f: 120, dur: e - s, hold: e - s - 0.012, a: 0.002, peak: 0.5, curve: 'fast' });
      tone(dest, t + s, { f: 120, dur: e - s, hold: e - s - 0.012, a: 0.002, peak: 0.12, curve: 'fast' });
      click(dest, t + s, { f: rnd(2500, 4000), peak: 0.35 });
    }
    return t + 1.1;
  },
  ee_puppet_giggle: (a, dest, o) => {
    const syl = [];
    for (let i = 0, n = 4 + (Math.random() * 2 | 0); i < n; i++) syl.push({ d: rnd(0.06, 0.09), p: rnd(0.95, 1.15), v: pick(['ee', 'i']), gap: 0.03 });
    return formant(dest, o.t, { base: rnd(400, 600) * pit(o), syl, ring: 32, breath: 0.4, peak: 0.3, vib: 20 });
  },
  ee_puppet_reveal: (a, dest, o) => {
    tinkle(dest, o.t + 0.05, { n: 5, span: 0.4, peak: 0.06 });
    return boing(dest, o.t, { f: 330, dur: 0.5, peak: 0.35 });
  },
  // one big, fat clap (three layered hands + a body thump) with a long 0.3 s echo tail (~1.8 s)
  ee_clap_single: (a, dest, o) => {
    const t = o.t, e = echo(dest, { time: 0.3, feedback: 0.58, wet: 0.65, lp: 3400 });
    clap(e, t, { peak: 1.5 });
    clap(e, t + 0.007, { peak: 1.0, f: 1050 });
    clap(e, t + 0.013, { peak: 0.8, f: 2300 });
    thump(e, t, { f0: 190, f1: 90, dur: 0.07, peak: 0.4 });
    return t + 2.4;
  },
  // counted kill, the bleachers' layer (positional, played at both bleachers): a 1.5 s burst of the big crowd with a
  // "whoo!" and sometimes a whistle; linear rolloff to 45 m so it fills Studio A instead of dying within a few metres
  ee_applause_burst: cue({ bus: 'tv', range: 45, wet: 0.35 }, (a, dest, o) => {
    const t = o.t;
    crowd(dest, t + 0.05, { vowel: 'oo', dur: 0.95, voices: 7, peak: 0.1, pitch: rnd(1.3, 1.45) });
    if (Math.random() < 0.55) whistle(dest, t + rnd(0.2, 0.55), 0.05);
    return crowdClaps(dest, t, { dur: o.dur ?? 1.5, peak: 0.4 });
  }),
  // counted kill, the close layer (non-positional, sfx bus): the audience right around you + the white gloves' own
  // claps on o.claps (s after the kill, default CLAP_BEATS; [] = none), panned a little apart
  ee_applause_near: cue({ bus: 'sfx', gap: 0.05 }, (a, dest, o) => {
    const t = o.t, beats = o.claps ?? CLAP_BEATS;
    let end = crowdClaps(dest, t + 0.01, { dur: o.dur ?? 1.45, peak: 0.32, lp: 5200, a: 0.035, holdFrac: 0.4 });
    beats.forEach((b, i) => {
      const pk = 0.5 * (1 - i * 0.05);
      clap(panner(dest, -0.22), t + b, { peak: pk, f: rnd(1250, 1450), dur: 0.08 });
      clap(panner(dest, 0.22), t + b + 0.006, { peak: pk * 0.8, f: rnd(1650, 1900), dur: 0.07 });
      end = Math.max(end, t + b + 0.15);
    });
    return end;
  }),
  // the tote board's +$1: a mechanical flip-flap (two resonant clacks) heard across the studio
  ee_tote_flip: cue({ limit: 6, range: 30 }, (a, dest, o) => {
    const t = o.t;
    for (const [d, k] of [[0, 1], [0.045, 0.7]]) {
      noise(dest, t + d, { hp: 2500, dur: 0.025, peak: 0.55 * k, curve: 'fast' });
      click(dest, t + d, { f: 2300, peak: 0.8 * k });
      noise(dest, t + d, { type: 'bandpass', f: 1150, q: 7, dur: 0.06, peak: 4.2 * k, curve: 'fast' });
    }
    return t + 0.12;
  }),
  ee_ovation: cue({ bus: 'tv', range: 45, wet: 0.3 }, (a, dest, o) => {
    const t = o.t;
    for (let i = 0; i < 4; i++) whistle(dest, t + rnd(0.4, 2.8), 0.06);
    crowd(dest, t + 0.3, { vowel: 'oo', dur: 2.4, voices: 8, peak: 0.18, pitch: 1.25 });
    return crowdClaps(dest, t, { dur: o.dur ?? 4.2, a: 0.7, holdFrac: 0.45, peak: 0.6 });
  }),
  ee_confetti_cannon: (a, dest, o) => {
    const t = o.t;
    thump(dest, t, { f0: 95, f1: 55, dur: 0.25, peak: 0.8 });
    noise(flutter(dest, t, t + 1.4, 18, 0.6), t + 0.05, { hp: 4000, dur: 1.3, a: 0.1, peak: 0.3 });
    return Math.max(t + 1.35, noise(dest, t, { type: 'lowpass', f: 300, f1: 1500, q: 1, dur: 0.3, a: 0.01, peak: 1.6 }));
  },
  ee_thunder_far: (a, dest, o) => noise(dest, o.t, { color: 'brown', type: 'lowpass', f: 800, f1: 80, glide: 1.5, dur: 1.8, a: 0.03, peak: 0.9 }),
  ee_map_rumble: (a, dest, o) => {
    const t = o.t;
    tone(dest, t, { f: 36, dur: 2.4, a: 0.5, peak: 0.4, trem: 0.4, tremRate: 4 });
    crackle(dest, t + 0.3, { n: 12, span: 2, lo: 2000, hi: 4000, peak: 0.12 });
    return noise(dest, t, { color: 'brown', lp: 130, dur: 2.6, a: 0.5, peak: 1.05 });
  },
  ee_storm_loop: cue({ limit: 2, loopable: true }, (a, dest, o) => sustain(dest, o, {
    loop: true, peak: 0.5, a: 1,
    build: (out, t, end) => {
      const ac = dest.context, n = noiseSrc(ac, 'pink', t, end), w = G(ac, 0.8, out);
      n.connect(F(ac, 'highpass', 2000, 0.7, F(ac, 'lowpass', 9000, 0.7, w)));
      return [n, lfo(ac, w.gain, t, end, { rate: 0.15, depth: 0.2 })];
    },
    every: [0.1, (out, tt) => {
      const f = rnd(1500, 3500);
      blip(out, tt, f, f * 1.3, 0.02, rnd(0.04, 0.1));
      return rnd(0.04, 0.2);
    }],
  })),
  ee_storm_zap: (a, dest, o) => {
    const t = o.t;
    tone(flutter(F(dest.context, 'lowpass', 1500, 1, dest), t, t + 0.45, 30, 0.8), t, { type: 'sawtooth', f: 60, dur: 0.45, peak: 0.3 });
    tone(dest, t, { f: 2400, f1: 300, glide: 0.3, dur: 0.35, peak: 0.2 });
    return Math.max(t + 0.45, crackle(dest, t, { n: 10, span: 0.4, peak: 0.5 }));
  },
  ee_lightning_strike: (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { hp: 1500, dur: 0.16, peak: 0.6, curve: 'fast' });
    crackle(dest, t, { n: 20, span: 0.35, peak: 0.3 });
    tone(dest, t, { f: 70, f1: 35, dur: 0.9, peak: 0.45, a: 0.002 });
    return noise(dest, t + 0.05, { color: 'brown', type: 'lowpass', f: 1500, f1: 90, glide: 2.4, dur: 3, a: 0.05, peak: 0.65 });
  },
  baron_laugh: cue({ tv: true, wet: 0.5 }, (a, dest, o) => {
    const syl = [{ d: 0.1, p: 1, v: 'm', gap: 0 }, { d: 0.32, p: 1.05, p1: 1.25, v: 'a', gap: 0.08 }];
    [1.35, 1.28, 1.2].forEach((p, i) => syl.push({ d: 0.15 + i * 0.02, p, p1: p * 0.92, v: 'a', gap: 0.06 }));
    syl.push({ d: 0.45, p: 1.1, p1: 0.85, v: 'a' });
    return baronVoice(dest, o, syl, { peak: 0.15, breath: 0.4, vib: 25 });
  }),
  ee_tape_thread: (a, dest, o) => {
    const t = o.t;
    thump(dest, t, { f0: 180, f1: 110, dur: 0.1, peak: 0.5 });
    click(dest, t, { f: 1600, peak: 0.5 });
    tone(flutter(dest, t + 0.2, t + 1.3, 20, 0.4), t + 0.2, { type: 'triangle', f: 180, f1: 260, dur: 1.1, a: 0.1, peak: 0.1 });
    tone(dest, t + 0.6, { f: 2600, f1: 2900, dur: 0.2, peak: 0.05, a: 0.03 });
    for (const dt of [0.9, 1.1, 1.45]) click(dest, t + dt, { f: rnd(1800, 2600), peak: 0.45 });
    return thump(dest, t + 1.45, { f0: 160, f1: 100, dur: 0.1, peak: 0.4 });
  },
  ee_tracking_click: cue({ limit: 3 }, (a, dest, o) => {
    click(dest, o.t, { f: 1800, q: 2, dur: 0.014, peak: 1 });
    click(dest, o.t + 0.02, { f: 900, q: 2, dur: 0.012, peak: 0.4 });
    return tone(dest, o.t, { f: 240, f1: 200, dur: 0.06, peak: 0.45, a: 0.001, curve: 'fast' });
  }),
  // Endless: 440 Hz reference plus 440 + 2.5·d Hz (GDD §13 step 5). handle.setDistance(d) glides the
  // second sine, so the beating (2.5·d Hz) slows as the knob nears the target; opts.d = start distance.
  ee_tracking_tones: cue({ limit: 1, loopable: true }, (a, dest, o) => {
    const ac = dest.context, t = o.t, out = G(ac, 0, dest), dFreq = (d) => 440 + 2.5 * clamp(+d || 0, 0, 12);
    out.gain.setValueAtTime(0, t);
    out.gain.linearRampToValueAtTime(1, t + 0.15);
    const ref = osc(ac, 'sine', 440, t), beat = osc(ac, 'sine', dFreq(o.d ?? 6), t);
    ref.connect(G(ac, 0.18, out));
    beat.connect(G(ac, 0.18, out));
    return loopHandle([ref, beat], null, {
      setDistance(d) { beat.frequency.setTargetAtTime(dFreq(d), ac.currentTime, 0.05); },
    });
  }),
  ee_baron_scream: cue({ tv: true, wet: 0.3 }, (a, dest, o) => {
    const t = o.t, ac = dest.context, bp = F(ac, 'bandpass', 900, 1.5, G(ac, 0.5, dest));
    tone(shaper(bp, 3), t, { type: 'sawtooth', f: 720, f1: 110, glide: 1.5, dur: 1.7, a: 0.05, hold: 1.2, peak: 0.25, vib: 50, vibRate: 7 });
    return noise(flutter(dest, t, t + 1.7, 24, 0.5), t, { hp: 1000, dur: 1.7, a: 0.05, peak: 0.28 });
  }),
  ee_cage_boing: (a, dest, o) => {
    metal(dest, o.t, { f: 420, dur: 0.6, peak: 0.12 });
    crackle(dest, o.t + 0.05, { n: 6, span: 0.3, lo: 2500, hi: 4500, peak: 0.25 });
    return boing(dest, o.t, { f: 180, dur: 0.7, peak: 0.35 });
  },
  // Electric bell: inharmonic partials struck 18× a second (inverted-sawtooth AM), opts.dur (10 s).
  ee_alarm_bell: (a, dest, o) => {
    const ac = dest.context, t = o.t, dur = o.dur ?? 10, end = t + dur, g = G(ac, 0, dest), am = G(ac, 0.5, g);
    const clapper = osc(ac, 'sawtooth', 18, t, end);
    clapper.connect(G(ac, -0.5, am.gain));
    [[1150, 0.5], [2760, 0.25], [4100, 0.12], [5600, 0.06]].forEach(([f, v]) => osc(ac, 'sine', f, t, end).connect(G(ac, v, am)));
    env(g.gain, t, { a: 0.03, hold: dur - 0.3, dur, peak: 0.35, curve: 'exp' });
    return end;
  },
  ee_switch_thunk: (a, dest, o) => {
    const t = o.t;
    noise(dest, t, { lp: 1200, dur: 0.1, peak: 0.8, curve: 'fast' });
    metal(dest, t, { f: 250, dur: 0.35, peak: 0.2 });
    noise(flutter(dest, t, t + 0.14, 60, 0.8), t + 0.01, { hp: 3000, dur: 0.12, peak: 0.4 });
    return thump(dest, t, { f0: 100, f1: 50, dur: 0.25, peak: 0.65 });
  },
  ee_tower_off: (a, dest, o) => {
    const t = o.t;
    let tt = t;
    for (let i = 0; i < 8; i++, tt += 0.09 * Math.pow(1.25, i)) click(dest, tt, { f: 3200 * Math.pow(0.85, i), q: 3, peak: 0.55 });
    tone(F(dest.context, 'lowpass', 500, 1, dest), t, { type: 'sawtooth', f: 120, f1: 35, glide: 1.6, dur: 1.8, a: 0.02, peak: 0.25 });
    return Math.max(t + 1.8, thump(dest, tt, { f0: 120, f1: 60, dur: 0.15, peak: 0.5 }));
  },
};

const BOSS_CUES = {
  boss_form: (a, dest, o) => {
    const ac = dest.context, t = o.t, end = t + 2.6, pan = panner(dest, 0);
    const pl = lfo(ac, pan.pan, t, end, { rate: 1.5, depth: 0.8 });
    glide(pl.frequency, t, 1.5, 6, 2.4);
    noise(pan, t, { type: 'bandpass', f: 300, f1: 4000, q: 2, dur: 2.6, a: 2.3, peak: 1.4 });
    const lp = F(ac, 'lowpass', 200, 2, dest);
    glide(lp.frequency, t, 200, 2400, 2.4);
    tone(shaper(lp, 2), t, { type: 'sawtooth', f: 55, f1: 220, dur: 2.6, a: 2.2, peak: 0.25 });
    crackle(dest, t + 2.2, { n: 10, span: 0.4, peak: 0.5 });
    return end;
  },
  // opts.syllables: how many "wah" syllables (default 3–6).
  boss_voice: cue({ tv: true, wet: 0.3, limit: 2 }, (a, dest, o) => {
    const n = o.syllables ?? 3 + (Math.random() * 4 | 0), syl = [];
    for (let i = 0; i < n; i++) {
      const p = rnd(0.9, 1.5);
      syl.push({ d: i === n - 1 ? 0.35 : rnd(0.14, 0.24), p, p1: p * rnd(0.85, 1.1), v: pick(['a', 'o', 'aw', 'a']), gap: rnd(0.03, 0.08) });
    }
    return baronVoice(dest, o, syl);
  }),
  boss_teleport: (a, dest, o) => {
    const t = o.t, b = t + 0.4;
    tone(dest, t, { f: 1500, f1: 80, glide: 0.18, dur: 0.2, peak: 0.35 });
    tone(dest, t + 0.2, { f: 2400, dur: 0.04, peak: 0.1, a: 0.001 });
    tone(dest, b, { f: 80, f1: 1500, glide: 0.18, dur: 0.2, peak: 0.3 });
    tone(dest, b + 0.2, { f: 120, dur: 0.35, peak: 0.4, trem: 0.8, tremRate: 16 });
    return tone(dest, b + 0.2, { f: 60, dur: 0.35, peak: 0.4, trem: 0.8, tremRate: 16 });
  },
  boss_static_ball: cue({ limit: 6, loopable: true }, (a, dest, o) => sustain(dest, o, {
    dur: 1.5, peak: 1.2, a: 0.05,
    build: (out, t, end) => {
      const ac = dest.context, n = noiseSrc(ac, 'white', t, end), bp = F(ac, 'bandpass', 1400, 3, flutter(out, t, end, 26, 0.5));
      n.connect(bp);
      return [n, lfo(ac, bp.frequency, t, end, { rate: 7, depth: 900 })];
    },
  })),
  boss_sweep_warn: (a, dest, o) => tone(dest, o.t, { f: 1000, f1: 1800, glide: 0.9, dur: 1, a: 0.02, hold: 0.9, peak: 0.22, trem: 0.9, tremRate: 10, curve: 'fast' }),
  boss_sweep: (a, dest, o) => {
    const t = o.t, lp = F(dest.context, 'lowpass', 500, 2, dest);
    lp.frequency.setValueAtTime(500, t);
    lp.frequency.exponentialRampToValueAtTime(2600, t + 0.5);
    lp.frequency.exponentialRampToValueAtTime(700, t + 1.4);
    for (const m of [36, 43, 48, 51, 55, 58, 62]) tone(lp, t, { type: 'square', f: mtof(m), detune: rnd(-15, 15), dur: 1.4, a: 0.08, hold: 1.1, peak: 0.06 });
    return t + 1.4;
  },
  boss_grab: (a, dest, o) => {
    tone(dest, o.t, { f: 220, f1: 70, dur: 0.4, peak: 0.2 });
    return whoosh(dest, o.t, { f0: 250, f1: 2500, dur: 0.45, peak: 1.4, at: 0.5 });
  },
  boss_offair: (a, dest, o) => {
    const t = o.t;
    tone(dest, t, { f: 7800, dur: 1.6, peak: 0.035 });
    crackle(dest, t, { n: 18, span: 1, peak: 0.45 });
    tone(dest, t, { f: 600, f1: 50, glide: 0.8, dur: 0.9, peak: 0.35 });
    return Math.max(t + 1.6, thump(dest, t + 0.9, { f0: 120, f1: 55, dur: 0.2, peak: 0.6 }));
  },
  boss_hurt: cue({ tv: true, wet: 0.3, limit: 2 }, (a, dest, o) => {
    noise(flutter(dest, o.t, o.t + 0.2, 30, 0.7), o.t, { hp: 1500, dur: 0.2, peak: 0.4 });
    return baronVoice(dest, o, [{ d: 0.1, p: 1.8, v: 'a', gap: 0 }, { d: 0.28, p: 1.7, p1: 1.05, v: 'o' }], { peak: 0.17 });
  }),
  boss_goodnight: (a, dest, o) => {
    const t = o.t;
    let tt = t;
    [['G5', 0.45], ['E5', 0.5], ['D5', 0.6], ['C5', 0.9]].forEach(([n, d], i) => {
      musicBox(dest, tt, { f: note(n) * (1 - i * 0.006), dur: 1.3, peak: 0.25 });
      tt += d;
    });
    crowd(dest, t + 0.3, { vowel: 'aw', dur: 1.8, voices: 8, peak: 0.25 });
    return tt + 0.9;
  },
};

// ------------------------------------------------------------------------------------------------
// Area ambience (endless, ambience bus) and hidden toys
// ------------------------------------------------------------------------------------------------

const AMB = { bus: 'ambience', limit: 2, loopable: true };

// Lobby muzak: a 120 BPM ii-V-I-VI bossa in eighth notes (4 eighths = one clock tick per second).
const BOSSA = [
  { keys: [53, 57, 60, 64], bass: 50 }, { keys: [53, 59, 64], bass: 55 },
  { keys: [52, 55, 59, 62], bass: 48 }, { keys: [55, 58, 61], bass: 57 },
];
const CLAVE = new Set([0, 3, 6, 10, 12]);

// Two-tone phone ring burst (440 + 480 Hz, 2 s) with a bell-like 20 Hz flutter, panned.
function phoneRing(dest, t, pan, peak = 0.05) {
  const p = panner(dest, pan);
  tone(p, t, { f: 440, dur: 2, a: 0.02, hold: 1.9, peak, curve: 'fast', trem: 0.6, tremRate: 20 });
  return tone(p, t, { f: 480, dur: 2, a: 0.02, hold: 1.9, peak, curve: 'fast', trem: 0.6, tremRate: 20 });
}

// Three quick 4.4 kHz pulses: a cricket (or the cricket toy).
function cricket(dest, t, f = 4400, peak = 0.04) {
  for (let i = 0; i < 3; i++) tone(dest, t + i * 0.05, { f, dur: 0.025, peak, a: 0.002, curve: 'fast' });
  return t + 0.15;
}

// Mains hum at 60 Hz with its first harmonics; `peak` is the fundamental's level.
function mains(ac, out, t, end, peak) {
  return [[60, 1], [120, 0.6], [180, 0.3]].map(([f, v]) => {
    const s = osc(ac, 'sine', f, t, end);
    s.connect(G(ac, peak * v, out));
    return s;
  });
}

const AMBIENCE_CUES = {
  amb_lobby: cue(AMB, (a, dest, o) => {
    let muzak = null;   // the exhibit TV's thin speaker band
    return sustain(dest, o, {
      loop: true, peak: 1, a: 1.5,
      build: (out) => {
        const ac = dest.context;
        muzak = F(ac, 'highpass', 350, 0.7, F(ac, 'lowpass', 3500, 0.7, G(ac, 1.6, out)));
        return [];
      },
      every: [0.25, (out, tt, i) => {
        const bar = BOSSA[Math.floor(i / 8) % 4], s = i % 8;
        if (s === 0 || s === 3 || s === 5) for (const m of bar.keys) epiano(muzak, tt, { f: mtof(m), dur: 0.5, peak: 0.05 });
        if (s === 0 || s === 4) tone(muzak, tt, { type: 'triangle', f: mtof(bar.bass), dur: 0.45, peak: 0.16, a: 0.005 });
        if (s === 3 || s === 7) tone(muzak, tt, { type: 'triangle', f: mtof(bar.bass + 7), dur: 0.3, peak: 0.12, a: 0.005 });
        if (CLAVE.has(i % 16)) rim(muzak, tt, { peak: 0.1 });
        if (s % 4 === 0) click(out, tt, { f: (i / 4) % 2 ? 2300 : 2700, q: 5, dur: 0.01, peak: 0.2 });
      }],
    });
  }),
  amb_newsroom: cue(AMB, (a, dest, o) => {
    let left = 0;
    return sustain(dest, o, {
      loop: true, peak: 1, a: 1.5,
      build: (out, t, end) => {
        const ac = dest.context, buzz = osc(ac, 'sawtooth', 120, t, end);
        buzz.connect(F(ac, 'bandpass', 1600, 2, G(ac, 0.05, out)));
        return [buzz, ...mains(ac, out, t, end, 0.05)];
      },
      every: [0.09, (out, tt) => {
        if (left <= 0) { left = 8 + (Math.random() * 16 | 0); return rnd(0.8, 2.5); }
        left--;
        click(out, tt, { f: rnd(1800, 3200), q: 3, peak: 0.22 });
        tone(out, tt, { f: 250, dur: 0.03, peak: 0.05, a: 0.001, curve: 'fast' });
        if (left === 0 && Math.random() < 0.3) ding(out, tt + 0.1, { f: 2600, dur: 0.6, peak: 0.04 });
        return rnd(0.07, 0.11);
      }],
    });
  }),
  amb_green_room: cue(AMB, (a, dest, o) => sustain(dest, o, {
    loop: true, peak: 1, a: 1.5,
    build: (out, t, end) => {
      const ac = dest.context, w = G(ac, 0.85, out), comp = osc(ac, 'sawtooth', 50, t, end);
      comp.connect(F(ac, 'lowpass', 300, 1, G(ac, 0.03, w)));
      return [comp, ...mains(ac, w, t, end, 0.07), lfo(ac, w.gain, t, end, { rate: 0.21, depth: 0.15 })];
    },
    every: [2, (out, tt) => { blip(out, tt, 90, 220, 0.25, 0.1); return rnd(1.5, 4); }],
  })),
  amb_studio_a: cue(AMB, (a, dest, o) => sustain(dest, o, {
    loop: true, peak: 1, a: 2,
    build: (out, t, end) => {
      const ac = dest.context, n = noiseSrc(ac, 'pink', t, end), w = G(ac, 0.18, out), w2 = G(ac, 0.12, out);
      n.connect(F(ac, 'bandpass', 450, 1.2, w));
      n.connect(F(ac, 'bandpass', 1300, 2, w2));
      return [n, lfo(ac, w.gain, t, end, { rate: 0.2, depth: 0.05 }), lfo(ac, w2.gain, t, end, { rate: 0.13, depth: 0.04 })];
    },
    every: [0.5, (out, tt, i) => {
      if (i % 12 === 1) phoneRing(out, tt, -0.55, 0.07);
      if ((i + 5) % 14 === 0) phoneRing(out, tt, 0.5, 0.055);
    }],
  })),
  amb_studio_b: cue(AMB, (a, dest, o) => {
    const tune = [79, 76, 72, 74, 76, 79, 81, 79, 76, 74, 72, 74, 76, 72, 67, 72];
    let crick = 0;
    return sustain(dest, o, {
      loop: true, peak: 1, a: 1.5,
      build: (out, t, end) => {
        const ac = dest.context, n = noiseSrc(ac, 'pink', t, end);
        n.connect(F(ac, 'lowpass', 400, 0.7, G(ac, 0.04, out)));
        return [n];
      },
      every: [0.6, (out, tt, i) => {
        musicBox(out, tt, { f: mtof(tune[i % tune.length]), dur: 1.2, peak: 0.12 });
        if (tt >= crick) { if (crick) cricket(out, tt + 0.3, 4200, 0.05); crick = tt + rnd(3, 6); }
        return i % 4 === 3 ? 1.1 : 0.55;
      }],
    });
  }),
  amb_master_control: cue(AMB, (a, dest, o) => sustain(dest, o, {
    loop: true, peak: 1, a: 1.5,
    build: (out, t, end) => {
      const ac = dest.context, fan = noiseSrc(ac, 'pink', t, end);
      fan.connect(F(ac, 'lowpass', 1200, 0.7, G(ac, 0.05, out)));
      return [fan, ...mains(ac, out, t, end, 0.08)];
    },
    every: [1, (out, tt) => {
      click(out, tt, { f: rnd(1500, 3500), q: 4, peak: 0.16 });
      if (Math.random() < 0.3) click(out, tt + 0.07, { f: rnd(1500, 3500), q: 4, peak: 0.12 });
      return rnd(0.25, 1.8);
    }],
  })),
  amb_yard: cue(AMB, (a, dest, o) => {
    let car = 0;
    return sustain(dest, o, {
      loop: true, peak: 1, a: 2,
      build: (out, t, end) => {
        const ac = dest.context, wind = noiseSrc(ac, 'pink', t, end), wg = G(ac, 0.25, out), lp = F(ac, 'lowpass', 400, 0.8, wg);
        wind.connect(lp);
        const hum = [osc(ac, 'sine', 120, t, end), osc(ac, 'sine', 121.5, t, end), osc(ac, 'sine', 240, t, end)], neon = osc(ac, 'sawtooth', 120, t, end);
        hum[0].connect(G(ac, 0.02, out));
        hum[1].connect(G(ac, 0.016, out));
        hum[2].connect(G(ac, 0.008, out));
        neon.connect(F(ac, 'bandpass', 2500, 3, G(ac, 0.012, out)));
        return [wind, neon, ...hum, lfo(ac, lp.frequency, t, end, { rate: 0.1, depth: 150 }), lfo(ac, wg.gain, t, end, { rate: 0.07, depth: 0.15 })];
      },
      every: [0.25, (out, tt, i) => {
        if (i % 2 === 0 && Math.random() < 0.7) cricket(out, tt, 4400, 0.025);
        if (i % 3 === 1 && Math.random() < 0.5) cricket(out, tt + 0.1, 3900, 0.018);
        if (tt >= car) {
          if (car) {
            const p = panner(out, -0.8);
            p.pan.setValueAtTime(-0.8, tt);
            p.pan.linearRampToValueAtTime(0.8, tt + 4);
            noise(p, tt, { color: 'brown', lp: 300, dur: 4, a: 2, peak: 0.2 });
          }
          car = tt + rnd(8, 15);
        }
      }],
    });
  }),
  // Pre-power 60 Hz at -42 dB (GDD §15).
  amb_hum: cue(AMB, (a, dest, o) => sustain(dest, o, {
    loop: true, peak: db(-42), a: 1,
    build: (out, t, end) => mains(dest.context, out, t, end, 1),
  })),
};

const TOY_CUES = {
  toy_bell: (a, dest, o) => ding(dest, o.t, { f: 2200, dur: 1.6, peak: 0.35 }),
  toy_camera_zoom: (a, dest, o) => {
    const t = o.t;
    click(dest, t, { f: 2000, peak: 0.5 });
    tone(dest, t, { f: 800, dur: 0.03, peak: 0.15, a: 0.001, curve: 'fast' });
    tone(F(dest.context, 'lowpass', 1200, 1, dest), t + 0.1, { type: 'sawtooth', f: 320, f1: 520, dur: 1, a: 0.05, hold: 0.85, peak: 0.08, curve: 'fast' });
    tone(dest, t + 0.1, { type: 'triangle', f: 1600, f1: 2400, dur: 1, a: 0.05, hold: 0.85, peak: 0.02, curve: 'fast' });
    return click(dest, t + 1.15, { f: 1700, peak: 0.5 });
  },
  toy_lava: (a, dest, o) => {
    const t = o.t;
    let tt = t;
    for (let i = 0; i < 8; i++) { tone(dest, tt, { f: 90, f1: 240, dur: 0.2, a: 0.03, peak: 0.25 }); tt += 0.6 - i * 0.055; }
    return tt;
  },
  toy_payphone: (a, dest, o) => {
    const t = o.t, band = F(dest.context, 'highpass', 300, 0.7, F(dest.context, 'lowpass', 3400, 0.7, dest));
    thump(dest, t, { f0: 200, f1: 120, dur: 0.08, peak: 0.4 });
    click(dest, t, { f: 1500, peak: 0.4 });
    for (let i = 0; i < 4; i++) {
      tone(band, t + 0.3 + i, { f: 480, dur: 0.5, a: 0.01, hold: 0.47, peak: 0.1, curve: 'fast' });
      tone(band, t + 0.3 + i, { f: 620, dur: 0.5, a: 0.01, hold: 0.47, peak: 0.1, curve: 'fast' });
    }
    return t + 3.8;
  },
  toy_typewriter: (a, dest, o) => {
    const t = o.t;
    for (const dt of [0, 0.13, 0.22, 0.4, 0.5, 0.63]) {
      click(dest, t + dt, { f: rnd(2200, 3000), q: 2, peak: 0.7 });
      tone(dest, t + dt, { f: 400, dur: 0.03, peak: 0.15, a: 0.001, curve: 'fast' });
    }
    ding(dest, t + 0.8, { f: 2637, dur: 0.9, peak: 0.2 });
    for (let i = 0; i < 6; i++) click(dest, t + 0.95 + i * 0.05, { f: 1500, q: 4, peak: 0.2 });
    noise(dest, t + 0.95, { type: 'bandpass', f: 1500, f1: 3000, q: 2, dur: 0.35, peak: 0.8 });
    return t + 1.7;
  },
  toy_globe: (a, dest, o) => {
    const t = o.t;
    let tt = t;
    while (tt < t + 3) { click(dest, tt, { f: 1400, q: 3, peak: 0.9 }); tt += 0.05 + 0.28 * Math.pow((tt - t) / 3, 2); }
    return Math.max(tt, noise(dest, t, { type: 'bandpass', f: 600, q: 1, dur: 3, a: 0.05, peak: 0.6 }));
  },
  toy_teletype: (a, dest, o) => {
    const t = o.t;
    for (let tt = t; tt < t + 3; tt += rnd(0.06, 0.12)) click(dest, tt, { f: rnd(1800, 3200), q: 3, peak: 0.5 });
    tone(F(dest.context, 'lowpass', 300, 1, dest), t, { type: 'sawtooth', f: 60, dur: 3.2, a: 0.1, hold: 2.9, peak: 0.08, curve: 'fast' });
    return noise(flutter(dest, t + 3.05, t + 3.35, 50, 0.7), t + 3.05, { type: 'bandpass', f: 2500, q: 1, dur: 0.25, peak: 1 });
  },
  toy_laff: cue({ tv: true, bus: 'tv' }, (a, dest, o) => laughter(dest, o.t, { dur: 2.6, voices: 7, peak: 0.28 })),
  toy_switcher: (a, dest, o) => {
    const t = o.t;
    thump(dest, t, { f0: 180, f1: 120, dur: 0.06, peak: 0.4 });
    click(dest, t, { f: 2000, peak: 0.6 });
    for (let i = 0; i < 16; i++) click(dest, t + 0.08 + i * 0.025, { f: 1500 + i * 120, q: 4, peak: 0.3 });
    return tone(dest, t + 0.5, { f: 1500, dur: 0.1, hold: 0.06, peak: 0.1, curve: 'fast' });
  },
  toy_ghost_light: (a, dest, o) => {
    const t = o.t;
    click(dest, t, { f: 2500, peak: 0.6 });
    tone(dest, t, { f: 300, dur: 0.03, peak: 0.2, a: 0.001, curve: 'fast' });
    tone(dest, t + 0.02, { f: 3500, dur: 0.15, peak: 0.04, a: 0.001 });
    return tone(dest, t + 0.02, { f: 120, dur: 0.6, a: 0.05, peak: 0.06 });
  },
  toy_wheel: (a, dest, o) => {
    const t = o.t;
    let tt = t, gap = 0.04;
    while (tt < t + 4) { click(dest, tt, { f: 3000, q: 3, peak: 0.5 }); tone(dest, tt, { f: 1500, dur: 0.02, peak: 0.06, a: 0.001, curve: 'fast' }); tt += gap; gap *= 1.07; }
    return ding(dest, tt + 0.15, { f: 1760, dur: 1.2, peak: 0.25 });
  },
  toy_train: (a, dest, o) => {
    const t = o.t, p = panner(dest, 0);
    for (const dt of [0, 0.35]) {
      for (const f of [740, 932]) tone(dest, t + dt, { f, dur: 0.25, a: 0.02, hold: 0.18, peak: 0.1, vib: 10 });
      noise(dest, t + dt, { type: 'bandpass', f: 900, q: 2, dur: 0.25, a: 0.02, hold: 0.18, peak: 0.3 });
    }
    lfo(dest.context, p.pan, t + 0.7, t + 3.3, { rate: 0.4, depth: 0.7 });
    for (let i = 0; i < 10; i++) noise(p, t + 0.7 + i * 0.25, { type: 'bandpass', f: 1200, q: 1, dur: 0.12, a: 0.005, peak: 0.9, curve: 'fast' });
    return t + 3.3;
  },
  // Fallback for music.js's xylophone: opts.notes (MIDI) or a random 3-note pentatonic tune.
  toy_xylophone: (a, dest, o) => {
    const notes = o.notes || Array.from({ length: 3 }, () => pick([72, 74, 76, 79, 81, 84, 86, 88]));
    notes.forEach((m, i) => {
      const tt = o.t + i * 0.22, f = mtof(m);
      tone(dest, tt, { f, dur: 0.5, peak: 0.25, a: 0.001 });
      tone(dest, tt, { f: f * 3.9, dur: 0.08, peak: 0.08, a: 0.001 });
      click(dest, tt, { f: Math.min(8000, f * 4), peak: 0.15 });
    });
    return o.t + notes.length * 0.22 + 0.5;
  },
};

export const SFX_CUES = {
  ...TELLY_CUES, ...CROWD_CUES, ...SPONSOR_CUES, ...UPLINK_CUES, ...SIGNON_CUES, ...WEAPON_CUES,
  ...ZOMBIE_CUES, ...POWERUP_CUES, ...PLAYER_CUES, ...UI_CUES, ...WORLD_CUES,
  ...EE_CUES, ...BOSS_CUES, ...AMBIENCE_CUES, ...TOY_CUES,
};
