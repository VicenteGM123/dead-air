// Bundled fonts (GDD §14): Titan One (HUD digits, prompt tape), VT323 (ammo counter), Shrikhand (chyron, logo,
// title), Bungee (in-world signage/posters). esbuild inlines the .woff2 files as data URLs, so the game has no
// network requests. loadFonts() registers them with document.fonts and resolves when they are ready.

import shrikhand from '@fontsource/shrikhand/files/shrikhand-latin-400-normal.woff2';
import titanOne from '@fontsource/titan-one/files/titan-one-latin-400-normal.woff2';
import vt323 from '@fontsource/vt323/files/vt323-latin-400-normal.woff2';
import bungee from '@fontsource/bungee/files/bungee-latin-400-normal.woff2';

export const FONTS = {
  hud: '"Titan One", "Arial Black", sans-serif',
  tape: '"VT323", "Courier New", monospace',
  logo: '"Shrikhand", "Georgia", serif',
  sign: '"Bungee", "Arial Black", sans-serif',
};

const SOURCES = [
  ['Shrikhand', shrikhand],
  ['Titan One', titanOne],
  ['VT323', vt323],
  ['Bungee', bungee],
];

let loading = null;

export function loadFonts() {
  if (loading) return loading;
  loading = Promise.all(SOURCES.map(async ([family, url]) => {
    const face = new FontFace(family, `url(${url})`);
    document.fonts.add(face);
    await face.load();
    return face;
  }));
  return loading;
}
