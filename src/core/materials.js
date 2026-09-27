// Cartoon material factory (ARCHITECTURE §5/§12, GDD §3.5) + the palette.
//
// toon(color, opts)  MeshStandardMaterial patched via onBeforeCompile:
//   - half-lambert "wrap" diffuse (soft GI-like falloff), optional stepped shading,
//   - fresnel rim light (the key PvZ-GW ingredient), brighter on up-facing normals,
//   - global pre-power grade: environment desaturation (uSatEnv) + amber tint (uAmber), skipped with keepColor,
//   - the Sign-On color wave: saturation restored inside uWaveRadius around uWaveOrigin and a 1 m band of
//     scrolling color-bar emissive stripes at the front (GDD §10.1),
//   - optional screen-door dither fade (heroFade) driven by the global uHeroFade (camera too close to hero),
//   - CAMERA OCCLUSION fade: a screen-door dither of whatever stands between the camera and the hero (props, the
//     tower lattice...), driven by the global uOcc* uniforms (camera.js computes them as cam.occ, render.js uploads
//     them for the gameplay main render only; feeds, menus, the ending and shadows never fade). A fragment fades
//     when it is closer to the camera than the hero (by more than ~0.3 m) AND either inside an ellipse around the
//     hero's screen silhouette (a see-through window over the hero) or inside one of up to 4 occluder boxes
//     (camera.js: props the lines to the hero cross, or right in front of the lens: they fade whole, with a smooth
//     ramp). Walls can't be in front of the hero (the camera probe stops at them). Never below the hero's feet
//     (floors, rugs), never on hero-fade / skinned / instanced materials (the hero, zombies, FX pools).
//   Materials are cached by their params: equal requests return the same instance (fewer programs/state changes).
//   PROGRAM SHARING (load time + fewer program switches): keepColor, fog:false and heroFade are per-material
//   uniforms (uKeep, uFogK, uDaFade), not defines, and every toon material carries the environment map
//   (envMapIntensity 0 = none, the IBL lookups are skipped by a uniform branch), so those options no longer split
//   shader programs (the hero and the held weapon share the level's programs). Same image.
//   The colour-bar palette of the wave front is a GLSL constant (uBars): a uniform array is re-uploaded by three on
//   every material switch (arrays have no value cache: one gl.uniform3fv per switch, ~150-300 per frame).
//   opts: { rough=0.75, metal=0, emissive, emissiveIntensity=1, rim=0.35, rimColor, rimPower=2.4, wrap=0.5,
//           steps=0, map, transparent, opacity=1, side, flat, keepColor, heroFade, vertexColors, env, alphaTest,
//           depthWrite, fog=true, name }
//   staticopt.js (area batches) builds on the patch: keep _patchToon(mat, params), mat.userData.uniforms (uWrap,
//   uSteps, uRimStrength, uRimPower, uRimColor, uKeep, uFogK), the shared customProgramCacheKey function, the
//   'uniform ...;' declaration lines, 'varying vec3 vDaWorld;' and the 'if ( envMapIntensity > 0.0 )' IBL branch.
// glow(color, intensity)  unlit HDR emissive (feeds bloom) for bulbs/neon/LEDs (with the occlusion fade).
// screen(texture, {bulge}) CRT glass: swappable `.map`, barrel, scanlines, chroma offset, vignette, glossy sheet.
// rubberGlass(texture)     screen() with the animated vertex bulge (uniforms.uBulge 0..0.35 m, uWobble 0..1);
//                          use screenGeometry(w, h) (plane subdivided 24x18).
// glass(color), skin(tone), basic(color, opts).
// Global uniforms (shared by every toon material): mats.uniforms = { uSatEnv, uAmber, uWaveOrigin, uWaveRadius,
//   uTime, uHeroFade, uRimAmbient, uBars (constant; kept for other shaders), uOccRect, uOccZ, uOccAmt, uOccBox0/1,
//   uOccWall0/1 }. signon.js animates the first four; lights.js drives uRimAmbient; render.js writes the uOcc* ones
//   from camera.js's cam.occ during the gameplay main render.

import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { PAL } from './config.js';
import { plane } from './geo.js';

export { PAL };

const WORLD_POS_VERT = /* glsl */`
#include <project_vertex>
{
  vec4 daW = vec4( transformed, 1.0 );
  #ifdef USE_BATCHING
    daW = batchingMatrix * daW;
  #endif
  #ifdef USE_INSTANCING
    daW = instanceMatrix * daW;
  #endif
  vDaWorld = ( modelMatrix * daW ).xyz;
}`;

