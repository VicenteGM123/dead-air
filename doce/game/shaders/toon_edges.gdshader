// TOON style test: ink outlines and an anime rim light, from the depth buffer.
// A full-screen quad parented to the camera, drawn after the opaque pass (transparent pass, high priority):
//  - outline: the second difference of 1/z (planes are linear in 1/z, so grazing planes such as the sea give
//    nothing) marks silhouettes on the nearer side; the line colour is a dark, saturated version of the colour
//    under it (coloured line art, not black);
//  - rim light: a pixel whose neighbour a few pixels towards the sun (projected on screen) is much farther away
//    sits on a silhouette facing the light, and gets a thin bright rim.
// Output is premultiplied: rgb = line colour * line + rim, a = line.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

uniform float line_px = 1.4;
uniform float line_strength = 1.0;
uniform vec3 line_tint : source_color = vec3(0.17, 0.14, 0.28);
uniform float line_lo = 0.010;
uniform float line_hi = 0.028;
uniform float line_far = 170.0;
uniform vec3 rim_color : source_color = vec3(1.0, 0.9, 0.7);
uniform float rim_strength = 0.6;
uniform float rim_px = 3.0;
uniform vec3 light_dir = vec3(0.4, 0.7, 0.3); // world space, towards the light
uniform float debug = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

float raw_depth(vec2 uv) {
	return texture(depth_tex, uv).r;
}

vec3 view_pos(vec2 uv, float d, mat4 inv_proj) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

float vz(vec2 uv, mat4 inv_proj) {
	return -view_pos(uv, raw_depth(uv), inv_proj).z;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float k = VIEWPORT_SIZE.y / 720.0;
	mat4 ip = INV_PROJECTION_MATRIX;
	float dc = raw_depth(uv);
	vec3 pc = view_pos(uv, dc, ip);
	float zc = -pc.z;
	float far_sky = step(0.99999, dc);

	// --- outline -------------------------------------------------------------------------------------------
	float w = line_px * k;
	float rc = 1.0 / zc;
	float rl = 1.0 / vz(uv + vec2(-w, 0.0) * px, ip);
	float rr = 1.0 / vz(uv + vec2(w, 0.0) * px, ip);
	float ru = 1.0 / vz(uv + vec2(0.0, -w) * px, ip);
	float rd = 1.0 / vz(uv + vec2(0.0, w) * px, ip);
	float ra = 1.0 / vz(uv + vec2(-w, -w) * px, ip);
	float rb = 1.0 / vz(uv + vec2(w, w) * px, ip);
	float rc2 = 1.0 / vz(uv + vec2(-w, w) * px, ip);
	float rd2 = 1.0 / vz(uv + vec2(w, -w) * px, ip);
	// nearer than the average of opposite neighbours = this pixel is the near side of a depth edge
	float e = 0.0;
	e = max(e, rc - (rl + rr) * 0.5);
	e = max(e, rc - (ru + rd) * 0.5);
	e = max(e, (rc - (ra + rb) * 0.5) * 0.85);
	e = max(e, (rc - (rc2 + rd2) * 0.5) * 0.85);
	e /= rc;
	float line = smoothstep(line_lo, line_hi, e);
	line *= 1.0 - smoothstep(line_far * 0.55, line_far, zc);
	line *= (1.0 - far_sky) * line_strength;

	vec3 sc = texture(screen_tex, uv).rgb;
	// coloured line: a darker, richer version of what is under it, pulled towards the mood's ink colour
	vec3 ink = mix(sc * sc * 0.55, line_tint, 0.55);

	// --- rim light ------------------------------------------------------------------------------------------
	vec3 lv = (VIEW_MATRIX * vec4(normalize(light_dir), 0.0)).xyz;
	vec4 c0 = PROJECTION_MATRIX * vec4(pc, 1.0);
	vec4 c1 = PROJECTION_MATRIX * vec4(pc + lv * 0.05 * zc, 1.0);
	vec2 sdir = (c1.xy / c1.w - c0.xy / c0.w);
	float sl = length(sdir);
	float rim = 0.0;
	if (sl > 1e-6 && far_sky < 0.5) {
		sdir = sdir / sl * 0.5; // NDC -> uv scale
		float rw = rim_px * k;
		float z1 = vz(uv + sdir * rw * px * 2.0, ip);
		float z2 = vz(uv + sdir * rw * px * 1.0, ip);
		float g = max((z1 - zc) / zc, (z2 - zc) / zc);
		rim = smoothstep(0.02, 0.06, g);
		rim *= 1.0 - smoothstep(line_far * 0.5, line_far, zc);
	}
	vec3 rim_add = rim_color * rim * rim_strength * (1.0 - line);

	if (debug > 0.5) {
		ALBEDO = vec3(line, rim, 0.0);
		ALPHA = 1.0;
	} else {
		ALBEDO = ink * line + rim_add;
		ALPHA = line;
	}
}
