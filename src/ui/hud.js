// DEAD AIR — in-game HUD (DOM/CSS). GDD §14 (minimal UI, NO hints), ARCHITECTURE §10.
// Laid out on a 1920x1080 reference stage scaled by innerHeight/1080 (the stage widens with the aspect ratio), with a
// 40 px safe margin. Only these elements exist: crosshair (cream dot + 4 ticks at the real spread cone, hitmarker X:
// white body / gold head / orange kill, tiny star on a headshot kill), telethon TOTE BOARD points (6 amber split-flap
// digits, "+50" labels, red flash on spend, gold during SWEEPS WEEK), TAPE-DECK ammo counter (magazine drums big,
// reserve small, low-magazine red pulse, no weapon names), equipment (4 vacuum tubes = grenades, 3 tiny orange TVs =
// Tiny Teles, grey when empty), WZTV badge ROUND DIAL (spins like a knob and clicks to the new number, "–" during the
// boss), active power-up icons with draining rings (blink the last 5 s), the DYMO-LABEL interact prompt ([E],
// [E] 950, [E] + plug, hold ring, red cost + shake when unaffordable; a round Xbox [X] while playing with the pad), the Uplink CHYRON, the Instant Replay bug and
// the rare flash. "Signal loss": render.post.damage (player.js eases 1 - HP/max; the HUD adds hit pulses), roll /
// static / chroma hit pulses, an off-screen hit shows a static TEAR on that screen edge, and the Big Shot whiteout.
//
// API (game.hud):
//   show() / hide()                  whole HUD (debug cameras)          suppress(key, on)  hide while any key is on
//   flash(text, style)               RARE big moments only              pointsPopup(delta) "+50" / red spend flash
//   hitmarker(head, kill)            X flash + tick                     setPrompt(obj|null) Dymo label (interact.js)
//        obj = { key:'E'|'X', cost?, plug?, hold?, progress 0..1, denied? }  ('X'/'A'/'B'/'Y' = Xbox glyph)
//   chyron(name, sub?)               Uplink lower third, 2.5 s          replayBug(on)  ◀◀ 13 bug (aliases setReplay(on),
//                                                                        showReplayBug(), hideReplayBug())
//   whiteout(seconds = 1.5, amount = 1)   Big Shot flash via render.post.whiteout, fading over `seconds`
//   glitch(amount = 0.5, seconds = 0.3)   generic signal hit (static + roll + chroma pulse)
//   tear(edge | Vector3)             static tear on 'left'|'right'|'top'|'bottom' (or the edge toward a world position)
//   setCrt(on)                       very light CRT vignette with rounded corners (pause-menu option)
//   reset(), update(dt) (real dt, every state)
// Automatic hookups (callers need nothing else): points:change (popups), points:denied (label shake), zombie:hit /
//   zombie:kill (hitmarkers; duplicates with hitmarker() in the same frame merge), player:hurt (pulse + tear),
//   weapon:fire (crosshair kick), round:start / machine:boss_start (dial), machine:commercial_start/_end (hidden),
//   machine:uplink_take (chyron fallback with the upgraded name if nobody called chyron()), replay events
//   ('perk:replay' {on}, 'replay:start' / 'replay:end'), state (visible only while playing / down).
// Sounds: ticks, flips, prompt click and bzzt are voiced by audio.js's event hookups; the HUD plays ui_round_dial and
//   the tick for hitmarker() calls without a zombie event (identical plays within 30 ms merge).
// Exports FlipBoard (split-flap digits) and Roller (tape-counter drums) for menu.js.

import * as THREE from 'three';
import { FONTS } from './fonts.js';
import { T, PAL } from '../core/config.js';

const REF_H = 1080;
const M = 40; // safe margin (reference px)
const WORLD = new Set(['playing', 'down']);
const PU_TOTAL = { one_take: T.drops.timed, sweeps_week: T.drops.timed, please_stand_by: T.drops.freeze };
const PU_GLOW = { cancelled: '#E3662B', full_reel: '#FFC23A', one_take: '#FF3B30', sweeps_week: '#FF4FA0', gaffer_tape: '#DDE3EA', please_stand_by: '#EDEDED' };
const HIT_COL = ['#FFFFFF', '#FFFFFF', '#FFD23A', '#FF8A2A', '#FF8A2A'];
const RING_R = 27;
const PAD_KEYS = new Set(['A', 'B', 'X', 'Y']); // Xbox face buttons the prompt can show
const RING_C = 2 * Math.PI * RING_R;
const PU_R = 26;
const PU_C = 2 * Math.PI * PU_R;

const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const easeOutBack = (x, k = 1.7) => 1 + (k + 1) * Math.pow(x - 1, 3) + k * Math.pow(x - 1, 2);
const easeOut = (x) => 1 - (1 - x) * (1 - x);
const easeIn = (x) => x * x;
const _v = new THREE.Vector3();
const _q = new THREE.Quaternion();

let cssDone = false;
function injectCss() {
  if (cssDone) return;
  cssDone = true;
  const s = document.createElement('style');
  s.id = 'deadair-hud-css';
  s.textContent = CSS;
  document.head.appendChild(s);
}

// ------------------------------------------------------------------------------------------------ split-flap digits
// FlipBoard(parent, count, { cls, onFlip }) builds `count` split-flap cards inside parent. set(str) aims each card at
// str[i] (' ' = blank); update(dt) animates: every card steps one flap at a time toward its target (0..9 in order,
// blank flips straight), faster when it has far to go. set(str, true) jumps without animating.
export class FlipBoard {
  constructor(parent, count, opts = {}) {
    this.cards = [];
    this.onFlip = opts.onFlip || null;
    this.speed = opts.speed || 1;
    for (let i = 0; i < count; i++) {
      const el = document.createElement('div');
      el.className = `fd ${opts.cls || ''}`;
      el.innerHTML = '<div class="fh ft"><b></b></div><div class="fh fb"><b></b></div><div class="fl ft"><b></b></div><div class="fl fb"><b></b></div>';
      parent.appendChild(el);
      const [top, bot, leafT, leafB] = el.children;
      const c = { el, top: top.firstChild, bot: bot.firstChild, leafT, leafB, leafTt: leafT.firstChild, leafBt: leafB.firstChild,
        cur: ' ', next: ' ', target: ' ', t: -1, dur: 0.08 };
      leafT.style.visibility = leafB.style.visibility = 'hidden';
      this.cards.push(c);
    }
  }

  set(str, instant = false) {
    for (let i = 0; i < this.cards.length; i++) {
      const c = this.cards[i];
      const ch = str[i] ?? ' ';
      c.target = ch;
      if (instant) {
        c.cur = c.next = ch;
        c.t = -1;
        c.top.textContent = c.bot.textContent = ch.trim();
        c.leafT.style.visibility = c.leafB.style.visibility = 'hidden';
      }
    }
  }

  get busy() { return this.cards.some((c) => c.t >= 0 || c.cur !== c.target); }

  _stepOf(cur, target) {
    if (cur === target) return null;
    if (target === ' ' || cur === ' ' || !/\d/.test(cur) || !/\d/.test(target)) return target;
    return String((Number(cur) + 1) % 10);
  }

  _steps(cur, target) {
    if (cur === target) return 0;
    if (target === ' ' || cur === ' ' || !/\d/.test(cur) || !/\d/.test(target)) return 1;
    return (Number(target) - Number(cur) + 10) % 10;
  }

  update(dt) {
    for (let i = 0; i < this.cards.length; i++) {
      const c = this.cards[i];
      if (c.t < 0) {
        const nx = this._stepOf(c.cur, c.target);
        if (nx === null) continue;
        c.next = nx;
        c.dur = clamp(0.34 / Math.max(1, this._steps(c.cur, c.target)), 0.036, 0.085) / this.speed;
        c.t = 0;
        c.top.textContent = nx.trim();
        c.bot.textContent = c.cur.trim();
        c.leafTt.textContent = c.cur.trim();
        c.leafBt.textContent = nx.trim();
        c.leafT.style.visibility = 'visible';
        c.leafB.style.visibility = 'hidden';
        c.leafT.style.transform = 'rotateX(0deg)';
        c.leafB.style.transform = 'rotateX(90deg)';
        c.leafT.style.filter = '';
        if (this.onFlip) this.onFlip(i);
      }
      c.t += dt;
      const half = c.dur * 0.5;
      if (c.t < half) {
        const p = easeIn(c.t / half);
        c.leafT.style.transform = `rotateX(${-90 * p}deg)`;
        c.leafT.style.filter = `brightness(${1 - 0.45 * p})`;
      } else if (c.t < c.dur) {
        c.leafT.style.visibility = 'hidden';
        c.leafB.style.visibility = 'visible';
        const p = (c.t - half) / half;
        c.leafB.style.transform = `rotateX(${90 * (1 - easeOut(p))}deg)`;
      } else {
        c.cur = c.next;
        c.bot.textContent = c.cur.trim();
        c.leafB.style.visibility = 'hidden';
        c.t = -1;
      }
    }
  }
}

