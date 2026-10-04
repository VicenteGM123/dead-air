// DEAD AIR CRT screen glass (port of materials.js screen() / rubberGlass(): SCREEN_VERT + SCREEN_FRAG).
// Swappable picture tScreen (DAMaterial.map), barrel, scanlines, chroma offset, vignette, glossy sheet, the
// animated vertex bulge of the rubber glass (uBulge 0..0.35 m, uWobble 0..1; use mats.screenGeometry(w, h)),
// camera occlusion fade and fog. Opaque, FrontSide, unlit.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back, depth_draw_opaque, blend_mix;
#include "res://shaders/da_common.gdshaderinc"

uniform sampler2D tScreen : source_color, filter_linear_mipmap, repeat_disable, hint_default_black;
uniform float uFlip = 1.0;
uniform float uBulge = 0.0;
uniform float uWobble = 0.0;
uniform vec2 uSize = vec2(1.0, 0.75);
uniform float uBarrel = 0.06;
uniform float uScan = 0.35;
uniform float uBright = 1.35;
uniform float uChroma = 1.5;
uniform float uVignette = 0.8;
uniform float uGloss = 1.0;
uniform float uLines = 120.0;
uniform vec2 uTexel = vec2(0.00390625, 0.00390625);
uniform vec3 uTint = vec3(1.0);
uniform float uFogK = 1.0;

varying vec3 vN;
varying vec3 vView;
varying vec3 vDaW;

void vertex() {
	vec2 c = UV * 2.0 - 1.0;
	float wob = 1.0 + uWobble * 0.35 * sin(uTime * 11.0 + c.x * 5.0) * sin(uTime * 8.0 - c.y * 4.0);
	float amp = uBulge * wob;
	float w = (1.0 - c.x * c.x) * (1.0 - c.y * c.y);
	vec3 p = VERTEX;
	p.z += amp * w;
	float dx = amp * (-2.0 * c.x) * (1.0 - c.y * c.y) * 2.0 / max(uSize.x, 1e-3);
	float dy = amp * (-2.0 * c.y) * (1.0 - c.x * c.x) * 2.0 / max(uSize.y, 1e-3);
	vN = normalize(MODELVIEW_NORMAL_MATRIX * normalize(vec3(-dx, -dy, 1.0)));
	vec4 mv = MODELVIEW_MATRIX * vec4(p, 1.0);
	vView = -mv.xyz;
	vDaW = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
	VERTEX = p;
}

void fragment() {
	vec2 vUv = UV;
	vec2 c = vUv - 0.5;
	vec2 uv = 0.5 + c * (1.0 - uBarrel + uBarrel * 4.0 * dot(c, c));
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	vec2 off = vec2(uChroma * uTexel.x, 0.0);
	vec2 st = vec2(uv.x, uFlip > 0.5 ? 1.0 - uv.y : uv.y);
	vec3 col = daIn(vec3(texture(tScreen, st + off).r, texture(tScreen, st).g, texture(tScreen, st - off).b));
	float sl = 0.5 + 0.5 * cos(uv.y * 2.0 * DA_PI * uLines);
	col *= 1.0 - uScan * (1.0 - sl);
	col *= 0.95 + 0.05 * sin(uv.y * 7.0 - uTime * 2.3);
	float vig = smoothstep(0.78, 0.25, length(c * vec2(1.0, 1.2)));
	col *= mix(1.0, vig, uVignette) * inside * uBright * uTint;
	vec3 n = normalize(vN);
	vec3 vd = normalize(vView);
	float fr = pow(1.0 - clamp(dot(n, vd), 0.0, 1.0), 3.0);
	vec3 r = reflect(-vd, n);
	float spec = pow(clamp(dot(r, normalize(vec3(-0.4, 0.65, 0.65))), 0.0, 1.0), 40.0);
	float streak = smoothstep(0.1, 0.0, abs((vUv.x + vUv.y * 0.6) - 1.05)) * 0.08;
	vec3 glass = vec3(0.012, 0.014, 0.02) + fr * vec3(0.16, 0.18, 0.22) + (spec * 0.9 + streak) * vec3(1.0, 0.97, 0.92);
	vec3 outc = col + glass * uGloss;
	if (!daIsShadowPass(PROJECTION_MATRIX) && daOccDrop(vView.z, vDaW, FRAGCOORD.xy, CAMERA_POSITION_WORLD)) discard;
	outc = mix(outc, daFogColor, daFogF(vView.z, CAMERA_VISIBLE_LAYERS) * uFogK);
	ALBEDO = daOut(outc);
}
