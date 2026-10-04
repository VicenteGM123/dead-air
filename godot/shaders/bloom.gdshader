// DEAD AIR bloom: exact port of three's UnrealBloomPass (strength 0.45, radius 0.55, threshold 0.8) as a chain of
// half-float SubViewports built by render.gd (nested so Godot draws them in order, after the world view):
//   mode 0  LuminosityHighPassShader: texel * smoothstep(threshold, threshold + 0.01, Rec.709 luminance) (half res)
//   mode 1  separable gaussian blur (kernel radius 6/10/14/18/22 on the 5 mips, sigma = radius / 3, paired taps)
//   mode 2  composite: 3 * strength * sum(lerpBloomFactor(factor_i) * mip_i) (half res; the grade adds it to the
//           scene where the JS blends it additively onto the read buffer)
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform int mode = 0;
uniform sampler2D colorTexture : filter_linear, repeat_disable;
uniform float luminosityThreshold = 0.8;
uniform float smoothWidth = 0.01;
uniform vec2 invSize = vec2(0.001);
uniform vec2 direction = vec2(1.0, 0.0);
uniform float centerWeight = 0.0;
uniform int pairs = 0;
uniform float gaussianOffsets[11];
uniform float gaussianWeights[11];
uniform sampler2D blurTexture1 : filter_linear, repeat_disable;
uniform sampler2D blurTexture2 : filter_linear, repeat_disable;
uniform sampler2D blurTexture3 : filter_linear, repeat_disable;
uniform sampler2D blurTexture4 : filter_linear, repeat_disable;
uniform sampler2D blurTexture5 : filter_linear, repeat_disable;
uniform float bloomStrength = 0.45;
uniform float bloomRadius = 0.55;

float lerpBloomFactor(float factor) {
	float mirrorFactor = 1.2 - factor;
	return mix(factor, mirrorFactor, bloomRadius);
}

void fragment() {
	vec2 vUv = UV;
	if (mode == 0) {
		vec4 texel = texture(colorTexture, vUv);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		// the world view is sRGB-encoded under Compatibility (see post.gdshader daCompatIn)
		texel.rgb = mix(vec3(0.0), pow((max(texel.rgb, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), vec3(greaterThan(texel.rgb, vec3(0.0))));
#endif
		float v = dot(vec3(0.2126, 0.7152, 0.0722), texel.rgb);
		float alpha = smoothstep(luminosityThreshold, luminosityThreshold + smoothWidth, v);
		COLOR = mix(vec4(0.0), texel, alpha);
	} else if (mode == 1) {
		vec3 diffuseSum = texture(colorTexture, vUv).rgb * centerWeight;
		for (int i = 0; i < pairs; i++) {
			vec2 uvOffset = direction * invSize * gaussianOffsets[i];
			vec3 sample1 = texture(colorTexture, vUv + uvOffset).rgb;
			vec3 sample2 = texture(colorTexture, vUv - uvOffset).rgb;
			diffuseSum += (sample1 + sample2) * gaussianWeights[i];
		}
		COLOR = vec4(diffuseSum, 1.0);
	} else {
		vec3 bloom = 3.0 * bloomStrength * (
			lerpBloomFactor(1.0) * texture(blurTexture1, vUv).rgb +
			lerpBloomFactor(0.8) * texture(blurTexture2, vUv).rgb +
			lerpBloomFactor(0.6) * texture(blurTexture3, vUv).rgb +
			lerpBloomFactor(0.4) * texture(blurTexture4, vUv).rgb +
			lerpBloomFactor(0.2) * texture(blurTexture5, vUv).rgb);
		COLOR = vec4(bloom, 1.0);
	}
}
