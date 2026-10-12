// DOCE anime meadow flowers (scripts/world/anime_meadow.gd): clusters of small blossoms (MeadowKit.flower_cluster:
// one triangle a blossom), baked over the meadow map's drifts in static regions. Each blossom sits in the top of the
// grass at its root (some half hidden among the blades), faces the camera tilted up like a flower facing the sky,
// and is cut per pixel into a 5-petal flower with a heart. The cluster shares the mound normal, the cel value and
// the wind of the clump it grows in (turns about its root with the same wave, noise and pushers).
// Species (custom data r): 0 pink campion (the reference's pink), 1/3 red poppy, 2/3 white chamomile, 1 purple
// anemone. Drawn like the grass (alpha list, stencil 32: no ink lines).
shader_type spatial;
render_mode cull_disabled, depth_draw_always, specular_disabled;
stencil_mode write, compare_always, 32;

#include "res://shaders/pharos.gdshaderinc"
#include "res://shaders/wind.gdshaderinc"
#include "res://shaders/grass_common.gdshaderinc"
#include "res://shaders/meadow_lib.gdshaderinc"

uniform float bloom_size = 0.05;    // blossom radius (m) of a size-1 pink campion (FIXER: 0.033 -> 0.05, fewer and
                                    // bigger heads in tighter heaps: soft dabs like the reference, not confetti)

varying vec2 v_p;          // position in the blossom (inradius 1)
varying float v_sp;        // species
varying float v_rnd;       // the blossom's random
varying float v_rot;       // petal rotation
varying float v_mh;
varying vec3 v_wroot;
varying vec3 v_lift;
varying vec3 v_base;
varying float v_fogf;
varying float v_cloud;
varying vec3 v_drop;       // FIXER: cast shadow -> chosen shadow colour (see mlib_lit)

// Petal colours (sRGB display targets in the day light, like the meadow palette).
vec3 petal_target(float sp, float rnd) {
	if (sp < 0.17) {
		return mix(vec3(226.0, 140.0, 168.0), vec3(242.0, 166.0, 190.0), rnd); // pink campion (the reference)
	} else if (sp < 0.5) {
		return mix(vec3(218.0, 36.0, 30.0), vec3(236.0, 62.0, 40.0), rnd); // poppy
	} else if (sp < 0.84) {
		return mix(vec3(244.0, 242.0, 230.0), vec3(252.0, 250.0, 242.0), rnd); // chamomile
	}
	return mix(vec3(146.0, 96.0, 206.0), vec3(166.0, 112.0, 220.0), rnd); // anemone
}

vec3 heart_target(float sp) {
	if (sp < 0.17) {
		return vec3(250.0, 214.0, 222.0);
	} else if (sp < 0.5) {
		return vec3(96.0, 36.0, 40.0);   // FIXER: lighter (was near black: dark specks at native size)
	} else if (sp < 0.84) {
		return vec3(240.0, 190.0, 40.0);
	}
	return vec3(112.0, 84.0, 160.0);     // FIXER: lighter (was near black)
}

float species_size(float sp) {
	if (sp < 0.17) {
		return 1.0;
	} else if (sp < 0.5) {
		return 1.2;
	} else if (sp < 0.84) {
		return 0.8;
	}
	return 1.0;
}

