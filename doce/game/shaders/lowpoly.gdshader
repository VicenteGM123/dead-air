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
uniform float flash = 0.0;     // hit flash (0..1)
uniform float dissolve = 0.0;  // 0 = solid, 1 = gone
uniform vec3 tint = vec3(1.0);
uniform float metal = 0.0; // TOON: bronze / gold surfaces of this material get anime metal highlights

varying vec3 v_albedo;
varying vec3 v_albedo_day;
varying float v_kind;
varying vec3 v_base;
varying float v_fogf;
varying float v_cloud;
varying vec3 v_wpos;
varying float v_metal;

void vertex() {
	v_albedo_day = ph_toon_albedo_day(ph_srgb_to_linear(COLOR.rgb)) * tint;
	v_albedo = ph_toon_night(v_albedo_day);
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
		emit = g_window * g_night * 3.2;
		albedo = mix(albedo, albedo * 0.4, g_night);
	} else if (v_kind < 0.75) {
		emit = albedo * glow_strength;
	}
	// TOON metal: bronze and gold (hue 28-52 deg, saturated) on characters flagged `metal`
	v_metal = 0.0;
	if (metal > 0.0 && v_kind > 0.75) {
		vec3 sg = sqrt(albedo);
		float mx = max(sg.r, max(sg.g, sg.b));
		float mn = min(sg.r, min(sg.g, sg.b));
		float sat = (mx - mn) / max(mx, 1e-4);
		float hue = 60.0 * (sg.g - sg.b) / max(mx - mn, 1e-4); // red is the max for these hues
		if (sg.r >= mx - 1e-4 && hue > 22.0 && hue < 56.0 && sat > 0.42 && mx > 0.35) {
			v_metal = metal;
		}
	}
	vec3 base = albedo * ph_toon_ambient(wn) * mix(1.0, 0.72, v_metal) + emit;
	// a cool sky reflection band across the upper half of metal parts (anime metal)
	vec3 vn = normalize(NORMAL);
	base += albedo * smoothstep(0.3, 0.36, vn.y) * 0.18 * v_metal * (1.0 - g_night * 0.6);
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
	v_cloud = ph_cloud_shade(v_wpos);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	vec3 lit;
	if (LIGHT_IS_DIRECTIONAL) {
		float k = ph_toon_ramp(ndl) * ph_toon_shadow(ATTENUATION) * v_cloud;
		lit = ALBEDO * LIGHT_COLOR / PI * k;
		if (v_metal > 0.0) {
			vec3 H = normalize(LIGHT + VIEW);
			float nh = dot(NORMAL, H);
			float hi = smoothstep(0.93, 0.95, nh) * 1.4 + smoothstep(0.7, 0.75, nh) * 0.18;
			lit += mix(ALBEDO, vec3(1.0), 0.6) * LIGHT_COLOR / PI * hi * ph_toon_shadow(ATTENUATION) * v_metal;
		}
	} else {
		float d = smoothstep(-0.2, 0.15, ndl);
		lit = v_albedo_day * (1.0 - flash) * LIGHT_COLOR / PI * d * ph_toon_pool(ATTENUATION);
		if (v_metal > 0.0) {
			vec3 H = normalize(LIGHT + VIEW);
			lit += LIGHT_COLOR / PI * smoothstep(0.88, 0.92, dot(NORMAL, H)) * ph_toon_pool(ATTENUATION) * v_metal;
		}
	}
	SPECULAR_LIGHT += ph_light_out(lit, LIGHT_IS_DIRECTIONAL, v_base, v_fogf);
}
