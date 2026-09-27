// THE SIGN-OFF ENDING + THE MORNING SHOW (GDD §13 step 6 "Defeat and ending", "Rewards"). Owner: boss + ending engineer.
// Constructed and driven by src/actors/boss.js (game.ending); game.js does not know this file.
//
// TIMELINE (seconds from the Baron's defeat; skippable after 5 s once it has been seen: Space / Enter / E / pad A)
//   0     he freezes; his screen shows the teary "goodnight" face and he waves (boss.goodnight); the Sign-Off hymn
//         swells (sting_signoff_hymn + boss_goodnight); a slow cinematic push-in on the gameplay camera.
//   3.0   his TV head collapses into a white line, then a dot (boss.collapseHead); 3.4 the WHOLE view collapses
//         (render.post.collapse 0 -> 1).
//   4–7   black; the dot lingers, grows two tiny eyes and winks.
//   7–17  the cozy 1977 living room at night (menu.getLivingRoom(), the character-select room): a kid asleep on the
//         couch in the WZTV "13" cap with a popcorn bowl; the camera dollies back from the console TV (the sign-off
//         film on its screen): it's Telly. Its rabbit ears twitch, a tiny sleepy hop, the glove waves goodnight,
//         and it switches itself off to a white dot.
//   17–20 3.0 s of total silence (audio.stopAll + music 'silence').
//   20–32 a 70s end-credit crawl over a chrome "13" ident ("Starring <your hero>", the other three, the guests,
//         "and WZTV Channel 13"), funk end theme (music 'credits').
//   31–35 your hero in their commercial pose on their show's backdrop -> at 32.0 a SEPIA FREEZE-FRAME.
//   35    STAY TUNED?  (Y / N)  -> game.victory() (emits game:victory {round}; the menu stays out of the way while
//         ending.active).  Y = the Morning Show, N = menu.showResults(summary, 'GOOD NIGHT') then the title.
// PERSISTENT UNLOCK: localStorage "deadair.signoff" = "1" (set when the ending starts; every access in try/catch).
// MORNING SHOW (Y): back in the Yard at dawn (sky #FF7E5F -> #FFE3A3, warm low sun from the east with long shadows,
//   warmer ambient in every area, warm light pools under every window), every clock reads 12:00 and ticks, music
//   'morning'; all five sponsors free + permanent in gold leaf (perks.morningShow), both held weapons uplinked for
//   free (or refilled if already upgraded), +13,013 points, Telly never signs off again and pulls cost 13 (the
//   machine_telly interactable is wrapped: 13-point prompt, forced non-sign-off outcomes), the run continues from the
//   next round. Emits game:morning {round}.
// API (game.ending)
//   active (from play() until the Y/N choice)  playing (alias)  running  stage  t  seen  morning (bool)
//   play({ round })  update(realDt) (boss.update calls it)  stop()  reset()  morningShow()  results()
//   timeScale (tests: 0 holds the sequence on one frame)  debugPlay({ round })  debugSeek(t)  debugChoose('y'|'n')
//   debugState()
//   padButton(name) -> used (input.js, Xbox pad): A skips (same rule as the keys); on the card A = YES, B = NO. The
//   card's key caps read A / B while the pad is the last input device (input:device).

import * as THREE from 'three';
import { T, PAL } from '../core/config.js';
import { HEROES, buildHero } from '../actors/heroes.js';
import { FONTS } from '../ui/fonts.js';
import { setTellyGlove, updateTellyArm } from '../props/machines.js';

const KEY = 'deadair.signoff';
const E = {
  head: 3.0, view: 3.4, black: 4.0, eyes: 4.8, wink: 5.8, room: 7.0, face: 10.4, ears: 10.9, hop: 11.8, glove: 12.6,
  wave: 12.9, waveEnd: 15.0, gloveIn: 15.15, off: 15.6, roomOut: 16.7, silence: 17.0, credits: 20.0, portrait: 30.6,
  freeze: 32.0, card: 35.0, skipAfter: 5.0,
};
const MORNING_BONUS = 13013;
const TELLY_MORNING_COST = 13;
const SIGNALS = ['hot_mic', 'laugh_track', 'cold_open'];
const TAU = Math.PI * 2;
const clamp = THREE.MathUtils.clamp;
const lerp = THREE.MathUtils.lerp;
const smooth = (x) => { x = clamp(x, 0, 1); return x * x * (3 - 2 * x); };
const easeInOut = (x) => { x = clamp(x, 0, 1); return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2; };
const easeOutBack = (x, s = 1.7) => { x = clamp(x, 0, 1); return 1 + (s + 1) * (x - 1) ** 3 + s * (x - 1) ** 2; };
const _v = new THREE.Vector3(), _v2 = new THREE.Vector3(), _v3 = new THREE.Vector3();

function storeGet(k) { try { return localStorage.getItem(k); } catch { return null; } }
function storeSet(k, v) { try { localStorage.setItem(k, v); } catch { /* private window / blocked storage */ } }

// ------------------------------------------------------------------------------------------------ credits art
// Chrome "13" ident: extruded bronze layers, a thick ink outline, a mirror-chrome gradient face, star glints.
function chromeIdent() {
  const W = 900, H = 640;
  const c = document.createElement('canvas');
  c.width = W; c.height = H;
  const x = c.getContext('2d');
  const font = `470px ${FONTS.logo}`;
  x.font = font;
  x.textAlign = 'center';
  x.textBaseline = 'middle';
  const cx = W / 2, cy = H / 2 + 30;
  for (let i = 22; i > 0; i--) {
    const k = i / 22;
    x.fillStyle = `rgb(${Math.round(58 + 70 * (1 - k))},${Math.round(34 + 40 * (1 - k))},${Math.round(40 + 30 * (1 - k))})`;
    x.fillText('13', cx + i * 1.6, cy + i * 2.1);
  }
  x.lineJoin = 'round';
  x.lineWidth = 30;
  x.strokeStyle = '#150E24';
  x.strokeText('13', cx, cy);
  const g = x.createLinearGradient(0, cy - 220, 0, cy + 220);
  g.addColorStop(0, '#FFFFFF'); g.addColorStop(0.22, '#D6E4FF'); g.addColorStop(0.46, '#7A88B4'); g.addColorStop(0.5, '#262A48');
  g.addColorStop(0.53, '#F6DDAE'); g.addColorStop(0.72, '#FFF7E8'); g.addColorStop(1, '#B08A5A');
  x.fillStyle = g;
  x.fillText('13', cx, cy);
  x.lineWidth = 5;
  x.strokeStyle = 'rgba(255,255,255,0.85)';
  x.strokeText('13', cx - 2, cy - 3);
  return c;
}

function star(x, cx, cy, r, a) {
  x.save();
  x.translate(cx, cy);
  x.globalAlpha = a;
  const g = x.createRadialGradient(0, 0, 0, 0, 0, r);
  g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.3, 'rgba(255,245,220,0.6)'); g.addColorStop(1, 'rgba(255,245,220,0)');
  x.fillStyle = g;
  x.fillRect(-r, -r, 2 * r, 2 * r);
  x.fillStyle = 'rgba(255,255,255,0.95)';
  x.beginPath();
  for (let i = 0; i < 8; i++) {
    const rr = i % 2 ? r * 0.12 : r;
    const ang = (i / 8) * TAU;
    x.lineTo(Math.cos(ang) * rr, Math.sin(ang) * rr);
  }
  x.closePath();
  x.fill();
  x.restore();
}

// ================================================================================================ Ending
export class Ending {
  constructor(game, boss) {
    this.game = game;
    this.boss = boss;
    this.active = false;
    this.stage = null;
    this.t = 0;
    this.seen = false;
    this.morning = false;
    this.timeScale = 1;
    this._flags = {};
    this._dom = null;
    this._raf = 0;
  }

  get playing() { return this.active && this.stage !== 'card'; }
  get running() { return this.active; }

  init() {
    this._onKey = (e) => this._key(e);
    this.game.events?.on?.('input:device', () => this._glyphs());
    // quitting to the title (pause menu) in the middle of the ending: drop the sequence (its overlay would cover the menu)
    this.game.events.on('state', ({ to } = {}) => { if (to === 'menu' && this.active) this.stop(); });
  }

  reset() {
    this.stop();
    this._undoMorning();
  }

  // ------------------------------------------------------------------------------------------ play
  play({ round } = {}) {
    const g = this.game;
    if (this.active) return false;
    this.active = true;
    this.stage = 'yard';
    this.t = 0;
    this._flags = {};
    this.round = Number.isFinite(round) ? round : (g.rounds?.round || 1);
    this.heroId = g.player?.heroId || g.heroId || 'duke';
    this.summary = { round: this.round, kills: g.rounds?.totalKills ?? 0, points: g.economy?.points ?? 0 };
    this.seen = storeGet(KEY) === '1';
    storeSet(KEY, '1');
    const p = g.player;
    if (p) { p.controlLocked = true; p.invulnerable = true; }
    g.hud?.hide?.();
    if (g.cam) g.cam.enabled = false;
    this._camFrom = { pos: g.camera.position.clone(), quat: g.camera.quaternion.clone(), fov: g.camera.fov };
    this._ensureDom();
    this._show(true);
    this._paintBlack(0);
    window.addEventListener('keydown', this._onKey, true);
    try { g.audio?.music?.('silence'); } catch { /* optional */ }
    g.audio?.play?.('sting_signoff_hymn', { vol: 1 });
    this.boss?.goodnight?.();
    this._setupYardCam();
    return true;
  }

