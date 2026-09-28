// DEAD AIR GradePass (port of render.js GradeShader): the full-screen grade that reads the HDR world view
// (render.gd `view`, linear), applies every render.post knob in linear HDR, then three's ACES Filmic tone mapping
// (toneMappingExposure 1.05) and the sRGB transfer (the JS pass folds the OutputPass in). vUv / the texture lookups
// use three's y-up convention (Godot UV.y is flipped on entry and on every sample).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D tDiffuse : filter_linear, repeat_disable;
uniform sampler2D tBloom : filter_linear, repeat_disable;   // render.gd bloom chain (UnrealBloomPass composite)
uniform vec2 uRes = vec2(1280.0, 720.0);
uniform float uTime = 0.0;
uniform float uSaturation = 1.0;
uniform float uContrast = 1.06;
uniform float uWarmth = 1.0;
uniform float uGrain = 0.03;
uniform float uVignette = 0.0;
uniform float uChroma = 0.0;
uniform float uDamage = 0.0;
uniform float uStatic = 0.0;
uniform float uRoll = 0.0;
uniform float uRollPhase = 0.0;
uniform float uWhiteout = 0.0;
uniform float uScanlines = 0.0;
uniform float uCrt = 0.0;
uniform float uCollapse = 0.0;
uniform vec4 uView = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec3 uLift : source_color = vec3(0.0423114, 0.0231534, 0.1022417);
uniform float uExposure = 1.05;

#define PI 3.141592653589793

vec3 daSafe(vec3 c) {
	c = (any(isnan(c)) || any(isinf(c))) ? vec3(0.0) : c;
	return clamp(c, vec3(0.0), vec3(64.0));
}

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float box(vec2 uv, vec2 px) {
	vec2 e = smoothstep(vec2(0.0), px, uv) * smoothstep(vec2(0.0), px, 1.0 - uv);
	return e.x * e.y;
}

// the scene target after the UnrealBloomPass additive blend
vec3 tex(vec2 uv) {
	vec2 st = vec2(uv.x, 1.0 - uv.y);
	return texture(tDiffuse, st).rgb + texture(tBloom, st).rgb;
}

vec3 RRTAndODTFit(vec3 v) {
	vec3 a = v * (v + 0.0245786) - 0.000090537;
	vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
	return a / b;
}

vec3 ACESFilmicToneMapping(vec3 color) {
	const mat3 ACESInputMat = mat3(vec3(0.59719, 0.07600, 0.02840), vec3(0.35458, 0.90834, 0.13383), vec3(0.04823, 0.01566, 0.83777));
	const mat3 ACESOutputMat = mat3(vec3(1.60475, -0.10208, -0.00327), vec3(-0.53108, 1.10813, -0.07276), vec3(-0.07367, -0.00605, 1.07602));
	color *= uExposure / 0.6;
	color = ACESInputMat * color;
	color = RRTAndODTFit(color);
	color = ACESOutputMat * color;
	return clamp(color, 0.0, 1.0);
}

vec3 sRGBTransferOETF(vec3 v) {
	return mix(pow(v, vec3(0.41666)) * 1.055 - vec3(0.055), v * 12.92, vec3(lessThanEqual(v, vec3(0.0031308))));
}

