// TOON style test: final grade over the whole frame (canvas layer).
//  - soft anime bloom built from the blurred mip chain of the screen copy (bright things bleed light);
//  - vibrance (more colour where there is little), warm highlights / cool shadows split toning;
//  - a light vignette.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float bloom = 0.35;
uniform float bloom_knee = 0.72;
uniform float sat = 1.06;
uniform float vignette = 0.22;
uniform vec3 hi_tint = vec3(1.02, 1.0, 0.97);
uniform vec3 lo_tint = vec3(0.97, 0.99, 1.05);
uniform float debug_mip = -1.0;
uniform vec2 leak_pos = vec2(-0.2, -0.2); // where the (off-screen) sun is, in screen uv
uniform vec3 leak_col = vec3(1.0, 0.85, 0.6);
uniform float leak_k = 0.0;
uniform float leak_r = 0.75;

vec3 bright(vec2 uv, float lod) {
	vec3 c = textureLod(screen_tex, uv, lod).rgb;
	float l = max(c.r, max(c.g, c.b));
	float k = smoothstep(bloom_knee - 0.12, 1.0, l);
	return c * k;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	if (debug_mip >= 0.0) {
		COLOR = vec4(textureLod(screen_tex, uv, debug_mip).rgb, 1.0);
	} else {
		vec3 b = bright(uv, 1.5) * 0.18 + bright(uv, 3.0) * 0.3 + bright(uv, 4.5) * 0.32 + bright(uv, 6.0) * 0.28;
		// screen blend keeps whites from clipping hard
		c = 1.0 - (1.0 - c) * (1.0 - b * bloom * 1.6);
		// warm light leak from the sun's side of the frame (anime key art)
		vec2 dl = (uv - leak_pos) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
		float leak = exp(-dot(dl, dl) / (leak_r * leak_r)) * leak_k;
		c = 1.0 - (1.0 - c) * (1.0 - leak_col * leak);
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		float s = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
		c = mix(vec3(l), c, sat + (1.0 - s) * (sat - 1.0) * 1.5);
		c *= mix(lo_tint, hi_tint, smoothstep(0.15, 0.85, l));
		vec2 q = uv - 0.5;
		float v = 1.0 - dot(q, q) * vignette * 2.2;
		c *= v;
		COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
	}
}
