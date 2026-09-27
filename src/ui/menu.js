// DEAD AIR — menus (GDD §14 menus, §4 character select, §6.5 game over, §13 results). Owned by the UI engineer.
// Text is allowed here (menus only); gameplay controls are shown ONLY on the pause menu's Controls card.
//
// THE LIVING ROOM (title + character select): a cozy 1977 living room at night (shag, wood paneling, the moon in the
//   window, a lamp, a lava lamp, a cloud sofa) built lazily from the prop kit around Telly's walnut console TV (the
//   'telly' prop with its face switched off: the ending reveals it is Telly). While a menu shows it, the render
//   pipeline's RenderPass draws this scene with the menu camera (full post: bloom, grade, collapse); the station scene
//   is not drawn. The TV picture is a render target composited every frame (snow, vertical roll, hold jitter, the
//   picture, an overlay canvas with the OSD channel number and the chyron) and mapped onto the TV's CRT glass.
//   - Title: the TV tunes from snow to the DEAD AIR logo (cards.js logo_dead_air); "PRESS ANY KEY". With the
//     persistent unlock (localStorage deadair.signoff = "1") the TV shows a sunrise instead of snow.
//   - Character select: the camera dollies in; the VHF dial (A/D, arrows, mouse wheel, click on the dial or the
//     arrows) clacks through the promo channels 2 Skip / 4 Roxy / 5 Penny / 7 Duke (Duke preselected, or ?char=).
//     Each channel shows the hero (buildHero: baked art when it exists, else the placeholder) posed on their show's
//     set (promo_<hero> backdrop + a few props), a chyron with name and role, and the hero's leitmotif
//     (audio.music('select:<id>')). E / Enter / Space / a click on the screen "tunes in": the camera dives into the
//     screen, white flash, game.newGame(heroId). Esc goes back to the title. With the unlock every hero wears a gold 13.
// PAUSE: the PLEASE STAND BY card (sleepy Telly, animated) on a TV, with Resume / Options / Controls / Quit.
//   Options (persisted in localStorage deadair.options, applied at boot): mouse sensitivity, gamepad look sensitivity,
//   invert Y (mouse + pad), FOV 60-90, hold/toggle aim and sprint, pad aim assist, pad vibration, volume buses
//   (master, music, sfx, ambience, tv, ui), quality preset (pixel-ratio cap), CRT vignette (hud.setCrt). Keyboard
//   (W/S, A/D, Enter/E, Esc), mouse and Xbox pad. Quit asks twice, then goes to the title. The Controls card lists
//   the keyboard/mouse and the Xbox layout side by side (the column of the last used device is highlighted).
// GAMEPAD: input.js calls padButton(name) for every pad press while a menu shows (names: a b x y lb rb lt rt start
//   back l3 r3 up down left right; D-pad and left stick repeat). Title / game over / results: any button. Select:
//   left/right (or LB/RB) change channel, A (or Start) tunes in, B back to the title. Pause: up/down + A, left/right
//   on options, B backs out / resumes, Start / View resume. Glyphs follow input.device ('input:device' event):
//   PRESS ANY BUTTON, the select Dymo shows a round green A instead of E.
// GAME OVER (GDD §6.5): sting_gameover (tape-stop, hum, silence, 1 kHz), the picture drains and rolls, CRT collapse
//   (render.post.collapse: white line, dot), black, then at 2.9 s (with the 1 kHz) the PLEASE STAND BY test card with
//   Telly asleep, the round in big split-flap digits, kills and points small. After 2 s any key -> character select.
// RESULTS (for the ending team): showResults({round, kills, points}, {title, onDone}) -> the same card layout, awake
//   Telly; after 2 s any key -> onDone() (default: the title).
//
// API (game.menu)
//   selected                      preselected hero id (params.char if valid, else DEFAULT_HERO = duke); updated by select
//   mode                          null | 'title' | 'select' | 'tunein' | 'pause' | 'over' | 'results'
//   showLoading() (real boot, before the room exists)  showTitle() showSelect() showPause() hidePause() showGameOver({round, kills, points}) showVictory({round})
//   showResults(summary, { title = 'GOOD NIGHT', onDone }) hideAll()
//   tune(dir) (+1 / -1 channel)  tuneIn()  options (object) setOption(key, value) (persists + applies)
//   getLivingRoom() -> { scene, camera, telly, parts, root, setPicture(texture|null), activate(camera?), deactivate() }
//       the character-select room for the ending (build it lazily, draw it through the normal pipeline with
//       activate(); setPicture puts any texture on the TV glass, null gives it back to the menu).
//   update(dt) (real dt, every state)  reset() (newGame)
// showVictory: when an ending system is running (game.ending.active / .playing) the menu stays out of its way;
//   otherwise it shows the results card ("SIGN-OFF"). test=1 never shows a menu before play (Game auto-starts).

import * as THREE from 'three';
import { FONTS } from './fonts.js';
import { PAL } from '../core/config.js';
import { HEROES, DEFAULT_HERO, buildHero } from '../actors/heroes.js';
import { woodPanel } from '../core/textures.js';
import { buildProp } from '../props/index.js';
import * as K from '../props/kit.js';
import { setLampLevel } from '../props/machines.js';
import { FlipBoard } from './hud.js';

// ------------------------------------------------------------------------------------------------ constants
const REF_W = 1920, REF_H = 1080;
const CHANNELS = [
  { ch: 2, hero: 'skip', show: 'BEHIND THE SCENES', role: 'FLOOR RUNNER · WZTV 13 CREW', glow: '#FFB870', rim: '#FFC98A', bg: '#3A2A20' },
  { ch: 4, hero: 'roxy', show: 'BOOGIE DOWN SATURDAY', role: 'HOST OF BOOGIE DOWN SATURDAY', glow: '#FF6FB0', rim: '#FF4FA0', bg: '#3A1030' },
  { ch: 5, hero: 'penny', show: 'ENGINEERING REPORT', role: 'NIGHT-SHIFT BROADCAST ENGINEER', glow: '#7FD8FF', rim: '#5FE3FF', bg: '#10284A' },
  { ch: 7, hero: 'duke', show: 'PRECINCT 13', role: 'STAR OF PRECINCT 13', glow: '#8A9CFF', rim: '#9FB6FF', bg: '#161A40' },
];
const GAMEOVER = { drain: 1.2, collapse: 1.15, card: 2.9, lock: 2.0 };
const OPT_KEY = 'deadair.options';
const SIGNOFF_KEY = 'deadair.signoff';
const QUALITY = { low: 0.75, medium: 1.0, high: 1.5 };
const VOL_ROWS = [['master', 'MASTER VOLUME'], ['music', 'MUSIC'], ['sfx', 'SOUND EFFECTS'], ['ambience', 'AMBIENCE'], ['tv', 'TV SPEAKERS'], ['ui', 'INTERFACE']];
// [action, keyboard/mouse keys, note, Xbox glyphs, pad note]
const CONTROLS = [
  ['MOVE', ['W', 'A', 'S', 'D'], null, ['LS']], ['LOOK', ['MOUSE'], null, ['RS']], ['SPRINT', ['SHIFT'], null, ['L3']],
  ['JUMP', ['SPACE'], null, ['A']],
  ['AIM', ['RIGHT MOUSE'], null, ['LT']], ['FIRE', ['LEFT MOUSE'], null, ['RT']], ['RELOAD', ['R'], null, ['X'], 'NO PROMPT'],
  ['INTERACT · BUY', ['E'], null, ['X']],
  ['REPAIR · CRANK', ['HOLD E'], null, ['X'], 'HOLD'], ['MELEE', ['V'], null, ['B']],
  ['TUBE GRENADE', ['G'], 'HOLD TO COOK', ['RB']], ['TINY TELE', ['Q'], null, ['LB']],
  ['SWAP WEAPON', ['1', '2', 'WHEEL'], null, ['Y', 'DL', 'DR']], ['SWAP SHOULDER', ['C'], null, ['DD']], ['PAUSE', ['ESC'], null, ['MENU', 'VIEW']],
];
// Xbox glyphs for the Controls card: face buttons (coloured letters), bumpers, triggers, sticks, D-pad arms, Menu / View.
const DPAD_ARM = { DL: 'M4 14.5h11v11H4z', DR: 'M25 14.5h11v11H25z', DD: 'M14.5 25h11v11h-11z', DU: 'M14.5 4h11v11h-11z' };
const DPAD_SVG = (arm) => `<svg viewBox="0 0 40 40"><path d="M14.5 4h11v10.5H36v11H25.5V36h-11V25.5H4v-11h10.5z" fill="rgba(246,231,200,.3)"/><path d="${DPAD_ARM[arm]}" fill="#FFC23A"/></svg>`;
function padGlyph(g) {
  if (g.length === 1) return `<span class="xb face xb-${g.toLowerCase()}">${g}</span>`;
  if (g === 'LB' || g === 'RB') return `<span class="xb bump">${g}</span>`;
  if (g === 'LT' || g === 'RT') return `<span class="xb trig">${g}</span>`;
  if (g === 'LS' || g === 'RS' || g === 'L3') return `<span class="xb stick">${g}</span>`;
  if (DPAD_ARM[g]) return `<span class="xb dpad">${DPAD_SVG(g)}</span>`;
  if (g === 'MENU') return '<span class="xb sys"><svg viewBox="0 0 20 20"><path d="M5 6h10M5 10h10M5 14h10" stroke="#F6E7C8" stroke-width="2" stroke-linecap="round"/></svg></span>';
  if (g === 'VIEW') return '<span class="xb sys"><svg viewBox="0 0 20 20"><rect x="4" y="4" width="8" height="8" rx="1.5" fill="none" stroke="#F6E7C8" stroke-width="1.8"/><rect x="8" y="8" width="8" height="8" rx="1.5" fill="#2A1E18" stroke="#F6E7C8" stroke-width="1.8"/></svg></span>';
  return `<span class="kc">${g}</span>`;
}
const PAD_MENU = { a: 'Enter', b: 'Escape', up: 'ArrowUp', down: 'ArrowDown', left: 'ArrowLeft', right: 'ArrowRight' };

const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const lerp = (a, b, t) => a + (b - a) * t;
const easeOut = (x) => 1 - (1 - x) * (1 - x);
const easeIn = (x) => x * x;
const easeInCubic = (x) => x * x * x;
const easeInOut = (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);
const easeOutBack = (x, k = 1.70158) => 1 + (k + 1) * Math.pow(x - 1, 3) + k * Math.pow(x - 1, 2);
const V3 = (x, y, z) => new THREE.Vector3(x, y, z);
const _v = new THREE.Vector3();
const _v2 = new THREE.Vector3();
const _ndc = new THREE.Vector2();
const _warm = new THREE.Color('#FFE8D0');

function storeGet(key) { try { return localStorage.getItem(key); } catch { return null; } }
function storeSet(key, v) { try { localStorage.setItem(key, v); } catch { /* private window / blocked storage */ } }
function el(tag, cls, html) { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; }
function canvas(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }

// ------------------------------------------------------------------------------------------------ TV compositor
const COMP_VERT = /* glsl */`varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4( position.xy, 0.0, 1.0 ); }`;
const COMP_FRAG = /* glsl */`
uniform sampler2D tPic;
uniform sampler2D tUI;
uniform float uTime, uSnow, uRoll, uJitter, uPic, uUI, uBright, uSeam;
varying vec2 vUv;
float h12( vec2 p ) { vec3 p3 = fract( vec3( p.xyx ) * 0.1031 ); p3 += dot( p3, p3.yzx + 33.33 ); return fract( ( p3.x + p3.y ) * p3.z ); }
void main() {
  vec2 uv = vUv;
  float ry = uv.y + uRoll;
  float seam = 1.0 - smoothstep( 0.0, 0.045, min( fract( ry ), 1.0 - fract( ry ) ) );
  uv.y = fract( ry );
  float line = floor( uv.y * 240.0 );
  float tj = floor( uTime * 30.0 );
  uv.x += ( h12( vec2( line, tj ) ) - 0.5 ) * uJitter * 0.05 + sin( uv.y * 26.0 + uTime * 19.0 ) * uJitter * 0.012;
  vec3 pic = texture2D( tPic, uv ).rgb * uPic;
  vec4 ui = texture2D( tUI, uv );
  pic = mix( pic, ui.rgb, ui.a * uUI );
  float n = h12( floor( vUv * vec2( 220.0, 165.0 ) ) + tj * vec2( 17.3, 91.7 ) );
  float by = fract( vUv.y * 0.7 - uTime * 0.41 );
  float band = smoothstep( 0.0, 0.3, by ) * smoothstep( 0.62, 0.3, by );
  vec3 snow = vec3( n * n ) * ( 0.75 + 0.45 * band ) * vec3( 0.95, 1.0, 1.08 ) + vec3( 0.015, 0.018, 0.03 );
  vec3 col = mix( pic, snow, uSnow );
  col *= 1.0 - seam * uSeam;
  gl_FragColor = vec4( col * uBright, 1.0 );
}`;

// Floating dust in the TV light: points drifting on slow sine paths (uTime), additive.
const DUST_VERT = /* glsl */`
uniform float uTime; uniform float uSize;
attribute vec4 seed;
varying float vA;
void main() {
  vec3 p = position;
  float t = uTime * ( 0.05 + seed.w * 0.07 );
  p.x += sin( t * 2.1 + seed.x * 6.3 ) * 0.22;
  p.y += fract( t * 0.35 + seed.y ) * 0.9 - 0.45;
  p.z += cos( t * 1.7 + seed.z * 6.3 ) * 0.18;
  vec4 mv = modelViewMatrix * vec4( p, 1.0 );
  gl_Position = projectionMatrix * mv;
  gl_PointSize = uSize * ( 0.6 + seed.w ) / -mv.z;
  vA = 0.5 + 0.5 * sin( uTime * ( 0.7 + seed.x ) + seed.z * 9.0 );
}`;
const DUST_FRAG = /* glsl */`
uniform vec3 uColor; uniform float uAlpha;
varying float vA;
void main() {
  vec2 c = gl_PointCoord - 0.5;
  float a = smoothstep( 0.5, 0.0, length( c ) );
  gl_FragColor = vec4( uColor * a * vA * uAlpha, 1.0 );
}`;

