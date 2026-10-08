// Soft volumetric light cone (lighthouse beam). The mesh is a double-sided cone along +Z; brightness falls
// off with distance and towards the silhouette, so it reads as a hazy shaft of light rather than a surface.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform float beam_length = 60.0;
uniform vec3 beam_color : source_color = vec3(1.0, 0.86, 0.6);
instance uniform float intensity = 1.0;
varying float v_z;

void vertex() {
	v_z = VERTEX.z / beam_length;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 3.0);
	float fade = pow(clamp(1.0 - v_z, 0.0, 1.0), 1.5) * smoothstep(0.0, 0.04, v_z);
	float shimmer = 0.85 + 0.15 * ph_noise(vec2(v_z * 14.0 - g_time * 0.6, 3.0));
	vec3 c = ph_srgb_to_linear(beam_color) * core * fade * shimmer * 0.12 * intensity;
	ALBEDO = ph_out(c);
}
