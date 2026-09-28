// Rigid character attachment material (port of src/art/charMaterial.js attachMaterial: MeshStandardMaterial /
// MeshPhysicalMaterial (clearcoat) + wrap + sss + fresnel rim + IBL diffuse scale). Eyes, lids, lashes, glasses,
// aviators, hoops, googly eyes, casters, badges... char_material.gd builds the variants:
//   shader_type spatial; render_mode <cull_back|cull_front|cull_disabled>, <depth_draw_opaque|depth_draw_never>,
//   blend_mix, fog_disabled, shadows_disabled; #define DA_TRANSPARENT / DA_BACK (BackSide) / DA_CC (physical clearcoat)
//   #include "res://shaders/char_attach.gdshaderinc"
// Lighting convention of shaders/da_common.gdshaderinc (see char.gdshader).
#include "res://shaders/da_common.gdshaderinc"

uniform vec3 uColor : source_color = vec3(1.0);
uniform float uOpacity = 1.0;
uniform float uRough = 0.5;
uniform float uMetal = 0.0;
uniform vec3 uEmissive : source_color = vec3(0.0);
uniform float uEmissiveIntensity = 1.0;
uniform float uEnv = 0.0;          // envMapIntensity (0: no envMap)
uniform float uVColor = 0.0;       // vertexColors
uniform vec3 uRimColor : source_color = vec3(1.0, 0.851, 0.627);
uniform float uRimStrength = 0.3;
uniform float uWrapA = 0.45;
uniform float uSSSA = 0.0;
uniform float uIBLA = 0.3;
uniform float uClearcoat = 0.0;
uniform float uClearcoatRough = 0.05;
uniform float uFogK = 1.0;
// map (DAMaterial facade names): uMapMode 0 none, 1 repeat+linear, 2 clamp+linear, 3 repeat+nearest, 4 clamp+nearest;
// uMapFlip 1 = three's flipY (canvas textures stored top row first); GLB textures use plain glTF UVs (0).
uniform int uMapMode = 0;
uniform float uMapFlip = 0.0;
uniform sampler2D mapRL : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mapCL : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D mapRN : source_color, filter_nearest, repeat_enable;
uniform sampler2D mapCN : source_color, filter_nearest, repeat_disable;

// fragment -> light
varying vec3 vDiff;
varying vec3 vSpecB;
varying float vRough;
varying vec3 vMsComp;
varying vec3 vHemiK;
varying float vFogKeep;
varying float vCcKeep;
varying float vCcRough;

vec4 daMapSample(vec2 uv) {
	vec2 st = vec2(uv.x, uMapFlip > 0.5 ? 1.0 - uv.y : uv.y);
	if (uMapMode == 1) return texture(mapRL, st);
	if (uMapMode == 2) return texture(mapCL, st);
	if (uMapMode == 3) return texture(mapRN, st);
	return texture(mapCN, st);
}

