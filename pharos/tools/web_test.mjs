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
//   --only <list>        scenarios, comma separated (default: shell,gate,title,play,night,mobile)
//                          shell   loading screen on a throttled connection (desktop + phone portrait) and the
//                                  "no WebGL 2" message                      -> loading.png, loading_mobile.png,
//                                                                               error_webgl2.png
//                          gate    autoplay blocked (emulated): the loaded shell waits for "Pulsa para entrar",
//                                  a click starts the sound, reveals the game and gives the canvas the keyboard
//                                                                            -> gate.png, gate_after.png
//                          title   index.html, screenshot ~8 s after start  -> title.png
//                          play    ?play=1                                   -> play.png
//                          night   --night-query: >= --night-wait s and until the bot's night has begun (at most
//                                  --night-max s; tools/bot.gd ships in the "Web" build)          -> night.png
//                          mobile  title on an emulated phone in landscape (863 x 360 CSS px, touch, DPR 1)
//                                                                            -> mobile.png
//   --title-wait <s>     default 8     --play-wait <s>   default 10     --night-wait <s>   default 40
//   --night-max <s>      default 240   --timeout <s>     max wait for the game to start, default 180
//   --night-query <q>    default ?play=1&bot=1&speed=2&startnight=1&nearfight=1 (startnight/nearfight: the night
//                        and its first creatures arrive at once, so the shot shows combat even on a software GPU)
//   --chrome <path>      Chromium/Chrome executable (default: Playwright's, then $PLAYWRIGHT_BROWSERS_PATH)
//   --headed             show the browser window      --no-gzip   serve without compression
//
// Writes <report_dir>/report.json, the PNGs and console-<scenario>.log. Each scenario lists its "problems" (did not
// start, crashed, console errors, no sound at all, a mostly black frame, no Spanish WebGL 2 message); exits 1 if any.
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

