// Game: owns every system, the frame loop, the state machine, URL params and time (ARCHITECTURE §0/§3, GDD §18.12).
//
// Construction order = the §3 field list; init() runs once in INIT_ORDER, reset() on every newGame(), update(dt)
// in UPDATE_ORDER while the state is 'playing' or 'down'. Each call is isolated: an exception logs
// console.error('[system:<name>]', err) at most once per 5 s per system and the game keeps running.
//
// time = { now, dt, realNow, realDt, frame, scale }: realDt is the clamped (<= 1/20 s) frame time; world systems
//   get dt = realDt * scale (0 while paused, during hitStop() or when scale = 0 for commercials / Instant Replay).
//   The player's animation, the camera, audio and UI use realDt. REAL_DT lists the systems updated with realDt.
// API: boot(), newGame(heroId), setState(s), pause(), resume(), gameOver(), victory(), hitStop(seconds), rand(),
//   precompile(opts) (async; compiles every scene material now, plus the throw-away objects returned by any system's
//   optional warmup() -> Object3D|Object3D[]; with { draw: true } also draws everything once: boot does it,
//   newGame only for never-compiled materials), warmSteps(objs, {scene, camera, target}) (step generator: draws
//   objs once, a few new programs per step, so their first sighting costs nothing),
//   loaded (false while the real boot still loads the station behind the title; see boot()), loadProgress (0..1
//   estimate of that load, the title's loading bar), loadStats (steps, waitMs: time spent only awaiting compiles),
//   events 'game:loaded'. Systems may expose initSteps() (a generator) to split a long init across frames.
//   params, state, time, ready, stats { fps, frameMs, drawCalls, triangles, zombies, pixelRatio } (every 0.5 s),
//   cards (the broadcast-card namespace of gfx/cards.js: get, animated, drawTo, ids, info, invalidateAll).
// Machines constructs the machine sub-systems (screens, signon, telly, sponsors, uplink); Game drives each of
// their lifecycles as its own isolated system right after `machines`.

import * as THREE from 'three';
import { EventBus } from './events.js';
import { mulberry32 } from './rng.js';
import { Render } from './render.js';
import { Materials } from './materials.js';
import { Textures } from './textures.js';
import { Lights } from './lights.js';
import { Input } from './input.js';
import { Audio } from '../audio/audio.js';
import { cards } from '../gfx/cards.js';
import { Interact } from './interact.js';
import { Debug } from './debug.js';
import { FX } from '../fx/fx.js';
import { Level } from '../world/level.js';
import { Nav } from '../world/nav.js';
import { Player } from '../actors/player.js';
import { ThirdPersonCamera } from '../actors/camera.js';
import { HEROES, DEFAULT_HERO, buildHero } from '../actors/heroes.js';
import { ZombieManager } from '../actors/zombies.js';
import { Boss } from '../actors/boss.js';
import { Weapons } from '../game/weapons.js';
import { Rounds } from '../game/rounds.js';
import { Economy } from '../game/economy.js';
import { Machines } from '../game/machines.js';
import { Perks } from '../game/perks.js';
import { PowerUps } from '../game/powerups.js';
import { EasterEgg } from '../game/easteregg.js';
import { Hud } from '../ui/hud.js';
import { Menu } from '../ui/menu.js';
import { loadFonts } from '../ui/fonts.js';
import { LAYERS } from './config.js';
import { buildModel, buildGrenadeModel, buildTeleModel, buildMeleeProp } from '../game/weaponModels.js';

// Held models warmed with the heroes (the player's hand makes hero-fade variants of their materials).
const HELD_WEAPONS = ['revolver_38', 'pump_37', 'mp7', 'm16a1', 'm60', 'zapper', 'boom_mic', 'chroma_key'];

const MAX_DT = 1 / 20;
const LOG_EVERY = 5000;
const STATS_EVERY = 0.5;
const WORLD_STATES = new Set(['playing', 'down']);

const INIT_ORDER = ['render', 'tex', 'mats', 'lights', 'input', 'audio', 'fx', 'level', 'nav', 'player', 'cam',
  'weapons', 'zombies', 'rounds', 'economy', 'machines', 'screens', 'signon', 'telly', 'sponsors', 'uplink', 'perks',
  'powerups', 'egg', 'boss', 'interact', 'hud', 'menu', 'debug'];
