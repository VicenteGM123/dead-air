shader_type canvas_item;
// Post-proceso estilo HD-2D: desenfoque "tilt-shift" arriba y abajo, viñeta y gradación de color suave.
// --- SS SEED: copiado de Midnight Cauldron (shaders/hd2d_post.gdshader). Mismo efecto, pero las BANDAS son
// chicas por defecto: el cliente encontró demasiado grandes las de Midnight Cauldron ("no el blur, sino la
// sección"). Antes: foco 0.46 ± 0.22 con 0.30 de transición (el desenfoque empezaba al 24 % desde arriba y al 32 %
// desde abajo). Ahora: foco 0.50 ± 0.35 con 0.13 de transición: nítido entre el 15 % y el 85 % del alto; el
// desenfoque (de la misma fuerza, max_lod) solo llega al borde de arriba y al de abajo. Cada escena puede
// cambiarlo con set_shader_parameter (ver main.gd, _setup_post).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float focus_center = 0.5;
uniform float focus_half = 0.35;
uniform float focus_falloff = 0.13;
uniform float max_lod = 2.6;
uniform float vignette_strength = 0.32;
uniform vec3 shadow_tint = vec3(0.94, 0.96, 1.06);
uniform vec3 highlight_tint = vec3(1.07, 1.0, 0.9);
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
	// gradación: sombras levemente frías, luces cálidas (sol del desierto)
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
