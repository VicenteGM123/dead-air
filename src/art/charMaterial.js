// Character material for baked SDF characters: MeshStandardMaterial patched with onBeforeCompile.
//   createCharMaterial({ header, rim, envMap, globals, heroFade }) -> material (one per character type, shared by
//   the skinned body and its rigid parts). Per-vertex inputs from the baker: color (vertex color), aux (ao, cavity,
//   material id, pattern mode), pco (pattern coords), pw (triplanar weights), flow (hair strand direction).
// Per-material params (header.materials[name]): color, rough, metal, wrap, sss (skin scatter), fuzz (fabric sheen),
//   aniso (hair strand highlight), sheen + sheenExp (molded-toy hair: one broad glossy band across the flow),
//   spec (specular scale), lines (draw stitch lines), bump, cav (cavity strength), pattern.
// Shading: half-lambert wrap, warm subsurface in the terminator, baked AO + cavity, fabric patterns sampled in REST
// space (never swim), stitch/seam lines, Kajiya-Kay strand highlights, fresnel rim (warm heroes / cyan zombies).
//   attachMaterial(opts) -> simpler toon-like material for rigid attachments (eyes, glasses, lids).
import * as THREE from 'three';
import { patternLayers } from './patterns.js';

const NMAT = 24;

const VERT_PARS = /* glsl */`
#include <common>
attribute vec4 aux;
attribute vec3 pco;
attribute vec4 pw;
attribute vec4 flow;
varying float vAO;
varying float vCav;
flat varying float vMat;
varying float vPMode;
varying vec3 vPco;
varying vec3 vPw;
varying vec3 vRest;
varying vec3 vFlowV;
`;

const VERT_SKIN = /* glsl */`
#include <skinnormal_vertex>
{
  vec3 daFl = flow.xyz;
  #ifdef USE_SKINNING
    daFl = ( skinMatrix * vec4( daFl, 0.0 ) ).xyz;
  #endif
  vFlowV = normalMatrix * daFl;
  vAO = aux.x / 255.0;
  vCav = ( aux.y - 128.0 ) / 127.0;
  vMat = aux.z;
  vPMode = aux.w;
  vPco = pco;
  vPw = pw.xyz;
  vRest = position;
}
`;

// Morph colors (expression morphs carry vertex-color deltas). three r186's chunk adds a vec3 to the vec4 vColor
// (compile error), so we use our own rgb-only version.
const MORPH_COLOR = /* glsl */`
#if defined( USE_MORPHCOLORS )
  vColor *= morphTargetBaseInfluence;
  for ( int i = 0; i < MORPHTARGETS_COUNT; i ++ ) {
    if ( morphTargetInfluences[ i ] != 0.0 ) vColor.rgb += getMorph( gl_VertexID, i, 2 ).rgb * morphTargetInfluences[ i ];
  }
#endif
`;

