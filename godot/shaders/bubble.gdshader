// DEAD AIR power-up drop bubble (port of props/sponsors.js bubbleMat: additive fresnel shell with scanlines and a
// rolling band). Transparent, additive, no depth write, unlit, fog as three's ShaderMaterial (fog: false).
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back, depth_draw_never, blend_add;
#include "res://shaders/da_common.gdshaderinc"

uniform vec3 uColor : source_color = vec3(1.0);
uniform float uIntensity = 1.1;
varying vec3 vP;

void vertex() {
	vP = VERTEX;
}

void fragment() {
	float f = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(f, 3.2);
	float scan = smoothstep(0.55, 1.0, 0.5 + 0.5 * sin(vP.y * 160.0 - uTime * 5.0));
	float roll = fract(vP.y * 1.3 - uTime * 0.45);
	float band = smoothstep(0.0, 0.05, roll) * (1.0 - smoothstep(0.05, 0.18, roll));
	float a = edge * 1.1 + scan * (0.018 + 0.25 * edge) + band * (0.035 + 0.3 * edge);
	ALBEDO = daOut(daIn(uColor) * a * uIntensity);
	ALPHA = 1.0;
}