// ------------------------------------------------------------------------------------------------ tape-counter drums
// Roller(parent, count, { cls }) = odometer drums; set(n) rolls every drum to its digit (leading zeros dimmed).
export class Roller {
  constructor(parent, count, opts = {}) {
    this.drums = [];
    this.value = -1;
    const strip = Array.from({ length: 10 }, (_, i) => `<i>${i}</i>`).join('');
    for (let i = 0; i < count; i++) {
      const el = document.createElement('div');
      el.className = `rd ${opts.cls || ''}`;
      el.innerHTML = `<div class="rs">${strip}</div>`;
      parent.appendChild(el);
      this.drums.push({ el, strip: el.firstChild, d: -1 });
    }
  }

  set(n) {
    n = Math.max(0, Math.floor(n));
    if (n === this.value) return;
    this.value = n;
    const s = String(Math.min(n, 10 ** this.drums.length - 1)).padStart(this.drums.length, '0');
    const lead = s.length - String(n).length;
    for (let i = 0; i < this.drums.length; i++) {
      const dr = this.drums[i], d = Number(s[i]);
      if (d !== dr.d) { dr.d = d; dr.strip.style.transform = `translateY(${-d * 10}%)`; }
      dr.el.classList.toggle('lead', i < lead);
    }
  }
}

// ------------------------------------------------------------------------------------------------ post knob mixing
// Several systems may write the same render.post knob. A Knob remembers what the HUD wrote last frame: a different
// value means someone else wrote it (their value becomes `ext`), and the HUD combines its own contribution with it.
class Knob {
  constructor(name) { this.name = name; this.ext = 0; this.wrote = null; this.still = 0; }
  apply(post, mine, mode, dt) {
    const cur = post[this.name];
    if (this.wrote === null || cur !== this.wrote) { this.ext = cur; this.still = 0; } else this.still += dt;
    let out = mode === 'add' ? this.ext + mine : Math.max(this.ext, mine);
    if (this.name === 'damage') out = Math.min(1, out);
    post[this.name] = out;
    this.wrote = out;
  }
  release(post) {
    if (this.wrote !== null && post[this.name] === this.wrote) post[this.name] = this.ext;
    this.wrote = null;
  }
}

// ------------------------------------------------------------------------------------------------ icons
const PLUG_SVG = `<svg class="plug" viewBox="0 0 64 40"><path d="M2 30c8 0 8-10 16-10h6" fill="none" stroke="#F4F1E8" stroke-width="4" stroke-linecap="round"/>
<rect x="22" y="9" width="22" height="22" rx="6" fill="#F4F1E8"/><rect x="26" y="13" width="14" height="4" rx="2" fill="#B8B2A8"/>
<path d="M44 14h14M44 26h14" stroke="#F4F1E8" stroke-width="4.5" stroke-linecap="round"/></svg>`;

const TUBE_SVG = `<svg viewBox="0 0 22 40"><path class="gl" d="M4 30V11a7 7 0 0 1 14 0v19z"/><path class="fi" d="M8 27V15l3-3 3 3v12"/>
<rect class="ba" x="3" y="29" width="16" height="7" rx="2"/><path class="pn" d="M7 36v3M11 36v3M15 36v3"/><path class="hl" d="M7 12v12"/></svg>`;

const TELE_SVG = `<svg viewBox="0 0 30 28"><path class="an" d="M15 9l-6-7M15 9l6-7"/><rect class="ca" x="2" y="8" width="26" height="18" rx="5"/>
<rect class="sc" x="5.5" y="11" width="14" height="11" rx="3"/><circle class="kn" cx="23.5" cy="14" r="1.8"/><circle class="kn" cx="23.5" cy="19.5" r="1.8"/></svg>`;

const PU_ICON = {
  one_take: `<rect x="8" y="20" width="32" height="20" rx="3" fill="#2A2230"/><path d="M8 20h32" stroke="#F4F1E8" stroke-width="1.5"/>
    <g transform="rotate(-18 9 19)"><rect x="7" y="12" width="33" height="8" rx="2" fill="#F4F1E8"/><path d="M12 12l5 8M20 12l5 8M28 12l5 8M36 12l4 6" stroke="#2A2230" stroke-width="3"/></g>
    <circle cx="9" cy="19" r="2.2" fill="#FF3B30"/><path d="M13 27h14M13 33h9" stroke="#F4F1E8" stroke-width="2" stroke-linecap="round"/>`,
  sweeps_week: `<path d="M24 12l-6-7M24 12l6-7" stroke="#F4F1E8" stroke-width="2" stroke-linecap="round"/><rect x="7" y="11" width="34" height="27" rx="7" fill="#FF4FA0"/>
    <rect x="11" y="15" width="21" height="19" rx="4" fill="#2A1830"/><text x="21.5" y="30.5" text-anchor="middle" font-size="12" font-family="Titan One, Arial Black" fill="#FFE14D">×2</text>
    <circle cx="36.5" cy="20" r="2" fill="#FFE14D"/><circle cx="36.5" cy="28" r="2" fill="#2A1830"/>`,
  please_stand_by: `<path d="M24 12l-6-7M24 12l6-7" stroke="#F4F1E8" stroke-width="2" stroke-linecap="round"/><rect x="7" y="11" width="34" height="27" rx="7" fill="#EDEDED"/>
    <rect x="11" y="15" width="21" height="19" rx="4" fill="#5A5A6A"/><circle cx="21.5" cy="24.5" r="7" fill="#9ED8FF" stroke="#F4F1E8" stroke-width="1.5"/>
    <path d="M14.5 21h14" stroke="#F4E03A" stroke-width="3"/><circle cx="36.5" cy="20" r="2" fill="#3A58E4"/><circle cx="36.5" cy="28" r="2" fill="#E4473A"/>`,
  full_reel: `<circle cx="24" cy="24" r="15" fill="#C8CED8" stroke="#FFC23A" stroke-width="2"/><circle cx="24" cy="24" r="4" fill="#2A2230"/>
    <circle cx="24" cy="15" r="4" fill="#2A2230"/><circle cx="31.8" cy="28.5" r="4" fill="#2A2230"/><circle cx="16.2" cy="28.5" r="4" fill="#2A2230"/>`,
  cancelled: `<rect x="15" y="8" width="18" height="16" rx="5" fill="#8A4A2A"/><rect x="10" y="24" width="28" height="7" rx="2" fill="#E3662B"/>
    <path d="M14 35l20 6M34 35l-20 6" stroke="#FF3B30" stroke-width="4" stroke-linecap="round"/>`,
  gaffer_tape: `<circle cx="24" cy="24" r="15" fill="#DDE3EA"/><circle cx="24" cy="24" r="7" fill="#2A2230"/><path d="M36 30l8 6" stroke="#DDE3EA" stroke-width="7"/>`,
};

const STAR_SVG = '<svg viewBox="0 0 40 40"><path d="M20 2l5 12 13 1-10 8 3 13-11-7-11 7 3-13-10-8 13-1z" fill="#FFD23A" stroke="#7A3A12" stroke-width="2.5" stroke-linejoin="round"/></svg>';
const RB_SVG = '<svg viewBox="0 0 64 36"><path d="M30 4L4 18l26 14z M60 4L34 18l26 14z" fill="#FFE14D" stroke="#5A3A10" stroke-width="3" stroke-linejoin="round"/></svg>';

