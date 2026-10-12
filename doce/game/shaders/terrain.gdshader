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
// GRASSLAB: the anime meadow (Trung Duy Nguyen's method): the ground under the grass clumps shares their mound normal,
// colours and cel value (meadow_lib.gdshaderinc), so grass and ground merge; the wheat field's ground likewise.
#include "res://shaders/wind.gdshaderinc"
#include "res://shaders/meadow_lib.gdshaderinc"
// GRASSLAB: the wheat field (WheatField sets field_tex / field_rect): the ground under the wheat is its shaded depth.
#include "res://shaders/wheat_lib.gdshaderinc"

uniform sampler2D ground_tex : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 ground_rect = vec4(-192.0, -192.0, 384.0, 384.0);
uniform float detail_far = 46.0;
uniform float patch_strength = 1.0;
uniform vec3 path_col : source_color = vec3(0.79, 0.75, 0.67);
uniform vec3 path_rim : source_color = vec3(0.6, 0.52, 0.42);
uniform vec3 strata_col : source_color = vec3(0.45, 0.37, 0.36);
// GRASSLAB: 1 = the anime meadow (AnimeMeadow sets it): grassy ground = the grass mass, lit with the mound normal.
uniform float trung = 0.0;
uniform sampler2D meadow_tex : filter_linear, repeat_disable, hint_default_black;
uniform vec4 meadow_rect = vec4(-193.0, -193.0, 386.0, 386.0);
uniform float ground_hf = 0.12; // where in the grass canopy the ground's colour sits seen steeply (0 foot .. 1 tips)
// FIXER (client: "falta densidad de pasto"): the ground under the meadow is the DEPTH of the stand where it is seen
// steeply (between the clumps near the camera: dark roots), the upper blades where it is seen at a grazing angle (far
// away, where the clumps have thinned out), and it is painted with blade strokes (MeadowKit.ground_strokes: dark
// roots, bright tips, two scales, combed along the wind) so any gap between the clumps reads as more grass.
uniform float graze_hf = 0.6;   // ... and seen at a grazing angle
uniform sampler2D stroke_tex : filter_linear_mipmap, repeat_enable, hint_default_black;
uniform float stroke_tile = 1.15;  // metres per tile of the strokes (the second layer is 1.75x bigger)
uniform float stroke_k = 1.0;
uniform vec2 stroke_dir = vec2(0.94, 0.34); // the strokes' combing direction (the mean wind; constant: no swimming)

varying vec3 v_albedo;
varying float v_grass;
varying vec3 v_wpos;
varying vec3 v_base;
varying float v_fogf;
varying float v_cloud;
varying vec3 v_day;
varying vec3 v_ground_srgb; // GRASSLAB
varying float v_mk;         // GRASSLAB: meadow weight (cel ramp + chosen shadow colour in light())
varying float v_mh;         // GRASSLAB: mound height (the folds sink into the shadow)
varying float v_far;        // GRASSLAB: 0 near .. 1 far (the cel softens with the distance)
varying vec3 v_lift;        // GRASSLAB: albedo * ambient - shadow colour
varying vec3 v_drop;        // FIXER: on the meadow, cast shadow -> chosen shadow colour (meadow_lib.gdshaderinc mlib_lit)

