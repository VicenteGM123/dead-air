// DEAD AIR shared shader library (godot-core). Port of the three.js pieces every game material shares:
//   - the GLOBAL uniforms of materials.js (mats.uniforms) as Godot global shader parameters (declared in
//     project.godot [shader_globals]; materials.gd writes them through RenderingServer), JS names kept:
//     uSatEnv uAmber uWaveOrigin uWaveRadius uTime uHeroFade uRimAmbient uOccRect uOccZ uOccAmt uOccBox0/1 uOccWall0/1
//     plus engine-only ones: daOccCam (main camera position: the occlusion fade only applies to the gameplay main
//     render, like render.js _occBegin), daFogColor (LINEAR) / daFogNear / daFogFar (THREE.Fog of game.scene; all
//     DEAD AIR shaders apply it themselves with render_mode fog_disabled), daEnvMap (the PMREM RoomEnvironment
//     cubeUV atlas of materials.js, 768x1024 RGBA16F, sampled with an exact port of three's textureCubeUV) and
//     daDFG (three r186's 16x16 DFG LUT).
//   - the camera flags: CAMERA_VISIBLE_LAYERS bit 19 = DA_CAM_FULLCOLOR (menu scenes: no pre-power grade / wave /
//     hero fade, menu.js _fullColor), bit 18 = DA_CAM_NOFOG (worlds without game.scene's fog).
//   - the hemisphere light: two DirectionalLight3D with light_specular == 0.0 (lights.gd DAHemi). In light():
//     if (daIsHemi(SPECULAR_AMOUNT)) irradiance = LIGHT_COLOR / PI * (0.5 + 0.5 * dot(NORMAL, LIGHT)) (the pair sums
//     to three's getHemisphereLightIrradiance) and it goes through RE_IndirectDiffuse; any other light is three's
//     directLight with color = LIGHT_COLOR / PI * ATTENUATION (Godot's LIGHT_COLOR is colour * energy * PI; light
//     energies are three intensities; OmniLight3D omni_attenuation = three decay).
//   - helpers: Bayer dither, camera occlusion (daOccDrop), the pre-power grade + Sign-On wave as an affine colour
//     transform (daGradeSetup / daGrade: applied to every light contribution in light() and to the emission, which is
//     exactly three's post-lighting patch because it is linear in the lit colour), three's linear fog, the physical
//     BRDF pieces (F_Schlick, V_GGX_SmithCorrelated, D_GGX, DFG multi-scattering) and the IBL (textureCubeUV,
//     getIBLRadiance, getIBLIrradiance).
// Materials write every lit term to SPECULAR_LIGHT / EMISSION with ALBEDO = 0, METALLIC = 0, SPECULAR = 0, so Godot
// adds no ambient light or reflection of its own (Godot multiplies DIFFUSE_LIGHT by ALBEDO).

global uniform float uSatEnv;
global uniform float uAmber;
global uniform vec3 uWaveOrigin;
global uniform float uWaveRadius;
global uniform float uTime;
global uniform float uHeroFade;
global uniform float uRimAmbient;
global uniform vec4 uOccRect;
global uniform vec4 uOccZ;
global uniform float uOccAmt;
global uniform mat4 uOccBox0;
global uniform mat4 uOccBox1;
global uniform mat4 uOccWall0;
global uniform mat4 uOccWall1;
global uniform vec3 daOccCam;
global uniform vec3 daFogColor;
global uniform float daFogNear;
global uniform float daFogFar;
global uniform sampler2D daEnvMap : filter_linear, repeat_disable;
global uniform sampler2D daDFG : filter_linear, repeat_disable;

#define DA_PI 3.141592653589793
#define DA_RECIPROCAL_PI 0.3183098861837907
#define DA_CAM_NOFOG 262144u
#define DA_CAM_FULLCOLOR 524288u

// The Sign-On wave's colour bars (PAL.BARS, linear, the exact float32 values of materials.js BARS_GLSL).
const vec3 uBars[7] = vec3[7](vec3(0.846873224, 0.846873224, 0.846873224), vec3(0.904661179, 0.745404184, 0.0423114114),
	vec3(0.0497065671, 0.672443151, 0.745404184), vec3(0.0843762085, 0.644479692, 0.0684781671),
	vec3(0.672443151, 0.0781874210, 0.672443151), vec3(0.775822222, 0.0630100146, 0.0423114114),
	vec3(0.0423114114, 0.0975873470, 0.775822222));

