// PHAROS shared lighting.
//
// Everything opaque in the game is lit by this code instead of Godot's built-in lighting, for two reasons:
// 1. Look: hemisphere ambient (cool sky from above, warm bounce from below), wrapped sun, distance haze.
// 2. The Compatibility renderer (the only one on the web) draws a light that casts shadows in a second
//    additive pass and adds it to the first one *in sRGB space*, which burns lit surfaces (sRGB(a)+sRGB(b) is
//    much brighter than sRGB(a+b)). The base pass therefore writes the ambient+fog colour through EMISSION, and
//    the sun pass outputs exactly the increment that, once Godot converts it to sRGB and adds it, lands on the
//    correctly lit colour. g_sun_comp = 1 when the sun casts shadows (separate pass), 0 when it does not.

global uniform vec3 g_amb_sky;
global uniform vec3 g_amb_ground;
global uniform vec3 g_fog_color;
global uniform float g_fog_near;
global uniform float g_fog_far;
global uniform float g_sun_comp;
global uniform float g_night;
global uniform float g_time;
global uniform vec3 g_window;
global uniform float g_wind;

// sRGB vertex colours -> linear albedo.
vec3 ph_srgb_to_linear(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

// Godot's GLES3 linear_to_srgb approximation (tonemap_inc.glsl) and its exact inverse.
vec3 ph_l2s(vec3 c) {
	return max(vec3(1.055) * pow(max(c, vec3(0.0)), vec3(0.416666667)) - vec3(0.055), vec3(0.0));
}
vec3 ph_s2l(vec3 s) {
	return pow((max(s, vec3(0.0)) + vec3(0.055)) / 1.055, vec3(2.4));
}

// The Compatibility renderer treats ALBEDO and EMISSION written by fragment() as sRGB and converts them to
// linear right after (scene.glsl: albedo = srgb_to_linear(albedo)). ph_out() pre-encodes a linear colour so
// that Godot ends up with it; ph_godot_in() reproduces Godot's conversion exactly.
vec3 ph_out(vec3 lin) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return ph_l2s(lin);
#else
	return lin;
#endif
}
vec3 ph_godot_in(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878);
#else
	return c;
#endif
}

float ph_fog(vec3 view_vertex) {
	float f = smoothstep(g_fog_near, g_fog_far, length(view_vertex));
	return f * f * (3.0 - 2.0 * f) * 0.92;
}

vec3 ph_ambient(vec3 world_normal) {
	float h = clamp(world_normal.y * 0.5 + 0.5, 0.0, 1.0);
	return mix(g_amb_ground, g_amb_sky, h * h * (3.0 - 2.0 * h));
}

// Light contribution for light(). `lit` is the linear colour this light adds before fog.
// Returns what to add to SPECULAR_LIGHT (DIFFUSE_LIGHT is left alone).
vec3 ph_light_out(vec3 lit, bool directional, vec3 base, float fogf) {
	float keep = 1.0 - fogf;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	if (directional && g_sun_comp > 0.5) {
		vec3 total = base + lit * keep;
		// Godot fog is disabled, so the pass output is only converted to sRGB and added.
		return ph_s2l(ph_l2s(total) - ph_l2s(base));
	}
#endif
	return lit * keep;
}

