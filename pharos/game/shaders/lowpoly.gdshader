// Flat-shaded, vertex-coloured material used by every model in the game.
// Vertex colour alpha is a material flag:
//   1.0  regular surface
//   0.5  self-lit (fire, glowing eyes, magic): bright regardless of light
//   0.0  window: dark by day, warm glow at night (g_night)
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled;

#include "res://shaders/pharos.gdshaderinc"

uniform float sway = 0.0;          // wind sway for foliage (metres per metre of height)
uniform float wrap = 0.35;         // wrapped diffuse amount
uniform float glow_strength = 2.4; // self-lit multiplier
uniform vec3 rim_color : source_color = vec3(0.0); // ethereal rim for the creatures of Nyx
uniform float rim_power = 2.5;
instance uniform float flash = 0.0;     // hit flash (0..1)
instance uniform float dissolve = 0.0;  // 0 = solid, 1 = gone
instance uniform vec3 tint = vec3(1.0);

varying vec3 v_albedo;
varying float v_kind;
varying vec3 v_base;
varying float v_fogf;
varying vec3 v_wpos;

void vertex() {
	v_albedo = ph_srgb_to_linear(COLOR.rgb) * tint;
	v_kind = COLOR.a;
	if (sway > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float h = max(VERTEX.y, 0.0);
		float t = g_time * 1.3 + wp.x * 0.21 + wp.z * 0.17;
		float s = sin(t) * 0.6 + sin(t * 2.3 + 1.7) * 0.25;
		VERTEX.x += s * h * sway * g_wind;
		VERTEX.z += cos(t * 0.8) * 0.4 * h * sway * g_wind;
	}
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dissolve > 0.0) {
		float n = ph_noise(v_wpos.xz * 3.1 + v_wpos.y * 2.3) * 0.7 + ph_noise(v_wpos.xy * 7.0) * 0.3;
		if (n < dissolve) {
			discard;
		}
	}
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 albedo = v_albedo;
	vec3 emit = vec3(0.0);
	if (v_kind < 0.25) {
		emit = g_window * g_night * 1.6;
		albedo = mix(albedo, albedo * 0.4, g_night);
	} else if (v_kind < 0.75) {
		emit = albedo * glow_strength;
	}
	vec3 base = albedo * ph_ambient(wn) + emit;
	if (rim_color.r + rim_color.g + rim_color.b > 0.0) {
		float rim = pow(1.0 - clamp(dot(NORMAL, normalize(-VERTEX)), 0.0, 1.0), rim_power);
		base += ph_srgb_to_linear(rim_color) * rim * (0.25 + 0.45 * g_night);
	}
	base = mix(base, vec3(1.0, 0.98, 0.94), flash * 0.85);
	if (dissolve > 0.0) {
		float n = ph_noise(v_wpos.xz * 3.1 + v_wpos.y * 2.3) * 0.7 + ph_noise(v_wpos.xy * 7.0) * 0.3;
		base += vec3(0.5, 0.95, 1.0) * smoothstep(dissolve + 0.08, dissolve, n) * 2.0;
	}
	float f = ph_fog(VERTEX);
	ALBEDO = ph_out(albedo * (1.0 - flash));
	EMISSION = ph_out(mix(base, g_fog_color, f));
	v_base = ph_godot_in(EMISSION);
	v_fogf = f;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float d = max((ndl + wrap) / (1.0 + wrap), 0.0);
	vec3 lit = ALBEDO * LIGHT_COLOR / PI * d * ATTENUATION;
	SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);
}