void fragment() {
	float viewZ = -VERTEX.z;
	vec4 diffuseColor = vec4(uColor, uOpacity);
	if (uMapMode > 0) diffuseColor *= daMapSample(UV);
	if (uVColor > 0.5) diffuseColor.rgb *= COLOR.rgb;

	vec3 N = normalize(NORMAL);
#ifdef DA_BACK
	N = -N;
#endif
	NORMAL = N;

	vec3 dxy = max(abs(dFdx(N)), abs(dFdy(N)));
	float geoRough = max(max(dxy.x, dxy.y), dxy.z);
	float rough = min(max(uRough, 0.0525) + geoRough, 1.0);
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

	vec3 outgoing = vec3(0.0);
	vec3 ccIndirect = vec3(0.0);
	vec3 wN = normalize((INV_VIEW_MATRIX * vec4(N, 0.0)).xyz);
	if (uEnv > 0.0) {
		vec3 iblIrr = getIBLIrradiance(wN) * uEnv * uIBLA;
		vec3 rad = getIBLRadiance(VIEW, N, rough, INV_VIEW_MATRIX) * uEnv;
		vec3 ssM = vec3(0.0);
		vec3 msM = vec3(0.0);
		daMultiscatter(dfg, diffuseColor.rgb, 1.0, ssM, msM);
		vec3 ss = mix(ssD, ssM, metal);
		vec3 ms = mix(msD, msM, metal);
		vec3 cwi = iblIrr * DA_RECIPROCAL_PI;
		outgoing = rad * ss + ms * cwi + diffC * (1.0 - (ssD + msD)) * cwi;
	}
	outgoing += uEmissive * uEmissiveIntensity;

	// MeshPhysicalMaterial clearcoat: outgoing * (1 - cc Fcc) + clearcoat specular (direct in light())
	float ccKeep = 1.0;
	float ccR = 0.0525;
#ifdef DA_CC
	ccR = min(max(uClearcoatRough, 0.0525) + geoRough, 1.0);
	vec3 Fcc = F_Schlick(vec3(0.04), 1.0, dotNV);
	ccKeep = 1.0 - uClearcoat * Fcc.x;
	if (uEnv > 0.0) {
		vec3 ccRad = getIBLRadiance(VIEW, N, ccR, INV_VIEW_MATRIX) * uEnv;
		vec2 fab = daDFGLookup(ccR, dotNV);
		ccIndirect = ccRad * (vec3(0.04) * fab.x + fab.y);
	}
	outgoing = outgoing * ccKeep + ccIndirect * uClearcoat;
#endif

	// ATT_FRAG_OUT: fresnel rim
	float rim = pow(1.0 - dotNV, 2.6);
	outgoing += uRimColor * rim * uRimStrength * uRimAmbient * 1.5;

	float fogK = daFogF(viewZ, CAMERA_VISIBLE_LAYERS) * uFogK;
	vFogKeep = 1.0 - fogK;
	EMISSION = outgoing * vFogKeep + daFogColor * fogK;

	vDiff = diffC;
	vSpecB = specB;
	vRough = rough;
	vMsComp = msComp;
	vHemiK = 1.0 - ssD - msD;
	vCcKeep = ccKeep;
	vCcRough = ccR;

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
		vec3 irr = LIGHT_COLOR * DA_RECIPROCAL_PI * (0.5 + 0.5 * dot(NORMAL, LIGHT));
		c = irr * DA_RECIPROCAL_PI * vDiff * vHemiK * vCcKeep;
	} else {
		vec3 lc = LIGHT_COLOR * DA_RECIPROCAL_PI * ATTENUATION;
		float daNL = dot(NORMAL, LIGHT);
		float dotNL = clamp(daNL, 0.0, 1.0);
		vec3 irradiance = dotNL * lc;
		vec3 daIrr = clamp((daNL + uWrapA) / (1.0 + uWrapA), 0.0, 1.0) * lc;
		if (uSSSA > 0.0) {
			float daS = smoothstep(-0.45, 0.2, daNL) * (1.0 - smoothstep(0.05, 0.8, daNL));
			daIrr += uSSSA * daS * lc * vec3(0.62, 0.16, 0.07);
		}
		vec3 H = normalize(LIGHT + VIEW);
		float dotNV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float dotNH = clamp(dot(NORMAL, H), 0.0, 1.0);
		float dotVH = clamp(dot(VIEW, H), 0.0, 1.0);
		float alpha = vRough * vRough;
		vec3 F = F_Schlick(vSpecB, 1.0, dotVH);
		vec3 spec = irradiance * (F * (V_GGX_SmithCorrelated(alpha, dotNL, dotNV) * D_GGX(alpha, dotNH))) * vMsComp;
		vec3 Fd = F_Schlick(vec3(0.04), 1.0, dotVH);
		c = (spec + daIrr * DA_RECIPROCAL_PI * vDiff * (1.0 - Fd)) * vCcKeep;
#ifdef DA_CC
		float ca = vCcRough * vCcRough;
		vec3 Fc = F_Schlick(vec3(0.04), 1.0, dotVH);
		c += irradiance * (Fc * (V_GGX_SmithCorrelated(ca, dotNL, dotNV) * D_GGX(ca, dotNH))) * uClearcoat;
#endif
	}
	SPECULAR_LIGHT += c * vFogKeep;
}
