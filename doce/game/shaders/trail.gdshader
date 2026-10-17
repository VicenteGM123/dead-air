// The sword's smear (BladeTrail): crisp anime bands drawn per pixel from two coordinates the ribbon carries, so the
// shapes stay sharp however few vertices the arc has. Flat colours with clean edges (Wind Waker), never a soft
// gradient soup: a short soft inner edge, a flat body, a crisp accent band along the tip, a solid leading stroke.
// Alpha blended, unshaded, never writes depth.
//   UV.x   across the band (see the modes)
//   UV.y   freshness: 1 where the blade is now .. 0 at the oldest end (the tail fades out under `tail`; older parts
//          are also fainter by `age_a`)
//   UV2.x  the mode:
//          0    body: UV.x 0 at the inner edge .. 1 at the blade's tip; the fill rises over `body_soft` of the band to
//               `body_a`, then a crisp accent band (`accent_w`, `accent_a`) runs along the tip
//          0.5  lance (the thrust): the body mirrored about the middle of the band (UV.x 0 and 1 the two sides)
//          1    line: a solid stroke across UV.x 0..1 with one anti-aliased pixel of fringe on each side (the leading
//               edge the tip draws; the thrust's pierce ring)
// Colours are sRGB (like fx.gdshader's vertex colours). Drawn `view_pull` m towards the camera (as fx.gdshader):
// the cut shows over the hero's own body and the foe it cuts; walls further away still hide it.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform float view_pull = 1.3;
uniform vec3 line_col = vec3(1.0, 1.0, 1.0);
uniform vec3 body_col = vec3(1.0, 0.97, 0.88);
uniform vec3 accent_col = vec3(1.0, 0.98, 0.92);
// The body's opacity; the accent band's width (fraction of the band next to the tip) and opacity.
uniform float body_a = 0.6;
uniform float accent_w = 0.2;
uniform float accent_a = 0.95;
// How far in from the inner edge the body takes to reach full opacity (0..1 of the band): short = crisp.
uniform float body_soft = 0.22;
// The freshness under which the tail fades out; how much fainter the oldest part is than the newest (0..1).
uniform float tail = 0.3;
uniform float age_a = 0.45;
uniform float line_a = 1.0;

void vertex() {
	if (view_pull > 0.0) {
		vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float l = max(length(vp.xyz), 1e-4);
		vp.xyz *= max(l - view_pull, 0.12) / l;
		POSITION = PROJECTION_MATRIX * vp;
	}
}

void fragment() {
	float u = clamp(UV.x, 0.0, 1.0);
	float fresh = clamp(UV.y, 0.0, 1.0);
	float fade = smoothstep(0.0, tail, fresh) * mix(1.0 - age_a, 1.0, fresh);
	vec3 c;
	float a;
	if (UV2.x > 0.75) {
		float d = 1.0 - abs(2.0 * u - 1.0);
		float aa = max(fwidth(d) * 1.25, 1e-4);
		a = smoothstep(0.0, aa, d) * line_a;
		c = line_col;
		// the stroke keeps its opacity longer than the body (the crescent ends in a thin bright line)
		fade = smoothstep(0.0, tail * 0.6, fresh);
	} else {
		if (UV2.x > 0.25) {
			u = 1.0 - abs(2.0 * u - 1.0);
		}
		float aa = max(fwidth(u) * 1.25, 1e-4);
		float acc = smoothstep(1.0 - accent_w - aa, 1.0 - accent_w, u);
		float body = body_a * smoothstep(0.0, max(body_soft, aa), u);
		a = mix(body, accent_a, acc);
		c = mix(body_col, accent_col, acc);
	}
	a *= fade;
	vec3 lin = ph_srgb_to_linear(c);
	ALBEDO = ph_out(mix(lin, g_fog_color, ph_fog(VERTEX)));
	ALPHA = clamp(a, 0.0, 1.0);
}
