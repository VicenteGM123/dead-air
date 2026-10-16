// DOCE wheat field: the EAR CLUMPS (mode 0), the EDGE CARDS (mode 1) and the EAR CARDS (mode 2)
// (scripts/world/wheat_field.gd).
// mode 0: 3D wheat clumps (MeadowKit.wheat_clump: stalks, slim nodding ears, awns, a leaf) scattered near the camera
//         on a fixed world grid (one MultiMesh cell = one clump, like the meadow), only where the field map has wheat,
//         their ears rising out of the ear canopy, density falling with the distance; each clump turns about its root
//         with the field's big slow wave and slow ripple and parts round the pushers (hero, beasts).
// mode 1: painted stands of wheat (MeadowPaint's wheat tiles) on cards along the field's border and the road's verges
//         (static instances: each card's +Z faces out of the field), swaying with the same wind: the field's
//         silhouette against the road, the sky and the meadow.
// mode 2: the same painted stands on camera-facing cards (cylindrical billboards) scattered on a grid in the middle
//         ring (beyond the 3D clumps, out to ~45 m): the ears that stand out of the canopy all over the field, so its
//         top stays a mass of ears (not a flat sheet) seen from low down and from the gameplay camera.
// All shade like the canopy at their root (the wheat's mound normal, two golds by the pattern, greener patches,
// lighter wave crests, a soft cel value with the CHOSEN warm shadow, a backlit glow). Alpha list + stencil 32.
shader_type spatial;
render_mode cull_disabled, depth_draw_always, specular_disabled;
stencil_mode write, compare_always, 32;
// FIXER: one source, two programs: as written (mode 0, the 3D clumps) there is no discard; WheatField builds the cards'
// program (modes 1 and 2) with "#define WHEAT_CARDS" inserted after the stencil line (MeadowKit.shader_variant).

#include "res://shaders/pharos.gdshaderinc"
#include "res://shaders/wind.gdshaderinc"
#include "res://shaders/grass_common.gdshaderinc"
#include "res://shaders/meadow_lib.gdshaderinc"
#include "res://shaders/wheat_lib.gdshaderinc"

uniform float mode = 0.0;
uniform float density_far = 0.55;
uniform sampler2D atlas : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform vec4 tile_a = vec4(0.0);
uniform vec4 tile_b = vec4(0.0);
uniform vec4 tile_c = vec4(0.0);
uniform float card_w = 1.05;        // card width (m) for a 1 m tall stand
uniform float near_sink = 0.72;     // FIXER: the canopy's height fraction within reach (see wheat_canopy.gdshader): the ear
                                    // cards (mode 2) are cropped to the band that stands above it
uniform float edge_near = 9.5;      // FIXER: the edge cards give way to the 3D clumps within this distance (m) (FIXER-2:
                                    // 5 -> 9.5, the 3D clumps own the whole edge out to where they fade, 8.5-12 m)
uniform float awn_far = 14.0;       // FIXER: beyond this distance the cards' awns are dropped (less sparkle, fewer pixels)
uniform float front_sheen = 0.3;    // FIXER: warm sheen of the ears when not backlit

varying vec3 v_wroot;
varying float v_part;
varying float v_hf;
varying vec4 v_tile;
varying vec2 v_uv;
varying float v_pat;
varying float v_green;
varying float v_wave;
varying float v_open;
varying float v_lhf;      // fragment -> light: height in the plant, part
varying float v_lpart;
varying vec3 v_lift;
varying vec3 v_base;
varying float v_fogf;
varying float v_cloud;

