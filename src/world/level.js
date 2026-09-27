// Level (ARCHITECTURE §7, §12): builds WZTV Channel 13 from layout.js — collision shell, the batched graybox with
// per-area finishes (architecture.js), doors and their opening beats (doors.js), windows/boards/fence/gate
// (windows.js), the street, skyline, night sky and tower (exterior.js) — then lets every rooms/<areaId>.js dress
// its area and merges static meshes per area and material. Owns portal culling, the Sign-On light switch-over
// and the level's animations.
//
// Scene graph: root 'level' → area:<id> (walls, floor, fixtures, windows frames, 'ceiling', 'dressing' → rooms),
//   'shell' (exterior faces, copings, wall tops; 'roof'), 'doors' (door:<id>), 'boards' (6 InstancedMeshes),
//   'exterior' (street, storefronts, skyline, tower), 'sky' (follows the camera). shell/exterior/boards/sky are
//   never culled; the boards and the always-visible exterior are occluded by walls.
//
// Public API (game.level)
//   col (Collision), areas {id → layout area}, anchors {id → { ...layout fields, pos:Vector3, rotY, area,
//   target:Vector3|null }}, doors {id → Door (doors.js): layout fields + open:bool, pos, approach, meshes,
//   setOnAir(on)}, windows {id → Win (windows.js): layout fields + boards, boardMeshes, breakBoard(),
//   repairBoard(), breakAll(), pos}, screenSpawns {id → { ...layout, pos:Vector3 }}, surf (surfaces.js),
//   root, areaRoots {id → Group}, powered (bool), culling (bool, default true), shadowCull (bool, default true:
//   only the player/camera areas, and an area behind an open door within 6 m, cast into the key shadow map)
//   init() → build(); listens to power:on        reset() closes doors, re-boards windows, powers down
//   update(dt) door/board animations, Sign-On light sequence (real time), tower beacons
//   lateUpdate() portal culling + sky follow      cull(camera?) the same on demand
//   areaAt(x, z) → area id | null                 surfaceAt(x, z, y=0) → 'carpet'|'tile'|'wood'|'gravel'|'metal'
//   openDoor(id, {instant}) → bool  (animates, disables the collider, nav.setDoor, emits door:open)
//   openAllDoors({instant=true})                  setAreaVisible(id, bool)
//   renderWith(areaIds, fn) shows those areas (+ their door groups) while fn runs, then restores culling
//   setPower(on, {instant}) fixtures, light anchors and ON AIR boxes switch as the color wave (15 m/s from the
//     lever) reaches them, with a 3-flash flicker; tower beacons start blinking 3.4 s after power:on (t = 6 s)
//   setOnAir(on, doorId?)                         setCeilingsVisible(bool) (plan views / free camera)
// Sounds played here: crowd_ooh + the door look's cue on purchase, board_tear/board_repair, light_thunk,
// onair_clack. DY (requiresPower) is opened by machines/signon through openDoor (buzz-and-swing beat).

import * as THREE from 'three';
import * as geo from '../core/geo.js';
import { AREAS, DOORS, ANCHORS, SCREEN_SPAWNS, PLATFORMS, FLOOR_PATCHES, areaAt } from './layout.js';
import { Collision } from './collision.js';
import { addShellColliders } from './shell.js';
import { createSurfaces, AREA_STYLE } from './surfaces.js';
import { Batch } from './batch.js';
import { buildArchitecture } from './architecture.js';
import { buildExterior } from './exterior.js';
import { Door } from './doors.js';
import { buildWindows } from './windows.js';
import { buildShadowProxies, bakeMaterialColors, buildAreaBatchesSteps } from './staticopt.js';
import * as lobby from './rooms/lobby.js';
import * as newsroom from './rooms/newsroom.js';
import * as greenRoom from './rooms/green_room.js';
import * as studioA from './rooms/studio_a.js';
import * as studioB from './rooms/studio_b.js';
import * as masterControl from './rooms/master_control.js';
import * as yard from './rooms/yard.js';

