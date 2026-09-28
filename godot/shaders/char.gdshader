// Character material for baked SDF characters (port of src/art/charMaterial.js createCharMaterial: three.js
// MeshStandardMaterial r186 + the onBeforeCompile patch). One material per character type, shared by the skinned body
// and its rigid parts (char_material.gd createCharMaterial; per-instance: uMorphW).
// Per-vertex inputs (blender/chars/FORMAT.md §4, + CUSTOM3 / TANGENT added by char_runtime.gd at load):
//   COLOR = (albedo sRGB, ao)  UV = pco.xy  UV2 = (pco.z, cavity)  CUSTOM0 = (matId, patternMode, pw.x, pw.y)
//   CUSTOM1 = (pw.z, flow.xyz)  CUSTOM2 = (dc0, dc1, dc2, 0) packed morph colour deltas  CUSTOM3 = rest position
//   (the JS vRest: Godot skins before vertex())  TANGENT = flow direction (skinned by Godot like the JS skinMatrix).
// Per-material params (header.materials[name] -> uMatA..D[matId]): rough, metal, pattern layer, pattern scale |
//   wrap, sss, fuzz, aniso | spec, lines, bump, cavity | sheen, sheenExp.
// Shading (as the JS): half-lambert wrap, warm subsurface in the terminator, baked AO + cavity, fabric patterns
// sampled in REST space (never swim), stitch/seam lines, Kajiya-Kay strand highlights, molded-toy hair sheen band,
// fuzz, fresnel rim (warm heroes / cyan zombies), heroFade screen-door dither (uFade), scene fog.
// Lighting follows shaders/da_common.gdshaderinc (godot-core): every lit term goes to SPECULAR_LIGHT / EMISSION with
// ALBEDO = METALLIC = SPECULAR = 0; hemisphere = the light_specular == 0 directional pair; directLight.color =
// LIGHT_COLOR / PI * ATTENUATION; RoomEnvironment IBL from daEnvMap (envMapIntensity uEnv, diffuse x uIBLDiffuse).
// JS characters are MeshStandardMaterials: no pre-power grade / Sign-On wave / camera occlusion (only fog).
// receiveShadow is false for every JS character (charRuntime default): shadows_disabled.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, blend_mix, fog_disabled, shadows_disabled;
#include "res://shaders/da_common.gdshaderinc"

#define DA_NMAT 24
uniform vec4 uMatA[DA_NMAT]; // rough, metal, pattern layer (-1 none), pattern scale (m)
uniform vec4 uMatB[DA_NMAT]; // wrap, sss, fuzz, aniso
uniform vec4 uMatC[DA_NMAT]; // spec, lines, bump, cavity
uniform vec4 uMatD[DA_NMAT]; // sheen, sheenExp, -, -
uniform sampler2DArray uPatterns : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D uLines : filter_nearest, repeat_disable;
uniform int uLineCount = 0;
uniform int uChunkCount = 0;
uniform vec3 uRimColor : source_color = vec3(1.0, 0.851, 0.627);
uniform float uRimStrength = 0.35;
uniform float uAOAmount = 1.0;
uniform int uDebug = 0;
uniform float uIBLDiffuse = 0.3;
uniform float uEnv = 0.8;      // envMapIntensity (0: no envMap)
uniform float uFade = 0.0;     // DA_FADE (opts.heroFade): dithered by the global uHeroFade
uniform float uFogK = 1.0;
// MeshStandardMaterial color / emissive (white / black; the zombie tints change them: DAMaterial.color / .emissive)
uniform vec3 uColor : source_color = vec3(1.0);
uniform vec3 uEmissive : source_color = vec3(0.0);
uniform float uEmissiveIntensity = 1.0;
// morph colour weights (= blend shape values of header.morphs[0..2]), set per instance by face.gd
instance uniform vec3 uMorphW = vec3(0.0);

