// DEAD AIR — audio.js
// WebAudio engine (ARCHITECTURE §10, GDD §15): lazy AudioContext, bus graph, per-area convolution reverb,
// positional voices, TV-speaker filter, ducking/low-HP muffle, loops, area ambience, music delegation
// and the automatic hookups of the trivial generic cues to game events.
//
// Public API (game.audio)
//   play(id, { pos, vol=1, rate=1, detune=0, delay=0, bus, tv, pan, ...recipeOpts }) -> Voice | null
//       Voice: { id, stop(fade), setPos(v), setVol(v, ramp), playing, ...recipe methods }. Unknown ids,
//       or a call before the first user gesture, return null silently.
//   loop(id, { pos, vol }) -> LoopHandle { stop(fade), setPos(v), setVol(v, ramp), setDistance(d), playing }
//       Always returns a handle (inert for unknown ids). A loop requested before the first gesture starts
//       as soon as the context exists. Pass `pos` at creation to make it positional. Inherent loop
//       recipes run until stopped; one-shot recipes are retriggered back to back.
//   music(stateId)  stopAll()  duck(db, lowpassHz, seconds)  setMasterVolume(v)  setBusVolume(bus, v)
//   getBusVolume(bus)  init()  update(dt)  reset()  unlock()
//
// Internal API (music.js / sfx.js)
//   ctx (null until the first gesture)  now()  synth (toolkit, also `export { synth }`)
//   bus = { master, music, sfx, ambience, ui, tv }: GainNodes. sfx/ambience/tv form the "world" group that
//       duck()/the low-HP muffle filter and that feeds the area reverb; music and ui bypass both.
//       master -> DynamicsCompressor -> limiter -> soft clip -> destination.
//   out({ bus, pos, tv, vol, pan, range, zombie, wet }) -> AudioNode (voice input) or null before unlock.
//       pos: THREE.Vector3 or [x,y,z] -> PannerNode (HRTF for up to 8 concurrent `zombie` voices, else
//       equal-power) with distance attenuation + air absorption; range: max audible distance (linear
//       rolloff); tv: bandpass 300–4000 Hz + mild waveshaper; wet: extra reverb send.
//   registerCues(table, defaults?)  table = { id: (a, dest, o) => endTime | handle | undefined }
//       a = synth; dest = voice input; o = play opts + { t (start time), ac, pitch (rate·detune), loop }.
//       Return the end time for one-shots, or { stop(t), update?(now), end?, ...methods } for loops.
//       Optional static props on a recipe function: bus, tv, zombie, range, ref, vol, limit, gap, wet.
//       Cues registered while createMusic() runs default to the 'music' bus. Later registrations win.
//   createMusic(audio) from music.js is called once the context exists; its update(dt) is driven by an
//   internal 25 ms ticker (exactly once per tick, in every game state). Any failure disables music only.
//
// Automatic hookups (callers don't play these themselves): ui_hit / ui_hit_head (zombie:hit), ui_kill,
// footsteps per floor surface (player:step; its `surface`, else level.surfaceAt; skate_push when sprinting
// on Roller Boogie), jump, land, hurt_grunt (per-hero voice pitch) + hurt_static (+ jelly_bwoing with
// Wobble-Up), low-HP heartbeat and 1.2 kHz muffle, ui_buy on every spend, ui_denied, points flips (ka-ching
// in SWEEPS WEEK), weapon fire (wpn_<id>, chirp/upgraded layers inside), dry_fire, weapon_swap, melee
// whoosh/hit, wallbuy_boing, power-up spawn/grab + announcer (+ pu_bossa_bed under PLEASE STAND BY), the
// commercial duck, ui_prompt, area ambience. Door beats (poof, chain snap, keypad motif, elephant, DY buzz,
// crowd ooh), board_tear / board_repair, light_thunk and onair_clack are played by the world (level.js,
// doors.js, windows.js) in sync with their animations.
// Identical plays of one id within its `gap` (default 30 ms) at the same spot are merged, so a system
// that also plays one of these by hand is harmless.

import { SFX_CUES, synth } from './sfx.js';
import * as musicModule from './music.js';

export { synth };

