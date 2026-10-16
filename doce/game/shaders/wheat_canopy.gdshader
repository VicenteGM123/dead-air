// DOCE wheat field: the ear CANOPY (scripts/world/wheat_field.gd). One mesh over the field at ground height; here it
// is lifted to the top of the wheat (~1 m, lower at the field's edge), carried by the big slow wind waves (the tops
// lean along the wind and dip in the crests), pushed down and aside round the hero and the beasts (the stalks part
// at hip height and close behind along the pushers' trails), painted with ears and awns seen from above
// (MeadowPaint.wheat_top: bright ears over the dark depth of the stand between them) in two golds mixed by the mound
// pattern plus a few greener patches, lighter sheen on the wave crests and darker troughs, the wheat's mound normal
// (bigger, softer than the meadow's), a soft cel value with a CHOSEN warm shadow (amber-brown) and a backlit glow
// (golden hour). Ragged edge: cut by the field map. Alpha list + stencil 32 (no ink lines), like the grass.
shader_type spatial;
render_mode cull_disabled, depth_draw_always, specular_disabled;
stencil_mode write, compare_always, 32;

#include "res://shaders/pharos.gdshaderinc"
#include "res://shaders/wind.gdshaderinc"
#include "res://shaders/grass_common.gdshaderinc"
#include "res://shaders/meadow_lib.gdshaderinc"
#include "res://shaders/wheat_lib.gdshaderinc"

uniform sampler2D wheat_top : filter_linear_mipmap, repeat_enable, hint_default_black;
uniform float top_tile = 1.3;      // metres per tile of the painted ears
uniform float depth_k = 0.56;      // brightness of the stand's depth between the ears
uniform float near_sink = 0.72;    // the canopy's height (fraction) where the 3D ears and the ear cards stand on it (FIXER: 0.55 -> 0.66;
                                   // FIXER-2: 0.72, a smaller gap under the ears)
// FIXER-2 (client: "falta densidad"): near the camera the canopy is the FLOOR of a dense stand, under the ears: the sun
// barely reaches it between the ears (floor_occ) and only partly on the lower ears painted in it (floor_ear), so the
// gaps between the 3D ears read as the stand's shaded depth (more wheat), never as a lit tan plate.
uniform float floor_occ = 0.22;
uniform float floor_ear = 0.4;

varying vec3 v_wpos;
varying float v_wave;
varying float v_f;
varying float v_green;
varying float v_pat;
varying float v_open;
varying float v_ear;      // fragment -> light: on an ear (1) or in the depth between them (0)
varying float v_ramp;     // FIXER: 0 at the field's edge .. 1 where the canopy has its full height
varying float v_fk;       // FIXER-2: 0 near (the stand's floor) .. 1 far (the field's top)
varying float v_h;        // FIXER-2: the plate's height above the ground (m), interpolated: the cut follows it
varying vec3 v_lift;
varying vec3 v_base;
varying float v_fogf;
varying float v_cloud;