// Hash / value noise helpers.
float ph_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float ph_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(ph_hash(i), ph_hash(i + vec2(1.0, 0.0)), u.x), mix(ph_hash(i + vec2(0.0, 1.0)), ph_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// ---------------------------------------------------------------------------------------------------------
// TOON style test (anime cel-shading / Wind Waker). Shared helpers for every lit shader.
// ---------------------------------------------------------------------------------------------------------
global uniform float g_toon;          // 1 = toon look on
global uniform vec3 g_toon_shade;     // tint multiplied into the shadow side (cool lavender by day)
global uniform float g_cloud_shadow;  // strength of the drifting cloud shadows (0..1)

// Sun terminator with two soft steps: shadow -> mid at the terminator, mid -> full light a little further in.
float ph_toon_ramp(float ndl) {
	float a = smoothstep(-0.03, 0.06, ndl);
	float b = smoothstep(0.10, 0.20, ndl);
	return a * 0.74 + b * 0.26;
}

// Cast shadows with a crisp, slightly soft edge.
float ph_toon_shadow(float att) {
	return smoothstep(0.32, 0.6, att);
}

// Point lights: posterised pools of light (bright core, mid ring, faint outer ring).
float ph_toon_pool(float att) {
	return smoothstep(0.08, 0.15, att) * 0.2 + smoothstep(0.3, 0.4, att) * 0.3 + smoothstep(0.75, 0.95, att) * 0.5;
}

// Anime palette: cleaner, more saturated albedo (works on linear colours, saturation done in gamma space).
vec3 ph_toon_albedo_day(vec3 lin) {
	vec3 s = sqrt(max(lin, vec3(0.0)));
	float l = dot(s, vec3(0.299, 0.587, 0.114));
	float sat = 1.38;
	s = max(mix(vec3(l), s, sat), vec3(0.0));
	// greens a touch fresher (towards yellow-green)
	s.g *= 1.0 + 0.05 * smoothstep(0.02, 0.12, s.g - max(s.r, s.b));
	return s * s;
}

// Anime night: colours sink towards indigo / teal under the moon (lamps and torches still reveal the day colours,
// see ph_light_albedo, and emission stays warm).
vec3 ph_toon_night(vec3 lin) {
	vec3 s = sqrt(max(lin, vec3(0.0)));
	float nl = dot(s, vec3(0.299, 0.587, 0.114));
	s = mix(s, nl * vec3(0.54, 0.7, 1.16) + vec3(0.0, 0.01, 0.07), 0.58 * g_night);
	return s * s;
}

vec3 ph_toon_albedo(vec3 lin) {
	return ph_toon_night(ph_toon_albedo_day(lin));
}

// Toon ambient: flat sky light on everything that faces up or sideways, warm bounce only from below.
vec3 ph_toon_ambient(vec3 world_normal) {
	float h = smoothstep(-0.55, 0.05, world_normal.y);
	return mix(g_amb_ground, g_amb_sky, h) * g_toon_shade;
}

// Big cloud shadows drifting over the island with the meltemi: a few explicit cloud shapes (ellipses with a
// ragged, slowly boiling edge) so their size and spacing stay art-directed.
float ph_cloud_one(vec2 p, vec2 c, vec2 r, float rot) {
	vec2 q = p - c;
	q = vec2(q.x * cos(rot) - q.y * sin(rot), q.x * sin(rot) + q.y * cos(rot));
	return length(q / r);
}
float ph_cloud_shade(vec3 wpos) {
	vec2 drift = vec2(0.35, 0.12) * g_time;
	vec2 p = wpos.xz - drift;
	float wob = ph_noise(wpos.xz * 0.11 + vec2(g_time * 0.05, 0.0)) * 0.34 + ph_noise(wpos.xz * 0.29 + 4.0) * 0.14;
	float d = ph_cloud_one(p, vec2(-14.5, 19.4), vec2(12.5, 8.5), 0.5);
	d = min(d, ph_cloud_one(p, vec2(-24.0, 8.0), vec2(7.0, 6.0), -0.3));
	d = min(d, ph_cloud_one(p, vec2(28.0, -22.0), vec2(16.0, 9.0), 0.2));
	d = min(d, ph_cloud_one(p, vec2(-30.0, -36.0), vec2(14.0, 10.0), -0.6));
	d = min(d, ph_cloud_one(p, vec2(40.0, 30.0), vec2(12.0, 8.0), 0.9));
	float inside = smoothstep(1.02, 0.985, d + wob - 0.24);
	return 1.0 - inside * g_cloud_shadow * (1.0 - g_night);
}