// ------------------------------------------------------------------------------------------------ CSS
const CSS = `
.mn{position:fixed;inset:0;z-index:20;pointer-events:none;user-select:none;font-family:${FONTS.hud};color:${PAL.cream};overflow:hidden}
.mn *{box-sizing:border-box}
.mn-flash{position:absolute;inset:0;background:#FFF8EC;opacity:0;pointer-events:none}
.mn-dim{position:absolute;inset:0;opacity:0;transition:opacity .22s;pointer-events:none;
  background:radial-gradient(ellipse at 50% 50%,rgba(34,20,52,.55),rgba(10,6,18,.86) 80%)}
.mn-dim::after{content:'';position:absolute;inset:0;background:repeating-linear-gradient(0deg,rgba(0,0,0,.16) 0 2px,transparent 2px 4px)}
.mn-dim.on{opacity:1}
.mn-bg{position:absolute;inset:0;display:none;background:radial-gradient(ellipse at 50% 42%,#2A2150,#140E26 60%,#07050C)}
.mn-bg.on{display:block}
.mn-bg::after{content:'';position:absolute;inset:0;background:repeating-linear-gradient(0deg,rgba(0,0,0,.18) 0 2px,transparent 2px 4px)}
.mn-st{position:absolute;left:0;top:0;width:${REF_W}px;height:${REF_H}px;transform-origin:0 0}
.mn-pn{position:absolute;inset:0;display:none}
.mn-pn.on{display:block}
.mn button{font:inherit;color:inherit;background:none;border:0;padding:0;margin:0;cursor:pointer}

/* title */
.mn .pn-title::before{content:'';position:absolute;left:0;right:0;bottom:0;height:300px;background:linear-gradient(0deg,rgba(12,6,20,.62),rgba(12,6,20,0))}
.mn .press{position:absolute;left:0;right:0;bottom:92px;text-align:center;font-size:40px;letter-spacing:.28em;color:#FFF4DC;opacity:0;
  text-shadow:0 3px 0 #5A2210,0 0 18px rgba(255,170,90,.55)}
.mn .press.on{animation:mnpress 1.6s ease-in-out infinite}
@keyframes mnpress{0%,100%{opacity:1}55%{opacity:.18}}
.mn .ldbar{position:absolute;left:50%;bottom:66px;width:280px;height:4px;margin-left:-140px;border-radius:2px;background:rgba(255,244,220,.13);
  box-shadow:0 2px 0 rgba(90,34,16,.55);opacity:0;transition:opacity .5s}
.mn .ldbar.on{opacity:1}
.mn .ldbar i{position:absolute;inset:0;border-radius:2px;background:#FFF4DC;box-shadow:0 0 12px rgba(255,170,90,.6);transform-origin:0 50%;
  transform:scaleX(0);transition:transform .8s linear}

/* select */
.mn .selttl{position:absolute;left:0;right:0;top:46px;text-align:center;font-family:${FONTS.logo};font-size:58px;color:#FFE9B8;transform:rotate(-2deg);opacity:0;
  text-shadow:0 4px 0 #8A2E14,0 8px 16px rgba(0,0,0,.5);transition:opacity .4s}
.mn .selttl.on{opacity:1}
.mn .selbar{position:absolute;left:50%;bottom:44px;transform:translateX(-50%);display:flex;align-items:center;gap:26px;opacity:0;transition:opacity .4s;pointer-events:none}
.mn .selbar.on{opacity:1;pointer-events:auto}
.mn .arrow{width:84px;height:84px;border-radius:50%;display:flex;align-items:center;justify-content:center;
  background:radial-gradient(circle at 40% 32%,#8A5A36,#5A3A22 60%,#3A2414);box-shadow:0 0 0 4px #E8A92E,0 6px 14px rgba(0,0,0,.5),inset 0 3px 0 rgba(255,220,170,.25);
  transition:transform .12s cubic-bezier(.3,1.8,.5,1)}
.mn .arrow:hover{transform:scale(1.1)}
.mn .arrow:active,.mn .arrow.hit{transform:scale(.88)}
.mn .arrow svg{width:40px;height:40px}
.mn .dymo{position:relative;display:flex;align-items:center;gap:16px;height:64px;padding:0 30px 0 20px;white-space:nowrap;transform:rotate(-1.5deg);
  background:linear-gradient(180deg,#3A3A40 0%,#1C1C21 16%,#121216 55%,#1E1E24 88%,#34343C 100%);
  clip-path:polygon(0 8%,1% 0,99% 0,100% 9%,99.3% 22%,100% 36%,99.3% 50%,100% 64%,99.3% 78%,100% 91%,99% 100%,1% 100%,0 92%,.7% 78%,0 64%,.7% 50%,0 36%,.7% 22%);
  filter:drop-shadow(0 5px 6px rgba(0,0,0,.45));font-size:36px;letter-spacing:.08em;color:#F2F0EA;
  text-shadow:0 -1px 0 rgba(0,0,0,.9),0 1px 0 rgba(255,255,255,.35),0 2px 3px rgba(0,0,0,.5)}
.mn .dymo .kc{display:flex;align-items:center;justify-content:center;min-width:46px;height:46px;padding:0 8px;border-radius:10px;font-size:28px;
  box-shadow:inset 0 0 0 3px rgba(242,240,234,.9),inset 0 3px 0 3px rgba(0,0,0,.35)}
.mn .dymo.go{animation:mnthump .28s cubic-bezier(.3,1.8,.5,1)}
@keyframes mnthump{40%{transform:rotate(-1.5deg) scale(1.12)}}

/* shared card TV + panels */
.mn .tvbox{position:absolute;border-radius:46px;padding:34px 170px 34px 34px;
  background:linear-gradient(135deg,#8A5530,#6A3C20 40%,#4E2A14);box-shadow:0 0 0 5px #2E1A0C,0 26px 50px rgba(0,0,0,.6),inset 0 4px 0 rgba(255,210,160,.22),inset 0 -6px 0 rgba(0,0,0,.35)}
.mn .tvbox::before{content:'';position:absolute;inset:0;border-radius:inherit;opacity:.5;
  background:repeating-linear-gradient(88deg,rgba(255,220,170,.06) 0 3px,transparent 3px 11px,rgba(40,16,4,.08) 11px 14px,transparent 14px 23px)}
.mn .tvbox .scr{position:relative;border-radius:30px;overflow:hidden;background:#0A0810;box-shadow:0 0 0 6px #F3E3C0,0 0 0 9px #C8963C,inset 0 0 40px rgba(0,0,0,.6)}
.mn .tvbox canvas{display:block;width:100%;height:100%}
.mn .tvbox .scr::after{content:'';position:absolute;inset:0;border-radius:inherit;pointer-events:none;
  background:radial-gradient(ellipse at 30% 18%,rgba(255,255,255,.2),transparent 40%),repeating-linear-gradient(0deg,rgba(0,0,0,.12) 0 2px,transparent 2px 4px);
  box-shadow:inset 0 0 70px rgba(10,4,20,.65)}
.mn .tvbox .knobs{position:absolute;right:34px;top:40px;bottom:40px;width:110px;display:flex;flex-direction:column;align-items:center;justify-content:space-around;
  border-radius:24px;background:linear-gradient(180deg,#F3E3C0,#E0C898);box-shadow:inset 0 0 0 3px #C8963C,inset 0 -4px 0 rgba(0,0,0,.12)}
.mn .tvbox .knob{width:74px;height:74px;border-radius:50%;background:repeating-conic-gradient(#5A3420 0 12deg,#3E2414 12deg 24deg);
  box-shadow:0 5px 8px rgba(0,0,0,.4),inset 0 0 0 7px rgba(0,0,0,.15);position:relative}
.mn .tvbox .knob::after{content:'';position:absolute;left:50%;top:6px;width:8px;height:22px;margin-left:-4px;border-radius:4px;background:#F3E3C0}
.mn .tvbox .grille{width:80px;height:80px;border-radius:50%;background:repeating-radial-gradient(circle,#C8963C 0 3px,#8A6428 3px 7px);box-shadow:0 0 0 4px #C8963C}
.mn .tvbox .pilot{width:16px;height:16px;border-radius:50%;background:#FF3B30;box-shadow:0 0 12px 3px rgba(255,60,40,.8)}

/* pause */
.mn .pmenu{position:absolute;left:1120px;top:250px;width:640px;display:flex;flex-direction:column;gap:22px}
.mn .pitem{position:relative;display:flex;align-items:center;gap:22px;height:104px;padding:0 30px 0 18px;border-radius:52px;text-align:left;
  background:linear-gradient(180deg,rgba(90,58,34,.92),rgba(58,34,20,.92));box-shadow:0 0 0 4px #2E1A0C,0 8px 16px rgba(0,0,0,.45),inset 0 3px 0 rgba(255,210,160,.18);
  font-size:50px;letter-spacing:.08em;color:#F6E7C8;text-shadow:0 3px 0 #2A140A;transition:transform .16s cubic-bezier(.3,1.6,.5,1),background .12s}
.mn .pitem .chn{flex:0 0 76px;height:76px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:40px;color:#2F5BD3;
  background:#F4F1E8;box-shadow:inset 0 0 0 7px #E23B3B,0 3px 0 rgba(0,0,0,.35);text-shadow:none}
.mn .pitem.sel{transform:translateX(26px) rotate(-1deg);background:linear-gradient(180deg,#F59A48,#D9602B 55%,#A8401E);color:#FFFBEA;text-shadow:0 3px 0 #6A2410}
.mn .pitem.sel .chn{box-shadow:inset 0 0 0 7px #E23B3B,0 0 18px 4px rgba(255,210,90,.75)}
.mn .pitem.warn{background:linear-gradient(180deg,#E8483A,#A82018);color:#FFFBEA}
.mn .gpanel{position:absolute;left:1000px;top:110px;width:820px;border-radius:36px;padding:24px 34px 26px;
  background:linear-gradient(180deg,#F6E7C8,#EAD3A4);box-shadow:0 0 0 6px #5A3A22,0 0 0 10px #E8A92E,0 24px 48px rgba(0,0,0,.55);color:#3A2414}
.mn .gpanel h2{margin:0 0 14px;display:flex;align-items:center;gap:18px;font-family:${FONTS.logo};font-weight:400;font-size:52px;color:#B5472A;text-shadow:0 3px 0 rgba(90,40,20,.25)}
.mn .gpanel h2 i{font-style:normal;font-family:${FONTS.sign};font-size:18px;letter-spacing:.12em;color:#F6E7C8;background:#2F5BD3;padding:6px 12px;border-radius:8px;transform:rotate(-3deg)}
.mn .orow{display:flex;align-items:center;justify-content:space-between;height:45px;padding:0 16px;border-radius:24px;font-size:24px;letter-spacing:.06em}
.mn .orow:nth-child(odd){background:rgba(90,58,34,.08)}
.mn .orow.sel{background:#2F5BD3;color:#F6E7C8;box-shadow:0 0 0 3px #E8A92E}
.mn .orow .lab{flex:1}
.mn .orow .val{min-width:84px;text-align:right;font-family:${FONTS.tape};font-size:32px}
.mn .sld{position:relative;width:300px;height:30px;margin:0 16px;cursor:pointer}
.mn .sld .tr{position:absolute;left:0;right:0;top:11px;height:8px;border-radius:4px;background:#5A3A22;box-shadow:inset 0 2px 2px rgba(0,0,0,.5)}
.mn .sld .fi{position:absolute;left:0;top:11px;height:8px;border-radius:4px;background:linear-gradient(90deg,#E8A92E,#E3662B)}
.mn .sld .kn{position:absolute;top:0;width:22px;height:30px;margin-left:-11px;border-radius:6px;background:linear-gradient(180deg,#F4F1E8,#B8B0A0);box-shadow:0 2px 3px rgba(0,0,0,.5),inset 0 -3px 0 rgba(0,0,0,.2)}
.mn .seg{display:flex;border-radius:18px;overflow:hidden;box-shadow:0 0 0 3px #5A3A22}
.mn .seg b{font-weight:400;padding:6px 16px;font-size:20px;background:#E0C898;color:#5A3A22;cursor:pointer}
.mn .seg b.on{background:#E3662B;color:#FFFBEA}
.mn .orow.sel .seg{box-shadow:0 0 0 3px #F6E7C8}
.mn .back{margin-top:12px;justify-content:center;font-size:28px;cursor:pointer}
.mn .ctl{display:grid;grid-template-columns:1fr auto auto;row-gap:5px;column-gap:20px;align-items:center;font-size:24px;letter-spacing:.06em}
.mn .ctl .hd{font-family:${FONTS.sign};font-size:14px;letter-spacing:.14em;color:#8A6428;text-align:right;padding-bottom:2px}
.mn .ctl .hd.cur{color:#2F5BD3}
.mn .ctl .p{display:flex;gap:6px;justify-content:flex-end;align-items:center;min-width:128px;padding-left:14px;border-left:2px dashed rgba(200,150,60,.55)}
.mn .ctl .p .pn{font-family:${FONTS.sign};font-size:12px;color:#B5472A;margin-right:2px}
.mn .ctl .xb{display:inline-flex;align-items:center;justify-content:center;height:40px;min-width:40px;font-size:19px;color:#F6E7C8;
  background:linear-gradient(180deg,#4A3A30,#2A1E18);box-shadow:0 3px 0 #140C08,inset 0 1px 0 rgba(255,255,255,.2)}
.mn .ctl .xb.face{width:40px;border-radius:50%;font-size:22px;background:radial-gradient(circle at 42% 34%,#4A4048,#1E1A20 72%)}
.mn .ctl .xb-a{color:#7EDB5A}.mn .ctl .xb-b{color:#FF6A5C}.mn .ctl .xb-x{color:#6FA8FF}.mn .ctl .xb-y{color:#FFD24A}
.mn .ctl .xb.bump{min-width:50px;border-radius:14px 14px 7px 7px;font-size:17px}
.mn .ctl .xb.trig{min-width:44px;height:42px;border-radius:16px 16px 8px 8px;font-size:17px}
.mn .ctl .xb.stick{width:40px;border-radius:50%;font-size:15px;box-shadow:0 3px 0 #140C08,inset 0 0 0 3px #6A5A50,inset 0 1px 0 rgba(255,255,255,.2)}
.mn .ctl .xb.dpad{width:40px;border-radius:10px}.mn .ctl .xb.dpad svg{width:32px;height:32px}
.mn .ctl .xb.sys{width:40px;border-radius:50%}.mn .ctl .xb.sys svg{width:22px;height:22px}
.mn .dymo .kc.pad{border-radius:50%;width:46px;padding:0;color:#7EDB5A;background:radial-gradient(circle at 42% 34%,#34343C,#18181D 70%)}
.mn .ctl .k{display:flex;gap:8px;justify-content:flex-end;align-items:center}
.mn .ctl .kc{display:inline-flex;align-items:center;justify-content:center;min-width:44px;height:40px;padding:0 10px;border-radius:9px;font-size:20px;color:#F6E7C8;
  background:linear-gradient(180deg,#4A3A30,#2A1E18);box-shadow:0 3px 0 #140C08,inset 0 1px 0 rgba(255,255,255,.2)}
.mn .ctl .nt{font-family:${FONTS.sign};font-size:13px;color:#B5472A;margin-left:6px}
.mn .ctl .sep{grid-column:1/4;height:2px;background:repeating-linear-gradient(90deg,#C8963C 0 8px,transparent 8px 14px);opacity:.6}

/* game over / results */
.mn .ovcard{left:110px;top:160px}
.mn .ovpan{position:absolute;left:1180px;top:210px;width:640px;display:flex;flex-direction:column;align-items:center}
.mn .ovpan .lab{font-family:${FONTS.sign};font-size:46px;letter-spacing:.2em;color:#FFC23A;text-shadow:0 4px 0 #6A2410}
.mn .ovpan .hdr{font-family:${FONTS.logo};font-size:64px;color:#FFE9B8;text-shadow:0 4px 0 #8A2E14;margin-bottom:10px;transform:rotate(-2deg)}
.mn .board{margin-top:16px;display:flex;gap:12px;padding:22px 26px;border-radius:30px;background:linear-gradient(180deg,#6A4428,#4A2E1A 45%,#3A2214);
  box-shadow:inset 0 3px 0 rgba(255,220,170,.18),inset 0 -5px 0 rgba(0,0,0,.35),0 10px 24px rgba(0,0,0,.5),0 0 0 4px #2A170E}
.mn .board .fd{width:132px;height:196px}
.mn .board .fd .fh,.mn .board .fd .fl{background:#22140D}
.mn .board .fd .ft{border-radius:14px 14px 0 0;background:linear-gradient(#2E1C12,#22140D)}
.mn .board .fd .fb{border-radius:0 0 14px 14px;background:linear-gradient(#1A0F09,#22140D);box-shadow:inset 0 2px 0 rgba(0,0,0,.8)}
.mn .board .fd b{font-size:170px;color:#FFB347;text-shadow:0 0 22px rgba(255,150,40,.75)}
.mn .stats{margin-top:34px;display:flex;gap:44px;font-size:34px;letter-spacing:.12em;color:#F6E7C8;text-shadow:0 3px 0 #2A140A}
.mn .stats span{font-family:${FONTS.tape};font-size:46px;color:#FFE08A;margin-left:12px;letter-spacing:.04em}
.mn .anykey{margin-top:56px;font-size:30px;letter-spacing:.26em;color:#FFF4DC;opacity:0;text-shadow:0 3px 0 #5A2210}
.mn .anykey.on{animation:mnpress 1.6s ease-in-out infinite}
`;