const AREA_REVERB = { lobby: 0.8, newsroom: 0.9, green_room: 0.5, studio_a: 1.8, studio_b: 1.2, master_control: 0.4, yard: 0.3 };
const HERO_VOICE = { skip: 210, roxy: 260, penny: 240, duke: 120 };
const WORLD_BUSES = ['sfx', 'ambience', 'tv'];
const REVERB_SEND = { sfx: 0.2, ambience: 0.12, tv: 0.16 };
const DEFAULT_VOLUMES = { master: 0.9, music: 0.75, sfx: 1, ambience: 0.8, ui: 0.85, tv: 1 };
const FIRE_CUES = { revolver_38: 'wpn_revolver_38', pump_37: 'wpn_pump_37', mp7: 'wpn_mp7', m16a1: 'wpn_m16a1', m60: 'wpn_m60', zapper: 'wpn_zapper', chroma_key: 'wpn_chroma_fire' };
const PU_CUES = { cancelled: 'pu_cancelled', full_reel: 'pu_full_reel', one_take: 'pu_one_take', sweeps_week: 'pu_sweeps_week', gaffer_tape: 'pu_gaffer_tape', please_stand_by: 'pu_stand_by' };
const PU_RHYTHM = { cancelled: [1.1, 0.9], full_reel: [1, 0.85], one_take: [1.15, 0.9], sweeps_week: [1, 1.1, 0.85], gaffer_tape: [1.1, 0.95, 1.05, 0.85], please_stand_by: [1.05, 1, 0.95, 1.12, 0.8] };
const LOW_HP = 0.35, MAX_VOICES = 96, MAX_HRTF = 8, LOOKAHEAD = 0.4, START_LAG = 0.012;

const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const px = (p) => (p.x ?? p[0] ?? 0), py = (p) => (p.y ?? p[1] ?? 0), pz = (p) => (p.z ?? p[2] ?? 0);

// Soft clip after the limiter: identity below 0.8, smooth knee, never above 0.985.
function clipCurve() {
  const n = 2048, c = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const x = (i / (n - 1)) * 2 - 1, ax = Math.abs(x);
    c[i] = ax <= 0.8 ? x : Math.sign(x) * (0.8 + 0.185 * Math.tanh((ax - 0.8) / 0.185));
  }
  return c;
}

// One playing cue: its output chain plus whatever the recipe returned.
class Voice {
  constructor(audio, id, recipe, chain, ret, ro, looping) {
    this.audio = audio;
    this.id = id;
    this.recipe = recipe;
    this.chain = chain;
    this.ro = ro;
    this.looping = looping;
    this.inner = ret && typeof ret === 'object' ? ret : null;
    this.end = typeof ret === 'number' ? ret : this.inner ? this.inner.end ?? Infinity : ro.t + 4;
    this.stopped = false;
    this.disposed = false;
    if (this.inner) {
      for (const k of Object.keys(this.inner)) {
        if (typeof this.inner[k] === 'function' && !(k in this)) this[k] = this.inner[k].bind(this.inner);
      }
    }
  }
  get playing() { return !this.stopped && !this.disposed && this.audio.ctx.currentTime < this.end; }
  stop(fade = 0.06) {
    if (this.stopped || this.disposed) return;
    this.stopped = true;
    const now = this.audio.ctx.currentTime, f = Math.max(0.005, fade);
    synth.release(this.chain.input.gain, now, f);
    if (this.inner && this.inner.stop) this.inner.stop(now + f);
    this.end = Math.min(this.end, now + f + 0.05);
  }
  setPos(p) {
    if (p && this.chain.panner) this.audio._placePanner(this.chain, p);
  }
  setVol(v, ramp = 0.05) {
    if (this.stopped || this.disposed) return;
    const g = this.chain.input.gain, now = this.audio.ctx.currentTime;
    g.cancelScheduledValues(now);
    g.setTargetAtTime(v * this.chain.baseVol, now, Math.max(0.001, ramp / 3));
  }
  update(now) {
    if (this.disposed) return;
    if (this.inner && this.inner.update && !this.stopped) this.inner.update(now);
    if (this.looping && !this.inner && !this.stopped && now + LOOKAHEAD >= this.end) {
      this.ro.t = Math.max(this.end, now + START_LAG);
      const r = this.recipe(synth, this.chain.input, this.ro);
      this.end = typeof r === 'number' && r > this.ro.t ? r : this.ro.t + 1;
    }
  }
  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    for (const n of this.chain.nodes) n.disconnect();
  }
}

