// DEAD AIR toon material (port of materials.js toon(): MeshStandardMaterial + the onBeforeCompile patch).
// materials.gd builds the variant shaders as
//   shader_type spatial; render_mode <cull_back|cull_front|cull_disabled>, <depth_draw_*>, <blend_*>, fog_disabled;
//   #define DA_TRANSPARENT (writes ALPHA) / DA_BACK (BackSide pass; normals: see fragment) / DA_CHROMA / DA_CC
//   #include "res://shaders/toon.gdshaderinc"
// (toon.gdshader is the default opaque FrontSide variant.) Every per-material option of the JS (wrap, steps, rim,
// keepColor, heroFade, fog, env, flat, vertexColors, alphaTest, map) is a uniform, as in the JS program sharing.
//   - three MeshStandardMaterial r186 physics: GGX specular with multi-scattering compensation, Lambert diffuse
//     x (1 - F), the "wrap" half-lambert + optional steps on the direct diffuse (PATCHED_LIGHTS), hemisphere
//     through RE_IndirectDiffuse, RoomEnvironment IBL through RE_IndirectSpecular when envMapIntensity > 0.
//   - fresnel rim brighter on up-facing normals, pre-power grade + Sign-On wave (skipped with keepColor), hero fade
//     dither (uDaFade 1) or camera occlusion dither (uDaFade 0; 2 = neither), fog (uFogK).
//   - DA_CHROMA: props/weapons.js patchChroma (Chromacast finish of upgraded prop weapons, chromaUV in UV).
//   - DA_CC: game/weaponModels.js patchCC (object-space Chromacast of the game weapon models).
#include "res://shaders/da_common.gdshaderinc"

uniform vec3 uColor : source_color = vec3(1.0);
uniform float uOpacity = 1.0;
uniform float uRough = 0.75;
uniform float uMetal = 0.0;
uniform vec3 uEmissive : source_color = vec3(0.0);
uniform float uEmissiveIntensity = 1.0;
uniform float uEnv = 0.0;
uniform float uWrap = 0.5;
uniform float uSteps = 0.0;
uniform float uRimStrength = 0.35;
uniform float uRimPower = 2.4;
uniform vec3 uRimColor : source_color = vec3(1.0, 0.9137255, 0.8);
uniform float uKeep = 0.0;
uniform float uFogK = 1.0;
uniform float uDaFade = 0.0;
uniform float uAlphaTest = 0.0;
uniform float uVColor = 0.0;
uniform float uFlat = 0.0;
// map: uMapMode 0 none, 1 repeat+linear, 2 clamp+linear, 3 repeat+nearest, 4 clamp+nearest; uMapFlip 1 = three's
// flipY (textures stored top row first: canvas PNGs, DACanvas, viewports).
uniform int uMapMode = 0;
uniform float uMapFlip = 1.0;
uniform vec4 uMapXf = vec4(1.0, 1.0, 0.0, 0.0);   // three map repeat.xy, offset.zw
uniform sampler2D mapRL : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mapCL : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D mapRN : source_color, filter_nearest, repeat_enable;
uniform sampler2D mapCN : source_color, filter_nearest, repeat_disable;
// three instanceColor (InstancedMesh.setColorAt): node.set_instance_shader_parameter("instanceColor", Color).
instance uniform vec4 instanceColor : source_color = vec4(1.0);

#ifdef DA_CHROMA
uniform float uChHue = 0.0;
uniform float uChSpread = 1.0;
uniform float uChLen = 0.3;
uniform float uChDark = 1.0;
varying vec3 vChPos;
#endif
#ifdef DA_CC
uniform float uCcHue = 0.0;
uniform float uCcSpread = 1.0;
varying vec3 vCcPos;
#endif
#if defined(DA_CHROMA) || defined(DA_CC)
vec3 chHue(float h) {
	vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return k * k * (3.0 - 2.0 * k);
}
float chHash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
#endif

// fragment -> light
varying vec3 vDiff;
varying vec3 vSpecB;
varying float vRough;
varying vec3 vMsComp;
varying vec3 vHemiK;
varying vec4 vG;

vec4 daMapSample(vec2 uv) {
	vec2 t0 = uv * uMapXf.xy + uMapXf.zw;
	vec2 st = vec2(t0.x, uMapFlip > 0.5 ? 1.0 - t0.y : t0.y);
	if (uMapMode == 1) return texture(mapRL, st);
	if (uMapMode == 2) return texture(mapCL, st);
	if (uMapMode == 3) return texture(mapRN, st);
	return texture(mapCN, st);
}