  // ------------------------------------------------------------------------------------------ update
  update(rdt) {
    if (this.morning) this._tickMorning(rdt);
    if (!this.active || this.stage === 'card' || this.stage === 'done') return;
    const dt = rdt * (Number.isFinite(this.timeScale) ? this.timeScale : 1);
    this.t += dt;
    const t = this.t, F = this._flags, g = this.game;
    const once = (k, at, fn) => { if (t >= at && !F[k]) { F[k] = true; try { fn(); } catch (err) { console.error(`[ending:${k}]`, err); } } };

    // ---- 0–4: the yard
    if (t < E.black) this._yardCam(t, dt);
    once('headSnd', E.head, () => g.audio?.play?.('crt_power_off', { pos: this.boss?.head?.screenWorld?.(), vol: 1 }));
    if (t >= E.head && t < E.black + 0.2) this.boss?.collapseHead?.((t - E.head) / 0.6);
    once('viewSnd', E.view, () => g.audio?.play?.('crt_power_off', { vol: 1.2, rate: 0.8 }));
    if (t >= E.view && t < E.room) { if (g.render?.post) g.render.post.collapse = clamp((t - E.view) / 0.6, 0, 1); }
    once('black', E.black, () => {
      this.stage = 'dot';
      this.boss?.cleanupAfterEnding?.();
      this._paintBlack(1);
    });
    // ---- 4–7: the dot winks
    if (t >= E.black && t < E.room) this._drawDot(t);
    once('wink', E.wink, () => g.audio?.play?.('smile_ting', { vol: 0.7 }));
    // ---- 7–17: the living room
    once('room', E.room, () => this._enterRoom());
    if (t >= E.room && t < E.silence) this._updateRoom(t, dt);
    once('lullaby', E.room + 0.3, () => g.audio?.play?.('telly_lullaby', { vol: 0.75 }));
    once('wake', E.face, () => g.audio?.play?.('telly_wake', { vol: 0.45 }));
    once('boing', E.hop + 0.25, () => g.audio?.play?.('telly_boing', { vol: 0.45, rate: 1.15 }));
    once('ploop', E.glove, () => g.audio?.play?.('telly_ploop', { vol: 0.6 }));
    once('giggle', E.wave + 0.5, () => g.audio?.play?.('telly_giggle', { vol: 0.45 }));
    once('zip', E.gloveIn, () => g.audio?.play?.('telly_zip', { vol: 0.5 }));
    once('offSnd', E.off, () => g.audio?.play?.('crt_power_off', { vol: 0.8 }));
    // ---- 17–20: dead air
    once('silence', E.silence, () => {
      this.stage = 'silence';
      this._leaveRoom();
      this._paintBlack(1);
      try { g.audio?.stopAll?.(); } catch { /* optional */ }
      g.audio?.music?.('silence');
    });
    // ---- 20–32: credits
    once('credits', E.credits, () => { this.stage = 'credits'; g.audio?.music?.('credits'); });
    if (t >= E.credits && t < E.freeze + 0.5) this._drawCredits(t);
    once('portrait', E.portrait, () => this._enterPortrait());
    if (t >= E.portrait && t < E.card) this._updatePortrait(t, dt);
    once('freeze', E.freeze, () => this._freeze());
    // ---- 35: STAY TUNED?
    once('card', E.card, () => this._showCard());
  }

  // ------------------------------------------------------------------------------------------ the yard (0–4)
  // A slow push-in on the Baron from the player's side, searching around him for a spot inside the yard with a clear
  // line of sight (the tower lattice, the van, the hut).
  _setupYardCam() {
    const g = this.game, b = this.boss, col = g.level?.col;
    const head = b?.head?.screenWorld?.() ? b.head.screenWorld().clone() : new THREE.Vector3(45, 6, -12);
    const p = g.player?.pos || new THREE.Vector3(45, 0, -5);
    const target = head.clone().setY(head.y - 1.0);
    const base = Math.atan2(p.z - head.z, p.x - head.x);
    // the tower lattice is see-through for collisions above 3 m: test its footprint explicitly (2D segment vs rect)
    const TW = [42.4, -14.6, 47.6, -9.4];
    const hitsTower = (a, b) => {
      for (let i = 0; i <= 24; i++) {
        const u = i / 24, x = a.x + (b.x - a.x) * u, z = a.z + (b.z - a.z) * u;
        if (x > TW[0] && x < TW[2] && z > TW[1] && z < TW[3]) return true;
      }
      return false;
    };
    const clear = (c) => {
      if (c.x < 35.8 || c.x > 50.2 || c.z < -19.2 || c.z > -2.8) return false;
      if (hitsTower(c, target)) return false;
      const d = _v3.subVectors(target, c), len = d.length();
      d.normalize();
      const hit = col?.raycast?.(c, d, len);
      return !(hit && hit.dist < len - 1.2);
    };
    let pick = null;
    for (let i = 0; i < 16 && !pick; i++) {
      const a = base + (i % 2 ? 1 : -1) * Math.ceil(i / 2) * (Math.PI / 8);
      const dir = new THREE.Vector3(Math.cos(a), 0, Math.sin(a));
      for (const [df, dt] of [[9.5, 5.8], [8, 5], [6.5, 4.2]]) {
        const from = head.clone().addScaledVector(dir, df).setY(Math.max(1.7, head.y - 1.7));
        const to = head.clone().addScaledVector(dir, dt).setY(Math.max(1.9, head.y - 1.0));
        if (clear(from) && clear(to)) { pick = { from, to }; break; }
      }
    }
    if (!pick) {
      _v.set(p.x - head.x, 0, p.z - head.z).normalize();
      pick = { from: head.clone().addScaledVector(_v, 9).setY(2), to: head.clone().addScaledVector(_v, 5.5).setY(2.4) };
    }
    this._yard = { target, from: pick.from, to: pick.to };
    // he turns to face the camera for his goodnight
    if (b) b.yaw = Math.atan2(-(this._yard.to.x - b.pos.x), -(this._yard.to.z - b.pos.z));
  }

  _yardCam(t) {
    const g = this.game, y = this._yard;
    if (!y) return;
    const k = easeInOut(t / E.black);
    const cam = g.camera;
    cam.position.lerpVectors(y.from, y.to, k);
    cam.lookAt(y.target);
    if (Math.abs(cam.fov - 50) > 0.01) { cam.fov = 50; cam.updateProjectionMatrix(); }
    cam.updateMatrixWorld();
  }

  // ------------------------------------------------------------------------------------------ DOM overlay
  _ensureDom() {
    if (this._dom) return;
    const st = document.createElement('style');
    st.textContent = `
.de-end{position:fixed;inset:0;z-index:18;pointer-events:none;user-select:none;display:none;font-family:${FONTS.hud};color:#F6E7C8}
.de-end canvas.de-main{position:absolute;inset:0;width:100%;height:100%}
.de-end .de-warm{position:absolute;inset:0;background:radial-gradient(ellipse at 50% 45%,rgba(255,230,190,0) 40%,rgba(40,22,8,.62) 100%);opacity:0;transition:opacity .45s ease}
.de-end .de-frame{position:absolute;inset:3.2vh 3.2vw;border:1.1vh solid #F2E6CC;box-shadow:0 0 0 100vmax rgba(20,12,6,.0),inset 0 0 4vh rgba(60,30,10,.45);opacity:0;transition:opacity .45s ease;border-radius:.6vh}
.de-end .de-flash{position:absolute;inset:0;background:#fff;opacity:0}
.de-end .de-card{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%) scale(.6);opacity:0;transition:transform .5s cubic-bezier(.2,1.4,.4,1),opacity .35s ease;
  text-align:center;pointer-events:none;padding:4.2vh 6vh 4.6vh;border-radius:3vh;background:linear-gradient(180deg,#3A2458 0%,#1D1330 100%);
  box-shadow:0 0 0 .7vh #F2C14E,0 0 0 1.4vh #D9602B,0 2vh 6vh rgba(0,0,0,.6)}
.de-end .de-card.on{transform:translate(-50%,-50%) scale(1);opacity:1;pointer-events:auto}
.de-end .de-card h1{margin:0;font-family:${FONTS.logo};font-weight:400;font-size:10.5vh;line-height:1;color:#FFE9B8;
  text-shadow:.45vh .45vh 0 #D9602B,.9vh .9vh 0 #7A2A4A;letter-spacing:.2vh}
.de-end .de-card .de-yn{margin-top:3.6vh;display:flex;gap:4vh;justify-content:center}
.de-end .de-card button{all:unset;cursor:pointer;display:flex;align-items:center;gap:1.4vh;font-family:${FONTS.hud};font-size:4.4vh;color:#F6E7C8;
  padding:1.2vh 2.6vh 1.2vh 1.2vh;border-radius:1.6vh;background:rgba(255,255,255,.06);transition:transform .12s ease,background .12s ease}
.de-end .de-card button:hover,.de-end .de-card button.hot{background:rgba(255,210,120,.18);transform:scale(1.06)}
.de-end .de-card kbd{display:inline-flex;align-items:center;justify-content:center;width:7vh;height:7vh;border-radius:1.4vh;font-family:${FONTS.hud};font-size:4.6vh;
  color:#2A1D3A;background:linear-gradient(180deg,#FFF3D6,#E8C98A);box-shadow:0 .6vh 0 #9A6A2A}`;
    document.head.appendChild(st);
    const root = document.createElement('div');
    root.className = 'de-end';
    root.innerHTML = `<canvas class="de-main"></canvas><div class="de-warm"></div><div class="de-frame"></div><div class="de-flash"></div>
      <div class="de-card"><h1>STAY TUNED?</h1><div class="de-yn"><button class="de-y"><kbd>Y</kbd>YES</button><button class="de-n"><kbd>N</kbd>NO</button></div></div>`;
    document.body.appendChild(root);
    const q = (s) => root.querySelector(s);
    this._dom = { root, style: st, canvas: q('canvas'), ctx: q('canvas').getContext('2d'), warm: q('.de-warm'), frame: q('.de-frame'),
      flash: q('.de-flash'), card: q('.de-card'), y: q('.de-y'), n: q('.de-n') };
    this._dom.y.addEventListener('click', () => this._choose('y'));
    this._dom.n.addEventListener('click', () => this._choose('n'));
  }

