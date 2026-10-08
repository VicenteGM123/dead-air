#!/usr/bin/env node
// PHAROS web smoke test. Serves an exported web build on localhost the way GitHub Pages does (same sub-path, gzip
// for html/js/wasm, no COOP/COEP headers), opens it in headless Chromium with WebGL 2 on SwiftShader (a CPU
// renderer: FPS numbers only show that rendering works, not real-device speed) and records load times, console
// errors/warnings, audio output levels and an FPS estimate, plus screenshots.
//
//   cd pharos/tools && npm install                  (playwright-core only; it uses an installed Chromium)
//   node pharos/tools/web_test.mjs <report_dir> [options]
//
// Options:
//   --dir <path>         exported build to serve (default: pharos/web next to this script)
//   --only <list>        scenarios, comma separated (default: shell,gate,title,flow,play,night,mobile)
//                          shell   loading screen on a throttled connection (desktop + phone portrait at its real
//                                  pixel ratio: fonts loaded, phone pixel-ratio cap, "turn the device" hint), the
//                                  "no WebGL 2" message (no useless retry button) and the link-preview image
//                                                                            -> loading.png, loading_mobile.png,
//                                                                               error_webgl2.png
//                          gate    autoplay blocked (emulated): the loaded shell waits for "Pulsa para entrar", a
//                                  click starts the sound, reveals the game and gives the canvas the keyboard, and the
//                                  click itself never reaches the game; then a phone held upright: "Toca para entrar",
//                                  the tap must not reach the game canvas either, "Gira el dispositivo" over the game
//                                  until the phone is turned
//                                                                            -> gate.png, gate_after.png,
//                                                                               gate_touch.png, gate_touch_portrait.png,
//                                                                               gate_touch_landscape.png
//                          title   index.html, screenshot ~8 s after start  -> title.png
//                          flow    index.html with no parameters, like a player: waits for the title, presses Enter
//                                  (the focused "Comenzar") and requires the console line "PHAROS phase DAY"
//                                  (Game.set_phase() prints "PHAROS phase <NAME> night N")
//                                                                            -> flow_title.png, flow.png
//                          play    ?dev=1&play=1                             -> play.png
//                          night   --night-query: >= --night-wait s and until "PHAROS phase NIGHT" (+8 s for the
//                                  waves to land; at most --night-max s; tools/bot.gd ships in the "Web" build)
//                                                                            -> night.png
//                          mobile  title on an emulated phone in landscape (863 x 360 CSS px, touch, DPR 1)
//                                                                            -> mobile.png
//                          og      (only when asked for) the link-preview image: the title screen at 1200 x 630 CSS px,
//                                  drawn at 2x and scaled down     -> og.jpg (publish it: copy it to
//                                                                     pharos/game/web/site/og.jpg and export again)
//   --title-wait <s>     default 8     --play-wait <s>   default 10     --night-wait <s>   default 40
//   --night-max <s>      default 240   --flow-max <s>    default 120    --timeout <s>      max wait for the game to
//                                                                                          start, default 180
//   --night-query <q>    default ?dev=1&play=1&bot=1&speed=2&startnight=1&nearfight=1 (startnight/nearfight: the
//                        night and its first creatures arrive at once, so the shot shows combat even on a software
//                        GPU; the published build only reads debug parameters when dev=1 is present)
//   --chrome <path>      Chromium/Chrome executable (default: Playwright's, then $PLAYWRIGHT_BROWSERS_PATH)
//   --headed             show the browser window      --no-gzip   serve without compression
//
// Writes <report_dir>/report.json, the PNGs and console-<scenario>.log. Each scenario lists its "problems" (did not
// start, crashed, an error or a timeout after the start, the engine stopped drawing, a screenshot that is not the game
// canvas, console errors or 404s, no sound, a silent last 5 s or 1 s of total silence anywhere, a mostly black frame,
// the expected "PHAROS phase" never printed, the title's "Comenzar" leading nowhere, input leaking through the gate,
// ...) and "warnings" (clipping, audio memory churn, very slow frames); exits 1 if there is any problem. A build must
// pass before it is published.
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, extname, join, normalize, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';

const HERE = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
let playwright;
try {
	playwright = require('playwright-core');
} catch {
	console.error('web_test: playwright-core is missing; run `npm install` in pharos/tools');
	process.exit(2);
}
const { chromium, devices } = playwright;

// --- options -----------------------------------------------------------------------------------------------------

const ALL = ['shell', 'gate', 'title', 'flow', 'play', 'night', 'mobile'];
const EXTRA = ['og'];
const opts = {
	report: null,
	dir: join(HERE, '..', 'web'),
	only: ALL,
	titleWait: 8,
	playWait: 10,
	nightWait: 40,
	nightMax: 240,
	flowMax: 120,
	nightQuery: '?dev=1&play=1&bot=1&speed=2&startnight=1&nearfight=1',
	timeout: 180,
	chrome: process.env.CHROME_PATH || null,
	headed: false,
	gzip: true,
};
{
	const a = process.argv.slice(2);
	for (let i = 0; i < a.length; i++) {
		const k = a[i];
		const v = () => {
			if (i + 1 >= a.length) {
				throw new Error(`missing value for ${k}`);
			}
			return a[++i];
		};
		if (k === '--dir') opts.dir = v();
		else if (k === '--only') opts.only = v().split(',').map((s) => s.trim()).filter(Boolean);
		else if (k === '--title-wait') opts.titleWait = Number(v());
		else if (k === '--play-wait') opts.playWait = Number(v());
		else if (k === '--night-wait') opts.nightWait = Number(v());
		else if (k === '--night-max') opts.nightMax = Number(v());
		else if (k === '--flow-max') opts.flowMax = Number(v());
		else if (k === '--night-query') opts.nightQuery = v().replace(/^\??/, '?');
		else if (k === '--timeout') opts.timeout = Number(v());
		else if (k === '--chrome') opts.chrome = v();
		else if (k === '--headed') opts.headed = true;
		else if (k === '--no-gzip') opts.gzip = false;
		else if (k === '-h' || k === '--help') {
			const lines = readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1);
			console.log(lines.slice(0, lines.findIndex((l) => !l.startsWith('//'))).map((l) => l.replace(/^\/\/ ?/, '')).join('\n'));
			process.exit(0);
		} else if (k.startsWith('--')) throw new Error(`unknown option ${k}`);
		else if (!opts.report) opts.report = k;
		else throw new Error(`unexpected argument ${k}`);
	}
	if (!opts.report) {
		console.error(`usage: node web_test.mjs <report_dir> [--dir pharos/web] [--only ${ALL.join(',')}]`);
		process.exit(2);
	}
	for (const s of opts.only) {
		if (!ALL.includes(s) && !EXTRA.includes(s)) throw new Error(`unknown scenario ${s} (${[...ALL, ...EXTRA].join(', ')})`);
	}
}
const ROOT = resolve(opts.dir);
const REPORT = resolve(opts.report);
if (!existsSync(join(ROOT, 'index.html'))) {
	console.error(`web_test: no index.html in ${ROOT} (export first: sh pharos/tools/export_web.sh)`);
	process.exit(2);
}
mkdirSync(REPORT, { recursive: true });

// --- static server (GitHub Pages-like) -----------------------------------------------------------------------------

const MOUNT = '/dead-air/pharos/web/';
const TYPES = {
	'.html': 'text/html; charset=utf-8',
	'.js': 'text/javascript; charset=utf-8',
	'.mjs': 'text/javascript; charset=utf-8',
	'.wasm': 'application/wasm',
	'.pck': 'application/octet-stream',
	'.png': 'image/png',
	'.svg': 'image/svg+xml',
	'.ico': 'image/x-icon',
	'.ttf': 'font/ttf',
	'.woff2': 'font/woff2',
	'.jpg': 'image/jpeg',
	'.json': 'application/json',
	'.txt': 'text/plain; charset=utf-8',
	'.md': 'text/markdown; charset=utf-8',
};
const COMPRESS = new Set(['.html', '.js', '.mjs', '.wasm', '.svg', '.json', '.txt', '.md']);
const gzCache = new Map();