const UPDATE_ORDER = ['input', 'player', 'nav', 'weapons', 'zombies', 'rounds', 'level', 'machines', 'screens',
  'signon', 'telly', 'sponsors', 'uplink', 'perks', 'powerups', 'egg', 'boss', 'interact', 'fx', 'cam', 'audio', 'hud'];
const LATE_ORDER = ['player', 'weapons', 'zombies', 'level', 'screens', 'fx', 'hud'];
const REAL_DT = new Set(['input', 'cam', 'audio', 'hud']);
// Updated in every state (real dt): UI and debug cameras keep working in menus, pause and game over.
const ALWAYS = ['menu', 'debug'];

function parseParams(search) {
  const out = {};
  for (const [k, v] of new URLSearchParams(search)) {
    if (v === '') out[k] = 1;
    else if (/^-?\d+(\.\d+)?$/.test(v)) out[k] = Number(v);
    else out[k] = v;
  }
  return out;
}

export class Game {
  constructor() {
    this.params = parseParams(location.search);
    this.seed = Number.isFinite(this.params.seed) ? this.params.seed : (Math.random() * 2 ** 31) | 0;
    this._rng = mulberry32(this.seed);
    this.rand = () => this._rng();
    this.events = new EventBus();
    this.state = 'boot';
    this.time = { now: 0, dt: 0, realNow: 0, realDt: 0, frame: 0, scale: 1 };
    this.ready = false;
    this.loaded = false;             // every system initialized and the scene precompiled (see boot())
    this._loading = false;
    this._inited = new Set();
    this.loadStats = { steps: [], titleMs: 0, loadedMs: 0 };
    this.loadProgress = 0;           // 0..1 estimate of the real boot's load behind the title (menu's loading bar)
    this.stats = { fps: 0, frameMs: 0, drawCalls: 0, triangles: 0, zombies: 0, pixelRatio: 1 };
    this.heroId = null;
    this._errT = new Map();
    this._hitStop = 0;
    this._last = -1;
    this._statT = 0;
    this._statFrames = 0;
    this._statMs = 0;
    this._pausedFrom = 'playing';
    window.__game = this;

    this.render = new Render(this);
    this.renderer = this.render.renderer;
    this.scene = this.render.scene;
    this.camera = this.render.camera;
    this.tex = new Textures(this);
    this.mats = new Materials(this);
    this.lights = new Lights(this);
    this.input = new Input(this);
    this.audio = new Audio(this);
    this.cards = cards;
    this.fx = new FX(this);
    this.level = new Level(this);
    this.nav = new Nav(this);
    this.interact = new Interact(this);
    this.player = new Player(this);
    this.cam = new ThirdPersonCamera(this);
    this.weapons = new Weapons(this);
    this.zombies = new ZombieManager(this);
    this.rounds = new Rounds(this);
    this.economy = new Economy(this);
    this.machines = new Machines(this); // also sets game.screens / signon / telly / sponsors / uplink
    this.perks = new Perks(this);
    this.powerups = new PowerUps(this);
    this.egg = new EasterEgg(this);
    this.boss = new Boss(this);
    this.hud = new Hud(this);
    this.menu = new Menu(this);
    this.debug = new Debug(this);

    this._frame = (ms) => this._tick(ms);
  }