// Stable handle returned by loop(): survives being requested before the context exists.
class LoopHandle {
  constructor(audio, id, opts) {
    this.audio = audio;
    this.id = id;
    this.opts = { ...opts };
    this.voice = null;
    this.stopped = false;
    this._dist = null;
  }
  get playing() { return !!(this.voice && this.voice.playing); }
  _start() {
    if (this.stopped || this.voice) return;
    const v = this.audio._launch(this.id, this.opts, true);
    if (!v) return;
    this.voice = v;
    if (v.inner) {
      for (const k of Object.keys(v.inner)) {
        if (typeof v.inner[k] === 'function' && !(k in this)) this[k] = v.inner[k].bind(v.inner);
      }
    }
    if (this._dist != null) this.setDistance(this._dist);
  }
  stop(fade = 0.12) {
    this.stopped = true;
    if (this.voice) this.voice.stop(fade);
  }
  setPos(p) {
    this.opts.pos = p;
    if (this.voice) this.voice.setPos(p);
  }
  setVol(v, ramp = 0.1) {
    this.opts.vol = v;
    if (this.voice) this.voice.setVol(v, ramp);
  }
  setDistance(d) {
    this._dist = d;
    if (this.voice && this.voice.inner && this.voice.inner.setDistance) this.voice.inner.setDistance(d);
  }
}

export class Audio {
  constructor(game) {
    this.game = game;
    this.ctx = null;
    this.bus = null;
    this.synth = synth;
    this.cues = Object.create(null);
    this.cueDefaults = Object.create(null);
    this.voices = [];
    this.volumes = { ...DEFAULT_VOLUMES };
    this._n = null;
    this._music = null;
    this._musicState = null;
    this._regDefaults = null;
    this._pending = [];
    this._last = new Map();
    this._warned = new Set();
    this._irs = Object.create(null);
    this._rv = { area: null, active: 0, switchedAt: -10, fadeOut: -1 };
    this._amb = { id: null, handle: null, hum: null, suspended: false };
    this._area = null;
    this._lowHp = false;
    this._heart = null;
    this._prompt = null;
    this._timer = 0;
    this._lastTick = 0;
    this._gesture = () => this.unlock();
    this.registerCues(SFX_CUES);
  }

  // ---------------------------------------------------------------- lifecycle
  init() {
    if (typeof window !== 'undefined') {
      for (const ev of ['pointerdown', 'keydown', 'touchstart', 'mousedown']) window.addEventListener(ev, this._gesture, true);
    }
    this._hookEvents();
  }

  unlock() {
    if (!this.ctx) {
      const AC = typeof window !== 'undefined' && (window.AudioContext || window.webkitAudioContext);
      if (!AC) return;
      try { this.attach(new AC({ latencyHint: 'interactive' })); } catch (e) { this._warn('ctx', e); return; }
    }
    if (this.ctx.state === 'suspended' && this.ctx.resume) this.ctx.resume().catch(() => {});
    if (this.ctx.state === 'running' && typeof window !== 'undefined') {
      for (const ev of ['pointerdown', 'keydown', 'touchstart', 'mousedown']) window.removeEventListener(ev, this._gesture, true);
    }
  }

  // Binds the engine to a context (the page's AudioContext, or an OfflineAudioContext for tests).
  attach(ctx, { music = true } = {}) {
    if (this.ctx) return;
    this.ctx = ctx;
    this._build(ctx);
    if (typeof ctx.startRendering !== 'function' && typeof setInterval !== 'undefined') {
      this._lastTick = performance.now();
      this._timer = setInterval(() => this._tick(), 25);
    }
    const pending = this._pending;
    this._pending = [];
    for (const h of pending) h._start();
    // Load time: building the music engine (~70 ms of synthesis) waits for the frame after the unlocking gesture,
    // so the key press that opens character select does not stall on it (the requested state is kept and applied).
    if (music) {
      if (typeof ctx.startRendering === 'function' || typeof requestAnimationFrame !== 'function') this._startMusic();
      else requestAnimationFrame(() => setTimeout(() => { if (this.ctx === ctx && !this._music) this._startMusic(); }, 0));
    }
  }

  reset() {
    for (const v of this.voices) if (v.chain.bus !== this.bus?.music) v.stop(0.1);
    for (const h of this._pending) h.stop();
    this._pending = [];
    this._amb = { id: null, handle: null, hum: null, suspended: false };
    this._area = null;
    this._lowHp = false;
    this._heart = null;
    this._prompt = null;
    if (this._n) {
      const now = this.ctx.currentTime;
      this._n.world.gain.cancelScheduledValues(now);
      this._n.world.gain.setTargetAtTime(1, now, 0.05);
      this._n.duckLp.frequency.cancelScheduledValues(now);
      this._n.duckLp.frequency.setTargetAtTime(20000, now, 0.05);
      this._n.muffLp.frequency.setTargetAtTime(20000, now, 0.05);
    }
  }