// 4x4 ordered-dither threshold (screen-door fades: hero fade, camera occlusion).
const BAYER_GLSL = /* glsl */`
float daBayer( vec2 p ) {
  const mat4 M = mat4( 0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0 );
  ivec2 q = ivec2( mod( p, 4.0 ) );
  return ( M[ q.y ][ q.x ] + 0.5 ) / 16.0;
}`;

// Camera occlusion (see the header), written by render.js from camera.js's cam.occ:
//   uOccRect  hero ellipse on the scene target: xy centre (px), zw 1 / radii (px)
//   uOccZ     x: view depth closer than which the fade is full (the hero's depth minus a margin), y: soft range
//             behind it (nothing fades beyond x + y), z: unused, w: world height below which nothing fades (feet)
//   uOccAmt   strength 0..1 (0 = off: every pass but the gameplay main render)
//   uOccBox0/1 two occluder boxes each (mat4 columns: min.xyz + fade level 0..1, max.xyz, min + level, max): world
//             AABBs that fade whole (0.15 m soft edge); unused slots have level 0.
//   uOccWall0/1 two protected boxes each (same layout, w = 1 when used): the walls, doors, windows, glass, fences
//             and platforms nearest the camera. Nothing inside them ever fades: the window's soft rim can reach a
//             wall right beside a hero standing close to the camera, and a prop box can touch a wall.
// Matrices, not arrays: three re-uploads uniform arrays on every material switch (no value cache).
// daOcc(viewZ, worldPos) -> 0..1 fraction of pixels to drop; daOccDrop() = this pixel is dropped.
const OCC_PARS = /* glsl */`
uniform vec4 uOccRect;
uniform vec4 uOccZ;
uniform float uOccAmt;
uniform mat4 uOccBox0;
uniform mat4 uOccBox1;
uniform mat4 uOccWall0;
uniform mat4 uOccWall1;
float daOccBox( vec4 b0, vec4 b1, vec3 p ) {
  vec3 d = max( b0.xyz - p, p - b1.xyz );
  return b0.w * ( 1.0 - smoothstep( 0.0, 0.15, max( max( d.x, d.y ), d.z ) ) );
}
bool daOccIn( vec4 b0, vec4 b1, vec3 p ) {
  return b0.w > 0.5 && all( greaterThanEqual( p, b0.xyz ) ) && all( lessThanEqual( p, b1.xyz ) );
}
float daOcc( float viewZ, vec3 wp ) {
  if ( uOccAmt <= 0.0 || wp.y < uOccZ.w ) return 0.0;
  float front = 1.0 - smoothstep( uOccZ.x, uOccZ.x + uOccZ.y, viewZ );
  if ( front <= 0.0 ) return 0.0;
  vec2 q = ( gl_FragCoord.xy - uOccRect.xy ) * uOccRect.zw;
  float k = 1.0 - smoothstep( 0.35, 1.0, dot( q, q ) );
  k = max( k, max( max( daOccBox( uOccBox0[ 0 ], uOccBox0[ 1 ], wp ), daOccBox( uOccBox0[ 2 ], uOccBox0[ 3 ], wp ) ),
    max( daOccBox( uOccBox1[ 0 ], uOccBox1[ 1 ], wp ), daOccBox( uOccBox1[ 2 ], uOccBox1[ 3 ], wp ) ) ) );
  if ( k <= 0.0 ) return 0.0;
  if ( daOccIn( uOccWall0[ 0 ], uOccWall0[ 1 ], wp ) || daOccIn( uOccWall0[ 2 ], uOccWall0[ 3 ], wp ) ||
    daOccIn( uOccWall1[ 0 ], uOccWall1[ 1 ], wp ) || daOccIn( uOccWall1[ 2 ], uOccWall1[ 3 ], wp ) ) return 0.0;
  return uOccAmt * front * k;
}
bool daOccDrop( float viewZ, vec3 wp ) {
  float o = daOcc( viewZ, wp );
  return o > 0.0 && o > daBayer( floor( gl_FragCoord.xy ) );
}`;