  // Real boot (no test/shot param): the title shows as soon as the living room is built and compiled (a few
  // seconds), and the station loads BEHIND it, one step per frame (_load): the remaining systems' init() (a system
  // may expose initSteps(), a generator, to split a long init: level does), the zombie pools, the menu's channel
  // sets, then precompile({ draw: true }). Meanwhile `loaded` is false, the TV shows snow and the menu ignores
  // input ('PLEASE STAND BY'); systems not initialized yet are not updated. test/shot boots load everything first
  // and start the loop straight into play, as before.
  async boot() {
    try {
      await loadFonts();
    } catch (err) {
      console.warn('[game] fonts unavailable, using fallbacks', err);
    }
    if (this.params.test || this.params.shot) {
      const pre = document.getElementById('da-boot'); // index.html's pre-script card (the real boot's menu removes it)
      if (pre) pre.remove();
      for (const name of INIT_ORDER) this._init(name);
      this.setState('menu');
      this.newGame(this.params.char);
      await this.precompile({ draw: true, heroes: true });
      this.loaded = true;
      this._booted = true;
      this.renderer.setAnimationLoop(this._frame);
      return;
    }
    this._loading = true;
    const LS = this.loadStats;
    LS.fontsMs = Math.round(performance.now());
    this._call('menu', 'showLoading'); // PLEASE STAND BY over the dark page until the living room shows
    for (const name of INIT_ORDER.slice(0, INIT_ORDER.indexOf('level'))) this._init(name);
    LS.systemsMs = Math.round(performance.now());
    this.setState('menu');
    this._call('menu', 'showTitle');
    LS.roomMs = Math.round(performance.now());
    // The living room's programs compile in parallel (KHR_parallel_shader_compile) before its first frame, so
    // that frame has no synchronous compile stall; the station's CPU-side build starts meanwhile, and the loop
    // (the title) starts as soon as the room is ready.
    const room = this.menu && this.menu._room;
    const roomReady = (room ? this._compileAsync(room.scene, room.camera, room.scene) : Promise.resolve()).then(() => {
      LS.roomCompiledMs = Math.round(performance.now());
      this._booted = true;
      this.renderer.setAnimationLoop(this._frame);
      LS.titleMs = Math.round(performance.now());
    });
    try {
      await this._load();
    } catch (err) {
      console.error('[game] load failed', err);
      for (const name of INIT_ORDER) if (!this._inited.has(name)) this._init(name);
    }
    await roomReady;
    this._loading = false;
    this._prog(1);
    this.loaded = true;
    this.loadStats.loadedMs = Math.round(performance.now());
    this.events.emit('game:loaded', {});
  }

  _init(name) {
    this._call(name, 'init');
    this._inited.add(name);
  }

  // Resolves after the next frame has been drawn (the game loop runs in requestAnimationFrame), so the title keeps
  // animating between load steps. A hidden tab (rAF paused) falls back to a plain task.
  // loadStats = { steps: [[label, ms], ...] (the time of every load step), fontsMs, systemsMs, roomMs,
  //   roomCompiledMs, titleMs (loop started), loadedMs } (page times).
  _yield() {
    const L = this.loadStats;
    if (this._stepT != null) L.steps.push([this._stepLabel, Math.round(performance.now() - this._stepT)]);
    return new Promise((resolve) => {
      const go = () => { this._stepT = performance.now(); resolve(); };
      if (document.hidden) { setTimeout(go, 0); return; }
      requestAnimationFrame(() => setTimeout(go, 0));
    });
  }

  _step(label) { this._stepLabel = label; }

  // loadProgress: monotonic, from each phase's share of a typical load (level build ~30 %, other systems, the menu
  // sets, the warm-up ~45 %); a phase with n of `expected` steps done sits at from + (to - from) * n / expected.
  _prog(p) { if (p > this.loadProgress) this.loadProgress = Math.min(1, p); }

  // Awaits `p` (a GPU compile): the time the load spends only waiting (the page keeps drawing) goes to
  // loadStats.waitMs, so the steps' ms minus waitMs is main-thread work.
  async _wait(p) {
    const t = performance.now();
    await p;
    const ms = Math.round(performance.now() - t), L = this.loadStats;
    L.waitMs = (L.waitMs || 0) + ms;
    (L.waits || (L.waits = [])).push([this._stepLabel, ms]);
  }

  // Runs a step generator: every `yield` gives a frame back; a yielded Promise is awaited first.
  async _runSteps(it, from = null, to = null, expected = 1) {
    let n = 0;
    for (let r = it.next(); !r.done; r = it.next()) {
      if (r.value && typeof r.value.then === 'function') await this._wait(r.value);
      if (from != null) this._prog(from + (to - from) * Math.min(1, ++n / expected));
      await this._yield();
    }
    if (to != null) this._prog(to);
  }