  update() {
    if (!this.ctx || !this._n) return;
    this._updateListener();
    this._updateArea();
    this._updateHealth();
    this._updatePrompt();
    this._schedule(this.ctx.currentTime);
  }

  // ---------------------------------------------------------------- graph
  _build(ctx) {
    const G = (v, dest) => { const g = ctx.createGain(); g.gain.value = v; if (dest) g.connect(dest); return g; };
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -16; comp.knee.value = 12; comp.ratio.value = 3; comp.attack.value = 0.004; comp.release.value = 0.25;
    const lim = ctx.createDynamicsCompressor();
    lim.threshold.value = -2.5; lim.knee.value = 0; lim.ratio.value = 20; lim.attack.value = 0.001; lim.release.value = 0.08;
    const clip = ctx.createWaveShaper();
    clip.curve = clipCurve();
    const master = G(this.volumes.master);
    master.connect(comp); comp.connect(lim); lim.connect(clip); clip.connect(ctx.destination);
    const muffLp = ctx.createBiquadFilter();
    muffLp.type = 'lowpass'; muffLp.frequency.value = 20000; muffLp.Q.value = 0.5;
    muffLp.connect(master);
    const duckLp = ctx.createBiquadFilter();
    duckLp.type = 'lowpass'; duckLp.frequency.value = 20000; duckLp.Q.value = 0.5;
    duckLp.connect(muffLp);
    const world = G(1, duckLp);
    const bus = { master };
    for (const name of ['music', 'ui']) bus[name] = G(this.volumes[name], master);
    for (const name of WORLD_BUSES) bus[name] = G(this.volumes[name], world);
    const rvIn = G(1), rvOut = G(1, world);
    const conv = [ctx.createConvolver(), ctx.createConvolver()];
    const convGain = [G(0, rvOut), G(0, rvOut)];
    conv[0].connect(convGain[0]); conv[1].connect(convGain[1]);
    for (const name of WORLD_BUSES) bus[name].connect(G(REVERB_SEND[name], rvIn));
    this.bus = bus;
    this._n = { comp, lim, clip, world, duckLp, muffLp, rvIn, conv, convGain, out: clip };
    this._setReverb('lobby', true);
  }

  // Procedural stereo IR: exponentially decaying, progressively darker noise (-60 dB at `decay`).
  _ir(area) {
    if (this._irs[area]) return this._irs[area];
    const ctx = this.ctx, sr = ctx.sampleRate, decay = AREA_REVERB[area] ?? 0.8;
    const len = Math.floor(sr * (decay * 1.1 + 0.06)), pre = Math.floor(sr * 0.006);
    const buf = ctx.createBuffer(2, len, sr);
    for (let c = 0; c < 2; c++) {
      const d = buf.getChannelData(c);
      let lp = 0;
      for (let i = pre; i < len; i++) {
        const tt = (i - pre) / sr, k = 0.85 - 0.6 * Math.min(1, tt / decay);
        lp += ((Math.random() * 2 - 1) - lp) * k;
        d[i] = lp * Math.exp((-6.9 * tt) / decay);
      }
      if (area === 'yard') {
        for (const [at, amp] of [[0.12, 0.55], [0.24, 0.2]]) {
          const s = Math.floor(sr * at) + c * 7;
          for (let i = 0; i < sr * 0.008 && s + i < len; i++) d[s + i] += (Math.random() * 2 - 1) * amp * Math.exp(-i / (sr * 0.0025));
        }
      }
    }
    return (this._irs[area] = buf);
  }

  _setReverb(area, immediate = false) {
    const rv = this._rv, n = this._n, now = this.ctx.currentTime;
    if (rv.area === area) return;
    if (!immediate && now - rv.switchedAt < 1) return;
    const next = immediate && rv.area === null ? 0 : 1 - rv.active, prev = rv.active;
    if (rv.fadeOut === next) rv.fadeOut = -1;
    n.conv[next].buffer = this._ir(area);
    n.rvIn.connect(n.conv[next]);
    n.convGain[next].gain.cancelScheduledValues(now);
    n.convGain[next].gain.setTargetAtTime(1, now, immediate ? 0.001 : 0.15);
    if (next !== prev) {
      n.convGain[prev].gain.cancelScheduledValues(now);
      n.convGain[prev].gain.setTargetAtTime(0, now, 0.15);
      rv.fadeOut = prev;
    }
    rv.active = next;
    rv.area = area;
    rv.switchedAt = now;
  }