function serve(req, res) {
	const url = new URL(req.url, 'http://localhost');
	let path = decodeURIComponent(url.pathname);
	if (path === '/' || path === MOUNT.slice(0, -1)) {
		res.writeHead(302, { Location: MOUNT });
		res.end();
		return;
	}
	if (!path.startsWith(MOUNT)) {
		res.writeHead(404);
		res.end('not found');
		return;
	}
	path = path.slice(MOUNT.length) || 'index.html';
	const file = normalize(join(ROOT, path));
	if (file !== ROOT && !file.startsWith(ROOT + sep)) {
		res.writeHead(403);
		res.end();
		return;
	}
	let st;
	try {
		st = statSync(file);
	} catch {
		res.writeHead(404);
		res.end('not found');
		return;
	}
	if (!st.isFile()) {
		res.writeHead(404);
		res.end('not found');
		return;
	}
	const ext = extname(file).toLowerCase();
	const headers = { 'Content-Type': TYPES[ext] || 'application/octet-stream', 'Cache-Control': 'no-cache' };
	let body;
	if (opts.gzip && COMPRESS.has(ext) && /\bgzip\b/.test(req.headers['accept-encoding'] || '')) {
		const key = `${file}:${st.mtimeMs}:${st.size}`;
		body = gzCache.get(key);
		if (!body) {
			body = gzipSync(readFileSync(file), { level: 6 });
			gzCache.set(key, body);
		}
		headers['Content-Encoding'] = 'gzip';
		headers.Vary = 'Accept-Encoding';
	} else {
		body = readFileSync(file);
	}
	headers['Content-Length'] = body.length;
	res.writeHead(200, headers);
	res.end(req.method === 'HEAD' ? undefined : body);
}

// --- in-page instrumentation (runs before the page's own scripts) --------------------------------------------------

function instrument(cfg) {
	const P = window.__pharos = {
		frames: [],
		readyAt: null,
		captureWanted: false,
		capture: null,
		audio: { contexts: [], blocks: [], sources: 0, worklets: 0, buffers: 0, bufferBytes: 0, bufferLog: [], meter: 'pending' },
		canvasEvents: [],
	};
	// Input that reaches the game canvas (Godot listens there): the gate scenario checks that the tap or click that
	// dismisses the loading screen does not also press something in the game.
	document.addEventListener('DOMContentLoaded', () => {
		const c = document.getElementById('canvas');
		for (const t of ['pointerdown', 'pointerup', 'mousedown', 'mouseup', 'click', 'touchstart', 'touchend']) {
			if (c) c.addEventListener(t, () => P.canvasEvents.push([Math.round(performance.now()), t]));
		}
	});
	// FPS: count the frames the page draws (Godot's main loop runs on requestAnimationFrame; a stuck or crashed engine
	// stops asking for frames). Screenshots: Godot draws inside requestAnimationFrame and its WebGL canvas is not
	// preserved after compositing, so the canvas is read right after a frame callback; this works even when
	// SwiftShader frames take seconds, where a CDP screenshot may time out.
	const raf = window.requestAnimationFrame.bind(window);
	window.requestAnimationFrame = function (cb) {
		return raf((t) => {
			P.frames.push(t);
			cb(t);
			if (P.captureWanted) {
				const c = document.getElementById('canvas');
				if (c && c.width > 0) {
					P.captureWanted = false;
					try {
						P.capture = c.toDataURL('image/png');
					} catch (e) {
						P.capture = `error:${e}`;
					}
				}
			}
		});
	};
	// Godot prints through console.log: note when the main scene reports "PHAROS world ready in N ms".
	const log = console.log;
	console.log = function (...a) {
		if (P.readyAt === null && a.map(String).join(' ').indexOf('world ready in') >= 0) {
			P.readyAt = performance.now();
		}
		return log.apply(this, a);
	};
	if (cfg && cfg.noWebGL2) {
		const getContext = HTMLCanvasElement.prototype.getContext;
		HTMLCanvasElement.prototype.getContext = function (type, ...rest) {
			return type === 'webgl2' ? null : getContext.call(this, type, ...rest);
		};
	}
	// Audio: everything that reaches the speakers goes through a meter AudioWorklet (on the audio thread, so it is
	// exact even when the page is slow). Every ~100 ms of audio it reports RMS, peak and the "gaps": runs of all-zero
	// render quanta between non-silent ones. PHAROS always plays the sea ambience once the title is up, so a gap is a
	// fault: with the Stream playback type a buffer underrun of the engine's mixer (main thread too busy to mix in
	// time); with Sample playback every voice silent at once, e.g. looping tracks that end together and wait for a busy
	// main thread to restart them (unpatched Godot 4.7; export_web.sh makes them loop on the audio thread).
	const A = P.audio;
	let AC = window.AudioContext;
	if (!AC) {
		A.meter = 'no AudioContext';
		return;
	}
	if (cfg && cfg.blockAutoplay) {
		// Headless Chromium always lets pages play sound (and reports navigator.userActivation as active): emulate the
		// normal policy, a context starts suspended and resume() only works after a real click, tap or key press.
		let interacted = false;
		for (const e of ['pointerdown', 'mousedown', 'touchend', 'keydown']) {
			window.addEventListener(e, (ev) => {
				if (ev.isTrusted) interacted = true;
			}, true);
		}
		const Base = AC;
		AC = class extends Base {
			constructor(...a) {
				super(...a);
				if (!interacted) {
					Base.prototype.suspend.call(this);
				}
			}
			resume() {
				return interacted ? super.resume() : Promise.resolve();
			}
		};
	}
	const METER = `class PharosMeter extends AudioWorkletProcessor {
		constructor() { super(); this.reset(); this.zeroRun = 0; this.hadSound = false; }
		reset() { this.sum = 0; this.n = 0; this.peak = 0; this.quanta = 0; this.zeroQuanta = 0; this.gaps = 0; this.gapQuanta = 0; }
		process(inputs, outputs) {
			const inp = inputs[0] || [];
			const out = outputs[0] || [];
			let zero = true;
			for (let c = 0; c < out.length; c++) {
				const i = inp[c];
				const o = out[c];
				if (!i) { o.fill(0); continue; }
				o.set(i);
				for (let k = 0; k < i.length; k++) {
					const v = i[k];
					if (v !== 0) { zero = false; this.sum += v * v; const m = v < 0 ? -v : v; if (m > this.peak) this.peak = m; }
				}
				this.n += i.length;
			}
			this.quanta++;
			if (zero) { this.zeroQuanta++; if (this.hadSound) this.zeroRun++; }
			else { if (this.zeroRun > 0) { this.gaps++; this.gapQuanta += this.zeroRun; } this.zeroRun = 0; this.hadSound = true; }
			if (this.quanta >= Math.round(sampleRate / 1280)) {
				this.port.postMessage([currentTime, Math.sqrt(this.sum / Math.max(1, this.n)), this.peak, this.zeroQuanta, this.quanta, this.gaps, this.gapQuanta, sampleRate]);
				this.reset();
			}
			return true;
		}
	}
	registerProcessor('pharos-meter', PharosMeter);`;
	const meterURL = URL.createObjectURL(new Blob([METER], { type: 'text/javascript' }));
	const taps = new Map();
	const connect = AudioNode.prototype.connect;
	const disconnect = AudioNode.prototype.disconnect;
	window.AudioContext = class extends AC {
		constructor(...a) {
			super(...a);
			A.contexts.push(this);
			const ctx = this;
			const input = ctx.createGain();
			connect.call(input, ctx.destination);
			taps.set(ctx, input);
			const offset = performance.now() - ctx.currentTime * 1000;
			if (!ctx.audioWorklet) {
				A.meter = 'no AudioWorklet (insecure context?)';
				return;
			}
			ctx.audioWorklet.addModule(meterURL).then(() => {
				const meter = new AudioWorkletNode(ctx, 'pharos-meter', { outputChannelCount: [ctx.destination.channelCount || 2] });
				meter.port.onmessage = (ev) => {
					const d = ev.data;
					// [time ms (performance.now() clock), rms, peak, zero quanta, quanta, gaps, gap quanta, sample rate]
					A.blocks.push([Math.round(offset + d[0] * 1000), d[1], d[2], d[3], d[4], d[5], d[6], d[7]]);
				};
				connect.call(meter, ctx.destination);
				connect.call(input, meter);
				disconnect.call(input, ctx.destination);
				A.meter = 'ok';
			}, (e) => {
				A.meter = `meter failed: ${e}`;
			});
		}
	};
	AudioNode.prototype.connect = function (dest, ...rest) {
		if (dest instanceof AudioDestinationNode && taps.has(dest.context)) {
			return connect.call(this, taps.get(dest.context), rest[0] || 0);
		}
		return connect.call(this, dest, ...rest);
	};
	AudioNode.prototype.disconnect = function (...a) {
		if (a[0] instanceof AudioDestinationNode && taps.has(a[0].context)) {
			a[0] = taps.get(a[0].context);
		}
		return disconnect.apply(this, a);
	};
	const start = AudioBufferSourceNode.prototype.start;
	AudioBufferSourceNode.prototype.start = function (...a) {
		A.sources++;
		return start.apply(this, a);
	};
	// Sample playback decodes every sound into an AudioBuffer (32-bit float PCM), and Godot 4.7 copies that buffer again
	// for every play(): the cumulative size of the buffers created is its memory churn (copies are freed by the GC).
	const createBuffer = BaseAudioContext.prototype.createBuffer;
	BaseAudioContext.prototype.createBuffer = function (channels, length, rate) {
		A.buffers++;
		A.bufferBytes += channels * length * 4;
		A.bufferLog.push([performance.now(), channels * length * 4]);
		return createBuffer.call(this, channels, length, rate);
	};
	if (window.AudioWorkletNode) {
		const AWN = window.AudioWorkletNode;
		window.AudioWorkletNode = class extends AWN {
			constructor(ctx, name, ...a) {
				super(ctx, name, ...a);
				if (name !== 'pharos-meter') {
					A.worklets++;
				}
			}
		};
	}
}