// The Sign-On wave's colour bars (PAL.BARS, linear) as a GLSL constant named like the old uniform (weapon shader
// patches read uBars too). Printed with 9 significant digits: the exact float32 values the uniform carried.
const BARS_GLSL = (() => {
  const f = (x) => Math.fround(x).toPrecision(9);
  const v = PAL.BARS.map((h) => { const c = new THREE.Color(h); return `vec3( ${f(c.r)}, ${f(c.g)}, ${f(c.b)} )`; });
  return `const vec3 uBars[ 7 ] = vec3[ 7 ]( ${v.join(', ')} );`;
})();

const FRAG_PARS = /* glsl */`
#include <common>
uniform float uWrap;
uniform float uSteps;
uniform float uRimStrength;
uniform float uRimPower;
uniform vec3 uRimColor;
uniform float uSatEnv;
uniform float uAmber;
uniform vec3 uWaveOrigin;
uniform float uWaveRadius;
uniform float uTime;
uniform float uHeroFade;
uniform float uRimAmbient;
${BARS_GLSL}
uniform float uKeep;
uniform float uFogK;
uniform float uDaFade;
varying vec3 vDaWorld;
float daShade( float x ) {
  if ( uSteps < 0.5 ) return x;
  float s = x * uSteps;
  return ( floor( s ) + smoothstep( 0.4, 0.6, fract( s ) ) ) / uSteps;
}
${BAYER_GLSL}
${OCC_PARS}`;

// Rim response gain: GDD rim strengths (heroes 0.35, zombies 0.3, props 0.2) read as a clear toy-like edge.
const RIM_GAIN = '1.6';

// End of main(), before the output: the hero fade (uDaFade 1: the hero, the held weapon) and the camera occlusion
// fade (uDaFade 0: every other toon material; uDaFade 2 = actors exempt from both, see noOcclusion(); skinned zombie
// placeholders and instanced FX pools never fade).
const FRAG_OUT = /* glsl */`
if ( uDaFade > 0.5 ) {
  if ( uDaFade < 1.5 && uHeroFade < 0.999 && uHeroFade <= daBayer( floor( gl_FragCoord.xy ) ) ) discard;
}
#if !defined( USE_SKINNING ) && !defined( USE_INSTANCING )
else if ( daOccDrop( vViewPosition.z, vDaWorld ) ) discard;
#endif
{
  float daNV = saturate( dot( geometryNormal, geometryViewDir ) );
  float daRim = pow( 1.0 - daNV, uRimPower );
  vec3 daWN = inverseTransformDirection( geometryNormal, viewMatrix );
  daRim *= 0.55 + 0.45 * saturate( daWN.y + 0.6 );
  outgoingLight += uRimColor * ( daRim * uRimStrength * uRimAmbient * ${RIM_GAIN} );
}
if ( uKeep < 0.5 ) {
  float daD = distance( vDaWorld, uWaveOrigin );
  float daK = uWaveRadius < 0.0 ? 0.0 : smoothstep( -0.5, 0.5, uWaveRadius - daD );
  float daSat = mix( uSatEnv, 1.0, daK );
  float daAmb = mix( uAmber, 0.0, daK );
  float daL = dot( outgoingLight, vec3( 0.2126, 0.7152, 0.0722 ) );
  outgoingLight = mix( vec3( daL ), outgoingLight, daSat );
  outgoingLight = mix( outgoingLight, vec3( daL ) * vec3( 1.45, 0.98, 0.45 ), daAmb );
  if ( uWaveRadius >= 0.0 ) {
    float daBand = 1.0 - smoothstep( 0.3, 0.5, abs( daD - uWaveRadius ) );
    if ( daBand > 0.0 ) {
      float daS = mod( floor( ( vDaWorld.x - vDaWorld.z ) * 1.6 + vDaWorld.y * 0.8 - uTime * 5.0 ), 7.0 );
      vec3 daBar = uBars[ int( daS ) ];
      outgoingLight = mix( outgoingLight, daBar * 2.4, daBand * 0.85 );
    }
  }
}
#include <opaque_fragment>`;

// Environment lighting skipped by a uniform branch when envMapIntensity is 0: every toon material carries the
// envMap (one program instead of two), the ones that had none keep exactly their old result (radiance and
// irradiance stay 0) and pay no texture lookups.
const PATCHED_MAPS = (() => {
  const src = THREE.ShaderChunk.lights_fragment_maps;
  const a = 'iblIrradiance += getIBLIrradiance( geometryNormal );';
  const b = 'vec3 iblRadiance = getIBLRadiance( geometryViewDir, geometryNormal, material.roughness );';
  if (!src.includes(a) || !src.includes(b)) return null;
  return src
    .replace(a, `if ( envMapIntensity > 0.0 ) ${a}`)
    .replace(b, 'vec3 iblRadiance = vec3( 0.0 );\n\t\tif ( envMapIntensity > 0.0 ) iblRadiance = getIBLRadiance( geometryViewDir, geometryNormal, material.roughness );');
})();

