// TOON style test: the anime sky as a function of direction, shared by the sky shader and the sea (which
// reflects it). Linear colours. Needs pharos.gdshaderinc first.
//  - smooth three-stop gradient (horizon glow -> band -> zenith);
//  - big cumulus banks standing on the horizon: unions of round puffs with flat bases, two cel tones (sunlit
//    cream / shaded lilac) and a silver lining on the side facing the sun;
//  - smaller fair-weather puffs higher up;
//  - a soft sun with a halo, a big moon with a glow, twinkling stars at night.

global uniform vec3 g_sky_top;
global uniform vec3 g_sky_horizon;
global uniform vec3 g_sun_dir;
global uniform vec3 g_sun_color;
global uniform vec3 g_moon_dir;
global uniform vec3 g_cloud_lit;
global uniform vec3 g_cloud_shade;
global uniform float g_cloud_cover;

float tsky_h1(float x) {
	return fract(sin(x * 127.1 + 11.3) * 43758.5453);
}

float tsky_smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// One cumulus bank; p = (azimuth offset from the bank centre, elevation), radians.
float tsky_bank(vec2 p, float seed, float w, float hgt, float base) {
	float d = 1e3;
	for (int k = 0; k < 7; k++) {
		float fk = float(k);
		float x = (fk / 6.0 * 2.0 - 1.0) * w * 0.82 + (tsky_h1(seed + fk * 3.7) - 0.5) * w * 0.12;
		float bulge = 1.0 - (x / w) * (x / w);
		float r = hgt * (0.32 + 0.5 * bulge) * (0.75 + 0.35 * tsky_h1(seed * 1.7 + fk));
		vec2 c = vec2(x, base + r * mix(0.55, 0.95, tsky_h1(seed * 2.3 + fk * 1.1)));
		d = tsky_smin(d, length(p - c) - r, hgt * 0.12);
	}
	// cauliflower top: a few smaller puffs riding on the crown
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float x = (fk - 1.0) * w * 0.33 + (tsky_h1(seed * 5.1 + fk) - 0.5) * w * 0.2;
		float r = hgt * mix(0.22, 0.34, tsky_h1(seed * 7.7 + fk));
		vec2 c = vec2(x, base + hgt * mix(0.75, 1.0, tsky_h1(seed * 3.3 + fk)) * (1.0 - (x / w) * (x / w) * 0.8));
		d = tsky_smin(d, length(p - c) - r, hgt * 0.08);
	}
	return max(d, base - p.y); // flat base
}

// Distance (radians) to the cumulus banks around the horizon, at azimuth az and elevation el.
float tsky_banks(float az, float el, float t) {
	const float CELLS = 9.0;
	float cw = TAU / CELLS;
	float u = (az + t * 0.0015) / cw;
	float ci = floor(u);
	float d = 1e3;
	for (int i = -1; i <= 1; i++) {
		float c = ci + float(i);
		float cm = mod(c, CELLS);
		float h = tsky_h1(cm * 3.1 + 1.0);
		if (h > 0.25 + 0.65 * g_cloud_cover) {
			continue;
		}
		float centre = (c + 0.5 + (tsky_h1(cm * 5.3) - 0.5) * 0.35) * cw;
		float w = cw * mix(0.32, 0.6, tsky_h1(cm * 7.9));
		float hgt = mix(0.07, 0.15, tsky_h1(cm * 2.2));
		float base = mix(-0.015, 0.02, tsky_h1(cm * 9.4));
		d = min(d, tsky_bank(vec2(u * cw - centre, el), cm * 13.0 + 1.0, w, hgt, base));
	}
	return d;
}

// Fair-weather puffs higher up, on a plane projection.
float tsky_puffs(vec3 d, float t) {
	vec2 q = d.xz / (d.y + 0.12) * 1.6 + vec2(t * 0.01, t * 0.004);
	vec2 g = floor(q);
	float dist = 1e3;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 id = g + vec2(float(i), float(j));
			float h = tsky_h1(id.x * 17.0 + id.y * 31.0);
			if (h > 0.45 * g_cloud_cover + 0.08) {
				continue;
			}
			vec2 c = id + 0.5 + (vec2(tsky_h1(id.x * 3.0 + id.y), tsky_h1(id.y * 5.0 - id.x)) - 0.5) * 0.5;
			float r = mix(0.12, 0.24, tsky_h1(h * 91.0));
			for (int k = 0; k < 4; k++) {
				float fk = float(k);
				vec2 o = vec2((fk - 1.5) * r * 0.75, (tsky_h1(h * 13.0 + fk) - 0.5) * r * 0.5);
				float rr = r * (0.55 + 0.45 * (1.0 - abs(fk - 1.5) / 1.5)) * mix(0.8, 1.1, tsky_h1(h * 7.0 + fk));
				dist = tsky_smin(dist, length((q - c - o) * vec2(1.0, 1.35)) - rr, 0.05);
			}
		}
	}
	return dist;
}