const ALL = ['shell', 'gate', 'title', 'play', 'night', 'mobile'];
const opts = {
	report: null,
	dir: join(HERE, '..', 'web'),
	only: ALL,
	titleWait: 8,
	playWait: 10,
	nightWait: 40,
	nightMax: 240,
	nightQuery: '?play=1&bot=1&speed=2&startnight=1&nearfight=1',
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
		console.error('usage: node web_test.mjs <report_dir> [--dir pharos/web] [--only shell,gate,title,play,night,mobile]');
		process.exit(2);
	}
	for (const s of opts.only) {
		if (!ALL.includes(s)) throw new Error(`unknown scenario ${s} (${ALL.join(', ')})`);
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
		audio: { contexts: [], blocks: [], sources: 0, worklets: 0, buffers: 0, bufferBytes: 0, meter: 'pending' },
	};
	// FPS: count animation frames. Screenshots: Godot draws inside requestAnimationFrame and its WebGL canvas is not
	// preserved after compositing, so the canvas is read right after a (non-instrumentation) frame callback; this
	// works even when SwiftShader frames take seconds, where a CDP screenshot may time out.
	const raf = window.requestAnimationFrame.bind(window);
	const tick = (t) => {
		P.frames.push(t);
		raf(tick);
	};
	raf(tick);
	window.requestAnimationFrame = function (cb) {
		return raf((t) => {
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
	// render quanta between non-silent ones. PHAROS always plays the sea ambience once the title is up, so with the
	// Stream playback type a gap is a buffer underrun of the engine's mixer (main thread too busy to mix in time).
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
		// all-zero stretches after the first sound: buffer underruns with the Stream playback type
		gaps: w.reduce((a, b) => a + b[5], 0),
		gapMs: round((gapQuanta * 128 * 1000) / rate, 0),
	};
}

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
// The in-game phone scenario keeps the phone's layout (863 x 360 CSS px, touch, mobile UA) but renders at DPR 1:
// at the real DPR (2.625) the engine draws 2265 x 945 pixels, which SwiftShader cannot do in useful time. The report
// still states the canvas size a real Pixel 7 gets (canvas.realDeviceWidth/Height).
const PHONE_DPR = (devices['Pixel 7 landscape'] || PHONE).deviceScaleFactor;
const PHONE_LANDSCAPE = { ...(devices['Pixel 7 landscape'] || { ...PHONE, viewport: { width: 863, height: 360 } }), deviceScaleFactor: 1 };

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

async function shellScenario(browser, base) {
	const out = { screenshots: [], problems: [] };
	const log = [];
	const t0 = Date.now();
	// Loading screen mid-download on a ~25 Mbit/s connection, desktop and phone portrait.
	for (const [file, ctxOpts] of [['loading.png', DESKTOP], ['loading_mobile.png', PHONE]]) {
		const { context, page } = await openPage(browser, ctxOpts, {}, log, t0);
		await throttle(context, page, 25);
		await page.goto(base + 'index.html', { waitUntil: 'domcontentloaded' });
		try {
			await page.waitForFunction(() => window.pharosShell && window.pharosShell.progress >= 0.3, null, { timeout: 60000, polling: 100 });
			await sleep(400); // fonts and the rise-in animation
			await page.screenshot({ path: join(REPORT, file) });
			out.screenshots.push(file);
			out[file] = await page.evaluate(() => ({ progress: window.pharosShell.progress, text: document.getElementById('status-text').textContent,
				fonts: [...document.fonts].filter((f) => f.status === 'loaded').map((f) => `${f.family} ${f.weight}`) }));
			if (file === 'loading.png') {
				// The whole download (wasm + pck, gzip where the server compresses) at 25 Mbit/s with 60 ms latency.
				await page.waitForFunction(() => window.pharosShell.downloadedAt !== null || window.pharosShell.failed, null, { timeout: 120000, polling: 100 });
				out.download25MbitS = await page.evaluate(() => Math.round(window.pharosShell.downloadedAt / 100) / 10);
			}
		} catch (e) {
			out[file] = { error: String(e.message || e).split('\n')[0] };
			out.problems.push(`${file}: ${out[file].error}`);
		}
		await context.close();
	}
	// Browser without WebGL 2: the Spanish error message.
	{
		const { context, page } = await openPage(browser, DESKTOP, { noWebGL2: true }, log, t0);
		await page.goto(base + 'index.html', { waitUntil: 'load' });
		await sleep(1500);
		const notice = await page.evaluate(() => {
			const n = document.getElementById('status-notice');
			return n && !n.hidden ? n.innerText : null;
		});
		await page.screenshot({ path: join(REPORT, 'error_webgl2.png') });
		out.screenshots.push('error_webgl2.png');
		out.noWebGL2Notice = notice;
		out.noWebGL2Ok = !!notice && /WebGL 2/.test(notice);
		if (!out.noWebGL2Ok) {
			out.problems.push('no Spanish "WebGL 2" message when WebGL 2 is missing');
		}
		await context.close();
	}
	writeLog('shell', log);
	const c = classify(log);
	out.console = { errors: c.errors, warnings: c.warnings };
	return out;
}

// A browser that keeps pages silent until the first interaction (the default everywhere): the loaded shell must
// wait with "Pulsa para entrar", and one click must start the sound, fade the loading screen and leave the keyboard
// with the game canvas.
// (Headless Chromium never blocks sound, so the usual policy is emulated in instrument(): blockAutoplay.)
async function gateScenario(browser, base) {
	const out = { screenshots: [], problems: [] };
	const log = [];
	const t0 = Date.now();
	const { context, page } = await openPage(browser, DESKTOP, { blockAutoplay: true }, log, t0);
	try {
		await page.goto(base + 'index.html', { waitUntil: 'load', timeout: 120000 });
		await page.waitForFunction(() => window.pharosShell && (window.pharosShell.phase === 'ready' || window.pharosShell.revealedAt !== null
			|| window.pharosShell.failed), null, { timeout: opts.timeout * 1000, polling: 250 });
		const before = await page.evaluate(() => ({ phase: window.pharosShell.phase, text: document.getElementById('status-text').textContent,
			audio: (window.pharosAudioContexts || []).map((c) => c.state), failed: window.pharosShell.failed }));
		out.before = before;
		await sleep(1200);
		await page.screenshot({ path: join(REPORT, 'gate.png'), timeout: 90000 });
		out.screenshots.push('gate.png');
		if (before.phase !== 'ready') {
			out.problems.push(`the loaded shell did not wait for a first input (phase ${before.phase}, audio ${before.audio.join(',') || 'none'})`);
		} else {
			await page.mouse.click(640, 360);
			await page.waitForFunction(() => window.pharosShell.revealedAt !== null, null, { timeout: 10000, polling: 100 });
			await page.waitForFunction(() => (window.pharosAudioContexts || []).every((c) => c.state === 'running'), null, { timeout: 10000, polling: 100 })
				.catch(() => {});
			await sleep(2500);
			out.after = await page.evaluate(() => ({ audio: (window.pharosAudioContexts || []).map((c) => c.state),
				overlayHidden: document.getElementById('status').hidden, focus: document.activeElement ? (document.activeElement.id || document.activeElement.tagName) : null }));
			const shot = await capture(page, 'gate_after.png');
			out.screenshots.push('gate_after.png');
			out.image = shot.image;
			if (!out.after.audio.length || out.after.audio.some((s) => s !== 'running')) {
				out.problems.push(`sound did not start after the click (${out.after.audio.join(',') || 'no AudioContext'})`);
			}
			if (!out.after.overlayHidden) out.problems.push('the loading screen did not go away after the click');
			if (out.after.focus !== 'canvas') out.problems.push(`keyboard focus is on ${out.after.focus}, not on the game canvas`);
		}
	} catch (e) {
		out.error = String((e && e.message) || e).split('\n')[0];
		out.problems.push(out.error);
	}
	await context.close();
	writeLog('gate', log);
	const c = classify(log);
	out.console = { errors: c.errors, warnings: c.warnings };
	return out;
}

// Screenshot of the game canvas taken right after an engine frame (see instrument()); falls back to a CDP screenshot.
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
		return { from: 'canvas', image: await imageStats(page) };
	} catch {
		await page.screenshot({ path: join(REPORT, file), timeout: 120000 });
		return { from: 'page', image: null };
	}
}

