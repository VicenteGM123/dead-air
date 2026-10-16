// DOCE shared wind: one wind for the meadow grass, the flowers, the wheat and the foliage of trees and shrubs, so
// everything moves together. Include it AFTER pharos.gdshaderinc (uses g_time and g_wind).
//
// Global uniforms (declared in project.godot, driven every frame by scripts/world/wind.gd):
//   g_wind       float  (pharos.gdshaderinc, set by TimeOfDay's mood) overall strength, 1 = a fresh breeze
//   g_wind_dir   vec2   unit XZ direction the wind blows TOWARDS (default east-south-east, with the clouds); it breathes
//                       by a few degrees over half a minute and only LEANS things: the waves below do not follow it
//   g_wind_gust  vec4   x gust strength (how far the travelling waves bend things, 0..1.5)
//                       y gust wavelength in metres (size of the waves rolling over the meadow)
//                       z gust speed in m/s (how fast the waves travel)
//                       w tip sway amount (0..1; slow and small, see wind_flutter)
//   g_push_a     mat4   up to four pushers (hero, beasts): column i = head (x, y, z, radius m); radius 0 = unused
//   g_push_b     mat4   column i = tail (x, y, z, strength 0..1 at the tail): the head's position a moment ago,
//                       so the plants it went through spring back along a soft trail
//
// ALWAYS FLUID (client report, 2026-10: "the grass is perfect for a second, then it trembles from side to side for five
// seconds, and so on for ever"). The wind it replaces had one slow component (travelling gust fronts, switched off for
// 56% of the time and in lulls of 10-50 s by an amplitude gate and a folding noise warp) and two fast ones that never
// stopped (a fast noise turning each clump about its root at ~2 Hz, a per-blade tip flutter at 1.0 and 1.45 Hz): in a
// lull only the trembling was left, between two crests it was all there was. Now:
//   * every visible temporal frequency is below ~1 Hz: the waves roll at ~0.27 Hz (period L / speed = 3.7 s) with a
//     little harmonic content, the clump-to-clump ripple is <= 0.17 Hz, the tip sway 0.33 Hz;
//   * the waves never stop: two overlapping trains and a drifting envelope that never goes below 45%, so at any
//     moment, anywhere, something is gently rolling through (a crest rises in ~0.9 s, as the old ones did);
//   * only sines of range-reduced phases (wind_cyc): no hash noise, no lattice advected by the clock (the old fast
//     noise lost its randomness as the session went on: its hash degenerates when the lattice coordinate reaches the
//     thousands, 2785 distinct values at the start, 134 after half an hour), no discontinuity, the same result on any GPU
//     after any session length;
//   * the wave phase uses a FIXED direction: when g_wind_dir breathed, the far fronts slid by metres per second.
// Checked, not assumed: tools/wind_probe.tscn renders these functions (every pixel one value, 16 bits) and the images match a
// float32 Python port of the same maths to 2e-5 (tools/wind_clock_test.tscn tests the clock that drives them).

global uniform vec2 g_wind_dir;
global uniform vec4 g_wind_gust;
global uniform mat4 g_push_a;
global uniform mat4 g_push_b;

#define WIND_NEW 1   // (marker: this is the always-fluid wind; tools/wind_probe.gdshader tests for it)

const float WIND_TAU = 6.2831853;
// The fixed travel directions of the two wave trains (Wind.direction normalised; and +0.20 rad).
const vec2 WIND_WAVE_DIR = vec2(0.9403762, 0.3401361);
const vec2 WIND_WAVE_DIR_B = vec2(0.8540567, 0.5201799);

// sin of a phase given in CYCLES, range reduced first (fract), so it stays exact however large the clock grows and on
// GPUs whose sin() loses precision for big arguments.
float wind_cyc(float cycles) {
	return sin(WIND_TAU * fract(cycles));
}

// The gust waves: long wiggly fronts rolling along the wind, like waves on water (0 trough .. 1 crest). A sine along the
// wind whose phase is bent by a slow warp (so the fronts meander and never run straight), a second, shorter train from a
// slightly different side (crests grow and shrink where they cross), and a slowly drifting envelope (patches of stronger
// and weaker gusts; never below WIND_ENV_MIN: the waves never stop). `scale` multiplies the wavelength and `speed_k` the
// speed (the wheat uses bigger, slower waves). Continuous in space and time: nothing pops, nothing folds (the warp's
// slope along the wind stays below 0.55 of the carrier's).
const float WIND_W1 = 0.82;       // weight of the main fronts ...
const float WIND_W2 = 0.18;       // ... and of the crossing train
const float WIND_LO = -0.10;      // the sum is stretched by smoothstep(LO, HI): crests and troughs stay distinct and
const float WIND_HI = 1.00;       // neither flattens into a plateau (a wave that rests for a second reads as a lull)
const float WIND_ENV_MIN = 0.45;  // the weakest gusts still lean the grass by this much of the strongest (in any 4 s the
                                  // waves swing by >= 0.20 at the 5th percentile; the shipped wind: 0.01)
