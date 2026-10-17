// A flat toon dust puff (Fx "dust" pool: the slam's dust ring and cloud), Wind Waker style: a camera-facing disc with
// a lobed, crisp cloud edge and two flat tones, the lit one up and to the left, a cooler shade down and to the right;
// no outline (it is a cloud, not a stone). The instance colour is the lit tone, its alpha the fade. The pool lays the
// quad in the camera plane unrotated and carries a per-puff seed in the flat quad's z scale (1 + seed), so each puff
// gets its own lobes without turning its shading. Alpha blended, unshaded (dust is drawn self-lit, like the other
// effects), depth tested (the hero and the foes stand in front of it), never writes depth.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/pharos.gdshaderinc"

// The shaded tone (times the lit one) and the radius of the lit disc (in half-sizes of the quad).
uniform vec3 shade_col = vec3(0.8, 0.79, 0.88);
uniform float lit_r = 0.8;

varying float v_seed;

void vertex() {
	v_seed = length(MODEL_MATRIX[2].xyz) - 1.0;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float ang = atan(q.y, q.x);
	float s = v_seed * 6.2832;
	float edge = 0.84 + 0.08 * sin(ang * 5.0 + s) + 0.05 * sin(ang * 3.0 - s * 1.7);
	float aa = max(fwidth(r) * 1.2, 1e-3);
	float a = 1.0 - smoothstep(edge - aa, edge, r);
	// the lit disc, offset up and to the left (UV y grows downwards), with its own lobes
	vec2 ql = q - vec2(-0.2, -0.24);
	float al = atan(ql.y, ql.x);
	float le = lit_r * (0.9 + 0.07 * sin(al * 4.0 + s * 2.3));
	float lit = 1.0 - smoothstep(le - aa, le, length(ql));
	vec3 c = COLOR.rgb * mix(shade_col, vec3(1.0), lit);
	vec3 lin = ph_srgb_to_linear(c);
	ALBEDO = ph_out(mix(lin, g_fog_color, ph_fog(VERTEX)));
	ALPHA = clamp(a * COLOR.a, 0.0, 1.0);
}