void vertex() {
	v_albedo = ph_toon_albedo_day(ph_srgb_to_linear(COLOR.rgb));
	v_grass = COLOR.a;
	v_ground_srgb = COLOR.rgb;
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
	// GRASSLAB: the anime meadow. Grassy ground is the grass mass itself: the same two tones (lit AND the chosen
	// shadow colour), mound normal, wind wave tint and cel value as the clumps rooted on it (meadow_lib.gdshaderinc);
	// flower drifts tint it from afar. `shade_alb` is the albedo of the shadow side (= albedo off the meadow).
	v_mk = 0.0;
	v_mh = 0.5;
	float mk = 0.0;
	vec3 shade_alb = albedo;
	if (trung > 0.5 && v_grass > 0.0) {
		mk = smoothstep(0.0, 0.1, v_grass);
		vec4 mo = mlib_mound_frag(v_wpos.xz);
		vec3 m2 = mlib_tuft_fade(mlib_mound2_frag(v_wpos.xz), dist);
		vec4 mm = textureLod(meadow_tex, (v_wpos.xz - meadow_rect.xy) / meadow_rect.zw, 0.0);
		// short lawns have shallow mounds (the masses are the grass's own bulk)
		float mstr = smoothstep(0.12, 0.42, mm.r);
		// FIXER: seen steeply the ground is the depth of the stand between the clumps (dark roots), seen at a grazing
		// angle the upper blades of the mass (where the clumps have thinned out)
		vec3 vd = normalize(v_wpos - CAMERA_POSITION_WORLD);
		float inc = clamp(dot(-vd, wn), 0.0, 1.0);
		float ghf = mix(graze_hf, ground_hf, smoothstep(0.06, 0.42, inc));
		// ... painted with blade strokes near the camera (two scales, combed along the wind): each stroke is a blade
		// lying in the stand, its root dark, its tip bright
		float sk = stroke_k * (1.0 - smoothstep(16.0, 34.0, dist)) * smoothstep(0.04, 0.2, inc);
		if (sk > 0.001) {
			vec2 sd = normalize(stroke_dir);
			vec2 sp = vec2(dot(v_wpos.xz, sd), dot(v_wpos.xz, vec2(-sd.y, sd.x)));
			vec4 s1 = texture(stroke_tex, sp / stroke_tile);
			vec4 s2 = texture(stroke_tex, sp / (stroke_tile * 1.75) + vec2(0.43, 0.17));
			float c1 = smoothstep(0.3, 0.7, s1.a);
			float c2 = smoothstep(0.3, 0.7, s2.a) * (1.0 - c1);
			float shf = mix(0.22, 0.88, s1.r) * c1 + mix(0.16, 0.78, s2.r) * c2;
			float scov = (c1 + c2) * sk;
			ghf = mix(ghf, shf / max(c1 + c2, 1e-3), scov * 0.92);
			ghf *= mix(1.0, mix(0.9, 1.1, s1.g * c1 + s2.g * c2), scov);
		}
		float big = mlib_big(v_wpos.xz);
		vec3 ma = mlib_grass_albedo(v_ground_srgb, mo.b, ghf, big);
		vec3 ms = mlib_grass_shadow(v_ground_srgb, mo.b, ghf, big);
		float wave = wind_gust_k(v_wpos.xz, 1.0, 1.0);
		float wk = mlib_wave_tint(wave, g_wind_gust.x, ghf);
		ma *= wk;
		ms *= wk;
		// flower drifts: a tint where the flower instances have faded (they fade out 26-33 m)
		// (FIXER: a faint tint near the camera too, so the drifts read as masses under the flower heads)
		float fl = mm.b * (0.1 + 0.32 * smoothstep(20.0, 32.0, dist));
		vec3 pc = mm.a < 0.17 ? vec3(0.86, 0.4, 0.55) : (mm.a < 0.5 ? vec3(0.75, 0.06, 0.04) : (mm.a < 0.84 ? vec3(0.88, 0.86, 0.78) : vec3(0.38, 0.17, 0.66)));
		ma = mix(ma, pc * 0.6, fl);
		ms = mix(ms, pc * 0.8, fl);
		// the wheat field: the shaded depth of the stand (dark olive gold) under the canopy and at its ragged edge
		vec4 wf = wheat_field(v_wpos.xz);
		// (FIXER: only under the canopy's visible extent: the verge outside its cut stays meadow green)
		float wfk = smoothstep(0.46, 0.6, wf.r);
		vec3 wa = wheat_albedo(0.0, mo.b, wf.a, 0.55) * 0.85;
		ma = mix(ma, wa, wfk);
		ms = mix(ms, wheat_shadow(0.0, wf.a, 0.55) * 0.85 / MLIB_AMB_DAY, wfk);
		shade_alb = mix(shade_alb, ms, mk);
		albedo = mix(albedo, ma, mk);
		vec3 n_m = mlib_normal(wn, mlib_slope(mo.rg, m2, mk * mstr), 1.0);
		// the gusts tilt the mass with the bend, like the clumps rooted here (meadow_grass.gdshader)
		n_m = normalize(n_m + vec3(g_wind_dir.x, 0.0, g_wind_dir.y) * wave * g_wind_gust.x * MLIB_GUST_TILT * g_wind * mk);
		wn = n_m;
		NORMAL = normalize((VIEW_MATRIX * vec4(n_m, 0.0)).xyz);
		v_mh = mix(0.5, mo.b, mstr);
	}
	float gk = 1.0 + (grain - 0.5) * 0.16 * near_k * (0.35 + 0.65 * v_grass) * (1.0 - mk);
	albedo *= gk;
	shade_alb *= gk;
	// Bare soil with a ragged edge.
	const vec3 SOIL_LIN = vec3(0.4026, 0.2318, 0.1191);
	float soil = clamp(gm.g * 1.25 + (grain - 0.5) * 0.55 * near_k - 0.08, 0.0, 1.0);
	soil = smoothstep(0.08, 0.62, soil) * min(gm.g * 3.0, 1.0);
	albedo = mix(albedo, SOIL_LIN * (0.92 + 0.16 * grain), soil * 0.85);
	shade_alb = mix(shade_alb, SOIL_LIN * (0.92 + 0.16 * grain), soil * 0.85);
	mk *= 1.0 - soil * 0.85;
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
	albedo = mix(albedo, ph_srgb_to_linear(path_rim), rim * 0.75 * (1.0 - mk * 0.85));
	albedo = mix(albedo, pc, on_path);
	shade_alb = mix(shade_alb, ph_srgb_to_linear(path_rim), rim * 0.75 * (1.0 - mk * 0.85));
	shade_alb = mix(shade_alb, pc, on_path);
	mk *= 1.0 - on_path;
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
		shade_alb = mix(shade_alb, rock, steep);
	}
	// Contact AO and the cave's darkness.
	albedo *= mix(1.0, 0.42, gm.r);
	shade_alb *= mix(1.0, 0.42, gm.r);
	v_day = albedo;
	albedo = ph_toon_night(albedo);
	vec3 ambl = ph_toon_ambient(wn);
	vec3 base = albedo * ambl;
	// GRASSLAB: the meadow's chosen shadow colour (the sun lifts it back to the lit colour in light())
	vec3 shadow = ph_toon_night(shade_alb) * ambl;
	// FIXER: the meadow's twilight shade keeps part of the mood's hue (meadow_lib.gdshaderinc), like the clumps
	shadow = mix(shadow, mlib_mood_shadow(shadow, ambl), mk);
	v_lift = base - shadow;
	v_mk = mk;
	// FIXER: on the meadow the base pass is the darker CAST shadow colour (like the clumps rooted here)
	float ck = mix(1.0, cast_k, mk);
	v_drop = shadow * (1.0 - ck);
	base = shadow * ck;
	float f = ph_fog(VERTEX);
	ALBEDO = ph_out(albedo);
	EMISSION = ph_out(mix(base, g_fog_color, f));
	v_base = ph_godot_in(EMISSION);
	v_fogf = f;
	v_cloud = ph_cloud_shade(v_wpos);
	v_far = mlib_far(dist);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	vec3 lit;
	if (LIGHT_IS_DIRECTIONAL) {
		// GRASSLAB: on the meadow, the grass's two-band cel ramp and its shadow colour
		float sun_up = (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).y;
		float ramp = mix(ph_toon_ramp(ndl), mlib_cel_far(ndl, sun_up, v_mh, v_far), v_mk);
		lit = mlib_lit(ALBEDO * LIGHT_COLOR / PI, v_lift, v_drop, ramp, ph_toon_shadow(ATTENUATION), v_cloud);
	} else {
		lit = v_day * LIGHT_COLOR / PI * smoothstep(-0.2, 0.15, ndl) * ph_toon_pool(ATTENUATION);
	}
	SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);
}