const float WIND_WARP = 0.22;     // how far the fronts meander (cycles)

float wind_gust_k(vec2 p, float scale, float speed_k) {
	float along = dot(p, WIND_WAVE_DIR);
	float across = dot(p, vec2(-WIND_WAVE_DIR.y, WIND_WAVE_DIR.x));
	float L = max(g_wind_gust.y * scale, 1.0);
	float s = g_time * g_wind_gust.z * speed_k;          // metres the fronts have travelled
	float ac = across / L;                                 // in wavelengths
	float sl = (along - s * 0.6) / L;                      // along the wind in a frame drifting at 0.6 of the crests' speed
	float warp = WIND_WARP * (wind_cyc(0.29 * ac + 0.11 * sl + 0.10)
			+ 0.72 * wind_cyc(-0.47 * ac + 0.21 * sl + 0.62)
			+ 0.40 * wind_cyc(0.71 * ac - 0.17 * sl + 0.27));
	float w1 = 0.5 + 0.5 * wind_cyc((along - s) / L + warp);
	float L2 = L * 0.8;
	float w2 = 0.5 + 0.5 * wind_cyc(dot(p, WIND_WAVE_DIR_B) / L2 - s * 0.9 / L2 + 0.2);
	float k = smoothstep(WIND_LO, WIND_HI, WIND_W1 * w1 + WIND_W2 * w2);
	float pat = 0.5 + 0.24 * wind_cyc(0.41 * ac + 0.13 * sl + 0.13)
			+ 0.17 * wind_cyc(-0.29 * ac + 0.19 * sl + 0.58)
			+ 0.13 * wind_cyc(0.67 * ac - 0.11 * sl + 0.91);
	return k * mix(WIND_ENV_MIN, 1.0, smoothstep(0.1, 0.9, pat));
}

float wind_gust(vec2 p) {
	return wind_gust_k(p, 1.0, 1.0);
}

// The small, slow variation from clump to clump (-0.5 .. 0.5; neighbours differ a little, nothing flickers): two
// travelling sines of 6 m, at 0.17 and 0.11 Hz. It replaces the fast noise that used to turn every clump at ~2 Hz.
float wind_ripple(vec2 p) {
	float a = wind_cyc(p.x * 0.151 + p.y * 0.067 - g_time * 0.17);
	float b = wind_cyc(p.x * -0.083 + p.y * 0.143 - g_time * 0.11 + 0.37);
	return 0.3 * a + 0.2 * b;
}

// Horizontal sway at the top of a plant rooted at p: a lean along the wind that grows in the gusts plus a gentle
// continuous rocking (spatially smooth phase, so neighbours move together). Multiply by height and flexibility.
// (the arguments of the sines are in cycles: 1.25, 2.05 and 0.7 rad/s; range reduced like the waves)
vec2 wind_sway(vec2 p, float gust) {
	float t = g_time;
	float ph = dot(p, vec2(0.23, 0.17)) * 0.15915494;
	float idle = wind_cyc(t * 0.19894368 + ph) * 0.6 + wind_cyc(t * 0.32626763 + ph * 1.9 + 0.20690143) * 0.4;
	float lean = 0.22 + 0.62 * gust * g_wind_gust.x + 0.12 * idle;
	vec2 side = vec2(-g_wind_dir.y, g_wind_dir.x) * (0.1 * idle + 0.08 * wind_cyc(t * 0.11140846 + ph * 0.5));
	return (g_wind_dir * lean + side) * g_wind;
}

