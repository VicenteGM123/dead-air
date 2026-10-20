// --- R4 SCENES: rayo de luz falso (vidrieras de la Academia, faroles): una lámina aditiva que no escribe profundidad.
// UV.y = 0 donde nace la luz (la ventana) y 1 donde muere (el suelo); UV.x va de un borde al otro. Unas franjas suaves se
// mueven despacio a lo ancho (polvo en el aire). Funciona igual en Forward+ y en Compatibility (WebGL 2): no usa niebla
// volumétrica ni texturas de pantalla o de profundidad.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.92, 0.75, 1.0);
uniform float intensity = 0.22;
uniform float streaks = 3.0;
uniform float speed = 0.05;
uniform float head = 0.06;         // largo del fundido donde nace
uniform float tail = 0.45;         // desde dónde empieza a apagarse hacia el final

void fragment() {
	float along = smoothstep(0.0, head, UV.y) * (1.0 - smoothstep(tail, 1.0, UV.y));
	float across = smoothstep(0.0, 0.3, UV.x) * (1.0 - smoothstep(0.7, 1.0, UV.x));
	float n = 0.62 + 0.38 * sin(UV.x * streaks * 6.2831 + TIME * speed * 6.2831 + sin(UV.x * 17.0 + TIME * 0.3) * 1.2);
	float breathe = 0.88 + 0.12 * sin(TIME * 0.45 + UV.x * 2.0);
	ALBEDO = color.rgb * intensity * along * across * n * breathe;
}
