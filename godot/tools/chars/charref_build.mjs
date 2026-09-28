// chars-godot: bundles charref_entry.js into <out>/mref.js + mref.html (same page tools/jsref/run.mjs drives).
// Bundles entry.js into <out>/mref.js (esbuild from the repo's node_modules). Usage: node build.mjs <outDir>
import * as esbuild from '/home/user/dead-air/node_modules/esbuild/lib/main.js';
import path from 'path';
import fs from 'fs';
const out = process.argv[2] || '.';
fs.mkdirSync(out, { recursive: true });
await esbuild.build({ entryPoints: [new URL('./charref_entry.js', import.meta.url).pathname], bundle: true,
  format: 'iife', target: ['es2022'], outfile: path.join(out, 'mref.js'), loader: { '.woff2': 'dataurl', '.bin': 'binary' },
  nodePaths: ['/home/user/dead-air/node_modules'], logLevel: 'warning' });
fs.writeFileSync(path.join(out, 'mref.html'), '<!DOCTYPE html><html><head><meta charset="utf-8"><style>html,body{margin:0;height:100%;overflow:hidden;background:#000}</style></head><body><script src="mref.js"></script></body></html>');
console.log('ok', out);