  async _load() {
    const rest = INIT_ORDER.filter((n) => !this._inited.has(n));
    this._prog(0.02);
    for (const name of rest) {
      await this._yield();
      this._step(name);
      const sys = this[name];
      if (name !== 'level') this._prog(0.25 + 0.08 * (rest.indexOf(name) / rest.length));
      if (sys && typeof sys.initSteps === 'function') {
        try {
          await this._runSteps(sys.initSteps(), name === 'level' ? 0.02 : null, name === 'level' ? 0.25 : null, 14);
        } catch (err) {
          this._report(name, err);
        }
        this._inited.add(name);
      } else {
        this._init(name);
      }
      if (name === 'level' && this.level && this.level.root) {
        // start compiling the station's programs now (KHR_parallel_shader_compile): the GPU driver works on them
        // while the other systems, the pools and the menu sets are built on the CPU; precompile() below finds
        // them compiled or compiling
        for (const c of this.level.root.children) {
          this._step('compile:' + (c.name || 'level'));
          this._compileAsync(c, this.camera, this.scene);
          await this._yield();
        }
      }
    }
    // zombies.reset() fills the model/head pools that newGame's reset would otherwise build (~0.6 s at tune-in);
    // it is idempotent and nothing is alive yet.
    await this._yield();
    this._step('zombies.pool');
    this._call('zombies', 'reset');
    this._prog(0.35);
    // The character-select channel sets (heroes, promo cards, props), built and drawn once now instead of on
    // the title -> select key press.
    const m = this.menu;
    if (m && typeof m.preloadSteps === 'function') {
      this._step('menu.sets');
      try {
        await this._runSteps(m.preloadSteps(), 0.35, 0.45, 20);
      } catch (err) {
        console.warn('[game] menu preload failed', err);
      }
    }
    await this._yield();
    this._step('precompile');
    await this.precompile({ draw: true, heroes: true, step: () => this._yield(), label: (l) => this._step(l), progress: (p) => this._prog(0.45 + 0.54 * p) });
    if (this._stepT != null) this.loadStats.steps.push([this._stepLabel, Math.round(performance.now() - this._stepT)]);
    this._stepT = null;
  }

  // compileAsync against the composer's HDR scene target (program variants depend on the bound target: tone
  // mapping / output colour space), exactly like RenderPass renders them. The synchronous part runs now; with
  // KHR_parallel_shader_compile the driver finishes in the background while frames keep running. Never throws.
  _compileAsync(obj, camera, targetScene) {
    const r = this.renderer;
    const prev = r.getRenderTarget();
    let pending = null;
    try {
      r.setRenderTarget(this.render.composer.readBuffer);
      if (r.compileAsync) pending = r.compileAsync(obj, camera, targetScene);
      else r.compile(obj, camera, targetScene);
    } catch (err) {
      console.warn('[game] compile failed', err);
    } finally {
      r.setRenderTarget(prev);
    }
    return pending ? pending.catch(() => {}) : Promise.resolve();
  }

