// DOCE anime meadow grass, after Trung Duy Nguyen's "Anime Grass" method (scripts/world/anime_meadow.gd).
// Low-poly grass clumps (MeadowKit.grass_clump: 5 blades, 15 triangles; 3 blades in the mid ring) and, far away,
// 2-triangle camera-facing billboards painted with a clump (MeadowKit.billboard_texture), scattered over the ground
// where the grass mask is on: each MultiMesh instance is one cell of a camera-centred chunk grid (same world cell =
// same clump), its root on the exact terrain triangle, a random yaw loosely combed with the wind, a random scale
// MULTIPLIED by the mask through a smooth ramp (the grass shrinks to nothing at path edges and under props), and a
// density that falls off with the distance from the camera (the survivors grow a little wider to keep the cover).
//
// Shading (meadow_lib.gdshaderinc): EVERY vertex of a clump takes the mound normal at the clump's ROOT, the ground
// under it takes the same normal (terrain.gdshader), so they light as one surface with hand-painted shadow shapes;
// two greens mixed by the same blob pattern; a cel ramp with a chosen deep cool shadow colour; tips glow when the
// sun is behind them. Wind: one noise at the root (slow wave + fast noise) turns the whole clump about its root,
// the wave darkens it a little where it bends; the tips flutter. The pushers (hero, beasts) bend it away.
//
// Drawn in the ALPHA list (ALPHA = 1: still opaque, depth written) with a negative render priority, writing the
// stencil bit 32 that keeps toon_edges.gdshader's ink lines off the grass (an opaque material writing stencil would
// force a depth prepass of the whole scene in Godot's Compatibility renderer).
shader_type spatial;
render_mode cull_disabled, depth_draw_always, specular_disabled;
stencil_mode write, compare_always, 32;
// FIXER: one source, two programs. As written (no define) these are the 3D clumps, WITHOUT discard (early depth
// rejection stays on); AnimeMeadow builds the far billboards' program from this same code with "#define MEADOW_CARDS"
// inserted after the stencil line (the painted clump is cut with discard there only). "#define MEADOW_OPAQUE" (lab
// test, arg grassopaque=1) leaves ALPHA unwritten: the opaque list instead of the alpha list.

#include "res://shaders/pharos.gdshaderinc"
#include "res://shaders/wind.gdshaderinc"
#include "res://shaders/grass_common.gdshaderinc"
#include "res://shaders/meadow_lib.gdshaderinc"

uniform float lod = 0.0;            // 0 near clumps, 1 mid clumps, 2 far billboards
uniform float width_k = 1.0;        // horizontal scale of the clump mesh
uniform float density_far = 0.45;   // fraction of the clumps kept at the far end of the ring
uniform float flex = 1.0;           // how much the clumps give to the wind
uniform sampler2D bb_tex : filter_linear_mipmap, repeat_disable, hint_default_white;
uniform float bb_w = 0.7;           // billboard width (m) for a 1 m tall clump