// --- helpers ------------------------------------------------------------------------------------------------------

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const round = (x, d = 1) => (x == null || !Number.isFinite(x) ? null : Math.round(x * 10 ** d) / 10 ** d);

function frameStats(frames, from, to) {
	const f = frames.filter((t) => t >= from && t <= to);
	if (f.length < 2) {
		return { fps: 0, frames: f.length, note: 'no frames in window' };
	}
	const d = [];
	for (let i = 1; i < f.length; i++) {
		d.push(f[i] - f[i - 1]);
	}
	const s = [...d].sort((a, b) => a - b);
	const q = (p) => s[Math.min(s.length - 1, Math.floor(p * s.length))];
	return {
		fps: round((f.length - 1) / ((f[f.length - 1] - f[0]) / 1000)),
		frames: f.length,
		medianMs: round(q(0.5)),
		p95Ms: round(q(0.95)),
		maxMs: round(s[s.length - 1]),
		over50ms: d.filter((x) => x > 50).length,
		over100ms: d.filter((x) => x > 100).length,
		over250ms: d.filter((x) => x > 250).length,
	};
}

function audioStats(blocks, from, to) {
	const w = blocks.filter((b) => b[0] >= from && b[0] <= to);
	if (!w.length) {
		return { seconds: 0, note: 'no audio measured (AudioContext not running or meter not installed)' };
	}
	const rate = w[0][7] || 48000;
	const quanta = w.reduce((a, b) => a + b[4], 0);
	const ms = w.reduce((a, b) => a + b[1] * b[1] * b[4], 0) / Math.max(1, quanta);
	const db = (x) => (x > 0 ? round(20 * Math.log10(x)) : null);
	const gapQuanta = w.reduce((a, b) => a + b[6], 0);
	return {
		seconds: round((quanta * 128) / rate),
		rmsDb: db(Math.sqrt(ms)),
		peakDb: db(Math.max(...w.map((b) => b[2]))),
		silentPct: round((100 * w.reduce((a, b) => a + b[3], 0)) / Math.max(1, quanta)),
		// all-zero stretches after the first sound: buffer underruns with the Stream playback type, or every voice
		// stopped at once; gapsAt: [seconds into the window when the sound came back, length in ms]
		gaps: w.reduce((a, b) => a + b[5], 0),
		gapMs: round((gapQuanta * 128 * 1000) / rate, 0),
		gapsAt: w.filter((b) => b[5] > 0).slice(0, 10).map((b) => [round((b[0] - from) / 1000), round((b[6] * 128 * 1000) / rate, 0)]),
	};
}

// Phase changes: Game.set_phase() prints "PHAROS phase <NAME> night <N>" (BOOT, TITLE, DAY, DUSK, NIGHT, DAWN,
// BLESSING, VICTORY, DEFEAT).
const PHASE_RE = /^PHAROS phase ([A-Z]+)\b/;
const phasesIn = (log) => log.map((e) => PHASE_RE.exec(e.text || '')).filter(Boolean).map((m) => m[1]);

function classify(log) {
	const errors = [];
	const warnings = [];
	for (const e of log) {
		const t = e.text || '';
		if (e.type === 'pageerror' || e.type === 'crash' || e.type === 'requestfailed' || e.type === 'http') {
			errors.push(`[${e.type}] ${t}`);
		} else if (e.type === 'error') {
			(/^\s*(WARNING|USER WARNING)\b/.test(t) ? warnings : errors).push(t);
		} else if (e.type === 'warning') {
			warnings.push(t);
		} else if (/^\s*(USER |SCRIPT )?ERROR\b/.test(t)) {
			errors.push(t);
		} else if (/^\s*(USER )?WARNING\b/.test(t)) {
			warnings.push(t);
		}
	}
	const audio = [...errors, ...warnings].filter((t) => /audio|sound|sample|worklet|\.ogg|AudioContext/i.test(t));
	return { errors, warnings, audio };
}

async function launch() {
	const args = [
		'--use-angle=swiftshader',
		'--enable-unsafe-swiftshader',
		'--ignore-gpu-blocklist',
		'--autoplay-policy=no-user-gesture-required',
		'--disable-background-timer-throttling',
		'--disable-renderer-backgrounding',
	];
	const base = { headless: !opts.headed, args };
	const tries = [];
	if (opts.chrome) {
		tries.push({ ...base, executablePath: opts.chrome });
	} else {
		tries.push(base);
		// Fallback: any Chromium in the Playwright browsers folder (version mismatch with playwright-core).
		const dirs = [process.env.PLAYWRIGHT_BROWSERS_PATH, join(process.env.HOME || '', '.cache', 'ms-playwright')].filter(Boolean);
		for (const d of dirs) {
			if (!existsSync(d)) continue;
			for (const sub of readdirSync(d).sort().reverse()) {
				for (const rel of ['chrome-linux/chrome', 'chrome-linux/headless_shell', 'chrome-linux64/chrome', 'chrome-headless-shell-linux64/chrome-headless-shell']) {
					const p = join(d, sub, rel);
					if (sub.startsWith('chromium') && existsSync(p)) tries.push({ ...base, executablePath: p });
				}
			}
		}
	}
	let last;
	for (const t of tries) {
		try {
			return await chromium.launch(t);
		} catch (e) {
			last = e;
		}
	}
	throw last || new Error('no Chromium found');
}


// --- scenarios ----------------------------------------------------------------------------------------------------