// ------------------------------------------------------------------------------------------------ camera / passes
bool daFullColor(uint camLayers) {
	return (camLayers & DA_CAM_FULLCOLOR) != 0u;
}

// Directional shadow maps render with an orthographic projection (three's shadow depth material never runs the
// fades): skip the screen-door discards there.
bool daIsShadowPass(mat4 proj) {
	return proj[3][3] > 0.5;
}

bool daIsHemi(float specularAmount) {
	return specularAmount == 0.0;
}

// ------------------------------------------------------------------------------------------------ dither / occlusion
// 4x4 ordered-dither threshold (screen-door fades: hero fade, camera occlusion). p = floor(FRAGCOORD.xy).
float daBayer(vec2 p) {
	const float M[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	ivec2 q = ivec2(mod(p, 4.0));
	return (M[q.y * 4 + q.x] + 0.5) / 16.0;
}

float daOccBox(vec4 b0, vec4 b1, vec3 p) {
	vec3 d = max(b0.xyz - p, p - b1.xyz);
	return b0.w * (1.0 - smoothstep(0.0, 0.15, max(max(d.x, d.y), d.z)));
}

bool daOccIn(vec4 b0, vec4 b1, vec3 p) {
	return b0.w > 0.5 && all(greaterThanEqual(p, b0.xyz)) && all(lessThanEqual(p, b1.xyz));
}

// Camera occlusion (materials.js OCC_PARS): 0..1 fraction of pixels to drop. uOccRect is in FRAGCOORD pixels
// (top-left origin; render.gd converts). camPos = CAMERA_POSITION_WORLD: only the gameplay main camera fades.
float daOcc(float viewZ, vec3 wp, vec2 fragCoord, vec3 camPos) {
	if (uOccAmt <= 0.0 || wp.y < uOccZ.w || distance(camPos, daOccCam) > 0.001) return 0.0;
	float front = 1.0 - smoothstep(uOccZ.x, uOccZ.x + uOccZ.y, viewZ);
	if (front <= 0.0) return 0.0;
	vec2 q = (fragCoord - uOccRect.xy) * uOccRect.zw;
	float k = 1.0 - smoothstep(0.35, 1.0, dot(q, q));
	k = max(k, max(max(daOccBox(uOccBox0[0], uOccBox0[1], wp), daOccBox(uOccBox0[2], uOccBox0[3], wp)),
		max(daOccBox(uOccBox1[0], uOccBox1[1], wp), daOccBox(uOccBox1[2], uOccBox1[3], wp))));
	if (k <= 0.0) return 0.0;
	if (daOccIn(uOccWall0[0], uOccWall0[1], wp) || daOccIn(uOccWall0[2], uOccWall0[3], wp) ||
		daOccIn(uOccWall1[0], uOccWall1[1], wp) || daOccIn(uOccWall1[2], uOccWall1[3], wp)) return 0.0;
	return uOccAmt * front * k;
}

bool daOccDrop(float viewZ, vec3 wp, vec2 fragCoord, vec3 camPos) {
	float o = daOcc(viewZ, wp, fragCoord, camPos);
	return o > 0.0 && o > daBayer(floor(fragCoord));
}

// ------------------------------------------------------------------------------------------------ fog
// three's linear THREE.Fog on view depth (fog_fragment: smoothstep(fogNear, fogFar, vFogDepth)).
float daFogF(float viewZ, uint camLayers) {
	if ((camLayers & DA_CAM_NOFOG) != 0u) return 0.0;
	return smoothstep(daFogNear, daFogFar, viewZ);
}

// ------------------------------------------------------------------------------------------------ grade
// materials.js FRAG_OUT (pre-power desaturation uSatEnv, amber tint uAmber, Sign-On wave) followed by the fog,
// written as the affine map  final = daGrade(lit, g) + K  (every step is linear in the lit colour).
// keep = keepColor (uKeep), full = daFullColor(camera). fogK = fog factor * uFogK. Returns g, writes K.
vec4 daGradeSetup(vec3 wp, bool keep, bool full, float fogK, out vec3 K) {
	float sat = 1.0;
	float amb = 0.0;
	float bs = 1.0;
	vec3 k = vec3(0.0);
	if (!keep) {
		float satEnv = full ? 1.0 : uSatEnv;
		float amber = full ? 0.0 : uAmber;
		float wr = full ? -1.0 : uWaveRadius;
		float d = distance(wp, uWaveOrigin);
		float kk = wr < 0.0 ? 0.0 : smoothstep(-0.5, 0.5, wr - d);
		sat = mix(satEnv, 1.0, kk);
		amb = mix(amber, 0.0, kk);
		if (wr >= 0.0) {
			float band = 1.0 - smoothstep(0.3, 0.5, abs(d - wr));
			if (band > 0.0) {
				float s = mod(floor((wp.x - wp.z) * 1.6 + wp.y * 0.8 - uTime * 5.0), 7.0);
				bs = 1.0 - band * 0.85;
				k = uBars[int(s)] * 2.4 * (band * 0.85);
			}
		}
	}
	K = k * (1.0 - fogK) + daFogColor * fogK;
	return vec4(sat, amb, bs, 1.0 - fogK);
}

vec3 daGrade(vec3 c, vec4 g) {
	float L = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(L), c, g.x);
	c = mix(c, vec3(L) * vec3(1.45, 0.98, 0.45), g.y);
	return c * (g.z * g.w);
}

