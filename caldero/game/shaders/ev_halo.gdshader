// --- R4 SCENES: el halo suave de las velas flotantes y de los farolillos (aditivo, MultiMesh con las mismas
// posiciones y la misma fase que ev_floater.gdshader: el halo sube y baja con su vela). Compatibility (WebGL 2).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_linear;
uniform vec4 color : source_color = vec4(1.0, 0.7, 0.35, 1.0);
uniform float intensity = 0.35;
uniform float bob = 0.07;
uniform float bob_speed = 0.8;

varying float v_flick;

void vertex() {
	float ph = float(INSTANCE_ID) * 2.399;
	VERTEX.y += sin(TIME * bob_speed + ph) * bob;
	v_flick = 0.82 + 0.18 * sin(TIME * 9.0 + ph * 3.0) * sin(TIME * 3.7 + ph);
}

void fragment() {
	float a = texture(tex, UV).a;
	ALBEDO = color.rgb * intensity * a * a * v_flick;
}
