// Instanced grass clumps (MultiMesh). Mesh UV.y = height fraction t (0 root, 1 tip), UV.x > 0.5 marks the seed
// heads. Per instance: COLOR.rgb = tip colour, INSTANCE_CUSTOM.rgb = root colour, INSTANCE_CUSTOM.a = seed flag.
// Lit like the facet it grows on (NORMAL = the instance's up, which Grass aligns to the facet normal), with the
// same Compatibility pass compensation as lowpoly.gdshader. Wind waves roll south with the meltemi; blades
// near the hero bend away; the clump shrinks to nothing with distance (no alpha).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform float wrap = 0.5;
uniform sampler2D ground_tex : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform vec4 ground_rect = vec4(-72.0, -72.0, 144.0, 144.0);
uniform vec3 hero_pos = vec3(0.0, -100.0, 0.0);
uniform float fade_near = 52.0;
uniform float fade_far = 72.0;

varying vec3 v_root;
varying vec3 v_tip;
varying float v_t;
varying float v_seed;
varying float v_gust;
varying vec3 v_base;
varying float v_fogf;

void vertex() {
	float t = UV.y;
	vec3 root_wp = MODEL_MATRIX[3].xyz;
	v_seed = 0.0;
	if (UV.x > 0.5) {
		v_seed = 1.0;
		if (INSTANCE_CUSTOM.a < 0.5) {
			VERTEX = vec3(0.0);
		}
	}
	vec2 guv = (root_wp.xz - ground_rect.xy) / ground_rect.zw;
	float ao = textureLod(ground_tex, guv, 0.0).r;
	v_root = ph_srgb_to_linear(INSTANCE_CUSTOM.rgb) * mix(1.0, 0.62, ao);
	v_tip = ph_srgb_to_linear(COLOR.rgb);
	float gust = ph_noise(root_wp.xz * 0.06 - vec2(0.0, g_time * 0.35));
	vec3 w = vec3(0.25, 0.0, 1.0) * (0.35 * sin(2.1 * g_time + dot(root_wp.xz, vec2(0.37, 0.21))) + 0.9 * gust) * t * t * 0.14 * g_wind;
	vec2 away = root_wp.xz - hero_pos.xz;
	float k = 1.0 - smoothstep(0.3, 1.2, length(away));
	w.xz += normalize(away + vec2(1e-4)) * k * 0.18 * t;
	w.y -= k * 0.08 * t;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * w;
	float cam_d = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	VERTEX.y *= 1.0 - smoothstep(fade_near, fade_far, cam_d);
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_t = t;
	v_gust = gust * t * (1.0 - g_night);
}

void fragment() {
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 albedo = mix(v_root, v_tip, smoothstep(0.0, 1.0, v_t)) * (1.0 + 0.08 * v_gust);
	if (v_seed > 0.5) {
		albedo = v_tip * vec3(1.08, 1.0, 0.82);
	}
	vec3 base = albedo * ph_ambient(wn);
	float f = ph_fog(VERTEX);
	NORMAL = n;
	ALBEDO = ph_out(albedo);
	EMISSION = ph_out(mix(base, g_fog_color, f));
	v_base = ph_godot_in(EMISSION);
	v_fogf = f;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float d = max((ndl + wrap) / (1.0 + wrap), 0.0);
	vec3 lit = ALBEDO * LIGHT_COLOR / PI * d * ATTENUATION;
	SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);
}
