// TOON style test: anime / Wind Waker sea.
// Depth still comes from the baked island texture (g_water_tex, R = 0 at the shoreline .. 1 in deep water).
//  - colour in crisp, slightly wobbly bands (sand-bright shallows -> turquoise -> teal -> deep ultramarine);
//  - a solid white shore line and foam rings that roll in towards the beach, broken into dashes;
//  - white crescent wave marks scattered over open water, each one swelling and fading on its own clock;
//  - cel-shaded swell (light / shade tone on the wave faces), posterised sky reflection at grazing angles;
//  - star sparkles that twinkle over the lit water, and hard-edged sun glints.
// At night the foam glows a soft cyan and the sparkles take the moonlight.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://shaders/pharos.gdshaderinc"
#include "res://shaders/toon_sky.gdshaderinc"

global uniform sampler2D g_water_tex : filter_linear, repeat_disable;
global uniform vec4 g_water_rect;
global uniform vec3 g_water_shallow;
global uniform vec3 g_water_deep;
global uniform vec3 g_foam;

uniform float wave_amp = 0.18;
uniform float glint = 1.0;

varying vec3 v_wpos;
varying vec3 v_base;
varying float v_fogf;
varying float v_depth;
varying float v_foam;

// DOCE: bilinear filtering done by hand (four texel-centre fetches): the global sampler is read with nearest
// filtering in the Compatibility renderer, which turned the shore foam and colour bands into staircases.
float depth_at(vec2 xz) {
	vec2 uv = (xz - g_water_rect.xy) / g_water_rect.zw;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return 1.0;
	}
	vec2 size = vec2(textureSize(g_water_tex, 0));
	vec2 p = uv * size - 0.5;
	vec2 f = fract(p);
	vec2 d = 1.0 / size;
	vec2 c0 = (floor(p) + 0.5) * d;
	float a = texture(g_water_tex, c0).r;
	float b = texture(g_water_tex, c0 + vec2(d.x, 0.0)).r;
	float c = texture(g_water_tex, c0 + vec2(0.0, d.y)).r;
	float e = texture(g_water_tex, c0 + d).r;
	return mix(mix(a, b, f.x), mix(c, e, f.x), f.y);
}

float waves(vec2 p, float t) {
	return sin(p.x * 0.33 + t * 1.05) * 0.45
		+ sin(p.y * 0.41 - t * 0.85 + p.x * 0.12) * 0.35
		+ sin((p.x + p.y) * 0.78 + t * 1.65) * 0.14
		+ sin((p.x - p.y) * 1.30 - t * 2.10) * 0.06;
}

vec2 waves_grad(vec2 p, float t) {
	float a = cos(p.x * 0.33 + t * 1.05) * 0.45 * 0.33;
	float b = cos(p.y * 0.41 - t * 0.85 + p.x * 0.12) * 0.35;
	float c = cos((p.x + p.y) * 0.78 + t * 1.65) * 0.14 * 0.78;
	float d = cos((p.x - p.y) * 1.30 - t * 2.10) * 0.06 * 1.30;
	return vec2(a + b * 0.12 + c + d, b * 0.41 + c - d);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
vec2 hash22(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// White crescent wave marks: one per cell, each with its own position, bend, size and clock.
float crest_marks(vec2 p, float t, float cell, float thick) {
	vec2 g = floor(p / cell);
	vec2 f = p / cell - g;
	float m = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 o = vec2(float(i), float(j));
			vec2 id = g + o;
			vec2 h = hash22(id);
			if (h.x < 0.25) {
				continue; // empty cell
			}
			float ph = fract(t * (0.06 + 0.05 * h.y) + h.x * 7.0);
			float life = smoothstep(0.0, 0.25, ph) * smoothstep(1.0, 0.55, ph);
			vec2 c = o + 0.5 + (hash22(id + 17.0) - 0.5) * 0.7 + vec2(0.0, ph * 0.35);
			vec2 q = f - c;
			float ang = (h.y - 0.5) * 0.7;
			q = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * q;
			float len = mix(0.18, 0.34, hash21(id + 5.0)) * (0.55 + 0.45 * life);
			float bend = mix(1.6, 3.2, h.x);
			float y = q.y + bend * q.x * q.x;
			float along = clamp(abs(q.x) / len, 0.0, 1.0);
			float w = thick * (1.0 - along * along) * life;
			float d = abs(y) - w;
			m = max(m, step(abs(q.x), len) * smoothstep(0.012, 0.0, d));
		}
	}
	return m;
}