const ROOMS = {
  lobby, newsroom, green_room: greenRoom, studio_a: studioA, studio_b: studioB, master_control: masterControl, yard,
};
const WAVE_SPEED = 15;                 // GDD §10.1 color wave, m/s
const SHADOW_DOOR_R = 6;               // m: an area seen through an open door casts shadows once the player or
                                       // the camera is this close to that door (no pop when crossing it)
const BEACON_DELAY = 6.0 - 2.6;        // beacons start with DY at t = 6.0 s; power:on fires at t = 2.6 s
const FLICKER = [[0, true], [0.07, false], [0.14, true], [0.22, false], [0.3, true]];
const LEVER = new THREE.Vector3(...ANCHORS.sign_on_lever.pos).setY(1);
const NO_CAST = new Set([
  ...Object.values(AREA_STYLE).map((s) => s.floor), 'metal_plate', 'trim_steel', 'chainlink', 'roof_gravel',
  ...Object.values(AREA_STYLE).map((s) => s.ceiling).filter(Boolean),
]);
const _eye = new THREE.Vector3();

export class Level {
  constructor(game) {
    this.game = game;
    this.col = new Collision();
    this.root = new THREE.Group();
    this.root.name = 'level';
    this.areas = {};
    this.anchors = {};
    this.doors = {};
    this.windows = {};
    this.screenSpawns = {};
    this.areaRoots = {};
    this.groups = {};
    this.culling = true;
    this.shadowCull = true;
    this.powered = false;
    this.built = false;
    this._visible = new Set();
    this.objectCull = true;            // perf: per-object portal culling of the areas seen through doors
    this._portals = new Map();         // areaId -> [chain]; chain = [{ d, far }] (see cull())
    this._hop1 = [];
    this._hidden = [];                 // objects portalBegin() hid for the main pass (portalEnd() shows them again)
    this._leaves = {};                 // areaId -> { t, list }: drawable leaves, rescanned every LEAF_RESCAN s
    this.shadowProxies = true;         // perf: static casters drawn into the shadow map as merged proxies
    this.skipHiddenMatrices = true;    // perf: hidden area roots skip scene.updateMatrixWorld()
    this.bakeColors = true;            // perf: static toon colours baked into vertex colours (staticopt.js)
    this.freezeStatic = true;          // perf: static nodes + the scene skip the per-frame matrix recompose
    this.areaBatches = true;           // perf: each area's opaque toon meshes drawn by a few batch meshes (staticopt.js;
                                       // URL abatch=0 off, abkeep=1 keeps the baked originals for setAreaBatches A/B)
    this.batches = null;               // staticopt AreaBatches
    this._static = null;
    this._proxies = [];
    this._shadowCast = new Set();
    this._shadowOff = {};
    this._switches = [];
    this._powerT = 0;
    this._powerDone = true;
    this._beaconT = -1;
  }

  init() {
    for (const _ of this.initSteps()) { /* run every step now */ }
  }

  // init() as a generator that yields between its heavy steps (architecture, exterior, doors + windows, the
  // batch, each room, the merges): Game's progressive boot runs one step per frame behind the title.
  *initSteps() {
    yield* this.buildSteps();
    if (this.game.events) this.game.events.on('power:on', () => this.setPower(true));
    const r = this.game.render;
    if (r && r.addMainHook) {
      r.addMainHook({
        before: (camera) => this.portalBegin(camera),
        shadow: () => { this.portalEnd(); this._showProxies(true); },
        after: () => { this.portalEnd(); this._showProxies(false); },
      });
    }
  }

  // ------------------------------------------------------------------------------------------------ build
  build() {
    for (const _ of this.buildSteps()) { /* run every step now */ }
  }

