// --- BOOT: el telón del cielo de los dos escenarios (antes era un Shader hecho por código en set_kit.gd, uno por
// escenario). Un solo archivo = un solo Shader compartido (cada telón con sus valores): en la web cada Shader se
// compila aparte, así el de la tienda ya está listo cuando se calentó la calle. El código es el mismo de antes.
// Día ámbar / noche violeta con estrellas que titilan; night 0..1 (SetKit.set_night).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float night = 0.0;
uniform vec3 day_top = vec3(0.93, 0.62, 0.40);
uniform vec3 day_hor = vec3(1.0, 0.87, 0.64);
uniform vec3 night_top = vec3(0.045, 0.04, 0.13);
uniform vec3 night_hor = vec3(0.26, 0.15, 0.30);
uniform float bright = 1.2;
uniform float horizon = 2.0;
uniform vec3 dune_col = vec3(0.86, 0.6, 0.38);
uniform vec3 dune_night = vec3(0.12, 0.09, 0.16);
uniform vec2 star_grid = vec2(420.0, 120.0);   // celdas de estrellas (el telón grande de la calle: más celdas)
uniform float star_size = 0.16;                 // radio de la estrella dentro de su celda (puntitos, no cuadros)
void fragment() {
	vec2 uv = UV;
	vec3 dayc = mix(day_hor, day_top, smoothstep(0.82, 0.08, uv.y));
	vec3 nightc = mix(night_hor, night_top, smoothstep(0.95, 0.15, uv.y));
	vec3 col = mix(dayc * bright, nightc, night);
	float hz = horizon + 0.010 * sin(uv.x * 37.0) + 0.006 * sin(uv.x * 91.0 + 1.3);
	float dune = step(hz, uv.y);
	col = mix(col, mix(dune_col, dune_night, night), dune);
	// estrellas: un punto chico (y no siempre en el centro) en algunas celdas; unas pocas más grandes y más blancas
	vec2 cell = uv * star_grid;
	vec2 g = floor(cell);
	float h = fract(sin(dot(g, vec2(12.9898, 78.233))) * 43758.5453);
	float h2 = fract(sin(dot(g, vec2(39.3468, 11.135))) * 24634.6345);
	vec2 c = vec2(0.25 + 0.5 * h2, 0.25 + 0.5 * fract(h * 7.31));
	float big = step(0.996, h);
	float r = star_size * (1.0 + 0.9 * big);
	float d = length(fract(cell) - c);
	float dot_ = 1.0 - smoothstep(r * 0.55, r, d);
	float star = step(0.978, h) * dot_ * night * smoothstep(0.92, 0.3, uv.y) * (1.0 - dune);
	float tw = 0.6 + 0.4 * sin(TIME * (0.8 + h * 2.5) + h * 40.0);
	col += mix(vec3(1.0, 0.86, 0.7), vec3(1.0, 0.97, 0.92), big) * star * tw * (1.2 + big);
	ALBEDO = col;
}