const ARROW = (d) => `<svg viewBox="0 0 40 40"><path d="${d < 0 ? 'M27 6L9 20l18 14z' : 'M13 6l18 14-18 14z'}" fill="#FFE9B8" stroke="#3A1E0E" stroke-width="3" stroke-linejoin="round"/></svg>`;

// ------------------------------------------------------------------------------------------------ Menu
export class Menu {
  constructor(game) {
    this.game = game;
    this.mode = null;
    this._t = 0;
    const want = game.params.char;
    this.selected = HEROES.some((h) => h.id === want) ? want : DEFAULT_HERO;
    this._chIdx = Math.max(0, CHANNELS.findIndex((c) => c.hero === this.selected));
    this.options = null;
    this._room = null;
    this._sets = null;
    this._pause = { sub: 'main', sel: 0, osel: 0, quitArm: -1 };
    this._over = null;
    this._unlocked = storeGet(SIGNOFF_KEY) === '1';
    const style = document.createElement('style');
    style.id = 'deadair-menu-css';
    style.textContent = CSS;
    document.head.appendChild(style);
    this._buildDom();
    this._onResize = () => this._resize();
    addEventListener('resize', this._onResize);
    this._resize();
  }

  // -------------------------------------------------------------------------------------------- lifecycle
  init() {
    this._loadOptions();
    this._applyOptions();
    addEventListener('keydown', (e) => this._onKey(e), true);
    addEventListener('mousedown', (e) => this._onMouseDown(e), true);
    addEventListener('mousemove', (e) => this._onMouseMove(e));
    addEventListener('wheel', (e) => this._onWheel(e), { passive: true });
    addEventListener('mouseup', () => { this._drag = null; });
    this.game.events.on('state', (p) => this._onState(p || {}));
    this.game.events.on('input:device', () => this._refreshGlyphs());
  }

  // ------------------------------------------------------------------------------------------- gamepad
  // input.js calls this for every pad press while a menu shows (see the header). Returns true when it was used.
  padButton(btn) {
    const m = this.mode;
    if (!m || m === 'tunein') return false;
    const key = (code) => this._onKey({ code, repeat: false, shiftKey: false, preventDefault() {}, stopPropagation() {}, stopImmediatePropagation() {} });
    if (m === 'title' || m === 'over' || m === 'results') { key('Enter'); return true; } // any button
    if (m === 'select') {
      const code = btn === 'lb' ? 'ArrowLeft' : btn === 'rb' ? 'ArrowRight' : btn === 'start' ? 'Enter' : PAD_MENU[btn];
      if (code && code !== 'ArrowUp' && code !== 'ArrowDown') key(code);
      return true;
    }
    if (m === 'pause') {
      if (btn === 'start' || btn === 'back') { this.game.audio?.play?.('ui_menu_clack', { vol: 0.7 }); this.game.resume(); return true; }
      if (PAD_MENU[btn]) key(PAD_MENU[btn]);
      return true;
    }
    return true;
  }

  _padMode() { return this.game.input?.device === 'pad'; }
  _anyText() { return this._padMode() ? 'PRESS ANY BUTTON' : 'PRESS ANY KEY'; }

  // Keyboard or Xbox glyphs on the menu surfaces (input:device).
  _refreshGlyphs() {
    const pad = this._padMode();
    const kc = this.dom.selbar.querySelector('.dymo .kc');
    if (kc) { kc.textContent = pad ? 'A' : 'E'; kc.classList.toggle('pad', pad); }
    if (this.dom.anykey) this.dom.anykey.textContent = this._anyText();
    if (this.mode === 'pause' && this._pause.sub === 'controls') this._renderPause();
  }

  reset() {
    // newGame: the run starts; every menu surface goes away (the tune-in flash keeps fading on its own).
    this.hideAll();
  }

  hideAll() {
    this.mode = null;
    this._use3D(false);
    for (const k in this.pn) this.pn[k].classList.remove('on');
    this.dom.dim.classList.remove('on');
    this.dom.bg.classList.remove('on');
    this.dom.press.classList.remove('on');
    this.dom.selttl.classList.remove('on');
    this.dom.selbar.classList.remove('on');
    this.root.style.pointerEvents = 'none';
    this._setCursor('');
  }

  // -------------------------------------------------------------------------------------------- public screens
  // Real boot, before the living room exists (Game.boot, right after the fonts): the title's prompt slot reads
  // PLEASE STAND BY over the dark page (replaces index.html's static pre-script card #da-boot).
  showLoading() {
    this.pn.title.classList.add('on');
    const P = this.dom.press;
    P.textContent = 'PLEASE STAND BY';
    P.classList.add('on');
    this.dom.ldbar?.classList.add('on');
    this._loadT = 1;
    const pre = document.getElementById('da-boot');
    if (pre) pre.remove();
  }

  showTitle() {
    const g = this.game;
    this.hideAll();
    if (g.loaded === false && this._loadT > 0.6) { this.dom.press.textContent = 'PLEASE STAND BY'; this.dom.press.classList.add('on'); }
    this.mode = 'title';
    this._t = 0;
    this._ensureRoom();
    this._use3D(true);
    this._resetPost();
    this._camFrom = this._camTo = 'title';
    this._camBlend = 1;
    this._tvMode('title');
    this.pn.title.classList.add('on');
    this.root.style.pointerEvents = 'auto';
    g.audio?.music?.('title');
  }

  showSelect() {
    const g = this.game;
    const fromTitle = this.mode === 'title';
    this.hideAll();
    if (g.state !== 'menu') g.setState('menu');
    this.mode = 'select';
    this._t = 0;
    this._ensureRoom();
    this._use3D(true);
    this._resetPost();
    this._camFrom = fromTitle ? 'title' : 'select';
    this._camTo = 'select';
    this._camBlend = fromTitle ? 0 : 1;
    this.pn.select.classList.add('on');
    this.root.style.pointerEvents = 'auto';
    setTimeout(() => { if (this.mode === 'select') { this.dom.selttl.classList.add('on'); this.dom.selbar.classList.add('on'); } }, fromTitle ? 700 : 150);
    this._chIdx = Math.max(0, CHANNELS.findIndex((c) => c.hero === this.selected));
    this._tvMode('channel');
    this._tuneTo(this._chIdx, true);
    this._refreshGlyphs();
  }

  tune(dir) {
    if (this.mode !== 'select' || this._camBlend < 0.35) return;
    this._tuneTo((this._chIdx + (dir < 0 ? -1 : 1) + CHANNELS.length) % CHANNELS.length, false, dir);
  }

  tuneIn() {
    if (this.mode !== 'select' || this._camBlend < 0.6) return;
    const g = this.game;
    this.mode = 'tunein';
    this._t = 0;
    this.dom.selttl.classList.remove('on');
    this.dom.selbar.classList.remove('on');
    const d = this.dom.selbar.querySelector('.dymo');
    d.classList.remove('go'); void d.offsetWidth; d.classList.add('go');
    g.audio?.play?.('ui_tune_in');
    const h = this._heroOnSet();
    h?.animator?.kick?.(1.2);
    h?.art?.face?.setExpression?.('smile', 1);
  }

  showPause() {
    this.hideAll();
    this.mode = 'pause';
    const P = this._pause;
    P.sub = 'main'; P.sel = 0; P.osel = 0; P.quitArm = -1;
    this.dom.dim.classList.add('on');
    this.pn.pause.classList.add('on');
    this.root.style.pointerEvents = 'auto';
    this._renderPause();
    this._drawCard(this.dom.pauseCanvas, 'stand_by', 0, true);
    this.game.audio?.play?.('ui_menu_clack', { vol: 0.8 });
  }

  hidePause() {
    if (this.mode !== 'pause') return;
    this.hideAll();
  }

  showGameOver(summary = {}) {
    const g = this.game;
    this.hideAll();
    g.hud?.hide?.();
    this.mode = 'over';
    this._t = 0;
    this._over = { summary: { round: summary.round | 0, kills: summary.kills | 0, points: summary.points | 0 }, phase: 'drain', title: null, onDone: null, results: false };
    g.audio?.play?.('sting_gameover');
  }

  showVictory(summary = {}) {
    const g = this.game;
    g.hud?.hide?.();
    const end = g.ending;
    if (end && (end.active || end.playing || end.running)) return; // the ending sequence owns the screen
    this.showResults({ round: summary.round ?? g.rounds?.round ?? 0, kills: summary.kills ?? g.rounds?.totalKills ?? 0, points: summary.points ?? g.economy?.points ?? 0 },
      { title: 'SIGN-OFF' });
  }

  showResults(summary = {}, { title = 'GOOD NIGHT', onDone = null } = {}) {
    this.hideAll();
    this.game.hud?.hide?.();
    this.mode = 'results';
    this._t = 0;
    this._over = { summary: { round: summary.round | 0, kills: summary.kills | 0, points: summary.points | 0 }, phase: 'card', title, onDone, results: true };
    this._showOverCard();
  }

  // Ending hook: the character-select room, drawn through the normal pipeline while activated.
  getLivingRoom() {
    this._ensureRoom();
    const R = this._room;
    if (!R.api) {
      R.api = {
        scene: R.scene, camera: R.camera, telly: R.telly, parts: R.parts, root: R.root,
        setPicture: (tex) => { R.external = tex || null; R.screenMat.map = tex || R.tv.rtOut.texture; },
        activate: (camera) => { R.externalCam = camera || null; this._use3D(true, camera); },
        deactivate: () => { R.externalCam = null; this._use3D(false); },
      };
    }
    return R.api;
  }

  setOption(key, value) {
    if (!this.options) this._loadOptions();
    if (key.startsWith('vol.')) this.options.vol[key.slice(4)] = value;
    else this.options[key] = value;
    this._applyOptions();
    storeSet(OPT_KEY, JSON.stringify(this.options));
  }

  // -------------------------------------------------------------------------------------------- DOM
  _buildDom() {
    const root = el('div', 'mn');
    root.innerHTML = `<div class="mn-bg"></div><div class="mn-dim"></div><div class="mn-st">
      <div class="mn-pn pn-title"><div class="press">PRESS ANY KEY</div><div class="ldbar"><i></i></div></div>
      <div class="mn-pn pn-select"><div class="selttl">Who's on tonight?</div>
        <div class="selbar"><button class="arrow l">${ARROW(-1)}</button><div class="dymo"><span>CHANNEL</span><span class="kc">E</span><span>TUNE IN</span></div>
        <button class="arrow r">${ARROW(1)}</button></div></div>
      <div class="mn-pn pn-pause"><div class="tvbox pcard" style="left:130px;top:215px"><div class="scr" style="width:640px;height:480px"><canvas width="1024" height="768"></canvas></div>
          <div class="knobs"><div class="knob"></div><div class="knob" style="transform:rotate(130deg)"></div><div class="grille"></div><div class="pilot"></div></div></div>
        <div class="pmenu"></div><div class="gpanel" style="display:none"></div></div>
      <div class="mn-pn pn-over"><div class="tvbox ovcard"><div class="scr" style="width:800px;height:600px"><canvas width="1024" height="768"></canvas></div>
          <div class="knobs"><div class="knob"></div><div class="knob" style="transform:rotate(200deg)"></div><div class="grille"></div><div class="pilot"></div></div></div>
        <div class="ovpan"><div class="hdr" style="display:none"></div><div class="lab">ROUND</div><div class="board"></div>
          <div class="stats"><div>KILLS<span class="sk">0</span></div><div>POINTS<span class="sp">0</span></div></div><div class="anykey">PRESS ANY KEY</div></div></div>
    </div><div class="mn-flash"></div>`;
    document.body.appendChild(root);
    const q = (s) => root.querySelector(s);
    this.root = root;
    this.stage = q('.mn-st');
    this.pn = { title: q('.pn-title'), select: q('.pn-select'), pause: q('.pn-pause'), over: q('.pn-over') };
    this.dom = {
      bg: q('.mn-bg'), dim: q('.mn-dim'), flash: q('.mn-flash'), press: q('.press'), ldbar: q('.ldbar'), selttl: q('.selttl'), selbar: q('.selbar'),
      pauseCanvas: q('.pn-pause canvas'), pmenu: q('.pmenu'), gpanel: q('.gpanel'), overCanvas: q('.pn-over canvas'),
      ovHdr: q('.ovpan .hdr'), ovLab: q('.ovpan .lab'), board: q('.ovpan .board'), sk: q('.stats .sk'), sp: q('.stats .sp'), anykey: q('.anykey'),
    };
    q('.arrow.l').addEventListener('click', (e) => { e.stopPropagation(); this.tune(-1); });
    q('.arrow.r').addEventListener('click', (e) => { e.stopPropagation(); this.tune(1); });
    q('.selbar .dymo').addEventListener('click', (e) => { e.stopPropagation(); this.tuneIn(); });
    this._board = new FlipBoard(this.dom.board, 2, { speed: 0.55, onFlip: () => this._flipSound() });
    this._board.set('00', true);
  }

  _resize() {
    const s = Math.min(innerWidth / REF_W, innerHeight / REF_H);
    this.scale = s;
    this.stage.style.transform = `translate(${(innerWidth - REF_W * s) / 2}px,${(innerHeight - REF_H * s) / 2}px) scale(${s})`;
  }

  _setCursor(c) { if (this._cursor !== c) { this._cursor = c; this.root.style.cursor = c; } }

  // -------------------------------------------------------------------------------------------- options
  _loadOptions() {
    const g = this.game;
    const vol = {};
    for (const [k] of VOL_ROWS) vol[k] = g.audio?.getBusVolume?.(k) ?? 1;
    const def = { sensitivity: 1, padSens: 1, invertY: false, fov: 70, aim: 'hold', sprint: 'hold', aimAssist: true, rumble: true, vol, quality: 'high', crt: false };
    let saved = null;
    try { saved = JSON.parse(storeGet(OPT_KEY) || 'null'); } catch { saved = null; }
    this.options = { ...def, ...(saved && typeof saved === 'object' ? saved : {}), vol: { ...vol, ...((saved && saved.vol) || {}) } };
  }