  *buildSteps() {
    if (this.built) return;
    this.built = true;
    const g = this.game;
    for (const a of AREAS) this.areas[a.id] = a;
    for (const [id, s] of Object.entries(ANCHORS)) {
      this.anchors[id] = {
        ...s, id, pos: new THREE.Vector3(...s.pos), rotY: s.rotY ?? 0, target: s.target ? new THREE.Vector3(...s.target) : null,
      };
    }
    for (const s of SCREEN_SPAWNS) this.screenSpawns[s.id] = { ...s, pos: new THREE.Vector3(...s.pos) };
    addShellColliders(this.col);

    const group = (name, parent = this.root, noMerge = false) => {
      const o = new THREE.Group();
      o.name = name;
      if (noMerge) o.userData.noMerge = true;
      parent.add(o);
      return o;
    };
    for (const a of AREAS) {
      const r = group(`area:${a.id}`);
      this.areaRoots[a.id] = this.groups[a.id] = r;
      // Perf: a culled (hidden) area skips the matrix update of its whole subtree. renderer.render() walks the
      // scene (~3300 level nodes) once per scene render, the feed passes included; a hidden area catches up the
      // next time it is drawn, and getWorldPosition() / updateWorldMatrix() still walk their parent chain.
      r.updateMatrixWorld = (force) => {
        if (r.visible || !this.skipHiddenMatrices) THREE.Object3D.prototype.updateMatrixWorld.call(r, force);
      };
      this.groups[`${a.id}#ceil`] = group('ceiling', r, true);
    }
    this.groups.shell = group('shell');
    this.groups['shell#roof'] = group('roof', this.groups.shell);
    this.groups.ext = group('exterior');
    const doorRoot = group('doors');
    const boardRoot = group('boards');

    this.surf = createSurfaces(g);
    const batch = new Batch(this.surf);
    const ctx = { game: g, level: this, batch, surf: this.surf, group: (n) => this.groups[n], root: boardRoot };
    const { fixtures } = buildArchitecture(ctx);
    yield;
    const ext = buildExterior(ctx);
    yield;
    this.sky = ext.sky;
    this.beacons = ext.beacons;
    this.root.add(this.sky);
    for (const d of DOORS) {
      const door = new Door(ctx, d);
      this.doors[d.id] = door;
      doorRoot.add(door.group);
    }
    const win = buildWindows(ctx);
    this.boardSet = win.boards;
    for (const w of win.list) this.windows[w.id] = w;
    yield;
    batch.build((name) => this.groups[name],
      (name, key) => !NO_CAST.has(key) && name !== 'ext' && !name.includes('#'));
    yield;

    for (const a of AREAS) {
      const room = ROOMS[a.id];
      const dressing = group('dressing', this.areaRoots[a.id]);
      try {
        room.build(g, a, dressing);
      } catch (err) {
        console.error(`[rooms:${a.id}]`, err);
      }
      yield;
    }
    for (const id in this.areaRoots) geo.mergeByMaterial(this.areaRoots[id]);
    geo.mergeByMaterial(this.groups.ext);
    yield;
    // Perf (staticopt.js): material colours of static props -> vertex colours (one white material per toon
    // finish), static casters -> shadow-only proxies, then merge again: the colour variants and the cast /
    // non-cast copies of a material in an area become one mesh.
    if (this.bakeColors) this.bakeStats = bakeMaterialColors(g, Object.values(this.areaRoots));
    yield;
    for (const id in this.areaRoots) {
      if (this.shadowProxies) this._proxies.push(...buildShadowProxies(this.areaRoots[id]));
      geo.mergeByMaterial(this.areaRoots[id]);
    }
    yield;

    this._buildSwitches(fixtures);
    this.setPower(false, { instant: true });
    if (g.scene) g.scene.add(this.root);
    this.root.updateMatrixWorld(true);
    // Perf (staticopt.js area batches): what is left of each area's opaque toon meshes (the merged finishes, one-off
    // textured props, animated / switchable parts) is drawn by a few batch meshes per area.
    const p = g.params || {};
    if (this.areaBatches && p.abatch !== 0) {
      const out = {};
      // coplanar depth ties are checked against the area's other opaque meshes, its doors and the shell
      const tieRoots = (id) => [...Object.values(this.doors).filter((d) => d.areas.includes(id)).map((d) => d.group), this.groups.shell];
      yield* buildAreaBatchesSteps(g, this.areaRoots, { keep: p.abkeep === 1, follow: p.abfollow !== 0, ties: p.abties !== 0, tieRoots }, out);
      this.batches = out.result;
      // the batches' shadow-only twins (followed casters) show only while the key shadow map renders
      if (this.batches) for (const A of Object.values(this.batches.areas)) for (const b of A.batches) if (b.shadow) this._proxies.push(b.shadow);
    }
    this._collectStatic();
    if (this.freezeStatic) this.setStaticFrozen(true);
  }

