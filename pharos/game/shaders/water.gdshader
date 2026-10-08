// Stylised faceted sea. Depth comes from a texture baked from the island heightmap (g_water_tex, R = 0 at the
// shoreline .. 1 in deep water), so it works without a depth buffer (Compatibility / WebGL 2).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://shaders/pharos.gdshaderinc"

global uniform sampler2D g_water_tex : filter_linear, repeat_disable;
global uniform vec4 g_water_rect;
global uniform vec3 g_water_shallow;
global uniform vec3 g_water_deep;
global uniform vec3 g_foam;
global uniform vec3 g_sky_top;
global uniform vec3 g_sky_horizon;

uniform float wave_amp = 0.18;
uniform float glint = 1.0;

varying vec3 v_wpos;
varying vec3 v_base;
varying float v_fogf;
varying float v_depth;
varying float v_foam;

float depth_at(vec2 xz) {
	vec2 uv = (xz - g_water_rect.xy) / g_water_rect.zw;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return 1.0;
	}
	return texture(g_water_tex, uv).r;
}

float waves(vec2 p, float t) {
	return sin(p.x * 0.33 + t * 1.05) * 0.45
		+ sin(p.y * 0.41 - t * 0.85 + p.x * 0.12) * 0.35
		+ sin((p.x + p.y) * 0.78 + t * 1.65) * 0.14
		+ sin((p.x - p.y) * 1.30 - t * 2.10) * 0.06;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dep = depth_at(wp.xz);
	float amp = wave_amp * mix(0.35, 1.0, smoothstep(0.0, 0.4, dep));
	VERTEX.y += waves(wp.xz, g_time) * amp;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_depth = dep;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VERTEX) > 0.0) {
		n = -n;
	}
	NORMAL = n;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float dep = depth_at(v_wpos.xz);
	float t = g_time;

	vec3 col = mix(g_water_shallow, g_water_deep, smoothstep(0.04, 0.85, dep));
	// The sandy bottom shows through in the shallows.
	vec3 sandy = g_water_shallow * vec3(1.18, 1.12, 0.92) + vec3(0.05, 0.045, 0.02) * (1.0 - g_night);
	col = mix(col, sandy, smoothstep(0.16, 0.0, dep) * 0.75);

	// Facet shading: faces tilted toward the sky are a touch lighter.
	col *= 0.88 + 0.18 * clamp(wn.y, 0.0, 1.0);

	// Sky reflection at grazing angles.
	vec3 V = normalize(-VERTEX);
	float fres = pow(1.0 - clamp(dot(n, V), 0.0, 1.0), 5.0);
	col = mix(col, g_sky_horizon, fres * 0.45);

	// Foam: a solid line on the shore plus bands that roll in.
	float nz = ph_noise(v_wpos.xz * 0.55 + vec2(t * 0.11, -t * 0.07));
	float nz2 = ph_noise(v_wpos.xz * 1.7 - vec2(t * 0.2, 0.0));
	float zone = smoothstep(0.20, 0.035, dep);
	float band = sin(dep * 52.0 + t * 1.35 + nz * 4.0);
	float foam = smoothstep(0.80, 0.86, band) * zone * smoothstep(0.30, 0.55, nz2 + zone * 0.35);
	foam = max(foam, smoothstep(0.045, 0.02, dep + (nz2 - 0.5) * 0.02));
	// Sparse whitecaps in open water.
	float caps = smoothstep(0.86, 0.95, ph_noise(v_wpos.xz * 0.18 + vec2(t * 0.05, t * 0.03))) * smoothstep(0.5, 0.9, dep);
	foam = max(foam, caps * smoothstep(0.6, 0.75, nz2) * 0.5);
	col = mix(col, g_foam, clamp(foam, 0.0, 1.0));

	float f = ph_fog(VERTEX);
	ALBEDO = ph_out(col);
	EMISSION = ph_out(mix(col * 0.82, g_fog_color, f));
	v_base = ph_godot_in(EMISSION);
	v_fogf = f;
	v_foam = clamp(foam, 0.0, 1.0);
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	vec3 lit = ALBEDO * LIGHT_COLOR / PI * ndl * 0.22 * ATTENUATION;
	vec3 H = normalize(LIGHT + VIEW);
	float spec = pow(max(dot(NORMAL, H), 0.0), 220.0) * 2.2 + pow(max(dot(NORMAL, H), 0.0), 30.0) * 0.05;
	lit += LIGHT_COLOR / PI * spec * glint * ATTENUATION * (1.0 - v_foam);
	SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);
}