void vertex() {
#ifdef DA_CHROMA
	vChPos = VERTEX;
#endif
#ifdef DA_CC
	vCcPos = VERTEX;
#endif
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float viewZ = -VERTEX.z;
	bool full = daFullColor(CAMERA_VISIBLE_LAYERS);

	vec4 diffuseColor = vec4(uColor, uOpacity);
	if (uMapMode > 0) diffuseColor *= daMapSample(UV);
	if (uVColor > 0.5) diffuseColor.rgb *= COLOR.rgb;
	diffuseColor.rgb *= instanceColor.rgb;
	vec3 extraEm = vec3(0.0);
#ifdef DA_CHROMA
	{
		float t = UV.x;
		float hue = uChSpread > 0.9 ? t * 0.9 - uTime * 0.1 + uChHue : uChHue + uChSpread * sin(t * 5.5 - uTime * 0.8);
		vec3 cc = chHue(fract(hue + 0.04 * sin(UV.y * 40.0 + t * 9.0)));
		cc = pow(mix(vec3(1.0), cc, 0.92), vec3(1.5));
		float s = UV.x * uChLen * 70.0 + UV.y * 40.0 - uTime * 2.0;
		float cell = floor(s);
		float f = fract(s);
		float grp = mod(cell, 17.0);
		float band = step(grp, 6.5) * smoothstep(0.0, 0.1, f) * (1.0 - smoothstep(0.9, 1.0, f));
		vec3 bar = uBars[int(mod(grp, 7.0))];
		cc = mix(cc, bar * bar, band * 0.8);
		cc *= min(1.0, 0.5 / max(dot(cc, vec3(0.299, 0.587, 0.114)), 1e-3));
		cc *= uChDark;
		diffuseColor.rgb *= cc;
		extraEm = cc * 0.3;
		float sp = chHash(floor(vChPos * 150.0));
		float tw = step(0.972, sp) * pow(max(0.0, sin(uTime * 3.3 + sp * 91.0)), 3.0);
		extraEm += vec3(1.0, 0.96, 0.88) * tw * 2.2;
	}
#endif
#ifdef DA_CC
	{
		float t = dot(vCcPos, vec3(0.7, 0.35, 0.6)) * 2.2;
		float hue = uCcSpread > 0.9 ? t - uTime * 0.1 + uCcHue : uCcHue + uCcSpread * sin(t * 5.5 - uTime * 0.8);
		vec3 cc = chHue(fract(hue));
		float s = t * 22.0 - uTime * 2.0;
		float grp = mod(floor(s), 17.0);
		float band = step(grp, 6.5) * smoothstep(0.0, 0.1, fract(s)) * (1.0 - smoothstep(0.9, 1.0, fract(s)));
		cc = mix(cc, uBars[int(mod(grp, 7.0))], band * 0.7);
		diffuseColor.rgb *= cc;
		extraEm = cc * 0.3;
		float sp = chHash(floor(vCcPos * 150.0));
		extraEm += vec3(1.0, 0.96, 0.88) * step(0.972, sp) * pow(max(0.0, sin(uTime * 3.3 + sp * 91.0)), 3.0) * 2.2;
	}
#endif
	if (uAlphaTest > 0.0 && diffuseColor.a < uAlphaTest) discard;

	// hero fade (uDaFade 1) / camera occlusion (uDaFade 0) screen-door fades; never in the shadow pass
	if (!daIsShadowPass(PROJECTION_MATRIX)) {
		float hf = full ? 1.0 : uHeroFade;
		if (uDaFade > 0.5) {
			if (uDaFade < 1.5 && hf < 0.999 && hf <= daBayer(floor(FRAGCOORD.xy))) discard;
		} else if (daOccDrop(viewZ, wp, FRAGCOORD.xy, CAMERA_POSITION_WORLD)) {
			discard;
		}
	}

	// normal (flatShading: screen-space derivative normal, always camera-facing like three's). Godot already flips
	// NORMAL on back faces (FRONT_FACING false), which is three's FLIP_SIDED (BackSide) / DOUBLE_SIDED behaviour.
	vec3 N = normalize(NORMAL);
	if (uFlat > 0.5) {
		N = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
		if (dot(N, VIEW) < 0.0) N = -N;
	}
	NORMAL = N;

	// PhysicalMaterial (lights_physical_fragment)
	vec3 dxy = max(abs(dFdx(N)), abs(dFdy(N)));
	float rough = max(uRough, 0.0525);
	rough += max(max(dxy.x, dxy.y), dxy.z);
	rough = min(rough, 1.0);
	float metal = uMetal;
	vec3 diffC = diffuseColor.rgb * (1.0 - metal);
	vec3 specB = mix(vec3(0.04), diffuseColor.rgb, metal);
	float dotNV = clamp(dot(N, VIEW), 0.0, 1.0);
	vec2 dfg = daDFGLookup(rough, dotNV);
	float EssMs = dfg.x + dfg.y;
	vec3 msComp = 1.0 + specB * (1.0 / EssMs - 1.0);
	vec3 ssD = vec3(0.0);
	vec3 msD = vec3(0.0);
	daMultiscatter(dfg, vec3(0.04), 1.0, ssD, msD);

	// RE_IndirectSpecular with the RoomEnvironment (skipped when envMapIntensity is 0, PATCHED_MAPS)
	vec3 indirect = vec3(0.0);
	if (uEnv > 0.0) {
		vec3 wN = normalize((INV_VIEW_MATRIX * vec4(N, 0.0)).xyz);
		vec3 iblIrr = getIBLIrradiance(wN) * uEnv;
		vec3 rad = getIBLRadiance(VIEW, N, rough, INV_VIEW_MATRIX) * uEnv;
		vec3 ssM = vec3(0.0);
		vec3 msM = vec3(0.0);
		daMultiscatter(dfg, diffuseColor.rgb, 1.0, ssM, msM);
		vec3 ss = mix(ssD, ssM, metal);
		vec3 ms = mix(msD, msM, metal);
		vec3 cwi = iblIrr * DA_RECIPROCAL_PI;
		indirect = rad * ss + ms * cwi + diffC * (1.0 - (ssD + msD)) * cwi;
	}

	// emissive + rim (FRAG_OUT)
	vec3 em = uEmissive * uEmissiveIntensity + extraEm;
	float daRim = pow(1.0 - dotNV, uRimPower);
	vec3 daWN = normalize((INV_VIEW_MATRIX * vec4(N, 0.0)).xyz);
	daRim *= 0.55 + 0.45 * clamp(daWN.y + 0.6, 0.0, 1.0);
	vec3 rim = uRimColor * (daRim * uRimStrength * uRimAmbient * 1.6);

	// pre-power grade / Sign-On wave / fog as an affine map, shared with light()
	float fogK = daFogF(viewZ, CAMERA_VISIBLE_LAYERS) * uFogK;
	vec3 K;
	vec4 g = daGradeSetup(wp, uKeep > 0.5, full, fogK, K);
	EMISSION = daGrade(indirect + em + rim, g) + K;

	vDiff = diffC;
	vSpecB = specB;
	vRough = rough;
	vMsComp = msComp;
	vHemiK = 1.0 - ssD - msD;
	vG = g;

	ALBEDO = vec3(0.0);
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
#ifdef DA_TRANSPARENT
	ALPHA = diffuseColor.a;
#endif
}