const FRAG_PARS = /* glsl */`
#include <common>
#define DA_NMAT ${NMAT}
uniform vec4 uMatA[ DA_NMAT ]; // rough, metal, pattern layer (-1 none), pattern scale (m)
uniform vec4 uMatB[ DA_NMAT ]; // wrap, sss, fuzz, aniso
uniform vec4 uMatC[ DA_NMAT ]; // spec, lines, bump, cavity
uniform vec4 uMatD[ DA_NMAT ]; // sheen, sheenExp, -, -
uniform highp sampler2DArray uPatterns;
uniform highp sampler2D uLines;
uniform int uLineCount;
uniform int uChunkCount;
uniform vec3 uRimColor;
uniform float uRimStrength;
uniform float uRimAmbient;
uniform float uHeroFade;
uniform float uAOAmount;
uniform int uDebug;
uniform float uIBLDiffuse;
varying float vAO;
varying float vCav;
flat varying float vMat;
varying float vPMode;
varying vec3 vPco;
varying vec3 vPw;
varying vec3 vRest;
varying vec3 vFlowV;
float daWrap = 0.5;
float daSSS = 0.0;
float daAniso = 0.0;
float daSpec = 1.0;
float daSheen = 0.0;
float daSheenExp = 14.0;
vec3 daFlowV = vec3( 0.0 );
vec3 daAlbedo = vec3( 1.0 );
float daBayer( vec2 p ) {
  const mat4 M = mat4( 0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0 );
  ivec2 q = ivec2( mod( p, 4.0 ) );
  return ( M[ q.y ][ q.x ] + 0.5 ) / 16.0;
}
vec4 daPattern( float layer, float scale, out float ok ) {
  ok = 0.0;
  if ( layer < -0.5 ) return vec4( 1.0, 1.0, 1.0, 0.5 );
  ok = 1.0;
  vec3 p = vPco / scale;
  if ( vPMode > 0.5 ) return texture( uPatterns, vec3( p.xy, layer ) );
  vec3 w = vPw / max( 1e-4, vPw.x + vPw.y + vPw.z );
  vec4 c = vec4( 0.0 );
  if ( w.x > 0.01 ) c += w.x * texture( uPatterns, vec3( p.zy, layer ) );
  if ( w.y > 0.01 ) c += w.y * texture( uPatterns, vec3( p.xz, layer ) );
  if ( w.z > 0.01 ) c += w.z * texture( uPatterns, vec3( p.xy, layer ) );
  return c;
}
vec3 daPerturb( vec3 surf_pos, vec3 surf_norm, vec2 dHdxy, float faceDirection ) {
  vec3 vSigmaX = normalize( dFdx( surf_pos.xyz ) );
  vec3 vSigmaY = normalize( dFdy( surf_pos.xyz ) );
  vec3 vN = surf_norm;
  vec3 R1 = cross( vSigmaY, vN );
  vec3 R2 = cross( vN, vSigmaX );
  float fDet = dot( vSigmaX, R1 ) * faceDirection;
  vec3 vGrad = sign( fDet ) * ( dHdxy.x * R1 + dHdxy.y * R2 );
  return normalize( abs( fDet ) * surf_norm - vGrad );
}
`;

// Pattern, stitch lines, cavity: after the vertex color multiply.
const FRAG_COLOR = /* glsl */`
#include <color_fragment>
int daM = int( vMat + 0.5 );
vec4 daA = uMatA[ daM ];
vec4 daB = uMatB[ daM ];
vec4 daC = uMatC[ daM ];
daWrap = daB.x; daSSS = daB.y; daAniso = daB.w; daSpec = daC.x;
daSheen = uMatD[ daM ].x; daSheenExp = uMatD[ daM ].y;
float daPatOk;
vec4 daPat = daPattern( daA.z, daA.w, daPatOk );
diffuseColor.rgb *= daPat.rgb;
float daH = daPat.a;
if ( daC.y > 0.5 && uLineCount > 0 ) {
  float daAA = max( fwidth( vRest.x ) + fwidth( vRest.y ) + fwidth( vRest.z ), 1e-5 ) * 0.6;
  for ( int c = 0; c < 96; c++ ) {
   if ( c >= uChunkCount ) break;
   vec4 ch0 = texelFetch( uLines, ivec2( uLineCount * 4 + c * 2, 0 ), 0 );
   if ( distance( vRest, ch0.xyz ) > ch0.w ) continue;
   vec4 ch1 = texelFetch( uLines, ivec2( uLineCount * 4 + c * 2 + 1, 0 ), 0 );
   int first = int( ch1.x ), cnt = int( ch1.y );
   for ( int k = 0; k < 16; k++ ) {
    if ( k >= cnt ) break;
    int i = first + k;
    vec4 l0 = texelFetch( uLines, ivec2( i * 4, 0 ), 0 );
    vec4 l3 = texelFetch( uLines, ivec2( i * 4 + 3, 0 ), 0 );
    int mask = int( l3.y );
    if ( mask != 0 && ( ( mask >> daM ) & 1 ) == 0 ) continue;
    vec4 l1 = texelFetch( uLines, ivec2( i * 4 + 1, 0 ), 0 );
    vec3 pa = vRest - l0.xyz, ba = l1.xyz - l0.xyz;
    float bl = dot( ba, ba );
    float h = clamp( dot( pa, ba ) / max( bl, 1e-10 ), 0.0, 1.0 );
    float d = length( pa - ba * h );
    if ( d > l0.w + daAA * 2.0 ) continue;
    vec4 l2 = texelFetch( uLines, ivec2( i * 4 + 2, 0 ), 0 );
    float s = l1.w + h * sqrt( bl );
    float dash = l2.w > 0.0 ? step( fract( s / l2.w ), l3.x ) : 1.0;
    float cov = ( 1.0 - smoothstep( l0.w - daAA, l0.w + daAA, d ) ) * dash;
    diffuseColor.rgb = mix( diffuseColor.rgb, l2.rgb, cov );
    daH = mix( daH, 0.9, cov );
   }
  }
}
float daCav = vCav * daC.w;
diffuseColor.rgb *= 1.0 + clamp( daCav, -1.0, 0.0 ) * 0.75 + max( daCav, 0.0 ) * 0.1;
daAlbedo = diffuseColor.rgb;
`;

