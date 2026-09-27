// Renderer, post pipeline, resize and dynamic resolution (ARCHITECTURE §5/§12, GDD §3.9, §14).
//
// Pipeline: 4x MSAA HalfFloat scene target (the second ping-pong target is single-sampled) -> RenderPass ->
// UnrealBloom (half-res mip chain) -> GradePass, which renders to the screen and ends with ACES + sRGB (the
// OutputPass work, folded in: one full-screen pass less). GradePass works in linear HDR before tone mapping and implements every `render.post` knob:
//   saturation (1), contrast, warmth (70s tint), grain, vignette (extra, on top of a subtle base), chroma (px),
//   damage   signal loss: static creeping in from the edges + chromatic aberration + line jitter + hold slip,
//   static   full-screen snow, roll = vertical roll, whiteout = Big Shot flash (also boosts bloom),
//   scanlines, crt (commercial look: barrel + scanlines + chroma), collapse (CRT power-off: 0 -> 1 = image
//   squashes to a white line, the line shrinks to a dot, the dot fades out).
// Other systems animate `game.render.post.*` as plain numbers; defaults are 0 except saturation 1.
// setCameraOverride(camera, {aspect}) renders another camera into a centered viewport of that aspect
// (letterboxed black, the HUD bezel covers it) with no extra pass: the frame is rendered with the override
// camera's aspect and remapped by GradePass. addPrePass(fn) runs fn(renderer) before the main render.
// TEMPORARY EFFECT LAYERS: setFx(owner, knobs, { ttl }) / clearFx(owner) / clearAllFx() / hasFx(owner). A short-lived
// look (Instant Replay's VHS rewind, ...) is a named layer combined into the grade uniforms every frame WITHOUT
// writing render.post: roll, chroma, scanlines, static, whiteout, crt, collapse, vignette, damage and grain take the
// max of render.post and every layer; saturation is multiplied by each layer's `saturation`. Ending the effect is
// clearFx(owner), which removes exactly that contribution whatever else changed meanwhile. (Snapshotting render.post
// and writing the snapshot back restores other systems' transients, e.g. the HUD's hurt pulse, and the HUD's knob
// mixer then keeps that value as a permanent external one: a vertical roll that never stops.) With `ttl` (s, real
// time) a layer also drops by itself when its owner stops refreshing it, so a crashed or interrupted effect can
// never leave its look on screen. reset() clears every layer.
// PERF FLAGS (live, for A/B; all image-identical): programSort (opaque draws grouped by shader program), twoPassTwins
// (transparent double-sided materials drawn through fixed-side twins instead of three's side flip + needsUpdate),
// skipHiddenRoots (hidden top-level branches skip the per-render matrix update). occlusionFade: the camera-occlusion
// screen-door fade (materials.js uOcc*, computed by camera.js as cam.occ) is uploaded for the gameplay main render
// only and switched off right after it.

import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { LAYERS, PAL } from './config.js';

const BLOOM = { strength: 0.45, radius: 0.55, threshold: 0.8 };
const MIN_PR = 0.6;

// NaN/Inf guard. One NaN pixel entering the bloom mip chain spreads over the whole frame (the blurred
// NaN reaches every pixel of the low mips, and the grade's max() turns it into black). The bloom high-pass
// and the grade therefore sanitize what they read: isnan/isinf for GPUs that honor them, then a clamp
// (D3D11 min/max return the non-NaN operand, so this also works where the compiler drops isnan).
const SAFE_GLSL = /* glsl */`
  vec3 daSafe( vec3 c ) {
    c = ( any( isnan( c ) ) || any( isinf( c ) ) ) ? vec3( 0.0 ) : c;
    return clamp( c, vec3( 0.0 ), vec3( 64.0 ) );
  }`;

