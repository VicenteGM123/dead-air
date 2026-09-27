// Seeded randomness: mulberry32 plus the small helpers gameplay code needs.
// game.rand() is the seeded stream (ARCHITECTURE §1); cosmetics may use Math.random().

export function mulberry32(seed) {
  let a = seed >>> 0;
  return function rand() {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Helpers bound to any () => [0,1) source (defaults to Math.random).
export const range = (min, max, r = Math.random) => min + (max - min) * r();
export const rangeInt = (min, max, r = Math.random) => Math.floor(min + (max - min + 1) * r());
export const pick = (arr, r = Math.random) => arr[Math.floor(r() * arr.length)];
export const chance = (p, r = Math.random) => r() < p;

// In-place Fisher-Yates shuffle.
export function shuffle(arr, r = Math.random) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(r() * (i + 1));
    const t = arr[i]; arr[i] = arr[j]; arr[j] = t;
  }
  return arr;
}

// Weighted pick over { key: weight } -> key (null if all weights are 0).
export function weighted(weights, r = Math.random) {
  let total = 0;
  for (const k in weights) total += weights[k];
  if (total <= 0) return null;
  let x = r() * total;
  for (const k in weights) {
    x -= weights[k];
    if (x < 0) return k;
  }
  return null;
}

// Cheap deterministic hash noise in [0,1) for cosmetic jitter (no allocation).
export function hash1(n) {
  const s = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return s - Math.floor(s);
}

// Smooth 1D value noise in [-1,1] (used by shake, flicker, wobble).
export function noise1(x) {
  const i = Math.floor(x);
  const f = x - i;
  const u = f * f * (3 - 2 * f);
  return (hash1(i) * (1 - u) + hash1(i + 1) * u) * 2 - 1;
}