vec3 toon_sky(vec3 dir, float t) {
	vec3 d = normalize(dir);
	float el = asin(clamp(d.y, -1.0, 1.0));
	float az = atan(d.x, d.z);
	float h = max(d.y, 0.0);
	vec3 band = mix(g_sky_horizon, g_sky_top, 0.45) * vec3(1.02, 1.0, 1.05);
	vec3 col = mix(g_sky_horizon, band, smoothstep(0.0, 0.22, h));
	col = mix(col, g_sky_top, smoothstep(0.12, 0.85, h));
	col = mix(col, g_fog_color, smoothstep(0.03, -0.08, d.y));

	vec3 sd = normalize(g_sun_dir);
	float s = max(dot(d, sd), 0.0);
	float day = 1.0 - g_night;
	col += g_sun_color * (pow(s, 24.0) * 0.4 + pow(s, 5.0) * 0.12) * day;

	// --- clouds ---------------------------------------------------------------------------------------------
	float sun_az = atan(sd.x, sd.z);
	float daz = sun_az - az;
	daz = mod(daz + PI, TAU) - PI;
	vec2 l2 = normalize(vec2(clamp(daz, -1.0, 1.0), 0.55 + max(sd.y, 0.0)));
	if (g_night > 0.5) {
		l2 = vec2(0.3, 0.95);
	}
	float cb = tsky_banks(az, el, t);
	float cb_s = tsky_banks(az + l2.x * 0.055, el + l2.y * 0.05, t);
	float aa = 0.0035;
	float cloud = smoothstep(aa, -aa, cb);
	float lit = smoothstep(-0.02, -0.012, cb_s);
	vec3 c_lit = g_cloud_lit;
	vec3 c_sh = g_cloud_shade;
	vec3 ccol = mix(c_sh, c_lit, lit);
	// silver lining on the sun side, warm glow on clouds near the sun
	float edge = smoothstep(-0.006, -0.001, cb) * lit;
	ccol += g_sun_color * edge * 0.35 * day + g_sun_color * pow(s, 6.0) * 0.25 * day;
	ccol = mix(ccol, mix(g_sky_horizon, g_fog_color, 0.5), smoothstep(0.03, -0.01, el) * 0.8);

	float pf = tsky_puffs(d, t);
	float pf_s = tsky_puffs(normalize(d + vec3(sd.x, 0.0, sd.z) * 0.02 + vec3(0.0, 0.012, 0.0)), t);
	float puff = smoothstep(0.012, -0.012, pf) * smoothstep(0.08, 0.25, h);
	float plit = smoothstep(-0.05, 0.0, pf_s);
	vec3 pcol = mix(c_sh, c_lit, plit);
	pcol = mix(pcol, col, 0.15 + 0.45 * smoothstep(0.6, 0.15, h));

	col = mix(col, pcol, puff);
	col = mix(col, ccol, cloud);

	// --- moon and stars ------------------------------------------------------------------------------------------
	vec3 md = normalize(g_moon_dir);
	float m = max(dot(d, md), 0.0);
	float moon = smoothstep(0.9993, 0.99945, m);
	col = mix(col, vec3(0.96, 0.97, 1.0) * 1.3, moon * g_night * (1.0 - cloud));
	col += vec3(0.35, 0.5, 0.95) * (pow(m, 90.0) * 0.45 + pow(m, 10.0) * 0.08) * g_night;
	if (g_night > 0.01 && h > 0.0) {
		vec3 p = d * 150.0;
		vec3 cell = floor(p);
		float r = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		vec3 fp = fract(p) - 0.5;
		float star = step(0.982, r) * smoothstep(0.17, 0.0, length(fp));
		star *= 0.55 + 0.45 * sin(t * 1.7 + r * 60.0);
		vec3 sc = mix(vec3(0.85, 0.92, 1.0), vec3(1.0, 0.9, 0.75), fract(r * 37.0));
		col += sc * star * g_night * smoothstep(0.02, 0.3, h) * (1.0 - cloud) * 1.2;
	}
	return col;
}