  // Compiles the shader program of every material in the scene (all areas, culled or not, visible or not) so
  // walking into an area for the first time does not stall (measured on Iris Xe / ANGLE D3D11). Called at boot and
  // by newGame (new hero); systems that add many new materials later may call it too. Never throws.
  // Warm-up hook: any system may implement warmup() -> Object3D | Object3D[] | null returning throw-away samples
  // of what it will spawn later (zombies of every type, pickups...); they are compiled here and discarded.
  // opts.draw: after compiling, each chunk (the warm-up samples, every child of the level root, everything else)
  //   is also DRAWN once, isolated and with culling off, into a small offscreen target. Compiling alone leaves
  //   the real cost of a first sighting in place (~150-800 ms per room / first zombie on Iris Xe): ANGLE builds
  //   the D3D shader variant for the mesh's vertex layout at its first draw, and the textures, vertex buffers
  //   and three's per-program uniform setup are uploaded at first use. Pixels written there are never shown.
  // opts.heroes: one throw-away sample of every hero joins the warm-up samples (newGame builds the chosen one).
  // opts.step: async () => void called between chunks (the progressive boot passes a frame yield).
  async precompile(opts = {}) {
    const { draw = false, heroes = false, step = null, label = null, fresh = false } = opts;
    const progress = opts.progress || (() => {});
    if (fresh) return this._precompileFresh(draw);
    const warm = new THREE.Group();
    warm.name = 'precompile:warmup';
    try {
      for (const name of INIT_ORDER) {
        const sys = this[name];
        if (!sys || typeof sys.warmup !== 'function') continue;
        try {
          const got = sys.warmup();
          for (const o of [].concat(got || [])) if (o && o.isObject3D) warm.add(o);
        } catch (err) {
          console.warn(`[game] ${name}.warmup failed`, err);
        }
        if (label) label(`warmup:${name}`);
        progress(0.06 * (INIT_ORDER.indexOf(name) + 1) / INIT_ORDER.length);
        if (step) await step();
      }
      if (heroes) {
        for (const h of HEROES) {
          try {
            const s = buildHero(h.id, this);
            this.mats.applyHeroFade(s.group);
            warm.add(s.group);
          } catch (err) {
            console.warn(`[game] hero warmup ${h.id} failed`, err);
          }
          if (step) await step();
        }
        // what the hand holds (player.setWeaponModel -> mats.applyHeroFade): every gun, plain and upgraded, the
        // grenade, Tiny Tele and the melee props, so the first equip / purchase / upgrade does not compile
        const held = new THREE.Group();
        held.name = 'precompile:held';
        const hold = (fn) => {
          try {
            const m = fn();
            if (m && m.isObject3D) { this.mats.applyHeroFade(m); held.add(m); }
          } catch (err) {
            console.warn('[game] held warmup failed', err);
          }
        };
        for (const id of HELD_WEAPONS) {
          for (const up of [false, true]) hold(() => buildModel(id, up, null, this));
          if (step) await step();
        }
        hold(() => buildGrenadeModel(this));
        hold(() => buildTeleModel(this));
        for (const h of HEROES) hold(() => buildMeleeProp(h.id, this));
        warm.add(held);
      }
      // The screens' camera feeds draw zombies with "human skin" variants of their materials (screens._variant,
      // made per zombie at spawn): warm those programs too, on clones of the samples' meshes.
      const sc = this.screens;
      if (sc && typeof sc._variant === 'function') {
        const feed = new THREE.Group();
        feed.name = 'precompile:feed';
        const meshes = [];
        warm.traverse((o) => { if (o.isMesh && (o.layers.mask & (1 << LAYERS.ZOMBIES))) meshes.push(o); });
        for (const o of meshes) {
          let v = null;
          try { v = sc._variant(o.material); } catch { v = null; }
          if (!v) continue;
          const c = o.clone(false);
          c.material = v;
          feed.add(c);
        }
        if (feed.children.length) warm.add(feed);
      }
      warm.position.set(0, -500, 0);
      this.scene.add(warm);
      this.scene.updateMatrixWorld(true);
      if (!draw) {
        const pending = this._compileAsync(this.scene, this.camera, this.scene);
        this.scene.remove(warm);
        await pending;
        return;
      }
      const lvl = this.level && this.level.root;
      const samples = warm.children.slice();
      const chunks = [];
      if (lvl && lvl.parent === this.scene) for (const c of lvl.children) chunks.push([c]);
      chunks.push(samples);
      chunks.push(this.scene.children.filter((o) => o !== lvl && o !== warm && !o.isLight));
      // start every compile of a chunk (a frame between their synchronous parts), wait for all of them, then draw.
      // The samples' compiles (new programs) start first and the driver works on them while the level's chunks
      // (compiled since the level was built) are drawn.
      // kick(objs) resolves once every compile is started, to a function returning the promise of their end
      const kick = async (objs, at = null) => {
        const pend = [];
        for (let i = 0; i < objs.length; i++) {
          pend.push(this._compileAsync(objs[i], this.camera, this.scene));
          if (at) at((i + 1) / objs.length);
          if (step && objs.length > 1) await step();
        }
        return () => Promise.all(pend);
      };
      if (label) label('warm:samples:compile');
      progress(0.08);
      const samplesDone = await kick(samples, (f) => progress(0.08 + 0.47 * f));
      progress(0.55);
      // each chunk's share of the rest of the bar ~ its mesh count; inside a chunk the bar eases towards its end
      const wts = chunks.map((objs) => { let n = 1; for (const o of objs) o.traverse((d) => { if (d.isMesh) n++; }); return n; });
      const wsum = wts.reduce((a, b) => a + b, 0);
      let wdone = 0;
      for (let ci = 0; ci < chunks.length; ci++) {
        const objs = chunks[ci];
        const base = wdone;
        const at = (f) => progress(0.55 + 0.45 * (base + wts[ci] * f) / wsum);
        at(0);
        wdone += wts[ci];
        if (!objs.length) continue;
        if (label) label(`warm:${objs === samples ? 'samples' : objs.length === 1 ? objs[0].name || objs[0].type : 'scene'}`);
        const done = objs === samples ? samplesDone : await kick(objs);
        await this._wait(done());
        const it = this.warmSteps(objs);
        let n = 0;
        for (let r = it.next(); !r.done; r = it.next()) { at(1 - Math.exp(-++n / 12)); if (step) await step(); }
      }
      this._warmScreens();
      progress(1);
      this.scene.remove(warm);
    } catch (err) {
      this.scene.remove(warm);
      console.warn('[game] precompile failed', err);
    }
  }