// ------------------------------------------------------------------------------------------------ CSS
const CSS = `
.dh{position:fixed;inset:0;pointer-events:none;user-select:none;z-index:10;overflow:hidden;font-family:${FONTS.hud};color:${PAL.cream}}
.dh.off .dh-s,.dh.off .dh-tear{opacity:0;visibility:hidden}
.dh-s{position:absolute;left:0;top:0;height:${REF_H}px;transform-origin:0 0;transition:opacity .18s}
.dh-tear{position:absolute;inset:0;width:100%;height:100%;image-rendering:pixelated;display:none}
.dh-crt{position:absolute;inset:0;border-radius:3.2vh;box-shadow:inset 0 0 14vh 2vh rgba(12,6,22,.42),0 0 0 6vh rgba(8,4,14,.55);display:none}
.dh-crt.on{display:block}
.dh-crt::after{content:'';position:absolute;inset:0;background:repeating-linear-gradient(0deg,rgba(0,0,0,.05) 0 1px,transparent 1px 3px);border-radius:inherit}

/* crosshair */
.dh .xh{position:absolute;left:50%;top:50%;width:0;height:0;transition:opacity .15s}
.dh .xh.dim{opacity:.3}
.dh .dot{position:absolute;width:5px;height:5px;left:-2.5px;top:-2.5px;border-radius:50%;background:${PAL.cream};box-shadow:0 0 0 1.5px rgba(40,22,48,.75)}
.dh .tk{position:absolute;background:${PAL.cream};border-radius:2px;box-shadow:0 0 0 1.5px rgba(40,22,48,.7)}
.dh .tk.v{width:3px;height:11px;left:-1.5px}
.dh .tk.h{height:3px;width:11px;top:-1.5px}
.dh .hm{position:absolute;left:0;top:0;width:0;height:0;opacity:0}
.dh .hm i{position:absolute;width:4px;height:13px;left:-2px;top:-6.5px;border-radius:2px;background:var(--hc,#fff);box-shadow:0 0 0 1.5px rgba(40,18,24,.7)}
.dh .star{position:absolute;left:-15px;top:-62px;width:30px;height:30px;opacity:0}
.dh .star svg{width:100%;height:100%;filter:drop-shadow(0 2px 0 rgba(60,20,10,.6))}

/* dymo prompt */
.dh .pr{position:absolute;left:50%;top:calc(50% + 90px);height:0;width:0}
.dh .dy{position:absolute;left:0;top:0;display:flex;align-items:center;gap:14px;height:54px;padding:0 22px 0 16px;white-space:nowrap;
  transform-origin:50% 50%;opacity:0;
  background:linear-gradient(180deg,#3A3A40 0%,#1C1C21 16%,#121216 55%,#1E1E24 88%,#34343C 100%);
  clip-path:polygon(0 8%,1.2% 0,98.8% 0,100% 9%,99.2% 22%,100% 36%,99.2% 50%,100% 64%,99.2% 78%,100% 91%,98.8% 100%,1.2% 100%,0 92%,.8% 78%,0 64%,.8% 50%,0 36%,.8% 22%);
  filter:drop-shadow(0 5px 6px rgba(0,0,0,.45))}
.dh .dy::before{content:'';position:absolute;left:0;right:0;top:5px;height:5px;background:linear-gradient(90deg,transparent,rgba(255,255,255,.14) 20%,rgba(255,255,255,.06) 70%,transparent)}
.dh .dy .emb{font-size:34px;letter-spacing:.07em;color:#F2F0EA;line-height:1;
  text-shadow:0 -1px 0 rgba(0,0,0,.9),0 1px 0 rgba(255,255,255,.35),0 2px 3px rgba(0,0,0,.5)}
.dh .dy .emb span{display:inline-block}
.dh .dy .key{position:relative;display:flex;align-items:center;justify-content:center;width:40px;height:40px;border-radius:9px;
  box-shadow:inset 0 0 0 3px rgba(242,240,234,.9),inset 0 3px 0 3px rgba(0,0,0,.35),0 1px 0 rgba(255,255,255,.3);font-size:26px}
.dh .dy .ring{position:absolute;left:-12px;top:-12px;width:64px;height:64px;transform:rotate(-90deg);display:none}
/* Xbox face button (gamepad is the last input device): a round embossed button, the letter in the pad's colour */
.dh .dy .key.pad{border-radius:50%;font-size:25px;background:radial-gradient(circle at 42% 34%,#34343C,#18181D 70%);
  box-shadow:inset 0 0 0 3px rgba(242,240,234,.9),inset 0 3px 0 3px rgba(0,0,0,.35),0 1px 0 rgba(255,255,255,.3)}
.dh .dy .key.pad span{transform:translateY(1px)}
.dh .dy .key.pad-x span{color:#6FA8FF;text-shadow:0 -1px 0 rgba(0,0,0,.9),0 0 8px rgba(80,150,255,.55)}
.dh .dy .key.pad-a span{color:#7EDB5A;text-shadow:0 -1px 0 rgba(0,0,0,.9),0 0 8px rgba(110,220,80,.5)}
.dh .dy .key.pad-b span{color:#FF6A5C;text-shadow:0 -1px 0 rgba(0,0,0,.9),0 0 8px rgba(255,90,70,.5)}
.dh .dy .key.pad-y span{color:#FFD24A;text-shadow:0 -1px 0 rgba(0,0,0,.9),0 0 8px rgba(255,210,70,.5)}
.dh .dy.hold .ring{display:block}
.dh .dy .cost{min-width:0}
.dh .dy .cost.den{color:#FF5A46;text-shadow:0 -1px 0 rgba(0,0,0,.9),0 1px 0 rgba(255,160,140,.35),0 0 10px rgba(255,60,40,.45)}
.dh .dy .plug{width:58px;height:36px;display:none;filter:drop-shadow(0 -1px 0 rgba(0,0,0,.9)) drop-shadow(0 1px 0 rgba(255,255,255,.3))}
.dh .dy.plugged .plug{display:block}

/* tote board */
.dh .tote{position:absolute;right:${M}px;bottom:${M + 78}px;width:200px;height:52px;display:flex;align-items:center;justify-content:center;gap:4px;
  border-radius:13px;background:linear-gradient(180deg,#6A4428,#4A2E1A 45%,#3A2214);
  box-shadow:inset 0 2px 0 rgba(255,220,170,.18),inset 0 -3px 0 rgba(0,0,0,.35),0 5px 12px rgba(0,0,0,.45),0 0 0 2px #2A170E}
.dh .tote::before,.dh .tote::after{content:'';position:absolute;top:50%;width:6px;height:6px;margin-top:-3px;border-radius:50%;background:#C8963C;box-shadow:inset 0 -1px 0 rgba(0,0,0,.4)}
.dh .tote::before{left:6px}.dh .tote::after{right:6px}
.fd{position:relative;perspective:220px}
.fd .fh,.fd .fl{position:absolute;left:0;width:100%;height:50%;overflow:hidden}
.fd .ft{top:0;transform-origin:50% 100%}
.fd .fb{top:50%;transform-origin:50% 0}
.fd .fl{backface-visibility:hidden;will-change:transform}
.fd b{position:absolute;left:0;width:100%;height:200%;display:flex;align-items:center;justify-content:center;line-height:1;font-weight:400}
.fd .ft b{top:0}.fd .fb b{top:-100%}
.dh .tote .fd{width:26px;height:40px}
.dh .tote .fd .fh,.dh .tote .fd .fl{background:#22140D}
.dh .tote .fd .ft{border-radius:5px 5px 0 0;background:linear-gradient(#2E1C12,#22140D)}
.dh .tote .fd .fb{border-radius:0 0 5px 5px;background:linear-gradient(#1A0F09,#22140D);box-shadow:inset 0 1px 0 rgba(0,0,0,.8)}
.dh .tote .fd b{font-size:31px;color:#FFB347;text-shadow:0 0 7px rgba(255,150,40,.75)}
.dh .tote.gold .fd b{color:#FFE66A;text-shadow:0 0 9px rgba(255,210,60,.95),0 0 2px #fff}
.dh .tote.spend .fd b{color:#FF4A3A;text-shadow:0 0 9px rgba(255,50,30,.9)}
.dh .pops{position:absolute;right:${M + 60}px;bottom:${M + 136}px;width:0;height:0}
.dh .pop{position:absolute;right:0;bottom:0;font-size:30px;color:#FFD23A;white-space:nowrap;
  text-shadow:0 2px 0 #6A3A12,0 -1px 0 #6A3A12,2px 0 0 #6A3A12,-2px 0 0 #6A3A12,0 4px 6px rgba(0,0,0,.4);animation:dhpop .6s cubic-bezier(.2,.9,.3,1) forwards}
.dh .pop.gold{color:#FFF1A0}
@keyframes dhpop{0%{transform:translateY(8px) scale(.6);opacity:0}18%{transform:translateY(-6px) scale(1.12);opacity:1}
  65%{opacity:1}100%{transform:translateY(-58px) scale(.95);opacity:0}}

/* tape counter */
.dh .ammo{position:absolute;right:${M}px;bottom:${M}px;height:64px;display:flex;align-items:center;gap:0;padding:0 10px;border-radius:12px;
  background:linear-gradient(180deg,#E8ECF2,#A8B0BC 45%,#8A929E 55%,#C8D0DA);box-shadow:0 5px 12px rgba(0,0,0,.45),inset 0 1px 0 #fff,inset 0 -2px 0 rgba(0,0,0,.25)}
.dh .ammo.none{display:none}
.dh .ammo .win{display:flex;align-items:center;height:48px;padding:0 5px;background:#0A0A0E;border-radius:6px;box-shadow:inset 0 2px 5px rgba(0,0,0,.9),0 1px 0 rgba(255,255,255,.6)}
.dh .ammo .res{height:34px;margin-left:8px}
.dh .ammo .sep{width:4px;height:40px;margin-left:8px;border-radius:2px;background:linear-gradient(90deg,#6A727E,#F0F4F8,#6A727E)}
.rd{position:relative;overflow:hidden;font-family:${FONTS.tape};color:#F6F6F2;background:linear-gradient(180deg,#000 0%,#26262C 22%,#34343A 50%,#26262C 78%,#000 100%)}
.rd+.rd{margin-left:2px}
.rd .rs{position:absolute;left:0;top:0;width:100%;height:1000%;transition:transform .12s cubic-bezier(.3,1.4,.6,1)}
.rd .rs i{display:flex;height:10%;align-items:center;justify-content:center;font-style:normal;line-height:1}
.rd.lead{color:#5A5A64}
.dh .ammo .mag .rd{width:30px;height:48px;font-size:56px}
.dh .ammo .res .rd{width:19px;height:34px;font-size:34px;color:#C8C4D0}
.dh .ammo .res .rd.lead{color:#4A4A54}
.dh .ammo.low .mag .rd:not(.lead){color:#FF4A3A;animation:dhlow .45s ease-in-out infinite alternate}
@keyframes dhlow{to{color:#7A1A14}}

/* equipment */
.dh .eq{position:absolute;right:${M + 222}px;bottom:${M + 4}px;display:flex;flex-direction:column;align-items:flex-end;gap:6px}
.dh .eq .row{display:flex;gap:5px}
.dh .eq .row.teles.none{display:none}
.dh .eq .tube{width:20px;height:36px}
.dh .eq .tube svg,.dh .eq .tele svg{width:100%;height:100%;overflow:visible;filter:drop-shadow(0 2px 2px rgba(0,0,0,.5))}
.dh .eq .gl{fill:rgba(200,230,255,.35);stroke:#F4F1E8;stroke-width:1.6}
.dh .eq .fi{fill:none;stroke:#FFB347;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}
.dh .eq .ba{fill:#2A2230;stroke:#F4F1E8;stroke-width:1.2}
.dh .eq .pn{stroke:#C8963C;stroke-width:1.4}
.dh .eq .hl{stroke:rgba(255,255,255,.7);stroke-width:1.4;stroke-linecap:round}
.dh .eq .tube.on .gl{fill:rgba(255,190,110,.45)}
.dh .eq .tube.on .fi{stroke:#FFE08A;filter:drop-shadow(0 0 3px #FF9A2A)}
.dh .eq .tube.off .gl{fill:rgba(120,120,130,.25);stroke:#8A8690}
.dh .eq .tube.off .fi{stroke:#6A6670}
.dh .eq .tube.off .ba{stroke:#8A8690}
.dh .eq .tele{width:28px;height:26px}
.dh .eq .an{stroke:#F4F1E8;stroke-width:1.6;stroke-linecap:round}
.dh .eq .ca{fill:#E3662B;stroke:#F4F1E8;stroke-width:1.2}
.dh .eq .sc{fill:#7FE7FF}
.dh .eq .kn{fill:#F4F1E8}
.dh .eq .tele.off .ca{fill:#6A6670;stroke:#9A96A0}
.dh .eq .tele.off .sc{fill:#3A3A44}

/* round badge dial */
.dh .dial{position:absolute;left:${M}px;bottom:${M}px;width:84px;height:84px}
.dh .dial .knob{position:absolute;inset:0;border-radius:50%;
  background:radial-gradient(circle at 50% 50%,transparent 57%,#9A1E1E 58%,#E23B3B 61%,#FF6A5A 66%,#E23B3B 72%,#8A1A1A 74%,transparent 75%),
  repeating-conic-gradient(from 0deg,#C42A2A 0deg 7deg,#8A1616 7deg 13.85deg);
  box-shadow:0 5px 12px rgba(0,0,0,.5),inset 0 2px 0 rgba(255,200,190,.35)}
.dh .dial .knob::after{content:'';position:absolute;left:50%;top:3px;width:6px;height:11px;margin-left:-3px;border-radius:3px;background:#F4F1E8;box-shadow:0 1px 0 rgba(0,0,0,.4)}
.dh .dial .disc{position:absolute;inset:14px;border-radius:50%;background:radial-gradient(circle at 36% 30%,#6A92FA,#2F5BD3 55%,#1C3690);
  box-shadow:inset 0 -3px 0 rgba(0,0,0,.3),inset 0 2px 0 rgba(255,255,255,.3),0 0 0 2px #F4F1E8}
.dh .dial .num{position:absolute;inset:14px;display:flex;align-items:center;justify-content:center;font-size:36px;color:#fff;line-height:1;
  text-shadow:0 2px 0 #14246A,0 0 1px #14246A}
.dh .dial .num.small{font-size:28px}

/* chyron */
.dh .chy{position:absolute;left:${M - 6}px;bottom:${M + 108}px;height:92px;width:620px;transform:translateX(-120%);opacity:0}
.dh .chy .bar{position:absolute;left:54px;top:10px;right:0;height:56px;border-radius:0 28px 28px 0;
  background:linear-gradient(180deg,#F59A48,#D9602B 50%,#A8401E);box-shadow:0 4px 10px rgba(30,10,6,.45),inset 0 3px 0 rgba(255,255,255,.28)}
.dh .chy .bar::after{content:'';position:absolute;left:30px;right:34px;bottom:8px;height:3px;background:#E8A92E;box-shadow:0 5px 0 -1px #D9A520}
.dh .chy .sub{position:absolute;left:84px;top:62px;height:26px;padding:0 22px 0 16px;border-radius:0 0 14px 14px;line-height:26px;
  background:linear-gradient(#6A3A22,#4A2616);font-family:${FONTS.sign};font-size:15px;letter-spacing:.06em;color:#FFD27A;display:none}
.dh .chy .sub.on{display:block}
.dh .chy .badge{position:absolute;left:0;top:0;width:80px;height:80px;border-radius:50%;background:radial-gradient(circle at 40% 35%,#8A5A36,#5A3A22);
  box-shadow:0 0 0 4px #E8A92E,0 4px 10px rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center}
.dh .chy .badge i{width:56px;height:56px;border-radius:50%;background:#F4F1E8;box-shadow:inset 0 0 0 5px #E23B3B;display:flex;align-items:center;justify-content:center;
  font-style:normal;font-size:26px;color:#2F5BD3;text-shadow:0 1px 0 #14246A}
.dh .chy .name{position:absolute;left:100px;top:14px;height:50px;display:flex;align-items:center;font-family:${FONTS.logo};font-size:38px;color:#FFFBEA;white-space:nowrap;
  text-shadow:0 3px 0 #5A2210,2px 0 0 #5A2210,-2px 0 0 #5A2210,0 -2px 0 #5A2210,2px 2px 0 #5A2210,-2px 2px 0 #5A2210}
.dh .chy .shine{position:absolute;left:54px;top:10px;right:0;height:56px;border-radius:0 28px 28px 0;overflow:hidden}
.dh .chy .shine::before{content:'';position:absolute;top:-20px;bottom:-20px;width:60px;left:-80px;background:linear-gradient(90deg,transparent,rgba(255,255,255,.55),transparent);transform:skewX(-20deg)}
.dh .chy.go .shine::before{animation:dhshine .9s .25s ease-out}
@keyframes dhshine{to{left:110%}}

/* power-ups */
.dh .pu{position:absolute;left:50%;bottom:${M}px;display:flex;gap:14px;transform:translateX(-50%)}
.dh .pu .ic{position:relative;width:58px;height:58px;transition:transform .2s cubic-bezier(.3,1.6,.5,1),opacity .2s}
.dh .pu .ic.in{transform:scale(0);opacity:0}
.dh .pu .ic svg.ico{position:absolute;left:5px;top:5px;width:48px;height:48px;filter:drop-shadow(0 2px 2px rgba(0,0,0,.55))}
.dh .pu .ic svg.rg{position:absolute;inset:0;width:58px;height:58px;transform:rotate(-90deg)}
.dh .pu .ic.blink svg.ico{animation:dhblink .25s steps(2) infinite}
@keyframes dhblink{50%{opacity:.25}}

/* replay bug */
.dh .rb{position:absolute;left:${M}px;top:${M}px;display:none;align-items:center;gap:10px}
.dh .rb.on{display:flex;animation:dhblink .5s steps(2) infinite}
.dh .rb svg{width:72px;height:40px;filter:drop-shadow(0 3px 0 rgba(60,30,0,.45))}
.dh .rb i{width:44px;height:44px;border-radius:50%;background:#F4F1E8;box-shadow:inset 0 0 0 5px #E23B3B,0 3px 0 rgba(0,0,0,.35);display:flex;align-items:center;justify-content:center;
  font-style:normal;font-size:21px;color:#2F5BD3}

/* flash */
.dh .fl{position:absolute;left:50%;top:28%;font-family:${FONTS.logo};font-size:104px;color:#FFE14D;white-space:nowrap;opacity:0;
  text-shadow:0 6px 0 #B5472A,0 12px 18px rgba(0,0,0,.5);transform:translate(-50%,-50%)}
`;