// Stepped shading (materials.js daShade).
float daShade(float x, float steps) {
	if (steps < 0.5) return x;
	float s = x * steps;
	return (floor(s) + smoothstep(0.4, 0.6, fract(s))) / steps;
}

// ------------------------------------------------------------------------------------------------ BRDF (three r186)
vec3 F_Schlick(vec3 f0, float f90, float dotVH) {
	float fresnel = exp2((-5.55473 * dotVH - 6.98316) * dotVH);
	return f0 * (1.0 - fresnel) + (f90 * fresnel);
}

float V_GGX_SmithCorrelated(float alpha, float dotNL, float dotNV) {
	float a2 = alpha * alpha;
	float gv = dotNL * sqrt(a2 + (1.0 - a2) * dotNV * dotNV);
	float gl = dotNV * sqrt(a2 + (1.0 - a2) * dotNL * dotNL);
	return 0.5 / max(gv + gl, 1e-6);
}

float D_GGX(float alpha, float dotNH) {
	float a2 = alpha * alpha;
	float denom = dotNH * dotNH * (a2 - 1.0) + 1.0;
	return DA_RECIPROCAL_PI * a2 / (denom * denom);
}

vec2 daDFGLookup(float roughness, float dotNV) {
	return textureLod(daDFG, vec2(roughness, dotNV), 0.0).rg;
}

// three computeMultiscattering (Fdez-Aguera).
void daMultiscatter(vec2 fab, vec3 specularColor, float specularF90, inout vec3 singleScatter, inout vec3 multiScatter) {
	vec3 Fr = specularColor;
	vec3 FssEss = Fr * fab.x + specularF90 * fab.y;
	float Ess = fab.x + fab.y;
	float Ems = 1.0 - Ess;
	vec3 Favg = Fr + (1.0 - Fr) * 0.047619;
	vec3 Fms = FssEss * Favg / (1.0 - Ems * Favg);
	singleScatter += FssEss;
	multiScatter += Fms * Ems;
}

// ------------------------------------------------------------------------------------------------ IBL (cubeUV)
// Exact port of three's cube_uv_reflection_fragment for the RoomEnvironment PMREM (cubeSize 256).
#define cubeUV_minMipLevel 4.0
#define cubeUV_minTileSize 16.0
#define CUBEUV_TEXEL_WIDTH 0.0013020833333333333
#define CUBEUV_TEXEL_HEIGHT 0.0009765625
#define CUBEUV_MAX_MIP 8.0

