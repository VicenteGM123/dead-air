// Drives mref.html in Chromium (Playwright, SwiftShader GL).
//   node run.mjs <outDir> shot <scene.json> <out.png>     reference render of a material_test scene (1280x720)
//   node run.mjs <outDir> env <out.bin>                    RoomEnvironment PMREM atlas (RGBA16F raw, 768x1024)
// PW = the Playwright module path (SPEC §8).
import fs from 'fs';
import path from 'path';
const PW = process.env.PW || '/tmp/claude-0/-home-user-dead-air/8458c55b-456c-5c02-b3dd-b7ced50b0561/scratchpad/pw/node_modules/playwright/index.mjs';
const { chromium } = await import(PW);
const [,, dir, mode, a, b] = process.argv;
const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--allow-file-access-from-files'] });
const p = await br.newPage({ viewport: { width: 1280, height: 720 } });
p.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') console.log(m.type(), m.text().slice(0, 300)); });
p.on('pageerror', (e) => console.log('PAGEERR', e.message));
await p.goto('file://' + path.resolve(dir, 'mref.html'), { waitUntil: 'load' });
await p.waitForFunction(() => !!window.__mref);
if (mode === 'env') {
  const r = await p.evaluate(() => window.__mref.bakeEnv());
  fs.writeFileSync(a, Buffer.from(r.b64, 'base64'));
  console.log('env', r.w, r.h, a);
} else {
  const spec = JSON.parse(fs.readFileSync(a, 'utf8'));
  const base = 'file://' + path.dirname(path.resolve(a)) + '/';
  const r = await p.evaluate(async ([s, base]) => await window.__mref.run(s, base), [spec, base]);
  fs.writeFileSync(b, Buffer.from(r.png.split(',')[1], 'base64'));
  console.log('shot', r.w, r.h, b, JSON.stringify(r.probe));
}
await br.close();