// ------------------------------------------------------------------------------------------------ Hud
export class Hud {
  constructor(game) {
    this.game = game;
    this.visible = false;
    this._supp = new Set();
    this._shown = { points: -1, gold: null, mag: -1, res: -1, low: null, noAmmo: null, gren: -1, tele: -1, teleRow: null, spread: -1, dim: null, want: null };
    this._prompt = { on: false, key: 'E', cost: undefined, denied: null, plug: null, hold: null, prog: -1, t: 0 };
    this._hm = 0; this._hmT = -1; this._starT = -1; this._hmLevel = 0;
    this._kick = 0;
    this._spendT = 0;
    this._pops = [];
    this._dedupe = new Map();
    this._frame = -1;
    this._flashT = -1;
    this._chy = { t: -1, name: '', lastAt: -1e9 };
    this._dial = { shown: null, target: null, t: -1, from: 0, spin: 0 };
    this._pu = new Map();
    this._hadTele = false;
    this._pulse = { static: 0, roll: 0, chroma: 0, damage: 0 };
    this._white = { t: -1, dur: 1.5, amount: 1 };
    this._knobs = { damage: new Knob('damage'), static: new Knob('static'), roll: new Knob('roll'), chroma: new Knob('chroma'), whiteout: new Knob('whiteout') };
    this._knobsOn = false;
    this._tear = { t: -1, edge: 'left', acc: 0, seed: 0 };
    this._shakeT = 0;
    this._replay = false;
    injectCss();
    this._build();
    this._onResize = () => this._resize();
    addEventListener('resize', this._onResize);
    this._resize();
  }