const FRAG_ROUGH = /* glsl */`
float roughnessFactor = daA.x;
`;
const FRAG_METAL = /* glsl */`
float metalnessFactor = daA.y;
`;

const FRAG_NORMAL = /* glsl */`
#include <normal_fragment_maps>
if ( daPatOk > 0.5 && daC.z > 0.0 ) {
  vec2 dH = vec2( dFdx( daH ), dFdy( daH ) ) * daC.z;
  normal = daPerturb( - vViewPosition, normal, dH, faceDirection );
}
{
  vec3 fl = vFlowV;
  float fl2 = dot( fl, fl );
  daFlowV = fl2 > 0.01 ? fl * inversesqrt( fl2 ) : vec3( 0.0 );
}
`;

// AO: indirect fully, direct partially; cavity already in albedo.
const FRAG_IBL = /* glsl */`
#include <lights_fragment_maps>
#if defined( USE_ENVMAP ) && defined( RE_IndirectDiffuse )
  iblIrradiance *= uIBLDiffuse;
#endif
`;
const FRAG_AO = /* glsl */`
{
  float ao = mix( 1.0, vAO, uAOAmount );
  reflectedLight.indirectDiffuse *= ao;
  reflectedLight.indirectSpecular *= ao * ao;
  reflectedLight.directDiffuse *= mix( 1.0, ao, 0.55 );
  reflectedLight.directSpecular *= mix( 1.0, ao, 0.8 );
}
#include <aomap_fragment>
`;

const FRAG_OUT = /* glsl */`
#ifdef DA_FADE
  if ( uHeroFade < 0.999 && uHeroFade <= daBayer( floor( gl_FragCoord.xy ) ) ) discard;
#endif
{
  float nv = saturate( dot( normal, normalize( vViewPosition ) ) );
  float rim = pow( 1.0 - nv, 2.6 );
  vec3 wn = inverseTransformDirection( normal, viewMatrix );
  rim *= 0.5 + 0.5 * saturate( wn.y + 0.55 );
  outgoingLight += uRimColor * rim * uRimStrength * uRimAmbient * 1.1 * mix( 1.0, vAO, 0.7 );
  float fuzz = daB.z;
  if ( fuzz > 0.0 ) outgoingLight += daAlbedo * fuzz * pow( 1.0 - nv, 2.0 ) * 0.22 * uRimAmbient * vAO;
}
if ( uDebug == 1 ) outgoingLight = vec3( vAO );
if ( uDebug == 2 ) outgoingLight = vec3( 0.5 + vCav * 0.5 );
if ( uDebug == 3 ) outgoingLight = normal * 0.5 + 0.5;
if ( uDebug == 4 ) outgoingLight = vec3( saturate( dot( normal, normalize( vec3( 0.3, 0.8, 0.6 ) ) ) ) ) * 0.9 + 0.05;
#include <opaque_fragment>
`;