void vertex() {
	vec3 root3;
	float H;
	float g = 0.0;
	vec3 p;
	vec4 f;
	v_tile = vec4(0.0);
	if (mode < 0.5 || mode > 1.5) {
		// a grid cell (modes 0 and 2): the root jittered in the cell, the ring and the density falloff
		vec3 inst = MODEL_MATRIX[3].xyz;
		vec2 cell = grass_cell(inst);
		vec4 r = grass_rand(cell);
		float r5 = gc_h21(cell + vec2(57.3, 31.1));
		vec2 root = (cell + 0.5 + (r.xy - 0.5) * 0.9) * spacing;
		f = wheat_field(root);
		float dist = length(root - CAMERA_POSITION_WORLD.xz);
		float far_t = clamp((dist - ring.y) / max(ring.w - ring.y, 1.0), 0.0, 1.0);
		float dens = density * mix(1.0, density_far, far_t);
		float thin = clamp((dens - r5) / 0.08 + 0.5, 0.0, 1.0);
		// FIXER: full size right to the field's edge (the stalks are the edge: no floating canopy shelf)
		g = ring_grow(dist, r.z) * thin * smoothstep(0.42, 0.55, f.r);
		vec3 gn;
		// FIXER-2: an instance that does not grow (outside the ring, thinned out, off the field) skips the rest
		float y = g > 0.01 ? terrain_hn(root, gn) : 0.0;
		root3 = vec3(root.x, y, root.y);
		H = 0.0;
		p = vec3(0.0);
		if (g <= 0.01) {
			v_part = 0.0;
			v_hf = 0.0;
			v_uv = vec2(0.0);
		} else if (mode < 0.5) {
			// the stand, its ears just out of the canopy (taller in the field's heart)
			H = wheat_stalk_h(f) * mix(1.12, 1.3, r.x) * g;
			float yaw = atan(g_wind_dir.y, g_wind_dir.x) + (r.w - 0.5) * 3.0;
			vec3 v = VERTEX;
			v = vec3(v.x * cos(yaw) - v.z * sin(yaw), v.y, v.x * sin(yaw) + v.z * cos(yaw));
			float sxz = mix(1.0, 1.3, far_t) * inversesqrt(max(dens, 0.3));
			p = vec3(v.x * sxz, v.y * H, v.z * sxz);
			v_part = UV.x;
			v_hf = clamp(UV.y, 0.0, 1.0);
			v_uv = UV2;
		} else {
			// a camera-facing card (cylindrical) painted with a stand, the ears just out of the canopy
			H = wheat_stalk_h(f) * mix(1.26, 1.44, r.x) * g;
			vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z) + vec3(1e-4, 0.0, 0.0));
			float w = card_w * mix(0.85, 1.15, r.w) * mix(1.0, 1.25, far_t) * inversesqrt(max(dens, 0.3));
			// FIXER: only the band that stands above the canopy is drawn (the rest is hidden by it but was rasterised
			// and shaded anyway): the quad starts a little under the canopy's top at this distance
			float ctop = wheat_canopy(f) * mix(near_sink, 1.0, smoothstep(26.0, 38.0, dist));
			float y0 = clamp((ctop - 0.08) / max(H, 0.05), 0.0, 0.8);
			float yv = mix(y0, 1.0, VERTEX.y);
			p = right * VERTEX.x * w + vec3(0.0, yv * H, 0.0);
			float k = floor(r.w * 2.999);
			v_tile = k < 0.5 ? tile_a : (k < 1.5 ? tile_b : tile_c);
			// mirror half of them
			v_uv = vec2(r.z > 0.5 ? UV.x : 1.0 - UV.x, 1.0 - yv);
			v_part = 0.0;
			v_hf = yv;
		}
	} else {
		// an edge card: the quad (x -0.5..0.5, y 0..1) facing +Z of its instance basis (out of the field)
		root3 = MODEL_MATRIX[3].xyz;
		f = wheat_field(root3.xz);
		float sc = INSTANCE_CUSTOM.g;
		// FIXER: within edge_near of the camera the 3D clumps (full size to the edge) take over from the flat cards
		float cd = length(root3.xz - CAMERA_POSITION_WORLD.xz);
		g = smoothstep(edge_near - 2.0, edge_near + 1.0, cd);
		H = canopy_h * 1.34 * sc * smoothstep(0.15, 0.45, f.r + 0.3) * g;
		vec3 ax = normalize(MODEL_MATRIX[0].xyz);
		p = ax * VERTEX.x * card_w * sc + vec3(0.0, VERTEX.y * H, 0.0);
		float k = floor(INSTANCE_CUSTOM.r * 2.999);
		v_tile = k < 0.5 ? tile_a : (k < 1.5 ? tile_b : tile_c);
		// FIXER: half of them mirrored (custom data b)
		v_uv = vec2(INSTANCE_CUSTOM.b > 0.5 ? 1.0 - UV.x : UV.x, 1.0 - UV.y);
		v_part = 0.0;
		v_hf = UV.y;
	}
	if (g < 0.01 || H < 0.05) {
		// FIXER-2: collapsed (no fragments) without the wind / push / shading work
		if (mode > 0.5 && mode < 1.5) {
			VERTEX = transpose(mat3(MODEL_MATRIX)) * (root3 + vec3(0.0, -80.0, 0.0) - MODEL_MATRIX[3].xyz);
		} else {
			VERTEX = root3 + vec3(0.0, -80.0, 0.0) - MODEL_MATRIX[3].xyz;
		}
		NORMAL = vec3(0.0, 1.0, 0.0);
		v_wroot = root3;
		v_pat = 0.5;
		v_green = 0.0;
		v_wave = 0.0;
		v_open = 0.0;
	} else {
	vec2 wind = mlib_wind(root3.xz, wave_scale, wave_speed);
	wind.x = pow(wind.x, wave_sharp);
	// the wave bows the stalks along the wind, the slow ripple only nods the ears a little (calm, never jittery)
	float a = (0.06 + 0.4 * wind.x * g_wind_gust.x + 0.03 * wind.y) * g_wind;
	vec2 bend = g_wind_dir * a;
	vec3 push = wind_push(root3 + vec3(0.0, 0.5, 0.0));
	bend += push.xy * 1.25;
	float bl = length(bend);
	if (bl > 1.25) {
		bend *= 1.25 / bl;
	}
	p = mlib_rotate(p, bend);
	p.y *= 1.0 - push.z * push.z * 0.6;
	v_wroot = root3;
	VERTEX = root3 + p - MODEL_MATRIX[3].xyz;
	if (mode > 0.5 && mode < 1.5) {
		// the instance basis is a rotation: back to the model space of the card
		VERTEX = (transpose(mat3(MODEL_MATRIX)) * (root3 + p - MODEL_MATRIX[3].xyz));
	}
	vec3 n = wheat_normal(root3.xz, bend);
	if (mode > 0.5 && mode < 1.5) {
		vec3 out_dir = normalize(MODEL_MATRIX[2].xyz);
		n = normalize(n + out_dir * 0.2);
		NORMAL = transpose(mat3(MODEL_MATRIX)) * n;
	} else {
		NORMAL = n;
	}
	v_pat = wheat_pattern(root3.xz);
	v_green = f.a;
	v_wave = wind.x;
	v_open = push.z;
	}
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 albedo;
	vec3 shade;
	float part;
	float hf;
	float vk = 1.0;
	float cdist = length(VERTEX);