const DESKTOP = { viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1 };
const PHONE = devices['Pixel 7'] || { viewport: { width: 412, height: 839 }, deviceScaleFactor: 2.625, isMobile: true, hasTouch: true };
// The in-game phone scenarios keep the phone's layout (CSS px, touch, mobile UA) but render at DPR 1: SwiftShader
// cannot draw a phone's pixel count in useful time. On a real phone or tablet the shell renders at most 1.5 device px
// per CSS px and ~1.5 MP (checked at the real DPR by the shell scenario); the report states the canvas a real Pixel 7
// gets.
const PHONE_DPR = PHONE.deviceScaleFactor;
const PHONE_PORTRAIT_1X = { ...PHONE, deviceScaleFactor: 1 };
const PHONE_LANDSCAPE = { ...(devices['Pixel 7 landscape'] || { ...PHONE, viewport: { width: 863, height: 360 } }), deviceScaleFactor: 1 };
const shellPixelRatio = (dpr, w, h) => Math.min(dpr, Math.max(1, Math.min(1.5, Math.sqrt(1.5e6 / Math.max(1, w * h)))));

async function openPage(browser, ctxOpts, initCfg, log, t0) {
	const context = await browser.newContext(ctxOpts);
	const page = await context.newPage();
	await page.addInitScript(instrument, initCfg || {});
	page.on('console', (m) => log.push({ t: Date.now() - t0, type: m.type(), text: m.text() }));
	page.on('pageerror', (e) => log.push({ t: Date.now() - t0, type: 'pageerror', text: String((e && e.stack) || e) }));
	page.on('requestfailed', (r) => log.push({ t: Date.now() - t0, type: 'requestfailed', text: `${r.url()} ${r.failure() ? r.failure().errorText : ''}` }));
	page.on('response', (r) => {
		if (r.status() >= 400) log.push({ t: Date.now() - t0, type: 'http', text: `${r.status()} ${r.url()}` });
	});
	page.on('crash', () => log.push({ t: Date.now() - t0, type: 'crash', text: 'page crashed' }));
	return { context, page };
}

function writeLog(name, log) {
	writeFileSync(join(REPORT, `console-${name}.log`), log.map((e) => `${String(e.t).padStart(7)} ms  ${e.type.padEnd(8)} ${e.text}`).join('\n') + '\n');
}

async function throttle(context, page, mbps) {
	const cdp = await context.newCDPSession(page);
	await cdp.send('Network.enable');
	await cdp.send('Network.emulateNetworkConditions', {
		offline: false,
		latency: 60,
		downloadThroughput: (mbps * 1e6) / 8,
		uploadThroughput: (10 * 1e6) / 8,
	});
}

const errorText = (e) => String((e && e.message) || e).split('\n')[0];

async function shellScenario(browser, base) {
	const out = { screenshots: [], problems: [], warnings: [] };
	const log = [];
	const t0 = Date.now();
	// Loading screen mid-download on a ~25 Mbit/s connection, desktop and phone portrait (at the phone's real DPR).
	for (const [file, ctxOpts] of [['loading.png', DESKTOP], ['loading_mobile.png', PHONE]]) {
		const { context, page } = await openPage(browser, ctxOpts, {}, log, t0);
		await throttle(context, page, 25);
		await page.goto(base + 'index.html', { waitUntil: 'domcontentloaded' });
		try {
			await page.waitForFunction(() => window.pharosShell && window.pharosShell.progress >= 0.3, null, { timeout: 60000, polling: 100 });
			await page.evaluate(() => document.fonts.ready.then(() => true));
			await sleep(400); // the rise-in animation
			await page.screenshot({ path: join(REPORT, file) });
			out.screenshots.push(file);
			const r = out[file] = await page.evaluate(() => ({ progress: window.pharosShell.progress, text: document.getElementById('status-text').textContent,
				fonts: [...document.fonts].filter((f) => f.status === 'loaded').map((f) => `${f.family} ${f.weight} ${f.style}`),
				touchOnly: window.pharosShell.touchOnly, pixelRatio: window.pharosShell.pixelRatio,
				hint: document.getElementById('status-hint').classList.contains('show') ? document.getElementById('status-hint').textContent : null }));
			const fonts = r.fonts.join(' | ');
			if (!/Cinzel 600/.test(fonts) || !/EB Garamond \S+ italic/.test(fonts)) {
				out.problems.push(`${file}: the loading-screen fonts did not load (${fonts || 'none'}); is fonts/ next to index.html?`);
			}
			if (file === 'loading.png') {
				// The whole download (wasm + pck, gzip where the server compresses) at 25 Mbit/s with 60 ms latency.
				await page.waitForFunction(() => window.pharosShell.downloadedAt !== null || window.pharosShell.failed, null, { timeout: 120000, polling: 100 });
				out.download25MbitS = await page.evaluate(() => Math.round(window.pharosShell.downloadedAt / 100) / 10);
			} else {
				if (!r.touchOnly) {
					out.problems.push(`${file}: the phone was not recognised as a touch device ("${r.text}")`);
				} else if (!(r.pixelRatio && r.pixelRatio.used <= 1.5 + 1e-9)) {
					out.problems.push(`${file}: the phone renders at ${r.pixelRatio && r.pixelRatio.used} device px per CSS px (the shell caps it at 1.5)`);
				}
				if (!r.hint) out.problems.push(`${file}: no "turn the device" hint on a phone held upright`);
			}
		} catch (e) {
			out[file] = { error: errorText(e) };
			out.problems.push(`${file}: ${out[file].error}`);
		}
		await context.close();
	}
	// Browser without WebGL 2: the Spanish error message (and no "retry" button: a reload cannot fix it).
	{
		const { context, page } = await openPage(browser, DESKTOP, { noWebGL2: true }, log, t0);
		await page.goto(base + 'index.html', { waitUntil: 'load' });
		await page.evaluate(() => document.fonts.ready.then(() => true));
		await sleep(1500);
		const notice = await page.evaluate(() => {
			const n = document.getElementById('status-notice');
			return n && !n.hidden ? { text: n.innerText, button: !document.getElementById('notice-button').hidden,
				fonts: [...document.fonts].filter((f) => f.status === 'loaded').map((f) => `${f.family} ${f.weight} ${f.style}`) } : null;
		});
		await page.screenshot({ path: join(REPORT, 'error_webgl2.png') });
		out.screenshots.push('error_webgl2.png');
		out.noWebGL2Notice = notice && notice.text;
		out.noWebGL2Ok = !!notice && /WebGL 2/.test(notice.text);
		if (!out.noWebGL2Ok) {
			out.problems.push('no Spanish "WebGL 2" message when WebGL 2 is missing');
		} else {
			if (notice.button) out.problems.push('the "no WebGL 2" message offers a reload, which cannot help');
			if (!notice.fonts.some((f) => /^EB Garamond \S+ normal$/.test(f))) {
				out.problems.push(`the error notice is not set in EB Garamond (fonts loaded: ${notice.fonts.join(', ') || 'none'})`);
			}
		}
		await context.close();
	}
	// Link preview: og:image points at og.jpg, which must be in the build.
	{
		const html = readFileSync(join(ROOT, 'index.html'), 'utf8');
		const m = /<meta property="og:image" content="([^"]+)"/.exec(html);
		out.ogImage = m ? m[1] : null;
		const file = m ? m[1].split('/').pop() : null;
		const res = file ? await fetch(base + file).catch(() => null) : null;
		if (!m) out.problems.push('index.html has no og:image');
		else if (!res || res.status !== 200 || !/^image\//.test(res.headers.get('content-type') || '')) out.problems.push(`link-preview image ${file} is not in the build`);
	}
	writeLog('shell', log);
	const c = classify(log);
	out.console = { errors: c.errors, warnings: c.warnings };
	// Nothing here should log an error: one is a missing file (fonts/, og.jpg: a 404) or a script error in the shell.
	if (c.errors.length) out.problems.push(`${c.errors.length} console error(s), first: ${c.errors[0].slice(0, 160)}`);
	return out;
}