  // Per-voice output chain: input gain -> [TV speaker] -> [air lowpass + panner | stereo pan] -> bus.
  _chain(o) {
    const ctx = this.ctx, bus = this.bus[o.bus] || this.bus.sfx;
    const baseVol = (o.norm ?? 1) * (o.tv ? 1.35 : 1);
    const input = ctx.createGain();
    input.gain.value = (o.vol ?? 1) * baseVol;
    const nodes = [input];
    let tail = input;
    const link = (node) => { tail.connect(node); nodes.push(node); tail = node; return node; };
    if (o.tv) {
      const hp = link(ctx.createBiquadFilter()); hp.type = 'highpass'; hp.frequency.value = 300; hp.Q.value = 0.7;
      const pk = link(ctx.createBiquadFilter()); pk.type = 'peaking'; pk.frequency.value = 2200; pk.Q.value = 1; pk.gain.value = 3;
      const lp = link(ctx.createBiquadFilter()); lp.type = 'lowpass'; lp.frequency.value = 4000; lp.Q.value = 0.9;
      const sh = link(ctx.createWaveShaper()); sh.curve = synth.softCurve(1.8);
    }
    let panner = null, air = null, hrtf = false;
    if (o.pos) {
      hrtf = !!o.zombie && this._hrtfCount() < MAX_HRTF;
      air = link(ctx.createBiquadFilter());
      air.type = 'lowpass'; air.Q.value = 0.5;
      panner = link(ctx.createPanner());
      panner.panningModel = hrtf ? 'HRTF' : 'equalpower';
      if (o.range) { panner.distanceModel = 'linear'; panner.refDistance = 1; panner.maxDistance = o.range; panner.rolloffFactor = 1; }
      else { panner.distanceModel = 'inverse'; panner.refDistance = o.ref ?? 2.5; panner.maxDistance = 120; panner.rolloffFactor = 1; }
    } else if (o.pan) {
      const sp = link(ctx.createStereoPanner());
      sp.pan.value = clamp(o.pan, -1, 1);
    }
    tail.connect(bus);
    if (o.wet) {
      const s = ctx.createGain();
      s.gain.value = o.wet;
      tail.connect(s);
      s.connect(this._n.rvIn);
      nodes.push(s);
    }
    const chain = { input, nodes, panner, air, hrtf, bus, baseVol };
    if (panner) this._placePanner(chain, o.pos);
    return chain;
  }

  _placePanner(chain, p) {
    const x = px(p), y = py(p), z = pz(p), pn = chain.panner;
    if (pn.positionX) { pn.positionX.value = x; pn.positionY.value = y; pn.positionZ.value = z; }
    else pn.setPosition(x, y, z);
    const l = this._lpos;
    const d = l ? Math.hypot(x - l[0], y - l[1], z - l[2]) : 0;
    chain.air.frequency.value = clamp(20000 * Math.exp(-d / 22), 2200, 20000);
  }

  _hrtfCount() {
    let n = 0;
    const now = this.ctx.currentTime;
    for (const v of this.voices) if (v.chain.hrtf && !v.disposed && now < v.end) n++;
    return n;
  }

  // ---------------------------------------------------------------- cues
  registerCues(table, defaults = this._regDefaults) {
    if (!table) return;
    for (const id of Object.keys(table)) {
      if (typeof table[id] !== 'function') continue;
      this.cues[id] = table[id];
      this.cueDefaults[id] = defaults || null;
    }
  }

  now() { return this.ctx ? this.ctx.currentTime : 0; }

  out(opts = {}) {
    if (!this.ctx || !this._n) return null;
    return this._chain(opts).input;
  }

  play(id, opts = {}) {
    if (!this.ctx || !this._n || !this.cues[id]) return null;
    if (this.ctx.state !== 'running' && typeof this.ctx.startRendering !== 'function') return null;
    return this._launch(id, opts, false);
  }

  loop(id, opts = {}) {
    const h = new LoopHandle(this, id, opts);
    if (!this.cues[id]) { h.stopped = true; return h; }
    if (!this.ctx || !this._n) this._pending.push(h);
    else h._start();
    return h;
  }

