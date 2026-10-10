// Island ground (DOCE, Nemea). Same lighting as lowpoly.gdshader (toon ramp, hemisphere ambient, haze, cloud
// shadows and the Compatibility sRGB pass compensation of pharos.gdshaderinc). Vertex colour = ground colour,
// vertex alpha = grassiness (0 on sand, rock, paths and the cave). The ground map (ground_tex over ground_rect):
//   R  contact AO under trees, rocks and walls; the darkness inside the cave
//   G  bare soil / wear (verges, pens, around houses), with a ragged painted edge
//   B  packed-earth paths: crisp edge, a darker rim line, pebbles near the camera
//   A  (grass exclusion, read by the grass shader only)
// Plus painted meadow patches (detail_tex), a fine grain near the camera, and layered rock strata on steep
// ground (Wind Waker cliffs): wobbly horizontal bands with a dark line under each lip.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform sampler2D ground_tex : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 ground_rect = vec4(-192.0, -192.0, 384.0, 384.0);
uniform float detail_far = 46.0;
uniform float patch_strength = 1.0;
uniform vec3 path_col : source_color = vec3(0.79, 0.75, 0.67);
uniform vec3 path_rim : source_color = vec3(0.6, 0.52, 0.42);
uniform vec3 strata_col : source_color = vec3(0.45, 0.37, 0.36);

varying vec3 v_albedo;
varying float v_grass;
varying vec3 v_wpos;
varying vec3 v_base;
varying float v_fogf;
varying float v_cloud;
varying vec3 v_day;

void vertex() {
	v_albedo = ph_toon_albedo_day(ph_srgb_to_linear(COLOR.rgb));
	v_grass = COLOR.a;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 guv = (v_wpos.xz - ground_rect.xy) / ground_rect.zw;
	vec4 gm = texture(ground_tex, guv);
	if (guv.x < 0.0 || guv.y < 0.0 || guv.x > 1.0 || guv.y > 1.0) {
		gm = vec4(0.0);
	}
	float dist = length(VERTEX);
	float near_k = 1.0 - smoothstep(detail_far * 0.45, detail_far, dist);
	float grain = 0.5;
	if (near_k > 0.001) {
		grain = 0.62 * ph_noise(v_wpos.xz * 3.1) + 0.38 * ph_noise(v_wpos.xz * 8.3 + vec2(17.0, 5.0));
	}
	vec3 albedo = v_albedo;
	// Painted meadow patches: a darker, bluer green and a lighter, yellower green, crisp graphic shapes.
	float dv = texture(detail_tex, v_wpos.xz * vec2(0.0042, 0.0028)).r;
	float dark = smoothstep(0.405, 0.39, dv);
	float light = smoothstep(0.635, 0.65, dv);
	float g = v_grass * patch_strength;
	vec3 tint = vec3(1.0) - dark * vec3(0.24, 0.12, 0.1) + light * vec3(0.12, 0.09, -0.07);
	albedo *= mix(vec3(1.0), tint, g);
	// Broad patches (10-20 m) that still read from afar.
	float bv = (texture(detail_tex, v_wpos.xz * 0.0011 + vec2(0.31, 0.57)).r - 0.5) * 2.0;
	float bq = smoothstep(-0.32, -0.28, bv) - 1.0 + smoothstep(0.3, 0.34, bv);
	vec3 broad = bq < 0.0 ? mix(vec3(1.0), vec3(0.88, 0.96, 0.9), -bq) : mix(vec3(1.0), vec3(1.07, 1.05, 0.9), bq);
	albedo *= mix(vec3(1.0), broad, g * 0.85);
	albedo *= 1.0 + (grain - 0.5) * 0.16 * near_k * (0.35 + 0.65 * v_grass);
	// Bare soil with a ragged edge.
	const vec3 SOIL_LIN = vec3(0.4026, 0.2318, 0.1191);
	float soil = clamp(gm.g * 1.25 + (grain - 0.5) * 0.55 * near_k - 0.08, 0.0, 1.0);
	soil = smoothstep(0.08, 0.62, soil) * min(gm.g * 3.0, 1.0);
	albedo = mix(albedo, SOIL_LIN * (0.92 + 0.16 * grain), soil * 0.85);
	// Paths: packed earth with a crisp, slightly wobbly edge and a darker rim (the toon outline of the road).
	float pn = ph_noise(v_wpos.xz * 0.9) - 0.5;
	float pb = gm.b + pn * 0.12 + (grain - 0.5) * 0.1 * near_k;
	float on_path = smoothstep(0.40, 0.46, pb);
	float rim = smoothstep(0.26, 0.34, pb) * (1.0 - on_path);
	vec3 pc = ph_srgb_to_linear(path_col);
	pc *= 0.94 + 0.12 * ph_noise(v_wpos.xz * 0.35);
	// pebbles near the camera
	float peb = smoothstep(0.78, 0.82, ph_noise(v_wpos.xz * 6.5 + 3.0)) * near_k;
	pc = mix(pc, pc * vec3(1.18, 1.14, 1.08), peb);
	albedo = mix(albedo, ph_srgb_to_linear(path_rim), rim * 0.75);
	albedo = mix(albedo, pc, on_path);
	// Layered rock on steep ground: horizontal strata that wobble, a dark line under each lip, lit tops.
	float steep = smoothstep(0.78, 0.68, wn.y) * (1.0 - v_grass);
	if (steep > 0.01) {
		float wob = ph_noise(v_wpos.xz * 0.13) * 1.6 + ph_noise(v_wpos.xz * 0.5 + 7.0) * 0.35;
		float band = fract(v_wpos.y * 0.42 + wob);
		float far_k = 1.0 - smoothstep(60.0, 150.0, dist);
		float line = (smoothstep(0.06, 0.0, band) + smoothstep(0.93, 1.0, band) * 0.6) * far_k;
		float lip = smoothstep(0.12, 0.2, band) * smoothstep(0.32, 0.22, band) * far_k;
		float tone = ph_noise(vec2(v_wpos.y * 0.42 + wob, 3.7) * 2.0);
		vec3 rock = albedo * mix(0.9, 1.08, tone) * (1.0 + lip * 0.1);
		rock = mix(rock, ph_srgb_to_linear(strata_col), line * 0.7);
		albedo = mix(albedo, rock, steep);
	}
	// Contact AO and the cave's darkness.
	albedo *= mix(1.0, 0.42, gm.r);
	v_day = albedo;
	albedo = ph_toon_night(albedo);
	vec3 base = albedo * ph_toon_ambient(wn);
	float f = ph_fog(VERTEX);
	ALBEDO = ph_out(albedo);
	EMISSION = ph_out(mix(base, g_fog_color, f));
	v_base = ph_godot_in(EMISSION);
	v_fogf = f;
	v_cloud = ph_cloud_shade(v_wpos);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	vec3 lit;
	if (LIGHT_IS_DIRECTIONAL) {
		float k = ph_toon_ramp(ndl) * ph_toon_shadow(ATTENUATION) * v_cloud;
		lit = ALBEDO * LIGHT_COLOR / PI * k;
	} else {
		lit = v_day * LIGHT_COLOR / PI * smoothstep(-0.2, 0.15, ndl) * ph_toon_pool(ATTENUATION);
	}
	SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);
}
