// Lighthouse beam: additive soft wedge that fades with distance and toward its edges.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/pharos.gdshaderinc"

instance uniform float intensity = 1.0;

void fragment() {
	float along = UV.y; // 0 far end .. 1 at the lighthouse (QuadMesh UV.y grows downwards)
	float spread = mix(0.08, 1.0, 1.0 - along);
	float x = abs(UV.x - 0.5) * 2.0;
	float edge = smoothstep(spread, spread * 0.25, x);
	float fade = pow(along, 1.6) * smoothstep(1.0, 0.94, along);
	vec3 c = vec3(1.0, 0.86, 0.6) * edge * fade * 0.22 * intensity;
	ALBEDO = ph_out(c);
}