  _applyOptions() {
    const g = this.game, o = this.options;
    if (!o) return;
    const inp = g.input;
    if (inp && inp.options) {
      inp.options.sensitivity = clamp(+o.sensitivity || 1, 0.1, 5);
      inp.options.invertY = !!o.invertY;
      inp.options.padSensitivity = clamp(+o.padSens || 1, 0.3, 2.5);
      inp.options.aimAssist = o.aimAssist !== false;
      inp.options.rumble = o.rumble !== false;
      if (!inp.options.rumble) inp.pad?.stopRumble?.();
      if (inp.options.holdToggle) { inp.options.holdToggle.aim = o.aim === 'toggle' ? 'toggle' : 'hold'; inp.options.holdToggle.sprint = o.sprint === 'toggle' ? 'toggle' : 'hold'; }
    }
    if (g.cam) g.cam.fovBase = clamp(+o.fov || 70, 60, 90);
    for (const [k] of VOL_ROWS) if (o.vol && Number.isFinite(o.vol[k])) g.audio?.setBusVolume?.(k, o.vol[k]);
    const r = g.render;
    if (r) {
      const cap = Math.min(window.devicePixelRatio || 1, QUALITY[o.quality] ?? 1.5);
      if (r.maxPixelRatio !== cap) {
        r.maxPixelRatio = cap;
        try { r.setPixelRatio(o.quality === 'high' ? cap : Math.min(r.pixelRatio, cap)); } catch { /* render not ready */ }
      }
    }
    g.hud?.setCrt?.(!!o.crt);
  }

  // -------------------------------------------------------------------------------------------- input routing
  _onState(p) {
    // A run started from anywhere (debug, test harness): no menu surface may stay up.
    if ((p.to === 'playing' || p.to === 'down') && this.mode && this.mode !== 'tunein') this.hideAll();
  }

  _onKey(e) {
    const m = this.mode;
    if (!m || e.repeat) return;
    const c = e.code;
    if (m === 'title') {
      if (/^(Shift|Control|Alt|Meta|Escape|Tab)/.test(c) || this._t < 0.35 || this.game.loaded === false) return;
      this._titleGo();
    } else if (m === 'select') {
      if (c === 'KeyA' || c === 'ArrowLeft') { this.tune(-1); this._arrowHit('l'); }
      else if (c === 'KeyD' || c === 'ArrowRight') { this.tune(1); this._arrowHit('r'); }
      else if (c === 'KeyE' || c === 'Enter' || c === 'Space' || c === 'NumpadEnter') { e.preventDefault(); this.tuneIn(); }
      else if (c === 'Escape') { e.preventDefault(); this.game.audio?.play?.('ui_menu_clack', { vol: 0.7 }); this.showTitle(); }
    } else if (m === 'pause') {
      this._pauseKey(e);
    } else if (m === 'over' || m === 'results') {
      if (/^(Shift|Control|Alt|Meta|Tab)/.test(c)) return;
      if (e.code === 'Escape') { e.stopImmediatePropagation(); e.preventDefault(); }
      this._overGo();
    }
  }

  _onMouseDown(e) {
    const m = this.mode;
    if (!m) return;
    if (m === 'title') { if (this._t >= 0.35 && this.game.loaded !== false) this._titleGo(); return; }
    if (m === 'over' || m === 'results') { this._overGo(); return; }
    if (m === 'select' && e.button === 0 && !e.target.closest?.('button,.dymo')) {
      const hit = this._pick(e.clientX, e.clientY);
      if (hit === 'dial') { this.tune(1); this._dialPunch = 1; }
      else if (hit === 'screen') this.tuneIn();
    }
  }

  _onMouseMove(e) {
    if (this.mode === 'select') {
      const hit = this._pick(e.clientX, e.clientY);
      this._hover = hit;
      this._setCursor(hit ? 'pointer' : '');
    }
    if (this._drag) this._dragTo(e.clientX);
  }

  _onWheel(e) {
    if (this.mode !== 'select' || !e.deltaY) return;
    const now = performance.now();
    if (now - (this._wheelAt || 0) < 130) return;
    this._wheelAt = now;
    this.tune(e.deltaY > 0 ? 1 : -1);
  }

  _arrowHit(side) {
    const b = this.dom.selbar.querySelector(`.arrow.${side}`);
    if (!b) return;
    b.classList.add('hit');
    setTimeout(() => b.classList.remove('hit'), 110);
  }

  _titleGo() {
    if (this.mode !== 'title') return;
    this.game.audio?.play?.('ui_menu_clack');
    this.showSelect();
  }

  _overGo() {
    const O = this._over;
    if (!O || O.phase !== 'card' || this._t < GAMEOVER.lock) return;
    this.game.audio?.play?.('ui_menu_clack');
    if (O.onDone) { const fn = O.onDone; this.hideAll(); this._over = null; this._resetPost(); try { fn(); } catch (err) { console.error('[menu] results onDone', err); } return; }
    this._over = null;
    if (O.results) { this.game.setState('menu'); this.showTitle(); } else this.showSelect();
  }

  // -------------------------------------------------------------------------------------------- per frame
  update(dt) {
    this._t += dt;
    const m = this.mode;
    if (!m) return;
    if ((m === 'title' || m === 'select' || m === 'tunein') && !this._room) { if (m === 'tunein' && this._t > 0.3) this._startGame(); return; }
    if (m === 'title' || m === 'select' || m === 'tunein') this._updateRoom(dt);
    if (m === 'title') this._updateTitle(dt);
    else if (m === 'select') this._updateSelect(dt);
    else if (m === 'tunein') this._updateTuneIn(dt);
    else if (m === 'pause') this._updatePause(dt);
    else if (m === 'over' || m === 'results') this._updateOver(dt);
  }

  _resetPost() {
    const p = this.game.render?.post;
    if (!p) return;
    Object.assign(p, { collapse: 0, saturation: 1, static: 0, roll: 0, damage: 0, whiteout: 0, crt: 0, chroma: 0, scanlines: 0, vignette: 0 });
  }

  // -------------------------------------------------------------------------------------------- title
  _updateTitle(dt = 0) {
    // While the station still loads behind the title (game.loaded === false, real boot only) the TV holds its
    // first beat (snow, or the sunrise with the unlock) and the prompt reads PLEASE STAND BY; the tune-in to the
    // logo and PRESS ANY KEY start once everything is loaded (input is ignored until then).
    const loading = this.game.loaded === false;
    if (loading) { this._t = 0; this._loadT = (this._loadT || 0) + dt; }
    const P = this.dom.press;
    if (loading) {
      if (this._loadT > 0.6 && !P.classList.contains('on')) { P.textContent = 'PLEASE STAND BY'; P.classList.add('on'); }
    } else if (P.textContent !== this._anyText()) {
      const wasLoading = P.textContent === 'PLEASE STAND BY';
      P.textContent = this._anyText(); // PRESS ANY BUTTON while the pad is the last device
      if (wasLoading) P.classList.remove('on');
    }
    // loading bar under PLEASE STAND BY (game.loadProgress; the CSS transition keeps it gliding through long steps)
    const B = this.dom.ldbar;
    if (B) {
      const p = loading ? (this.game.loadProgress || 0) : 1;
      if (p !== this._ldP) { this._ldP = p; B.firstChild.style.transform = `scaleX(${p.toFixed(3)})`; }
      const on = loading && this._loadT > 0.6;
      if (on !== B.classList.contains('on')) B.classList.toggle('on', on);
    }
    const t = this._t, TV = this._room.tv;
    const u = TV.u;
    if (this._unlocked) {
      // sunrise instead of snow, then the logo tunes in
      TV.pic = t < 0.9 ? TV.sunrise : TV.titleTex;
      u.uPic.value = 1;
      u.uSnow.value = t < 0.9 ? 0.08 : t < 1.55 ? lerp(0.9, 0.04, easeOut((t - 0.9) / 0.65)) : 0.03;
    } else {
      TV.pic = TV.titleTex;
      u.uPic.value = t < 0.8 ? 0 : 1;
      u.uSnow.value = t < 0.8 ? 1 : t < 1.6 ? lerp(1, 0.04, easeOut((t - 0.8) / 0.8)) * (0.85 + 0.15 * Math.sin(t * 60)) : 0.035;
    }
    const tune = clamp((t - 0.8) / 0.9, 0, 1);
    u.uRoll.value = t < 0.8 ? 0 : (1 - easeOut(tune)) * 1.35;
    u.uSeam.value = tune < 1 ? 0.9 : 0;
    // hold hiccup every few seconds once stable
    const hic = t > 2 ? Math.max(0, Math.sin(t * 0.9) - 0.985) * 60 : 0;
    u.uJitter.value = t < 0.8 ? 0.2 : lerp(1, 0.02, easeOut(tune)) + hic * 0.4;
    u.uUI.value = 0;
    u.uBright.value = 1;
    if (t > 0.8 && !this._titlePing) { this._titlePing = true; this.game.audio?.play?.('crt_ping', { vol: 0.6 }); }
    if (t < 0.1) this._titlePing = false;
    if (!loading && t > 1.7 && !this.dom.press.classList.contains('on')) this.dom.press.classList.add('on');
    this._tvGlow(t < 0.8 ? '#B8D0FF' : '#FFB070', t < 0.8 ? 1.3 + Math.random() * 0.5 : 1.7 + hic);
  }

  // -------------------------------------------------------------------------------------------- select
  _tuneTo(idx, instant = false, dir = 1) {
    const g = this.game;
    this._chIdx = idx;
    const C = CHANNELS[idx];
    this.selected = C.hero;
    this._ch = { t: instant ? 0.1 : 0, osd: 0, chy: -1, drawn: '', pose: 0, dir };
    this._showSet(idx);
    if (!instant) g.audio?.play?.('ui_menu_clack', { vol: 0.75, rate: 0.95 + Math.random() * 0.1 });
    g.audio?.play?.('telly_zip', { vol: 0.3 });
    clearTimeout(this._musicT);
    this._musicT = setTimeout(() => { if (this.mode === 'select' || this.mode === 'tunein') g.audio?.music?.(`select:${C.hero}`); }, instant ? 0 : 90);
    const R = this._room;
    if (R) R.dialTarget = R.parts.dialDetents?.[C.ch] ?? R.dialTarget;
  }

  _updateSelect(dt) {
    const R = this._room, TV = R.tv, u = TV.u, S = this._ch;
    if (this._camBlend < 1) this._camBlend = Math.min(1, this._camBlend + dt / 1.25);
    S.t += dt;
    const t = S.t;
    // snow burst -> rolling picture that settles
    const settle = clamp((t - 0.16) / 0.45, 0, 1);
    TV.pic = this._sets ? this._sets.rt.texture : TV.titleTex;
    u.uPic.value = t < 0.16 ? 0 : 1;
    u.uSnow.value = t < 0.16 ? 1 : lerp(0.85, 0.025, easeOut(settle));
    u.uRoll.value = t < 0.16 ? 0 : (1 - easeOut(settle)) * 0.6 * (S.dir || 1);
    u.uSeam.value = settle < 1 ? 0.9 : 0;
    u.uJitter.value = lerp(0.8, 0.012, easeOut(settle));
    u.uUI.value = 1;
    u.uBright.value = 1;
    this._updateSetScene(dt, t);
    this._drawUI(t);
    this._prebuild(t);
    const C = CHANNELS[this._chIdx];
    this._tvGlow(t < 0.16 ? '#C8D8FF' : C.glow, t < 0.16 ? 1.4 + Math.random() * 0.6 : 1.9);
  }

  _updateTuneIn(dt) {
    const R = this._room, u = R.tv.u, t = this._t;
    this._updateSetScene(dt, this._ch.t += dt);
    this._drawUI(this._ch.t);
    // the camera dives into the glass, the picture blows out to white, the flash covers the load
    const k = clamp(t / 1.0, 0, 1);
    this._camFrom = 'select'; this._camTo = 'screen'; this._camBlend = easeInCubic(k);
    u.uBright.value = 1 + easeIn(clamp((t - 0.45) / 0.5, 0, 1)) * 5;
    this.dom.flash.style.transition = 'none';
    this.dom.flash.style.opacity = String(easeIn(clamp((t - 0.72) / 0.28, 0, 1)));
    this._tvGlow(CHANNELS[this._chIdx].glow, 1.9 + u.uBright.value);
    if (t >= 1.0) this._startGame();
  }

  _startGame() {
    const g = this.game, hero = this.selected, f = this.dom.flash;
    this.hideAll();
    f.style.transition = 'none';
    f.style.opacity = '1';
    this._camBlend = 1;
    try { g.newGame(hero); } catch (err) { console.error('[menu] newGame failed', err); }
    // CSS transition (not the game loop): the first frames of a run can hitch while shaders compile, the white
    // must still clear on time.
    void f.offsetWidth;
    f.style.transition = 'opacity .6s cubic-bezier(.2,.7,.3,1) .12s';
    f.style.opacity = '0';
  }

  // -------------------------------------------------------------------------------------------- living room
  _ensureRoom() {
    if (this._room) return;
    try {
      this._buildRoom();
    } catch (err) {
      console.error('[menu] living room build failed', err);
      this._room = null;
    }
  }

  _use3D(on, camera = null) {
    const r = this.game.render;
    if (!r || !r.renderPass) return;
    const R = this._room;
    if (on && R) {
      r.renderPass.scene = R.scene;
      r.renderPass.camera = camera || R.camera;
      R.active = true;
    } else if (R && R.active) {
      r.renderPass.scene = this.game.scene;
      r.renderPass.camera = r.cameraOverride || this.game.camera;
      R.active = false;
    }
  }

