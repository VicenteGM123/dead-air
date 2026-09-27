// Bundles src/main.js -> build/game.js as a classic IIFE script so index.html
// works when opened straight from disk (file://), no server needed.
import * as esbuild from 'esbuild';
const args = process.argv.slice(2);
const min = args.includes('--min');
const opts = {
  entryPoints: ['src/main.js'],
  bundle: true,
  format: 'iife',
  target: ['es2022'],
  outfile: 'build/game.js',
  minify: min,
  sourcemap: min ? false : 'inline',
  legalComments: 'none',
  logLevel: 'info',
  loader: { '.woff2': 'dataurl', '.bin': 'binary' },
};
if (args.includes('--watch')) {
  const ctx = await esbuild.context(opts);
  await ctx.watch();
  console.log('watching...');
} else {
  const r = await esbuild.build({ ...opts, metafile: true });
  const out = r.metafile.outputs['build/game.js'];
  console.log(`build ok: ${(out.bytes / 1024).toFixed(0)} KB`);
}