varying float vAO;
varying float vCav;
varying flat float vMat;
varying float vPMode;
varying vec3 vPco;
varying vec3 vPw;
varying vec3 vRest;
varying float vFl2;
varying vec3 vColor;

// fragment -> light
varying vec3 vDiff;
varying vec3 vSpecB;
varying float vRough;
varying vec3 vMsComp;
varying vec3 vHemiK;
varying float vFogKeep;
varying float vAOi;
varying float vWrap;
varying float vSSS;
varying float vAniso;
varying float vSpec;
varying float vSheen;
varying float vSheenExp;
varying vec3 vFlowV;
varying vec3 vAlbedo;

float daSrgbToLinear(float c) {
	return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

vec3 daUnpackDC(float v) {
	int i = int(v + 0.5);
	return (vec3(float(i & 255), float((i >> 8) & 255), float((i >> 16) & 255)) - 128.0) / 127.0;
}

vec4 daPattern(float layer, float scale, out float ok) {
	ok = 0.0;
	if (layer < -0.5) return vec4(1.0, 1.0, 1.0, 0.5);
	ok = 1.0;
	vec3 p = vPco / scale;
	if (vPMode > 0.5) return texture(uPatterns, vec3(p.xy, layer));
	vec3 w = vPw / max(1e-4, vPw.x + vPw.y + vPw.z);
	vec4 c = vec4(0.0);
	if (w.x > 0.01) c += w.x * texture(uPatterns, vec3(p.zy, layer));
	if (w.y > 0.01) c += w.y * texture(uPatterns, vec3(p.xz, layer));
	if (w.z > 0.01) c += w.z * texture(uPatterns, vec3(p.xy, layer));
	return c;
}

vec3 daPerturb(vec3 surf_pos, vec3 surf_norm, vec2 dHdxy, float faceDirection, vec3 sigX, vec3 sigY) {
	vec3 vSigmaX = normalize(sigX);
	vec3 vSigmaY = normalize(sigY);
	vec3 vN = surf_norm;
	vec3 R1 = cross(vSigmaY, vN);
	vec3 R2 = cross(vN, vSigmaX);
	float fDet = dot(vSigmaX, R1) * faceDirection;
	vec3 vGrad = sign(fDet) * (dHdxy.x * R1 + dHdxy.y * R2);
	return normalize(abs(fDet) * surf_norm - vGrad);
}

void vertex() {
	vec3 c = vec3(daSrgbToLinear(COLOR.r), daSrgbToLinear(COLOR.g), daSrgbToLinear(COLOR.b));
	// morph colours (relative): mouths open/close with the right colour
	if (uMorphW.x != 0.0) c += daUnpackDC(CUSTOM2.x) * uMorphW.x;
	if (uMorphW.y != 0.0) c += daUnpackDC(CUSTOM2.y) * uMorphW.y;
	if (uMorphW.z != 0.0) c += daUnpackDC(CUSTOM2.z) * uMorphW.z;
	vColor = c;
	vAO = COLOR.a;
	vCav = UV2.y;
	vMat = CUSTOM0.x;
	vPMode = CUSTOM0.y;
	vPco = vec3(UV.x, UV.y, UV2.x);
	vPw = vec3(CUSTOM0.z, CUSTOM0.w, CUSTOM1.x);
	vRest = CUSTOM3.xyz;
	vFl2 = dot(CUSTOM1.yzw, CUSTOM1.yzw);
}

void fragment() {
	float viewZ = -VERTEX.z;
	bool full = daFullColor(CAMERA_VISIBLE_LAYERS);

	// DA_FADE: screen-door dither while the camera is too close to the hero (never in the shadow pass / menu scenes)
	if (uFade > 0.5 && !daIsShadowPass(PROJECTION_MATRIX)) {
		float hf = full ? 1.0 : uHeroFade;
		if (hf < 0.999 && hf <= daBayer(floor(FRAGCOORD.xy))) discard;
	}

	// color_fragment (vertex colour) + FRAG_COLOR: pattern, stitch lines, cavity
	vec4 diffuseColor = vec4(uColor, 1.0);
	diffuseColor.rgb *= vColor;
	int daM = int(vMat + 0.5);
	vec4 daA = uMatA[daM];
	vec4 daB = uMatB[daM];
	vec4 daC = uMatC[daM];
	vec4 daD = uMatD[daM];
	float daPatOk;
	vec4 daPat = daPattern(daA.z, daA.w, daPatOk);
	diffuseColor.rgb *= daPat.rgb;
	float daH = daPat.a;
	vec3 fwRest = fwidth(vRest);
	if (daC.y > 0.5 && uLineCount > 0) {
		float daAA = max(fwRest.x + fwRest.y + fwRest.z, 1e-5) * 0.6;
		for (int c = 0; c < 96; c++) {
			if (c >= uChunkCount) break;
			vec4 ch0 = texelFetch(uLines, ivec2(uLineCount * 4 + c * 2, 0), 0);
			if (distance(vRest, ch0.xyz) > ch0.w) continue;
			vec4 ch1 = texelFetch(uLines, ivec2(uLineCount * 4 + c * 2 + 1, 0), 0);
			int first = int(ch1.x);
			int cnt = int(ch1.y);
			for (int k = 0; k < 16; k++) {
				if (k >= cnt) break;
				int i = first + k;
				vec4 l0 = texelFetch(uLines, ivec2(i * 4, 0), 0);
				vec4 l3 = texelFetch(uLines, ivec2(i * 4 + 3, 0), 0);
				int mask = int(l3.y);
				if (mask != 0 && ((mask >> daM) & 1) == 0) continue;
				vec4 l1 = texelFetch(uLines, ivec2(i * 4 + 1, 0), 0);
				vec3 pa = vRest - l0.xyz;
				vec3 ba = l1.xyz - l0.xyz;
				float bl = dot(ba, ba);
				float h = clamp(dot(pa, ba) / max(bl, 1e-10), 0.0, 1.0);
				float d = length(pa - ba * h);
				if (d > l0.w + daAA * 2.0) continue;
				vec4 l2 = texelFetch(uLines, ivec2(i * 4 + 2, 0), 0);
				float s = l1.w + h * sqrt(bl);
				float dash = l2.w > 0.0 ? step(fract(s / l2.w), l3.x) : 1.0;
				float cov = (1.0 - smoothstep(l0.w - daAA, l0.w + daAA, d)) * dash;
				diffuseColor.rgb = mix(diffuseColor.rgb, l2.rgb, cov);
				daH = mix(daH, 0.9, cov);
			}
		}
	}
	float daCav = vCav * daC.w;
	diffuseColor.rgb *= 1.0 + clamp(daCav, -1.0, 0.0) * 0.75 + max(daCav, 0.0) * 0.1;
	vec3 daAlbedo = diffuseColor.rgb;

	// normal (FrontSide) + bump from the pattern height (FRAG_NORMAL); derivatives taken in uniform control flow
	vec3 N = normalize(NORMAL);
	vec3 nonPerturbedNormal = N;
	vec2 dHraw = vec2(dFdx(daH), dFdy(daH));
	vec3 sigX = dFdx(VERTEX);
	vec3 sigY = dFdy(VERTEX);
	if (daPatOk > 0.5 && daC.z > 0.0) {
		N = daPerturb(VERTEX, N, dHraw * daC.z, FRONT_FACING ? 1.0 : -1.0, sigX, sigY);
	}
	NORMAL = N;
	vec3 fl = TANGENT;
	vec3 daFlowV = vFl2 > 0.01 ? normalize(fl) : vec3(0.0);

	// PhysicalMaterial (lights_physical_fragment): roughness from FRAG_ROUGH / FRAG_METAL
	vec3 dxy = max(abs(dFdx(nonPerturbedNormal)), abs(dFdy(nonPerturbedNormal)));
	float rough = max(daA.x, 0.0525);
	rough += max(max(dxy.x, dxy.y), dxy.z);
	rough = min(rough, 1.0);
	float metal = daA.y;
	vec3 diffC = daAlbedo * (1.0 - metal);
	vec3 specB = mix(vec3(0.04), daAlbedo, metal);
	float dotNV = clamp(dot(N, VIEW), 0.0, 1.0);
	vec2 dfg = daDFGLookup(rough, dotNV);
	float EssMs = dfg.x + dfg.y;
	vec3 msComp = 1.0 + specB * (1.0 / EssMs - 1.0);
	vec3 ssD = vec3(0.0);
	vec3 msD = vec3(0.0);
	daMultiscatter(dfg, vec3(0.04), 1.0, ssD, msD);

	// FRAG_AO: AO on the indirect fully (specular squared), direct partially (in light())
	float ao = mix(1.0, vAO, uAOAmount);

	// RE_IndirectSpecular with the envMap (FRAG_IBL: iblIrradiance x uIBLDiffuse)
	vec3 wN = normalize((INV_VIEW_MATRIX * vec4(N, 0.0)).xyz);
	vec3 indirectSpec = vec3(0.0);
	vec3 indirectDiff = vec3(0.0);
	if (uEnv > 0.0) {
		vec3 iblIrr = getIBLIrradiance(wN) * uEnv * uIBLDiffuse;
		vec3 rad = getIBLRadiance(VIEW, N, rough, INV_VIEW_MATRIX) * uEnv;
		vec3 ssM = vec3(0.0);
		vec3 msM = vec3(0.0);
		daMultiscatter(dfg, daAlbedo, 1.0, ssM, msM);
		vec3 ss = mix(ssD, ssM, metal);
		vec3 ms = mix(msD, msM, metal);
		vec3 cwi = iblIrr * DA_RECIPROCAL_PI;
		indirectSpec = rad * ss + ms * cwi;
		indirectDiff = diffC * (1.0 - (ssD + msD)) * cwi;
	}
	vec3 outgoing = indirectDiff * ao + indirectSpec * ao * ao + uEmissive * uEmissiveIntensity;

	// FRAG_OUT: fresnel rim (brighter on up-facing normals) + fabric fuzz
	float nv = dotNV;
	float rim = pow(1.0 - nv, 2.6);
	rim *= 0.5 + 0.5 * clamp(wN.y + 0.55, 0.0, 1.0);
	outgoing += uRimColor * rim * uRimStrength * uRimAmbient * 1.1 * mix(1.0, vAO, 0.7);
	float fuzz = daB.z;
	if (fuzz > 0.0) outgoing += daAlbedo * fuzz * pow(1.0 - nv, 2.0) * 0.22 * uRimAmbient * vAO;

	// fog (three linear fog, as an affine map shared with light())
	float fogK = daFogF(viewZ, CAMERA_VISIBLE_LAYERS) * uFogK;
	vFogKeep = 1.0 - fogK;
	EMISSION = outgoing * vFogKeep + daFogColor * fogK;
	if (uDebug == 1) EMISSION = vec3(vAO);
	if (uDebug == 2) EMISSION = vec3(0.5 + vCav * 0.5);
	if (uDebug == 3) EMISSION = N * 0.5 + 0.5;
	if (uDebug == 4) EMISSION = vec3(clamp(dot(N, normalize(vec3(0.3, 0.8, 0.6))), 0.0, 1.0)) * 0.9 + 0.05;
	if (uDebug > 0) vFogKeep = 0.0;

	vDiff = diffC;
	vSpecB = specB;
	vRough = rough;
	vMsComp = msComp;
	vHemiK = 1.0 - ssD - msD;
	vAOi = ao;
	vWrap = daB.x;
	vSSS = daB.y;
	vAniso = daB.w;
	vSpec = daC.x;
	vSheen = daD.x;
	vSheenExp = daD.y;
	vFlowV = daFlowV;
	vAlbedo = daAlbedo;

	ALBEDO = vec3(0.0);
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	vec3 c;
	if (daIsHemi(SPECULAR_AMOUNT)) {
		// hemisphere half: getHemisphereLightIrradiance -> RE_IndirectDiffuse_Physical (x AO)
		vec3 irr = LIGHT_COLOR * DA_RECIPROCAL_PI * (0.5 + 0.5 * dot(NORMAL, LIGHT));
		c = irr * DA_RECIPROCAL_PI * vDiff * vHemiK * vAOi;
	} else {
		// RE_Direct_Physical patched (charMaterial patchLights): wrap + sss diffuse, spec scale, strand highlights
		vec3 lc = LIGHT_COLOR * DA_RECIPROCAL_PI * ATTENUATION;
		float daNL = dot(NORMAL, LIGHT);
		float dotNL = clamp(daNL, 0.0, 1.0);
		vec3 irradiance = dotNL * lc;
		vec3 daIrr = clamp((daNL + vWrap) / (1.0 + vWrap), 0.0, 1.0) * lc;
		if (vSSS > 0.0) {
			float daS = smoothstep(-0.45, 0.2, daNL) * (1.0 - smoothstep(0.05, 0.8, daNL));
			daIrr += vSSS * daS * lc * vec3(0.62, 0.16, 0.07);
		}
		vec3 H = normalize(LIGHT + VIEW);
		float dotNV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float dotNH = clamp(dot(NORMAL, H), 0.0, 1.0);
		float dotVH = clamp(dot(VIEW, H), 0.0, 1.0);
		float alpha = vRough * vRough;
		vec3 F = F_Schlick(vSpecB, 1.0, dotVH);
		vec3 spec = irradiance * (F * (V_GGX_SmithCorrelated(alpha, dotNL, dotNV) * D_GGX(alpha, dotNH))) * vMsComp * vSpec;
		if (vAniso > 0.0 && dot(vFlowV, vFlowV) > 0.1) {
			vec3 T = normalize(vFlowV - NORMAL * dot(vFlowV, NORMAL));
			vec3 T1 = normalize(T + NORMAL * 0.12);
			vec3 T2 = normalize(T - NORMAL * 0.18);
			float th1 = dot(T1, H);
			float th2 = dot(T2, H);
			float s1 = pow(sqrt(max(0.0, 1.0 - th1 * th1)), 90.0);
			float s2 = pow(sqrt(max(0.0, 1.0 - th2 * th2)), 26.0);
			float att = smoothstep(-0.1, 0.3, daNL);
			spec += lc * att * vAniso * (s1 * 0.1 + s2 * 0.09 * vAlbedo * 2.2);
		}
		if (vSheen > 0.0 && dot(vFlowV, vFlowV) > 0.1) {
			// molded-toy hair sheen: ONE broad soft glossy band across the flow (low-exponent Kajiya-Kay), no strand lines
			vec3 Ts = normalize(vFlowV - NORMAL * dot(vFlowV, NORMAL));
			float ths = dot(Ts, H);
			float sb = pow(sqrt(max(0.0, 1.0 - ths * ths)), vSheenExp);
			float atts = smoothstep(-0.05, 0.35, daNL);
			spec += lc * atts * vSheen * sb * mix(vAlbedo * 3.5, vec3(1.0), 0.3) * 0.22;
		}
		vec3 Fd = F_Schlick(vec3(0.04), 1.0, dotVH);
		vec3 diff = daIrr * DA_RECIPROCAL_PI * vDiff * (1.0 - Fd);
		c = diff * mix(1.0, vAOi, 0.55) + spec * mix(1.0, vAOi, 0.8);
	}
	SPECULAR_LIGHT += c * vFogKeep;
}