  // -------------------------------------------------------------------------------------------- DOM
  _build() {
    const root = document.createElement('div');
    root.className = 'dh hud off'; // 'hud' / 'prompt': the selectors engine_smoke.cjs reads
    root.innerHTML = `<canvas class="dh-tear" width="160" height="90"></canvas><div class="dh-crt"></div><div class="dh-s">
      <div class="xh"><div class="dot"></div><div class="tk v"></div><div class="tk v"></div><div class="tk h"></div><div class="tk h"></div>
        <div class="hm"><i></i><i></i><i></i><i></i></div><div class="star">${STAR_SVG}</div></div>
      <div class="pr"><div class="dy prompt"><div class="key emb"><span>E</span><svg class="ring" viewBox="0 0 64 64"><circle cx="32" cy="32" r="${RING_R}" fill="none"
        stroke="rgba(255,255,255,.14)" stroke-width="5"/><circle class="rgv" cx="32" cy="32" r="${RING_R}" fill="none" stroke="#FFD23A" stroke-width="5" stroke-linecap="round"
        stroke-dasharray="${RING_C}" stroke-dashoffset="${RING_C}"/></svg></div><div class="cost emb"></div>${PLUG_SVG}</div></div>
      <div class="pops"></div>
      <div class="tote"></div>
      <div class="ammo none"><div class="win mag"></div><div class="sep"></div><div class="win res"></div></div>
      <div class="eq"><div class="row teles none"></div><div class="row tubes"></div></div>
      <div class="dial"><div class="knob"></div><div class="disc"></div><div class="num"></div></div>
      <div class="chy"><div class="bar"></div><div class="shine"></div><div class="sub"></div><div class="badge"><i>13</i></div><div class="name"></div></div>
      <div class="pu"></div>
      <div class="rb">${RB_SVG}<i>13</i></div>
      <div class="fl"></div>
    </div>`;
    document.body.appendChild(root);
    const q = (s) => root.querySelector(s);
    this.root = root;
    this.stage = q('.dh-s');
    const el = this.el = {
      xh: q('.xh'), ticks: [...root.querySelectorAll('.tk')], hm: q('.hm'), hmBars: [...root.querySelectorAll('.hm i')], star: q('.star'),
      pr: q('.pr'), dy: q('.dy'), key: q('.key'), keyTxt: q('.key span'), ring: q('.rgv'), cost: q('.cost'),
      pops: q('.pops'), tote: q('.tote'), ammo: q('.ammo'), mag: q('.ammo .mag'), res: q('.ammo .res'),
      tubes: q('.row.tubes'), teles: q('.row.teles'), dial: q('.dial'), knob: q('.dial .knob'), num: q('.dial .num'),
      chy: q('.chy'), chyName: q('.chy .name'), chySub: q('.chy .sub'), pu: q('.pu'), rb: q('.rb'), fl: q('.fl'),
      tear: q('.dh-tear'), crt: q('.dh-crt'),
    };
    this.tote = new FlipBoard(el.tote, 6, {});
    this.magDrums = new Roller(el.mag, 3);
    this.resDrums = new Roller(el.res, 3);
    this.tubes = [];
    for (let i = 0; i < T.player.grenadesMax; i++) {
      const d = document.createElement('div');
      d.className = 'tube off';
      d.innerHTML = TUBE_SVG;
      el.tubes.appendChild(d);
      this.tubes.push(d);
    }
    this.teles = [];
    for (let i = 0; i < T.player.teleMax; i++) {
      const d = document.createElement('div');
      d.className = 'tele off';
      d.innerHTML = TELE_SVG;
      el.teles.appendChild(d);
      this.teles.push(d);
    }
    // Hitmarker bars: 4 diagonal strokes around the center.
    el.hmBars.forEach((b, i) => { b.dataset.a = String(45 + i * 90); });
    this._tearCtx = el.tear.getContext('2d');
    this._tearImg = this._tearCtx.createImageData(160, 90);
  }

  _resize() {
    const s = innerHeight / REF_H;
    this.scale = s;
    this.stage.style.width = `${innerWidth / s}px`;
    this.stage.style.transform = `scale(${s})`;
  }

  init() {
    const ev = this.game.events;
    ev.on('points:change', (p) => { if (p && p.delta) this._popupFrom('ev', p.delta); });
    ev.on('points:denied', () => { this._shakeT = 0.32; });
    ev.on('zombie:hit', (p) => this._mark(p && p.head ? 2 : 1, false));
    ev.on('zombie:kill', (p) => this._mark(p && p.head ? 4 : 3, false));
    ev.on('player:hurt', (p) => this._hurt(p || {}));
    ev.on('weapon:fire', () => { this._kick = Math.min(1, this._kick + 0.55); });
    ev.on('weapon:acquire', (p) => { if (p && p.weaponId === 'tiny_tele') this._hadTele = true; });
    ev.on('machine:commercial_start', () => this.suppress('commercial', true));
    ev.on('machine:commercial_end', () => this.suppress('commercial', false));
    ev.on('machine:uplink_take', (p) => this._uplinkFallback(p || {}));
    ev.on('perk:replay', (p) => this.replayBug(!!(p && (p.on ?? true))));
    ev.on('replay:start', () => this.replayBug(true));
    ev.on('replay:end', () => this.replayBug(false));
    ev.on('player:revive', (p) => { if (p && p.selfRevive) setTimeout(() => this.replayBug(false), 1200); });
    ev.on('state', (p) => { if (p && !WORLD.has(p.to)) this._releaseKnobs(); });
  }

