shader_type sky;

#include "res://shaders/pharos.gdshaderinc"

global uniform vec3 g_sky_top;
global uniform vec3 g_sky_horizon;
global uniform vec3 g_sun_dir;
global uniform vec3 g_sun_color;
global uniform vec3 g_moon_dir;

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(g_sky_horizon, g_sky_top, pow(smoothstep(0.0, 1.0, max(h, 0.0)), 0.55));
	// Thin warm band right above the horizon.
	col += g_sun_color * 0.08 * smoothstep(0.25, 0.0, abs(h)) * (1.0 - g_night);
	// Below the horizon the sky melts into the sea haze.
	col = mix(col, g_fog_color, smoothstep(0.02, -0.10, h));

	vec3 sd = normalize(g_sun_dir);
	float s = max(dot(d, sd), 0.0);
	col += g_sun_color * (smoothstep(0.9988, 0.9993, s) * 3.0 + pow(s, 28.0) * 0.30 + pow(s, 4.0) * 0.06) * (1.0 - g_night);

	vec3 md = normalize(g_moon_dir);
	float m = max(dot(d, md), 0.0);
	col += vec3(0.92, 0.95, 1.0) * smoothstep(0.99935, 0.9996, m) * 1.4 * g_night;
	col += vec3(0.32, 0.42, 0.75) * (pow(m, 60.0) * 0.30 + pow(m, 8.0) * 0.05) * g_night;

	if (g_night > 0.01 && h > 0.0) {
		vec3 p = d * 140.0;
		vec3 cell = floor(p);
		float r = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		vec3 fp = fract(p) - 0.5;
		float star = step(0.986, r) * smoothstep(0.16, 0.0, length(fp));
		star *= 0.55 + 0.45 * sin(g_time * 1.7 + r * 60.0);
		col += vec3(0.95, 0.97, 1.0) * star * g_night * smoothstep(0.02, 0.35, h) * 0.9;
	}
	COLOR = ph_out(col);
}
