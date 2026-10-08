// Instanced grass tufts and meadow flowers (MultiMesh). Mesh UV.y = height fraction t (0 root, 1 tip), UV.x > 0.5
// marks head triangles. Per instance: COLOR.rgb = blade tip colour, COLOR.a = flower palette index (0..1),
// INSTANCE_CUSTOM.rgb = root colour (the ground under it), INSTANCE_CUSTOM.a = head mode: < 0.25 no heads
// (collapsed), < 0.75 seed heads (straw; exactly 0.6 = sown crop, which fades much further away), else flowers
// (palette colour).
// Lit like the ground it grows on (NORMAL = the instance's up, which Grass aligns to the smoothed ground normal),
// with the same Compatibility pass compensation as lowpoly.gdshader. Wind waves roll south with the meltemi;
// blades near the hero bend away; the clump shrinks to nothing with distance (no alpha).
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
varying vec3 v_head;
varying float v_t;
varying float v_mode;
varying float v_gust;
varying vec3 v_base;
varying float v_fogf;

// Late-spring meadow flowers of the Cyclades: chamomile, crown daisy, poppy, anemone (violet and pink), Silene,
// borage blue, and the pale yellow of the dunes' horned poppy.
const vec3 FLOWERS[8] = vec3[8](
	vec3(0.957, 0.945, 0.890), // chamomile white
	vec3(0.949, 0.788, 0.298), // crown daisy yellow
	vec3(0.878, 0.290, 0.227), // poppy red
	vec3(0.604, 0.498, 0.820), // anemone violet
	vec3(0.878, 0.478, 0.620), // anemone / cistus pink
	vec3(0.902, 0.561, 0.690), // Silene pink
	vec3(0.420, 0.545, 0.850), // borage blue
	vec3(0.930, 0.860, 0.420)  // horned poppy pale yellow
);

void vertex() {
	float t = UV.y;
	vec3 root_wp = MODEL_MATRIX[3].xyz;
	v_mode = 0.0;
	v_head = vec3(0.0);
	if (UV.x > 0.5) {
		float m = INSTANCE_CUSTOM.a;
		if (m < 0.25) {
			VERTEX = vec3(0.0);
		} else if (m < 0.75) {
			v_mode = 1.0;
			v_head = ph_srgb_to_linear(COLOR.rgb) * vec3(1.08, 1.0, 0.82);
		} else {
			v_mode = 2.0;
			int idx = clamp(int(COLOR.a * 7.0 + 0.5), 0, 7);
			v_head = ph_srgb_to_linear(FLOWERS[idx]);
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
	// Crops (head mode 0.6) are landmarks of the farmland: they shrink away much further out than the meadow.
	float reach = abs(INSTANCE_CUSTOM.a - 0.6) < 0.05 ? 1.7 : 1.0;
	VERTEX *= 1.0 - smoothstep(fade_near * reach, fade_far * reach, cam_d);
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_t = t;
	v_gust = gust * t * (1.0 - g_night);
}

void fragment() {
	vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// Dark only right at the root (contact), then quickly the blade colour, lightest at the tip.
	vec3 albedo = mix(v_root, v_tip, smoothstep(0.0, 0.5, v_t)) * (1.0 + 0.08 * v_gust);
	if (v_mode > 0.5) {
		albedo = v_head;
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