  reset() {
    this._dial.shown = null;
    this._dial.target = null;
    this._dial.t = -1;
    this.el.num.textContent = '';
    this.el.knob.style.transform = '';
    this._hadTele = false;
    this._supp.clear();
    this._pulse.static = this._pulse.roll = this._pulse.chroma = this._pulse.damage = 0;
    this._white.t = -1;
    this._tear.t = -1;
    this.el.tear.style.display = 'none';
    this._chy.t = -1;
    this._chy.lastAt = -1e9;
    this.el.chy.style.opacity = '0';
    this.replayBug(false);
    for (const [, it] of this._pu) it.el.remove();
    this._pu.clear();
    for (const p of this._pops) p.el.remove();
    this._pops.length = 0;
    this.tote.set('      ', true);
    this._shown.points = -1;
    this._knobs.damage.wrote = null;
    this.setPrompt(null);
    this.show();
  }

  show() { this.visible = true; }
  hide() { this.visible = false; this._applyVisibility(); }
  suppress(key, on) { if (on) this._supp.add(key); else this._supp.delete(key); this._applyVisibility(); }
  setCrt(on) { this.el.crt.classList.toggle('on', !!on); }

  _applyVisibility() {
    const st = this.game.state;
    const want = this.visible && this._supp.size === 0 && (WORLD.has(st) || st === 'boot');
    if (want === this._shown.want) return;
    this._shown.want = want;
    this.root.classList.toggle('off', !want);
  }

  // -------------------------------------------------------------------------------------------- public API
  // Rare, big moments only (GDD §14: no hints).
  flash(text, style = 'default') {
    const f = this.el.fl;
    f.textContent = String(text);
    f.dataset.style = style;
    this._flashT = 0;
  }

  pointsPopup(delta) { if (delta) this._popupFrom('api', delta); }

  hitmarker(head = false, kill = false) {
    this._mark(kill ? (head ? 4 : 3) : head ? 2 : 1, true);
  }

  // obj: { key:'E', cost?, plug?, hold?, progress 0..1, denied? } | null. Called every frame by interact.js.
  setPrompt(obj) {
    const P = this._prompt, el = this.el;
    const on = !!obj;
    if (on !== P.on) {
      P.on = on;
      P.t = on ? 0 : -1;
      if (!on) el.dy.style.opacity = '0';
    }
    if (!on) return;
    // key glyph: 'E' (keyboard) or an Xbox face button ('X' / 'A' / 'B' / 'Y': round, tinted like the pad's letters)
    const key = typeof obj.key === 'string' && obj.key ? obj.key.slice(0, 2).toUpperCase() : 'E';
    if (key !== P.key) {
      P.key = key;
      el.keyTxt.textContent = key;
      const pad = PAD_KEYS.has(key) && key !== 'E';
      el.key.classList.toggle('pad', pad);
      for (const k of PAD_KEYS) el.key.classList.toggle(`pad-${k.toLowerCase()}`, pad && k === key);
    }
    const plug = !!obj.plug;
    const cost = !plug && Number.isFinite(obj.cost) && obj.cost > 0 ? Math.round(obj.cost) : null;
    if (cost !== P.cost) {
      P.cost = cost;
      el.cost.innerHTML = cost === null ? '' : [...String(cost)].map((c, i) => `<span style="transform:translateY(${((i * 7) % 3) - 1}px) rotate(${((i * 5) % 3 - 1) * 1.5}deg)">${c}</span>`).join('');
      el.cost.style.display = cost === null ? 'none' : '';
    }
    const denied = cost !== null && !!obj.denied;
    if (denied !== P.denied) { P.denied = denied; el.cost.classList.toggle('den', denied); }
    if (plug !== P.plug) { P.plug = plug; el.dy.classList.toggle('plugged', plug); }
    const hold = !!obj.hold;
    if (hold !== P.hold) { P.hold = hold; el.dy.classList.toggle('hold', hold); }
    const prog = hold ? Math.round(clamp(obj.progress || 0, 0, 1) * 200) / 200 : 0;
    if (prog !== P.prog) { P.prog = prog; el.ring.setAttribute('stroke-dashoffset', String(RING_C * (1 - prog))); }
  }

  chyron(name, sub = '') {
    if (!name) return;
    const now = this.game.time.realNow;
    const C = this._chy;
    if (C.t >= 0 && C.name === String(name) && C.t < 2.5) return;
    C.name = String(name);
    C.t = 0;
    C.lastAt = now;
    this.el.chyName.textContent = C.name;
    this.el.chySub.textContent = sub || '';
    this.el.chySub.classList.toggle('on', !!sub);
    const chy = this.el.chy;
    chy.classList.remove('go');
    void chy.offsetWidth;
    chy.classList.add('go');
  }

  replayBug(on) {
    this._replay = !!on;
    this.el.rb.classList.toggle('on', this._replay);
  }
  setReplay(on) { this.replayBug(on); }
  showReplayBug() { this.replayBug(true); }
  hideReplayBug() { this.replayBug(false); }

  whiteout(seconds = T.zombies.bigShot.flash.white, amount = 1) {
    this._white.t = 0;
    this._white.dur = Math.max(0.1, seconds);
    this._white.amount = clamp(amount, 0, 1);
  }

  glitch(amount = 0.5, seconds = 0.3) {
    const a = clamp(amount, 0, 1);
    this._pulse.static = Math.max(this._pulse.static, 0.35 * a);
    this._pulse.roll = Math.max(this._pulse.roll, 0.5 * a);
    this._pulse.chroma = Math.max(this._pulse.chroma, 4 * a);
    this._pulseDecay = 1 / Math.max(0.05, seconds);
  }

  tear(edgeOrPos) {
    let edge = edgeOrPos;
    if (edgeOrPos && edgeOrPos.isVector3) edge = this._edgeToward(edgeOrPos);
    if (!['left', 'right', 'top', 'bottom'].includes(edge)) return;
    this._tear.edge = edge;
    this._tear.t = 0;
    this._tear.acc = 1;
    this._tear.seed = Math.random() * 1000;
    this.el.tear.style.display = 'block';
  }

  // -------------------------------------------------------------------------------------------- internals
  _dup(kind, key, from) {
    const f = this.game.time.frame;
    if (f !== this._frame) { this._frame = f; this._dedupe.clear(); }
    const k = `${kind}|${key}`;
    let e = this._dedupe.get(k);
    if (!e) { e = { ev: 0, api: 0 }; this._dedupe.set(k, e); }
    e[from]++;
    const other = from === 'ev' ? 'api' : 'ev';
    return e[from] <= e[other];
  }

  _popupFrom(from, delta) {
    if (this._dup('pts', delta, from)) return;
    if (delta < 0) {
      this._spendT = 0.2;
      this.el.tote.classList.add('spend');
      return;
    }
    const now = this.game.time.realNow;
    const last = this._pops[this._pops.length - 1];
    if (last && now - last.born < 0.14 && last.el.isConnected) {
      last.value += delta;
      last.el.textContent = `+${last.value}`;
      return;
    }
    const el = document.createElement('div');
    const gold = this._gold();
    el.className = gold ? 'pop gold' : 'pop';
    el.textContent = `+${delta}`;
    el.style.right = `${(this._pops.length % 3) * 14}px`;
    this.el.pops.appendChild(el);
    this._pops.push({ el, born: now, value: delta });
  }

  _gold() {
    const g = this.game;
    return (g.economy && g.economy.multiplier > 1) || !!(g.powerups && g.powerups.active && g.powerups.active.sweeps_week > 0);
  }

  _mark(level, fromApi) {
    if (fromApi) {
      // hitmarker() calls without a zombie event this frame still tick.
      const id = level >= 3 ? 'ui_kill' : level === 2 ? 'ui_hit_head' : 'ui_hit';
      this.game.audio?.play?.(id);
    }
    if (level > this._hm) this._hm = level;
  }

  _hurt(p) {
    const g = this.game, pl = g.player;
    const max = (pl && pl.maxHealth) || 150;
    // GDD §14 "signal loss": edge static, chroma up to 4 px, a SLIGHT roll; the edge static itself follows HP
    // (player.js drives post.damage), a hit only adds a short kick on top.
    const k = clamp((p.dmg || 20) / max, 0.08, 0.6);
    this._pulse.static = Math.max(this._pulse.static, 0.015 + k * 0.08);
    this._pulse.roll = Math.max(this._pulse.roll, 0.05 + k * 0.18);
    this._pulse.chroma = Math.max(this._pulse.chroma, 1.5 + k * 4);
    this._pulse.damage = Math.max(this._pulse.damage, 0.04 + k * 0.15);
    this._pulseDecay = 3.2;
    if (p.from && p.from.isVector3) {
      const edge = this._edgeToward(p.from);
      if (edge) this.tear(edge);
    }
  }