  _launch(id, opts, looping) {
    const recipe = this.cues[id];
    if (!recipe) return null;
    if (!looping && this._duplicate(id, recipe, opts)) return null;
    this._enforceLimits(id, recipe);
    const def = this.cueDefaults[id];
    const chain = this._chain({
      bus: opts.bus || recipe.bus || (def && def.bus) || 'sfx',
      tv: opts.tv ?? recipe.tv,
      pos: opts.pos,
      pan: opts.pan,
      zombie: recipe.zombie,
      range: opts.range ?? recipe.range,
      ref: recipe.ref,
      wet: opts.wet ?? recipe.wet,
      vol: opts.vol ?? 1,
      norm: recipe.vol ?? 1,
    });
    const ro = { ...opts, t: this.ctx.currentTime + START_LAG + (opts.delay || 0), ac: this.ctx, loop: looping };
    ro.pitch = (opts.rate ?? 1) * Math.pow(2, (opts.detune ?? 0) / 1200);
    let ret;
    try {
      ret = recipe(synth, chain.input, ro);
    } catch (e) {
      this._warn('cue:' + id, e);
      for (const n of chain.nodes) n.disconnect();
      return null;
    }
    const v = new Voice(this, id, recipe, chain, ret, ro, looping);
    this.voices.push(v);
    return v;
  }

  _duplicate(id, recipe, opts) {
    const now = this.ctx.currentTime, gap = recipe.gap ?? 0.03, p = opts.pos;
    let last = this._last.get(id);
    if (last && now - last.t < gap) {
      if (!p && !last.has) return true;
      if (p && last.has) {
        const dx = px(p) - last.x, dy = py(p) - last.y, dz = pz(p) - last.z;
        if (dx * dx + dy * dy + dz * dz < 2.25) return true;
      }
    }
    if (!last) this._last.set(id, (last = { t: 0, has: false, x: 0, y: 0, z: 0 }));
    last.t = now;
    last.has = !!p;
    if (p) { last.x = px(p); last.y = py(p); last.z = pz(p); }
    return false;
  }

  _enforceLimits(id, recipe) {
    const limit = recipe.limit ?? 10, now = this.ctx.currentTime;
    let same = 0, oldest = null, live = 0, oldestAny = null;
    for (const v of this.voices) {
      if (v.stopped || v.disposed || now >= v.end) continue;
      live++;
      if (!oldestAny && !v.looping) oldestAny = v;
      if (v.id === id) { same++; if (!oldest) oldest = v; }
    }
    if (same >= limit && oldest) oldest.stop(0.03);
    if (live >= MAX_VOICES && oldestAny) oldestAny.stop(0.03);
  }

  // Loop scheduling, retriggers and disposal of finished voices.
  _schedule(now) {
    const vs = this.voices;
    let w = 0;
    for (let i = 0; i < vs.length; i++) {
      const v = vs[i];
      try { v.update(now); } catch (e) { this._warn('cue:' + v.id, e); v.stop(0.02); }
      if (now > v.end + 0.15) v.dispose();
      else vs[w++] = v;
    }
    vs.length = w;
  }

  _tick() {
    const ctx = this.ctx;
    if (!ctx || ctx.state === 'closed') return;
    const t = performance.now(), dt = Math.min(0.25, (t - this._lastTick) / 1000);
    this._lastTick = t;
    this._schedule(ctx.currentTime);
    if (this._music && this._music.update) {
      try { this._music.update(dt); } catch (e) { this._warn('music.update', e); }
    }
  }

  // ---------------------------------------------------------------- music / global controls
  _startMusic() {
    const create = musicModule.createMusic;
    if (typeof create !== 'function') return;
    this._regDefaults = { bus: 'music' };
    try { this._music = create(this) || null; } catch (e) { this._warn('music', e); this._music = null; }
    this._regDefaults = null;
    if (this._music && this._musicState) this.music(this._musicState);
  }

  music(stateId) {
    this._musicState = stateId;
    this._amb.suspended = stateId === 'silence';
    if (this._music && this._music.setState) {
      try { this._music.setState(stateId); } catch (e) { this._warn('music.setState', e); }
    }
  }

  stopAll() {
    for (const v of this.voices) v.stop(0.08);
    for (const h of this._pending) h.stop();
    this._pending = [];
    this._amb.handle = null;
    this._amb.hum = null;
    this._amb.id = null;
    this._amb.suspended = true;
    this._heart = null;
    this._lowHp = false;
    if (this._music && this._music.stop) {
      try { this._music.stop(); } catch (e) { this._warn('music.stop', e); }
    }
  }

  duck(dbv = 0, lowpassHz = 20000, seconds = 0) {
    if (!this._n) return;
    const now = this.ctx.currentTime, g = this._n.world.gain, f = this._n.duckLp.frequency;
    g.cancelScheduledValues(now);
    g.setTargetAtTime(Math.pow(10, (dbv || 0) / 20), now, 0.03);
    f.cancelScheduledValues(now);
    f.setTargetAtTime(clamp(lowpassHz || 20000, 60, 20000), now, 0.03);
    if (seconds > 0 && Number.isFinite(seconds)) {
      g.setTargetAtTime(1, now + seconds, 0.12);
      f.setTargetAtTime(20000, now + seconds, 0.12);
    }
  }