// Four-point star (screen space), centred at p, radius r (pixels).
float star_shape(vec2 p, float r) {
	vec2 a = abs(p) / r;
	float cross = max(smoothstep(0.16, 0.0, a.y) * (1.0 - a.x), smoothstep(0.16, 0.0, a.x) * (1.0 - a.y));
	float core = smoothstep(0.32, 0.0, length(a));
	return clamp(max(cross, core), 0.0, 1.0) * step(max(a.x, a.y), 1.0);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dep = depth_at(wp.xz);
	float amp = wave_amp * mix(0.35, 1.0, smoothstep(0.0, 0.4, dep));
	VERTEX.y += waves(wp.xz, g_time) * amp;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_depth = dep;
}

void fragment() {
	float t = g_time;
	float dep = depth_at(v_wpos.xz);
	// DOCE: the swell normal per fragment (not interpolated from the 2 m vertex grid), so the cel tone bands stay
	// smooth at third-person distance.
	vec2 fgr = waves_grad(v_wpos.xz, t) * wave_amp * mix(0.35, 1.0, smoothstep(0.0, 0.4, dep));
	vec3 wn = normalize(vec3(-fgr.x, 1.0, -fgr.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float dist = length(VERTEX);
	float far_k = smoothstep(150.0, 60.0, dist); // fine detail fades with distance
	float nz = ph_noise(v_wpos.xz * 0.35 + vec2(t * 0.05, -t * 0.03));
	float nz2 = ph_noise(v_wpos.xz * 1.3 - vec2(t * 0.12, 0.0));
	float dw = dep + ((nz - 0.5) * 0.045 + (nz2 - 0.5) * 0.015) * mix(1.0, 0.35, smoothstep(0.2, 0.6, dep));

	// --- colour bands ---------------------------------------------------------------------------------------
	vec3 c_sand = mix(g_water_shallow, vec3(1.0), 0.42) * mix(vec3(1.06, 1.04, 0.92), vec3(1.0), g_night);
	vec3 c_shallow = g_water_shallow;
	vec3 c_mid = mix(g_water_shallow, g_water_deep, 0.48);
	vec3 c_deep = g_water_deep;
	float e = 0.006;
	vec3 col = c_sand;
	col = mix(col, c_shallow, smoothstep(0.075 - e, 0.075 + e, dw));
	col = mix(col, c_mid, smoothstep(0.26 - e, 0.26 + e, dw));
	col = mix(col, c_deep, smoothstep(0.55 - e * 2.0, 0.55 + e * 2.0, dw));
	// a thin bright contour where the shelf drops off
	float contour = smoothstep(0.012, 0.0, abs(dw - 0.26)) * 0.5 + smoothstep(0.01, 0.0, abs(dw - 0.55)) * 0.25;
	col = mix(col, mix(c_shallow, vec3(1.0), 0.5), contour * smoothstep(0.0, 1.0, far_k + 0.3));
	// far water drifts toward a deeper, bluer tone before the haze
	col = mix(col, c_deep * vec3(0.92, 0.96, 1.08), smoothstep(90.0, 220.0, dist) * 0.35 * step(0.55, dw));

	// --- cel-shaded swell -----------------------------------------------------------------------------------
	vec3 L = normalize(mix(g_sun_dir, vec3(0.33, 0.72, 0.61), step(0.5, g_night)));
	float tone = smoothstep(0.06, 0.1, wn.x * L.x + wn.z * L.z);
	col *= mix(0.9, 1.07, tone);

	// --- sky reflection, posterised --------------------------------------------------------------------------
	vec3 V = normalize(-VERTEX);
	vec3 vw = normalize(v_wpos - CAMERA_POSITION_WORLD);
	// mirror-like reflection of the toon sky (clouds included), broken into horizontal ripple streaks
	vec3 rn = normalize(mix(wn, vec3(0.0, 1.0, 0.0), 0.8));
	vec3 rd = reflect(vw, rn);
	rd.y = abs(rd.y);
	float fres = pow(1.0 - clamp(-vw.y, 0.0, 1.0), 5.0);
	vec3 cam_r = INV_VIEW_MATRIX[0].xyz;
	vec2 cam_f = normalize(-INV_VIEW_MATRIX[2].xz + vec2(1e-4));
	vec2 sq = vec2(dot(v_wpos, cam_r) * 0.045, dot(v_wpos.xz, cam_f) * 0.42);
	float streak = smoothstep(0.32, 0.5, ph_noise(sq + vec2(t * 0.05, -t * 0.25)) * 0.75 + ph_noise(sq * 2.3 + 9.0) * 0.25 + (tone - 0.5) * 0.25);
	float fstep = smoothstep(0.3, 0.36, fres) * 0.45 + smoothstep(0.6, 0.66, fres) * 0.35;
	fstep *= mix(0.45, 1.0, streak);
	// DOCE: no big reflection streaks right under the third-person camera.
	fstep *= smoothstep(3.0, 18.0, dist);
	vec3 refl = toon_sky(rd, t);
	col = mix(col, refl, fstep);

	// --- foam -----------------------------------------------------------------------------------------------
	float zone = smoothstep(0.30, 0.05, dep);
	// rings rolling in toward the beach (two families), broken into dashes
	float r1 = fract(dw * 9.0 + t * 0.32);
	float ring = smoothstep(0.86, 0.885, r1) * smoothstep(0.985, 0.96, r1);
	float dash = smoothstep(0.38, 0.45, ph_noise(v_wpos.xz * 0.9 + vec2(t * 0.15, 0.0)));
	float foam = ring * dash * zone;
	float r2 = fract(dw * 15.0 + t * 0.55 + 0.37);
	foam = max(foam, smoothstep(0.9, 0.92, r2) * smoothstep(0.99, 0.97, r2) * smoothstep(0.12, 0.03, dep) * smoothstep(0.3, 0.4, nz2));
	// solid shore line with a wobbly edge, and a second thin line just outside it
	float shore = smoothstep(0.034, 0.026, dep + (nz2 - 0.5) * 0.018 + sin(t * 1.3 + nz * 6.0) * 0.004);
	float shore2 = smoothstep(0.006, 0.0, abs(dep - 0.05 - sin(t * 0.9 + nz * 5.0) * 0.008)) * 0.9;
	foam = max(foam, max(shore, shore2));
	// open-water crest marks
	float marks = crest_marks(v_wpos.xz * vec2(1.0, 1.25) + vec2(t * 0.35, t * 0.18), t, 9.0, 0.035) * smoothstep(0.35, 0.6, dep);
	marks *= smoothstep(170.0, 70.0, dist);
	float marks2 = crest_marks(v_wpos.xz * vec2(1.3, 1.6) + vec2(-t * 0.25, t * 0.3) + 40.0, t * 1.3, 4.5, 0.03) * smoothstep(0.3, 0.55, dep);
	marks2 *= smoothstep(80.0, 30.0, dist);
	foam = max(foam, marks * 0.95);
	vec3 foam_col = g_foam;
	col = mix(col, mix(col, vec3(1.0), 0.35), marks2 * 0.8);
	col = mix(col, foam_col, clamp(foam, 0.0, 1.0));

	// --- sparkles (screen-space stars over lit water) ------------------------------------------------------------
	vec2 sp = FRAGCOORD.xy;
	float cell = 26.0 * VIEWPORT_SIZE.y / 720.0;
	vec2 cid = floor(sp / cell);
	vec2 cf = sp - (cid + 0.5) * cell;
	float sparkle = 0.0;
	{
		vec2 h = hash22(cid + floor(t * 0.7) * 0.37);
		float tw = fract(t * 0.7);
		vec2 off = (h - 0.5) * cell * 0.6;
		float size = mix(3.0, 6.5, hash21(cid * 1.7 + 3.0)) * VIEWPORT_SIZE.y / 720.0;
		float alive = step(0.9, hash21(cid + floor(t * 0.7) * 1.31)) * sin(tw * PI);
		vec3 H = normalize(L + V);
		float lobe = pow(max(dot(wn, H), 0.0), 18.0) * 3.0 + 0.25;
		sparkle = star_shape(cf - off, size) * alive * clamp(lobe, 0.0, 1.0) * step(0.4, dep) * (1.0 - foam);
		sparkle *= smoothstep(220.0, 60.0, dist);
	}

	float f = ph_fog(VERTEX);
	vec3 emit_extra = vec3(0.0);
	// night: glowing foam, moonlit sparkles
	emit_extra += foam_col * clamp(foam, 0.0, 1.0) * 0.35 * g_night;
	vec3 spark_col = mix(vec3(1.0, 0.97, 0.88), vec3(0.75, 0.92, 1.0), g_night);
	emit_extra += spark_col * sparkle * mix(1.6, 1.3, g_night);

	vec3 base = col + emit_extra;
	ALBEDO = ph_out(col);
	EMISSION = ph_out(mix(base, g_fog_color, f));
	v_base = ph_godot_in(EMISSION);
	v_fogf = f;
	v_foam = clamp(foam, 0.0, 1.0);
}

void light() {
	// hard-edged glints only (the colour is all in the base pass)
	vec3 H = normalize(LIGHT + VIEW);
	float s = pow(max(dot(NORMAL, H), 0.0), 140.0);
	float g = smoothstep(0.45, 0.55, s) * 1.6 * glint * (1.0 - v_foam);
	vec3 lit = LIGHT_COLOR / PI * g * ATTENUATION;
	SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);
}