const GradeShader = {
  uniforms: {
    tDiffuse: { value: null },
    uRes: { value: new THREE.Vector2(1280, 720) },
    uTime: { value: 0 },
    uSaturation: { value: 1 },
    uContrast: { value: 1.06 },
    uWarmth: { value: 1 },
    uGrain: { value: 0.03 },
    uVignette: { value: 0 },
    uChroma: { value: 0 },
    uDamage: { value: 0 },
    uStatic: { value: 0 },
    uRoll: { value: 0 },
    uRollPhase: { value: 0 },
    uWhiteout: { value: 0 },
    uScanlines: { value: 0 },
    uCrt: { value: 0 },
    uCollapse: { value: 0 },
    uView: { value: new THREE.Vector4(0, 0, 1, 1) },
    uLift: { value: new THREE.Color(PAL.shadow) },
  },
  vertexShader: /* glsl */`
    varying vec2 vUv;
    void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 ); }`,
  fragmentShader: /* glsl */`
    #include <common>
    uniform sampler2D tDiffuse;
    uniform vec2 uRes;
    uniform float uTime, uSaturation, uContrast, uWarmth, uGrain, uVignette, uChroma, uDamage, uStatic;
    uniform float uRoll, uRollPhase, uWhiteout, uScanlines, uCrt, uCollapse;
    uniform vec4 uView;
    uniform vec3 uLift;
    varying vec2 vUv;
    ${SAFE_GLSL}

    float h12( vec2 p ) {
      vec3 p3 = fract( vec3( p.xyx ) * 0.1031 );
      p3 += dot( p3, p3.yzx + 33.33 );
      return fract( ( p3.x + p3.y ) * p3.z );
    }
    float box( vec2 uv, vec2 px ) {
      vec2 e = smoothstep( vec2( 0.0 ), px, uv ) * smoothstep( vec2( 0.0 ), px, 1.0 - uv );
      return e.x * e.y;
    }

    void main() {
      vec2 px = 1.0 / uRes;
      // CRT power-off: squash to a line (c1), shrink to a dot (c2), fade (c3).
      float c1 = smoothstep( 0.0, 0.5, uCollapse );
      float c2 = smoothstep( 0.45, 0.85, uCollapse );
      float c3 = smoothstep( 0.85, 1.0, uCollapse );
      vec2 sq = vec2( mix( 1.0, 0.006, c2 ), mix( 1.0, 0.005, c1 ) );
      vec2 cuv = 0.5 + ( vUv - 0.5 ) / sq;
      float onScreen = box( cuv, 1.5 * px / sq );

      // Camera override viewport (commercials).
      vec2 uv = ( cuv - uView.xy ) / uView.zw;
      float inView = box( uv, px / uView.zw );

      // Commercial CRT barrel.
      vec2 cc = uv - 0.5;
      float k = 0.2 * uCrt;
      uv = 0.5 + cc * ( 1.0 - k * 0.5 + k * 2.0 * dot( cc, cc ) );
      inView *= mix( 1.0, box( uv, 2.0 * px ), step( 0.001, uCrt ) );

      // Vertical roll / hold slip.
      float slip = smoothstep( 0.65, 1.0, uDamage );
      float ry = uv.y + uRollPhase;
      float seam = 1.0 - smoothstep( 0.0, 0.035, min( fract( ry ), 1.0 - fract( ry ) ) );
      uv.y = fract( ry );

      // Line jitter (signal loss / static).
      vec2 dir = uv - 0.5;
      float edge = dot( dir, dir ) * 4.0;
      float line = floor( uv.y * 200.0 );
      float jit = h12( vec2( line, floor( uTime * 30.0 ) ) ) - 0.5;
      uv.x += jit * ( 0.012 * uDamage * edge + 0.006 * uStatic + 0.004 * uCrt * step( 0.97, h12( vec2( line, floor( uTime * 8.0 ) ) ) ) );

      // Chromatic aberration growing toward the edges.
      float ca = ( 0.4 + uChroma + uDamage * 4.0 + uCrt * 1.5 ) * px.x;
      vec2 off = dir * ca * ( 0.35 + edge ) * 2.0;
      vec3 col = daSafe( vec3( texture2D( tDiffuse, uv + off ).r, texture2D( tDiffuse, uv ).g, texture2D( tDiffuse, uv - off ).b ) );

      // Grade: saturation, contrast (around linear mid-grey), warm tint, purple-lifted shadows.
      float L = dot( col, vec3( 0.2126, 0.7152, 0.0722 ) );
      col = mix( vec3( L ), col, uSaturation );
      col = 0.18 * pow( max( col, vec3( 0.0 ) ) / 0.18, vec3( uContrast ) );
      col *= mix( vec3( 1.0 ), vec3( 1.045, 1.0, 0.93 ), uWarmth );
      col += uLift * 0.018 * ( 1.0 - smoothstep( 0.0, 0.2, L ) );

      // Signal-loss static from the edges + full-screen snow.
      vec2 q = vUv - 0.5;
      float n = h12( floor( vUv * uRes * 0.5 ) + floor( uTime * 30.0 ) * vec2( 17.3, 91.7 ) );
      vec3 snow = vec3( n * n ) * vec3( 1.35, 1.45, 1.6 );
      float r = length( q * vec2( 1.25, 1.0 ) ) * 2.0;
      float emask = smoothstep( 1.25 - 0.75 * uDamage, 1.45, r + ( n - 0.5 ) * 0.25 ) * uDamage;
      col = mix( col, snow, clamp( emask, 0.0, 0.95 ) );
      col = mix( col, snow * 1.1, uStatic );

      // Scanlines (HUD/crt) and the roll seam.
      float sl = 0.5 + 0.5 * cos( vUv.y * uRes.y * PI );
      col *= 1.0 - ( uScanlines * 0.25 + uCrt * 0.3 ) * ( 1.0 - sl );
      col *= 1.0 - seam * 0.7 * clamp( uRoll + slip, 0.0, 1.0 );

      // Vignette: subtle base + extra + commercial.
      float vig = 0.28 + uVignette * 0.6 + uCrt * 0.35;
      col *= 1.0 - vig * smoothstep( 0.45, 1.25, length( q * vec2( 1.3, 1.0 ) ) * 1.6 );

      // Whiteout and grain.
      col = mix( col, vec3( 7.0 ), uWhiteout );
      col += ( h12( vUv * uRes + fract( uTime * 13.7 ) * 311.0 ) - 0.5 ) * uGrain * ( 0.2 + L );

      // Clip to viewport and collapse; the collapsing line/dot glows white-hot.
      col *= inView;
      col = mix( col, vec3( 5.0 ), c1 * 0.9 );
      float halo = exp( -abs( vUv.y - 0.5 ) / 0.012 ) * exp( -max( abs( vUv.x - 0.5 ) - 0.5 * sq.x, 0.0 ) / 0.012 );
      col = col * onScreen + vec3( 1.6, 1.8, 2.2 ) * halo * c1 * ( 1.0 - onScreen );
      col *= 1.0 - c3;
      gl_FragColor = vec4( max( col, vec3( 0.0 ) ), 1.0 );
      // Folded OutputPass: ACES + sRGB (three injects both when this pass renders to the screen).
      #include <tonemapping_fragment>
      #include <colorspace_fragment>
    }`,
};