void light() {
	vec3 c;
	if (daIsHemi(SPECULAR_AMOUNT)) {
		// hemisphere half: getHemisphereLightIrradiance -> RE_IndirectDiffuse_Physical
		vec3 irr = LIGHT_COLOR * DA_RECIPROCAL_PI * (0.5 + 0.5 * dot(NORMAL, LIGHT));
		c = irr * DA_RECIPROCAL_PI * vDiff * vHemiK;
	} else {
		// RE_Direct_Physical with the toon wrap/steps on the diffuse (PATCHED_LIGHTS)
		vec3 lc = LIGHT_COLOR * DA_RECIPROCAL_PI * ATTENUATION;
		float nl = dot(NORMAL, LIGHT);
		float dotNL = clamp(nl, 0.0, 1.0);
		vec3 irradiance = dotNL * lc;
		vec3 daIrr = daShade(clamp((nl + uWrap) / (1.0 + uWrap), 0.0, 1.0), uSteps) * lc;
		vec3 H = normalize(LIGHT + VIEW);
		float dotNV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float dotNH = clamp(dot(NORMAL, H), 0.0, 1.0);
		float dotVH = clamp(dot(VIEW, H), 0.0, 1.0);
		float alpha = vRough * vRough;
		vec3 F = F_Schlick(vSpecB, 1.0, dotVH);
		vec3 spec = irradiance * (F * (V_GGX_SmithCorrelated(alpha, dotNL, dotNV) * D_GGX(alpha, dotNH))) * vMsComp;
		vec3 Fd = F_Schlick(vec3(0.04), 1.0, dotVH);
		c = spec + daIrr * DA_RECIPROCAL_PI * vDiff * (1.0 - Fd);
	}
	SPECULAR_LIGHT += daGrade(c, vG);
}