  setMasterVolume(v) { this.setBusVolume('master', v); }

  setBusVolume(name, v) {
    if (!(name in this.volumes)) return;
    this.volumes[name] = clamp(+v || 0, 0, 1.5);
    if (this.bus && this.bus[name]) this.bus[name].gain.setTargetAtTime(this.volumes[name], this.ctx.currentTime, 0.03);
  }

  getBusVolume(name) { return this.volumes[name]; }

  // ---------------------------------------------------------------- per-frame state
  _updateListener() {
    const cam = this.game.camera, l = this.ctx.listener;
    if (!cam || !cam.matrixWorld) return;
    const e = cam.matrixWorld.elements, pl = this.game.player;
    let x = e[12], y = e[13], z = e[14];
    if (pl && pl.pos) { x += (pl.pos.x - x) * 0.6; y += (pl.pos.y + 1.5 - y) * 0.6; z += (pl.pos.z - z) * 0.6; }
    const lp = this._lpos || (this._lpos = [0, 0, 0]);
    lp[0] = x; lp[1] = y; lp[2] = z;
    if (l.positionX) {
      l.positionX.value = x; l.positionY.value = y; l.positionZ.value = z;
      l.forwardX.value = -e[8]; l.forwardY.value = -e[9]; l.forwardZ.value = -e[10];
      l.upX.value = e[4]; l.upY.value = e[5]; l.upZ.value = e[6];
    } else {
      l.setPosition(x, y, z);
      l.setOrientation(-e[8], -e[9], -e[10], e[4], e[5], e[6]);
    }
  }

  _currentArea() {
    const g = this.game, pl = g.player;
    if (pl && pl.area) return pl.area;
    if (pl && pl.pos && g.level && g.level.areaAt) return g.level.areaAt(pl.pos.x, pl.pos.z);
    return null;
  }

  _updateArea() {
    const area = this._currentArea() || this._area;
    if (area && area !== this._rv.area) this._setReverb(area);
    const rv = this._rv, now = this.ctx.currentTime;
    if (rv.fadeOut >= 0 && now - rv.switchedAt > 0.9) {
      try { this._n.rvIn.disconnect(this._n.conv[rv.fadeOut]); } catch { /* already disconnected */ }
      rv.fadeOut = -1;
    }
    this._area = area;
    this._updateAmbience(area);
  }

  _updateAmbience(area) {
    const amb = this._amb, st = this.game.state;
    const allowed = !amb.suspended && (!st || st === 'playing' || st === 'down');
    const power = !!(this.game.machines && this.game.machines.powerOn);
    const want = allowed && area && this.cues['amb_' + area] ? 'amb_' + area : null;
    const level = power ? 1 : 0.55;
    if (want !== amb.id) {
      if (amb.handle) amb.handle.stop(1.5);
      amb.handle = want ? this.loop(want, { vol: 0 }) : null;
      if (amb.handle) amb.handle.setVol(level, 1.5);
      amb.id = want;
      amb.level = level;
    } else if (amb.handle && amb.level !== level) {
      amb.handle.setVol(level, 2);
      amb.level = level;
    }
    const wantHum = allowed && !power;
    if (wantHum && !amb.hum) amb.hum = this.loop('amb_hum');
    else if (!wantHum && amb.hum) { amb.hum.stop(2); amb.hum = null; }
  }

  _updateHealth() {
    const pl = this.game.player;
    if (!pl) return;
    const max = pl.maxHealth || (pl.mods && pl.mods.maxHealth) || 150, hp = pl.health ?? max;
    const low = pl.alive !== false && hp > 0 && hp / max < LOW_HP;
    if (low === this._lowHp) return;
    this._lowHp = low;
    this._n.muffLp.frequency.setTargetAtTime(low ? 1200 : 20000, this.ctx.currentTime, 0.25);
    if (low) this._heart = this.loop('heartbeat');
    else if (this._heart) { this._heart.stop(0.5); this._heart = null; }
  }

  _updatePrompt() {
    const it = this.game.interact, cur = it ? it.current || null : null;
    if (cur && cur !== this._prompt) this.play('ui_prompt');
    this._prompt = cur;
  }