float daCubeFace(vec3 direction) {
	vec3 absDirection = abs(direction);
	float face = -1.0;
	if (absDirection.x > absDirection.z) {
		if (absDirection.x > absDirection.y)
			face = direction.x > 0.0 ? 0.0 : 3.0;
		else
			face = direction.y > 0.0 ? 1.0 : 4.0;
	} else {
		if (absDirection.z > absDirection.y)
			face = direction.z > 0.0 ? 2.0 : 5.0;
		else
			face = direction.y > 0.0 ? 1.0 : 4.0;
	}
	return face;
}

vec2 daCubeUV(vec3 direction, float face) {
	vec2 uv;
	if (face == 0.0) {
		uv = vec2(direction.z, direction.y) / abs(direction.x);
	} else if (face == 1.0) {
		uv = vec2(-direction.x, -direction.z) / abs(direction.y);
	} else if (face == 2.0) {
		uv = vec2(-direction.x, direction.y) / abs(direction.z);
	} else if (face == 3.0) {
		uv = vec2(-direction.z, direction.y) / abs(direction.x);
	} else if (face == 4.0) {
		uv = vec2(-direction.x, direction.z) / abs(direction.y);
	} else {
		uv = vec2(direction.x, direction.y) / abs(direction.z);
	}
	return 0.5 * (uv + 1.0);
}

vec3 daBilinearCubeUV(vec3 direction, float mipInt) {
	float face = daCubeFace(direction);
	float filterInt = max(cubeUV_minMipLevel - mipInt, 0.0);
	mipInt = max(mipInt, cubeUV_minMipLevel);
	float faceSize = exp2(mipInt);
	vec2 uv = daCubeUV(direction, face) * (faceSize - 2.0) + 1.0;
	if (face > 2.0) {
		uv.y += faceSize;
		face -= 3.0;
	}
	uv.x += face * faceSize;
	uv.x += filterInt * 3.0 * cubeUV_minTileSize;
	uv.y += 4.0 * (exp2(CUBEUV_MAX_MIP) - faceSize);
	uv.x *= CUBEUV_TEXEL_WIDTH;
	uv.y *= CUBEUV_TEXEL_HEIGHT;
	return textureLod(daEnvMap, uv, 0.0).rgb;
}

float daRoughnessToMip(float roughness) {
	float mip = 0.0;
	if (roughness >= 0.8) {
		mip = (1.0 - roughness) * (-1.0 + 2.0) / (1.0 - 0.8) - 2.0;
	} else if (roughness >= 0.4) {
		mip = (0.8 - roughness) * (2.0 + 1.0) / (0.8 - 0.4) - 1.0;
	} else if (roughness >= 0.305) {
		mip = (0.4 - roughness) * (3.0 - 2.0) / (0.4 - 0.305) + 2.0;
	} else if (roughness >= 0.21) {
		mip = (0.305 - roughness) * (4.0 - 3.0) / (0.305 - 0.21) + 3.0;
	} else {
		mip = -2.0 * log2(1.16 * roughness);
	}
	return mip;
}

vec3 textureCubeUV(vec3 sampleDir, float roughness) {
	float mip = clamp(daRoughnessToMip(roughness), -2.0, CUBEUV_MAX_MIP);
	float mipF = fract(mip);
	float mipInt = floor(mip);
	vec3 color0 = daBilinearCubeUV(sampleDir, mipInt);
	if (mipF == 0.0) {
		return color0;
	}
	vec3 color1 = daBilinearCubeUV(sampleDir, mipInt + 1.0);
	return mix(color0, color1, mipF);
}

// three getIBLIrradiance (x envMapIntensity by the caller). worldNormal: world-space normal.
vec3 getIBLIrradiance(vec3 worldNormal) {
	return DA_PI * textureCubeUV(worldNormal, 1.0);
}

// three getIBLRadiance (x envMapIntensity by the caller). viewDir / normal in view space.
vec3 getIBLRadiance(vec3 viewDir, vec3 normal, float roughness, mat4 invView) {
	vec3 reflectVec = reflect(-viewDir, normal);
	float r4 = roughness * roughness;
	r4 *= r4;
	reflectVec = normalize(mix(reflectVec, normal, r4));
	reflectVec = normalize((invView * vec4(reflectVec, 0.0)).xyz);
	return textureCubeUV(reflectVec, roughness);
}