void fragment() {
	vec2 vUv = vec2(UV.x, 1.0 - UV.y);
	vec2 px = 1.0 / uRes;
	// CRT power-off: squash to a line (c1), shrink to a dot (c2), fade (c3).
	float c1 = smoothstep(0.0, 0.5, uCollapse);
	float c2 = smoothstep(0.45, 0.85, uCollapse);
	float c3 = smoothstep(0.85, 1.0, uCollapse);
	vec2 sq = vec2(mix(1.0, 0.006, c2), mix(1.0, 0.005, c1));
	vec2 cuv = 0.5 + (vUv - 0.5) / sq;
	float onScreen = box(cuv, 1.5 * px / sq);

	// Camera override viewport (commercials).
	vec2 uv = (cuv - uView.xy) / uView.zw;
	float inView = box(uv, px / uView.zw);

	// Commercial CRT barrel.
	vec2 cc = uv - 0.5;
	float k = 0.2 * uCrt;
	uv = 0.5 + cc * (1.0 - k * 0.5 + k * 2.0 * dot(cc, cc));
	inView *= mix(1.0, box(uv, 2.0 * px), step(0.001, uCrt));

	// Vertical roll / hold slip.
	float slip = smoothstep(0.65, 1.0, uDamage);
	float ry = uv.y + uRollPhase;
	float seam = 1.0 - smoothstep(0.0, 0.035, min(fract(ry), 1.0 - fract(ry)));
	uv.y = fract(ry);

	// Line jitter (signal loss / static).
	vec2 dir = uv - 0.5;
	float edge = dot(dir, dir) * 4.0;
	float line = floor(uv.y * 200.0);
	float jit = h12(vec2(line, floor(uTime * 30.0))) - 0.5;
	uv.x += jit * (0.012 * uDamage * edge + 0.006 * uStatic + 0.004 * uCrt * step(0.97, h12(vec2(line, floor(uTime * 8.0)))));

	// Chromatic aberration growing toward the edges.
	float ca = (0.4 + uChroma + uDamage * 4.0 + uCrt * 1.5) * px.x;
	vec2 off = dir * ca * (0.35 + edge) * 2.0;
	vec3 col = daSafe(vec3(tex(uv + off).r, tex(uv).g, tex(uv - off).b));

	// Grade: saturation, contrast (around linear mid-grey), warm tint, purple-lifted shadows.
	float L = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(L), col, uSaturation);
	col = 0.18 * pow(max(col, vec3(0.0)) / 0.18, vec3(uContrast));
	col *= mix(vec3(1.0), vec3(1.045, 1.0, 0.93), uWarmth);
	col += uLift * 0.018 * (1.0 - smoothstep(0.0, 0.2, L));

	// Signal-loss static from the edges + full-screen snow.
	vec2 q = vUv - 0.5;
	float n = h12(floor(vUv * uRes * 0.5) + floor(uTime * 30.0) * vec2(17.3, 91.7));
	vec3 snow = vec3(n * n) * vec3(1.35, 1.45, 1.6);
	float r = length(q * vec2(1.25, 1.0)) * 2.0;
	float emask = smoothstep(1.25 - 0.75 * uDamage, 1.45, r + (n - 0.5) * 0.25) * uDamage;
	col = mix(col, snow, clamp(emask, 0.0, 0.95));
	col = mix(col, snow * 1.1, uStatic);

	// Scanlines (HUD/crt) and the roll seam.
	float sl = 0.5 + 0.5 * cos(vUv.y * uRes.y * PI);
	col *= 1.0 - (uScanlines * 0.25 + uCrt * 0.3) * (1.0 - sl);
	col *= 1.0 - seam * 0.7 * clamp(uRoll + slip, 0.0, 1.0);

	// Vignette: subtle base + extra + commercial.
	float vig = 0.28 + uVignette * 0.6 + uCrt * 0.35;
	col *= 1.0 - vig * smoothstep(0.45, 1.25, length(q * vec2(1.3, 1.0)) * 1.6);

	// Whiteout and grain.
	col = mix(col, vec3(7.0), uWhiteout);
	col += (h12(vUv * uRes + fract(uTime * 13.7) * 311.0) - 0.5) * uGrain * (0.2 + L);

	// Clip to viewport and collapse; the collapsing line/dot glows white-hot.
	col *= inView;
	col = mix(col, vec3(5.0), c1 * 0.9);
	float halo = exp(-abs(vUv.y - 0.5) / 0.012) * exp(-max(abs(vUv.x - 0.5) - 0.5 * sq.x, 0.0) / 0.012);
	col = col * onScreen + vec3(1.6, 1.8, 2.2) * halo * c1 * (1.0 - onScreen);
	col *= 1.0 - c3;
	col = max(col, vec3(0.0));
	// Folded OutputPass: ACES + sRGB.
	COLOR = vec4(sRGBTransferOETF(ACESFilmicToneMapping(col)), 1.0);
}
