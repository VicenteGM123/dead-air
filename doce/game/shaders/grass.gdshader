// Grass and meadow flowers (DOCE): a MultiMesh grid that follows the camera (Grass moves it in whole cells), so
// every world cell always grows the same tuft. Each instance hashes its cell for jitter, turn, height and hue;
// its root sits exactly on the terrain triangle (height_tex: the terrain's vertex heights, same triangulation as
// the mesh and height_at()); what grows comes from the ground: color_tex (ground colour, a = grassiness) and the
// ground map (B paths, A no-grass under props, G bare soil, R contact AO). Instances that should not grow
// collapse to a point. Lit like the ground (NORMAL up), toon ramp, wind waves, blades bend away from the hero,
// tufts shrink to nothing with distance (no alpha).
// Mesh: UV.y = height fraction (0 root, 1 tip), UV.x > 0.5 marks head triangles (seed heads / flower heads).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D color_tex : filter_linear, repeat_disable;
uniform sampler2D ground_tex : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform vec4 grid = vec4(-192.0, -192.0, 1.0, 385.0); // origin x, origin z, cell, vertices per side
uniform vec4 ground_rect = vec4(-192.0, -192.0, 384.0, 384.0);
uniform float spacing = 0.45;
uniform vec3 grid_center = vec3(0.0); // the near grid's centre (the far layer skips it)
uniform float skip_half = 0.0; // > 0: skip instances inside this half-size square round grid_center
uniform float density = 1.0;
uniform vec2 tuft_scale = vec2(1.2, 1.9);
uniform float flowers = 0.0; // 1 = flower layer
uniform vec3 hero_pos = vec3(0.0, -100.0, 0.0);
uniform float fade_near = 30.0;
uniform float fade_far = 44.0;

varying vec3 v_root;
varying vec3 v_tip;
varying vec3 v_head;
varying float v_t;
varying float v_mode;
varying float v_gust;
varying vec3 v_base;
varying float v_fogf;
varying float v_cloud;
varying vec3 v_wroot;
varying vec3 v_day;

