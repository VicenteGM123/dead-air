// DEAD AIR shadow caster pass for transparent toon materials: three renders every castShadow mesh into the shadow
// map whatever its material's transparency (glass casts a shadow), Godot's transparent pass never does. materials.gd
// chains this opaque pass (next_pass) under transparent toon materials: it discards every pixel except in the
// directional shadow pass (orthographic projection), so only the shadow is drawn.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, fog_disabled;

void fragment() {
	if (PROJECTION_MATRIX[3][3] < 0.5) discard;
	ALBEDO = vec3(0.0);
}
