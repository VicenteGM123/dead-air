shader_type canvas_item;
// Post-proceso estilo HD-2D: desenfoque "tilt-shift" arriba y abajo, viñeta y gradación de color suave.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float focus_center = 0.46;
uniform float focus_half = 0.22;
uniform float focus_falloff = 0.30;
uniform float max_lod = 2.6;
uniform float vignette_strength = 0.42;
uniform vec3 shadow_tint = vec3(0.92, 0.96, 1.08);
uniform vec3 highlight_tint = vec3(1.06, 1.0, 0.92);
uniform float grade_amount = 1.0;

const vec2 TAPS[8] = vec2[](
	vec2(0.0, 1.0), vec2(0.71, 0.71), vec2(1.0, 0.0), vec2(0.71, -0.71),
	vec2(0.0, -1.0), vec2(-0.71, -0.71), vec2(-1.0, 0.0), vec2(-0.71, 0.71)
);

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = abs(uv.y - focus_center);
	float b = smoothstep(focus_half, focus_half + focus_falloff, d);
	vec3 col;
	if (b < 0.01) {
		col = texture(screen_tex, uv).rgb;
	} else {
		float lod = b * max_lod;
		vec2 px = SCREEN_PIXEL_SIZE * (1.0 + b * 3.0);
		vec3 acc = textureLod(screen_tex, uv, lod).rgb * 2.0;
		for (int i = 0; i < 8; i++) {
			acc += textureLod(screen_tex, uv + TAPS[i] * px * 2.0, lod).rgb;
		}
		col = acc / 10.0;
	}
	// gradación: sombras levemente frías, luces cálidas
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 graded = col * mix(shadow_tint, highlight_tint, smoothstep(0.15, 0.85, l));
	col = mix(col, graded, grade_amount);
	// viñeta
	vec2 c = uv - vec2(0.5);
	c.x *= 1.25;
	float v = 1.0 - vignette_strength * smoothstep(0.35, 0.85, length(c));
	col *= v;
	COLOR = vec4(col, 1.0);
}