  _show(on) {
    if (!this._dom) return;
    this._dom.root.style.display = on ? 'block' : 'none';
  }

  _fit() {
    const c = this._dom.canvas;
    const w = Math.max(320, Math.min(1920, innerWidth)), h = Math.round(w * innerHeight / innerWidth);
    if (c.width !== w || c.height !== h) { c.width = w; c.height = h; }
    return { w: c.width, h: c.height, x: this._dom.ctx };
  }

  // a = opacity of the black cover (0 = see the 3D scene)
  _paintBlack(a) {
    if (!this._dom) return;
    const { w, h, x } = this._fit();
    x.clearRect(0, 0, w, h);
    if (a > 0) { x.fillStyle = `rgba(0,0,0,${a})`; x.fillRect(0, 0, w, h); }
    this._dom.canvas.style.opacity = '1';
  }

  // 4–7: the lingering dot grows two tiny eyes and winks.
  _drawDot(t) {
    const { w, h, x } = this._fit();
    x.fillStyle = '#000';
    x.fillRect(0, 0, w, h);
    const s = h / 720;
    const u = t - E.black;
    let r = 5 * s;
    if (t >= E.eyes) r = lerp(5, 30, easeOutBack((t - E.eyes) / 0.5, 2)) * s;
    if (t > E.room - 0.45) r *= Math.max(0, (E.room - t) / 0.45);
    const cx = w / 2, cy = h / 2;
    const glow = x.createRadialGradient(cx, cy, 0, cx, cy, r * 4 + 10 * s);
    glow.addColorStop(0, 'rgba(235,240,255,0.9)'); glow.addColorStop(0.3, 'rgba(200,210,255,0.25)'); glow.addColorStop(1, 'rgba(200,210,255,0)');
    x.fillStyle = glow;
    x.beginPath(); x.arc(cx, cy, r * 4 + 10 * s, 0, TAU); x.fill();
    x.fillStyle = '#FBFBFF';
    x.beginPath(); x.arc(cx, cy + Math.sin(u * 3) * 1.5 * s, r, 0, TAU); x.fill();
    if (t >= E.eyes + 0.25 && r > 12 * s) {
      const ey = cy - r * 0.12, ex = r * 0.34, er = r * 0.13;
      const winking = t >= E.wink && t < E.wink + 0.55;
      x.fillStyle = '#1B1430';
      x.strokeStyle = '#1B1430';
      x.lineCap = 'round';
      // left eye (viewer's left) always open; the right one winks
      x.beginPath(); x.ellipse(cx - ex, ey, er, er * 1.35, 0, 0, TAU); x.fill();
      if (winking) {
        x.lineWidth = er * 0.8;
        x.beginPath(); x.arc(cx + ex, ey + er * 0.2, er * 1.1, Math.PI * 1.15, Math.PI * 1.85); x.stroke();
      } else {
        x.beginPath(); x.ellipse(cx + ex, ey, er, er * 1.35, 0, 0, TAU); x.fill();
      }
      // a tiny smile
      x.lineWidth = er * 0.55;
      x.beginPath(); x.arc(cx, cy + r * 0.12, r * 0.28, Math.PI * 0.2, Math.PI * 0.8); x.stroke();
    }
  }

  // ------------------------------------------------------------------------------------------ living room (7–17)
  _enterRoom() {
    const g = this.game;
    this.stage = 'room';
    if (g.render?.post) g.render.post.collapse = 0;
    let room = null;
    try { room = g.menu?.getLivingRoom?.(); } catch (err) { console.warn('[ending] living room unavailable', err); }
    this._room = room;
    if (!room) return;
    // the TV picture: our own canvas (sign-off film -> Telly's face -> CRT power-off)
    if (!this._tv) {
      const c = document.createElement('canvas');
      c.width = 384; c.height = 288;
      const tex = new THREE.CanvasTexture(c);
      tex.colorSpace = THREE.SRGBColorSpace;
      this._tv = { canvas: c, ctx: c.getContext('2d'), tex };
    }
    try { room.setPicture(this._tv.tex); } catch { /* optional */ }
    this._buildKid(room);
    const telly = room.telly;
    this._tellyRest = null;
    if (telly) {
      const P = telly.userData?.parts || {};
      this._tellyRest = {
        bodyY: P.body ? P.body.position.y : 0, bodySX: P.body ? P.body.scale.x : 1,
        earL: P.earL ? P.earL.rotation.clone() : null, earR: P.earR ? P.earR.rotation.clone() : null,
      };
      try { this._attachSideArm(telly); } catch (err) { console.warn('[ending] telly side arm', err); }
    }
    telly?.updateMatrixWorld?.(true);
    const scr = telly?.userData?.parts?.screen;
    const sw = scr ? scr.getWorldPosition(new THREE.Vector3()) : new THREE.Vector3(0.12, 1.0, 1.2);
    this._roomCamPath = {
      screen: sw,
      p0: sw.clone().add(new THREE.Vector3(0, 0.02, -0.42)),
      p1: new THREE.Vector3(1.62, 1.62, -2.95),                     // over the sleeping kid's shoulder, behind the couch
      p2: new THREE.Vector3(0.45, 1.22, -0.55),                     // then in on Telly
      look0: sw.clone(),
      look1: new THREE.Vector3(0.12, 0.5, 0.5),
      look2: sw.clone().add(new THREE.Vector3(-0.05, -0.1, 0)),
    };
    if (!this._roomCam) this._roomCam = new THREE.PerspectiveCamera(42, innerWidth / innerHeight, 0.05, 60);
    this._roomCam.aspect = innerWidth / innerHeight;
    this._roomCam.updateProjectionMatrix();
    try { room.activate(this._roomCam); } catch (err) { console.warn('[ending] room.activate', err); }
  }

  _updateRoom(t, dt) {
    const g = this.game, room = this._room;
    const u = t - E.room;
    // black cover: fade in at 7.0, out at 16.7
    const cover = t < E.room + 0.55 ? 1 - smooth(u / 0.55) : t > E.roomOut ? smooth((t - E.roomOut) / (E.silence - E.roomOut)) : 0;
    this._paintBlack(cover);
    if (!room) return;
    // camera: dolly back from the TV glass to reveal the room, then a slow push toward Telly
    const P = this._roomCamPath, cam = this._roomCam;
    if (P && cam) {
      const k1 = easeInOut((t - (E.room + 0.3)) / 3.4);
      const k2 = easeInOut((t - E.face) / 5.8);
      cam.position.lerpVectors(P.p0, P.p1, k1).lerp(P.p2, k2 * 0.85);
      _v.lerpVectors(P.look0, P.look1, k1).lerp(P.look2, k2 * 0.85);
      cam.fov = lerp(40, 38, k1);
      cam.updateProjectionMatrix();
      cam.lookAt(_v);
      cam.updateMatrixWorld();
    }
    this._drawTv(t);
    this._animateTelly(t);
    this._animateKid(t, dt);
  }