// The bloom high-pass is the only reader of the scene target inside UnrealBloomPass: sanitizing it keeps the
// whole mip chain finite (a NaN scene pixel then stays one local pixel, which the grade also sanitizes).
function guardBloom(bloom) {
  const m = bloom.materialHighPassFilter;
  const fetch = 'vec4 texel = texture2D( tDiffuse, vUv );';
  if (!m || !m.fragmentShader.includes(fetch)) {
    console.warn('[render] bloom NaN guard not installed (UnrealBloomPass high-pass shader changed)');
    return;
  }
  m.fragmentShader = m.fragmentShader
    .replace('void main() {', `${SAFE_GLSL}\n\t\tvoid main() {`)
    // alpha too: the bloom is blended back with SRC_ALPHA, so a NaN alpha would poison every pixel as well
    .replace(fetch, `${fetch}\n\t\t\ttexel = vec4( daSafe( texel.rgb ), daSafe( vec3( texel.a ) ).x );`);
  m.needsUpdate = true;
}

// Two-pass twins (render.twoPassTwins). three's renderObject draws a transparent DoubleSide material as
//   side = BackSide; needsUpdate; renderBufferDirect(...); side = FrontSide; needsUpdate; renderBufferDirect(...)
// and each needsUpdate forces a full program re-selection + uniform upload for that draw. Material.onBeforeRender
// (called right before that branch) marks such a material; the renderBufferDirect wrapper then undoes the flip's
// version bump and draws a twin fixed to the pass's side: Object.create(material) with its own id / side /
// version, so every property, map and uniform (onBeforeCompile's, ShaderMaterial.uniforms) is read live from the
// material itself, and the twin resolves to the same program the material compiled for that side. A real change
// of the material (its owner's needsUpdate) still bumps its version, which the twins follow. Materials with their
// own onBeforeRender keep three's path. Shadow/depth draws are untouched.
let _twinId = 1 << 30;
function makeTwin(m, side) {
  const tw = Object.create(m);
  Object.defineProperty(tw, 'id', { value: _twinId++ });
  tw.uuid = THREE.MathUtils.generateUUID();
  tw.side = side;
  tw.version = 0;
  tw._daSrcV = m.version;
  tw._daTP = 0;
  tw._daTwinB = tw._daTwinF = undefined;
  tw._listeners = undefined; // own event listeners (three registers its dispose handler per material)
  if (side === THREE.BackSide) m._daTwinB = tw; else m._daTwinF = tw;
  m.addEventListener('dispose', () => tw.dispose());
  return tw;
}
function installTwoPassTwins(renderer, owner) {
  const proto = THREE.Material.prototype;
  if (!proto._daTwinHook) {
    proto._daTwinHook = true;
    proto.onBeforeRender = function () {
      if (this.transparent === true && this.side === THREE.DoubleSide && this.forceSinglePass === false) this._daTP = owner.twoPassTwins ? 2 : 0;
    };
  }
  const rbd = renderer.renderBufferDirect;
  renderer.renderBufferDirect = function (camera, scene, geometry, material, object, group) {
    if (material._daTP > 0) {
      material._daTP--;
      material.version--; // the side flip is not a change of the material
      const side = material.side;
      let tw = side === THREE.BackSide ? material._daTwinB : material._daTwinF;
      if (!tw || Object.getPrototypeOf(tw) !== material) tw = makeTwin(material, side);
      if (tw._daSrcV !== material.version) { tw._daSrcV = material.version; tw.version++; }
      return rbd.call(this, camera, scene, geometry, tw, object, group);
    }
    return rbd.call(this, camera, scene, geometry, material, object, group);
  };
}