  // warmSteps(objs, { scene = game.scene, camera = game.camera, target = 32x32 scene-type target, per = 4 }):
  // a step generator that DRAWS objs once, isolated, so their first real sighting costs nothing: first the objects
  // grouped by program, at most `per` programs never warm-drawn before per step (a program's first draw is where
  // ANGLE builds its D3D shader variant and three fetches its uniforms: ~20-400 ms each on Iris Xe, so a whole
  // room at once froze the page for seconds), then everything together (vertex buffers, textures). Compile first
  // (compileAsync) so each first draw only waits for the tail of an already started compile. Every yield is a
  // point where the caller may give a frame back. Pixels written to the target are never shown.
  *warmSteps(objs, opts = {}) {
    const { scene = this.scene, camera = this.camera, target = null, per = 4 } = opts;
    const props = this.renderer.properties;
    const seen = this._warmProgs || (this._warmProgs = new WeakSet());
    const byProg = new Map();
    for (const o of objs) {
      o.traverse((d) => {
        if (!(d.isMesh || d.isPoints || d.isLine || d.isSprite) || !d.material) return;
        for (const m of [].concat(d.material)) {
          const p = m && props.has(m) ? props.get(m).currentProgram : null;
          if (!p || seen.has(p)) continue;
          let list = byProg.get(p);
          if (!list) byProg.set(p, (list = []));
          list.push(d);
        }
      });
    }
    const progs = [...byProg.keys()];
    for (let i = 0; i < progs.length; i += per) {
      const batch = new Set();
      for (const p of progs.slice(i, i + per)) { seen.add(p); for (const d of byProg.get(p)) batch.add(d); }
      this._warmDraw([...batch], scene, camera, target);
      yield;
    }
    this._warmDraw(objs, scene, camera, target);
  }

  // Draws `objs` (and nothing else but the scene's lights) once into `target` (default: a 32x32 target of the scene
  // target's type, i.e. the same program variants as RenderPass). Every other branch is hidden, the objects' whole
  // subtrees are forced visible, unculled and shadow-casting (level.shadowCull turns casting off per area; the
  // depth programs warm too), then every flag is restored. Branches holding lights keep their state, so the light
  // setup (and with it the program variant) is the one of a normal frame.
  _warmDraw(objs, scene = this.scene, camera = this.camera, target = null) {
    const r = this.renderer;
    if (!target) {
      if (!this._warmRT) {
        const src = this.render.composer.readBuffer;
        this._warmRT = new THREE.WebGLRenderTarget(32, 32, { type: src.texture.type, samples: src.samples });
        this._warmRT.texture.name = 'precompile:warm';
      }
      target = this._warmRT;
    }
    const lit = new Set();
    scene.traverse((o) => { if (o.isLight) for (let p = o; p; p = p.parent) lit.add(p); });
    const keep = new Set(objs), path = new Set();
    for (const o of objs) for (let p = o.parent; p && p !== scene; p = p.parent) path.add(p);
    const vis = [], cull = [], cast = [];
    const set = (o, v) => { if (o.visible !== v) { vis.push(o); o.visible = v; } };
    const walk = (o) => {
      for (const c of o.children) {
        if (keep.has(c)) {
          c.traverse((d) => {
            set(d, true);
            if (d.frustumCulled) { cull.push(d); d.frustumCulled = false; }
            if (d.isMesh && !d.castShadow) { cast.push(d); d.castShadow = true; }
          });
        } else if (path.has(c)) {
          set(c, true);
          walk(c);
        } else if (!lit.has(c)) {
          set(c, false);
        }
      }
    };
    walk(scene);
    const prev = r.getRenderTarget();
    try {
      r.setRenderTarget(target);
      r.render(scene, camera);
    } catch (err) {
      console.warn('[game] warm draw failed', err);
    } finally {
      r.setRenderTarget(prev);
      // the shadow map now holds only these objects: if something switched to manual shadow updates, redo it
      if (!r.shadowMap.autoUpdate) r.shadowMap.needsUpdate = true;
      for (let i = vis.length - 1; i >= 0; i--) vis[i].visible = !vis[i].visible;
      for (const o of cull) o.frustumCulled = true;
      for (const o of cast) o.castShadow = false;
    }
  }

