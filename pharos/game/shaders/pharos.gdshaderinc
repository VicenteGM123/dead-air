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