#ifdef WHEAT_CARDS
	{
		// painted wheat: R height in the tile, G grain / shade, B part (0 stalk, 0.33 leaf, 0.66 ear, 1 awn), A coverage
		vec4 t = texture(atlas, v_tile.xy + v_uv * v_tile.zw);
		if (t.a < 0.5) {
			discard;
		}
		// FIXER: far away the thin awns go (dithered over 6 m): less sparkle without MSAA, fewer pixels
		if (t.b > 0.85 && gc_h21(floor(FRAGCOORD.xy)) < smoothstep(awn_far, awn_far + 6.0, cdist)) {
			discard;
		}
		part = t.b < 0.2 ? 0.0 : (t.b < 0.5 ? 0.2 : (t.b < 0.85 ? 0.66 : 1.0));
		hf = t.r;
		// the grain / shade detail fades with the distance (FIXER: calmer far field)
		vk = mix(1.0, mix(0.8, 1.12, t.g), 1.0 - 0.7 * smoothstep(12.0, 30.0, cdist));
		// FIXER: the edge cards' lower half sinks into the stand's depth (the canopy's colour under the ears)
		if (mode < 1.5) {
			vk *= mix(0.6, 1.0, smoothstep(0.06, 0.5, hf));
			// FIXER-2: no leaves at the card's sides (the painted leaves are clipped by the tile there: hard vertical
			// edges along the field's foot)
			if (t.b > 0.2 && t.b < 0.5 && abs(v_uv.x - 0.5) > 0.36) {
				discard;
			}
		}
	}
#else
	{
		part = v_part < 0.25 ? 0.0 : (v_part < 0.75 ? 0.66 : 1.0);
		hf = v_hf;
		// grains along the ear: alternating light / dark rows
		if (part > 0.5 && part < 0.8) {
			vk = 0.86 + 0.24 * step(0.5, fract(v_uv.y * 4.5));
		}
	}
#endif
	albedo = wheat_albedo(part, v_pat, v_green, hf);
	shade = wheat_shadow(part, v_green, hf);
	// sheen: lighter wave crests on the ears, darker troughs
	float up = smoothstep(0.55, 0.9, hf);
	vk *= mix(1.0 - sheen * 0.45, 1.0 + sheen, v_wave * mix(0.4, 1.0, up)) * mix(1.0 + sheen * 0.27, 1.0, up);
	vk *= 1.0 - v_open * 0.25;
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
	v_cloud = ph_cloud_shade(v_wroot);
	v_lhf = hf;
	v_lpart = part;
}

void light() {
	vec3 lit;
	if (LIGHT_IS_DIRECTIONAL) {
		float sun_up = (INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).y;
		float sh = ph_toon_shadow(ATTENUATION) * v_cloud;
		float k = wheat_cel(dot(NORMAL, LIGHT), sun_up) * sh;
		vec3 lc = wheat_light(LIGHT_COLOR / PI);
		float back = pow(clamp(dot(LIGHT, -VIEW), 0.0, 1.0), 3.0);
		float up = v_lpart > 0.5 ? 1.0 : smoothstep(0.55, 1.0, v_lhf);
		// backlit: the stalks show their shaded side, the ears and awns glow (Gladiator)
		k *= mix(1.0, 0.4, back * (1.0 - up));
		lit = (ALBEDO * lc + v_lift) * k;
		lit += ALBEDO * vec3(1.15, 1.0, 0.62) * lc * back * wheat_glow * up * sh * (1.0 - g_night);
		// FIXER: a warm sheen on the ears when the sun is NOT behind them (front- and side-lit: the field keeps a golden
		// glow instead of dull ochre straw)
		lit += ALBEDO * vec3(1.1, 0.95, 0.55) * lc * front_sheen * (1.0 - back) * up * sh * (1.0 - g_night);
	} else {
		lit = ALBEDO * LIGHT_COLOR / PI * ph_toon_pool(ATTENUATION);
	}
	SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);
}
