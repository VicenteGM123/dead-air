// Unshaded vertex-coloured particles and world-space decals (alpha blended).
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform bool billboard = false;
uniform bool soft_round = false;

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	float a = COLOR.a;
	if (soft_round) {
		float d = length(UV - vec2(0.5)) * 2.0;
		a *= smoothstep(1.0, 0.6, d);
	}
	vec3 c = ph_srgb_to_linear(COLOR.rgb);
	ALBEDO = ph_out(mix(c, g_fog_color, ph_fog(VERTEX)));
	ALPHA = a;
}