function patchLights(src) {
  const a = 'vec3 irradiance = dotNL * directLight.color;';
  const b = 'reflectedLight.directDiffuse += irradiance * BRDF_Lambert( material.diffuseContribution ) * ( 1.0 - F );';
  const c = 'reflectedLight.directSpecular += irradiance * specularBRDF * material.multiScatteringCompensation;';
  if (!src.includes(a) || !src.includes(b) || !src.includes(c)) {
    console.warn('[charMaterial] three.js lighting chunk changed; wrap/sss/aniso disabled');
    return src;
  }
  return src
    .replace(a, `${a}
  float daNL = dot( geometryNormal, directLight.direction );
  vec3 daIrr = saturate( ( daNL + daWrap ) / ( 1.0 + daWrap ) ) * directLight.color;
  if ( daSSS > 0.0 ) {
    float daS = smoothstep( -0.45, 0.2, daNL ) * ( 1.0 - smoothstep( 0.05, 0.8, daNL ) );
    daIrr += daSSS * daS * directLight.color * vec3( 0.62, 0.16, 0.07 );
  }`)
    .replace(b, 'reflectedLight.directDiffuse += daIrr * BRDF_Lambert( material.diffuseContribution ) * ( 1.0 - F );')
    .replace(c, `reflectedLight.directSpecular += irradiance * specularBRDF * material.multiScatteringCompensation * daSpec;
  if ( daAniso > 0.0 && dot( daFlowV, daFlowV ) > 0.1 ) {
    vec3 T = normalize( daFlowV - geometryNormal * dot( daFlowV, geometryNormal ) );
    vec3 H = normalize( directLight.direction + geometryViewDir );
    vec3 T1 = normalize( T + geometryNormal * 0.12 );
    vec3 T2 = normalize( T - geometryNormal * 0.18 );
    float th1 = dot( T1, H ), th2 = dot( T2, H );
    float s1 = pow( sqrt( max( 0.0, 1.0 - th1 * th1 ) ), 90.0 );
    float s2 = pow( sqrt( max( 0.0, 1.0 - th2 * th2 ) ), 26.0 );
    float att = smoothstep( -0.1, 0.3, daNL );
    reflectedLight.directSpecular += directLight.color * att * daAniso * ( s1 * 0.1 + s2 * 0.09 * daAlbedo * 2.2 );
  }
  if ( daSheen > 0.0 && dot( daFlowV, daFlowV ) > 0.1 ) {
    // molded-toy hair sheen: ONE broad soft glossy band across the flow (low-exponent Kajiya-Kay), no strand lines
    vec3 Ts = normalize( daFlowV - geometryNormal * dot( daFlowV, geometryNormal ) );
    vec3 Hs = normalize( directLight.direction + geometryViewDir );
    float ths = dot( Ts, Hs );
    float sb = pow( sqrt( max( 0.0, 1.0 - ths * ths ) ), daSheenExp );
    float atts = smoothstep( -0.05, 0.35, daNL );
    reflectedLight.directSpecular += directLight.color * atts * daSheen * sb * mix( daAlbedo * 3.5, vec3( 1.0 ), 0.3 ) * 0.22;
  }`);
}

const LIGHTS = patchLights(THREE.ShaderChunk.lights_physical_pars_fragment);

function linesTexture(stitches, chunks) {
  const n = Math.max(1, stitches.length);
  const data = new Float32Array((n * 4 + chunks.length * 2 + 1) * 4);
  stitches.forEach((s, i) => {
    const [ax, ay, az, bx, by, bz, t0, width, dash, duty, color, mats] = s;
    const c = new THREE.Color(color);
    let mask = 0;
    for (const m of mats || []) mask |= 1 << m;
    data.set([ax, ay, az, width, bx, by, bz, t0, c.r, c.g, c.b, dash, duty, mask, 0, 0], i * 16);
  });
  chunks.forEach((c, i) => data.set([c[0], c[1], c[2], c[3], c[4], c[5], 0, 0], (stitches.length * 4 + i * 2) * 4));
  const t = new THREE.DataTexture(data, n * 4 + chunks.length * 2 + 1, 1, THREE.RGBAFormat, THREE.FloatType);
  t.minFilter = t.magFilter = THREE.NearestFilter;
  t.needsUpdate = true;
  return t;
}