void vertex() {
	vec3 g = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 f = wheat_field(g.xz);
	// Within reach of the 3D ear clumps and the ear cards (out to ~45 m) the canopy is only the low, shaded floor of
	// the stand (the stalks' depth under the ears); beyond, where they have faded out, it rises to the field's top.
	float cd = length(g.xz - CAMERA_POSITION_WORLD.xz);
	float far_k = smoothstep(26.0, 38.0, cd);
	float H = wheat_canopy(f) * mix(near_sink, 1.0, far_k);
	vec2 wind = mlib_wind(g.xz, wave_scale, wave_speed);
	float wave = pow(wind.x, wave_sharp);
	// the bend of the stalks under this point: the wave leans them along the wind, the ripple sways them, the pushers
	// part them
	float a = (0.06 + 0.4 * wave * g_wind_gust.x + 0.025 * wind.y) * g_wind;
	vec2 bend = g_wind_dir * a;
	vec3 push = wind_push(vec3(g.x, g.y + 0.5, g.z));
	bend += push.xy * 1.15;
	float bl = length(bend);
	if (bl > 1.2) {
		bend *= 1.2 / bl;
	}
	vec3 top = mlib_rotate(vec3(0.0, H, 0.0), bend);
	// the crests dip a little more (the stalks bow), the trampled middle of a pusher lies down
	top.y -= wave * 0.06 * g_wind;
	top.y *= 1.0 - push.z * push.z * 0.75;
	v_wpos = g + top;
	v_h = top.y;
	VERTEX = v_wpos - MODEL_MATRIX[3].xyz; // the canopy mesh is in world axes (no rotation / scale)
	NORMAL = wheat_normal(g.xz, bend);
	v_wave = wave;
	v_f = f.r;
	v_green = f.a;
	v_pat = wheat_pattern(g.xz);
	v_open = push.z;
	v_ramp = wheat_canopy_ramp(f);
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// FIXER-2: the plate ends where it reaches the ground (its height ramps to 0 at the field's cut, see
	// wheat_canopy_ramp): it slopes into the terrain, never ends in a raised shelf or a vertical cut face
	if (v_h < 0.04 || v_f < 0.2) {
		discard;
	}
	// ears and awns seen from above (R along the ear, G grain / shade, B part: 0.66 ear, 1 awn, A coverage), two
	// layers at two scales: bright ears over the dark depth of the stand between them
	vec2 tp = v_wpos.xz / top_tile;
	vec4 t1 = texture(wheat_top, tp);
	vec4 t2 = texture(wheat_top, tp * 0.61 + vec2(0.37, 0.71));
	float cov = max(t1.a, t2.a * 0.85);
	float part = t1.a > 0.5 ? t1.b : (t2.a > 0.5 ? t2.b : 0.66);
	float grain = t1.a > 0.5 ? t1.g : t2.g;
	part = part > 0.83 ? 1.0 : 0.66;
	vec3 albedo = wheat_albedo(part, v_pat, v_green, 1.0);
	vec3 shade = wheat_shadow(part, v_green, 1.0);
	float ear = smoothstep(0.25, 0.75, cov);
	// FIXER-2: near the camera the floor's ears melt softly into its depth (no crisp dark holes between them)
	ear = mix(smoothstep(0.05, 0.95, cov) * 0.8 + 0.2, ear, smoothstep(26.0, 38.0, length(VERTEX)));
	// ... and the sloping foot of the stand at the field's edge is one even shade (no blotches on the bank)
	ear = mix(0.35, ear, v_ramp);
	// FIXER-2: near the camera the gaps between the painted ears are the stalks of the stand's depth (deep olive-brown,
	// its chosen shadow), not more ear colour: the floor reads as a dense stand seen from above
	float fk0 = smoothstep(26.0, 38.0, length(VERTEX));
	float gap_hf = 1.0;
	albedo = mix(mix(wheat_albedo(0.0, v_pat, v_green, gap_hf), albedo, fk0), albedo, ear);
	shade = mix(mix(wheat_shadow(0.0, v_green, gap_hf), shade, fk0), shade, ear);
	// (FIXER-2: near the camera the floor's ears and gaps are close in value: the lit 3D ears above carry the detail)
	float vk = mix(mix(0.84, depth_k, fk0), 1.0, ear) * mix(0.9, 1.08, grain * ear + (1.0 - ear) * 0.5);
	// sheen: lighter wave crests, darker troughs
	vk *= mix(1.0 - sheen * 0.45, 1.0 + sheen, v_wave);
	// the parted wheat round the hero shows the darker stalks
	vk *= 1.0 - v_open * 0.4;
	// FIXER: where the canopy ramps down to the field's edge it is the shaded foot of the stand (no lit slope)
	vk *= mix(0.42, 1.0, v_ramp * v_ramp);
	// near the camera the canopy is the stand's floor under the 3D ears and the ear cards (deep, stalky), far away
	// (where only the canopy is left) it is the field's whole golden top
	float fk = smoothstep(26.0, 38.0, length(VERTEX));
	vk *= mix(0.62, 1.0, fk);
	v_fk = fk;
	albedo *= vk;
	shade *= vk;
	albedo = ph_toon_night(albedo);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 ambl = ph_toon_ambient(wn);
	vec3 amb = albedo * ambl;
	vec3 shadow = ph_toon_night(shade) * wheat_amb_k(ambl);
	float f = ph_fog(VERTEX);
	ALBEDO = ph_out(albedo);
	EMISSION = ph_out(mix(shadow, g_fog_color, f));
#ifndef MEADOW_OPAQUE
	ALPHA = 1.0;
#endif
	v_lift = amb - shadow;
	v_base = ph_godot_in(EMISSION);
	v_fogf = f;
	v_cloud = ph_cloud_shade(v_wpos);
	v_ear = ear;
}

void light() {
	vec3 lit;
	if (LIGHT_IS_DIRECTIONAL) {
		float sun_up = (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).y;
		float sh = ph_toon_shadow(ATTENUATION) * v_cloud;
		float k = wheat_cel(dot(NORMAL, LIGHT), sun_up) * sh;
		vec3 lc = wheat_light(LIGHT_COLOR / PI);
		// backlight: the ears and awns glow against a low sun, the depth of the stand between them sinks into shade
		float back = pow(clamp(dot(LIGHT, -VIEW), 0.0, 1.0), 3.0);
		k *= mix(1.0, 0.45, back * (1.0 - v_ear));
		// FIXER-2: the floor of the stand near the camera is under the ears (see floor_occ)
		float occ = mix(mix(floor_occ, floor_ear, v_ear), 1.0, v_fk);
		k *= occ;
		lit = (ALBEDO * lc + v_lift) * k;
		lit += ALBEDO * vec3(1.15, 1.0, 0.62) * lc * back * wheat_glow * sh * (1.0 - g_night) * mix(v_ear * floor_ear, 1.0, v_fk);
	} else {
		lit = ALBEDO * LIGHT_COLOR / PI * ph_toon_pool(ATTENUATION);
	}
	SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);
}