  // The console TV's picture: the station's sign-off film, then Telly's sleepy face, then its CRT power-off dot.
  _drawTv(t) {
    const tv = this._tv;
    if (!tv) return;
    const x = tv.ctx, w = tv.canvas.width, h = tv.canvas.height, g = this.game;
    x.fillStyle = '#000';
    x.fillRect(0, 0, w, h);
    const draw = (id, time, opts) => { try { g.cards.drawTo(x, id, w, h, time, opts); } catch { /* optional */ } };
    if (t < E.face) {
      draw('signoff_film', 3.2 + (t - E.room) * 0.9);
    } else if (t < E.off) {
      let expr = 'sleepy';
      if (t >= E.hop && t < E.hop + 0.5) expr = 'o_mouth';
      else if (t >= E.wave && t < E.wave + 1.4) expr = 'happy';
      else if (t >= E.wave + 1.4 && t < E.waveEnd) expr = 'wink';
      else if (t >= E.waveEnd) expr = 'sleepy';
      draw('telly_face', t, { expr, look: [0.15, -0.1] });
      if (t < E.face + 0.18) { x.fillStyle = `rgba(255,255,255,${1 - (t - E.face) / 0.18})`; x.fillRect(0, 0, w, h); }
    } else {
      // CRT power-off: squash into a white line, shrink into a dot, fade
      const k = (t - E.off) / 0.9;
      if (k < 0.35) {
        draw('telly_face', t, { expr: 'sleepy' });
        const sy = 1 - smooth(k / 0.35);
        x.fillStyle = '#000';
        const band = h * sy / 2;
        x.fillRect(0, 0, w, h / 2 - band);
        x.fillRect(0, h / 2 + band, w, h / 2 - band);
        x.fillStyle = `rgba(255,255,255,${0.5 + k})`;
        x.fillRect(0, h / 2 - band, w, band * 2);
      } else if (k < 0.7) {
        const sx = 1 - smooth((k - 0.35) / 0.35);
        const lw = Math.max(6, w * sx);
        const gr = x.createLinearGradient(w / 2 - lw / 2, 0, w / 2 + lw / 2, 0);
        gr.addColorStop(0, 'rgba(255,255,255,0)'); gr.addColorStop(0.5, 'rgba(255,255,255,1)'); gr.addColorStop(1, 'rgba(255,255,255,0)');
        x.fillStyle = gr;
        x.fillRect(w / 2 - lw / 2, h / 2 - 3, lw, 6);
      } else {
        const a = Math.max(0, 1 - (t - (E.off + 0.63)) / 0.9);
        const gr = x.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, 14);
        gr.addColorStop(0, `rgba(255,255,255,${a})`); gr.addColorStop(1, 'rgba(255,255,255,0)');
        x.fillStyle = gr;
        x.fillRect(w / 2 - 16, h / 2 - 16, 32, 32);
      }
    }
    tv.tex.needsUpdate = true;
  }

  _animateTelly(t) {
    const telly = this._room?.telly, R = this._tellyRest;
    if (!telly || !R) return;
    const P = telly.userData.parts || {};
    // ears: two quick twitches after the face comes on, a sleepy droop otherwise
    const tw = (at) => { const k = (t - at) / 0.35; return k > 0 && k < 1 ? Math.sin(k * Math.PI * 3) * (1 - k) : 0; };
    const twitch = tw(E.ears) + tw(E.ears + 0.55) * 0.8 + tw(E.waveEnd + 0.1) * 0.5;
    if (P.earL && R.earL) P.earL.rotation.set(R.earL.x, R.earL.y, R.earL.z + twitch * 0.35);
    if (P.earR && R.earR) P.earR.rotation.set(R.earR.x, R.earR.y, R.earR.z - twitch * 0.3);
    // the tiny sleepy hop (squash, up, land, settle)
    if (P.body) {
      const k = (t - E.hop) / 0.9;
      let dy = 0, sq = 1;
      if (k > 0 && k < 1) {
        if (k < 0.22) sq = 1 - 0.1 * Math.sin((k / 0.22) * Math.PI);
        else if (k < 0.7) { const a = (k - 0.22) / 0.48; dy = Math.sin(a * Math.PI) * 0.11; sq = 1 + 0.05 * Math.sin(a * Math.PI); }
        else { const a = (k - 0.7) / 0.3; sq = 1 - 0.07 * Math.sin(a * Math.PI) * (1 - a); }
      }
      const breathe = t > E.face ? Math.sin(t * 2.1) * 0.006 : 0;
      P.body.position.y = R.bodyY + dy;
      P.body.scale.set(R.bodySX * (2 - sq), R.bodySX * (sq + breathe), R.bodySX * (2 - sq));
    }
    // the glove: Telly's RIGHT hand (the viewer's left) reaches out of a little hatch in the cabinet's right side
    // wall, rises beside the screen, waves goodnight and tucks back in (the gameplay presentation, out of the screen
    // centre, is untouched: this is a local arm, see _attachSideArm)
    const A = this._sideArm;
    if (A && A.rig.parent) {
      const on = t >= E.glove && t < E.gloveIn + 0.35;
      const out = !on ? 0 : t < E.wave ? easeOutBack((t - E.glove) / 0.3) : t > E.gloveIn ? 1 - smooth((t - E.gloveIn) / 0.3) : 1;
      const show = out > 0.02;
      A.arm.visible = A.glove.visible = show;
      A.hatch.visible = on;
      if (on) {
        // the hatch pops open first and snaps shut after the glove is back in
        const hk = t < E.glove + 0.12 ? easeOutBack((t - E.glove) / 0.12, 2.5) : t > E.gloveIn + 0.24 ? 1 - smooth((t - E.gloveIn - 0.24) / 0.11) : 1;
        A.hatch.scale.setScalar(Math.max(0.001, hk));
      }
      if (show) {
        const k = clamp(out, 0, 1.2);
        const wave = t >= E.wave && t < E.waveEnd ? Math.sin((t - E.wave) * 9) * 0.45 * Math.min(1, (t - E.wave) / 0.15) : 0;
        // out of the wall (fingers first, pointing away from the cabinet), then up beside the screen, palm to the viewer
        A.glove.position.set(lerp(-0.1, 0.2, k), 0.31 * Math.pow(Math.max(0, k), 1.6), lerp(0, -0.14, k));
        A.glove.rotation.set(0.1, -0.15, lerp(-Math.PI / 2, 0, clamp(k, 0, 1)) + wave, 'XYZ');
        const s = A.scale * lerp(0.55, 1, clamp(k, 0, 1));
        A.glove.scale.set(-s, s, s);                        // mirrored: the prop's glove is a left hand
        A.ctrl.position.set(lerp(0.02, 0.2, k) + wave * 0.03, lerp(0, 0.02, k), lerp(0, -0.06, k));
        try { updateTellyArm(A.proxy); } catch { /* optional */ }
      }
    }
  }

  // Telly's goodnight arm for the ending (built once, parented to the living-room Telly's body while in the room):
  // a copy of the prop's glove (shared geometry/materials, mirrored into a right hand) on a copy of its accordion arm,
  // rooted inside the cabinet's right side wall behind a brass-ringed hatch found by raycasting that wall. The prop's
  // own glove/arm stay hidden (no screen membrane parting, the menu keeps the picture seated at the front).
  _attachSideArm(telly) {
    const P = telly?.userData?.parts;
    if (!P || !P.body || !P.glove || !P.arm) return;
    if (!this._sideArm) {
      const saved = [];
      P.glove.traverse((o) => { saved.push([o, o.userData]); o.userData = {}; });
      let glove;
      try { glove = P.glove.clone(true); } finally { for (const [o, u] of saved) o.userData = u; }
      glove.name = 'ending:tellyGlove';
      glove.visible = true;
      glove.position.set(0, 0, 0);
      glove.quaternion.identity();
      for (const n of ['index', 'middle', 'pinky']) { const f = glove.getObjectByName(`glove_${n}`); if (f) f.rotation.x = -0.12; }
      const th = glove.getObjectByName('glove_thumb');
      if (th) th.rotation.x = -0.45;
      const arm = new THREE.Mesh(P.arm.geometry.clone(), P.arm.material);
      arm.name = 'ending:tellyArm';
      arm.frustumCulled = false;
      arm.castShadow = P.arm.castShadow;
      arm.receiveShadow = P.arm.receiveShadow;
      const ctrl = new THREE.Object3D();
      // hatch: a dark hole in a brass ring, facing out of the wall (+x); vertex-coloured like the arm (same material)
      const tint = (g, hex) => {
        const c = new THREE.Color(hex), n = g.attributes.position.count, a = new Float32Array(n * 3);
        for (let i = 0; i < n; i++) { a[i * 3] = c.r; a[i * 3 + 1] = c.g; a[i * 3 + 2] = c.b; }
        g.setAttribute('color', new THREE.BufferAttribute(a, 3));
        return g;
      };
      const hatch = new THREE.Group();
      hatch.name = 'ending:tellyHatch';
      const hole = new THREE.Mesh(tint(new THREE.CircleGeometry(0.066, 24), '#150C12'), P.arm.material);
      const ring = new THREE.Mesh(tint(new THREE.TorusGeometry(0.07, 0.013, 8, 28), '#C8963C'), P.arm.material);
      hatch.add(hole, ring);
      hatch.rotation.y = Math.PI / 2;
      const rig = new THREE.Group();
      rig.name = 'ending:tellySideArm';
      rig.add(arm, glove, ctrl);
      this._sideArm = { rig, arm, glove, ctrl, hatch, scale: Math.abs(P.glove.scale.x) || 1.35,
        proxy: { userData: { parts: { arm, glove, armCtrl: ctrl } } } };
    }
    const A = this._sideArm;
    this._detachSideArm();
    // the right side wall (+x, body space) just below the screen centre, a little toward the front: the arm bends up
    const hy = 0.45, hz = -0.06;
    let hx = 0.73;
    try {
      telly.updateMatrixWorld(true);
      const o = P.body.localToWorld(new THREE.Vector3(1.6, hy, hz));
      const d = P.body.localToWorld(new THREE.Vector3(0.6, hy, hz)).sub(o).normalize();
      const meshes = [];
      P.body.traverse((m) => { if (m.isMesh && m.visible && m !== P.arm && !P.glove.getObjectById(m.id)) meshes.push(m); });
      const hit = new THREE.Raycaster(o, d, 0, 1.2).intersectObjects(meshes, false)[0];
      if (hit) { const lp = P.body.worldToLocal(hit.point.clone()); if (lp.x > 0.55 && lp.x < 0.9) hx = lp.x; }
    } catch { /* keep the estimate */ }
    A.hatch.position.set(hx + 0.003, hy, hz);
    A.rig.position.set(hx - 0.035, hy, hz);              // tube root inside the wall
    A.arm.visible = A.glove.visible = A.hatch.visible = false;
    P.body.add(A.rig, A.hatch);
  }

  _detachSideArm() {
    const A = this._sideArm;
    if (!A) return;
    A.rig.removeFromParent();
    A.hatch.removeFromParent();
  }

  // A kid asleep on the couch in the WZTV "13" cap (Skip's sculpted model, kid-sized) hugging a popcorn bowl.
  _buildKid(room) {
    const g = this.game;
    if (!this._kid) {
      let hero = null;
      try { hero = buildHero('skip', g); } catch (err) { console.warn('[ending] kid build failed', err); }
      if (!hero) return;
      const grp = new THREE.Group();
      grp.name = 'ending_kid';
      grp.add(hero.group);
      hero.group.scale.setScalar(0.7);
      // popcorn bowl in the lap
      const bowl = new THREE.Group();
      const M = g.mats;
      const b = new THREE.Mesh(new THREE.SphereGeometry(0.12, 18, 10, 0, TAU, Math.PI * 0.5, Math.PI * 0.5), M.toon('#E23B3B', { rough: 0.35, rim: 0.3, keepColor: true, side: THREE.DoubleSide }));
      b.scale.set(1, 0.7, 1);
      bowl.add(b);
      const pop = M.toon('#FFF3D0', { rough: 0.9, rim: 0.45, rimColor: '#FFE6A0', wrap: 0.8, keepColor: true });
      const pg = new THREE.IcosahedronGeometry(0.022, 1);
      for (let i = 0; i < 22; i++) {
        const a = i * 2.4, r = 0.015 + (i % 6) * 0.015;
        const m = new THREE.Mesh(pg, pop);
        m.position.set(Math.cos(a) * r, -0.015 + (i % 3) * 0.012 + (0.1 - r) * 0.2, Math.sin(a) * r);
        m.scale.setScalar(0.8 + (i % 4) * 0.12);
        bowl.add(m);
      }
      grp.add(bowl);
      // sleepy "z Z z" floating up from the kid
      const zc = document.createElement('canvas');
      zc.width = zc.height = 96;
      const zx = zc.getContext('2d');
      zx.font = `78px ${FONTS.logo}`;
      zx.textAlign = 'center'; zx.textBaseline = 'middle';
      zx.lineWidth = 9; zx.strokeStyle = '#2A1D3A'; zx.lineJoin = 'round';
      zx.strokeText('Z', 48, 52);
      zx.fillStyle = '#FFF1CC';
      zx.fillText('Z', 48, 52);
      const ztex = new THREE.CanvasTexture(zc);
      ztex.colorSpace = THREE.SRGBColorSpace;
      const zs = [];
      for (let i = 0; i < 3; i++) {
        const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: ztex, transparent: true, depthWrite: false, fog: false }));
        s.renderOrder = 6;
        grp.add(s);
        zs.push(s);
      }
      this._kid = { group: grp, hero, bowl, zs };
      hero.group.traverse((o) => { if (o.isMesh) { o.castShadow = true; } });
    }
    const K = this._kid;
    // the couch (sofa_cloud at z -1.95 facing the TV): the kid slumps in its right-hand corner
    K.group.position.set(0.52, 0.2, -1.92);
    K.group.rotation.set(0, Math.PI, 0);
    if (!K.group.parent) room.root.add(K.group);
    const hero = K.hero;
    if (hero.art?.face) { hero.art.face.auto = false; hero.art.face.setExpression('smile', 0.6); }
    if (hero.animator) hero.animator.override = (rig) => this._kidPose(rig);
  }

  _kidPose(rig) {
    const J = rig.joints, t = this.t;
    const br = Math.sin(t * 1.6) * 0.03;
    const set = (n, x, y, z) => { const j = J[n]; if (j) j.rotation.set(x, y, z); };
    set('hips', -0.35, 0, 0);
    set('spine', -0.12 + br * 0.5, 0, 0.05);
    set('chest', -0.05 + br, 0, 0.04);
    set('neck', 0.22, 0.35, 0.3);
    set('head', 0.18, 0.55, 0.32 + Math.sin(t * 0.8) * 0.02);
    set('hipL', 1.65, 0.12, 0.08); set('kneeL', -1.55, 0, 0); set('footL', 0.2, 0, 0);
    set('hipR', 1.6, -0.2, -0.12); set('kneeR', -1.45, 0, 0); set('footR', 0.25, 0, 0);
    set('shoulderL', 0.75, 0, -0.35); set('elbowL', 1.35, 0, 0); set('handL', 0, 0, 0.2);
    set('shoulderR', 0.55, 0, 0.45); set('elbowR', 1.25, 0, 0); set('handR', 0, 0, -0.2);
  }

  _animateKid(t, dt) {
    const K = this._kid;
    if (!K || !K.group.parent) return;
    const hero = K.hero;
    const f = hero.art?.face;
    if (f) f.blinkPhase = 0.46 - (dt || 0.016) / 0.16;       // eyes shut (held mid-blink)
    try { hero.animator?.update?.(dt || 0.016, { speed: 0, grounded: true }); } catch { /* optional */ }
    // z Z z: three letters rising from the head, drifting and fading, staggered
    const J = hero.rig?.joints;
    if (J && J.head && K.zs) {
      J.head.getWorldPosition(_v);
      K.group.worldToLocal(_v);
      K.zs.forEach((s, i) => {
        const u = ((t * 0.42) + i / 3) % 1;
        s.position.set(_v.x - 0.08 - u * 0.25, _v.y + 0.22 + u * 0.55, _v.z + Math.sin(u * 6 + i) * 0.05);
        const sc = 0.07 + u * 0.12;
        s.scale.set(sc, sc, 1);
        s.material.opacity = Math.min(1, u * 5) * (1 - smooth((u - 0.6) / 0.4));
        s.material.rotation = Math.sin(u * 5 + i) * 0.3;
      });
    }
    // bowl rests on the lap (between the hands)
    if (J && J.handL && J.handR) {
      J.handL.getWorldPosition(_v); J.handR.getWorldPosition(_v2);
      _v.add(_v2).multiplyScalar(0.5);
      K.group.worldToLocal(_v3.copy(_v));
      K.bowl.position.copy(_v3).add(_v2.set(0, 0.02, 0));
    }
  }

  _leaveRoom() {
    const room = this._room;
    if (this._kid && this._kid.group.parent) this._kid.group.parent.remove(this._kid.group);
    if (room) {
      const telly = room.telly, R = this._tellyRest;
      if (telly && R) {
        const P = telly.userData.parts || {};
        if (P.body) { P.body.position.y = R.bodyY; P.body.scale.setScalar(R.bodySX); }
        if (P.earL && R.earL) P.earL.rotation.copy(R.earL);
        if (P.earR && R.earR) P.earR.rotation.copy(R.earR);
        try { setTellyGlove(telly, 'hidden'); } catch { /* optional */ }
      }
      this._detachSideArm();
      this._gloveOut = false;
      try { room.setPicture(null); } catch { /* optional */ }
      try { room.deactivate(); } catch { /* optional */ }
    }
    this._room = null;
  }

  // ------------------------------------------------------------------------------------------ credits (20–32)
  _creditLines() {
    const me = HEROES.find((h) => h.id === this.heroId) || HEROES[HEROES.length - 1];
    const others = HEROES.filter((h) => h !== me);
    const L = [];
    const add = (text, kind, gap = 0) => L.push({ text, kind, gap });
    add('STARRING', 'head', 0);
    add(me.name.toUpperCase(), 'star', 0.3);
    add(`as ${me.role.toLowerCase()} of the night shift`, 'role', 0.1);
    add('CO-STARRING', 'head', 1.2);
    for (const h of others) { add(h.name.toUpperCase(), 'name', 0.35); add(`as the ${h.role.toLowerCase()}`, 'role', 0.05); }
    add('SPECIAL GUEST STAR', 'head', 1.2);
    add('BARON VON STATIC', 'name', 0.3);
    add('as himself', 'role', 0.05);
    add('WITH', 'head', 1.0);
    add('TELLY', 'name', 0.3); add('as the television', 'role', 0.05);
    add('THE TUNED-IN', 'name', 0.35); add('as the studio audience', 'role', 0.05);
    add('HOOTIE, DUDLEY & SOCKRATES', 'name', 0.35); add('as the puppets', 'role', 0.05);
    add('STORMY STU', 'name', 0.35); add('as the weather', 'role', 0.05);
    add('AND', 'head', 1.3);
    add('WZTV CHANNEL 13', 'big', 0.35);
    add('good night, and stay tuned', 'role', 0.5);
    return L;
  }

  _drawCredits(t) {
    const { w, h, x } = this._fit();
    const s = h / 720;
    const u = t - E.credits;
    // backdrop: deep indigo, slow 70s sunburst, scanlines
    const bg = x.createRadialGradient(w / 2, h * 0.46, 0, w / 2, h * 0.46, h * 0.95);
    bg.addColorStop(0, '#3A2466'); bg.addColorStop(0.55, '#1C1336'); bg.addColorStop(1, '#0B0818');
    x.fillStyle = bg;
    x.fillRect(0, 0, w, h);
    x.save();
    x.translate(w / 2, h * 0.46);
    x.rotate(u * 0.05);
    const rays = 18;
    const cols = ['rgba(227,102,43,0.13)', 'rgba(232,169,46,0.12)', 'rgba(181,71,42,0.1)'];
    for (let i = 0; i < rays; i++) {
      x.fillStyle = cols[i % 3];
      x.beginPath();
      x.moveTo(0, 0);
      x.arc(0, 0, h * 1.2, (i / rays) * TAU, ((i + 0.5) / rays) * TAU);
      x.closePath();
      x.fill();
    }
    x.restore();
    // chrome "13" ident, breathing, with a glint sweeping across
    if (!this._ident) this._ident = chromeIdent();
    const I = this._ident;
    const iw = h * 0.95 * (I.width / I.height), ih = h * 0.95;
    const pulse = 1 + Math.sin(u * 1.2) * 0.012;
    const ix = w / 2 - (iw * pulse) / 2, iy = h * 0.46 - (ih * pulse) / 2;
    x.globalAlpha = 0.9;
    x.drawImage(I, ix, iy, iw * pulse, ih * pulse);
    x.globalAlpha = 1;
    // glint sweeping across the chrome only (composited on a scratch copy of the ident)
    if (!this._glint) { this._glint = document.createElement('canvas'); this._glint.width = I.width; this._glint.height = I.height; }
    const gc = this._glint, gx2 = gc.getContext('2d');
    gx2.globalCompositeOperation = 'source-over';
    gx2.clearRect(0, 0, gc.width, gc.height);
    gx2.drawImage(I, 0, 0);
    gx2.globalCompositeOperation = 'source-in';
    const gp = ((u * 0.3) % 1.7 - 0.35) * gc.width;
    const gl = gx2.createLinearGradient(gp - 90, 0, gp + 90, gc.height * 0.25);
    gl.addColorStop(0, 'rgba(255,255,255,0)'); gl.addColorStop(0.5, 'rgba(255,252,240,0.85)'); gl.addColorStop(1, 'rgba(255,255,255,0)');
    gx2.fillStyle = gl;
    gx2.fillRect(0, 0, gc.width, gc.height);
    x.save();
    x.globalCompositeOperation = 'lighter';
    x.globalAlpha = 0.55;
    x.drawImage(gc, ix, iy, iw * pulse, ih * pulse);
    x.restore();
    star(x, ix + iw * 0.22, iy + ih * 0.3, (22 + 10 * Math.sin(u * 3)) * s, 0.8);
    star(x, ix + iw * 0.8, iy + ih * 0.62, (16 + 8 * Math.sin(u * 2.3 + 1)) * s, 0.7);
    // dim the ident under the crawl
    x.fillStyle = 'rgba(12,8,24,0.42)';
    x.fillRect(0, 0, w, h);
    // the crawl
    if (!this._lines) this._lines = this._creditLines();
    const SZ = { head: 26, star: 64, name: 44, role: 24, big: 62 };
    const LH = { head: 1.4, star: 1.2, name: 1.2, role: 1.5, big: 1.25 };
    let total = 0;
    for (const l of this._lines) total += (l.gap * 60 + SZ[l.kind] * LH[l.kind]) * s;
    const dur = E.portrait + 0.6 - E.credits;
    const off = lerp(h + 30 * s, -total - 30 * s, clamp(u / dur, 0, 1));
    let y = off;
    x.textAlign = 'center';
    x.textBaseline = 'alphabetic';
    for (const l of this._lines) {
      y += l.gap * 60 * s;
      const sz = SZ[l.kind] * s;
      y += sz * LH[l.kind];
      if (y < -40 * s || y > h + 60 * s) continue;
      const fade = clamp(Math.min(y / (h * 0.12), (h - y) / (h * 0.12)), 0, 1);
      x.globalAlpha = fade;
      if (l.kind === 'head' || l.kind === 'role') {
        x.font = `${sz}px ${l.kind === 'head' ? FONTS.logo : FONTS.hud}`;
        x.fillStyle = l.kind === 'head' ? '#FFB347' : '#E9D8BE';
        x.fillText(l.text, w / 2, y);
      } else {
        x.font = `${sz}px ${FONTS.hud}`;
        x.fillStyle = '#7A2A4A';
        x.fillText(l.text, w / 2 + 4 * s, y + 4 * s);
        x.fillStyle = '#D9602B';
        x.fillText(l.text, w / 2 + 2 * s, y + 2 * s);
        x.fillStyle = l.kind === 'big' || l.kind === 'star' ? '#FFF0C8' : '#F6E7C8';
        x.fillText(l.text, w / 2, y);
      }
    }
    x.globalAlpha = 1;
    // scanlines + vignette
    x.fillStyle = 'rgba(0,0,0,0.12)';
    for (let yy = 0; yy < h; yy += 3 * Math.max(1, Math.round(s))) x.fillRect(0, yy, w, 1);
    const vg = x.createRadialGradient(w / 2, h / 2, h * 0.35, w / 2, h / 2, h * 0.95);
    vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,0.55)');
    x.fillStyle = vg;
    x.fillRect(0, 0, w, h);
    // the crawl gives way to the portrait (31.0–31.8)
    const k = clamp((t - (E.portrait + 0.4)) / 0.8, 0, 1);
    this._dom.canvas.style.opacity = String(1 - k);
  }

  // ------------------------------------------------------------------------------------------ portrait + freeze
  _enterPortrait() {
    const g = this.game;
    this.stage = 'portrait';
    try {
      if (!this._portrait) this._portrait = this._buildPortrait();
      const P = this._portrait;
      const r = g.render;
      if (r && r.renderPass) {
        this._savedPass = { scene: r.renderPass.scene, camera: r.renderPass.camera };
        P.camera.aspect = innerWidth / innerHeight;
        P.camera.updateProjectionMatrix();
        r.renderPass.scene = P.scene;
        r.renderPass.camera = P.camera;
      }
    } catch (err) { console.error('[ending] portrait', err); this._portrait = null; }
  }

  _buildPortrait() {
    const g = this.game, M = g.mats;
    const scene = new THREE.Scene();
    scene.name = 'ending:portrait';
    scene.background = new THREE.Color('#1A1226');
    // same light counts as core/lights.js (hemisphere, key with shadow, fill, 8 points): reuses the station's programs
    const hemi = new THREE.HemisphereLight('#FFE8CC', '#4A3040', 0.9);
    const key = new THREE.DirectionalLight('#FFE2BE', 2.0);
    key.position.set(-2.2, 4, -3.2);
    key.castShadow = true;
    key.shadow.mapSize.set(1024, 1024);
    Object.assign(key.shadow.camera, { left: -3, right: 3, top: 3, bottom: -3, near: 0.5, far: 20 });
    key.shadow.bias = -0.0006; key.shadow.normalBias = 0.03;
    const fill = new THREE.DirectionalLight('#A8BCFF', 0.55);
    fill.position.set(2.5, 1.5, -2);
    scene.add(hemi, key, key.target, fill);
    const pts = [];
    for (let i = 0; i < 8; i++) { const p = new THREE.PointLight('#ffffff', 0, 6, 1.5); scene.add(p); pts.push(p); }
    pts[0].position.set(0.9, 2.2, -1.4); pts[0].color.set('#FFC98A'); pts[0].intensity = 3; pts[0].distance = 7;
    pts[1].position.set(-1.4, 1.2, 0.6); pts[1].color.set('#FF7AB0'); pts[1].intensity = 1.6; pts[1].distance = 5;
    // the hero's show backdrop + a stage floor
    let backTex = null;
    try { backTex = g.cards.get(`promo_${this.heroId}`); } catch { backTex = null; }
    const back = new THREE.Mesh(new THREE.PlaneGeometry(6.4, 4.8), new THREE.MeshBasicMaterial({ map: backTex, color: backTex ? '#ffffff' : '#3A2A5A', fog: false }));
    back.position.set(0, 1.6, 2.2);
    back.rotation.y = Math.PI;
    scene.add(back);
    const floor = new THREE.Mesh(new THREE.CircleGeometry(4, 40), M.toon('#6B4A3A', { rough: 0.8, rim: 0.1, keepColor: true }));
    floor.rotation.x = -Math.PI / 2;
    floor.receiveShadow = true;
    scene.add(floor);
    let hero = null;
    try { hero = buildHero(this.heroId, g); } catch (err) { console.warn('[ending] portrait hero', err); }
    if (hero) {
      scene.add(hero.group);
      hero.group.rotation.y = -0.4;
      hero.group.traverse((o) => { if (o.isMesh) o.castShadow = true; });
      if (hero.art?.face) { hero.art.face.auto = false; hero.art.face.setExpression('smile', 1); hero.art.face.setLook(0.1, 0.05); }
    }
    const camera = new THREE.PerspectiveCamera(34, innerWidth / innerHeight, 0.05, 40);
    camera.position.set(0.35, 1.25, -3.1);
    camera.lookAt(0, 1.0, 0);
    scene.add(camera);
    // full colour while this scene renders (no pre-power grade / colour wave, heroes never dither-fade)
    const U = M.uniforms, saved = {};
    const WANT = { uSatEnv: 1, uAmber: 0, uWaveRadius: -1, uHeroFade: 1 };
    scene.onBeforeRender = () => { for (const k in WANT) if (U[k]) { saved[k] = U[k].value; U[k].value = WANT[k]; } };
    scene.onAfterRender = () => { for (const k in WANT) if (U[k] && k in saved) U[k].value = saved[k]; };
    return { scene, camera, hero, frozen: false, t: 0 };
  }

  _updatePortrait(t, dt) {
    const P = this._portrait;
    if (!P || P.frozen || !P.hero) return;
    const h = P.hero;
    P.t += dt;
    try {
      h.animator.pose?.(`commercial_${this.heroId}`, Math.min(1, P.t / 0.5));
      h.animator.update(dt || 0.016, { speed: 0, grounded: true });
    } catch { /* optional */ }
    const cam = P.camera;
    const k = smooth((t - E.portrait) / (E.freeze - E.portrait));
    cam.position.set(lerp(0.55, 0.3, k), lerp(1.3, 1.22, k), lerp(-3.4, -2.9, k));
    cam.lookAt(0, 1.02, 0);
  }

  _freeze() {
    const g = this.game, D = this._dom;
    this.stage = 'freeze';
    if (this._portrait) this._portrait.frozen = true;
    // sepia on the WebGL canvas itself (a mix-blend layer inside our overlay could not reach the canvas)
    const cv = g.renderer?.domElement;
    if (cv) { cv.style.transition = 'filter .45s ease'; cv.style.filter = 'sepia(0.92) saturate(1.15) contrast(1.06) brightness(0.96)'; }
    D.warm.style.opacity = '1';
    D.frame.style.opacity = '1';
    D.canvas.style.opacity = '0';
    D.flash.style.transition = 'none';
    D.flash.style.opacity = '0.85';
    void D.flash.offsetWidth;
    D.flash.style.transition = 'opacity .5s ease';
    D.flash.style.opacity = '0';
    if (g.render?.post) { this._savedGrain = g.render.post.grain; g.render.post.grain = 0.12; g.render.post.saturation = 0.35; }
    g.audio?.play?.('studio_flash', { vol: 0.8 });
    g.audio?.play?.('commercial_cut', { vol: 0.6, delay: 0.05 });
  }

  // ------------------------------------------------------------------------------------------ STAY TUNED?
  _showCard() {
    const g = this.game;
    this.stage = 'card';
    try { g.victory?.(); } catch (err) { console.error('[ending] victory', err); }
    const D = this._dom;
    this._glyphs();
    D.card.classList.add('on');
    g.audio?.play?.('ui_menu_clack', { vol: 0.8 });
    this._hot = null;
  }

  // Xbox pad (input.js routes every pad press here first while the ending runs).
  padButton(btn) {
    if (!this.active || this.game.state === 'paused') return false;
    if (this.stage === 'card') {
      if (btn === 'a') { this._choose('y'); return true; }
      if (btn === 'b') { this._choose('n'); return true; }
      return false;
    }
    if (btn !== 'a') return false;
    this._key({ code: 'Enter', preventDefault() {}, stopPropagation() {} });
    return true;
  }

  // STAY TUNED? key caps: Y / N on the keyboard, A / B (green / red) on the pad.
  _glyphs() {
    const D = this._dom;
    if (!D || !D.y) return;
    const pad = this.game.input?.device === 'pad';
    const set = (btn, key, color) => {
      const k = btn.querySelector('kbd');
      if (!k) return;
      k.textContent = key;
      k.style.borderRadius = pad ? '50%' : '';
      k.style.color = pad ? color : '';
      k.style.background = pad ? 'radial-gradient(circle at 42% 34%,#4A4048,#1E1A20 72%)' : '';
      k.style.boxShadow = pad ? '0 .6vh 0 #0E0A10' : '';
    };
    set(D.y, pad ? 'A' : 'Y', '#7EDB5A');
    set(D.n, pad ? 'B' : 'N', '#FF6A5C');
  }

  _key(e) {
    if (!this.active || this.game.state === 'paused') return;
    const k = e.code;
    if (this.stage === 'card') {
      if (k === 'KeyY') { e.preventDefault(); e.stopPropagation(); this._choose('y'); }
      else if (k === 'KeyN') { e.preventDefault(); e.stopPropagation(); this._choose('n'); }
      return;
    }
    if ((k === 'Space' || k === 'Enter' || k === 'KeyE') && this.seen && this.t >= E.skipAfter && this.t < E.freeze) {
      e.preventDefault();
      this._skip();
    }
  }

  _skip() {
    const g = this.game;
    this.boss?.cleanupAfterEnding?.();
    this._leaveRoom();
    if (g.render?.post) g.render.post.collapse = 0;
    try { g.audio?.stopAll?.(); } catch { /* optional */ }
    g.audio?.music?.('credits');
    for (const k of ['headSnd', 'viewSnd', 'black', 'wink', 'room', 'lullaby', 'wake', 'boing', 'ploop', 'giggle', 'zip', 'offSnd', 'silence', 'credits']) this._flags[k] = true;
    this._paintBlack(1);
    this.t = E.portrait;
    this._flags.portrait = true;
    this._enterPortrait();
    this.t = E.freeze - 0.4;
  }

  _choose(c) {
    if (!this.active || this.stage !== 'card') return;
    this.game.audio?.play?.('ui_tune_in', { vol: 0.8 });
    if (c === 'y') this.morningShow();
    else this.results();
  }

  // N: the results card, then the title.
  results() {
    const g = this.game;
    const summary = this.summary || { round: this.round || 0, kills: 0, points: 0 };
    this._finishSequence();
    this.boss?.finish?.();
    try {
      g.menu?.showResults?.(summary, { title: 'GOOD NIGHT', onDone: () => { try { g.menu?.showTitle?.(); } catch { /* optional */ } } });
    } catch (err) { console.error('[ending] results', err); }
  }

  // Tears the sequence down (overlay, render pass, camera, post) without touching the world state.
  _finishSequence() {
    const g = this.game;
    window.removeEventListener('keydown', this._onKey, true);
    this._leaveRoom();
    const r = g.render;
    if (r && r.renderPass && this._savedPass) {
      r.renderPass.scene = g.scene;
      r.renderPass.camera = r.cameraOverride || g.camera;
    }
    this._savedPass = null;
    if (r?.post) {
      r.post.collapse = 0;
      r.post.saturation = 1;
      if (this._savedGrain !== undefined) { r.post.grain = this._savedGrain; this._savedGrain = undefined; }
    }
    const cv = g.renderer?.domElement;
    if (cv) { cv.style.transition = ''; cv.style.filter = ''; }
    if (this._dom) {
      const D = this._dom;
      D.card.classList.remove('on');
      D.warm.style.opacity = '0'; D.frame.style.opacity = '0';
      this._show(false);
    }
    if (g.cam) g.cam.enabled = true;
    if (this._camFrom) { g.camera.fov = this._camFrom.fov; g.camera.updateProjectionMatrix(); }
    const p = g.player;
    if (p) { p.controlLocked = false; p.invulnerable = false; }
    this.active = false;
    this.stage = 'done';
    this._portrait = null;
  }

  stop() {
    if (!this.active && this.stage !== 'done' && !this._dom) return;
    if (this.active) this._finishSequence();
    this.stage = null;
    this.t = 0;
  }

  // ------------------------------------------------------------------------------------------ the Morning Show
  morningShow() {
    const g = this.game;
    const round = this.round || g.rounds?.round || 1;
    this._finishSequence();
    this.boss?.finish?.();
    g.menu?.hideAll?.();
    g.setState?.('playing');
    const p = g.player;
    if (p) {
      p.teleport?.(41.2, -9.6, -Math.PI / 2 + 0.25);
      p.health = p.maxHealth;
      p.invulnerable = true;
      setTimeout(() => { if (g.player === p) p.invulnerable = false; }, 2500);
    }
    g.hud?.show?.();
    this.morning = true;
    this._applyDawn();
    try { g.perks?.morningShow?.(); } catch (err) { console.warn('[ending] perks.morningShow', err); }
    try {
      const W = g.weapons;
      for (const s of (W?.slots || []).slice()) {
        if (!s || !s.id) continue;
        if (s.upgraded) W.refill?.(s.id);
        else W.upgrade?.(s.id, SIGNALS[Math.floor(Math.random() * SIGNALS.length)], 'uplink');
      }
    } catch (err) { console.warn('[ending] free uplinks', err); }
    try { g.economy?.add?.(MORNING_BONUS, 'morning'); } catch { /* optional */ }
    this._wrapTelly();
    try {
      const tb = g.level?.objects?.tower_beacons;
      tb?.setMode?.((g.egg?.step ?? 0) >= 4 ? 'rainbow' : 'blink');
    } catch { /* optional */ }
    g.audio?.music?.('morning');
    try { g.rounds?.startRound?.(round + 1); } catch (err) { console.warn('[ending] next round', err); }
    g.audio?.music?.('morning');
    g.events.emit('game:morning', { round: round + 1 });
    try { g.input?.requestLock?.(); } catch { /* optional */ }
  }

  _applyDawn() {
    const g = this.game, L = g.level;
    if (this._dawn) return;
    const D = { sky: null, stars: null, moon: null, areas: {}, key: null, fill: null, keyDir: null, pools: [], sun: null, clocks: [] };
    // sky dome, stars, moon
    L?.sky?.traverse?.((o) => {
      const u = o.material && o.material.uniforms;
      if (o.isMesh && u && u.uTop && u.uHorizon) D.sky = { mesh: o, top: u.uTop.value.clone(), hor: u.uHorizon.value.clone(), glow: u.uGlow?.value.clone(), ground: u.uGround?.value.clone() };
      if (o.isPoints) D.stars = o;
      if (o.isMesh && o.material && o.material.map && o.renderOrder === -8) D.moon = o;
    });
    if (D.sky) {
      const u = D.sky.mesh.material.uniforms;
      u.uTop.value.set(PAL.dawn3); u.uHorizon.value.set(PAL.dawn1);
      if (u.uGlow) u.uGlow.value.set(PAL.dawn2);
      if (u.uGround) u.uGround.value.set('#4A2E36');
    }
    if (D.stars) D.stars.visible = false;
    if (D.moon) D.moon.visible = false;
    if (L?.sky) {
      const sun = new THREE.Sprite(new THREE.SpriteMaterial({ map: this._sunTex(), color: new THREE.Color('#FFE2A8').multiplyScalar(2.2), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, fog: false }));
      sun.position.copy(new THREE.Vector3(1, 0.2, -0.18).normalize().multiplyScalar(120));
      sun.scale.setScalar(46);
      sun.renderOrder = -7;
      L.sky.add(sun);
      D.sun = sun;
    }
    // warm dawn ambient everywhere, a haze outside
    const warm = new THREE.Color('#FFD6A8'), warmG = new THREE.Color('#8A5A3A'), c = new THREE.Color();
    for (const [id, a] of Object.entries(L?.areas || {})) {
      D.areas[id] = { ambient: a.ambient, ambientPre: a.ambientPre, fog: a.fog };
      if (a.ambient) a.ambient = { sky: '#' + c.set(a.ambient.sky).lerp(warm, 0.55).getHexString(), ground: '#' + c.set(a.ambient.ground).lerp(warmG, 0.4).getHexString(), intensity: (a.ambient.intensity ?? 0.8) * 1.12 };
      if (id === 'yard') a.fog = { color: '#F2B08A', near: 30, far: 150 };
    }
    const lt = g.lights;
    if (lt?.key) { D.key = lt.key.color.clone(); lt.key.color.set('#FFC48E'); }
    if (lt?.fill) { D.fill = lt.fill.color.clone(); lt.fill.color.set('#FFB0C8'); }
    if (lt?.keyDir) { D.keyDir = lt.keyDir.clone(); lt.keyDir.set(0.85, 0.52, 0.2).normalize(); }
    // dawn light through every window: warm pools on the floor inside
    for (const w of Object.values(L?.windows || {})) {
      const ins = w.inside;
      if (!ins) continue;
      const pos = Array.isArray(ins) ? new THREE.Vector3(ins[0], 0.02, ins[2]) : new THREE.Vector3(ins.x, 0.02, ins.z);
      try { const h = g.fx?.lightPool?.(pos, 2.4, '#FFC48A', 0.5); if (h) D.pools.push(h); } catch { /* optional */ }
    }
    // clocks: 12:00, ticking from now
    try { L?.objects?.lobby_clock?.setMidnight?.(true); } catch { /* optional */ }
    const seen = new Set();
    L?.root?.traverse?.((o) => {
      if (o.name !== 'minute' || seen.has(o.parent)) return;
      const par = o.parent;
      const hour = par.getObjectByName('hour'), sec = par.getObjectByName('second');
      if (!hour) return;
      seen.add(par);
      D.clocks.push({ hour, minute: o, second: sec, rest: [hour.rotation.z, o.rotation.z, sec ? sec.rotation.z : 0] });
    });
    D.clockT = 0;
    this._dawn = D;
  }

  _sunTex() {
    const c = document.createElement('canvas');
    c.width = c.height = 128;
    const x = c.getContext('2d');
    const g = x.createRadialGradient(64, 64, 0, 64, 64, 64);
    g.addColorStop(0, 'rgba(255,255,240,1)'); g.addColorStop(0.18, 'rgba(255,240,200,1)'); g.addColorStop(0.22, 'rgba(255,200,140,0.55)'); g.addColorStop(1, 'rgba(255,160,110,0)');
    x.fillStyle = g;
    x.fillRect(0, 0, 128, 128);
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    return t;
  }

  _tickMorning(rdt) {
    const D = this._dawn;
    if (!D) return;
    D.clockT += rdt;
    const s = D.clockT, ang = (h, m, sec) => [((h % 12) + m / 60 + sec / 3600) / 12 * TAU, (m + sec / 60) / 60 * TAU, (sec / 60) * TAU];
    const m = Math.floor(s / 60), sec = Math.floor(s % 60) + Math.min(1, (s % 1) / 0.08) - 1 + 1;
    const [ah, am, as] = ang(12, m + Math.floor(sec / 60), sec % 60);
    for (const c of D.clocks) {
      c.hour.rotation.z = ah;
      c.minute.rotation.z = am;
      if (c.second) c.second.rotation.z = as;
    }
  }

  // Telly in the Morning Show: never signs off again, 13-point pulls (wraps the machine_telly interactable).
  _wrapTelly() {
    const g = this.game, telly = g.telly;
    const it = g.interact?.items?.get?.('machine_telly');
    if (!it || !telly || it._morning) return;
    const op = it.prompt, ou = it.use;
    it._morning = { prompt: op, use: ou };
    it.prompt = () => { const r = op ? op() : null; return r && r.cost !== undefined ? { ...r, cost: TELLY_MORNING_COST } : r; };
    it.use = () => {
      const can = typeof telly.canPull === 'function' ? telly.canPull() : false;
      if (!can || telly.seq) { ou?.(); return; }
      if (!g.economy?.spend?.(TELLY_MORNING_COST, 'telly')) return;
      telly.pull?.({ free: true, forced: this._rollTelly() });
    };
    telly.morning = true;
    this._tellyWrapped = it;
  }

  _rollTelly() {
    const g = this.game, telly = g.telly, W = T.telly.weights;
    const pool = [];
    let total = 0;
    for (const [id, w] of Object.entries(W)) {
      let ex = false;
      try { ex = typeof telly?._excluded === 'function' ? telly._excluded(id) : (id !== 'tiny_tele' && !!g.weapons?.has?.(id)); } catch { ex = false; }
      if (ex) continue;
      pool.push([id, w]);
      total += w;
    }
    let x = Math.random() * total;
    for (const [id, w] of pool) { if ((x -= w) < 0) return id; }
    return pool.length ? pool[pool.length - 1][0] : 'revolver_38';
  }

  _undoMorning() {
    const g = this.game, D = this._dawn;
    this.morning = false;
    if (this._tellyWrapped) {
      const it = this._tellyWrapped;
      if (it._morning) { it.prompt = it._morning.prompt; it.use = it._morning.use; delete it._morning; }
      if (g.telly) g.telly.morning = false;
      this._tellyWrapped = null;
    }
    if (!D) return;
    if (D.sky) {
      const u = D.sky.mesh.material.uniforms;
      u.uTop.value.copy(D.sky.top); u.uHorizon.value.copy(D.sky.hor);
      if (u.uGlow && D.sky.glow) u.uGlow.value.copy(D.sky.glow);
      if (u.uGround && D.sky.ground) u.uGround.value.copy(D.sky.ground);
    }
    if (D.stars) D.stars.visible = true;
    if (D.moon) D.moon.visible = true;
    if (D.sun && D.sun.parent) D.sun.parent.remove(D.sun);
    const areas = g.level?.areas || {};
    for (const [id, a] of Object.entries(D.areas)) if (areas[id]) { areas[id].ambient = a.ambient; areas[id].fog = a.fog; }
    const lt = g.lights;
    if (lt?.key && D.key) lt.key.color.copy(D.key);
    if (lt?.fill && D.fill) lt.fill.color.copy(D.fill);
    if (lt?.keyDir && D.keyDir) lt.keyDir.copy(D.keyDir);
    for (const p of D.pools) { try { p.remove?.(); } catch { /* optional */ } }
    for (const c of D.clocks) { c.hour.rotation.z = c.rest[0]; c.minute.rotation.z = c.rest[1]; if (c.second) c.second.rotation.z = c.rest[2]; }
    try { g.level?.objects?.lobby_clock?.setMidnight?.(false); } catch { /* optional */ }
    this._dawn = null;
  }

  // ------------------------------------------------------------------------------------------ debug
  debugPlay({ round } = {}) {
    const b = this.boss;
    if (this.active) return this.debugState();
    if (b && !b.active) b.debugStart({ round, skipIntro: true });
    if (b) b.debugKill();
    else this.play({ round });
    return this.debugState();
  }

  // Jump the timeline to t (every beat before t fires in order; continuous stages pick up at t).
  debugSeek(t) {
    if (!this.active) return null;
    const target = Math.max(this.t, t);
    const step = 0.05;
    const ts = this.timeScale;
    this.timeScale = 1;
    while (this.t < target - 1e-6 && this.stage !== 'card') this.update(Math.min(step, target - this.t));
    this.timeScale = ts;
    return this.debugState();
  }

  debugChoose(c) {
    if (this.stage !== 'card') this.debugSeek(E.card + 0.01);
    this._choose(c === 'n' ? 'n' : 'y');
    return this.debugState();
  }

  debugState() {
    return { active: this.active, stage: this.stage, t: +this.t.toFixed(2), seen: this.seen, morning: this.morning, hero: this.heroId || null,
      unlock: storeGet(KEY), room: !!this._room, portrait: !!this._portrait, card: !!(this._dom && this._dom.card.classList.contains('on')) };
  }
}