export function createCharMaterial({ header, rim, envMap = null, globals = null, heroFade = false, aoAmount = 1, iblDiffuse = 0.3 } = {}) {
  const mats = header.matNames.map((n) => header.materials[n]);
  const { texture, layerOf } = patternLayers(mats);
  const A = [], B = [], C = [], D = [];
  for (let i = 0; i < NMAT; i++) {
    const m = mats[i] || {};
    A.push(new THREE.Vector4(m.rough ?? 0.6, m.metal ?? 0, layerOf[i] ?? -1, (m.pattern && m.pattern.scale) || 0.1));
    B.push(new THREE.Vector4(m.wrap ?? 0.45, m.sss ?? 0, m.fuzz ?? 0, m.aniso ?? 0));
    C.push(new THREE.Vector4(m.spec ?? 1, m.lines ? 1 : 0, m.bump ?? (m.pattern ? 0.35 : 0), m.cav ?? 1));
    D.push(new THREE.Vector4(m.sheen ?? 0, m.sheenExp ?? 70, 0, 0));
  }
  const stitches = header.stitches || [];
  const kind = header.kind || 'hero';
  const rimC = rim?.color || (kind === 'zombie' ? '#8FF3FF' : '#FFD9A0');
  const uniforms = {
    uMatA: { value: A }, uMatB: { value: B }, uMatC: { value: C }, uMatD: { value: D },
    uPatterns: { value: texture },
    uLines: { value: linesTexture(stitches, header.stitchChunks || []) },
    uLineCount: { value: stitches.length },
    uChunkCount: { value: (header.stitchChunks || []).length },
    uRimColor: { value: new THREE.Color(rimC) },
    uRimStrength: { value: rim?.strength ?? (kind === 'zombie' ? 0.3 : 0.35) },
    uRimAmbient: globals?.uRimAmbient || { value: 1 },
    uHeroFade: globals?.uHeroFade || { value: 1 },
    uAOAmount: { value: aoAmount },
    uDebug: { value: 0 },
    uIBLDiffuse: { value: iblDiffuse },
  };
  const mat = new THREE.MeshStandardMaterial({ color: 0xffffff, vertexColors: true, roughness: 0.6, metalness: 0, envMap, envMapIntensity: 0.8 });
  mat.name = `char:${header.id}`;
  mat.userData.uniforms = uniforms;
  if (heroFade) mat.defines = { DA_FADE: '' };
  mat.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms);
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', VERT_PARS)
      .replace('#include <morphcolor_vertex>', MORPH_COLOR)
      .replace('#include <skinnormal_vertex>', VERT_SKIN);
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', FRAG_PARS)
      .replace('#include <color_fragment>', FRAG_COLOR)
      .replace('#include <roughnessmap_fragment>', FRAG_ROUGH)
      .replace('#include <metalnessmap_fragment>', FRAG_METAL)
      .replace('#include <normal_fragment_maps>', FRAG_NORMAL)
      .replace('#include <lights_physical_pars_fragment>', LIGHTS)
      .replace('#include <lights_fragment_maps>', FRAG_IBL)
      .replace('#include <aomap_fragment>', FRAG_AO)
      .replace('#include <opaque_fragment>', FRAG_OUT);
  };
  mat.customProgramCacheKey = () => 'dachar4' + (heroFade ? 'f' : '');
  return mat;
}