  // A/B toggle of the area batches (complete only when built with abkeep=1).
  setAreaBatches(on) {
    if (!this.batches) return false;
    this.batches.setEnabled(on);
    this._leaves = {};
    return true;
  }

  // Perf: nodes that never move (the level / area / shell / exterior roots, 'dressing' and 'ceiling' groups, merged
  // meshes, batched architecture, shadow proxies) and the scene itself stop recomposing their matrices every frame.
  // With the scene's matrixAutoUpdate on, updateMatrixWorld() forced a compose + world multiply on all ~3000 nodes
  // per scene render (main + feeds). Everything else keeps matrixAutoUpdate (props, doors, sky, characters...): a
  // child still composes its own matrix against its frozen parent's (valid) world matrix, so nothing changes on
  // screen. Nothing in src touches matrixAutoUpdate / matrix directly, and these nodes are never moved.
  _collectStatic() {
    const list = [this.root, this.groups.shell, this.groups['shell#roof'], this.groups.ext];
    const add = (root) => {
      root.traverse((o) => {
        const n = o.name || '';
        if (o === root || n === 'dressing' || n === 'ceiling' || n.startsWith('merged:') || n.startsWith('batch:') || n.startsWith('abatch:') || o.userData.shadowProxy) list.push(o);
      });
    };
    for (const id in this.areaRoots) add(this.areaRoots[id]);
    add(this.groups.ext);
    add(this.groups.shell);
    this._static = [...new Set(list.filter(Boolean))];
  }

  setStaticFrozen(on) {
    this.staticFrozen = on;
    const sc = this.game.scene;
    if (sc) {
      if (on) { sc.updateMatrix(); sc.updateMatrixWorld(true); }
      sc.matrixAutoUpdate = !on;
    }
    for (const o of this._static || []) {
      if (on) { o.updateMatrix(); o.matrixAutoUpdate = false; } else o.matrixAutoUpdate = true;
    }
    if (on) this.root.updateMatrixWorld(true);
  }

  // Sign-On switch list: fixtures + their anchors per area, ON AIR boxes per door (by wave arrival time).
  _buildSwitches(fixtures) {
    const lights = this.game.lights;
    for (const f of fixtures) {
      this._switches.push({
        delay: f.dist / WAVE_SPEED, pos: f.center, sound: 'light_thunk',
        apply: (on) => {
          f.mesh.material = on ? f.post.mat : f.pre.mat;
          if (lights) for (const a of f.anchors) lights.setAnchor(a.id, on ? a.post : a.pre);
        },
      });
    }
    for (const d of Object.values(this.doors)) {
      if (!d.onAirBoxes.length) continue;
      this._switches.push({
        delay: LEVER.distanceTo(d.pos) / WAVE_SPEED, pos: d.pos, sound: 'onair_clack', apply: (on) => d.setOnAir(on),
      });
    }
  }

  // ----------------------------------------------------------------------------------------------- lifecycle
  reset() {
    for (const d of Object.values(this.doors)) {
      d.reset();
      this.col.setEnabled(d.id, true);
      if (this.game.nav && this.game.nav.setDoor) this.game.nav.setDoor(d.id, false);
    }
    for (const w of Object.values(this.windows)) w.reset();
    this.setPower(false, { instant: true });
  }