// Mean luma (0..255) of the captured frame, and the share of near-black (< 10) and of blown-out (> 250) pixels.
function imageStats(page) {
	return page.evaluate(async () => {
		const img = new Image();
		img.src = window.__pharos.capture;
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
	});
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
			const res = performance.getEntriesByType('resource').filter((r) => /\.(wasm|pck|js|ttf)$/.test(r.name)).map((r) => ({
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
			// the bot's night (plus a few seconds for the waves to land) instead of a fixed time, up to --night-max.
			const minEnd = Date.now() + waitS * 1000;
			const maxEnd = Date.now() + Math.max(waitS, opts.nightMax) * 1000;
			let nightSeen = null;
			while (Date.now() < maxEnd && !crashed) {
				if (nightSeen === null && log.some((x) => /^\[bot\].*phase=NIGHT/.test(x.text))) {
					nightSeen = Date.now();
				}
				const bot = log.some((x) => /^\[bot\] start/.test(x.text));
				if (Date.now() >= minEnd && (!bot || (nightSeen !== null && Date.now() - nightSeen >= 8000))) {
					break;
				}
				await sleep(500);
			}
			out.bot = {
				available: log.some((x) => /^\[bot\] start/.test(x.text)),
				nightReached: nightSeen !== null,
				nightAfterStartS: nightSeen !== null ? round((nightSeen - t0 - startAt) / 1000) : null,
				lines: log.filter((x) => /^\[bot\]/.test(x.text)).map((x) => x.text).slice(0, 60),
			};
			if (!out.bot.available) {
				out.bot.hint = 'tools/bot.gd is not in this build (check exclude_filter of the "Web" preset in export_presets.cfg)';
			}
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
			contexts: window.__pharos.audio.contexts.map((c) => ({ state: c.state, sampleRate: c.sampleRate, baseLatency: c.baseLatency })),
		}));
		out.fps = {
			last5s: frameStats(data.frames, now - 5000, now),
			sinceStart: frameStats(data.frames, startAt, now),
		};
		out.audio = {
			contexts: data.contexts,
			// Sample playback starts one AudioBufferSourceNode per voice; Stream mixes everything in the engine and feeds
			// a single AudioWorklet (Sample mode also creates that worklet, plus one position worklet per voice).
			mode: data.sources > 0 ? 'Sample' : data.worklets > 0 ? 'Stream' : 'none',
			workletNodes: data.worklets,
			bufferSourcesStarted: data.sources,
			// Sample playback: AudioBuffers created so far (decoded sounds + one copy per play(), float PCM, cumulative)
			audioBuffersCreated: data.buffers,
			audioBuffersMB: round(data.bufferBytes / 1048576),
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
			out.canvas.realDeviceWidth = Math.round(out.canvas.cssWidth * PHONE_DPR);
			out.canvas.realDeviceHeight = Math.round(out.canvas.cssHeight * PHONE_DPR);
		}
		out.screenshot = `${name}.png`;
		const shot = await capture(page, out.screenshot);
		out.screenshotFrom = shot.from;
		out.image = shot.image;
	} catch (e) {
		out.error = out.error || String((e && e.message) || e).split('\n')[0];
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
	if (!out.ok) problems.push(`did not start: ${out.error || '?'}`);
	if (crashed) problems.push('page crashed');
	if (c.errors.length) problems.push(`${c.errors.length} console error(s), first: ${c.errors[0].slice(0, 160)}`);
	if (out.audio && out.audio.meter === 'ok' && out.audio.sinceStart.seconds >= 4 && out.audio.sinceStart.rmsDb === null) {
		problems.push(`no sound at all in ${out.audio.sinceStart.seconds} s (${out.audio.mode} playback)`);
	}
	if (out.image && out.image.darkPct > (extra.night ? 90 : 50)) {
		problems.push(`${out.image.darkPct}% of the frame is black (mean luma ${out.image.meanLuma})`);
	}
	if (extra.night && out.bot && out.bot.available && !out.bot.nightReached) problems.push('the bot never reached the night');
	out.problems = problems;
	await context.close();
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

const problems = [];
for (const name of ALL.filter((s) => opts.only.includes(s))) {
	const started = Date.now();
	process.stdout.write(`-- ${name} ... `);
	let r;
	if (name === 'shell') r = await shellScenario(browser, base);
	else if (name === 'gate') r = await gateScenario(browser, base);
	else if (name === 'title') r = await gameScenario(browser, base, 'title', '', opts.titleWait, DESKTOP);
	else if (name === 'play') r = await gameScenario(browser, base, 'play', '?play=1', opts.playWait, DESKTOP);
	else if (name === 'night') r = await gameScenario(browser, base, 'night', opts.nightQuery, opts.nightWait, DESKTOP, { night: true });
	else if (name === 'mobile') r = await gameScenario(browser, base, 'mobile', '', opts.titleWait, PHONE_LANDSCAPE);
	r.wallS = round((Date.now() - started) / 1000);
	report.scenarios[name] = r;
	for (const p of r.problems || []) problems.push(`${name}: ${p}`);
	const bits = [];
	if (r.download25MbitS != null) bits.push(`download at 25 Mbit/s ${r.download25MbitS} s`);
	if (r.loadMs) bits.push(`first frame ${r.loadMs.firstFrame} ms (world ${r.loadMs.worldGenInEngine} ms)`);
	if (r.fps) bits.push(`${r.fps.last5s.fps} fps (max frame ${r.fps.last5s.maxMs} ms)`);
	if (r.audio) {
		bits.push(`audio ${r.audio.mode} ${r.audio.sinceStart.rmsDb} dBFS rms, ${r.audio.sinceStart.gaps || 0} gaps (${r.audio.sinceStart.gapMs || 0} ms)`
			+ (r.audio.audioBuffersCreated ? `, ${r.audio.audioBuffersMB} MB of AudioBuffers created` : ''));
	}
	if (r.image) bits.push(`frame luma ${r.image.meanLuma}, ${r.image.darkPct}% black`);
	if (r.bot) bits.push(r.bot.available ? `bot night ${r.bot.nightReached ? `at +${r.bot.nightAfterStartS} s` : 'NOT reached'}` : 'no bot in build');
	if (r.noWebGL2Ok !== undefined) bits.push(`no-WebGL2 message ${r.noWebGL2Ok ? 'ok' : 'MISSING'}`);
	if (r.after) bits.push(`after the click: audio ${r.after.audio.join(',')}, focus ${r.after.focus}`);
	if (r.canvas) bits.push(`canvas ${r.canvas.width}x${r.canvas.height} (DPR ${r.canvas.devicePixelRatio})`);
	if (r.console) bits.push(`${r.console.errors.length} errors, ${r.console.warnings.length} warnings`);
	console.log(`${r.problems && r.problems.length ? 'PROBLEM' : 'ok'} in ${r.wallS} s: ${bits.join('; ')}`);
	for (const p of r.problems || []) console.log(`   ! ${p}`);
}
await browser.close();
server.close();
report.problems = problems;
writeFileSync(join(REPORT, 'report.json'), JSON.stringify(report, null, '\t') + '\n');
console.log(`web_test: ${problems.length ? `${problems.length} problem(s)` : 'no problems'}; report in ${join(REPORT, 'report.json')}`);
process.exit(problems.length ? 1 : 0);