// ---------------------------------------------------------------------------------------------------------------
// Rigid attachment material: standard + wrap + rim (+ optional sss). Cached by params.
const attachCache = new Map();
// Skinned attachments (charRuntime.mergeAttachments binds merged eyes / lids / lashes to the body skeleton) ride
// joints that breathe with a NON-uniform scale (chest ~1.005/1.01/1.007). three skins normals with the skin matrix
// itself; an unskinned mesh uses the inverse transpose (normalMatrix). Same here, so a merged attachment shades
// exactly like the separate mesh it replaces (the eyeballs' sharp clearcoat highlight moved otherwise).
// Only compiled under USE_SKINNING: unskinned attachments are untouched.
const ATT_SKIN_NORMAL = /* glsl */`
#ifdef USE_SKINNING
  mat4 skinMatrix = mat4( 0.0 );
  skinMatrix += skinWeight.x * boneMatX;
  skinMatrix += skinWeight.y * boneMatY;
  skinMatrix += skinWeight.z * boneMatZ;
  skinMatrix += skinWeight.w * boneMatW;
  skinMatrix = bindMatrixInverse * skinMatrix * bindMatrix;
  objectNormal = inverse( transpose( mat3( skinMatrix ) ) ) * objectNormal;
  #ifdef USE_TANGENT
    objectTangent = vec4( skinMatrix * vec4( objectTangent, 0.0 ) ).xyz;
  #endif
#endif
`;
const ATT_FRAG_OUT = /* glsl */`
{
  float nv = saturate( dot( normal, normalize( vViewPosition ) ) );
  float rim = pow( 1.0 - nv, 2.6 );
  outgoingLight += uRimColor * rim * uRimStrength * uRimAmbient * 1.5;
}
#include <opaque_fragment>
`;
export function attachMaterial(o = {}) {
  const key = JSON.stringify(Object.fromEntries(Object.entries(o).map(([k, v]) => [k, v && v.isTexture ? v.uuid : k === 'globals' ? !!v : v])));
  let m = attachCache.get(key);
  if (m) return m;
  const P = o.physical ? THREE.MeshPhysicalMaterial : THREE.MeshStandardMaterial;
  m = new P({
    color: o.color ?? '#ffffff', roughness: o.rough ?? 0.5, metalness: o.metal ?? 0, map: o.map || null,
    transparent: !!o.transparent, opacity: o.opacity ?? 1, depthWrite: o.depthWrite ?? !o.transparent,
    side: o.side ?? THREE.FrontSide, envMap: o.envMap || null, envMapIntensity: o.envIntensity ?? 1,
    emissive: o.emissive || '#000000', emissiveIntensity: o.emissiveIntensity ?? 1, vertexColors: !!o.vertexColors,
    polygonOffset: !!o.polygonOffset, polygonOffsetFactor: o.polygonOffset ? -2 : 0, polygonOffsetUnits: o.polygonOffset ? -2 : 0,
  });
  if (o.physical) { m.clearcoat = o.clearcoat ?? 1; m.clearcoatRoughness = o.clearcoatRough ?? 0.05; }
  const u = {
    uRimColor: { value: new THREE.Color(o.rimColor || '#FFD9A0') }, uRimStrength: { value: o.rim ?? 0.3 },
    uRimAmbient: o.globals?.uRimAmbient || { value: 1 }, uWrapA: { value: o.wrap ?? 0.45 }, uSSSA: { value: o.sss ?? 0 },
    // same IBL diffuse scale as the body material (0.3), so skin-colored lids / attachments match the baked skin
    uIBLA: { value: o.iblDiffuse ?? 0.3 },
  };
  m.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, u);
    shader.vertexShader = shader.vertexShader.replace('#include <skinnormal_vertex>', ATT_SKIN_NORMAL);
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', `#include <common>
uniform vec3 uRimColor; uniform float uRimStrength; uniform float uRimAmbient; uniform float uWrapA; uniform float uSSSA; uniform float uIBLA;
float daWrap = 0.45; float daSSS = 0.0; float daAniso = 0.0; float daSpec = 1.0; float daSheen = 0.0; float daSheenExp = 14.0; vec3 daFlowV = vec3(0.0); vec3 daAlbedo = vec3(1.0);`)
      .replace('#include <lights_physical_pars_fragment>', LIGHTS)
      .replace('#include <lights_fragment_maps>', `#include <lights_fragment_maps>
#if defined( USE_ENVMAP ) && defined( RE_IndirectDiffuse )
  iblIrradiance *= uIBLA;
#endif`)
      .replace('#include <color_fragment>', '#include <color_fragment>\ndaWrap = uWrapA; daSSS = uSSSA; daAlbedo = diffuseColor.rgb;')
      .replace('#include <opaque_fragment>', ATT_FRAG_OUT);
  };
  m.customProgramCacheKey = () => 'daatt3' + (o.physical ? 'p' : '');
  attachCache.set(key, m);
  return m;
}