// Small tip sway ACROSS the wind (a gentle, slow side-to-side of the blade tips, in step along the field: neighbouring
// blades sway together; `phase` only offsets them by a few percent of a cycle). It used to be a per-blade flutter at 1.0
// and 1.45 Hz, which is what read as trembling. The caller multiplies by the height fraction squared, H and 0.12: at
// most ~3.6% of H.
vec2 wind_flutter(vec2 p, float phase, float gust) {
	float sw = wind_cyc(p.x * 0.11 + p.y * 0.07 - g_time * 0.33 + phase * 0.12);
	vec2 side = vec2(-g_wind_dir.y, g_wind_dir.x);
	return side * sw * 0.25 * g_wind_gust.w * (0.5 + 0.5 * gust) * g_wind;
}

// One pusher: the segment head -> tail (the tail lags behind the head), a soft disc round it.
// Returns xz = unit push direction * strength, z component unused (w = strength).
vec3 wind_push_one(vec3 root, vec4 head, vec4 tail) {
	if (head.w <= 0.0) {
		return vec3(0.0);
	}
	vec2 ab = tail.xz - head.xz;
	// (the +0.04 keeps `s` continuous as the tail catches up with the head: with the old max(l2, 1e-4) a hero standing
	// still, whose tail was still a fraction of a millimetre behind for ~6 s, had a hard seam through him: s jumped from
	// 0 to 1 within centimetres, so on a ring round him the push was 85% weaker behind than in front)
	float l2 = dot(ab, ab) + 0.04;
	float s = clamp(dot(root.xz - head.xz, ab) / l2, 0.0, 1.0);
	vec2 c = head.xz + ab * s;
	vec2 dv = root.xz - c;
	float d = length(dv);
	float r = head.w * mix(1.0, 0.75, s);
	float k = 1.0 - smoothstep(r * 0.3, r, d);
	k *= mix(1.0, tail.w, s);
	k *= 1.0 - smoothstep(1.0, 2.2, abs(root.y - mix(head.y, tail.y, s)));
	// Right on the segment: push sideways (away from the line of travel).
	vec2 dir = d > 0.02 ? dv / d : normalize(vec2(-ab.y, ab.x) + vec2(1e-4, 0.0));
	return vec3(dir * k, k);
}

// Sum of the four pushers at a root: xy = push direction * strength (xz), z = flattening (max strength).
vec3 wind_push(vec3 root) {
	vec3 a = wind_push_one(root, g_push_a[0], g_push_b[0]);
	vec3 b = wind_push_one(root, g_push_a[1], g_push_b[1]);
	vec3 c = wind_push_one(root, g_push_a[2], g_push_b[2]);
	vec3 d = wind_push_one(root, g_push_a[3], g_push_b[3]);
	vec2 v = a.xy + b.xy + c.xy + d.xy;
	float k = max(max(a.z, b.z), max(c.z, d.z));
	float l = length(v);
	if (l > 1.0) {
		v /= l;
	}
	return vec3(v, k);
}

// Bends a point of a plant: `rest` is the point relative to the root (world axes, metres), `h` its height fraction
// (0 root .. 1 tip), `H` the plant height, `flex` how much it gives. `push` comes from wind_push(root).
// The offset keeps the stem length roughly constant (the tip drops as it leans).
vec3 wind_bend(vec3 rest, float h, float H, vec2 sway, vec3 push, float flex) {
	vec2 lean = sway * flex + push.xy * 1.15;
	float l = length(lean);
	if (l > 1.25) {
		lean *= 1.25 / l;
		l = 1.25;
	}
	float hh = h * h;
	vec3 o = vec3(lean.x, 0.0, lean.y) * hh * H;
	o.y -= (1.0 - sqrt(max(1.0 - min(l * l * 0.55, 0.95), 0.0))) * h * H;
	// Under the feet: blades lie down.
	o.y -= push.z * push.z * 0.35 * h * H;
	return rest + o;
}

// Foliage of trees and shrubs (lowpoly.gdshader, sway > 0): `wp` the model origin, `v` the vertex (world offset
// from the origin), `h` its height above the origin. Returns the world-space offset.
// (the leaves' shimmer: 0.49 Hz with a phase per vertex, a few centimetres on a tree)
vec3 wind_foliage(vec3 wp, vec3 v, float h, float amount) {
	float g = wind_gust(wp.xz);
	vec2 s = wind_sway(wp.xz, g) * (0.55 + 0.6 * g);
	float leaf = wind_cyc(g_time * 0.49338032 + dot(v, vec3(2.1, 1.7, 2.6)) * 0.15915494) * 0.18 * (0.4 + g);
	vec2 o = (s + vec2(-g_wind_dir.y, g_wind_dir.x) * leaf) * h * amount;
	return vec3(o.x, -length(o) * 0.15, o.y);
}