  // The screens' feed post quads (grade / flinch ShaderMaterials in screens' own quad scene) drawn once into a small
  // target of the feed pictures' type (half float, no depth), so the first feed frame at tune-in compiles nothing.
  _warmScreens() {
    const sc = this.screens;
    if (!sc || !sc._quad || !sc._quadScene || !sc._quadCam) return;
    const r = this.renderer, prev = r.getRenderTarget(), keep = sc._quad.material;
    try {
      if (!this._warmFeedRT) {
        this._warmFeedRT = new THREE.WebGLRenderTarget(32, 32, { type: THREE.HalfFloatType, depthBuffer: false });
        this._warmFeedRT.texture.generateMipmaps = false;
        this._warmFeedRT.texture.name = 'precompile:feed';
      }
      for (const m of [sc._gradeMat, sc._flinchMat]) {
        if (!m) continue;
        sc._quad.material = m;
        r.setRenderTarget(this._warmFeedRT);
        r.render(sc._quadScene, sc._quadCam);
      }
    } catch (err) {
      console.warn('[game] screens warm failed', err);
    } finally {
      sc._quad.material = keep;
      r.setRenderTarget(prev);
    }
  }

  // precompile({ fresh: true }): only the scene meshes whose materials were never compiled (newGame after the
  // boot's full warm-up: typically nothing, or the few objects a reset() rebuilt), compiled and drawn once.
  async _precompileFresh(draw) {
    const props = this.renderer.properties, objs = [];
    try {
      this.scene.traverse((o) => {
        const m = o.material;
        if (!m || !(o.isMesh || o.isPoints || o.isLine || o.isSprite)) return;
        for (const x of [].concat(m)) if (x && !(props.has(x) && props.get(x).programs)) { objs.push(o); return; }
      });
      if (!objs.length) return;
      for (const o of objs) await this._compileAsync(o, this.camera, this.scene);
      if (draw) for (const _ of this.warmSteps(objs)) { /* all now: a new run's first frame follows */ }
    } catch (err) {
      console.warn('[game] precompile failed', err);
    }
  }

  // Resets every system and starts a run (Rounds schedules round 1, or params.round, T.rounds.firstRoundDelay later).
  newGame(heroId) {
    const id = HEROES.some((h) => h.id === heroId) ? heroId : DEFAULT_HERO;
    this.heroId = id;
    this._rng = mulberry32(this.seed);
    Object.assign(this.time, { now: 0, dt: 0, scale: 1 });
    this._hitStop = 0;
    this._safe('player', () => this.player.setHero(id));
    for (const name of INIT_ORDER) this._call(name, 'reset');
    const p = this.params;
    if (p.power) this._safe('machines', () => this.machines.setPower(true));
    if (p.doors) this._safe('level', () => this.level.openAllDoors());
    if (p.nozombies) this._safe('rounds', () => this.rounds.pauseSpawning(true));
    this.setState('playing');
    this.events.emit('game:start', { heroId: id });
    this.input.requestLock();
    if (this._booted) this.precompile({ fresh: true, draw: true });
  }