varying vec3 v_albedo;
varying vec3 v_shade;     // the chosen shadow albedo (x ambient = the shadow colour, the base pass)
varying float v_mh;       // the mound height at the root (the folds sink into the shadow)
varying vec3 v_lift;      // albedo * ambient - the chosen shadow colour (light() adds it back in the light)
varying float v_hf;
varying vec3 v_wroot;
varying vec2 v_bb;        // billboard: atlas u offset, unused for clumps
varying vec3 v_base;
varying float v_fogf;
varying float v_cloud;
varying float v_glow;
varying float v_far;      // 0 near .. 1 far (the cel softens with the distance, like the ground)
varying vec3 v_drop;      // FIXER: cast shadow -> chosen shadow colour (see mlib_lit)

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	vec2 cell = grass_cell(inst);
	vec4 r = grass_rand(cell);
	float r5 = gc_h21(cell + vec2(57.3, 31.1));
	vec2 root = (cell + 0.5 + (r.xy - 0.5) * 0.9) * spacing;
	vec4 gc = sample_color(root);
	vec4 gm = sample_ground(root);
	vec4 mm = sample_meadow(root);
	float dist = length(root - CAMERA_POSITION_WORLD.xz);
	// The mask (grassiness, paths, props, bare soil, the meadow's density) through a smooth ramp.
	float mask = smoothstep(0.02, 0.3, grass_keep(gc, gm) * mm.g);
	// Trung: less grass with distance; the survivors grow wider to keep the cover.
	float far_t = clamp((dist - ring.y) / max(ring.w - ring.y, 1.0), 0.0, 1.0);
	float dens = density * mix(1.0, density_far, far_t);
	float thin = clamp((dens - r5) / 0.08 + 0.5, 0.0, 1.0);
	float g = ring_grow(dist, r.z) * thin * mask;
	float H = mm.r * max_height * mix(0.78, 1.16, r.x) * g;
	vec3 gn;
	float y = terrain_hn(root, gn);
	vec3 root3 = vec3(root.x, y, root.y);
	vec3 wp;
	v_bb = vec2(0.0);
	if (g > 0.01 && H > 0.03) {
		float sxz = width_k * inversesqrt(max(dens, 0.2)) * smoothstep(0.0, 0.4, g);
		vec3 p;
#ifdef MEADOW_CARDS
		{
			// Billboard: a quad turned to the camera (cylindrical), painted with a clump.
			vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z) + vec3(1e-4, 0.0, 0.0));
			p = right * VERTEX.x * bb_w * sxz * mix(1.0, H / 0.5, 0.35) + vec3(0.0, VERTEX.y * H * 1.08, 0.0);
			v_bb = vec2(floor(r.w * 3.0) / 3.0, 0.0);
		}
#else
		{
			// Trung: random yaw, here COMBED: a smooth field turns neighbouring clumps the same way (the strokes of a
			// painted meadow lean together in patches), loosely along the wind; the clump is scaled by its height
			// (the mesh is a 1 m clump) and widened where the density thins.
			float comb = ph_noise(root * 0.21 + vec2(5.3, 1.7)) - 0.5;
			float yaw = atan(g_wind_dir.y, g_wind_dir.x) + comb * 2.8 + (r.w - 0.5) * 1.1;
			vec3 v = VERTEX;
			v = vec3(v.x * cos(yaw) - v.z * sin(yaw), v.y, v.x * sin(yaw) + v.z * cos(yaw));
			p = vec3(v.x * sxz * H, v.y * H, v.z * sxz * H);
		}
#endif
#ifdef MEADOW_CARDS
		float hf = clamp(UV.y, 0.0, 1.0);
#else
		float hf = clamp(UV.y * UV2.y, 0.0, 1.0);
#endif
		// Wind (Trung): one noise at the root -> a slow wave and a fast noise turn the clump about its root.
		vec2 wind = mlib_wind(root, 1.0, 1.0);
		vec3 bend = mlib_bend(root3, wind, flex);
		// the verges: clumps by a path lean out over it (the path's edge disappears under the grass)
		float pb = gm.b;
		float verge = smoothstep(0.01, 0.16, pb) * (1.0 - smoothstep(0.44, 0.54, pb));
		if (verge > 0.01) {
			vec2 grad = vec2(sample_ground(root + vec2(0.5, 0.0)).b - sample_ground(root - vec2(0.5, 0.0)).b, sample_ground(root + vec2(0.0, 0.5)).b - sample_ground(root - vec2(0.0, 0.5)).b);
			float gl = length(grad);
			if (gl > 1e-3) {
				bend.xy += grad / gl * verge * 0.85;
			}
		}
		p = mlib_rotate(p, bend.xy);
		// under the feet: lie down
		p.y *= 1.0 - bend.z * bend.z * 0.55;
		// tip flutter (a few centimetres, per blade)
#ifndef MEADOW_CARDS
		p.xz += wind_flutter(root, UV.x, wind.x) * hf * hf * H * 0.12;