  _stopWorld() {
    for (const v of this.voices) if (v.chain.bus !== this.bus.music && v.chain.bus !== this.bus.ui) v.stop(0.6);
    if (this._heart) { this._heart.stop(0.3); this._heart = null; }
    this._lowHp = false;
    this._amb.handle = null;
    this._amb.hum = null;
    this._amb.id = null;
    if (this._n) this._n.muffLp.frequency.setTargetAtTime(20000, this.ctx.currentTime, 0.2);
  }

  // ---------------------------------------------------------------- event hookups
  _hookEvents() {
    const ev = this.game.events;
    if (!ev || !ev.on) return;
    const on = (name, fn) => ev.on(name, (p) => { if (this.ctx) { try { fn(p || {}); } catch (e) { this._warn('event:' + name, e); } } });
    on('zombie:hit', (p) => this.play(p.head ? 'ui_hit_head' : 'ui_hit'));
    on('zombie:kill', () => this.play('ui_kill'));
    on('player:step', (p) => this._step(p));
    on('player:jump', () => this.play('jump'));
    on('player:land', (p) => this.play('land', { vol: clamp((p.speed ?? 6) / 10, 0.35, 1) }));
    on('player:hurt', () => this._hurt());
    on('points:change', (p) => this._points(p));
    on('points:denied', () => this.play('ui_denied'));
    on('weapon:fire', (p) => { const id = FIRE_CUES[p.weaponId]; if (id) this.play(id, { upgraded: !!p.upgraded }); });
    on('weapon:empty', () => this.play('dry_fire'));
    on('weapon:switch', () => this.play('weapon_swap'));
    on('weapon:melee', (p) => this._melee(p));
    on('weapon:acquire', (p) => { if (p.source === 'wallbuy') this.play('wallbuy_boing'); });
    on('powerup:spawn', (p) => this.play('pu_spawn', { pos: p.pos }));
    on('powerup:grab', (p) => this._powerup(p.type));
    on('powerup:end', (p) => { if (p.type === 'please_stand_by') this.play('sting_back'); });
    on('machine:commercial_start', () => this.duck(-18, 800, 3.2));
    on('game:start', () => { this._amb.suspended = false; });
    on('game:over', () => this._stopWorld());
    on('state', (p) => { if (p.to === 'menu' || p.to === 'gameover' || p.to === 'victory') this._stopWorld(); });
  }

  _step(p) {
    const pl = this.game.player;
    if (!pl || !pl.pos) return;
    if (p.sprint && this.game.perks && this.game.perks.has && this.game.perks.has('roller_boogie')) {
      this.play('skate_push', { vol: 0.7 });
      return;
    }
    const level = this.game.level;
    const surface = p.surface || (level && level.surfaceAt ? level.surfaceAt(pl.pos.x, pl.pos.z, pl.pos.y) : 'tile');
    const id = this.cues['step_' + surface] ? 'step_' + surface : 'step_tile';
    this.play(id, { vol: p.sprint ? 1 : 0.75, rate: 0.93 + Math.random() * 0.14, foot: p.foot });
  }

  _hurt() {
    const g = this.game, hero = g.player && g.player.heroId;
    this.play('hurt_grunt', { base: HERO_VOICE[hero] || 200 });
    this.play('hurt_static');
    if (g.perks && g.perks.has && g.perks.has('wobble_up')) this.play('jelly_bwoing');
  }

  _melee(p) {
    this.play('melee_whoosh');
    const hero = this.game.player && this.game.player.heroId;
    if (p.hit) this.play('melee_hit_' + (HERO_VOICE[hero] ? hero : 'skip'), { delay: 0.04 });
  }

  _points(p) {
    const d = p.delta || 0;
    if (d < 0) { this.play('ui_buy'); return; }
    if (d <= 0) return;
    const pu = this.game.powerups;
    if (pu && pu.active && pu.active.sweeps_week > 0) this.play('pu_sweeps_week', { vol: 0.3, flip: true });
    else this.play('ui_points_flip');
  }

  _powerup(type) {
    if (!PU_CUES[type]) return;
    this.play(PU_CUES[type]);
    this.play('announcer_wahwah', { rhythm: PU_RHYTHM[type], delay: 0.55 });
    if (type === 'cancelled') this.play('pu_sad_trombone', { delay: 1.7 });
    if (type === 'please_stand_by') this.play('pu_bossa_bed', { delay: 0.3 });
  }

  _warn(key, e) {
    if (this._warned.has(key)) return;
    this._warned.add(key);
    console.warn('[audio] ' + key + ':', e);
  }
}