  _buildRoom() {
    const g = this.game, M = g.mats;
    const R = { active: false, dialAngle: 0, dialVel: 0, dialTarget: 0, glow: new THREE.Color('#FFB070'), glowI: 1.5 };
    const scene = new THREE.Scene();
    scene.name = 'menu:livingRoom';
    scene.background = new THREE.Color('#0B0814');
    scene.fog = new THREE.Fog('#0B0814', 40, 90);
    R.lights = this._lightRig(scene, { sky: '#6A78C8', ground: '#3A2418', hemi: 0.42, key: '#A8BCFF', keyI: 0.55, fill: '#FFB070', fillI: 0.1 });
    R.lights.key.position.set(-5.5, 3.6, -1.2);
    R.lights.key.target.position.set(0.5, 0.4, 0.6);
    const root = new THREE.Group();
    root.name = 'livingRoom';
    scene.add(root);
    R.scene = scene; R.root = root;
    this._fullColor(scene);

    // ---- shell: shag floor, paneled walls (window hole on the left), baseboards, ceiling
    const X0 = -3, X1 = 3, Z0 = -3.3, Z1 = 2.1, H = 3.0;
    const floorMat = M.toon('#ffffff', { rough: 1, rim: 0.1, map: K.tex.shag('#C8562A', '#E8A92E') });
    const fg = new THREE.PlaneGeometry(X1 - X0, Z1 - Z0);
    K.uvScale(fg, (X1 - X0) * 1.1, (Z1 - Z0) * 1.1);
    const floor = new THREE.Mesh(fg, floorMat);
    floor.rotation.x = -Math.PI / 2; floor.position.set(0, 0, (Z0 + Z1) / 2); floor.receiveShadow = true;
    root.add(floor);
    const wallMat = M.toon('#ffffff', { rough: 0.5, rim: 0.12, map: woodPanel('#7A4A2A') });
    const trim = M.toon('#4A2E1C', { rough: 0.4, rim: 0.15 });
    const win = { z: -0.55, y: 1.42, w: 1.34, h: 1.12 };
    const wall = (len, rotY, pos, hole = null) => {
      let geo;
      if (hole) {
        const s = new THREE.Shape();
        s.moveTo(-len / 2, 0); s.lineTo(len / 2, 0); s.lineTo(len / 2, H); s.lineTo(-len / 2, H); s.closePath();
        const hp = new THREE.Path();
        hp.moveTo(hole.x - hole.w / 2, hole.y - hole.h / 2); hp.lineTo(hole.x + hole.w / 2, hole.y - hole.h / 2);
        hp.lineTo(hole.x + hole.w / 2, hole.y + hole.h / 2); hp.lineTo(hole.x - hole.w / 2, hole.y + hole.h / 2); hp.closePath();
        s.holes.push(hp);
        geo = new THREE.ShapeGeometry(s);
        const uv = geo.attributes.uv;
        for (let i = 0; i < uv.count; i++) uv.setXY(i, (uv.getX(i) + len / 2) / 1.2, uv.getY(i) / 2.4);
      } else {
        geo = new THREE.PlaneGeometry(len, H);
        geo.translate(0, H / 2, 0);
        K.uvScale(geo, len / 1.2, H / 2.4);
      }
      const w = new THREE.Mesh(geo, wallMat);
      w.position.set(pos[0], 0, pos[2]); w.rotation.y = rotY; w.receiveShadow = true;
      root.add(w);
      const bb = new THREE.Mesh(K.box(len, 0.12, 0.03, 0.008), trim);
      bb.position.set(pos[0], 0.06, pos[2]); bb.rotation.y = rotY; bb.translateZ(0.015); bb.receiveShadow = true;
      root.add(bb);
      const cr = new THREE.Mesh(K.box(len, 0.08, 0.05, 0.01), trim);
      cr.position.set(pos[0], H - 0.04, pos[2]); cr.rotation.y = rotY; cr.translateZ(0.025);
      root.add(cr);
    };
    wall(X1 - X0, Math.PI, [0, 0, Z1]);
    wall(Z1 - Z0, Math.PI / 2, [X0, 0, (Z0 + Z1) / 2], { x: -(win.z - (Z0 + Z1) / 2), y: win.y, w: win.w, h: win.h });
    wall(Z1 - Z0, -Math.PI / 2, [X1, 0, (Z0 + Z1) / 2]);
    wall(X1 - X0, 0, [0, 0, Z0]);
    const ceil = new THREE.Mesh(new THREE.PlaneGeometry(X1 - X0, Z1 - Z0), M.toon('#3A2A22', { rough: 0.95, rim: 0 }));
    ceil.rotation.x = Math.PI / 2; ceil.position.set(0, H, (Z0 + Z1) / 2);
    root.add(ceil);

    // ---- the window: walnut frame, sill, glass, the night outside (moon, skyline, the WZTV tower), curtains
    const wood = M.toon('#ffffff', { rough: 0.45, rim: 0.15, map: K.tex.wood(PAL.walnut, { dark: 0.4 }) });
    const fw = 0.08;
    const addB = (w, h, d, x, y, z, mat = wood) => { const m = new THREE.Mesh(K.box(w, h, d, 0.015), mat); m.position.set(x, y, z); m.castShadow = true; m.receiveShadow = true; root.add(m); return m; };
    addB(0.14, win.h + fw * 2, fw, X0 + 0.03, win.y, win.z - win.w / 2 - fw / 2).rotation.y = Math.PI / 2;
    addB(0.14, win.h + fw * 2, fw, X0 + 0.03, win.y, win.z + win.w / 2 + fw / 2).rotation.y = Math.PI / 2;
    addB(0.14, fw, win.w, X0 + 0.03, win.y + win.h / 2 + fw / 2, win.z);
    addB(0.26, 0.05, win.w + 0.3, X0 + 0.09, win.y - win.h / 2 - 0.025, win.z);
    addB(0.05, win.h, 0.035, X0 + 0.02, win.y, win.z);
    addB(0.05, 0.035, win.w, X0 + 0.02, win.y, win.z);
    const night = new THREE.Mesh(new THREE.PlaneGeometry(3.2, 2.4), new THREE.MeshBasicMaterial({ map: this._nightTexture(), fog: false }));
    night.position.set(X0 - 0.9, win.y + 0.2, win.z); night.rotation.y = Math.PI / 2;
    root.add(night);
    const beacon = new THREE.Mesh(new THREE.SphereGeometry(0.018, 8, 6), M.glow('#FF3B30', 5));
    beacon.position.set(X0 - 0.88, win.y + 0.47, win.z - 0.42);
    root.add(beacon);
    R.beacon = beacon;
    const curtain = M.toon('#ffffff', { rough: 0.9, rim: 0.4, map: K.tex.weave('#E8A92E', { pattern: 'cord' }) });
    for (const s of [-1, 1]) {
      const c = new THREE.Mesh(K.cushion(0.46, win.h + 0.5, 0.1, { puff: 0.03 }), curtain);
      c.position.set(X0 + 0.14, win.y + 0.05, win.z + s * (win.w / 2 + 0.18)); c.rotation.y = Math.PI / 2; c.castShadow = true;
      root.add(c);
    }
    addB(0.05, 0.05, win.w + 1.2, X0 + 0.14, win.y + win.h / 2 + 0.3, win.z, M.toon('#C8963C', { rough: 0.3, metal: 0.8, rim: 0.3 }));

    // ---- props (the kit's own AO + shadows); Telly's TV at the back wall
    const put = (id, pos, rotY = 0, opts = {}) => {
      try {
        const p = buildProp(id, g, opts);
        p.position.set(pos[0], pos[1], pos[2]); p.rotation.y = rotY;
        root.add(p);
        return p;
      } catch (err) {
        console.warn(`[menu] prop ${id} failed`, err);
        return null;
      }
    };
    const telly = put('telly', [0, 0, 1.55], 0, { card: null, pose: 'hidden', legs: 0, channel: 7 });
    R.telly = telly;
    put('telly_rug', [0, 0, 1.25]);
    const lamp = put('telly_lamp', [-1.4, 0, 1.62], 0.4);
    if (lamp) try { setLampLevel(g, lamp, 1); } catch { /* optional */ }
    put('table_side_tulip', [1.38, 0, 1.66]);
    const lava = put('lamp_lava', [1.38, 0.54, 1.66], 0.3);
    R.lava = lava;
    put('plant_rubber', [2.45, 0, 1.62], 0.6);
    put('bookshelf', [X0 + 0.2, 0, 1.05], -Math.PI / 2);
    put('clock_sunburst', [1.45, 1.3, Z1 - 0.045]);   // prop centre is 0.4 m above its origin → hangs at ~1.7 m, above the lava lamp
    put('macrame_owl', [-2.25, 0.25, Z1 - 0.07]);
    // frame_picture's origin is the frame bottom (wall prop): hang both at ~1.25 m like real pictures
    put('frame_picture', [2.35, 1.25, Z1 - 0.03], 0, { card: 'poster_precinct13', style: 'walnut' });
    put('frame_picture', [X1 - 0.03, 1.25, -0.2], -Math.PI / 2, { card: 'poster_boogie_down', style: 'gold' });
    put('sofa_cloud', [0.05, 0, -1.95], Math.PI);
    put('table_coffee', [0.05, 0, -0.55], Math.PI);
    root.add(this._popcorn(g, [0.42, 0.49, -0.5]));
    const guide = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.012, 0.27), M.toon('#ffffff', { rough: 0.6, rim: 0.1, map: this._card('magazine_tv_weekly') }));
    guide.position.set(-0.28, 0.486, -0.62); guide.rotation.y = 0.35; guide.castShadow = true;
    root.add(guide);

    // ---- Telly's glass: our composited picture
    const P = telly?.userData?.parts || {};
    R.parts = { ...P, dialDetents: telly?.userData?.rig?.dial?.detents || {} };
    R.screenMat = P.screen?.material || null;
    R.tv = this._buildTv();
    if (R.screenMat) R.screenMat.map = R.tv.rtOut.texture;
    R.dialAngle = R.dialTarget = P.dial ? P.dial.rotation.z : 0;
    if (telly) telly.updateMatrixWorld(true);
    const glowFrom = P.screen ? P.screen.getWorldPosition(new THREE.Vector3()) : V3(0.12, 0.9, 1.45); // lighting keeps the prop's anchor
    try { this._seatScreen(R, telly); } catch (err) { console.warn('[menu] screen seat failed', err); }
    if (telly) telly.updateMatrixWorld(true);
    R.screenWorld = P.screen ? P.screen.getWorldPosition(new THREE.Vector3()) : V3(0.12, 0.9, 1.45);

    // ---- lights: TV glow, lamp, lava, moon spill (the rest of the pool stays dark)
    const L = R.lights.points;
    L[0].position.copy(glowFrom).add(V3(0, -0.45, -1.35)); L[0].distance = 4.5;
    if (P.glass) P.glass.visible = false; // the rubber membrane's env reflection washes the picture out at this range
    const la = lamp?.userData?.lightAnchors?.[0];
    if (lamp && la) { lamp.updateMatrixWorld(true); L[1].position.fromArray(la.pos).applyMatrix4(lamp.matrixWorld); } else L[1].position.set(-1.4, 1.5, 1.62);
    L[1].color.set('#FFC98A'); L[1].intensity = 2.4; L[1].distance = 5.5;
    L[2].position.set(1.38, 0.85, 1.5); L[2].color.set('#FF7A5A'); L[2].intensity = 0.7; L[2].distance = 2.2;
    L[3].position.set(X0 + 0.5, win.y, win.z); L[3].color.set('#7C94FF'); L[3].intensity = 1.1; L[3].distance = 3.2;
    L[4].position.set(0.3, 1.9, -2.6); L[4].color.set('#FF9A50'); L[4].intensity = 0.35; L[4].distance = 4;

    // ---- dust motes in the TV light
    const N = 90, pos = new Float32Array(N * 3), seed = new Float32Array(N * 4);
    for (let i = 0; i < N; i++) {
      pos[i * 3] = (Math.random() - 0.5) * 1.6; pos[i * 3 + 1] = 0.45 + Math.random() * 1.2; pos[i * 3 + 2] = -0.6 + Math.random() * 1.5;
      for (let k = 0; k < 4; k++) seed[i * 4 + k] = Math.random();
    }
    const dg = new THREE.BufferGeometry();
    dg.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    dg.setAttribute('seed', new THREE.BufferAttribute(seed, 4));
    const dm = new THREE.ShaderMaterial({
      uniforms: { uTime: M.uniforms.uTime, uSize: { value: 11 * Math.min(1.5, window.devicePixelRatio || 1) }, uColor: { value: new THREE.Color('#FFE2B8') }, uAlpha: { value: 0.22 } },
      vertexShader: DUST_VERT, fragmentShader: DUST_FRAG, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    });
    const dust = new THREE.Points(dg, dm);
    dust.frustumCulled = false;
    root.add(dust);
    R.dust = dm;

    // ---- cameras
    R.camera = new THREE.PerspectiveCamera(40, innerWidth / innerHeight, 0.05, 60);
    R.poses = {
      title: { pos: V3(0.5, 1.42, -2.35), target: V3(0.02, 1.0, 1.4), fov: 42 },
      select: { pos: V3(-0.06, 1.02, -0.95), target: V3(-0.1, 0.9, 1.5), fov: 38 },
      screen: { pos: V3(R.screenWorld.x, R.screenWorld.y, R.screenWorld.z - 0.34), target: R.screenWorld.clone(), fov: 44 },
      review: { pos: V3(R.screenWorld.x, R.screenWorld.y, R.screenWorld.z - 1.25), target: R.screenWorld.clone(), fov: 34 },
    };
    scene.add(R.camera);
    this._room = R;
    // compile off the critical path (the first frame would otherwise stall)
    try { g.renderer.compileAsync?.(scene, R.camera)?.catch?.(() => {}); } catch { /* optional */ }
    this._raycaster = new THREE.Raycaster();
  }

  // Same light counts as core/lights.js (1 hemisphere, 2 directional with 1 shadow, 8 points) so every shared material
  // reuses the station's shader programs instead of compiling a second variant.
  _lightRig(scene, o) {
    const hemi = new THREE.HemisphereLight(o.sky, o.ground, o.hemi);
    const key = new THREE.DirectionalLight(o.key, o.keyI);
    key.castShadow = true;
    const s = key.shadow;
    s.mapSize.set(1024, 1024);
    s.camera.left = -4.5; s.camera.right = 4.5; s.camera.top = 4.5; s.camera.bottom = -4.5;
    s.camera.near = 0.5; s.camera.far = 24;
    s.bias = -0.0006; s.normalBias = 0.03; s.radius = 3;
    const fill = new THREE.DirectionalLight(o.fill, o.fillI);
    fill.position.set(1.5, 1.2, -2);
    const points = [];
    for (let i = 0; i < 8; i++) { const p = new THREE.PointLight('#ffffff', 0, 6, 1.5); points.push(p); scene.add(p); }
    scene.add(hemi, key, key.target, fill);
    return { hemi, key, fill, points };
  }

  // While this scene renders: full colour (no pre-power grade, no Sign-On wave), heroes never dither-fade.
  _fullColor(scene) {
    const U = this.game.mats.uniforms, saved = {};
    const KEYS = ['uSatEnv', 'uAmber', 'uWaveRadius', 'uHeroFade'];
    const WANT = { uSatEnv: 1, uAmber: 0, uWaveRadius: -1, uHeroFade: 1 };
    scene.onBeforeRender = () => { for (const k of KEYS) if (U[k]) { saved[k] = U[k].value; U[k].value = WANT[k]; } };
    scene.onAfterRender = () => { for (const k of KEYS) if (U[k] && k in saved) U[k].value = saved[k]; };
  }

  _card(id, opts = {}) {
    try { return this.game.cards.get(id, opts); } catch { return null; }
  }

  _popcorn(g, pos) {
    const grp = new THREE.Group();
    const bowl = new THREE.Mesh(K.lathe([[0, 0], [0.06, 0], [0.11, 0.035], [0.13, 0.085], [0.125, 0.09], [0.1, 0.05], [0, 0.045]], { seg: 20, round: 0.01 }),
      g.mats.toon('#E23B3B', { rough: 0.35, rim: 0.3 }));
    bowl.castShadow = true;
    grp.add(bowl);
    const pop = g.mats.toon('#FFF3D0', { rough: 0.9, rim: 0.45, rimColor: '#FFE6A0', wrap: 0.8 });
    const pg = new THREE.IcosahedronGeometry(0.022, 1);
    for (let i = 0; i < 26; i++) {
      const a = i * 2.4, r = 0.02 + (i % 7) * 0.013;
      const m = new THREE.Mesh(pg, pop);
      m.position.set(Math.cos(a) * r, 0.075 + (i % 3) * 0.014 + (0.1 - r) * 0.25, Math.sin(a) * r);
      m.rotation.set(i, i * 1.7, i * 0.3);
      m.scale.setScalar(0.8 + (i % 4) * 0.12);
      grp.add(m);
    }
    grp.position.set(pos[0], pos[1], pos[2]);
    return grp;
  }

  _nightTexture() {
    const c = canvas(512, 384), x = c.getContext('2d');
    const gr = x.createLinearGradient(0, 0, 0, 384);
    gr.addColorStop(0, '#0A0E2E'); gr.addColorStop(0.55, '#1B1E4A'); gr.addColorStop(1, '#3A3478');
    x.fillStyle = gr; x.fillRect(0, 0, 512, 384);
    let s = 7;
    const rnd = () => ((s = (s * 16807) % 2147483647) / 2147483647);
    for (let i = 0; i < 90; i++) { x.fillStyle = `rgba(255,244,214,${0.3 + rnd() * 0.7})`; const r = rnd() * 1.4 + 0.4; x.beginPath(); x.arc(rnd() * 512, rnd() * 230, r, 0, 7); x.fill(); }
    const mg = x.createRadialGradient(360, 90, 10, 360, 90, 110);
    mg.addColorStop(0, 'rgba(255,244,214,.55)'); mg.addColorStop(1, 'rgba(255,244,214,0)');
    x.fillStyle = mg; x.fillRect(200, 0, 312, 220);
    x.fillStyle = '#FFF4D6'; x.beginPath(); x.arc(360, 90, 30, 0, 7); x.fill();
    x.fillStyle = '#1B1E4A'; x.beginPath(); x.arc(372, 82, 26, 0, 7); x.fill();
    // skyline + tower
    x.fillStyle = '#120E26';
    let bx = 0;
    while (bx < 512) { const w = 26 + rnd() * 40, h = 40 + rnd() * 90; x.fillRect(bx, 384 - h, w, h); for (let wy = 384 - h + 8; wy < 380; wy += 12) for (let wx = bx + 5; wx < bx + w - 5; wx += 9) if (rnd() < 0.18) { x.fillStyle = '#FFC98A'; x.fillRect(wx, wy, 4, 5); x.fillStyle = '#120E26'; } bx += w + 2; }
    x.strokeStyle = '#161230'; x.lineWidth = 3;
    x.beginPath(); x.moveTo(150, 384); x.lineTo(170, 170); x.lineTo(190, 384); x.moveTo(158, 300); x.lineTo(182, 300); x.moveTo(163, 240); x.lineTo(177, 240); x.stroke();
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    return t;
  }

  _updateRoom(dt) {
    const R = this._room;
    if (!R) return;
    const t = this.game.time.realNow;
    // camera: blend between poses + a slow handheld drift
    const A = R.poses[this._camFrom] || R.poses.title, B = R.poses[this._camTo] || R.poses.title;
    const k = this.mode === 'tunein' ? this._camBlend : easeInOut(clamp(this._camBlend, 0, 1));
    const cam = R.camera;
    cam.position.lerpVectors(A.pos, B.pos, k);
    _v.lerpVectors(A.target, B.target, k);
    const drift = this.mode === 'tunein' ? 0.2 : 1;
    cam.position.x += Math.sin(t * 0.37) * 0.018 * drift;
    cam.position.y += Math.sin(t * 0.53 + 1.3) * 0.012 * drift;
    if (this.mode === 'title') cam.position.z += Math.min(this._t, 30) * 0.008;
    _v.x += Math.sin(t * 0.29 + 0.7) * 0.01 * drift;
    cam.lookAt(_v);
    const aspect = innerWidth / Math.max(1, innerHeight);
    let fov = lerp(A.fov, B.fov, k);
    // keep the TV framed on narrow screens (fit the horizontal field instead)
    if (aspect < 1.6) fov = THREE.MathUtils.radToDeg(2 * Math.atan(Math.tan(THREE.MathUtils.degToRad(fov) / 2) * 1.6 / aspect));
    if (cam.fov !== fov || cam.aspect !== aspect) { cam.fov = fov; cam.aspect = aspect; cam.updateProjectionMatrix(); }
    // dial spring toward its detent (overshoot = the clack), plus a punch when clicked
    const P = R.parts;
    if (P.dial) {
      R.dialVel += ((R.dialTarget - R.dialAngle) * 420 - R.dialVel * 24) * dt;
      R.dialAngle += R.dialVel * dt;
      P.dial.rotation.z = R.dialAngle;
      const hov = this._hover === 'dial' ? 1 : 0;
      this._dialPunch = Math.max(0, (this._dialPunch || 0) - dt * 5);
      P.dial.scale.setScalar(1 + hov * 0.06 + Math.sin(this._dialPunch * Math.PI) * 0.1);
    }
    // rabbit ears breathe a little
    if (P.earL) P.earL.rotation.x = 0.06 + Math.sin(t * 1.3) * 0.02;
    if (P.earR) P.earR.rotation.x = 0.2 + Math.sin(t * 1.1 + 1) * 0.02;
    if (R.beacon) R.beacon.visible = (t % 1.6) < 0.8;
    // lava blobs drift if the prop exposes them
    const blobs = R.lava?.userData?.parts?.blobs;
    if (blobs && blobs.children) blobs.children.forEach((b, i) => { b.position.y = (b.userData.y0 ??= b.position.y) + Math.sin(t * 0.4 + i * 2.1) * 0.05; });
    const L = R.lights.points;
    L[0].color.lerp(R.glow, 1 - Math.exp(-dt * 8));
    L[0].intensity = lerp(L[0].intensity, R.glowI, 1 - Math.exp(-dt * 12));
    L[1].intensity = 2.4 + Math.sin(t * 7.3) * 0.03;
  }

  _tvGlow(color, intensity) {
    const R = this._room;
    if (!R) return;
    R.glow.set(color).lerp(_warm, 0.45); // a soft wash: the picture tints the room, it does not repaint the TV
    R.glowI = intensity * 0.8;
  }

  // Picks what the mouse is over in the select view: 'dial' | 'screen' | null.
  _pick(cx, cy) {
    const R = this._room;
    if (!R || !R.active || !this._raycaster) return null;
    _ndc.set((cx / innerWidth) * 2 - 1, -(cy / innerHeight) * 2 + 1);
    this._raycaster.setFromCamera(_ndc, R.camera);
    const P = R.parts;
    const ray = this._raycaster.ray;
    if (P.dial) {
      P.dial.getWorldPosition(_v);
      if (ray.distanceSqToPoint(_v) < 0.11 * 0.11) return 'dial';
    }
    if (P.screen) {
      const hit = this._raycaster.intersectObject(P.glass || P.screen, false)[0] || this._raycaster.intersectObject(P.screen, false)[0];
      if (hit) return 'screen';
    }
    return null;
  }

  // -------------------------------------------------------------------------------------------- TV compositing
  _buildTv() {
    const g = this.game;
    const W = 640, H = 480;
    const rtOut = new THREE.WebGLRenderTarget(W, H, { type: THREE.HalfFloatType, depthBuffer: false });
    rtOut.texture.generateMipmaps = false;
    rtOut.texture.minFilter = THREE.LinearFilter;
    rtOut.texture.name = 'menu:tv';
    const ui = canvas(W, H);
    const uiTex = new THREE.CanvasTexture(ui);
    uiTex.colorSpace = THREE.SRGBColorSpace;
    uiTex.minFilter = THREE.LinearFilter; uiTex.generateMipmaps = false;
    const titleTex = new THREE.CanvasTexture(this._titleCanvas(W, H));
    titleTex.colorSpace = THREE.SRGBColorSpace;
    const sunrise = new THREE.CanvasTexture(this._sunriseCanvas(W, H));
    sunrise.colorSpace = THREE.SRGBColorSpace;
    const u = {
      tPic: { value: titleTex }, tUI: { value: uiTex }, uTime: g.mats.uniforms.uTime,
      uSnow: { value: 1 }, uRoll: { value: 0 }, uJitter: { value: 0 }, uPic: { value: 0 }, uUI: { value: 0 }, uBright: { value: 1 }, uSeam: { value: 0 },
    };
    const mat = new THREE.ShaderMaterial({ uniforms: u, vertexShader: COMP_VERT, fragmentShader: COMP_FRAG, depthTest: false, depthWrite: false });
    const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), mat);
    quad.frustumCulled = false;
    const scene = new THREE.Scene();
    scene.add(quad);
    const cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    const TV = { rtOut, ui, uiCtx: ui.getContext('2d'), uiTex, titleTex, sunrise, u, scene, cam, pic: titleTex };
    this._unPre = g.render?.addPrePass?.((r) => this._prePass(r));
    return TV;
  }

  _tvMode(m) { this._tvState = m; }

  // Seats Telly's CRT canvas in the bezel opening (title, select and the ending's room). The telly prop builds it as a
  // diorama for the glove: the canvas sits ~0.21 m behind the cream faceplate. From the title's three-quarter view that
  // tunnel showed as grey/black bands beside and under the picture, so the picture looked shifted out of its frame.
  // And the dark tunnel liner's front ring was coplanar with the faceplate front (same plane, same merged draw):
  // z-fighting, the jagged black flicker just outside the brass lip. Here, on the menu's own Telly only:
  //   - the liner's front ring is tucked 1 cm back, inside the faceplate (nothing coplanar is left on show);
  //   - the canvas sits just behind the bezel (its overscan edge hidden in the faceplate/liner, the visible edge under
  //     the brass lip) with a shallow dome that stays behind the lip;
  //   - while the glove is out (ending) it eases back to the diorama depth + dome so the arm still comes out of the
  //     tunnel (_seatUpdate, every frame from _prePass).
  _seatScreen(R, telly) {
    const P = R.parts, scr = P.screen, rig = telly?.userData?.rig?.screen, body = P.body;
    if (!scr || !rig || !body) return;
    const [sx, sy] = rig.center, hw = rig.w / 2, hh = rig.h / 2;
    const ring = (x, y) => Math.max(Math.abs(x - sx) - hw, Math.abs(y - sy) - hh); // box distance to the window edge
    // the liner: dark vertex-coloured faces around the window, in body space (merged per material by finishRig)
    let front = Infinity;
    const hits = [];
    for (const m of body.children) {
      const pa = m.isMesh && m.material?.vertexColors && m.geometry.attributes.position, ca = pa && m.geometry.attributes.color;
      if (!ca) continue;
      const idx = [];
      for (let i = 0; i < pa.count; i++) {
        const d = ring(pa.getX(i), pa.getY(i));
        if (d < -0.05 || d > 0.03 || pa.getZ(i) > rig.center[2] - 0.05) continue;
        if (ca.getX(i) + ca.getY(i) + ca.getZ(i) > 0.3 || ca.getZ(i) <= ca.getX(i)) continue; // dark + blue-leaning: the plum liner, not cream/walnut
        idx.push(i);
        front = Math.min(front, pa.getZ(i));
      }
      if (idx.length) hits.push([m, idx]);
    }
    if (!Number.isFinite(front)) return;
    for (const [m, idx] of hits) {
      m.geometry = m.geometry.clone(); // our copy: the prop's buffers stay untouched
      const pa = m.geometry.attributes.position;
      let n = 0;
      for (const i of idx) if (pa.getZ(i) < front + 0.0045) { pa.setZ(i, pa.getZ(i) + 0.01); n++; } // front cap + bevel
      pa.needsUpdate = true;
      m.geometry.computeBoundingSphere();
      m.geometry.computeBoundingBox();
      R.linerTucked = (R.linerTucked || 0) + n;
    }
    const U = scr.material?.uniforms;
    R.seat = {
      diorama: scr.position.z, flush: front + 0.0085, // faceplate front + 8.5 mm: just in front of the faceplate/liner hole walls
      bulge0: U?.uBulge ? U.uBulge.value : 0, bulge: 0.012, // dome apex 3.5 mm proud of the faceplate, 7.5 mm behind the lip
      k: 1, last: -1,
    };
    this._seatUpdate(R, true);
  }

  _seatUpdate(R, snap = false) {
    const S = R.seat, P = R.parts, scr = P?.screen;
    if (!S || !scr) return;
    const want = (P.arm?.visible || P.glove?.visible) ? 0 : 1;
    const now = this.game.time?.realNow ?? 0;
    const dt = S.last < 0 ? 0 : Math.min(0.1, Math.max(0, now - S.last));
    S.last = now;
    if (snap) S.k = want;
    else if (S.k !== want) S.k = want > S.k ? Math.min(1, S.k + dt / 0.25) : Math.max(0, S.k - dt / 0.12);
    const e = easeInOut(S.k);
    scr.position.z = lerp(S.diorama, S.flush, e);
    const U = scr.material?.uniforms;
    if (U?.uBulge) U.uBulge.value = lerp(S.bulge0, S.bulge, e);
  }

  _prePass(renderer) {
    const R = this._room;
    if (!R || !R.active || (!this.mode && !R.externalCam)) return;
    this._seatUpdate(R);
    const TV = R.tv, prev = renderer.getRenderTarget();
    try {
      if (this._tvState === 'channel' && this._sets && (this.mode === 'select' || this.mode === 'tunein')) {
        renderer.setRenderTarget(this._sets.rt);
        renderer.clear();
        renderer.render(this._sets.scene, this._sets.cam);
      }
      TV.u.tPic.value = TV.pic || TV.titleTex;
      renderer.setRenderTarget(TV.rtOut);
      renderer.render(TV.scene, TV.cam);
    } finally {
      renderer.setRenderTarget(prev);
    }
  }

  _titleCanvas(W, H) {
    const c = canvas(W, H), x = c.getContext('2d');
    const bg = x.createRadialGradient(W / 2, H * 0.45, 20, W / 2, H * 0.5, W * 0.7);
    bg.addColorStop(0, '#4A2A6E'); bg.addColorStop(0.55, '#24164A'); bg.addColorStop(1, '#0E0A22');
    x.fillStyle = bg; x.fillRect(0, 0, W, H);
    x.save(); x.translate(W / 2, H * 0.46);
    for (let i = 0; i < 24; i++) {
      x.rotate(Math.PI / 12);
      x.fillStyle = i % 2 ? 'rgba(255,120,60,.10)' : 'rgba(255,200,90,.07)';
      x.beginPath(); x.moveTo(0, 0); x.lineTo(W, -46); x.lineTo(W, 46); x.closePath(); x.fill();
    }
    x.restore();
    const barsY = H * 0.86;
    PAL.BARS.forEach((col, i) => { x.fillStyle = col; x.globalAlpha = 0.85; x.fillRect((i * W) / PAL.BARS.length, barsY, W / PAL.BARS.length + 1, H * 0.035); });
    x.globalAlpha = 1;
    // cards.drawTo draws at 0,0 scaled to w x h: translate into place first
    x.save();
    x.translate(W * 0.03, H * 0.12);
    try { this.game.cards.drawTo(x, 'logo_dead_air', W * 0.94, W * 0.47, 0); } catch { /* cards missing: the gradient stays */ }
    x.restore();
    return c;
  }

  _sunriseCanvas(W, H) {
    const c = canvas(W, H), x = c.getContext('2d');
    const gr = x.createLinearGradient(0, 0, 0, H);
    gr.addColorStop(0, '#FF7E5F'); gr.addColorStop(0.55, '#FFB36B'); gr.addColorStop(1, '#FFE3A3');
    x.fillStyle = gr; x.fillRect(0, 0, W, H);
    x.save(); x.translate(W / 2, H * 0.78);
    for (let i = 0; i < 18; i++) { x.rotate(Math.PI / 9); x.fillStyle = 'rgba(255,255,255,.12)'; x.beginPath(); x.moveTo(0, 0); x.lineTo(W, -40); x.lineTo(W, 40); x.closePath(); x.fill(); }
    x.restore();
    x.fillStyle = '#FFF4D6'; x.beginPath(); x.arc(W / 2, H * 0.78, H * 0.2, Math.PI, 0); x.fill();
    x.fillStyle = '#8A3A2A'; x.fillRect(0, H * 0.78, W, H * 0.22);
    x.strokeStyle = '#5A2218'; x.lineWidth = 5;
    x.beginPath(); x.moveTo(W * 0.72, H * 0.78); x.lineTo(W * 0.76, H * 0.3); x.lineTo(W * 0.8, H * 0.78); x.stroke();
    return c;
  }

  // Overlay drawn into the TV picture: the OSD channel number (fades after 2.5 s), the station bug and the chyron.
  _drawUI(t) {
    const TV = this._room.tv, x = TV.uiCtx, W = TV.ui.width, H = TV.ui.height;
    const C = CHANNELS[this._chIdx], hero = HEROES.find((h) => h.id === C.hero);
    const osd = t < 2.4 ? 1 : clamp(1 - (t - 2.4) / 0.5, 0, 1);
    const cp = clamp((t - 0.38) / 0.42, 0, 1);
    const chyX = t < 0.38 ? -1 : 1 - easeOutBack(cp, 1.3);
    const key = `${this._chIdx}|${osd.toFixed(2)}|${chyX.toFixed(3)}`;
    if (key === TV.uiKey) return;
    TV.uiKey = key;
    x.clearRect(0, 0, W, H);
    // OSD channel number, top right (VT323 green with a dark drop)
    if (osd > 0 && t > 0.05) {
      x.globalAlpha = osd;
      x.font = `92px ${FONTS.tape}`;
      x.textAlign = 'right'; x.textBaseline = 'top';
      x.fillStyle = 'rgba(10,20,10,.75)'; x.fillText(String(C.ch), W - 34 + 4, 22 + 4);
      x.fillStyle = '#5CFF6E'; x.fillText(String(C.ch), W - 34, 22);
      x.globalAlpha = 1;
    }
    // station bug bottom right
    x.globalAlpha = 0.55;
    x.beginPath(); x.arc(W - 46, H - 44, 20, 0, 7); x.fillStyle = '#F4F1E8'; x.fill();
    x.lineWidth = 4; x.strokeStyle = '#E23B3B'; x.stroke();
    x.font = `18px ${FONTS.hud}`; x.textAlign = 'center'; x.textBaseline = 'middle'; x.fillStyle = '#2F5BD3'; x.fillText('13', W - 46, H - 43);
    x.globalAlpha = 1;
    // chyron (lower third)
    if (chyX > -1) {
      x.save();
      x.translate(chyX * (W * 0.9), 0);
      const y0 = H - 148, bw = W * 0.8;
      const gr = x.createLinearGradient(0, y0, 0, y0 + 64);
      gr.addColorStop(0, '#F59A48'); gr.addColorStop(0.5, '#D9602B'); gr.addColorStop(1, '#A8401E');
      x.fillStyle = 'rgba(20,8,4,.35)'; this._rr(x, 30, y0 + 6, bw, 64, 32); x.fill();
      x.fillStyle = gr; this._rr(x, 24, y0, bw, 64, 32); x.fill();
      x.fillStyle = 'rgba(255,255,255,.28)'; x.fillRect(48, y0 + 5, bw - 60, 3);
      x.fillStyle = '#4A2616'; this._rr(x, 60, y0 + 60, bw * 0.78, 30, 12); x.fill();
      x.font = `40px ${FONTS.logo}`; x.textAlign = 'left'; x.textBaseline = 'middle';
      x.lineJoin = 'round'; x.lineWidth = 6; x.strokeStyle = '#5A2210';
      const name = hero ? hero.name : C.hero;
      x.strokeText(name, 50, y0 + 31); x.fillStyle = '#FFFBEA'; x.fillText(name, 50, y0 + 31);
      x.font = `17px ${FONTS.sign}`; x.fillStyle = '#FFD27A';
      x.fillText(C.role, 76, y0 + 76);
      x.restore();
    }
    TV.uiTex.needsUpdate = true;
  }

  _rr(x, px, py, w, h, r) {
    x.beginPath();
    x.moveTo(px + r, py); x.lineTo(px + w - r, py); x.quadraticCurveTo(px + w, py, px + w, py + r);
    x.lineTo(px + w, py + h - r); x.quadraticCurveTo(px + w, py + h, px + w - r, py + h);
    x.lineTo(px + r, py + h); x.quadraticCurveTo(px, py + h, px, py + h - r);
    x.lineTo(px, py + r); x.quadraticCurveTo(px, py, px + r, py);
    x.closePath();
  }

  // -------------------------------------------------------------------------------------------- hero sets (on TV)
  _ensureSets() {
    if (this._sets) return this._sets;
    const g = this.game;
    const scene = new THREE.Scene();
    scene.name = 'menu:sets';
    scene.background = new THREE.Color('#1E1530');
    scene.fog = new THREE.Fog('#1E1530', 40, 90);
    const lights = this._lightRig(scene, { sky: '#FFE8D0', ground: '#4A3048', hemi: 0.85, key: '#FFE4C2', keyI: 1.9, fill: '#9FB6FF', fillI: 0.35 });
    lights.key.position.set(2.2, 4.5, 4);
    lights.key.target.position.set(0, 0.8, 0);
    this._fullColor(scene);
    const rt = new THREE.WebGLRenderTarget(640, 480, { type: THREE.HalfFloatType, samples: 4 });
    rt.texture.generateMipmaps = false;
    rt.texture.minFilter = THREE.LinearFilter;
    rt.texture.name = 'menu:set';
    const cam = new THREE.PerspectiveCamera(25, 4 / 3, 0.1, 40);
    cam.position.set(0.12, 1.3, 4.5);
    cam.lookAt(0.04, 1.02, 0);
    this._sets = { scene, lights, rt, cam, groups: {}, heroes: {}, cur: -1 };
    return this._sets;
  }

  // Builds the other channels' sets one at a time while the viewer watches a settled channel (no hitch later).
  _prebuild(t) {
    const S = this._sets;
    if (!S || t < 0.9 || S.prebuilt) return;
    const now = this.game.time.realNow;
    if (now - (S.lastBuild || 0) < 0.35) return;
    const next = CHANNELS.find((c) => !S.groups[c.hero]);
    if (!next) { S.prebuilt = true; return; }
    S.lastBuild = now;
    try { S.groups[next.hero] = this._buildSet(next); } catch (err) { console.error(`[menu] set ${next.hero} failed`, err); S.groups[next.hero] = new THREE.Group(); }
    S.scene.add(S.groups[next.hero]);
    // compile() only walks visible objects: show the new set for the (synchronous) collection pass
    try { this.game.renderer.compileAsync?.(S.scene, S.cam)?.catch?.(() => {}); } catch { /* optional */ }
    S.groups[next.hero].visible = false;
  }

  // Game's progressive boot (behind the title): builds every channel's set (hero, promo card, props) and draws each
  // once, alone, into the set target, so its programs, textures and buffers are warm: the title -> select press
  // and the channel flips no longer build or compile anything (was a ~2.4 s freeze on the key press).
  // A step generator: a yielded Promise is awaited by the caller.
  // Every set is built and its compile started first (the driver compiles the first sets while the next ones are
  // built on the CPU), then each is drawn once.
  *preloadSteps() {
    let S;
    try { S = this._ensureSets(); } catch (err) { console.error('[menu] sets failed', err); return; }
    const r = this.game.renderer;
    const pend = {};
    for (const C of CHANNELS) {
      if (!S.groups[C.hero]) {
        try { S.groups[C.hero] = this._buildSet(C); } catch (err) { console.error(`[menu] set ${C.hero} failed`, err); S.groups[C.hero] = new THREE.Group(); }
        S.scene.add(S.groups[C.hero]);
      }
      yield;
      for (const id in S.groups) S.groups[id].visible = id === C.hero;
      const prev = r.getRenderTarget();
      try {
        r.setRenderTarget(S.rt);
        if (r.compileAsync) pend[C.hero] = r.compileAsync(S.scene, S.cam).catch(() => {});
      } catch { /* optional */ } finally { r.setRenderTarget(prev); }
      for (const id in S.groups) S.groups[id].visible = false;
      yield;
    }
    for (const C of CHANNELS) {
      if (pend[C.hero]) yield pend[C.hero];
      for (const id in S.groups) S.groups[id].visible = id === C.hero;
      // drawn once, alone, a few programs per step (game.warmSteps), then hidden: _showSet shows the tuned set
      try {
        if (typeof this.game.warmSteps === 'function') yield* this.game.warmSteps([S.groups[C.hero]], { scene: S.scene, camera: S.cam, target: S.rt });
      } catch (err) {
        console.warn('[menu] set warm draw', err);
      }
      for (const id in S.groups) S.groups[id].visible = false;
      yield;
    }
    S.prebuilt = true;
  }

  _showSet(idx) {
    let S;
    try { S = this._ensureSets(); } catch (err) { console.error('[menu] sets failed', err); return; }
    const C = CHANNELS[idx];
    if (!S.groups[C.hero]) {
      try { S.groups[C.hero] = this._buildSet(C); } catch (err) { console.error(`[menu] set ${C.hero} failed`, err); S.groups[C.hero] = new THREE.Group(); }
      S.scene.add(S.groups[C.hero]);
    }
    for (const id in S.groups) S.groups[id].visible = id === C.hero;
    S.cur = idx;
    S.scene.background.set(C.bg);
    const L = S.lights.points;
    for (const p of L) p.intensity = 0;
    L[0].position.set(-1.6, 2.6, -1.0); L[0].color.set(C.rim); L[0].intensity = 5; L[0].distance = 6;
    L[1].position.set(1.9, 1.6, 1.6); L[1].color.set('#FFD8B0'); L[1].intensity = 1.6; L[1].distance = 6;
    L[2].position.set(0, 3.2, -1.6); L[2].color.set(C.glow); L[2].intensity = 3; L[2].distance = 5;
    const h = S.heroes[C.hero];
    if (h) { h.poseT = 0; h.art?.face?.setExpression?.('neutral', 1); }
  }

  _buildSet(C) {
    const g = this.game, M = g.mats, S = this._sets;
    const grp = new THREE.Group();
    grp.name = `set:${C.hero}`;
    // backdrop: the show's promo art, gently curved like a cyclorama flat
    const bg = new THREE.PlaneGeometry(5.6, 4.2, 24, 1);
    const p = bg.attributes.position;
    for (let i = 0; i < p.count; i++) p.setZ(i, -0.09 * p.getX(i) * p.getX(i));
    bg.computeVertexNormals();
    const tex = this._card(`promo_${C.hero}`, { osd: false });
    const back = new THREE.Mesh(bg, new THREE.MeshBasicMaterial({ map: tex, color: new THREE.Color(0.82, 0.8, 0.86), fog: false }));
    back.position.set(0, 1.75, -2.0);
    grp.add(back);
    // floor per show
    let floorMat;
    if (C.hero === 'roxy') floorMat = new THREE.MeshBasicMaterial({ map: this._discoFloor(), fog: false });
    else if (C.hero === 'duke') floorMat = M.toon('#ffffff', { rough: 0.45, rim: 0.1, map: this._checker('#2A2E5A', '#3A4FA0') });
    else if (C.hero === 'penny') floorMat = M.toon('#6E7684', { rough: 0.38, metal: 0.55, rim: 0.2 });
    else floorMat = M.toon('#ffffff', { rough: 0.6, rim: 0.1, map: K.tex.wood('#B07A45', { planks: 5 }) });
    const floor = new THREE.Mesh(new THREE.CircleGeometry(3.2, 40), floorMat);
    floor.rotation.x = -Math.PI / 2; floor.receiveShadow = true;
    floor.scale.set(1.3, 1, 1);
    grp.add(floor);
    if (C.hero === 'roxy') S.disco = floorMat;
    const put = (id, pos, rotY = 0, opts = {}) => {
      try { const q = buildProp(id, g, opts); q.position.set(pos[0], pos[1], pos[2]); q.rotation.y = rotY; grp.add(q); return q; } catch (err) { console.warn(`[menu] set prop ${id}`, err); return null; }
    };
    if (C.hero === 'skip') { put('bc_flight_case_stack', [-1.75, 0, -0.9], 0.35); put('bc_cable_coil', [1.1, 0, 0.3], -0.4); }
    else if (C.hero === 'roxy') { const b = put('disco_ball', [0.3, 2.35, -0.9], 0); if (b) b.scale.setScalar(0.7); }
    else if (C.hero === 'penny') { put('hut_tubes', [1.75, 0, -0.9], -0.4); }
    else if (C.hero === 'duke') { put('st_hydrant', [1.5, 0, -0.4], -0.5); put('st_mailbox', [-1.7, 0, -0.8], 0.4); }
    // the hero
    let hero = null;
    try {
      hero = buildHero(C.hero, g);
      hero.group.position.set(0, 0, 0.2);
      hero.group.rotation.y = Math.PI - 0.28;
      hero.group.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.frustumCulled = false; } });
      if (this._unlocked) this._goldBadge(hero);
      grp.add(hero.group);
      hero.poseT = 0;
      S.heroes[C.hero] = hero;
    } catch (err) {
      console.warn(`[menu] hero ${C.hero} failed`, err);
    }
    return grp;
  }

  _heroOnSet() {
    const S = this._sets;
    return S ? S.heroes[CHANNELS[this._chIdx].hero] : null;
  }

  _updateSetScene(dt, t) {
    const S = this._sets;
    if (!S) return;
    const h = S.heroes[CHANNELS[this._chIdx].hero];
    if (h) {
      h.poseT = (h.poseT || 0) + dt;
      // idle a beat, then snap into the signature pose (overshoot), hold it with a breathing idle
      const pt = clamp((h.poseT - 0.35) / 0.38, 0, 1);
      const w = pt <= 0 ? 0 : Math.min(1.08, easeOutBack(pt, 2.2));
      try {
        h.animator.pose(`commercial_${CHANNELS[this._chIdx].hero}`, w);
        h.animator.update(dt, { speed: 0, grounded: true, aimPitch: 0 });
        if (h.poseT > 0.35 && !h.kicked) { h.kicked = true; h.animator.kick?.(0.8); h.art?.face?.setExpression?.('smile', 1); }
        if (h.poseT < 0.1) h.kicked = false;
        h.art?.face?.lookAt?.(S.cam.position);
      } catch (err) { /* keep the menu alive */ }
    }
    if (S.disco && S.disco.map) {
      const step = Math.floor(this.game.time.realNow * 2.2);
      if (step !== S.discoStep) { S.discoStep = step; S.disco.map.offset.x = (step % 4) * 0.25; }
    }
  }

  _discoFloor() {
    const c = canvas(256, 256), x = c.getContext('2d');
    const cols = ['#FF4FA0', '#5FE3FF', '#FFD23A', '#52D24A', '#E3662B', '#D64FD6', '#3A58E4'];
    for (let j = 0; j < 8; j++) for (let i = 0; i < 8; i++) {
      x.fillStyle = (i + j) % 3 === 0 ? '#2A1830' : cols[(i * 3 + j * 5) % cols.length];
      x.fillRect(i * 32 + 1, j * 32 + 1, 30, 30);
    }
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(2, 2);
    return t;
  }

  _checker(a, b) {
    const c = canvas(128, 128), x = c.getContext('2d');
    for (let j = 0; j < 4; j++) for (let i = 0; i < 4; i++) { x.fillStyle = (i + j) % 2 ? a : b; x.fillRect(i * 32, j * 32, 32, 32); }
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    t.repeat.set(5, 5);
    return t;
  }

  _goldBadge(hero) {
    const c = canvas(128, 128), x = c.getContext('2d');
    const gr = x.createRadialGradient(50, 44, 6, 64, 64, 62);
    gr.addColorStop(0, '#FFF1A0'); gr.addColorStop(0.6, '#E8B84A'); gr.addColorStop(1, '#8A5A18');
    x.fillStyle = gr; x.beginPath(); x.arc(64, 64, 60, 0, 7); x.fill();
    x.lineWidth = 6; x.strokeStyle = '#6A4010'; x.stroke();
    x.font = `64px ${FONTS.hud}`; x.textAlign = 'center'; x.textBaseline = 'middle'; x.fillStyle = '#6A3A10'; x.fillText('13', 64, 68);
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    const m = new THREE.Mesh(new THREE.CircleGeometry(0.06, 24), this.game.mats.toon('#ffffff', { map: t, rough: 0.3, metal: 0.4, rim: 0.4, keepColor: true }));
    const anchor = hero.parts?.torso || hero.slots?.neck;
    if (!anchor) return;
    m.position.set(0.08, 0.02, -0.17);
    m.rotation.y = Math.PI;
    anchor.add(m);
  }

  // -------------------------------------------------------------------------------------------- pause
  _pauseItems() {
    return [
      { ch: 2, label: 'RESUME', act: () => this.game.resume() },
      { ch: 4, label: 'OPTIONS', act: () => this._pauseSub('options') },
      { ch: 5, label: 'CONTROLS', act: () => this._pauseSub('controls') },
      { ch: 7, label: 'QUIT', act: () => this._quit() },
    ];
  }

  _quit() {
    const P = this._pause;
    if (P.quitArm < 0) { P.quitArm = 2.5; this.game.audio?.play?.('ui_denied', { vol: 0.5 }); this._renderPause(); return; }
    this.game.audio?.play?.('ui_menu_clack');
    this.game.input?.exitLock?.();
    this.hideAll();
    this.game.setState('menu');
    this.showTitle();
  }

  _pauseSub(sub) {
    const P = this._pause;
    P.sub = sub;
    P.osel = 0;
    this.game.audio?.play?.('ui_menu_clack', { vol: 0.7 });
    this._renderPause();
  }

  _optRows() {
    const o = this.options;
    const rows = [
      { key: 'sensitivity', label: 'MOUSE SENSITIVITY', type: 'slider', min: 0.2, max: 3, step: 0.05, fmt: (v) => v.toFixed(2) },
      { key: 'padSens', label: 'PAD SENSITIVITY', type: 'slider', min: 0.3, max: 2.5, step: 0.05, fmt: (v) => v.toFixed(2) },
      { key: 'invertY', label: 'INVERT Y', type: 'toggle' },
      { key: 'fov', label: 'FIELD OF VIEW', type: 'slider', min: 60, max: 90, step: 1, fmt: (v) => `${Math.round(v)}°` },
      { key: 'aim', label: 'AIM', type: 'seg', opts: [['hold', 'HOLD'], ['toggle', 'TOGGLE']] },
      { key: 'sprint', label: 'SPRINT', type: 'seg', opts: [['hold', 'HOLD'], ['toggle', 'TOGGLE']] },
      { key: 'aimAssist', label: 'PAD AIM ASSIST', type: 'toggle' },
      { key: 'rumble', label: 'PAD VIBRATION', type: 'toggle' },
      ...VOL_ROWS.map(([k, label]) => ({ key: `vol.${k}`, label, type: 'slider', min: 0, max: 1, step: 0.05, fmt: (v) => `${Math.round(v * 100)}` })),
      { key: 'quality', label: 'PICTURE QUALITY', type: 'seg', opts: [['low', 'LOW'], ['medium', 'MED'], ['high', 'HIGH']] },
      { key: 'crt', label: 'CRT VIGNETTE', type: 'toggle' },
      { key: 'back', label: '◀ BACK', type: 'back' },
    ];
    for (const r of rows) r.value = r.key.startsWith('vol.') ? o.vol[r.key.slice(4)] : o[r.key];
    return rows;
  }

  _renderPause() {
    const P = this._pause, d = this.dom;
    if (P.sub === 'main') {
      d.gpanel.style.display = 'none';
      d.pmenu.style.display = '';
      const items = this._pauseItems();
      d.pmenu.innerHTML = items.map((it, i) => {
        const quit = it.label === 'QUIT' && P.quitArm > 0;
        return `<button class="pitem${i === P.sel ? ' sel' : ''}${quit ? ' warn' : ''}" data-i="${i}"><span class="chn">${it.ch}</span>${quit ? 'QUIT? SURE' : it.label}</button>`;
      }).join('');
      d.pmenu.querySelectorAll('.pitem').forEach((b) => {
        b.addEventListener('mouseenter', () => { const i = +b.dataset.i; if (i !== P.sel) { P.sel = i; this._tick(); this._renderPause(); } });
        b.addEventListener('click', () => { P.sel = +b.dataset.i; this._pauseItems()[P.sel].act(); });
      });
      return;
    }
    d.pmenu.style.display = 'none';
    d.gpanel.style.display = '';
    if (P.sub === 'controls') {
      const pad = this._padMode();
      d.gpanel.innerHTML = `<h2>Controls<i>WZTV TV GUIDE</i></h2><div class="ctl"><div></div><div class="hd${pad ? '' : ' cur'}">KEYBOARD · MOUSE</div><div class="hd${pad ? ' cur' : ''}">XBOX CONTROLLER</div>${CONTROLS.map(([a, keys, note, pads, pnote], i) =>
        `${i && i % 4 === 0 ? '<div class="sep"></div>' : ''}<div>${a}${note ? `<span class="nt">${note}</span>` : ''}</div><div class="k">${keys.map((k) => `<span class="kc">${k}</span>`).join('')}</div>`
        + `<div class="p">${pnote ? `<span class="pn">${pnote}</span>` : ''}${(pads || []).map(padGlyph).join('')}</div>`).join('')}</div>
        <div class="orow back sel" data-back="1">◀ BACK</div>`;
      d.gpanel.querySelector('[data-back]').addEventListener('click', () => this._pauseSub('main'));
      return;
    }
    const rows = this._optRows();
    d.gpanel.innerHTML = `<h2>Options<i>ADJUST YOUR SET</i></h2>` + rows.map((r, i) => {
      let ctl = '';
      if (r.type === 'slider') {
        const f = (r.value - r.min) / (r.max - r.min);
        ctl = `<div class="sld" data-i="${i}"><div class="tr"></div><div class="fi" style="width:${f * 100}%"></div><div class="kn" style="left:${f * 100}%"></div></div><div class="val">${r.fmt(r.value)}</div>`;
      } else if (r.type === 'toggle') {
        ctl = `<div class="seg" data-i="${i}"><b class="${!r.value ? 'on' : ''}" data-v="0">OFF</b><b class="${r.value ? 'on' : ''}" data-v="1">ON</b></div>`;
      } else if (r.type === 'seg') {
        ctl = `<div class="seg" data-i="${i}">${r.opts.map(([v, l]) => `<b class="${r.value === v ? 'on' : ''}" data-v="${v}">${l}</b>`).join('')}</div>`;
      }
      return `<div class="orow${r.type === 'back' ? ' back' : ''}${i === P.osel ? ' sel' : ''}" data-row="${i}"><span class="lab">${r.label}</span>${ctl}</div>`;
    }).join('');
    d.gpanel.querySelectorAll('.orow').forEach((rowEl) => {
      const i = +rowEl.dataset.row;
      rowEl.addEventListener('mouseenter', () => { if (P.osel !== i) { P.osel = i; this._highlightRow(); } });
      if (rows[i].type === 'back') rowEl.addEventListener('click', () => this._pauseSub('main'));
    });
    d.gpanel.querySelectorAll('.seg b').forEach((b) => b.addEventListener('click', (e) => {
      const i = +b.parentElement.dataset.i, r = rows[i];
      const v = b.dataset.v;
      this._setRow(r, r.type === 'toggle' ? v === '1' : v);
      e.stopPropagation();
    }));
    d.gpanel.querySelectorAll('.sld').forEach((s) => s.addEventListener('mousedown', (e) => {
      const i = +s.dataset.i;
      this._drag = { row: rows[i], el: s };
      this._dragTo(e.clientX);
      e.stopPropagation();
    }));
  }

  _highlightRow() {
    const P = this._pause;
    this.dom.gpanel.querySelectorAll('.orow').forEach((r) => r.classList.toggle('sel', +r.dataset.row === P.osel));
    this._tick();
  }

  _dragTo(clientX) {
    const D = this._drag;
    if (!D) return;
    const rect = D.el.getBoundingClientRect();
    const f = clamp((clientX - rect.left) / Math.max(1, rect.width), 0, 1);
    const r = D.row;
    const v = Math.round((r.min + f * (r.max - r.min)) / r.step) * r.step;
    this._setRow(r, clamp(v, r.min, r.max), true);
  }

  _setRow(r, v, fromDrag = false) {
    const cur = r.key.startsWith('vol.') ? this.options.vol[r.key.slice(4)] : this.options[r.key];
    if (cur === v) return;
    this.setOption(r.key, v);
    if (r.type === 'slider') {
      const now = performance.now();
      if (now - (this._sldSnd || 0) > 70) { this._sldSnd = now; this.game.audio?.play?.('ui_points_flip', { vol: 0.5 }); }
    } else this.game.audio?.play?.('ui_prompt');
    // refresh just this row's visuals (keep the drag element alive)
    const P = this._pause;
    if (fromDrag && this._drag) {
      const f = (v - r.min) / (r.max - r.min);
      const s = this._drag.el;
      s.querySelector('.fi').style.width = `${f * 100}%`;
      s.querySelector('.kn').style.left = `${f * 100}%`;
      const val = s.parentElement.querySelector('.val');
      if (val) val.textContent = r.fmt(v);
      return;
    }
    const keep = P.osel;
    this._renderPause();
    P.osel = keep;
  }

  _pauseKey(e) {
    const P = this._pause, c = e.code;
    const up = c === 'KeyW' || c === 'ArrowUp', down = c === 'KeyS' || c === 'ArrowDown';
    const left = c === 'KeyA' || c === 'ArrowLeft', right = c === 'KeyD' || c === 'ArrowRight';
    const ok = c === 'Enter' || c === 'KeyE' || c === 'Space' || c === 'NumpadEnter';
    if (c === 'Escape') {
      // Esc backs out of a sub-card; on the main card it resumes (Input would too; we own it here)
      e.stopImmediatePropagation(); e.preventDefault();
      if (P.sub !== 'main') this._pauseSub('main'); else this.game.resume();
      return;
    }
    if (P.sub === 'main') {
      const n = this._pauseItems().length;
      if (up || down) { P.sel = (P.sel + (up ? -1 : 1) + n) % n; this._tick(); this._renderPause(); }
      else if (ok) { e.preventDefault(); this._pauseItems()[P.sel].act(); }
      return;
    }
    if (P.sub === 'controls') { if (ok) this._pauseSub('main'); return; }
    const rows = this._optRows();
    if (up || down) { P.osel = (P.osel + (up ? -1 : 1) + rows.length) % rows.length; this._highlightRow(); return; }
    const r = rows[P.osel];
    if (!r) return;
    if (r.type === 'back') { if (ok) this._pauseSub('main'); return; }
    if (r.type === 'slider' && (left || right)) this._setRow(r, clamp(Math.round((r.value + (right ? r.step : -r.step) * (e.shiftKey ? 4 : 1)) / r.step) * r.step, r.min, r.max));
    else if (r.type === 'toggle' && (left || right || ok)) this._setRow(r, !r.value);
    else if (r.type === 'seg' && (left || right || ok)) {
      const i = r.opts.findIndex(([v]) => v === r.value);
      const n = r.opts.length;
      this._setRow(r, r.opts[(i + (left ? -1 : 1) + n) % n][0]);
    }
    if (ok || left || right) e.preventDefault();
  }

  _tick() { this.game.audio?.play?.('ui_prompt', { vol: 0.6 }); }

  _updatePause(dt) {
    const P = this._pause;
    if (P.quitArm > 0) { P.quitArm -= dt; if (P.quitArm <= 0) { P.quitArm = -1; this._renderPause(); } }
    // sleepy Telly breathes on the stand-by card (~8 fps redraw)
    this._cardT = (this._cardT || 0) + dt;
    if (this._cardT > 0.125) { this._cardT = 0; this._drawCard(this.dom.pauseCanvas, 'stand_by', this.game.time.realNow); }
  }

  _drawCard(cv, id, time, sleepy = true, opts = {}) {
    const x = cv.getContext('2d');
    try {
      this.game.cards.drawTo(x, id, cv.width, cv.height, time, { ...opts, ...(sleepy ? {} : { variant: 'awake' }) });
    } catch {
      x.fillStyle = '#1E1830'; x.fillRect(0, 0, cv.width, cv.height);
      x.font = `80px ${FONTS.logo}`; x.textAlign = 'center'; x.fillStyle = '#FFE9B8'; x.fillText('Please Stand By', cv.width / 2, cv.height / 2);
    }
  }

  // -------------------------------------------------------------------------------------------- game over
  _updateOver(dt) {
    const O = this._over, g = this.game, post = g.render?.post;
    if (!O) return;
    const t = this._t;
    if (O.phase === 'drain') {
      // the picture drains and the vertical hold slips while the tape stops
      const k = clamp(t / GAMEOVER.drain, 0, 1);
      if (post) { post.saturation = 1 - k * 0.85; post.roll = k * 0.22; post.static = k * 0.045; post.damage = Math.max(0, (post.damage || 0) * 0.95); post.whiteout = 0; }
      if (t >= GAMEOVER.drain) O.phase = 'collapse';
    } else if (O.phase === 'collapse') {
      const k = clamp((t - GAMEOVER.drain) / GAMEOVER.collapse, 0, 1);
      if (post) { post.collapse = easeIn(k) * 0.55 + k * 0.45; post.roll = 0.22 * (1 - k); post.static = 0.045 * (1 - k); }
      if (k >= 1) { O.phase = 'black'; if (post) post.collapse = 1; this.dom.bg.classList.add('on'); this.dom.bg.style.background = '#000'; }
    } else if (O.phase === 'black') {
      if (t >= GAMEOVER.card) { this._showOverCard(); this._t = 0; }
    } else if (O.phase === 'card') {
      this._board.update(dt);
      this._cardT = (this._cardT || 0) + dt;
      if (this._cardT > 0.125) { this._cardT = 0; this._drawCard(this.dom.overCanvas, 'stand_by', g.time.realNow, !O.results); }
      if (this._t > GAMEOVER.lock && !this.dom.anykey.classList.contains('on')) this.dom.anykey.classList.add('on');
      // count kills/points up
      const k = clamp((this._t - 0.35) / 1.1, 0, 1);
      const e = easeOut(k);
      this.dom.sk.textContent = String(Math.round(O.summary.kills * e));
      this.dom.sp.textContent = Math.round(O.summary.points * e).toLocaleString('en-US');
    }
  }

  _showOverCard() {
    const O = this._over, d = this.dom;
    O.phase = 'card';
    this._resetPost();
    const post = this.game.render?.post;
    if (post) post.collapse = 1; // keep the world hidden behind the card (the next screen resets it)
    d.bg.classList.add('on');
    d.bg.style.background = '';
    this.pn.over.classList.add('on');
    this.root.style.pointerEvents = 'auto';
    d.anykey.classList.remove('on');
    d.anykey.textContent = this._anyText();
    d.ovHdr.style.display = O.title ? '' : 'none';
    d.ovHdr.textContent = O.title || '';
    d.sk.textContent = '0';
    d.sp.textContent = '0';
    this._drawCard(d.overCanvas, 'stand_by', 0, !O.results);
    const r = clamp(O.summary.round, 0, 999);
    const n = r > 99 ? 3 : 2;
    if (this._board.cards.length !== n) {
      this.dom.board.innerHTML = '';
      this._board = new FlipBoard(this.dom.board, n, { speed: 0.55, onFlip: () => this._flipSound() });
    }
    this._board.set('0'.repeat(n), true);
    this._board.set(String(r).padStart(n, '0'));
  }

  _flipSound() {
    const now = performance.now();
    if (now - (this._flipAt || 0) < 45) return;
    this._flipAt = now;
    this.game.audio?.play?.('ui_points_flip', { vol: 0.7 });
  }
}
