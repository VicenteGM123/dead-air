// --- R3 WORLD3: los chorros de la fuente (tubos finos que caen en arco del cuenco a la pileta).
// UV.y va de 0 (donde sale el agua) a 1 (donde toca el agua de abajo); UV.x da la vuelta al tubo.
// Unas rayas claras bajan por el chorro (el agua que cae) y el borde del tubo es más transparente.
// Compatibility (WebGL 2): sin texturas de pantalla ni de profundidad.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform vec4 water : source_color = vec4(0.62, 0.84, 0.94, 1.0);
uniform vec4 foam : source_color = vec4(0.95, 0.99, 1.0, 1.0);
uniform float alpha = 0.72;
uniform float speed = 1.6;      // vueltas de UV por segundo (hacia abajo)
uniform float dashes = 5.0;     // rayas a lo largo del chorro

void fragment() {
	// las rayas bajan; cada franja del tubo va un poco desfasada (se ve como agua que corre, no como un tubo)
	float lane = floor(UV.x * 4.0);
	float s = fract(UV.y * dashes - TIME * speed + lane * 0.29);
	float dash = step(0.62, s) * (1.0 - step(0.86, s));
	// cerca de la caída se abre en espuma; arriba sale más lisa
	float tail = smoothstep(0.78, 1.0, UV.y);
	vec3 col = mix(water.rgb, foam.rgb, clamp(dash * 0.75 + tail * 0.45, 0.0, 1.0));
	// borde del tubo (de lado a la cámara) más transparente: el chorro parece redondo
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = col;
	ALPHA = alpha * mix(0.45, 1.0, smoothstep(0.1, 0.6, facing)) * (0.85 + dash * 0.15);
}