// Four boxes into two mat4 uniforms (materials.js uOccBox0/1, uOccWall0/1): columns min.xyz + level, max.xyz.
function occBoxes(M0, M1, list, n) {
  for (let i = 0; i < 4; i++) {
    const M = i < 2 ? M0 : M1;
    if (!M) continue;
    const e = M.value.elements, j = (i & 1) * 8, b = i < n ? list[i] : null;
    if (b) {
      e[j] = b.min.x; e[j + 1] = b.min.y; e[j + 2] = b.min.z; e[j + 3] = b.level;
      e[j + 4] = b.max.x; e[j + 5] = b.max.y; e[j + 6] = b.max.z; e[j + 7] = 0;
    } else e[j + 3] = 0;
  }
}

export class Render {
  constructor(game) {
    this.game = game;
    const renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: 'high-performance' });
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.05;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFShadowMap; // r186: PCF with shadow.radius = soft Vogel-disk filtering
    renderer.info.autoReset = false;
    // Perf: opaque draws grouped by shader program first (three sorts by material id, which interleaves the toon
    // variants: ~210 program switches in a 520-draw view, and every switch re-uploads the camera + all light
    // uniforms). Same image: opaque surfaces are depth-tested; within a program the order is material, then
    // front to back as before.
    const props = renderer.properties;
    let sortFrame = 0;
    const progId = (m) => {
      if (m._daSortF !== sortFrame) {
        const p = props.get(m).currentProgram;
        m._daSortP = p ? p.id : 0;
        m._daSortF = sortFrame;
      }
      return m._daSortP;
    };
    this.programSort = true;
    renderer.setOpaqueSort((a, b) => {
      if (a.groupOrder !== b.groupOrder) return a.groupOrder - b.groupOrder;
      if (a.renderOrder !== b.renderOrder) return a.renderOrder - b.renderOrder;
      if (this.programSort) {
        const pa = progId(a.material), pb = progId(b.material);
        if (pa !== pb) return pa - pb;
      }
      if (a.material.id !== b.material.id) return a.material.id - b.material.id;
      if (a.materialVariant !== b.materialVariant) return a.materialVariant - b.materialVariant;
      if (a.z !== b.z) return a.z - b.z;
      return a.id - b.id;
    });
    this._nextSortFrame = () => { sortFrame++; };
    // Perf: transparent double-sided materials (glass, lenses, FX cards) are drawn by three in two passes (back
    // faces, then front faces) by flipping material.side + needsUpdate before each pass, so every such draw
    // re-selects its program (getParameters + cache key) and re-uploads all its uniforms (~6-20 per frame).
    // twoPassTwins: the two passes draw two fixed-side twins of the material instead (see installTwoPassTwins):
    // same draws, same order, same programs, no re-selection. False = three's own path (A/B).
    this.twoPassTwins = true;
    installTwoPassTwins(renderer, this);
    // Camera occlusion fade (materials.js uOcc*, camera.js cam.occ): enabled for the gameplay main render only.
    this.occlusionFade = true;
    renderer.domElement.style.cssText = 'position:fixed;inset:0;width:100%;height:100%;display:block;outline:none';
    renderer.domElement.tabIndex = 0;
    document.body.appendChild(renderer.domElement);
    this.renderer = renderer;

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color('#150F1C');
    // A Fog always exists (toggling scene.fog would recompile every program); lights.js drives it per area.
    this.scene.fog = new THREE.Fog('#150F1C', 1000, 2000);
    // Perf: every scene render starts with scene.updateMatrixWorld(); hidden top-level branches (hero samples and
    // pools, FX pools, ...: ~500 nodes) skip it and catch up on the first render where they are visible again, like
    // level.js's hidden area roots. getWorldPosition()/updateWorldMatrix() still walk their parent chain on demand.
    this.skipHiddenRoots = true;
    const scene = this.scene;
    scene.updateMatrixWorld = function (force) {
      if (this.matrixAutoUpdate) this.updateMatrix();
      if (this.matrixWorldNeedsUpdate || force) {
        this.matrixWorld.copy(this.matrix);
        this.matrixWorldNeedsUpdate = false;
        force = true;
      }
      const ch = this.children, skip = this === scene && scene._daSkip;
      for (let i = 0, l = ch.length; i < l; i++) {
        const c = ch[i];
        if (!skip || c.visible) c.updateMatrixWorld(force);
      }
    };
    Object.defineProperty(scene, '_daSkip', { get: () => this.skipHiddenRoots });

    // near 0.1 (was 0.05): twice the depth precision everywhere (trims, decals, frames stop shimmering at range);
    // the camera probe keeps the eye >= 0.23 m from walls and the hero dither-fades under 0.8 m, so nothing clips.
    this.camera = new THREE.PerspectiveCamera(70, innerWidth / innerHeight, 0.1, 260);
    this.camera.layers.enable(LAYERS.ZOMBIES);
    this.scene.add(this.camera);

    this.post = {
      saturation: 1, damage: 0, static: 0, roll: 0, whiteout: 0, scanlines: 0, crt: 0, collapse: 0,
      vignette: 0, chroma: 0, contrast: 1.06, warmth: 1, grain: 0.03,
    };

    this.maxPixelRatio = Math.min(window.devicePixelRatio || 1, 1.5);
    this.pixelRatio = this.maxPixelRatio;
    this.dynamic = true;
    this._fpsAvg = 60;
    this._lowT = 0;
    this._highT = 0;
    this._rollPhase = 0;
    this._override = null;
    this._overrideAspect = 4 / 3;
    this._fx = new Map();            // owner -> { knobs, until }: temporary effect layers (setFx)
    this._eff = {};                  // effective knob values of the current frame (render.post + layers)
    this._prePasses = [];
    this._preErrT = -1e9;
    this._mainHooks = [];            // addMainHook: level.js object portal culling + shadow-only caster proxies
    this._inMain = false;

    const target = new THREE.WebGLRenderTarget(innerWidth, innerHeight, { type: THREE.HalfFloatType, samples: 4 });
    this.composer = new EffectComposer(renderer, target);
    // Only the scene render needs MSAA: the ping-pong target that receives GradePass is single-sampled (a
    // multisampled full-screen write + resolve costs ~4 ms on Iris Xe). frame() pins the scene to renderTarget1.
    this.composer.renderTarget2.samples = 0;
    this.renderPass = new RenderPass(this.scene, this.camera);
    this.bloom = new UnrealBloomPass(new THREE.Vector2(innerWidth, innerHeight), BLOOM.strength, BLOOM.radius, BLOOM.threshold);
    guardBloom(this.bloom);
    this.grade = new ShaderPass(GradeShader);
    this.output = null; // folded into GradePass (one full-screen pass less); GradePass is the last pass
    this.composer.addPass(this.renderPass);
    // Main-pass hooks: before(camera) runs right before the gameplay scene render (after the pre-passes), shadow()
    // when the key shadow map starts rendering inside that render, after() once it is done (always, even on throw).
    // Only the gameplay render triggers them (not the menu / ending scenes, the commercial camera or feed passes).
    const rp = this.renderPass, rpRender = rp.render.bind(rp);
    rp.render = (...a) => this._mainRender(rpRender, a);
    const sm = renderer.shadowMap, smRender = sm.render.bind(sm);
    sm.render = (lights, scene, camera) => {
      if (this._inMain) this._runHooks('shadow');
      return smRender(lights, scene, camera);
    };
    this.composer.addPass(this.bloom);
    this.composer.addPass(this.grade);

    this._onResize = () => this.resize();
    window.addEventListener('resize', this._onResize);
    this.resize();
  }

  init() {
    const p = this.game.params;
    this.dynamic = p.dynres !== 0 && !p.shot;
  }

  reset() {
    Object.assign(this.post, { saturation: 1, damage: 0, static: 0, roll: 0, whiteout: 0, scanlines: 0, crt: 0, collapse: 0, vignette: 0, chroma: 0 });
    this._rollPhase = 0;
    this._fx.clear();
    this.setCameraOverride(null);
  }

  // ---- temporary effect layers (see the header)
  setFx(owner, knobs, { ttl = Infinity } = {}) {
    let L = this._fx.get(owner);
    if (!L) { L = { knobs: null, until: Infinity }; this._fx.set(owner, L); }
    L.knobs = knobs || {};
    L.until = Number.isFinite(ttl) ? this.game.time.realNow + Math.max(0, ttl) : Infinity;
    return L;
  }

  clearFx(owner) { return this._fx.delete(owner); }
  clearAllFx() { this._fx.clear(); }
  hasFx(owner) { return this._fx.has(owner); }

  // render.post combined with the live layers (expired layers are dropped here), written into this._eff.
  _effective() {
    const p = this.post, e = this._eff;
    e.roll = p.roll; e.chroma = p.chroma; e.scanlines = p.scanlines; e.static = p.static; e.whiteout = p.whiteout;
    e.crt = p.crt; e.collapse = p.collapse; e.vignette = p.vignette; e.damage = p.damage; e.grain = p.grain;
    e.saturation = p.saturation;
    if (this._fx.size) {
      const now = this.game.time.realNow;
      for (const [owner, L] of this._fx) {
        if (now > L.until) { this._fx.delete(owner); continue; }
        const k = L.knobs;
        for (const name in k) {
          const v = k[name];
          if (typeof v !== 'number' || !Number.isFinite(v)) continue;
          if (name === 'saturation') e.saturation *= v;
          else if (name in e && v > e[name]) e[name] = v;
        }
      }
    }
    return e;
  }

  resize() {
    const w = Math.max(1, innerWidth), h = Math.max(1, innerHeight);
    this.renderer.setPixelRatio(this.pixelRatio);
    this.renderer.setSize(w, h, false);
    this.composer.setPixelRatio(this.pixelRatio);
    this.composer.setSize(w, h);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.grade.uniforms.uRes.value.set(w * this.pixelRatio, h * this.pixelRatio);
    this._updateView();
  }

  setPixelRatio(pr) {
    const v = THREE.MathUtils.clamp(pr, MIN_PR, this.maxPixelRatio);
    if (Math.abs(v - this.pixelRatio) < 1e-3) return;
    this.pixelRatio = v;
    this.resize();
  }

  // Render from `camera` into a centered viewport of `aspect` (null restores the gameplay camera).
  setCameraOverride(camera, { aspect = 4 / 3 } = {}) {
    this._override = camera || null;
    this._overrideAspect = aspect;
    if (camera) {
      camera.aspect = aspect;
      camera.updateProjectionMatrix();
    }
    this.renderPass.camera = camera || this.camera;
    this._updateView();
  }

  get cameraOverride() { return this._override; }

  _updateView() {
    const v = this.grade.uniforms.uView.value;
    if (!this._override) { v.set(0, 0, 1, 1); return; }
    const screen = innerWidth / innerHeight;
    if (this._overrideAspect < screen) {
      const w = this._overrideAspect / screen;
      v.set((1 - w) / 2, 0, w, 1);
    } else {
      const h = screen / this._overrideAspect;
      v.set(0, (1 - h) / 2, 1, h);
    }
  }

  // fn(renderer) runs before the main render each frame; returns an unsubscribe function.
  addPrePass(fn) {
    this._prePasses.push(fn);
    return () => {
      const i = this._prePasses.indexOf(fn);
      if (i >= 0) this._prePasses.splice(i, 1);
    };
  }

  // hook = { before(camera), shadow(), after() } (all optional); returns an unsubscribe function.
  addMainHook(hook) {
    this._mainHooks.push(hook);
    return () => {
      const i = this._mainHooks.indexOf(hook);
      if (i >= 0) this._mainHooks.splice(i, 1);
    };
  }

  _runHooks(name, arg) {
    for (let i = 0; i < this._mainHooks.length; i++) {
      const f = this._mainHooks[i][name];
      if (!f) continue;
      try {
        f(arg);
      } catch (err) {
        const now = performance.now();
        if (now - this._preErrT > 5000) { this._preErrT = now; console.error('[system:render.mainHook]', err); }
      }
    }
  }

  _mainRender(rpRender, args) {
    const rp = this.renderPass;
    const main = !this._override && rp.scene === this.scene && rp.camera === this.camera;
    const occ = main && this._occBegin();
    try {
      if (!main || this._mainHooks.length === 0) return rpRender(...args);
      this._inMain = true;
      this._runHooks('before', rp.camera);
      try {
        return rpRender(...args);
      } finally {
        this._inMain = false;
        this._runHooks('after');
      }
    } finally {
      if (occ) this.game.mats.uniforms.uOccAmt.value = 0;
    }
  }

  // Camera occlusion uniforms for this main render from camera.js's cam.occ (NDC ellipse -> scene-target pixels,
  // occluder boxes). Only when cam.occ was computed for the camera exactly as it renders now (another system moving
  // the camera, e.g. a cutscene, turns it off). Returns true when the fade is on (it is switched off again right
  // after the render: feeds, menus, the ending and every other pass see uOccAmt = 0).
  _occBegin() {
    const U = this.game.mats && this.game.mats.uniforms;
    const cam = this.game.cam, o = cam && cam.occ;
    if (!this.occlusionFade || !U || !U.uOccAmt || !o || !(o.amt > 0.001) || !cam.occValid(this.camera)) return false;
    const t = this.composer.renderTarget1, W = t.width, H = t.height;
    U.uOccRect.value.set((o.cx * 0.5 + 0.5) * W, (o.cy * 0.5 + 0.5) * H, 2 / Math.max(1e-3, o.rx * W), 2 / Math.max(1e-3, o.ry * H));
    U.uOccZ.value.set(o.zFull, o.zSoft, 0, o.feetY);
    // boxes (occluders, then protected walls): two per matrix, columns min.xyz + level / max.xyz (unused: w 0)
    occBoxes(U.uOccBox0, U.uOccBox1, o.boxes, o.n);
    occBoxes(U.uOccWall0, U.uOccWall1, o.walls, o.nw || 0);
    U.uOccAmt.value = o.amt;
    return true;
  }

  setLayerRecursive(object3d, layer) {
    object3d.traverse((o) => o.layers.set(layer));
  }

  frame(dt) {
    this._nextSortFrame();
    this._dynamicResolution(dt);
    const p = this._effective();
    const u = this.grade.uniforms;
    // Roll phase: rolls while `roll` (or the damage hold slip) is up, then settles back on a frame boundary.
    const slip = THREE.MathUtils.smoothstep(p.damage, 0.65, 1.0);
    const speed = p.roll * 1.4 + slip * 0.35;
    if (speed > 0.001) this._rollPhase += dt * speed;
    else this._rollPhase = THREE.MathUtils.damp(this._rollPhase, Math.round(this._rollPhase), 6, dt);
    this._rollPhase %= 8;

    u.uTime.value = this.game.time.realNow;
    u.uSaturation.value = p.saturation;
    u.uContrast.value = this.post.contrast;
    u.uWarmth.value = this.post.warmth;
    u.uGrain.value = p.grain;
    u.uVignette.value = p.vignette;
    u.uChroma.value = p.chroma;
    u.uDamage.value = p.damage;
    u.uStatic.value = p.static;
    u.uRoll.value = p.roll;
    u.uRollPhase.value = this._rollPhase;
    u.uWhiteout.value = p.whiteout;
    u.uScanlines.value = p.scanlines;
    u.uCrt.value = p.crt;
    u.uCollapse.value = p.collapse;
    this.bloom.strength = BLOOM.strength + p.whiteout * 2.5;

    for (let i = 0; i < this._prePasses.length; i++) {
      try {
        this._prePasses[i](this.renderer);
      } catch (err) {
        const now = performance.now();
        if (now - this._preErrT > 5000) { this._preErrT = now; console.error('[system:render.prePass]', err); }
      }
    }
    // Pin the buffers so RenderPass always draws into the MSAA target, whatever the number of swapping passes.
    const c = this.composer;
    c.readBuffer = c.renderTarget1;
    c.writeBuffer = c.renderTarget2;
    c.render(dt);
  }

  // Drop the pixel ratio in 0.1 steps when the average fps stays < 50 for 2 s; raise it again above 58.
  _dynamicResolution(dt) {
    if (!this.dynamic || dt <= 0) return;
    this._fpsAvg = THREE.MathUtils.lerp(this._fpsAvg, 1 / dt, Math.min(1, dt * 2));
    this._lowT = this._fpsAvg < 50 ? this._lowT + dt : 0;
    this._highT = this._fpsAvg > 58 ? this._highT + dt : 0;
    if (this._lowT > 2 && this.pixelRatio > MIN_PR) {
      this._lowT = 0;
      this.setPixelRatio(this.pixelRatio - 0.1);
    } else if (this._highT > 2 && this.pixelRatio < this.maxPixelRatio) {
      this._highT = 0;
      this.setPixelRatio(this.pixelRatio + 0.1);
    }
  }
}
