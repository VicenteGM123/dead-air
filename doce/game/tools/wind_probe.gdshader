// Wind probe: every pixel evaluates one of the wind functions (shaders/wind.gdshaderinc) at the world point its UV
// maps to and writes the value as a 16-bit number in R (high byte) and G (low byte): tools/wind_probe.gd renders one
// mode per frame, analysis/probe_compare.py compares the image with the Python port of the same maths (windsim_*.py).
shader_type canvas_item;

#include "res://shaders/pharos.gdshaderinc"
#include "res://shaders/wind.gdshaderinc"

uniform vec4 rect = vec4(-80.0, -45.0, 160.0, 90.0);   // x, z, width, depth (m) of the world rectangle the image maps to
uniform int mode = 0;

vec2 enc16(float v01) {
	float x = floor(clamp(v01, 0.0, 1.0) * 65535.0 + 0.5);
	float hi = floor(x / 256.0);
	return vec2(hi, x - hi * 256.0) / 255.0;
}

void fragment() {
	vec2 p = rect.xy + UV * rect.zw;
	float v = 0.0;
	if (mode == 0) {
		v = wind_gust_k(p, 1.0, 1.0);                 // the meadow's gust wave (0..1)
	} else if (mode == 1) {
		v = wind_gust_k(p, 1.45, 1.0);                // the wheat's (bigger waves)
#ifdef WIND_NEW
	} else if (mode == 2) {
		v = wind_ripple(p) + 0.5;                     // the ripple (-0.5..0.5 -> 0..1)
	} else if (mode == 3) {
		v = wind_flutter(p, 0.37, wind_gust(p)).x * 4.0 + 0.5;   // the tip sway (x component)
	} else if (mode == 4) {
		v = wind_foliage(vec3(p.x, 0.0, p.y), vec3(1.0), 5.0, 0.063).x * 0.5 + 0.5;   // a 5 m tree's crown offset (x)
#endif
	}
	COLOR = vec4(enc16(v), 0.0, 1.0);
}
