// chars-godot QA: bundles char_dump_entry.js -> char_dump.mjs (node char_dump_build.mjs).
import * as esbuild from '/home/user/dead-air/node_modules/esbuild/lib/main.js';
await esbuild.build({ entryPoints: [new URL('./char_dump_entry.js', import.meta.url).pathname], bundle: true, platform: 'node', format: 'esm', outfile: new URL('./char_dump.mjs', import.meta.url).pathname,
  loader: { '.bin': 'binary', '.woff2': 'dataurl' }, nodePaths: ['/home/user/dead-air/node_modules'], logLevel: 'warning', banner: { js: "if (!Uint8Array.fromBase64) Uint8Array.fromBase64 = (s) => new Uint8Array(Buffer.from(s, 'base64'));" } });
console.log('ok');