  update(dt) {
    if (!this.built) return;
    for (const id in this.doors) this.doors[id].update(dt);
    this.boardSet.update(dt);
    const t = this.game.time;
    const real = t && t.realDt !== undefined ? t.realDt : dt;
    this._updatePower(real);
    if (this.batches) this.batches.update();
    if (this._beaconT >= 0) {
      this._beaconT += real;
      if (this._beaconT >= BEACON_DELAY) this.beacons.set((this._beaconT - BEACON_DELAY) % 1 < 0.5);
    }
  }

  lateUpdate() {
    this.cull();
  }

  // ------------------------------------------------------------------------------------------------- queries
  areaAt(x, z) {
    return areaAt(x, z);
  }

  surfaceAt(x, z, y = 0) {
    for (const p of PLATFORMS) {
      const [x0, z0, x1, z1] = p.rect;
      if (x >= x0 && x < x1 && z >= z0 && z < z1 && y >= p.top - 0.25) return p.surface;
    }
    for (const p of FLOOR_PATCHES) {
      const [x0, z0, x1, z1] = p.rect;
      if (x >= x0 && x < x1 && z >= z0 && z < z1) return p.surface;
    }
    const a = areaAt(x, z);
    return a ? this.areas[a].floor : 'gravel';
  }

  // --------------------------------------------------------------------------------------------------- doors
  openDoor(id, { instant = false } = {}) {
    const d = this.doors[id];
    if (!d || d.open) return false;
    const g = this.game;
    d.open = true;
    this.col.setEnabled(id, false);
    if (g.nav && g.nav.setDoor) g.nav.setDoor(id, true);
    d.play(instant);
    if (!instant && d.cost > 0 && g.audio) g.audio.play('crowd_ooh', { pos: d.pos });
    if (g.events) g.events.emit('door:open', { doorId: id });
    return true;
  }

  openAllDoors({ instant = true } = {}) {
    for (const id in this.doors) this.openDoor(id, { instant });
  }

  setOnAir(on, doorId = null) {
    for (const d of Object.values(this.doors)) if (!doorId || d.id === doorId) d.setOnAir(on);
  }

  // ------------------------------------------------------------------------------------------------- culling
  setAreaVisible(id, visible) {
    const r = this.areaRoots[id];
    if (!r) return;
    r.visible = visible;
    for (const d of Object.values(this.doors)) {
      if (d.areas.includes(id)) d.group.visible = this.areaRoots[d.areas[0]].visible || this.areaRoots[d.areas[1]].visible;
    }
  }

