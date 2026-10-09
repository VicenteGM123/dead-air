// Additive soft halo: a camera-facing quad with a radial falloff. Vertex colour = tint, alpha = intensity.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform bool billboard = true;
uniform bool uv_falloff = true;
uniform float pull = 0.35; // metres pulled toward the camera so the halo is not clipped by its owner
uniform float intensity = 1.0;
uniform vec3 tint_color = vec3(1.0);
uniform bool star = false; // TOON: four-point anime sparkle instead of a round halo

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	}
	MODELVIEW_MATRIX[3].xyz += normalize(-MODELVIEW_MATRIX[3].xyz) * pull;
}

void fragment() {
	float g = 1.0;
	if (star) {
		vec2 q = abs(UV - vec2(0.5)) * 2.0;
		float arms = max(smoothstep(0.14, 0.0, q.y) * (1.0 - q.x), smoothstep(0.14, 0.0, q.x) * (1.0 - q.y));
		float core = smoothstep(0.42, 0.12, length(q));
		float halo = pow(clamp(1.0 - length(q), 0.0, 1.0), 2.0) * 0.35;
		g = clamp(max(max(arms * 1.4, core * 1.6), halo), 0.0, 1.6);
	} else if (uv_falloff) {
		float d = length(UV - vec2(0.5)) * 2.0;
		g = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	}
	vec3 c = ph_srgb_to_linear(COLOR.rgb * tint_color) * COLOR.a * intensity * g;
	ALBEDO = ph_out(c * (1.0 - ph_fog(VERTEX)));
}