// A browser that keeps pages silent until the first interaction (the default everywhere): the loaded shell must
// wait with "Pulsa para entrar", and one click must start the sound, fade the loading screen and leave the keyboard
// with the game canvas, without the click itself reaching the game. Then the same on a phone held upright: "Toca
// para entrar", a tap (whose emulated mouse events must not reach the canvas either), the "turn the device" screen,
// and the game once the phone is turned.
// (Headless Chromium never blocks sound, so the usual policy is emulated in instrument(): blockAutoplay.)
async function gateScenario(browser, base) {
	const out = { screenshots: [], problems: [], warnings: [] };
	const log = [];
	const t0 = Date.now();
	const waitReady = (page) => page.waitForFunction(() => window.pharosShell && (window.pharosShell.phase === 'ready'
		|| window.pharosShell.revealedAt !== null || window.pharosShell.failed), null, { timeout: opts.timeout * 1000, polling: 250 });
	const state = (page) => page.evaluate(() => ({ phase: window.pharosShell.phase, text: document.getElementById('status-text').textContent,
		audio: (window.pharosAudioContexts || []).map((c) => c.state), failed: window.pharosShell.failed }));
	const leaked = (page, from) => page.evaluate((f) => window.__pharos.canvasEvents.filter((e) => e[0] >= f && e[0] <= f + 1500).map((e) => e[1]), from);
	// Desktop, mouse.
	{
		const { context, page } = await openPage(browser, DESKTOP, { blockAutoplay: true }, log, t0);
		try {
			await page.goto(base + 'index.html', { waitUntil: 'load', timeout: 120000 });
			await waitReady(page);
			const before = out.before = await state(page);
			await sleep(1200);
			await page.screenshot({ path: join(REPORT, 'gate.png'), timeout: 90000 });
			out.screenshots.push('gate.png');
			if (before.phase !== 'ready') {
				out.problems.push(`the loaded shell did not wait for a first input (phase ${before.phase}, audio ${before.audio.join(',') || 'none'})`);
			} else {
				const at = await page.evaluate(() => performance.now());
				await page.mouse.click(640, 360);
				await page.waitForFunction(() => window.pharosShell.revealedAt !== null, null, { timeout: 10000, polling: 100 });
				await page.waitForFunction(() => (window.pharosAudioContexts || []).every((c) => c.state === 'running'), null, { timeout: 10000, polling: 100 })
					.catch(() => {});
				await sleep(2500);
				out.after = await page.evaluate(() => ({ audio: (window.pharosAudioContexts || []).map((c) => c.state),
					overlayHidden: document.getElementById('status').hidden, focus: document.activeElement ? (document.activeElement.id || document.activeElement.tagName) : null }));
				out.after.canvasEvents = await leaked(page, at);
				const shot = await capture(page, 'gate_after.png');
				out.screenshots.push('gate_after.png');
				out.image = shot.image;
				if (shot.from !== 'canvas') out.problems.push(`no frame from the game canvas after the click (${shot.error})`);
				if (!out.after.audio.length || out.after.audio.some((s) => s !== 'running')) {
					out.problems.push(`sound did not start after the click (${out.after.audio.join(',') || 'no AudioContext'})`);
				}
				if (!out.after.overlayHidden) out.problems.push('the loading screen did not go away after the click');
				if (out.after.focus !== 'canvas') out.problems.push(`keyboard focus is on ${out.after.focus}, not on the game canvas`);
				if (out.after.canvasEvents.length) out.problems.push(`the click that opened the game also reached it (${out.after.canvasEvents.join(', ')})`);
			}
		} catch (e) {
			out.error = errorText(e);
			out.problems.push(out.error);
		}
		await context.close();
	}
	// Phone held upright, touch.
	{
		const touch = out.touch = {};
		const { context, page } = await openPage(browser, PHONE_PORTRAIT_1X, { blockAutoplay: true }, log, t0);
		try {
			await page.goto(base + 'index.html', { waitUntil: 'load', timeout: 120000 });
			await waitReady(page);
			touch.before = await state(page);
			await sleep(1200);
			await page.screenshot({ path: join(REPORT, 'gate_touch.png'), timeout: 90000 });
			out.screenshots.push('gate_touch.png');
			if (touch.before.phase !== 'ready' || touch.before.text !== 'Toca para entrar') {
				out.problems.push(`phone: the loaded shell shows "${touch.before.text}" (phase ${touch.before.phase}), not "Toca para entrar"`);
			} else {
				const at = await page.evaluate(() => performance.now());
				await page.touchscreen.tap(206, 640);
				await page.waitForFunction(() => window.pharosShell.revealedAt !== null, null, { timeout: 10000, polling: 100 });
				await page.waitForFunction(() => (window.pharosAudioContexts || []).every((c) => c.state === 'running'), null, { timeout: 10000, polling: 100 })
					.catch(() => {});
				await sleep(2000);
				touch.after = await page.evaluate(() => ({ audio: (window.pharosAudioContexts || []).map((c) => c.state), rotatePrompt: window.pharosShell.rotatePrompt }));
				touch.after.canvasEvents = await leaked(page, at);
				await page.screenshot({ path: join(REPORT, 'gate_touch_portrait.png'), timeout: 90000 });
				out.screenshots.push('gate_touch_portrait.png');
				if (touch.after.audio.some((s) => s !== 'running') || !touch.after.audio.length) {
					out.problems.push(`phone: sound did not start after the tap (${touch.after.audio.join(',') || 'no AudioContext'})`);
				}
				if (touch.after.canvasEvents.length) {
					out.problems.push(`phone: the tap that opened the game also reached it (${touch.after.canvasEvents.join(', ')}): it can press a title-screen button`);
				}
				if (!touch.after.rotatePrompt) out.problems.push('phone held upright: no "Gira el dispositivo" screen over the game');
				// Turn the phone.
				await page.setViewportSize({ width: PHONE.viewport.height, height: PHONE.viewport.width });
				await sleep(2500);
				touch.landscape = await page.evaluate(() => ({ rotatePrompt: window.pharosShell.rotatePrompt,
					canvas: [document.getElementById('canvas').width, document.getElementById('canvas').height] }));
				if (touch.landscape.rotatePrompt) out.problems.push('phone: the "Gira el dispositivo" screen stays after turning the phone');
				const shot = await capture(page, 'gate_touch_landscape.png');
				out.screenshots.push('gate_touch_landscape.png');
				touch.image = shot.image;
				if (shot.from !== 'canvas') out.problems.push(`phone: no frame from the game canvas after turning the phone (${shot.error})`);
				if (shot.image && shot.image.darkPct > 50) out.problems.push(`phone: ${shot.image.darkPct}% of the frame is black after turning the phone`);
			}
		} catch (e) {
			touch.error = errorText(e);
			out.problems.push(`phone: ${touch.error}`);
		}
		await context.close();
	}
	writeLog('gate', log);
	const c = classify(log);
	out.console = { errors: c.errors, warnings: c.warnings };
	if (c.errors.length) out.problems.push(`${c.errors.length} console error(s), first: ${c.errors[0].slice(0, 160)}`);
	return out;
}

// Screenshot of the game canvas taken right after an engine frame (see instrument()); falls back to a CDP screenshot.
// Either way the image is measured (mean luma, black and blown-out shares).
async function capture(page, file) {
	try {
		await page.evaluate(() => {
			window.__pharos.capture = null;
			window.__pharos.captureWanted = true;
		});
		// Under heavy CPU load a SwiftShader frame can take tens of seconds: wait up to --timeout for the next one.
		await page.waitForFunction(() => window.__pharos.capture !== null, null, { timeout: opts.timeout * 1000, polling: 200 });
		const url = await page.evaluate(() => window.__pharos.capture);
		if (!url.startsWith('data:image/png;base64,')) {
			throw new Error(url);
		}
		writeFileSync(join(REPORT, file), Buffer.from(url.slice('data:image/png;base64,'.length), 'base64'));
		return { from: 'canvas', image: await imageStats(page, url) };
	} catch (e) {
		// No engine frame in time (frozen, or far too slow): keep a page screenshot to look at, but it is not a check of
		// the game's picture (the callers report it as a problem).
		const error = errorText(e);
		const png = await page.screenshot({ path: join(REPORT, file), timeout: 120000 });
		return { from: 'page', error, image: await imageStats(page, `data:image/png;base64,${png.toString('base64')}`) };
	}
}

