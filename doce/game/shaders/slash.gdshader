// The cut flash (Fx "slash" pool, Fx.slash_mark). Two shapes, picked by the instance's z scale (the quad is flat,
// so its z axis is free to carry a flag: 1 = cut, 2 = pierce):
//  - cut: a long thin lens across the point where a blade bites, pointed at both ends, its centre line bowing a
//    little towards the quad's +y (up on screen: the pool always lays it pointing right, like the far side of a
//    swing seen from behind the hero); a white core inside a rim of the instance colour and a thin saturated warm
//    edge outside it, all with crisp edges;
//  - pierce (a thrust driving into the screen, its cut foreshortened to a dot): a thin ring with four short spikes,
//    the same white core, coloured rim and warm edge.
// The quad is laid in the camera plane by the pool (x along the cut, y across); the instance colour's alpha fades it.
// Alpha blended (it reads on bright sand and on dark fur alike), unshaded, pulled `pull` m towards the camera like
// the impact stars (the hero's own body never hides it; the pool shrinks it in proportion). Drawn after the stars
// (render_priority) so the crisp line sits on top of the glow.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform float pull = 1.9;
// The cut: how far the centre line bows at the middle (in half-heights of the quad), the lens' half-thickness at its
// middle (in half-heights) and the white core's share of it.
uniform float bend = 0.22;
uniform float thick = 0.5;
uniform float core = 0.55;
// The rim's opacity; the warm edge outside it (the instance colour times edge_tint: a saturated orange-red, like
// Wind Waker's hit sparks), its width (in units of the rim's half-thickness) and opacity. The edge is what makes
// the flash read on white: the star, a foe's white hit flash, bright sand.
uniform float rim_a = 0.95;
uniform vec3 edge_tint = vec3(0.86, 0.42, 0.16);
uniform float edge_w = 0.3;
uniform float edge_a = 0.9;
// The pierce: the ring's radius and half-width (in half-sizes of the quad), the spikes' half-width.
uniform float ring_r = 0.66;
uniform float ring_w = 0.1;
uniform float spike_w = 0.07;

varying float v_mode;

void vertex() {
	v_mode = length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX[3].xyz += normalize(-MODELVIEW_MATRIX[3].xyz) * pull;
}

void fragment() {
	vec2 q = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float d;
	if (v_mode < 1.5) {
		float along = max(1.0 - q.x * q.x, 0.0);
		float yc = bend * along;
		float ht = thick * pow(along, 0.7);
		d = abs(q.y - yc) / max(ht, 1e-3);
	} else {
		float r = length(q);
		float dr = abs(r - ring_r) / ring_w;
		// four spikes from the ring outwards (and a little inwards), thinning to points
		vec2 aq = abs(q);
		float s1 = aq.y / max(spike_w * (1.0 - aq.x), 1e-3) + step(aq.x, ring_r * 0.55) * 9.0;
		float s2 = aq.x / max(spike_w * (1.0 - aq.y), 1e-3) + step(aq.y, ring_r * 0.55) * 9.0;
		d = min(dr, min(s1, s2));
		d = r > 1.0 ? 9.0 : d;
	}
	float aa = max(fwidth(d) * 1.2, 1e-3);
	float outer = 1.0 - smoothstep(1.0 + edge_w - aa, 1.0 + edge_w, d);
	float rim = 1.0 - smoothstep(1.0 - aa, 1.0, d);
	float cr = 1.0 - smoothstep(core - aa, core, d);
	vec3 c = mix(mix(COLOR.rgb * edge_tint, COLOR.rgb, rim), vec3(1.0), cr);
	float a = max(max(outer * edge_a, rim * rim_a), cr) * COLOR.a;
	vec3 lin = ph_srgb_to_linear(c);
	ALBEDO = ph_out(mix(lin, g_fog_color, ph_fog(VERTEX)));
	ALPHA = clamp(a, 0.0, 1.0);
}
