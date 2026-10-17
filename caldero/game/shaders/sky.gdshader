shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Cielo pintado que se ve por la ventana y la puerta: degradado, estrellas, luna y colinas en pixel art.

uniform vec3 top_color : source_color = vec3(0.35, 0.55, 0.9);
uniform vec3 bottom_color : source_color = vec3(1.0, 0.8, 0.55);
uniform float star_amount = 0.0;
uniform float moon_amount = 0.0;
uniform vec2 moon_pos = vec2(0.22, 0.22);
uniform sampler2D hills : filter_nearest, source_color, repeat_enable;
uniform vec3 hills_tint : source_color = vec3(1.0);
uniform float hills_height = 0.45;
uniform float brightness = 1.0;
uniform float hills_repeat = 2.0;     // veces que se repiten las colinas a lo ancho (WORLD: el cielo de la tienda es más ancho)
uniform float aspect = 2.142857;       // ancho / alto del cuadro del cielo (para que la luna sea redonda)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec3 sky = mix(top_color, bottom_color, smoothstep(0.0, 0.8, uv.y));
	// estrellas pixeladas
	vec2 g = floor(uv * vec2(300.0, 140.0));
	float h = hash(g);
	float tw = 0.55 + 0.45 * sin(TIME * 1.7 + h * 50.0);
	float star = step(0.986, h) * star_amount * tw * (1.0 - smoothstep(0.25, 0.6, uv.y));
	sky += vec3(star) * vec3(1.0, 0.95, 0.85) * 1.6;
	// luna
	vec2 mp = (uv - moon_pos) * vec2(aspect, 1.0);
	float md = length(mp);
	float moon = (1.0 - step(0.035, md)) * moon_amount;
	float halo = smoothstep(0.16, 0.0, md) * 0.35 * moon_amount;
	sky = mix(sky, vec3(1.0, 0.97, 0.88) * 2.2, moon);
	sky += vec3(0.7, 0.8, 1.0) * halo;
	// colinas
	float hy = (uv.y - (1.0 - hills_height)) / hills_height;
	if (hy > 0.0) {
		vec4 hc = texture(hills, vec2(uv.x * hills_repeat, hy));
		sky = mix(sky, hc.rgb * hills_tint, hc.a);
	}
	ALBEDO = sky * brightness;
}