  // Visible = the areas of the player and of the camera, every area behind one of their open doors, and a
  // second area when its open door can be seen through the first open door from the camera.
  cull(camera = this.game.camera) {
    if (!this.built) return;
    if (camera) this.sky.position.copy(camera.position);
    const vis = this._visible;
    vis.clear();
    const p = this.game.player;
    const here = [
      p && p.pos ? areaAt(p.pos.x, p.pos.z) : null,
      camera ? areaAt(camera.position.x, camera.position.z) : null,
    ].filter(Boolean);
    const hop = [];
    const culled = this.culling && here.length > 0;
    // Object portal culling (perf pass): every area seen through doors also records its portal chains, the door
    // openings the eye looks through ([{d, far}] or [{d1, far:b}, {d2, far:c}]); right before the main render,
    // portalBegin() hides that area's objects whose bounding sphere lies outside every chain's view cone.
    const portals = this._portals;
    portals.clear();
    const hop1 = this._hop1;
    hop1.length = 0;
    const addPortal = (area, chain) => {
      if (here.includes(area)) return;
      let l = portals.get(area);
      if (!l) portals.set(area, (l = []));
      l.push(chain);
    };
    if (!culled) {
      for (const id in this.areaRoots) vis.add(id);
    } else {
      for (const a of here) vis.add(a);
      // An area behind an open door is drawn only when that doorway is inside the view frustum (or the player /
      // camera stands right at it): in the dressed rooms each neighbour costs 200-400 draw calls.
      let fr = null;
      if (camera && this.doorFrustum !== false) {
        camera.updateMatrixWorld();
        _fm.multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse);
        fr = _frustum.setFromProjectionMatrix(_fm);
      }
      for (const a of here) {
        for (const id of this.areas[a].doors) {
          const d = this.doors[id];
          const b = d.areas[0] === a ? d.areas[1] : d.areas[0];
          if (!d.open || here.includes(b)) continue;
          if (fr && !doorInView(fr, d, p && p.pos, camera.position)) continue;
          addPortal(b, [{ d, far: b }]);
          hop1.push([b, d]);
          if (vis.has(b)) continue;
          vis.add(b);
          hop.push([b, d]);
        }
      }
      if (camera) {
        _eye.copy(camera.position);
        for (const [b, d1] of hop1) {
          for (const id of this.areas[b].doors) {
            const d2 = this.doors[id];
            const c = d2.areas[0] === b ? d2.areas[1] : d2.areas[0];
            if (d2 === d1 || !d2.open || here.includes(c)) continue;
            if (!seenThrough(_eye, d1, d2) || (fr && !doorInView(fr, d2, null, _eye))) continue;
            addPortal(c, [{ d: d1, far: b }, { d: d2, far: c }]);
            vis.add(c);
          }
        }
      }
    }
    for (const id in this.areaRoots) this.areaRoots[id].visible = vis.has(id);
    for (const d of Object.values(this.doors)) d.group.visible = vis.has(d.areas[0]) || vis.has(d.areas[1]);
    this._cullShadows(here, culled ? hop : null, camera);
  }

  // Shadow casters: only the player's and the camera's areas (plus an area behind an open door when the player
  // or camera is within SHADOW_DOOR_R of that door) render into the key light's shadow map. Areas merely seen
  // through a door still draw, without casting: in a dressed room that was ~200 extra shadow draws and ~360k
  // triangles (the 36 m shadow box spans 4-5 rooms). castShadow is flipped only on meshes this method turned
  // off, and only when an area's state changes; areas not drawn this frame keep their state.
  _cullShadows(here, hop, camera) {
    const all = !this.shadowCull || !hop;
    const on = this._shadowCast;
    on.clear();
    if (!all) {
      for (const a of here) on.add(a);
      const p = this.game.player;
      for (const [b, d] of hop) {
        if (!on.has(b) && (nearDoor(p && p.pos, d) || nearDoor(camera && camera.position, d))) on.add(b);
      }
    }
    for (const id in this.areaRoots) {
      if (!all && !this._visible.has(id)) continue;
      const cast = all || on.has(id);
      const off = this._shadowOff[id];
      if (cast && off) {
        for (const m of off) m.castShadow = true;
        this._shadowOff[id] = null;
      } else if (!cast && !off) {
        const list = [];
        this.areaRoots[id].traverse((o) => { if (o.castShadow) { o.castShadow = false; list.push(o); } });
        this._shadowOff[id] = list;
      }
    }
  }

  // Main-pass object portal culling (render.addMainHook). Exact: the walls are opaque and doors are the only openings
  // between areas, so an object of an area seen through doors can only show inside the view cone from the eye
  // through those door openings (a thick wall's hole is inside the cone through its centre plane). Objects are
  // hidden only for the main camera's render list: portalEnd() runs when the shadow map starts rendering (hidden
  // objects still cast) and after the main render, so feeds, shadows and gameplay code never see the change.
  portalBegin(camera) {
    if (this._hidden.length) this.portalEnd();
    if (!this.culling || !this.objectCull || !this._portals.size || !camera) return;
    const eye = camera.position;
    const hid = this._hidden;
    for (const [area, chains] of this._portals) {
      const root = this.areaRoots[area];
      if (!root || !root.visible) continue;
      const sets = _planeSets;
      let n = 0, all = false;
      for (const chain of chains) {
        const planes = sets[n] || (sets[n] = []);
        planes.length = 0;
        for (const { d, far } of chain) {
          if (!portalPlanes(eye, d, this.areas[far], planes)) { all = true; break; }
        }
        if (all) break;
        n++;
      }
      if (all || !n) continue;
      const leaves = this._leavesOf(area);
      for (let i = 0; i < leaves.length; i++) {
        const o = leaves[i];
        if (!o.visible) continue;
        const g = o.geometry;
        if (!g.boundingSphere) g.computeBoundingSphere();
        const bs = g.boundingSphere;
        if (!bs) continue;
        _c.copy(bs.center).applyMatrix4(o.matrixWorld);
        const r = bs.radius * o.matrixWorld.getMaxScaleOnAxis() + PORTAL_MARGIN;
        let inside = false;
        for (let k = 0; k < n && !inside; k++) inside = inCone(sets[k], _c, r);
        if (!inside) { o.visible = false; hid.push(o); }
      }
    }
  }

  portalEnd() {
    const hid = this._hidden;
    for (let i = 0; i < hid.length; i++) hid[i].visible = true;
    hid.length = 0;
  }

  // Shadow-only caster proxies (staticopt.js) are visible only while the key shadow map renders.
  _showProxies(on) {
    const list = this._proxies;
    for (let i = 0; i < list.length; i++) list[i].visible = on;
  }

  // Drawable leaves of an area (childless meshes / points / lines / sprites that three frustum-culls; instanced
  // and skinned meshes stay drawn), rescanned every LEAF_RESCAN s so objects added later are picked up.
  _leavesOf(area) {
    const now = this.game.time ? this.game.time.realNow : 0;
    let e = this._leaves[area];
    if (e && now - e.t < LEAF_RESCAN && now >= e.t) return e.list;
    const list = [];
    this.areaRoots[area].traverse((o) => {
      if (!(o.isMesh || o.isPoints || o.isLine || o.isSprite) || o.children.length || !o.geometry) return;
      if (o.isInstancedMesh || o.isSkinnedMesh || o.isBatchedMesh || o.frustumCulled === false || o.userData.shadowProxy) return;
      if (o.layers.daHidden) return; // drawn by its area batch
      list.push(o);
    });
    e = this._leaves[area] = { t: now, list };
    return list;
  }

  renderWith(areaIds, fn) {
    const saved = Object.values(this.areaRoots).map((r) => r.visible);
    const doorSaved = Object.values(this.doors).map((d) => d.group.visible);
    for (const id of areaIds) this.setAreaVisible(id, true);
    try {
      return fn();
    } finally {
      Object.values(this.areaRoots).forEach((r, i) => { r.visible = saved[i]; });
      Object.values(this.doors).forEach((d, i) => { d.group.visible = doorSaved[i]; });
    }
  }

  setCeilingsVisible(visible) {
    for (const a of AREAS) this.groups[`${a.id}#ceil`].visible = visible;
    this.groups['shell#roof'].visible = visible;
  }

  // --------------------------------------------------------------------------------------------------- power
  setPower(on, { instant = false } = {}) {
    this.powered = on;
    this._powerT = 0;
    for (const s of this._switches) { s.done = false; s.sounded = false; s.state = null; }
    if (!on || instant) {
      for (const s of this._switches) { s.apply(on); s.state = on; s.done = true; }
      this._powerDone = true;
    } else this._powerDone = false;
    this._beaconT = on ? (instant ? BEACON_DELAY : 0) : -1;
    this.beacons.set(false);
  }

  _updatePower(dt) {
    if (this._powerDone) return;
    this._powerT += dt;
    let pending = false;
    for (const s of this._switches) {
      if (s.done) continue;
      const t = this._powerT - s.delay;
      if (t < 0) { pending = true; continue; }
      let on = true;
      for (const [t0, v] of FLICKER) if (t >= t0) on = v;
      if (on !== s.state) { s.apply(on); s.state = on; }
      if (!s.sounded) {
        s.sounded = true;
        if (this.game.audio) this.game.audio.play(s.sound, { pos: s.pos });
      }
      if (t >= FLICKER[FLICKER.length - 1][0]) s.done = true; else pending = true;
    }
    this._powerDone = !pending;
  }
}

