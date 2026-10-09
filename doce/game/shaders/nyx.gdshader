// The children of Nyx are made of night sky: deep indigo bodies with stars twinkling inside them (seen as
// through a window onto the sky), a soft violet rim, and a smoky hem that frays into nothing.
// Vertex colour alpha: 1 body, 0.5 self-lit (eyes, ornaments).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform vec3 rim_color : source_color = vec3(0.62, 0.48, 1.0);
uniform float star_density = 330.0;
uniform float hem = 0.35; // model-space height under which the body frays into smoke
uniform float glow_strength = 2.6;
uniform float flash = 0.0;
uniform float dissolve = 0.0;
uniform vec3 eye_tint = vec3(1.0);

varying vec3 v_albedo;
varying float v_kind;
varying vec3 v_base;
varying float v_fogf;
varying vec3 v_wpos;
varying float v_my;

float star_field(vec3 dir, float density, float t) {
	vec3 p = dir * density;
	vec3 cell = floor(p);
	float r = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	vec3 f = fract(p) - 0.5;
	vec3 off = vec3(fract(r * 13.7), fract(r * 71.3), fract(r * 29.1)) - 0.5;
	float d = length(f - off * 0.5);
	float star = step(0.925, r) * smoothstep(0.3, 0.03, d);
	float tw = 0.55 + 0.45 * sin(t * (1.5 + r * 3.0) + r * 40.0);
	return star * tw * (0.6 + 0.8 * fract(r * 7.7));
}

void vertex() {
	v_albedo = ph_srgb_to_linear(COLOR.rgb);
	v_kind = COLOR.a;
	v_my = VERTEX.y;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = ph_noise(v_wpos.xz * 3.1 + v_wpos.y * 2.3 + vec2(g_time * 0.6, -g_time * 0.4)) * 0.7 + ph_noise(v_wpos.xy * 7.0 - g_time * 0.8) * 0.3;
	// Smoky hem: fray the lowest part of the body into wisps that drift down.
	float fray = hem > 0.0 ? smoothstep(hem, 0.0, v_my) : 0.0;
	if (fray > 0.0) {
		float wisp = ph_noise(vec2(atan(v_wpos.x - MODEL_MATRIX[3].x, v_wpos.z - MODEL_MATRIX[3].z) * 2.2, v_my * 7.0 + g_time * 1.6));
		n = mix(n, wisp, 0.65);
	}
	if (n < fray * 0.85 + dissolve) {
		discard;
	}
	vec3 albedo = v_albedo;
	vec3 base;
	if (v_kind > 0.25 && v_kind < 0.75) {
		base = albedo * glow_strength * eye_tint;
	} else {
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 V = normalize(-VERTEX);
		float fr = 1.0 - clamp(dot(NORMAL, V), 0.0, 1.0);
		// TOON: a crisp cel rim band plus a little of the soft falloff
		float rim = smoothstep(0.6, 0.68, fr) * 0.9 + pow(fr, 3.5) * 0.3;
		// Window onto the night sky.
		vec3 dir = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
		float st = star_field(dir, star_density, g_time) + star_field(dir.zxy, star_density * 0.55, g_time * 0.7) * 0.6;
		base = albedo * (0.5 + 0.5 * ph_ambient(wn));
		base += ph_srgb_to_linear(rim_color) * rim * (0.3 + 0.4 * g_night);
		base += vec3(0.85, 0.9, 1.0) * st * (1.1 + 0.9 * g_night);
		// Faint inner nebula tint.
		base += ph_srgb_to_linear(rim_color) * 0.06 * ph_noise(dir.xy * 9.0 + g_time * 0.05);
	}
	// Edges about to dissolve glow.
	if (fray + dissolve > 0.001) {
		base += ph_srgb_to_linear(rim_color) * smoothstep(fray * 0.85 + dissolve + 0.12, fray * 0.85 + dissolve, n) * 1.6;
	}
	base = mix(base, vec3(1.0, 0.98, 0.94), flash * 0.8);
	float f = ph_fog(VERTEX);
	ALBEDO = ph_out(albedo * 0.35 * (1.0 - flash));
	EMISSION = ph_out(mix(base, g_fog_color, f));
	v_base = ph_godot_in(EMISSION);
	v_fogf = f;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float d = max((ndl + 0.3) / 1.3, 0.0);
	vec3 lit = ALBEDO * LIGHT_COLOR / PI * d * ATTENUATION;
	SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);
}
