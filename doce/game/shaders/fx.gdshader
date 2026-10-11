// Unshaded vertex-coloured particles and world-space decals (alpha blended).
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform bool billboard = false;
uniform bool soft_round = false;
// Metres the geometry is drawn towards the camera (same place on screen, nearer in depth): a sword trail shows
// over the body that swings it and the foe it cuts, but not through walls further away. 0 = off.
uniform float view_pull = 0.0;

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
	if (view_pull > 0.0) {
		vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float l = max(length(vp.xyz), 1e-4);
		vp.xyz *= max(l - view_pull, 0.12) / l;
		POSITION = PROJECTION_MATRIX * vp;
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