// fog:false as a uniform (uFogK 0): mix( c, fogColor, 0 ) is exactly c, so fogless materials share the program.
const PATCHED_FOG = (() => {
  const src = THREE.ShaderChunk.fog_fragment;
  const a = 'gl_FragColor.rgb = mix( gl_FragColor.rgb, fogColor, fogFactor );';
  if (!src.includes(a)) return null;
  return src.replace(a, 'gl_FragColor.rgb = mix( gl_FragColor.rgb, fogColor, fogFactor * uFogK );');
})();


const toonKey = () => 'datoon2';
const glowKey = () => 'daglow2';

// glow(): the same camera-occlusion fade on MeshBasicMaterial (a faded lamp keeps no floating bulb).
const GLOW_VERT = /* glsl */`
#include <project_vertex>
vDaVZ = - mvPosition.z;
{
  vec4 daW = vec4( transformed, 1.0 );
  #ifdef USE_BATCHING
    daW = batchingMatrix * daW;
  #endif
  #ifdef USE_INSTANCING
    daW = instanceMatrix * daW;
  #endif
  vDaW = ( modelMatrix * daW ).xyz;
}`;
const GLOW_OCC_OUT = /* glsl */`
#if !defined( USE_SKINNING ) && !defined( USE_INSTANCING )
  if ( daOccDrop( vDaVZ, vDaW ) ) discard;
#endif
#include <opaque_fragment>`;

// Patched lights chunk: wrapped + stepped diffuse for direct lights (specular keeps the true N.L).
const PATCHED_LIGHTS = (() => {
  const src = THREE.ShaderChunk.lights_physical_pars_fragment;
  const a = 'vec3 irradiance = dotNL * directLight.color;';
  const b = 'reflectedLight.directDiffuse += irradiance * BRDF_Lambert';
  if (!src.includes(a) || !src.includes(b)) {
    console.warn('[materials] three.js lighting chunk changed; toon wrap disabled');
    return src;
  }
  return src
    .replace(a, `${a}
  float daNL = dot( geometryNormal, directLight.direction );
  vec3 daIrradiance = daShade( saturate( ( daNL + uWrap ) / ( 1.0 + uWrap ) ) ) * directLight.color;`)
    .replace(b, 'reflectedLight.directDiffuse += daIrradiance * BRDF_Lambert');
})();

const SCREEN_VERT = /* glsl */`
#include <common>
#include <fog_pars_vertex>
uniform float uBulge;
uniform float uWobble;
uniform float uTime;
uniform vec2 uSize;
varying vec2 vUv;
varying vec3 vN;
varying vec3 vView;
varying vec3 vDaW;
void main() {
  vUv = uv;
  vec2 c = uv * 2.0 - 1.0;
  float wob = 1.0 + uWobble * 0.35 * sin( uTime * 11.0 + c.x * 5.0 ) * sin( uTime * 8.0 - c.y * 4.0 );
  float amp = uBulge * wob;
  float w = ( 1.0 - c.x * c.x ) * ( 1.0 - c.y * c.y );
  vec3 p = position;
  p.z += amp * w;
  float dx = amp * ( -2.0 * c.x ) * ( 1.0 - c.y * c.y ) * 2.0 / max( uSize.x, 1e-3 );
  float dy = amp * ( -2.0 * c.y ) * ( 1.0 - c.x * c.x ) * 2.0 / max( uSize.y, 1e-3 );
  vN = normalize( normalMatrix * normalize( vec3( -dx, -dy, 1.0 ) ) );
  vec4 mvPosition = modelViewMatrix * vec4( p, 1.0 );
  vView = -mvPosition.xyz;
  vDaW = ( modelMatrix * vec4( p, 1.0 ) ).xyz;
  gl_Position = projectionMatrix * mvPosition;
  #include <fog_vertex>
}`;

