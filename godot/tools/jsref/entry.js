// DEAD AIR godot-core QA: minimal three.js harness around the ORIGINAL render.js / materials.js / lights.js /
// geo.js / textures.js, used to render reference images of tools/material_test_scene.json and to bake the
// RoomEnvironment PMREM atlas (shaders/data/room_env.res). Bundled by build.mjs (esbuild), driven by run.mjs.
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { Render } from '../../../src/core/render.js';
import { Materials } from '../../../src/core/materials.js';
import { Lights } from '../../../src/core/lights.js';
import * as geo from '../../../src/core/geo.js';
import * as tex from '../../../src/core/textures.js';

function makeGame(spec) {
  const game = {
    params: { shot: 1 }, time: { now: 0, dt: 0, realNow: 0, realDt: 0, frame: 0, scale: 1 },
    events: { on() { return () => {}; }, emit() {} }, state: 'playing', level: null, cam: null,
  };
  game.render = new Render(game);
  game.render.dynamic = false;
  game.renderer = game.render.renderer;
  game.scene = game.render.scene;
  game.camera = game.render.camera;
  game.mats = new Materials(game);
  game.machines = { powerOn: spec.powered !== false };
  game.player = { pos: new THREE.Vector3().fromArray(spec.focus || [0, 0, 0]) };
  game.lights = new Lights(game);
  game.tex = new tex.Textures(game);
  return game;
}

function makeGeo(g) {
  const [kind, ...a] = g;
  return geo[kind](...a);
}

async function loadTex(url) {
  return await new Promise((res) => new THREE.TextureLoader().load(url, (t) => { t.colorSpace = THREE.SRGBColorSpace; res(t); }));
}

async function makeMat(game, m, base) {
  const o = { ...(m.opts || {}) };
  if (o.side === 'double') o.side = THREE.DoubleSide; else if (o.side === 'back') o.side = THREE.BackSide; else if (o.side === 'front') o.side = THREE.FrontSide;
  let map = null;
  if (m.map) {
    map = await loadTex(base + m.map);
    if (m.mapWrap === 'repeat') { map.wrapS = map.wrapT = THREE.RepeatWrapping; }
    map.needsUpdate = true;
  }
  const M = game.mats;
  switch (m.kind) {
    case 'glow': { const it = o.intensity ?? 2; delete o.intensity; if (map) o.map = map; return M.glow(m.color, it, o); }
    case 'basic': if (map) o.map = map; return M.basic(m.color, o);
    case 'glass': return M.glass(m.color, o);
    case 'skin': return M.skin(m.color, o);
    case 'screen': return M.screen(map, o);
    case 'rubberGlass': return M.rubberGlass(map, o);
    default: if (map) o.map = map; return M.toon(m.color, o);
  }
}

window.__mref = {
  THREE, RoomEnvironment, Render, Materials, Lights, geo, tex,
  // Builds the scene of a material_test_scene.json spec, advances `frames` fixed steps and renders.
  async run(spec, base) {
    const game = makeGame(spec);
    window.__game = game;
    const U = game.mats.uniforms;
    for (const k in spec.globals || {}) {
      const v = spec.globals[k];
      if (Array.isArray(v)) U[k].value.fromArray(v); else U[k].value = v;
    }
    Object.assign(game.render.post, spec.post || {});
    const cam = game.camera;
    cam.fov = spec.camera.fov ?? 70; cam.near = spec.camera.near ?? 0.1; cam.far = spec.camera.far ?? 260;
    cam.position.fromArray(spec.camera.pos);
    cam.lookAt(new THREE.Vector3().fromArray(spec.camera.target));
    cam.updateProjectionMatrix();
    if (spec.fog) { game.scene.fog.color.set(spec.fog.color); game.scene.fog.near = spec.fog.near; game.scene.fog.far = spec.fog.far; }
    for (const a of spec.anchors || []) game.lights.addAnchor({ ...a });
    for (const ob of spec.objects || []) {
      const mat = await makeMat(game, ob.mat, base);
      const g = ob.ao ? geo.withAO(makeGeo(ob.geo), ob.ao) : makeGeo(ob.geo);
      const mesh = geo.mesh(g, mat, { pos: ob.pos, rot: ob.rot, scale: ob.scale, cast: ob.cast ?? true });
      if (ob.bulge !== undefined && mat.uniforms && mat.uniforms.uBulge) mat.uniforms.uBulge.value = ob.bulge;
      game.scene.add(mesh);
    }
    const dt = 1 / 30;
    const frames = spec.frames ?? 45;
    for (let i = 0; i < frames; i++) {
      game.time.realNow += dt; game.time.now += dt; game.time.frame++;
      game.lights.update(dt);
      // the fixed focus/area values of the spec override what lights.js computed from the (absent) level
      if (spec.hemi) {
        game.lights.hemi.color.set(spec.hemi.sky); game.lights.hemi.groundColor.set(spec.hemi.ground);
        game.lights.hemi.intensity = spec.hemi.intensity;
      }
      game.mats.update();
      if (spec.time !== undefined) U.uTime.value = spec.time;
      game.render.frame(dt);
    }
    return { w: game.renderer.domElement.width, h: game.renderer.domElement.height, png: game.renderer.domElement.toDataURL('image/png') };
  },
  // The RoomEnvironment PMREM atlas of materials.js as raw RGBA half floats (row 0 = GL bottom row).
  bakeEnv() {
    const renderer = new THREE.WebGLRenderer();
    const pmrem = new THREE.PMREMGenerator(renderer);
    const room = new RoomEnvironment();
    const rt = pmrem.fromScene(room, 0.04);
    const w = rt.width, h = rt.height;
    const buf = new Uint16Array(w * h * 4);
    renderer.readRenderTargetPixels(rt, 0, 0, w, h, buf);
    const bytes = new Uint8Array(buf.buffer);
    let s = '';
    for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return { w, h, b64: btoa(s) };
  },
};
