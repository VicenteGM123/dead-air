// --- R4 SCENES: velas flotantes (Academia) y farolillos de papel (Concurso). Todas van en un solo MultiMesh: una sola
// llamada de dibujo. Cada instancia sube y baja (o se balancea, colgada) con su propia fase (INSTANCE_ID) y su llama
// parpadea con los cuadros de una tira horizontal. Compatibility (WebGL 2): INSTANCE_ID y TIME, sin uniforms por
// instancia ni set_instance_shader_parameter.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_nearest;
uniform float frames = 3.0;        // cuadros de la tira (a lo ancho)
uniform float fps = 6.0;
uniform float bob = 0.07;          // sube y baja (m)
uniform float bob_speed = 0.8;
uniform float sway = 0.0;          // balanceo de lado (radianes), colgado del punto pivot_y
uniform float pivot_y = 0.0;       // y local del punto del que cuelga (la mitad del alto del quad = el borde de arriba)
uniform float variants = 1.0;      // filas de la tira (colores distintos): cada instancia usa una
uniform vec4 tint : source_color = vec4(1.0);

varying float v_frame;
varying float v_row;

void vertex() {
	float ph = float(INSTANCE_ID) * 2.399;               // ángulo áureo: fases bien repartidas
	if (sway > 0.0) {
		float a = sin(TIME * 1.3 + ph) * sway;
		vec2 p = VERTEX.xy - vec2(0.0, pivot_y);
		VERTEX.xy = vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a)) + vec2(0.0, pivot_y);
	}
	VERTEX.y += sin(TIME * bob_speed + ph) * bob;
	v_frame = floor(mod(TIME * fps * (0.8 + 0.4 * fract(ph)) + ph * 5.0, frames));
	v_row = mod(float(INSTANCE_ID), variants);
}

void fragment() {
	vec2 uv = vec2((UV.x + v_frame) / frames, (UV.y + v_row) / variants);
	vec4 c = texture(tex, uv) * tint;
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
}
