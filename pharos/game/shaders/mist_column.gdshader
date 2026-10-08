// Violet column of mist over a landing beach (additive, soft, slowly churning).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform float intensity = 1.0;

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float h = 1.0 - UV.y; // 0 at the bottom, 1 at the top
	float n = ph_noise(vec2(UV.x * 3.0, h * 2.5 - g_time * 0.35)) * 0.6 + ph_noise(vec2(UV.x * 7.0 + 3.0, h * 5.0 - g_time * 0.8)) * 0.4;
	float edge = smoothstep(1.0, 0.15, x + (n - 0.5) * 0.5);
	float fade = smoothstep(0.0, 0.08, h) * pow(1.0 - h, 1.4);
	vec3 c = mix(vec3(0.45, 0.32, 0.95), vec3(0.65, 0.95, 1.0), smoothstep(0.55, 0.95, n)) * edge * fade * (0.35 + 0.4 * n) * intensity;
	ALBEDO = ph_out(c * (1.0 - ph_fog(VERTEX) * 0.6));
}