void vertex() {
	vec3 root3 = MODEL_MATRIX[3].xyz;
	vec2 root = root3.xz;
	vec4 mm = sample_meadow(root);
	float dist = length(root - CAMERA_POSITION_WORLD.xz);
	float rnd = INSTANCE_CUSTOM.g;
	float grow = ring_grow(dist, rnd);
	// the blossoms sit in the top of the grass (its height at the root)
	float H = mm.r * max_height * grow;
	float yaw = INSTANCE_CUSTOM.b * 6.2831853;
	float sc = INSTANCE_CUSTOM.a;
	float sp = INSTANCE_CUSTOM.r;
	vec3 c = VERTEX;
	c = vec3(c.x * cos(yaw) - c.z * sin(yaw), c.y, c.x * sin(yaw) + c.z * cos(yaw));
	c = vec3(c.x * sc, c.y * H, c.z * sc);
	vec2 wind = mlib_wind(root, 1.0, 1.0);
	vec3 bend = mlib_bend(root3, wind, 1.0);
	c = mlib_rotate(c, bend.xy);
	c.y *= 1.0 - bend.z * bend.z * 0.55;
	// the blossom's plane: facing the camera, tilted up (a flower looks at the sky)
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - (root3 + c));
	vec3 n = normalize(to_cam + vec3(0.0, 0.9, 0.0));
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z) + vec3(1e-4, 0.0, 0.0));
	vec3 up = normalize(cross(n, right));
	float R = bloom_size * species_size(sp) * UV2.x * mix(0.3, 1.0, grow);
	vec3 p = c + (right * UV.x + up * UV.y) * R;
	if (H < 0.03 || grow < 0.01) {
		p = vec3(0.0, -80.0, 0.0);
	}
	VERTEX = p;
	v_p = UV;
	v_sp = sp;
	v_rnd = fract(UV2.y * 7.31 + rnd * 3.7);
	v_rot = UV2.y * 6.2831853;
	v_wroot = root3;
	vec4 mo = mlib_mound(root);
	v_mh = mo.b;
	NORMAL = mlib_normal(vec3(0.0, 1.0, 0.0), mlib_slope(mo.rg, mlib_tuft_fade(mlib_mound2(root), dist), 1.0), 1.0);
}

void fragment() {
	// one normal for the whole cluster, both faces (Godot flips it on back faces)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// five rounded petals round a heart, inscribed in the triangle; FIXER: small on screen (a few pixels across) the
	// blossom becomes a soft round dab and its heart melts into the petals (no star confetti, no dark specks)
	float r = length(v_p);
	float th = atan(v_p.y, v_p.x) + v_rot;
	float lobe = abs(cos(2.5 * th));
	float detail = 1.0 - smoothstep(0.1, 0.28, fwidth(r));
	float edge = mix(0.93, 0.66 + 0.34 * pow(lobe, 0.55), detail);
	if (r > edge) {
		discard;
	}
	float heart_r = (v_sp < 0.17 ? 0.26 : (v_sp > 0.5 && v_sp < 0.84 ? 0.4 : 0.22)) * mix(0.55, 1.0, detail);
	vec3 pc = mlib_lin(petal_target(v_sp, v_rnd));
	// roundness: the petals darker towards the heart and the lower side, lighter at the tips
	pc *= mix(0.8, 1.06, smoothstep(0.2, 0.9, r / edge)) * mix(0.86, 1.04, smoothstep(-1.0, 0.8, v_p.y));
	// the creases between the petals (each petal reads as one, close up)
	pc *= mix(mix(0.92, 0.74, detail), 1.0, smoothstep(0.04, 0.3, lobe) + (1.0 - smoothstep(0.3, 0.55, r)));
	vec3 col = r < heart_r ? mix(pc, mlib_lin(heart_target(v_sp)), mix(0.35, 1.0, detail)) : pc;
	vec3 albedo = ph_toon_night(col / MLIB_LIT_DAY);
	// in the grass's shadow a flower keeps its colour, cooler and deeper (a chosen shadow, like the grass)
	vec3 shade = ph_toon_night(col * vec3(0.5, 0.48, 0.62) / MLIB_AMB_DAY);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 ambl = ph_toon_ambient(wn);
	vec3 amb = albedo * ambl;
	vec3 shadow = mlib_mood_shadow(shade * ambl, ambl);
	float f = ph_fog(VERTEX);
	ALBEDO = ph_out(albedo);
	EMISSION = ph_out(mix(shadow * cast_k, g_fog_color, f));
#ifndef MEADOW_OPAQUE
	ALPHA = 1.0;
#endif
	v_lift = amb - shadow;
	v_drop = shadow * (1.0 - cast_k);
	v_base = ph_godot_in(EMISSION);
	v_fogf = f;
	v_cloud = ph_cloud_shade(v_wroot);
}

void light() {
	vec3 lit;
	if (LIGHT_IS_DIRECTIONAL) {
		float sun_up = (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).y;
		float k = mlib_cel(dot(NORMAL, LIGHT), sun_up, v_mh);
		lit = mlib_lit(ALBEDO * LIGHT_COLOR / PI, v_lift, v_drop, k, ph_toon_shadow(ATTENUATION), v_cloud);
	} else {
		lit = ALBEDO * LIGHT_COLOR / PI * ph_toon_pool(ATTENUATION);
	}
	SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);
}