const SCREEN_FRAG = /* glsl */`
#include <common>
#include <fog_pars_fragment>
uniform sampler2D tScreen;
uniform float uTime;
uniform float uBarrel;
uniform float uScan;
uniform float uBright;
uniform float uChroma;
uniform float uVignette;
uniform float uGloss;
uniform float uLines;
uniform vec2 uTexel;
uniform vec3 uTint;
varying vec2 vUv;
varying vec3 vN;
varying vec3 vView;
varying vec3 vDaW;
${BAYER_GLSL}
${OCC_PARS}
void main() {
  vec2 c = vUv - 0.5;
  vec2 uv = 0.5 + c * ( 1.0 - uBarrel + uBarrel * 4.0 * dot( c, c ) );
  float inside = step( 0.0, uv.x ) * step( uv.x, 1.0 ) * step( 0.0, uv.y ) * step( uv.y, 1.0 );
  vec2 off = vec2( uChroma * uTexel.x, 0.0 );
  vec3 col = vec3( texture2D( tScreen, uv + off ).r, texture2D( tScreen, uv ).g, texture2D( tScreen, uv - off ).b );
  float sl = 0.5 + 0.5 * cos( uv.y * PI2 * uLines );
  col *= 1.0 - uScan * ( 1.0 - sl );
  col *= 0.95 + 0.05 * sin( uv.y * 7.0 - uTime * 2.3 );
  float vig = smoothstep( 0.78, 0.25, length( c * vec2( 1.0, 1.2 ) ) );
  col *= mix( 1.0, vig, uVignette ) * inside * uBright * uTint;
  vec3 n = normalize( vN );
  vec3 vd = normalize( vView );
  float fr = pow( 1.0 - saturate( dot( n, vd ) ), 3.0 );
  vec3 r = reflect( -vd, n );
  float spec = pow( saturate( dot( r, normalize( vec3( -0.4, 0.65, 0.65 ) ) ) ), 40.0 );
  float streak = smoothstep( 0.1, 0.0, abs( ( vUv.x + vUv.y * 0.6 ) - 1.05 ) ) * 0.08;
  vec3 glass = vec3( 0.012, 0.014, 0.02 ) + fr * vec3( 0.16, 0.18, 0.22 ) + ( spec * 0.9 + streak ) * vec3( 1.0, 0.97, 0.92 );
  gl_FragColor = vec4( col + glass * uGloss, 1.0 );
  if ( daOccDrop( vView.z, vDaW ) ) discard;
  #include <fog_fragment>
}`;

// three re-uploads the key light's shadow matrix (a mat4 array uniform: flatten + gl.uniformMatrix4fv, no value
// cache) on every material switch, because markUniformsLightsNeedsUpdate() leaves it out of the light uniforms it
// refreshes only on program switches. Its value only changes when the shadow map re-renders, before any scene draw
// of a render call, and every program's first draw of a render call is a program switch (the shadow pass, the
// feeds and the post passes bind other programs in between), so it can follow the lights' flag: same values, one
// upload per program switch instead of per material (~150-250 GL calls less per frame). Samplers are left alone
// (skipping one would shift three's texture-unit allocation).
function lightsOnly(U) {
  const m = U.directionalShadowMatrix, L = U.directionalLights;
  if (!m || !L || Object.getOwnPropertyDescriptor(m, 'needsUpdate')) return;
  Object.defineProperty(m, 'needsUpdate', { get: () => L.needsUpdate !== false, set() {}, configurable: true });
}

const BLACK = new THREE.DataTexture(new Uint8Array([0, 0, 0, 255]), 1, 1);
BLACK.needsUpdate = true;