// Portal culling helpers. portalPlanes() appends the 4 side planes (nx, ny, nz, w; inside = n.p + w >= -r) of the
// cone from `eye` through door d's opening (grown by PORTAL_MARGIN) toward area `far`; false when the eye is too
// close to the door plane or already on the far side (then that area is not culled this frame).
const PORTAL_MARGIN = 0.15;
const LEAF_RESCAN = 2;
const _c = new THREE.Vector3();
const _planeSets = [];
const _pc = [new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3()];
const _po = new THREE.Vector3();
const _pu = new THREE.Vector3();
const _pv = new THREE.Vector3();
function portalPlanes(eye, d, farArea, out) {
  if (!farArea) return false;
  const [axis, at] = d.line;
  const r = farArea.rect;
  const fc = axis === 'x' ? (r[0] + r[2]) / 2 : (r[1] + r[3]) / 2;
  const ep = axis === 'x' ? eye.x : eye.z;
  if (Math.abs(ep - at) < 0.3 || Math.sign(ep - at) === Math.sign(fc - at)) return false;
  const m = PORTAL_MARGIN;
  const s0 = d.span[0] - m, s1 = d.span[1] + m, y0 = (d.y0 || 0) - m, y1 = (d.y1 || 3) + m;
  const put = (v, s, y) => (axis === 'x' ? v.set(at, y, s) : v.set(s, y, at));
  put(_pc[0], s0, y0); put(_pc[1], s1, y0); put(_pc[2], s1, y1); put(_pc[3], s0, y1);
  put(_po, (s0 + s1) / 2, (y0 + y1) / 2);
  for (let i = 0; i < 4; i++) {
    _pu.subVectors(_pc[i], eye);
    _pv.subVectors(_pc[(i + 1) & 3], eye);
    _pu.cross(_pv).normalize();
    let w = -_pu.dot(eye);
    if (_pu.dot(_po) + w < 0) { _pu.negate(); w = -w; }
    out.push(_pu.x, _pu.y, _pu.z, w);
  }
  return true;
}

