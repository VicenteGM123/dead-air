// Island ground. Same lighting as lowpoly.gdshader (hemisphere ambient, wrapped sun, haze, and the Compatibility
// sRGB pass compensation of pharos.gdshaderinc), plus:
//   - soft relief: the vertex NORMAL is the smoothed ground normal and UV carries the facet normal (x, z); the
//     two are blended (facet_mix), so slopes, mounds and terrace steps read as gentle light and shade while the
//     ground keeps a hint of the low-poly facets of everything else;
//   - a ground map (ground_tex over ground_rect): R = contact AO under trees, rocks and walls, G = bare soil /
//     wear (olive basins, vine rows, lane verges, cleared build plots), with a broken, painterly edge, B = sown
//     wheat and barley beds (golden stubble);
//   - painted meadow patches from a baked noise (detail_tex, same rect, mipmapped so it calms down with
//     distance) and a fine grain near the camera, both scaled by the vertex alpha (grassiness: 0 on sand,
//     rock, plaza, paths and risers).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform float wrap = 0.35;
uniform sampler2D ground_tex : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 ground_rect = vec4(-72.0, -72.0, 144.0, 144.0);
uniform float facet_mix = 0.0;
uniform float detail_far = 46.0;
uniform float patch_strength = 1.0;

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
	vec3 fn = vec3(UV.x, sqrt(max(1.0 - dot(UV, UV), 0.0)), UV.y);
	NORMAL = normalize(mix(NORMAL, fn, facet_mix));
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
	// Fine grain (two value-noise octaves, about 0.3 m and 0.12 m), only near the camera.
	float grain = 0.5;
	if (near_k > 0.001) {
		grain = 0.62 * ph_noise(v_wpos.xz * 3.1) + 0.38 * ph_noise(v_wpos.xz * 8.3 + vec2(17.0, 5.0));
	}
	// Bare soil with a ragged edge instead of a soft blur.
	const vec3 SOIL_LIN = vec3(0.4026, 0.2318, 0.1191); // #A98361
	float soil = clamp(gm.g * 1.25 + (grain - 0.5) * 0.55 * near_k - 0.08, 0.0, 1.0);
	soil = smoothstep(0.08, 0.62, soil) * min(gm.g * 3.0, 1.0);
	vec3 albedo = mix(v_albedo, SOIL_LIN * (0.92 + 0.16 * grain), soil * 0.9);
	// Sown beds: golden stubble between the stalks (and a gold strip from afar).
	const vec3 STUBBLE_LIN = vec3(0.619, 0.465, 0.122); // #CDB462
	albedo = mix(albedo, STUBBLE_LIN * (0.9 + 0.2 * grain), smoothstep(0.1, 0.7, gm.b) * 0.85);
	// Painted meadow patches: a darker, bluer green (clover, damp) and a lighter, yellower green (sunlit, dry).
	// The texture is stretched north-south, along the meltemi.
	float dv = texture(detail_tex, vec2(guv.x * 1.6, guv.y * 1.05)).r;
	// TOON: crisp painted patches (graphic shapes instead of soft blotches)
	float dark = smoothstep(0.405, 0.39, dv);
	float light = smoothstep(0.635, 0.65, dv);
	float g = v_grass * (1.0 - soil) * patch_strength;
	vec3 tint = vec3(1.0) - dark * vec3(0.26, 0.13, 0.1) + light * vec3(0.13, 0.1, -0.07);
	albedo *= mix(vec3(1.0), tint, g);
	// Broad patches (10-15 m) that still read from the title camera: greener swales, sunnier yellow slopes.
	float bv = (texture(detail_tex, guv * 0.27 + vec2(0.31, 0.57)).r - 0.5) * 2.0;
	float bq = smoothstep(-0.32, -0.28, bv) - 1.0 + smoothstep(0.3, 0.34, bv); // posterised -1 / 0 / 1
	vec3 broad = bq < 0.0 ? mix(vec3(1.0), vec3(0.88, 0.96, 0.9), -bq) : mix(vec3(1.0), vec3(1.07, 1.05, 0.9), bq);
	albedo *= mix(vec3(1.0), broad, v_grass * 0.85 * patch_strength);
	albedo *= 1.0 + (grain - 0.5) * 0.16 * near_k * (0.35 + 0.65 * v_grass);
	albedo *= mix(1.0, 0.62, gm.r);
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