  setState(s) {
    if (s === this.state) return;
    const from = this.state;
    this.state = s;
    this.events.emit('state', { from, to: s });
  }

  pause() {
    if (!WORLD_STATES.has(this.state)) return;
    this._pausedFrom = this.state;
    this.setState('paused');
    this.input.exitLock();
    this._call('menu', 'showPause');
  }

  resume() {
    if (this.state !== 'paused') return;
    this._call('menu', 'hidePause');
    this.setState(this._pausedFrom);
    this.input.requestLock();
  }

  // Lethal damage without Instant Replay (GDD §6.5). The menu plays the tape-stop / CRT collapse / stand-by card.
  gameOver() {
    if (this.state === 'gameover' || this.state === 'victory') return;
    const summary = { round: this.rounds.round, kills: this.rounds.totalKills, points: this.economy.points };
    this.setState('gameover');
    this.input.exitLock();
    this.events.emit('game:over', summary);
    this._call('menu', 'showGameOver', summary);
  }

  victory() {
    if (this.state === 'gameover' || this.state === 'victory') return;
    const summary = { round: this.rounds.round };
    this.setState('victory');
    this.input.exitLock();
    this.events.emit('game:victory', summary);
    this._call('menu', 'showVictory', summary);
  }

  // Freezes world systems for `seconds` of real time (headshot pops, big hits). Overlapping calls keep the longest.
  hitStop(seconds) {
    this._hitStop = Math.max(this._hitStop, seconds);
  }

  _tick(ms) {
    const t0 = performance.now();
    const realDt = this._last < 0 ? 1 / 60 : Math.min(MAX_DT, Math.max(0, (ms - this._last) / 1000));
    this._last = ms;
    const time = this.time;
    time.realDt = realDt;
    time.realNow += realDt;
    time.frame++;
    const world = WORLD_STATES.has(this.state);
    let scale = time.scale;
    if (this._hitStop > 0) {
      this._hitStop = Math.max(0, this._hitStop - realDt);
      scale = 0;
    }
    const dt = world ? realDt * scale : 0;
    time.dt = dt;
    time.now += dt;

    if (world) {
      for (const name of UPDATE_ORDER) this._call(name, 'update', REAL_DT.has(name) ? realDt : dt);
      for (const name of LATE_ORDER) this._call(name, 'lateUpdate', dt);
    } else {
      this._call('input', 'update', realDt);
      if (this._inited.has('hud')) this._call('hud', 'update', realDt);
    }
    // while the station loads behind the title only the systems initialized so far are updated (the menu always)
    for (const name of ALWAYS) if (name === 'menu' || this._inited.has(name)) this._call(name, 'update', realDt);
    this._call('lights', 'update', realDt);
    this._call('mats', 'update', realDt);
    this._call('tex', 'update', realDt);

    this.renderer.info.reset();
    if (this._call('render', 'frame', realDt)) this.ready = true;
    this._updateStats(realDt, performance.now() - t0);
  }

  _updateStats(realDt, ms) {
    this._statT += realDt;
    this._statFrames++;
    this._statMs += ms;
    if (this._statT < STATS_EVERY) return;
    const info = this.renderer.info.render;
    const s = this.stats;
    s.fps = Math.round(this._statFrames / this._statT);
    s.frameMs = Math.round((this._statMs / this._statFrames) * 100) / 100;
    s.drawCalls = info.calls;
    s.triangles = info.triangles;
    s.zombies = this.zombies.alive.length;
    s.pixelRatio = this.render.pixelRatio;
    this._statT = this._statFrames = this._statMs = 0;
  }

  // Calls system[method](arg) if it exists, isolated. Returns true when the call completed.
  _call(name, method, arg) {
    const sys = this[name];
    if (!sys || typeof sys[method] !== 'function') return false;
    try {
      sys[method](arg);
      return true;
    } catch (err) {
      this._report(name, err);
      return false;
    }
  }

  _safe(name, fn) {
    try {
      fn();
    } catch (err) {
      this._report(name, err);
    }
  }

  _report(name, err) {
    const now = performance.now();
    if (now - (this._errT.get(name) ?? -Infinity) < LOG_EVERY) return;
    this._errT.set(name, now);
    console.error(`[system:${name}]`, err);
  }
}