const vec3 FLOWERS[8] = vec3[8](
	vec3(0.957, 0.945, 0.890), // chamomile white
	vec3(0.949, 0.788, 0.298), // crown daisy yellow
	vec3(0.878, 0.290, 0.227), // poppy red
	vec3(0.604, 0.498, 0.820), // anemone violet
	vec3(0.878, 0.478, 0.620), // anemone pink
	vec3(0.902, 0.561, 0.690), // Silene pink
	vec3(0.420, 0.545, 0.850), // borage blue
	vec3(0.930, 0.860, 0.420)  // horned poppy pale yellow
);

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float terrain_h(vec2 p) {
	vec2 f = (p - grid.xy) / grid.z;
	vec2 fi = floor(f);
	ivec2 i = ivec2(fi);
	int n = int(grid.w) - 2;
	i = clamp(i, ivec2(0), ivec2(n));
	vec2 t = clamp(f - vec2(i), 0.0, 1.0);
	float ha = texelFetch(height_tex, i, 0).r;
	float hb = texelFetch(height_tex, i + ivec2(1, 0), 0).r;
	float hc = texelFetch(height_tex, i + ivec2(1, 1), 0).r;
	float hd = texelFetch(height_tex, i + ivec2(0, 1), 0).r;
	if (((i.x + i.y) & 1) == 0) {
		if (t.x >= t.y) {
			return ha + (hb - ha) * t.x + (hc - hb) * t.y;
		}
		return ha + (hc - hd) * t.x + (hd - ha) * t.y;
	}
	if (t.x + t.y <= 1.0) {
		return ha + (hb - ha) * t.x + (hd - ha) * t.y;
	}
	return hc + (hd - hc) * (1.0 - t.x) + (hb - hc) * (1.0 - t.y);
}

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	vec2 cell = floor(inst.xz / spacing + 0.5);
	float r1 = h21(cell);
	float r2 = h21(cell + vec2(13.1, 7.7));
	float r3 = h21(cell + vec2(27.7, 3.1));
	float r4 = h21(cell + vec2(41.3, 19.9));
	vec2 root = (cell + (vec2(r1, r2) - 0.5) * 0.94) * spacing;
	vec2 cuv = ((root - grid.xy) / grid.z + 0.5) / grid.w;
	vec4 gc = texture(color_tex, cuv);
	vec4 gm = textureLod(ground_tex, (root - ground_rect.xy) / ground_rect.zw, 0.0);
	float cam_d = length(root - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_near, fade_far, cam_d);
	float keep = gc.a * (1.0 - smoothstep(0.22, 0.42, gm.b)) * (1.0 - smoothstep(0.3, 0.6, gm.a)) * (1.0 - gm.g * 0.6);
	// Clumps: patches with short gaps between them.
	float clump = 0.55 + 0.75 * ph_noise(root * 0.42);
	float dry = smoothstep(-0.04, 0.12, gc.r - gc.g);
	if (flowers > 0.5) {
		// Drifts of one or two species where the meadow is green.
		float drift = smoothstep(0.42, 0.62, ph_noise(root * 0.075 + vec2(31.0, 7.0)) + 0.15 * ph_noise(root * 0.3));
		keep *= drift * (1.0 - dry * 0.7);
		clump = 1.0;
	}
	if (skip_half > 0.0 && max(abs(root.x - grid_center.x), abs(root.y - grid_center.z)) < skip_half) {
		keep = 0.0;
	}
	bool alive = r3 < keep * clump * density && fade > 0.0 && gc.a > 0.05;
	float t = UV.y;
	v_mode = 0.0;
	v_head = vec3(0.0);
	if (UV.x > 0.5) {
		if (flowers > 0.5) {
			v_mode = 2.0;
			float sp = floor(ph_noise(root * 0.045 + vec2(5.0, 11.0)) * 6.0 + r4 * 2.0);
			int idx = int(mod(sp, 8.0));
			v_head = ph_srgb_to_linear(FLOWERS[idx]);
		} else if (dry > 0.4 && r4 > 0.45) {
			v_mode = 1.0;
			v_head = ph_srgb_to_linear(vec3(0.89, 0.82, 0.6));
		} else {
			alive = false; // no head on green tufts
		}
	}
	vec3 wp = vec3(0.0);
	if (alive) {
		float yaw = r4 * TAU;
		float sc = mix(tuft_scale.x, tuft_scale.y, r1) * mix(1.0, 0.8, dry) * fade;
		vec3 v = VERTEX;
		v = vec3(v.x * cos(yaw) - v.z * sin(yaw), v.y, v.x * sin(yaw) + v.z * cos(yaw)) * sc;
		float y = terrain_h(root);
		// Wind waves rolling south, the hero's wake.
		float gust = ph_noise(root * 0.06 - vec2(0.0, g_time * 0.35));
		vec3 w = vec3(0.25, 0.0, 1.0) * (0.35 * sin(2.1 * g_time + dot(root, vec2(0.37, 0.21))) + 0.9 * gust) * t * t * 0.16 * g_wind;
		vec2 away = root - hero_pos.xz;
		float k = (1.0 - smoothstep(0.3, 1.3, length(away))) * (1.0 - smoothstep(1.0, 2.5, abs(y - hero_pos.y)));
		w.xz += normalize(away + vec2(1e-4)) * k * 0.22 * t;
		w.y -= k * 0.1 * t;
		wp = vec3(root.x, y - 0.02, root.y) + v + w;
		v_gust = gust * t * (1.0 - g_night);
	} else {
		wp = vec3(root.x, -50.0, root.y);
		v_gust = 0.0;
	}
	VERTEX = wp - inst;
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_t = t;
	v_wroot = vec3(root.x, wp.y, root.y);
	// Colours: the root takes the ground colour (darker in contact shade), the tip a fresher or a golden tint.
	vec3 ground = ph_srgb_to_linear(gc.rgb);
	vec3 fresh = ph_srgb_to_linear(vec3(0.64, 0.76, 0.36));
	vec3 straw = ph_srgb_to_linear(vec3(0.86, 0.78, 0.5));
	vec3 tipc = mix(mix(ground, fresh, 0.45), straw, dry * 0.75);
	tipc *= mix(0.88, 1.12, r2);
	v_root = ph_toon_albedo_day(ground * 0.82) * mix(1.0, 0.6, gm.r);
	v_tip = ph_toon_albedo_day(tipc);
}

void fragment() {
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 tip = v_tip * mix(vec3(1.0), vec3(1.18, 1.14, 0.84), smoothstep(0.6, 0.78, v_t));
	vec3 albedo = mix(v_root, tip, smoothstep(0.0, 0.55, v_t)) * (1.0 + 0.18 * v_gust);
	if (v_mode > 0.5) {
		albedo = v_head;
	}
	v_day = albedo;
	albedo = ph_toon_night(albedo);
	vec3 base = albedo * ph_toon_ambient(wn);
	float f = ph_fog(VERTEX);
	NORMAL = n;
	ALBEDO = ph_out(albedo);
	EMISSION = ph_out(mix(base, g_fog_color, f));
	v_base = ph_godot_in(EMISSION);
	v_fogf = f;
	v_cloud = ph_cloud_shade(v_wroot);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	vec3 lit;
	if (LIGHT_IS_DIRECTIONAL) {
		float k = ph_toon_ramp(ndl) * ph_toon_shadow(ATTENUATION) * v_cloud;
		lit = ALBEDO * LIGHT_COLOR / PI * k;
	} else {
		lit = v_day * LIGHT_COLOR / PI * ph_toon_pool(ATTENUATION);
	}
	SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);
}