  // The screen edge toward a world position, or null when it is inside the view.
  _edgeToward(pos) {
    const cam = this.game.camera;
    _v.copy(pos).sub(cam.position);
    _q.copy(cam.quaternion).invert();
    _v.applyQuaternion(_q); // camera space: x right, y up, -z forward
    const front = _v.z < 0;
    if (front) {
      const tanV = Math.tan(THREE.MathUtils.degToRad(cam.fov) / 2), tanH = tanV * cam.aspect;
      const nx = _v.x / (-_v.z * tanH), ny = _v.y / (-_v.z * tanV);
      if (Math.abs(nx) < 0.92 && Math.abs(ny) < 0.92) return null;
      return Math.abs(nx) >= Math.abs(ny) ? (nx < 0 ? 'left' : 'right') : ny < 0 ? 'bottom' : 'top';
    }
    // Behind: left/right by side, straight behind reads as the bottom edge.
    if (Math.abs(_v.x) < Math.abs(_v.z) * 0.35) return 'bottom';
    return _v.x < 0 ? 'left' : 'right';
  }

  _releaseKnobs() {
    if (!this._knobsOn) return;
    this._knobsOn = false;
    const post = this.game.render && this.game.render.post;
    if (!post) return;
    for (const k in this._knobs) this._knobs[k].release(post);
  }

  _uplinkFallback(p) {
    const now = this.game.time.realNow;
    if (now - this._chy.lastAt < 20) return;
    const defs = this.game.weapons && this.game.weapons.defs;
    const d = defs && p.weaponId && defs[p.weaponId];
    if (d && d.upgradedName) this.chyron(d.upgradedName);
  }

  // -------------------------------------------------------------------------------------------- per frame
  update(dt) {
    const g = this.game;
    this._applyVisibility();
    this._updatePost(dt);
    this._updateTear(dt);
    this._updateFlash(dt);
    if (this._shown.want === false && !WORLD.has(g.state)) return;
    this._updateCrosshair(dt);
    this._updatePrompt(dt);
    this._updatePoints(dt);
    this._updateAmmo();
    this._updateEquipment();
    this._updateDial(dt);
    this._updateChyron(dt);
    this._updatePowerups();
  }

  _updatePost(dt) {
    const g = this.game, post = g.render && g.render.post;
    const P = this._pulse, W = this._white;
    const decay = Math.exp(-dt * (this._pulseDecay || 3.2));
    P.static *= decay; P.roll *= decay; P.chroma *= decay; P.damage *= Math.exp(-dt * 2.6);
    if (P.static < 0.002) P.static = 0;
    if (P.roll < 0.002) P.roll = 0;
    if (P.chroma < 0.01) P.chroma = 0;
    if (P.damage < 0.002) P.damage = 0;
    let white = 0;
    if (W.t >= 0) {
      W.t += dt;
      const hold = 0.08;
      white = W.t < hold ? W.amount : W.amount * (1 - easeOut(clamp((W.t - hold) / W.dur, 0, 1)));
      if (W.t > W.dur + hold) W.t = -1;
    }
    if (!post || !WORLD.has(g.state)) return;
    this._knobsOn = true;
    const K = this._knobs;
    K.damage.apply(post, P.damage, 'add', dt);
    K.static.apply(post, P.static, 'max', dt);
    K.roll.apply(post, P.roll, 'max', dt);
    K.chroma.apply(post, P.chroma, 'max', dt);
    // Whiteout never sticks: an external flash nobody fades decays by itself over the Big Shot's 1.5 s.
    const kw = K.whiteout;
    if (kw.wrote !== null && post.whiteout === kw.wrote && kw.ext > 0 && kw.still > 0.2) kw.ext = Math.max(0, kw.ext - dt / T.zombies.bigShot.flash.white);
    kw.apply(post, white, 'max', dt);
  }

  _updateTear(dt) {
    const tr = this._tear;
    if (tr.t < 0) return;
    tr.t += dt;
    const life = 0.38;
    if (tr.t >= life) { tr.t = -1; this.el.tear.style.display = 'none'; return; }
    tr.acc += dt;
    if (tr.acc < 1 / 30) return;
    tr.acc = 0;
    const W = 160, H = 90, img = this._tearImg, d = img.data;
    const k = 1 - tr.t / life;
    const horiz = tr.edge === 'left' || tr.edge === 'right';
    const lines = horiz ? H : W, span = horiz ? W : H;
    const base = (horiz ? 0.2 : 0.26) * span * (0.45 + 0.55 * k);
    d.fill(0);
    let jag = 0;
    for (let l = 0; l < lines; l++) {
      if ((l & 3) === 0) jag = (Math.random() - 0.3) * base * 0.8;
      const streak = Math.random() < 0.05 ? base * (0.8 + Math.random()) : 0;
      const depth = Math.max(0, base * (0.55 + 0.45 * Math.sin(l * 0.37 + tr.seed)) + jag + streak);
      const n = Math.min(span, Math.ceil(depth));
      for (let s = 0; s < n; s++) {
        const x = horiz ? (tr.edge === 'left' ? s : W - 1 - s) : l;
        const y = horiz ? l : (tr.edge === 'top' ? s : H - 1 - s);
        const i = (y * W + x) * 4;
        const v = Math.random();
        const c = 60 + v * v * 195;
        d[i] = c; d[i + 1] = c * 1.02; d[i + 2] = Math.min(255, c * 1.12);
        d[i + 3] = 255 * k * clamp(1.15 - s / (depth + 1), 0, 1) * (0.55 + 0.45 * v);
      }
    }
    this._tearCtx.putImageData(img, 0, 0);
  }

  _updateFlash(dt) {
    if (this._flashT < 0) return;
    this._flashT += dt;
    const t = this._flashT, f = this.el.fl;
    if (t > 2.4) { f.style.opacity = '0'; this._flashT = -1; return; }
    const s = t < 0.25 ? 0.4 + 0.6 * easeOutBack(t / 0.25, 2.4) : 1;
    const o = t < 0.1 ? t / 0.1 : t > 2.0 ? 1 - (t - 2.0) / 0.4 : 1;
    f.style.opacity = String(o);
    f.style.transform = `translate(-50%,-50%) scale(${s})`;
  }

  _updateCrosshair(dt) {
    const g = this.game, el = this.el, S = this._shown;
    const w = g.weapons, pl = g.player;
    let deg = 1.5;
    const def = w && w.currentDef ? w.currentDef() : null;
    if (w && typeof w.currentSpread === 'function') deg = w.currentSpread();
    else if (def && def.spread) deg = def.spread[pl && pl.ads ? 1 : 0];
    this._kick *= Math.exp(-dt * 11);
    const fov = THREE.MathUtils.degToRad(g.camera.fov || 70);
    const cone = Math.tan(THREE.MathUtils.degToRad(deg)) / Math.tan(fov / 2) * (REF_H / 2);
    const spread = Math.round(clamp(cone, 5, 150) + this._kick * 9);
    if (spread !== S.spread) {
      S.spread = spread;
      const [t, b, l, r] = el.ticks;
      t.style.top = `${-spread - 11}px`; b.style.top = `${spread}px`; l.style.left = `${-spread - 11}px`; r.style.left = `${spread}px`;
    }
    const dim = !!(pl && pl.sprinting);
    if (dim !== S.dim) { S.dim = dim; el.xh.classList.toggle('dim', dim); }

    // Hitmarker: the strongest hit this frame restarts the X; kills are bigger, headshot kills pop a star.
    if (this._hm > 0) {
      const lv = this._hm;
      this._hm = 0;
      if (lv >= this._hmLevel || this._hmT > 0.08 || this._hmT < 0) {
        this._hmLevel = lv;
        this._hmT = 0;
        el.hm.style.setProperty('--hc', HIT_COL[lv]);
        if (lv === 4) this._starT = 0;
      }
    }
    if (this._hmT >= 0) {
      this._hmT += dt;
      const t = this._hmT, kill = this._hmLevel >= 3;
      const life = kill ? 0.3 : 0.2;
      const pop = t < 0.06 ? 1.35 - (t / 0.06) * 0.35 : 1;
      const gap = (kill ? 13 : 10) * pop, len = kill ? 1.25 : 1;
      el.hm.style.opacity = String(t < life * 0.6 ? 1 : clamp(1 - (t - life * 0.6) / (life * 0.4), 0, 1));
      for (const b of el.hmBars) b.style.transform = `rotate(${b.dataset.a}deg) translateY(${-gap - 6}px) scale(${kill ? 1.25 : 1},${len})`;
      if (t > life) { this._hmT = -1; this._hmLevel = 0; el.hm.style.opacity = '0'; }
    }
    if (this._starT >= 0) {
      this._starT += dt;
      const t = this._starT;
      const s = t < 0.18 ? easeOutBack(t / 0.18, 3) * 1.1 : 1.1 - (t - 0.18) * 0.3;
      el.star.style.opacity = String(t < 0.35 ? 1 : clamp(1 - (t - 0.35) / 0.2, 0, 1));
      el.star.style.transform = `translateY(${-t * 30}px) rotate(${t * 220}deg) scale(${Math.max(0, s)})`;
      if (t > 0.55) { this._starT = -1; el.star.style.opacity = '0'; }
    }
  }

