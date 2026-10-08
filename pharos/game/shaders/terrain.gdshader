// Island ground. Same lighting as lowpoly.gdshader (flat facets, hemisphere ambient, wrapped sun, haze, and the
// Compatibility sRGB pass compensation of pharos.gdshaderinc), plus:
//   - a ground map (ground_tex over ground_rect): R = contact AO under trees, rocks and walls, G = bare soil /
//     wear (olive basins, vine rows, lane verges, cleared build plots);
//   - painterly grass strokes, stretched north-south along the meltemi, scaled by the vertex alpha
//     (grassiness: 0 on sand, rock, plaza, paths and risers) and faded with distance.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform float wrap = 0.35;
uniform sampler2D ground_tex : filter_linear_mipmap, repeat_disable, hint_default_black;
uniform vec4 ground_rect = vec4(-72.0, -72.0, 144.0, 144.0);
uniform float stroke_far = 60.0;

varying vec3 v_albedo;
varying float v_grass;
varying vec3 v_wpos;
varying vec3 v_base;
varying float v_fogf;

void vertex() {
	v_albedo = ph_srgb_to_linear(COLOR.rgb);
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
	const vec3 SOIL_LIN = vec3(0.4026, 0.2318, 0.1191); // #A98361
	vec3 albedo = mix(v_albedo, SOIL_LIN * (1.0 - 0.15 * gm.g), gm.g * 0.85);
	float fade = v_grass * (1.0 - smoothstep(stroke_far * 0.5, stroke_far, length(VERTEX)));
	if (fade > 0.001) {
		vec2 q = vec2(v_wpos.x * 1.9 + v_wpos.z * 0.4, v_wpos.z * 0.75); // strokes stretched N-S
		float n = 0.6 * ph_noise(q * 1.6) + 0.4 * ph_noise(q * 4.1);
		float st = smoothstep(0.42, 0.50, n) + smoothstep(0.62, 0.70, n) - 1.0; // three posterised levels
		vec3 stroke = (1.0 + 0.05 * st) * (st > 0.0 ? vec3(1.06, 1.02, 0.90) : vec3(1.0));
		albedo *= mix(vec3(1.0), stroke, fade);
	}
	albedo *= mix(1.0, 0.62, gm.r);
	vec3 base = albedo * ph_ambient(wn);
	float f = ph_fog(VERTEX);
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
