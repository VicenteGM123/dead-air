// DOCE shared wind: one wind for the meadow grass, the flowers, the wheat and the foliage of trees and shrubs, so
// everything moves together. Include it AFTER pharos.gdshaderinc (uses g_time, g_wind and ph_noise).
//
// Global uniforms (declared in project.godot, driven every frame by scripts/world/wind.gd):
//   g_wind       float  (pharos.gdshaderinc, set by TimeOfDay's mood) overall strength, 1 = a fresh breeze
//   g_wind_dir   vec2   unit XZ direction the wind blows TOWARDS (default east-south-east, with the clouds)
//   g_wind_gust  vec4   x gust strength (how far the travelling waves bend things, 0..1.5)
//                       y gust wavelength in metres (size of the waves rolling over the meadow)
//                       z gust speed in m/s (how fast the waves travel along g_wind_dir)
//                       w tip flutter amount (0..1)
//   g_push_a     mat4   up to four pushers (hero, beasts): column i = head (x, y, z, radius m); radius 0 = unused
//   g_push_b     mat4   column i = tail (x, y, z, strength 0..1 at the tail): the head's position a moment ago,
//                       so the plants it went through spring back along a soft trail
//
// All motion is continuous in space and time (no per-blade random phases on big motions): nothing jitters.

global uniform vec2 g_wind_dir;
global uniform vec4 g_wind_gust;
global uniform mat4 g_push_a;
global uniform mat4 g_push_b;

// Travelling gust waves: long wiggly fronts across the wind that roll along it, like waves on water (0 calm .. 1 on a
// crest). The fronts are a sine along the wind whose phase is warped by a slow noise (so they bend and break), their
// strength varies along each front and over time (gusts come and go). `scale` multiplies the wavelength and `speed_k`
// the speed (the wheat uses bigger, slower waves). Continuous in space and time: nothing pops.
float wind_gust_k(vec2 p, float scale, float speed_k) {
	vec2 d = g_wind_dir;
	float along = dot(p, d);
	float across = dot(p, vec2(-d.y, d.x));
	float L = max(g_wind_gust.y * scale, 1.0);
	float s = g_time * g_wind_gust.z * speed_k;
	float warp = (ph_noise(vec2(across / (L * 1.3), (along - s * 0.6) / (L * 2.2))) - 0.5) * 2.0;
	float ph = (along - s) / L + warp;
	float front = 0.5 + 0.5 * sin(ph * 6.2831853);
	float amp = smoothstep(0.12, 0.62, ph_noise(vec2(across / (L * 2.4), (along - s) / (L * 3.2)) + vec2(7.3, 2.9)));
	return smoothstep(0.36, 0.96, front) * amp;
}

float wind_gust(vec2 p) {
	return wind_gust_k(p, 1.0, 1.0);
}

// Horizontal sway at the top of a plant rooted at p: a lean along the wind that grows in the gusts plus a gentle
// continuous rocking (spatially smooth phase, so neighbours move together). Multiply by height and flexibility.
vec2 wind_sway(vec2 p, float gust) {
	float t = g_time;
	float ph = dot(p, vec2(0.23, 0.17));
	float idle = sin(t * 1.25 + ph) * 0.6 + sin(t * 2.05 + ph * 1.9 + 1.3) * 0.4;
	float lean = 0.22 + 0.78 * gust * g_wind_gust.x + 0.12 * idle;
	vec2 side = vec2(-g_wind_dir.y, g_wind_dir.x) * (0.1 * idle + 0.08 * sin(t * 0.7 + ph * 0.5));
	return (g_wind_dir * lean + side) * g_wind;
}

// Small fast flutter of tips (per-blade phase is fine here: the amplitude is a couple of centimetres).
vec2 wind_flutter(vec2 p, float phase, float gust) {
	float t = g_time;
	float a = sin(t * 6.3 + phase * 6.283 + dot(p, vec2(1.7, 1.3)));
	float b = sin(t * 9.1 + phase * 3.1 + dot(p, vec2(-1.1, 2.3)));
	vec2 side = vec2(-g_wind_dir.y, g_wind_dir.x);
	return (side * a + g_wind_dir * b * 0.6) * g_wind_gust.w * (0.35 + 0.65 * gust) * g_wind;
}

// One pusher: the segment head -> tail (the tail lags behind the head), a soft disc round it.
// Returns xz = unit push direction * strength, z component unused (w = strength).
vec3 wind_push_one(vec3 root, vec4 head, vec4 tail) {
	if (head.w <= 0.0) {
		return vec3(0.0);
	}
	vec2 ab = tail.xz - head.xz;
	float l2 = max(dot(ab, ab), 1e-4);
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
vec3 wind_foliage(vec3 wp, vec3 v, float h, float amount) {
	float g = wind_gust(wp.xz);
	vec2 s = wind_sway(wp.xz, g) * (0.55 + 0.9 * g);
	float t = g_time;
	float leaf = sin(t * 3.1 + dot(v, vec3(2.1, 1.7, 2.6))) * 0.18 * (0.4 + g);
	vec2 o = (s + vec2(-g_wind_dir.y, g_wind_dir.x) * leaf) * h * amount;
	return vec3(o.x, -length(o) * 0.15, o.y);
}