#endif
		wp = root3 + p;
		// Colour: the zone of the ground at the root, two greens by the blob pattern, the canopy gradient.
		vec4 mo = mlib_mound(root);
		vec3 m2 = mlib_tuft_fade(mlib_mound2(root), dist);
		float big = mlib_big(root);
		vec3 alb = mlib_grass_albedo(gc.rgb, mo.b, hf, big);
		vec3 sha = mlib_grass_shadow(gc.rgb, mo.b, hf, big);
		// the wind wave darkens the grass where it bends (Trung), its crest's upper blades catch a sheen (FIXER)
		float wk = mlib_wave_tint(wind.x, g_wind_gust.x, hf);
		// contact shade under trees and rocks
		float ck = mix(1.0, 0.6, gm.r * (1.0 - 0.5 * hf));
		v_albedo = alb * wk * ck;
		v_shade = sha * wk * ck;
		// short lawns have shallow mounds (the masses are the grass's own bulk)
		float mstr = smoothstep(0.12, 0.42, mm.r * max_height);
		v_mh = mix(0.5, mo.b, mstr);
		v_hf = hf;
		// THE KEY: the clump's normal is the mound normal at its root (the ground uses the same).
		NORMAL = mlib_normal(gn, mlib_slope(mo.rg, m2, mask * mstr), 1.0);
		// the gusts tilt the mass with the bend (the light on the field changes as the waves roll through)
		NORMAL = normalize(NORMAL + vec3(g_wind_dir.x, 0.0, g_wind_dir.y) * wind.x * g_wind_gust.x * MLIB_GUST_TILT * g_wind);
		v_glow = tip_glow * smoothstep(0.45, 1.0, hf);
	} else {
		wp = vec3(root.x, -80.0, root.y);
		v_albedo = vec3(0.0);
		v_shade = vec3(0.0);
		v_mh = 0.5;
		v_hf = 0.0;
		v_glow = 0.0;
		NORMAL = vec3(0.0, 1.0, 0.0);
	}
	v_wroot = root3;
	v_far = mlib_far(dist);
	VERTEX = wp - inst;
}

void fragment() {
	// Trung: ONE normal for the whole plant, both faces (Godot flips it on back faces of cull_disabled meshes)
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 albedo = v_albedo;
	vec3 shade = v_shade;
#ifdef MEADOW_CARDS
	{
		// the painted clump: R height fraction, G shade (back .. front blades), A coverage
		vec4 t = texture(bb_tex, vec2(v_bb.x + UV.x / 3.0, 1.0 - UV.y));
		if (t.a < 0.5) {
			discard;
		}
		float pk = mix(0.74, 1.08, t.g) * mix(0.72, 1.0, t.r);
		albedo *= pk;
		shade *= pk;
	}
#endif
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	albedo = ph_toon_night(albedo);
	vec3 ambl = ph_toon_ambient(wn);
	vec3 amb = albedo * ambl;
	// the chosen shadow colour: a deep, cool green
	vec3 shadow = mlib_mood_shadow(ph_toon_night(shade) * ambl, ambl);
	float f = ph_fog(VERTEX);
	ALBEDO = ph_out(albedo);
	// FIXER: the base pass is the CAST shadow colour; light() lifts it to the chosen (form) shadow colour and on
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
		float k = mlib_cel_far(dot(NORMAL, LIGHT), sun_up, v_mh, v_far);
		vec3 alb = ALBEDO; // already linear here (Godot converted it)
		lit = mlib_lit(alb * LIGHT_COLOR / PI, v_lift, v_drop, k, ph_toon_shadow(ATTENUATION), v_cloud);
		// backlight: the upper blades glow warm against the sun
		float back = pow(clamp(dot(LIGHT, -VIEW), 0.0, 1.0), 4.0);
		lit += alb * vec3(1.25, 1.1, 0.55) * LIGHT_COLOR / PI * back * v_glow * ph_toon_shadow(ATTENUATION) * v_cloud * (1.0 - g_night);
	} else {
		lit = ALBEDO * LIGHT_COLOR / PI * ph_toon_pool(ATTENUATION);
	}
	SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);
}