export class Materials {
  constructor(game) {
    this.game = game;
    this._cache = new Map();
    const bars = PAL.BARS.map((h) => new THREE.Color(h));
    // Pre-power defaults (GDD §3.3); machines/signon restore 1.0 / 0.0 at Sign-On (or power=1).
    this.uniforms = {
      uSatEnv: { value: 0.7 },
      uAmber: { value: 0.08 },
      uWaveOrigin: { value: new THREE.Vector3() },
      uWaveRadius: { value: -1 },
      uTime: { value: 0 },
      uHeroFade: { value: 1 },
      uRimAmbient: { value: 1 },
      uBars: { value: bars },
      // camera occlusion (render.js writes them for the gameplay main render only; uOccAmt 0 = off)
      uOccRect: { value: new THREE.Vector4(0, 0, 0, 0) },
      uOccZ: { value: new THREE.Vector4(0, 0, 0, 0) },
      uOccAmt: { value: 0 },
    };
    // occluder boxes, two per matrix (columns: min + level, max, min + level, max)
    this.uniforms.uOccBox0 = { value: new THREE.Matrix4().set(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) };
    this.uniforms.uOccBox1 = { value: new THREE.Matrix4().set(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) };
    this.uniforms.uOccWall0 = { value: new THREE.Matrix4().set(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) };
    this.uniforms.uOccWall1 = { value: new THREE.Matrix4().set(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) };
    // the occlusion uniforms alone (glow and CRT materials)
    this._occUniforms = {};
    for (const k in this.uniforms) if (k.startsWith('uOcc')) this._occUniforms[k] = this.uniforms[k];
    const pmrem = new THREE.PMREMGenerator(game.renderer);
    const room = new RoomEnvironment();
    this.envMap = pmrem.fromScene(room, 0.04).texture;
    room.dispose();
    pmrem.dispose();
    this.PAL = PAL;
    const OU = this._occUniforms;
    const FOG_ON = { value: 1 };
    // one shared onBeforeCompile for every glow material (same program key); `this` is the material (its fog:false
    // is a uniform too: uFogK 0 on a fog program, same image, one program less)
    this._glowCompile = function (shader) {
      Object.assign(shader.uniforms, OU);
      shader.uniforms.uFogK = (this && this.userData && this.userData.daFogK) || FOG_ON;
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', `#include <common>
varying float vDaVZ;
varying vec3 vDaW;`)
        .replace('#include <project_vertex>', GLOW_VERT);
      let fs = shader.fragmentShader
        .replace('#include <common>', `#include <common>
uniform float uFogK;
varying float vDaVZ;
varying vec3 vDaW;${BAYER_GLSL}${OCC_PARS}`)
        .replace('#include <opaque_fragment>', GLOW_OCC_OUT);
      if (PATCHED_FOG) fs = fs.replace('#include <fog_fragment>', PATCHED_FOG);
      shader.fragmentShader = fs;
    };
  }

  update() {
    this.uniforms.uTime.value = this.game.time.realNow;
  }

  _key(kind, color, p) {
    // Swap textures for their uuid BEFORE stringify: JSON.stringify calls Texture.toJSON ahead of any replacer
    // (slow, and warns "Unable to serialize Texture" for canvas images).
    const q = {};
    for (const k in p) { const v = p[k]; q[k] = v && v.isTexture ? 'tex:' + v.uuid : v; }
    return `${kind}|${color}|${JSON.stringify(q, (k, v) => (v && v.isTexture ? v.uuid : v))}`;
  }

  // Cartoon standard material (see header for opts).
  toon(color = '#ffffff', opts = {}) {
    const hex = typeof color === 'string' ? color : '#' + new THREE.Color(color).getHexString();
    const p = {
      rough: opts.rough ?? 0.75,
      metal: opts.metal ?? 0,
      emissive: opts.emissive ?? null,
      emissiveIntensity: opts.emissiveIntensity ?? 1,
      rim: opts.rim ?? 0.35,
      rimColor: opts.rimColor ?? '#FFE9CC',
      rimPower: opts.rimPower ?? 2.4,
      wrap: opts.wrap ?? 0.5,
      steps: opts.steps ?? 0,
      map: opts.map ?? null,
      transparent: !!opts.transparent,
      opacity: opts.opacity ?? 1,
      side: opts.side ?? THREE.FrontSide,
      flat: !!opts.flat,
      keepColor: !!opts.keepColor,
      heroFade: !!opts.heroFade,
      vertexColors: !!opts.vertexColors,
      env: opts.env ?? null,
      alphaTest: opts.alphaTest ?? 0,
      depthWrite: opts.depthWrite ?? true,
      fog: opts.fog ?? true,
      name: opts.name ?? '',
    };
    const key = this._key('toon', hex, p);
    let mat = this._cache.get(key);
    if (mat) return mat;

    mat = new THREE.MeshStandardMaterial({
      color: hex,
      roughness: p.rough,
      metalness: p.metal,
      map: p.map,
      transparent: p.transparent,
      opacity: p.opacity,
      side: p.side,
      flatShading: p.flat,
      vertexColors: p.vertexColors,
      alphaTest: p.alphaTest,
      depthWrite: p.depthWrite,
      fog: PATCHED_FOG ? true : p.fog, // fog:false = uFogK 0 (shares the fog program, same image)
    });
    mat.name = p.name || `toon:${hex}`;
    if (p.emissive) {
      mat.emissive.set(p.emissive);
      mat.emissiveIntensity = p.emissiveIntensity;
    }
    const envAmount = p.env ?? (p.metal > 0 ? 1.0 : p.rough < 0.5 ? 0.3 * (1 - p.rough) : 0);
    if (envAmount > 0 || PATCHED_MAPS) {
      // every toon material carries the env map when the IBL branch patch is available (intensity 0 = none)
      mat.envMap = this.envMap;
      mat.envMapIntensity = Math.max(0, envAmount);
    }
    this._patchToon(mat, p);
    mat.userData.daToon = { color: hex, params: p };
    this._cache.set(key, mat);
    return mat;
  }

  _patchToon(mat, p) {
    const local = {
      uWrap: { value: p.wrap },
      uSteps: { value: p.steps },
      uRimStrength: { value: p.rim },
      uRimPower: { value: p.rimPower },
      uRimColor: { value: new THREE.Color(p.rimColor) },
      uKeep: { value: p.keepColor ? 1 : 0 },        // keepColor: skip the pre-power grade / colour wave
      uFogK: { value: p.fog || !PATCHED_FOG ? 1 : 0 }, // fog:false
      uDaFade: { value: p.heroFade ? 1 : 0 },        // heroFade: dithered by uHeroFade, never occlusion-faded (2: neither)
    };
    mat.userData.uniforms = local;
    mat.defines = mat.defines || {};
    const G = this.uniforms;
    mat.onBeforeCompile = (shader) => {
      Object.assign(shader.uniforms, G, local);
      lightsOnly(shader.uniforms);
      shader.vertexShader = shader.vertexShader
        .replace('#include <common>', '#include <common>\nvarying vec3 vDaWorld;')
        .replace('#include <project_vertex>', WORLD_POS_VERT);
      let fs = shader.fragmentShader
        .replace('#include <common>', FRAG_PARS)
        .replace('#include <lights_physical_pars_fragment>', PATCHED_LIGHTS)
        .replace('#include <opaque_fragment>', FRAG_OUT);
      if (PATCHED_MAPS) fs = fs.replace('#include <lights_fragment_maps>', PATCHED_MAPS);
      if (PATCHED_FOG) fs = fs.replace('#include <fog_fragment>', PATCHED_FOG);
      shader.fragmentShader = fs;
    };
    mat.customProgramCacheKey = toonKey;
  }

  // Actors never take part in the camera-occlusion fade (a zombie behind the hero stays solid, attachments included):
  // flags every plain toon material under root (uDaFade 0 -> 2; hero-fade materials keep theirs). camera.js calls it
  // for spawned zombies and the boss. A material shared with level props stops fading there too (none known).
  noOcclusion(root) {
    if (!root || !root.traverse) return;
    root.traverse((o) => {
      const ms = o.material;
      if (!ms) return;
      for (let i = 0, n = Array.isArray(ms) ? ms.length : 1; i < n; i++) {
        const m = Array.isArray(ms) ? ms[i] : ms;
        const u = m && m.userData && m.userData.uniforms;
        if (u && u.uDaFade && u.uDaFade.value === 0) u.uDaFade.value = 2;
      }
    });
  }

  // Same material with some params overridden (e.g. {heroFade:true}); non-toon materials are returned as-is.
  variant(mat, extra) {
    const d = mat && mat.userData.daToon;
    if (!d) return mat;
    return this.toon(d.color, { ...d.params, ...extra });
  }

  // Swap every toon material under `root` to its heroFade variant (the player's hero + held weapon).
  // Meshes with other materials get userData.daHideOnFade so the player can hide them when faded.
  applyHeroFade(root) {
    root.traverse((o) => {
      if (!o.isMesh) return;
      if (o.material && o.material.userData.daToon) o.material = this.variant(o.material, { heroFade: true });
      else o.userData.daHideOnFade = true;
    });
  }

  // Unlit HDR emissive (bloom threshold is ~0.8). opts: { transparent, opacity, additive, map, fog=true, side }
  glow(color = '#ffffff', intensity = 2, opts = {}) {
    const key = this._key('glow', color, { intensity, ...opts });
    let mat = this._cache.get(key);
    if (mat) return mat;
    const c = new THREE.Color(color).multiplyScalar(intensity);
    mat = new THREE.MeshBasicMaterial({
      color: c,
      map: opts.map ?? null,
      transparent: !!opts.transparent || !!opts.additive,
      opacity: opts.opacity ?? 1,
      blending: opts.additive ? THREE.AdditiveBlending : THREE.NormalBlending,
      depthWrite: !opts.additive,
      fog: PATCHED_FOG ? true : opts.fog ?? true, // fog:false = uFogK 0 (shares the fog program, same image)
      side: opts.side ?? THREE.FrontSide,
    });
    mat.name = `glow:${color}`;
    mat.userData.daFogK = { value: (opts.fog ?? true) || !PATCHED_FOG ? 1 : 0 };
    mat.onBeforeCompile = this._glowCompile;
    mat.customProgramCacheKey = glowKey;
    this._cache.set(key, mat);
    return mat;
  }

  // Plain unlit color (UI-ish props, backdrops). Cached.
  basic(color = '#ffffff', opts = {}) {
    const key = this._key('basic', color, opts);
    let mat = this._cache.get(key);
    if (!mat) {
      mat = new THREE.MeshBasicMaterial({ color, ...opts });
      this._cache.set(key, mat);
    }
    return mat;
  }

  // Transparent glossy glass (display cases, booth glass, aviators). Cached.
  glass(color = '#CFE8FF', opts = {}) {
    return this.toon(color, {
      rough: 0.05, transparent: true, opacity: opts.opacity ?? 0.22, rim: 0.6, rimColor: '#ffffff', rimPower: 2.0,
      env: 1.2, depthWrite: false, keepColor: opts.keepColor ?? true, side: opts.side ?? THREE.DoubleSide, name: 'glass',
    });
  }

  // Skin: softer wrap, warm rim, always full color.
  skin(tone = '#F2B48C', opts = {}) {
    return this.toon(tone, { rough: 0.58, wrap: 0.7, rim: 0.35, rimColor: PAL.rimHero, keepColor: true, ...opts });
  }

  // CRT screen material (NOT cached: ScreenManager swaps `.map` per screen at runtime).
  // opts: { bulge=0, barrel=0.06, scan=0.35, bright=1.35, chroma=1.5 (px), vignette=0.8, gloss=1, lines=120,
  //         w=1, h=0.75 (plane size, for the bulge normal) }
  screen(texture = null, opts = {}) {
    const u = {
      tScreen: { value: texture || BLACK },
      uTime: this.uniforms.uTime,
      uBulge: { value: opts.bulge ?? 0 },
      uWobble: { value: 0 },
      uSize: { value: new THREE.Vector2(opts.w ?? 1, opts.h ?? 0.75) },
      uBarrel: { value: opts.barrel ?? 0.06 },
      uScan: { value: opts.scan ?? 0.35 },
      uBright: { value: opts.bright ?? 1.35 },
      uChroma: { value: opts.chroma ?? 1.5 },
      uVignette: { value: opts.vignette ?? 0.8 },
      uGloss: { value: opts.gloss ?? 1 },
      uLines: { value: opts.lines ?? 120 },
      uTexel: { value: new THREE.Vector2(1 / 256, 1 / 256) },
      uTint: { value: new THREE.Color(1, 1, 1) },
      ...this._occUniforms,
    };
    const mat = new THREE.ShaderMaterial({
      uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog]),
      vertexShader: SCREEN_VERT,
      fragmentShader: SCREEN_FRAG,
      fog: true,
    });
    Object.assign(mat.uniforms, u);
    mat.name = 'crt';
    const setTexel = (t) => {
      const img = t && (t.image || (t.source && t.source.data));
      if (img && img.width) u.uTexel.value.set(1 / img.width, 1 / img.height);
    };
    setTexel(texture);
    Object.defineProperty(mat, 'map', {
      get: () => (u.tScreen.value === BLACK ? null : u.tScreen.value),
      set: (t) => { u.tScreen.value = t || BLACK; setTexel(t); },
      configurable: true,
    });
    return mat;
  }

  // Rubber-glass screen (GDD §3.5): animate mat.uniforms.uBulge (0..0.35 m) / uWobble (0..1).
  rubberGlass(texture = null, opts = {}) {
    return this.screen(texture, { bulge: 0.03, barrel: 0.04, scan: 0.3, ...opts });
  }

  // Plane subdivided 24x18 for bulging screens (cached per size).
  screenGeometry(w = 0.8, h = 0.6) {
    return plane(w, h, 24, 18);
  }
}