function inCone(planes, c, r) {
  for (let i = 0; i < planes.length; i += 4) {
    if (planes[i] * c.x + planes[i + 1] * c.y + planes[i + 2] * c.z + planes[i + 3] < -r) return false;
  }
  return true;
}

function nearDoor(v, d) {
  return !!v && Math.hypot(v.x - d.pos.x, v.z - d.pos.z) < SHADOW_DOOR_R;
}

// True if the camera sees door d2's opening through door d1's opening (2D, on d1's wall line).
const _fm = new THREE.Matrix4();
const _frustum = new THREE.Frustum();
const _dbox = new THREE.Box3();
const DOOR_NEAR = 2.5;
function doorInView(fr, d, pos, eye) {
  const [cx, cz] = d.center;
  if (pos && Math.hypot(pos.x - cx, pos.z - cz) < DOOR_NEAR) return true;
  if (eye && Math.hypot(eye.x - cx, eye.z - cz) < DOOR_NEAR) return true;
  const [x0, z0, x1, z1] = d.rect;
  _dbox.min.set(x0 - 0.3, (d.y0 || 0) - 0.1, z0 - 0.3);
  _dbox.max.set(x1 + 0.3, (d.y1 || 3) + 0.3, z1 + 0.3);
  return fr.intersectsBox(_dbox);
}

function seenThrough(eye, d1, d2) {
  const [axis, at] = d1.line;
  const [s0, s1] = d1.span;
  const [c2x, c2z] = d2.center;
  const half = d2.width * 0.45;
  const alongX2 = d2.line[0] === 'z';
  for (const o of [0, -half, half]) {
    const px = alongX2 ? c2x + o : c2x, pz = alongX2 ? c2z : c2z + o;
    const ea = axis === 'x' ? eye.x : eye.z, pa = axis === 'x' ? px : pz;
    if ((ea - at) * (pa - at) >= 0) continue;
    const t = (at - ea) / (pa - ea);
    const s = axis === 'x' ? eye.z + t * (pz - eye.z) : eye.x + t * (px - eye.x);
    if (s >= s0 - 0.1 && s <= s1 + 0.1) return true;
  }
  return false;
}