// Mean luma (0..255) of a PNG data URL, and the share of near-black (< 10) and of blown-out (> 250) pixels.
function imageStats(page, url) {
	return page.evaluate(async (src) => {
		const img = new Image();
		img.src = src;
		await img.decode();
		const c = document.createElement('canvas');
		c.width = 160;
		c.height = 90;
		const g = c.getContext('2d');
		g.drawImage(img, 0, 0, c.width, c.height);
		const d = g.getImageData(0, 0, c.width, c.height).data;
		let sum = 0;
		let dark = 0;
		let blown = 0;
		const n = d.length / 4;
		for (let i = 0; i < d.length; i += 4) {
			const y = 0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2];
			sum += y;
			if (y < 10) dark++;
			if (y > 250) blown++;
		}
		return { meanLuma: Math.round(sum / n), darkPct: Math.round((100 * dark) / n), blownPct: Math.round((100 * blown) / n) };
	}, url);
}

// flow: wait for the title (and its intro), press Enter like a player (the title focuses "Comenzar") and require
// "PHAROS phase DAY" afterwards.
async function flowSteps(page, log, out, waitS) {
	await sleep(waitS * 1000);
	const shot = await capture(page, 'flow_title.png');
	out.titleImage = shot.image;
	out.titleScreenshotFrom = shot.from;
	out.titleScreenshotError = shot.error;
	out.flow = {
		phasesBefore: phasesIn(log),
		focus: await page.evaluate(() => (document.activeElement ? document.activeElement.id || document.activeElement.tagName : null)),
	};
	const pressed = Date.now();
	await page.keyboard.down('Enter');
	await sleep(600);
	await page.keyboard.up('Enter');
	const end = Date.now() + opts.flowMax * 1000;
	let day = false;
	while (Date.now() < end && !day) {
		day = phasesIn(log).slice(out.flow.phasesBefore.length).includes('DAY');
		if (!day) await sleep(500);
	}
	out.flow.dayAfterEnter = day;
	out.flow.afterEnterS = day ? round((Date.now() - pressed) / 1000) : null;
	out.flow.phases = phasesIn(log);
	if (day) await sleep(4000); // the island, the hero and the first day's banner
}