  _updatePrompt(dt) {
    const P = this._prompt, el = this.el;
    if (!P.on) return;
    if (P.t >= 0 && P.t < 1) {
      P.t += dt;
      const t = clamp(P.t / 0.18, 0, 1);
      el.dy.style.opacity = String(clamp(P.t / 0.06, 0, 1));
      this._dyScale = 0.62 + 0.38 * easeOutBack(t, 2.6);
    }
    let dx = 0;
    if (this._shakeT > 0) {
      this._shakeT = Math.max(0, this._shakeT - dt);
      dx = Math.sin(this._shakeT * 70) * 9 * (this._shakeT / 0.32);
    }
    el.dy.style.transform = `translate(calc(-50% + ${dx.toFixed(1)}px),0) rotate(-2.5deg) scale(${(this._dyScale || 1).toFixed(3)})`;
  }

  _updatePoints(dt) {
    const g = this.game, S = this._shown, eco = g.economy;
    const pts = eco ? clamp(Math.floor(eco.points || 0), 0, 999999) : 0;
    if (pts !== S.points) {
      const first = S.points < 0;
      S.points = pts;
      this.tote.set(String(pts).padStart(6, ' '), first);
    }
    this.tote.update(dt);
    const gold = this._gold();
    if (gold !== S.gold) { S.gold = gold; this.el.tote.classList.toggle('gold', gold); }
    if (this._spendT > 0 && (this._spendT -= dt) <= 0) this.el.tote.classList.remove('spend');
    const now = g.time.realNow;
    while (this._pops.length && now - this._pops[0].born > 0.62) this._pops.shift().el.remove();
  }

  _updateAmmo() {
    const g = this.game, S = this._shown, el = this.el, w = g.weapons;
    const slot = w && w.slots ? w.slots[w.current] : null;
    const def = w && w.currentDef ? w.currentDef() : null;
    const has = !!(slot && def && def.mag > 0 && Number.isFinite(slot.mag));
    if (!has !== S.noAmmo) { S.noAmmo = !has; el.ammo.classList.toggle('none', !has); }
    if (!has) return;
    const mag = slot.mag, res = Number.isFinite(slot.reserve) ? slot.reserve : 0;
    if (mag !== S.mag) { S.mag = mag; this.magDrums.set(mag); }
    if (res !== S.res) { S.res = res; this.resDrums.set(res); }
    const low = mag <= Math.ceil(def.mag * 0.25);
    if (low !== S.low) { S.low = low; el.ammo.classList.toggle('low', low); }
  }

  _updateEquipment() {
    const w = this.game.weapons, S = this._shown;
    if (!w) return;
    const gren = clamp(Math.floor(w.grenades ?? w.equipment?.grenades ?? 0), 0, this.tubes.length);
    if (gren !== S.gren) {
      S.gren = gren;
      this.tubes.forEach((d, i) => { d.className = i < gren ? 'tube on' : 'tube off'; });
    }
    const tele = clamp(Math.floor(w.teles ?? w.equipment?.teles ?? 0), 0, this.teles.length);
    if (tele > 0) this._hadTele = true;
    if (tele !== S.tele) {
      S.tele = tele;
      this.teles.forEach((d, i) => { d.className = i < tele ? 'tele on' : 'tele off'; });
    }
    const row = this._hadTele;
    if (row !== S.teleRow) { S.teleRow = row; this.el.teles.classList.toggle('none', !row); }
  }

  _updateDial(dt) {
    const g = this.game, D = this._dial, el = this.el;
    const boss = !!(g.boss && g.boss.active);
    const round = g.rounds ? g.rounds.round : 0;
    const want = boss ? '–' : round > 0 ? String(round) : '';
    if (want !== D.target) {
      D.target = want;
      if (D.shown === null && want === '') { D.shown = ''; el.num.textContent = ''; }
      else { D.t = 0; D.from = D.spin % 360; D.spin = D.from; }
    }
    if (D.t < 0) return;
    D.t += dt;
    const dur = 0.85, t = clamp(D.t / dur, 0, 1);
    // Knob: 1.25 turns with an overshoot, clicking into the detent; the number swaps mid-spin.
    const ang = D.from + 450 * easeOutBack(t, 1.4);
    D.spin = ang;
    el.knob.style.transform = `rotate(${ang.toFixed(1)}deg)`;
    const blur = t < 0.55 ? clamp((t - 0.05) / 0.2, 0, 1) : clamp(1 - (t - 0.55) / 0.12, 0, 1);
    if (t >= 0.55 && D.shown !== D.target) {
      D.shown = D.target;
      el.num.textContent = D.shown;
      el.num.classList.toggle('small', D.shown.length > 2);
    }
    const squash = t > 0.55 && t < 0.85 ? Math.sin(((t - 0.55) / 0.3) * Math.PI) * 0.22 : 0;
    el.num.style.opacity = String(1 - blur * 0.85);
    el.num.style.transform = `scale(${(1 + squash).toFixed(3)},${(1 - squash * 0.7 - blur * 0.35).toFixed(3)})`;
    if (t >= 0.62 && !D.clicked) { D.clicked = true; g.audio?.play?.('ui_round_dial'); }
    if (t >= 1) { D.t = -1; D.clicked = false; el.num.style.transform = ''; el.num.style.opacity = '1'; }
  }

  _updateChyron(dt) {
    const C = this._chy, chy = this.el.chy;
    if (C.t < 0) return;
    C.t += dt;
    const t = C.t, inT = 0.4, hold = 2.5, outT = 0.35;
    let x, o = 1;
    if (t < inT) x = -120 + 120 * easeOutBack(t / inT, 1.2);
    else if (t < inT + hold) x = 0;
    else if (t < inT + hold + outT) { const p = (t - inT - hold) / outT; x = -120 * easeIn(p); o = 1 - p * 0.5; }
    else { C.t = -1; chy.style.opacity = '0'; return; }
    chy.style.opacity = String(o);
    chy.style.transform = `translateX(${x.toFixed(1)}%)`;
  }

  _updatePowerups() {
    const pu = this.game.powerups, act = pu && pu.active;
    const seen = this._seenPu || (this._seenPu = new Set());
    seen.clear();
    if (act) {
      for (const type in act) {
        const left = act[type];
        if (!(left > 0)) continue;
        seen.add(type);
        let it = this._pu.get(type);
        if (!it) {
          const el = document.createElement('div');
          el.className = 'ic in';
          const glow = PU_GLOW[type] || '#FFC23A';
          el.innerHTML = `<svg class="rg" viewBox="0 0 58 58"><circle cx="29" cy="29" r="${PU_R}" fill="rgba(20,12,28,.72)" stroke="rgba(255,255,255,.14)" stroke-width="4"/>
            <circle class="rv" cx="29" cy="29" r="${PU_R}" fill="none" stroke="${glow}" stroke-width="4.5" stroke-linecap="round" stroke-dasharray="${PU_C}" stroke-dashoffset="0"
            style="filter:drop-shadow(0 0 3px ${glow})"/></svg><svg class="ico" viewBox="0 0 48 48">${PU_ICON[type] || `<circle cx="24" cy="24" r="12" fill="${glow}"/>`}</svg>`;
          this.el.pu.appendChild(el);
          requestAnimationFrame(() => el.classList.remove('in'));
          it = { el, ring: el.querySelector('.rv'), total: Math.max(PU_TOTAL[type] || left, left), blink: null, off: -1 };
          this._pu.set(type, it);
        }
        if (left > it.total) it.total = left;
        const off = Math.round(PU_C * (1 - left / it.total) * 10) / 10;
        if (off !== it.off) { it.off = off; it.ring.setAttribute('stroke-dashoffset', String(off)); }
        const blink = left <= 5;
        if (blink !== it.blink) { it.blink = blink; it.el.classList.toggle('blink', blink); }
      }
    }
    for (const [type, it] of this._pu) {
      if (seen.has(type)) continue;
      it.el.classList.add('in');
      setTimeout(() => it.el.remove(), 220);
      this._pu.delete(type);
    }
  }
}
