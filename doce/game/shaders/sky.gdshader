// TOON style test sky: see toon_sky.gdshaderinc (shared with the sea, which reflects it).
shader_type sky;

#include "res://shaders/pharos.gdshaderinc"
#include "res://shaders/toon_sky.gdshaderinc"

void sky() {
	vec3 col = toon_sky(EYEDIR, g_time);
	// the sun disc itself (only in the sky, not in reflections)
	vec3 sd = normalize(g_sun_dir);
	float s = max(dot(normalize(EYEDIR), sd), 0.0);
	col += g_sun_color * smoothstep(0.9986, 0.9991, s) * 2.5 * (1.0 - g_night);
	COLOR = ph_out(col);
}