async function gameScenario(browser, base, name, query, waitS, ctxOpts, extra = {}) {
	const log = [];
	const t0 = Date.now();
	const url = `${base}index.html${query}`;
	const { context, page } = await openPage(browser, ctxOpts, {}, log, t0);
	const out = { url, ok: false };
	let crashed = false;
	page.on('crash', () => {
		crashed = true;
	});
	try {
		await page.goto(url, { waitUntil: 'load', timeout: 120000 });
		await page.waitForFunction(() => (window.__pharos && window.__pharos.readyAt !== null && window.pharosShell && window.pharosShell.startedAt !== null)
			|| (window.pharosShell && window.pharosShell.failed), null, { timeout: opts.timeout * 1000, polling: 250 });
		const t = await page.evaluate(() => {
			const nav = performance.getEntriesByType('navigation')[0];
			const res = performance.getEntriesByType('resource').filter((r) => /\.(wasm|pck|js|ttf|woff2)$/.test(r.name)).map((r) => ({
				file: r.name.split('/').pop(), ms: Math.round(r.duration), transferKB: Math.round(r.transferSize / 1024), sizeKB: Math.round(r.decodedBodySize / 1024),
			}));
			return { failed: window.pharosShell.failed, readyAt: window.__pharos.readyAt, startedAt: window.pharosShell.startedAt,
				downloadedAt: window.pharosShell.downloadedAt, domContentLoaded: nav ? nav.domContentLoadedEventEnd : null, resources: res };
		});
		if (t.failed) {
			out.error = await page.evaluate(() => document.getElementById('status-notice').innerText);
			throw new Error(`the shell shows an error: ${out.error}`);
		}
		const m = log.map((e) => /world ready in (\d+) ms/.exec(e.text)).find(Boolean);
		out.loadMs = {
			domContentLoaded: round(t.domContentLoaded, 0),
			downloaded: round(t.downloadedAt, 0),
			worldReady: round(t.readyAt, 0),
			firstFrame: round(t.startedAt, 0),
			worldGenInEngine: m ? Number(m[1]) : null,
		};
		out.resources = t.resources;
		out.ok = true;
		const startAt = t.startedAt;
		// Scenario-specific wait.
		if (extra.night) {
			// SwiftShader frames are slow and Godot caps physics steps per frame, so speed=2 is far from 2x here: wait for
			// the night ("PHAROS phase NIGHT", plus a few seconds for the waves to land) instead of a fixed time, up to
			// --night-max.
			const minEnd = Date.now() + waitS * 1000;
			const maxEnd = Date.now() + Math.max(waitS, opts.nightMax) * 1000;
			let nightSeen = null;
			while (Date.now() < maxEnd && !crashed) {
				if (nightSeen === null) {
					const l = log.find((x) => /^PHAROS phase NIGHT\b/.test(x.text || ''));
					if (l) nightSeen = t0 + l.t;
				}
				if (Date.now() >= minEnd && nightSeen !== null && Date.now() - nightSeen >= 8000) {
					break;
				}
				await sleep(500);
			}
			const bot = log.some((x) => /^\[bot\] start/.test(x.text));
			out.night = {
				reached: nightSeen !== null,
				afterStartS: nightSeen !== null ? round((nightSeen - t0 - startAt) / 1000) : null,
				bot,
				botLines: log.filter((x) => /^\[bot\]/.test(x.text)).map((x) => x.text).slice(0, 60),
			};
			if (!bot) {
				out.night.hint = 'no "[bot] start" line: tools/bot.gd is not in this build (exclude_filter of the "Web" preset), or the build ignored the debug parameters (dev=1 missing?)';
			}
		} else if (extra.flow) {
			await flowSteps(page, log, out, waitS);
		} else {
			await sleep(waitS * 1000);
		}
		const now = await page.evaluate(() => performance.now());
		const data = await page.evaluate(() => ({
			frames: window.__pharos.frames,
			blocks: window.__pharos.audio.blocks,
			meter: window.__pharos.audio.meter,
			sources: window.__pharos.audio.sources,
			worklets: window.__pharos.audio.worklets,
			buffers: window.__pharos.audio.buffers,
			bufferBytes: window.__pharos.audio.bufferBytes,
			bufferLog: window.__pharos.audio.bufferLog,
			contexts: window.__pharos.audio.contexts.map((c) => ({ state: c.state, sampleRate: c.sampleRate, baseLatency: c.baseLatency })),
		}));
		const lastFrame = data.frames.length ? data.frames[data.frames.length - 1] : null;
		out.fps = {
			last5s: frameStats(data.frames, now - 5000, now),
			sinceStart: frameStats(data.frames, startAt, now),
			lastFrameAgoMs: lastFrame === null ? null : round(now - lastFrame, 0),
		};
		const minutes = Math.max(1 / 60, (now - startAt) / 60000);
		out.audio = {
			contexts: data.contexts,
			// Sample playback starts one AudioBufferSourceNode per voice; Stream mixes everything in the engine and feeds
			// a single AudioWorklet (Sample mode also creates that worklet, plus one position worklet per voice).
			mode: data.sources > 0 ? 'Sample' : data.worklets > 0 ? 'Stream' : 'none',
			workletNodes: data.worklets,
			bufferSourcesStarted: data.sources,
			// Sample playback: AudioBuffers created so far (decoded sounds, plus one copy per play() unless export_web.sh
			// patched that out of index.js; float PCM, cumulative: the memory churn)
			audioBuffersCreated: data.buffers,
			audioBuffersMB: round(data.bufferBytes / 1048576),
			// created in the last 30 s: after the start-up decoding this stays near 0 unless every play() copies its buffer
			audioBuffersMBLast30s: round(data.bufferLog.filter((b) => b[0] >= now - 30000).reduce((a, b) => a + b[1], 0) / 1048576),
			runSeconds: round(minutes * 60, 0),
			meter: data.meter,
			sinceStart: audioStats(data.blocks, startAt, now),
			last5s: audioStats(data.blocks, now - 5000, now),
		};
		out.canvas = await page.evaluate(() => {
			const c = document.getElementById('canvas');
			return { width: c.width, height: c.height, cssWidth: window.innerWidth, cssHeight: window.innerHeight, devicePixelRatio: window.devicePixelRatio,
				waitedForInput: window.pharosShell.waitedForInput, revealed: window.pharosShell.revealedAt !== null };
		});
		if (name === 'mobile') {
			const r = shellPixelRatio(PHONE_DPR, out.canvas.cssWidth, out.canvas.cssHeight);
			out.canvas.realDeviceWidth = Math.round(out.canvas.cssWidth * r);
			out.canvas.realDeviceHeight = Math.round(out.canvas.cssHeight * r);
			out.canvas.realDevicePixelRatio = round(r, 2);
		}
		out.screenshot = `${name}.png`;
		const shot = await capture(page, out.screenshot);
		out.screenshotFrom = shot.from;
		out.screenshotError = shot.error;
		out.image = shot.image;
	} catch (e) {
		out.error = out.error || errorText(e);
		try {
			await page.screenshot({ path: join(REPORT, `${name}_failed.png`), timeout: 60000 });
			out.screenshot = `${name}_failed.png`;
		} catch { /* page gone */ }
	}
	out.crashed = crashed;
	writeLog(name, log);
	const c = classify(log);
	out.console = { errors: c.errors, warnings: c.warnings, audio: c.audio };
	const problems = [];
	const warnings = [];
	if (!out.ok) problems.push(`did not start: ${out.error || '?'}`);
	else if (out.error) problems.push(`failed after start: ${out.error}`);
	if (crashed) problems.push('page crashed');
	if (c.errors.length) problems.push(`${c.errors.length} console error(s), first: ${c.errors[0].slice(0, 160)}`);
	if (out.fps) {
		// The engine asks for a frame after every frame it draws: none for 10 s means it is stuck (or has crashed).
		if (out.fps.sinceStart.frames < 2) problems.push('no frames drawn after the start');
		else if (out.fps.lastFrameAgoMs > 10000) problems.push(`no frame in the last ${round(out.fps.lastFrameAgoMs / 1000)} s (frozen?)`);
		else if (out.fps.last5s.frames < 2) warnings.push('fewer than 2 frames in the last 5 s (very slow software rendering?)');
	}
	if (out.audio) {
		// PHAROS always plays something once the island is up (the sea ambience under everything, music on top), so any
		// 5 s without sound is a fault.
		const a = out.audio;
		const idle = a.contexts.filter((x) => x.state !== 'running');
		if (!a.contexts.length) problems.push('the game created no AudioContext');
		else if (idle.length) problems.push(`audio context ${idle.map((x) => x.state).join(', ')} (should be running)`);
		if (a.meter !== 'ok') warnings.push(`audio not measured: ${a.meter}`);
		if (a.meter === 'ok') {
			if (a.sinceStart.seconds >= 4 && a.sinceStart.rmsDb === null) {
				problems.push(`no sound at all in ${a.sinceStart.seconds} s (${a.mode} playback)`);
			} else if (!a.last5s.seconds) {
				problems.push('no audio processed in the last 5 s (audio stopped?)');
			} else if (a.last5s.rmsDb === null) {
				problems.push(`silence in the last 5 s (${a.last5s.silentPct}% silent)`);
			}
			for (const [at, ms] of a.sinceStart.gapsAt || []) {
				if (ms >= 1000) problems.push(`${round(ms / 1000)} s of total silence ending ${at} s after the start (every voice stopped)`);
			}
		}
		if (a.sinceStart.peakDb !== null && a.sinceStart.peakDb > 0) warnings.push(`audio clips: peak +${a.sinceStart.peakDb} dBFS`);
		if (a.runSeconds >= 60 && a.audioBuffersMBLast30s > 30) {
			warnings.push(`${a.audioBuffersMBLast30s} MB of AudioBuffers created in the last 30 s (memory churn: sounds copied on every play()?)`);
		}
		if (a.audioBuffersMB > 200) warnings.push(`${a.audioBuffersMB} MB of decoded audio (a risk for phones with little memory)`);
	}
	if (out.ok && !out.error) {
		if (!out.image) problems.push('no screenshot of the game');
		else if (out.screenshotFrom !== 'canvas') problems.push(`the screenshot is a page capture, not an engine frame (${out.screenshotError})`);
	}
	if (out.titleScreenshotFrom && out.titleScreenshotFrom !== 'canvas') problems.push(`the title screenshot is a page capture, not an engine frame (${out.titleScreenshotError})`);
	if (out.image && out.image.darkPct > (extra.night ? 90 : 50)) {
		problems.push(`${out.image.darkPct}% of the frame is black (mean luma ${out.image.meanLuma})`);
	}
	// Every game scenario must reach its phase (Game.set_phase() prints "PHAROS phase <NAME> night N").
	const phases = phasesIn(log);
	out.phases = phases;
	if (out.ok && !phases.length) {
		problems.push('no "PHAROS phase <NAME>" line in the console (Game.set_phase() prints it): the game state cannot be checked');
	} else if (out.ok && extra.expect && !phases.includes(extra.expect)) {
		problems.push(`the game never reached ${extra.expect} (phases: ${phases.join(' ')})`);
	}
	if (extra.night && out.night && !out.night.reached) {
		problems.push(`the night never began in ${opts.nightMax} s (no "PHAROS phase NIGHT" line${out.night.bot ? '' : `; ${out.night.hint}`})`);
	}
	if (extra.flow && out.flow && phases.length && !out.flow.dayAfterEnter) {
		problems.push(`Enter on the title screen did not start the game in ${opts.flowMax} s (no "PHAROS phase DAY"; phases: ${out.flow.phases.join(' ')}; focus on ${out.flow.focus}): no title menu, or "Comenzar" not focused?`);
	}
	out.problems = problems;
	out.warnings = warnings;
	await context.close();
	return out;
}

// og: the link-preview image (og:image in the shell). The title screen exactly as the web build shows it, at
// 1200 x 630 CSS px rendered at 2x (3 MP: sharp text and edges once scaled down), saved as <report_dir>/og.jpg.
async function ogScenario(browser, base) {
	const out = { problems: [], warnings: [] };
	const log = [];
	const t0 = Date.now();
	const { context, page } = await openPage(browser, { viewport: { width: 1200, height: 630 }, deviceScaleFactor: 2 }, {}, log, t0);
	try {
		await page.goto(base + 'index.html', { waitUntil: 'load', timeout: 120000 });
		await page.waitForFunction(() => window.pharosShell && (window.pharosShell.revealedAt !== null || window.pharosShell.failed), null,
			{ timeout: opts.timeout * 1000, polling: 250 });
		// The loading screen fades out in 1 s and the title's logo and menu fade in over ~2.5 s of game time.
		await page.waitForFunction(() => document.getElementById('status').hidden, null, { timeout: 30000, polling: 250 });
		await sleep(opts.titleWait * 1000);
		const shot = await capture(page, 'og_2x.png');
		out.image = shot.image;
		if (shot.from !== 'canvas') throw new Error(`no engine frame to capture (${shot.error})`);
		const jpg = await page.evaluate(async () => {
			const img = new Image();
			img.src = window.__pharos.capture;
			await img.decode();
			const c = document.createElement('canvas');
			c.width = 1200;
			c.height = 630;
			const g = c.getContext('2d');
			g.imageSmoothingEnabled = true;
			g.imageSmoothingQuality = 'high';
			g.drawImage(img, 0, 0, c.width, c.height);
			return { size: [img.naturalWidth, img.naturalHeight], url: c.toDataURL('image/jpeg', 0.88) };
		});
		out.source = jpg.size;
		writeFileSync(join(REPORT, 'og.jpg'), Buffer.from(jpg.url.slice(jpg.url.indexOf(',') + 1), 'base64'));
		out.file = join(REPORT, 'og.jpg');
		out.bytes = statSync(out.file).size;
		if (!phasesIn(log).includes('TITLE')) out.problems.push('the title screen never showed (no "PHAROS phase TITLE")');
	} catch (e) {
		out.error = errorText(e);
		out.problems.push(out.error);
	}
	await context.close();
	writeLog('og', log);
	const c = classify(log);
	out.console = { errors: c.errors, warnings: c.warnings };
	if (c.errors.length) out.problems.push(`${c.errors.length} console error(s), first: ${c.errors[0].slice(0, 160)}`);
	return out;
}

// --- main ---------------------------------------------------------------------------------------------------------

const server = createServer(serve);
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}${MOUNT}`;
const browser = await launch();
const report = {
	date: new Date().toISOString(),
	build: ROOT,
	url: base,
	browser: `Chromium ${browser.version()}`,
	gzip: opts.gzip,
	files: {},
	scenarios: {},
};
for (const f of readdirSync(ROOT, { recursive: true })) {
	const p = join(ROOT, f);
	if (statSync(p).isFile()) report.files[relative(ROOT, p).split(sep).join('/')] = statSync(p).size;
}
// export_web.sh patches Godot's web audio in index.js: sounds share their decoded AudioBuffer instead of copying it on
// every play(), and looping sounds loop on the audio thread instead of being restarted from the main thread.
{
	const js = readFileSync(join(ROOT, 'index.js'), 'utf8');
	report.audioBufferShared = js.includes('getAudioBuffer(){return this._audioBuffer}');
	report.audioLoopNative = js.includes('this._source.loop=true');
}
{
	const ctx = await browser.newContext();
	const page = await ctx.newPage();
	await page.goto(base + 'README.md');
	report.webgl = await page.evaluate(() => {
		const gl = document.createElement('canvas').getContext('webgl2');
		if (!gl) return { webgl2: false };
		const ext = gl.getExtension('WEBGL_debug_renderer_info');
		return { webgl2: true, version: gl.getParameter(gl.VERSION), renderer: ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER),
			maxTextureSize: gl.getParameter(gl.MAX_TEXTURE_SIZE), maxUniformBlockSize: gl.getParameter(gl.MAX_UNIFORM_BLOCK_SIZE) };
	});
	await ctx.close();
}
console.log(`web_test: ${base} (${ROOT}) with ${report.browser}; ${report.webgl.renderer || 'no WebGL 2'}`);
if (!report.audioBufferShared || !report.audioLoopNative) {
	console.log('web_test: warning: index.js lacks the web audio fixes of pharos/tools/export_web.sh (copies of every sound on each play(),'
		+ ' gaps at every music loop): export with that script');
}

const problems = [];
const warnings = [];
for (const name of [...ALL, ...EXTRA].filter((s) => opts.only.includes(s))) {
	const started = Date.now();
	process.stdout.write(`-- ${name} ... `);
	let r;
	if (name === 'shell') r = await shellScenario(browser, base);
	else if (name === 'og') r = await ogScenario(browser, base);
	else if (name === 'gate') r = await gateScenario(browser, base);
	else if (name === 'title') r = await gameScenario(browser, base, 'title', '', opts.titleWait, DESKTOP, { expect: 'TITLE' });
	else if (name === 'flow') r = await gameScenario(browser, base, 'flow', '', opts.titleWait, DESKTOP, { flow: true, expect: 'TITLE' });
	else if (name === 'play') r = await gameScenario(browser, base, 'play', '?dev=1&play=1', opts.playWait, DESKTOP, { expect: 'DAY' });
	else if (name === 'night') r = await gameScenario(browser, base, 'night', opts.nightQuery, opts.nightWait, DESKTOP, { night: true, expect: 'NIGHT' });
	else if (name === 'mobile') r = await gameScenario(browser, base, 'mobile', '', opts.titleWait, PHONE_LANDSCAPE, { expect: 'TITLE' });
	r.wallS = round((Date.now() - started) / 1000);
	report.scenarios[name] = r;
	for (const p of r.problems || []) problems.push(`${name}: ${p}`);
	for (const w of r.warnings || []) warnings.push(`${name}: ${w}`);
	const bits = [];
	if (r.download25MbitS != null) bits.push(`download at 25 Mbit/s ${r.download25MbitS} s`);
	if (r['loading_mobile.png'] && r['loading_mobile.png'].pixelRatio) {
		const pr = r['loading_mobile.png'].pixelRatio;
		bits.push(`phone pixel ratio ${round(pr.used, 2)} (device ${pr.device})`);
	}
	if (r.loadMs) bits.push(`first frame ${r.loadMs.firstFrame} ms (world ${r.loadMs.worldGenInEngine} ms)`);
	if (r.fps) bits.push(`${r.fps.last5s.fps} fps (max frame ${r.fps.last5s.maxMs} ms)`);
	if (r.audio) {
		bits.push(`audio ${r.audio.mode} ${r.audio.sinceStart.rmsDb} dBFS rms, peak ${r.audio.sinceStart.peakDb}, ${r.audio.sinceStart.gaps || 0} gaps (${r.audio.sinceStart.gapMs || 0} ms)`
			+ (r.audio.audioBuffersCreated ? `, ${r.audio.audioBuffersMB} MB of AudioBuffers created (${r.audio.audioBuffersMBLast30s} MB in the last 30 s)` : ''));
	}
	if (r.image) bits.push(`frame luma ${r.image.meanLuma}, ${r.image.darkPct}% black`);
	if (r.night) bits.push(r.night.reached ? `night at +${r.night.afterStartS} s` : 'night NOT reached');
	if (r.flow) bits.push(r.flow.dayAfterEnter ? `title -> DAY ${r.flow.afterEnterS} s after Enter` : 'Enter on the title led NOWHERE');
	if (r.file) bits.push(`${r.file} (${Math.round(r.bytes / 1024)} KB, from ${r.source.join('x')})`);
	if (r.noWebGL2Ok !== undefined) bits.push(`no-WebGL2 message ${r.noWebGL2Ok ? 'ok' : 'MISSING'}`);
	if (r.after) bits.push(`after the click: audio ${r.after.audio.join(',')}, focus ${r.after.focus}`);
	if (r.touch && r.touch.after) bits.push(`after the tap: audio ${r.touch.after.audio.join(',')}, ${r.touch.after.canvasEvents.length} events on the canvas, rotate screen ${r.touch.after.rotatePrompt ? 'shown' : 'NOT shown'}`);
	if (r.canvas) bits.push(`canvas ${r.canvas.width}x${r.canvas.height} (DPR ${r.canvas.devicePixelRatio})`);
	if (r.console) bits.push(`${r.console.errors.length} errors, ${r.console.warnings.length} warnings`);
	console.log(`${r.problems && r.problems.length ? 'PROBLEM' : 'ok'} in ${r.wallS} s: ${bits.join('; ')}`);
	for (const p of r.problems || []) console.log(`   ! ${p}`);
	for (const w of r.warnings || []) console.log(`   ~ ${w}`);
}
await browser.close();
server.close();
report.problems = problems;
report.warnings = warnings;
writeFileSync(join(REPORT, 'report.json'), JSON.stringify(report, null, '\t') + '\n');
console.log(`web_test: ${problems.length ? `${problems.length} problem(s)` : 'no problems'}${warnings.length ? `, ${warnings.length} warning(s)` : ''}; report in ${join(REPORT, 'report.json')}`);
process.exit(problems.length ? 1 : 0);
