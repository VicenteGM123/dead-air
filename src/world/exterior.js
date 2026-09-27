// Everything outside the walls (always visible, never portal-culled): lawn, the station parking lot with
// stall lines, the front sidewalk and curb, the night street with its dashed centre line and sodium lamps
// (additive light pools), a row of neon-signed 70s storefronts across the street (what the lobby and newsroom
// windows look out on), a ring of skyline blocks with lit window grids, the night sky (gradient dome with a warm
// city glow on the horizon, twinkling stars, the moon and its halo; it follows the camera) and the transmitter
// tower placeholder (red/white lattice with blinking beacons, GDD §5.7).
//
// buildExterior(ctx) → { sky: Object3D (Level keeps it centred on the camera), beacons: { set(on) } }
//   ctx = { game, batch, surf, group(name) }  batch group / mesh root: 'ext'

import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import * as geo from '../core/geo.js';
import { mulberry32 } from '../core/rng.js';
import { PAL } from '../core/config.js';
import { ANCHORS } from './layout.js';
import { labelTex } from './decals.js';

const G = 'ext';
const CITY = new THREE.Vector2(22, -12);
const SKY_R = 150;

export function buildExterior(ctx) {
  const rand = mulberry32(0x0d13a1);
  ground(ctx);
  street(ctx, rand);
  storefronts(ctx);
  skyline(ctx, rand);
  const beacons = tower(ctx);
  const sky = skyDome(ctx, rand);
  return { sky, beacons };
}

// --------------------------------------------------------------------------------------------------- ground
function ground({ batch }) {
  batch.hface(G, 'grass', -240, -260, 280, 11, -0.03, true);
  batch.hface(G, 'grass', -240, 23.5, 280, 220, -0.03, true);
  batch.hface(G, 'asphalt', -34, -48, 62, 6.15, -0.02, true);
  batch.hface(G, 'sidewalk', -34, 6.15, 62, 11, -0.01, true);
  batch.vface(G, 'sidewalk', 'z', 11, 1, -34, 62, -0.13, -0.01);
  // Parking stalls west of the station and along the service lane behind the studios.
  for (let i = 0; i <= 6; i++) {
    const x = -30 + i * 3;
    for (const [z0, z1] of [[-25, -20], [-12, -7], [2, 5.5]]) batch.hface(G, 'paint_line', x - 0.06, z0, x + 0.06, z1, -0.01, true);
  }
  for (let i = 0; i <= 10; i++) {
    const x = -4 + i * 3;
    batch.hface(G, 'paint_line', x - 0.06, -46, x + 0.06, -41, -0.01, true);   // paint 1 cm over the asphalt (5 mm shimmered far off)
  }
}

// --------------------------------------------------------------------------------------------------- street
function street({ game, batch, group }, rand) {
  batch.hface(G, 'asphalt', -240, 11, 280, 20, -0.13, true);
  for (let x = -236; x < 280; x += 6) batch.hface(G, 'paint_yellow', x, 15.42, x + 3, 15.58, -0.12, true);
  batch.hface(G, 'sidewalk', -240, 20, 280, 23.5, -0.01, true);
  batch.vface(G, 'sidewalk', 'z', 20, -1, -240, 280, -0.13, -0.01);
  const root = group(G);
  const M = game.mats;
  const pole = M.toon('#3A3440', { metal: 0.4, rough: 0.5, rimColor: '#9FB6FF' });
  const lens = M.glow(PAL.sodium, 2.4);
  const pool = M.glow(PAL.sodium, 0.55, { map: game.tex.radial(), additive: true });
  const lenses = [], pools = [];
  const lamp = (x, z, dir) => {
    root.add(geo.mesh(geo.cylinder(0.07, 0.1, 6.2, 10), pole, { pos: [x, 3.1, z], cast: false }));
    root.add(geo.mesh(geo.cylinder(0.05, 0.05, 1.5, 8), pole, { pos: [x, 6.1, z + dir * 0.7], rot: [Math.PI / 2, 0, 0], cast: false }));
    root.add(geo.mesh(geo.roundedBox(0.34, 0.16, 0.62, 0.06, 2), pole, { pos: [x, 6.05, z + dir * 1.45], cast: false }));
    lenses.push(new THREE.PlaneGeometry(0.26, 0.5).rotateX(Math.PI / 2).translate(x, 5.965, z + dir * 1.45));
    pools.push(new THREE.PlaneGeometry(9, 9).rotateX(-Math.PI / 2).translate(x, 0.004, z + dir * 1.2));
  };
  for (let x = -30; x <= 62; x += 15) lamp(x, 10.4, 1);
  for (let x = -22.5; x <= 70; x += 15) lamp(x + (rand() - 0.5), 21.1, -1);
  const lm = new THREE.Mesh(mergeGeometries(lenses), lens);
  const pm = new THREE.Mesh(mergeGeometries(pools), pool);
  pm.renderOrder = 2;
  lm.userData.noMerge = pm.userData.noMerge = true;
  root.add(lm, pm);
}

// ---------------------------------------------------------------------------------------------- storefronts
const SHOPS = [
  [-44, -27, 7.0, 'brick', 'BOWL-O-RAMA', '#FF5FA2'],
  [-26, -16, 5.5, 'stucco_teal', 'DINER', '#7FE7FF'],
  [-15, -2, 8.0, 'stucco_cream', 'TV REPAIR', '#FFC23A'],
  [-1, 9, 6.0, 'brick', null, null],
  [10, 23, 9.0, 'stucco_rust', 'MOTEL', '#FF3B30'],
  [24, 34, 6.5, 'stucco_cream', 'LIQUORS', '#52E04A'],
  [35, 49, 7.5, 'brick', 'DISCO', '#D64FD6'],
  [50, 64, 5.5, 'stucco_teal', null, null],
];

function storefronts({ game, batch, group }) {
  const root = group(G);
  const M = game.mats;
  const z0 = 23.5, z1 = 34;
  for (const [x0, x1, h, key, sign, color] of SHOPS) {
    batch.box(G, key, [x0, 0, z0], [x1, h, z1], { skip: { ny: true, pz: true }, ao: 0.3 });
    batch.box(G, 'trim_coping', [x0 - 0.1, h, z0 - 0.1], [x1 + 0.1, h + 0.25, z1], { skip: { ny: true, pz: true } });
    // Lit shop window band and, on the taller blocks, an upper floor of apartments.
    batch.vface(G, 'storefront', 'z', z0 - 0.02, -1, x0 + 0.8, x1 - 0.8, 0.7, 2.7);
    if (h > 6.2) batch.vface(G, 'storefront', 'z', z0 - 0.02, -1, x0 + 0.8, x1 - 0.8, 3.9, h - 1.3);
    if (!sign) continue;
    const w = Math.min(x1 - x0 - 2, 1.1 * sign.length + 1.2);
    const face = labelTex(sign, { w: 512, h: 128, fg: '#FFFFFF', bg: '#140E1C', border: color, pad: 0.14 });
    const m = geo.mesh(geo.plane(w, w / 4), M.glow(color, 1.8, { map: face }), { pos: [(x0 + x1) / 2, 3.35, z0 - 0.08], rot: [0, Math.PI, 0], cast: false });
    m.userData.noMerge = true;
    root.add(m);
    if (sign === 'DINER' || sign === 'MOTEL') {
      const awning = M.toon('#ffffff', { map: game.tex.stripes([color === '#FF3B30' ? '#E23B3B' : '#2E8C8C', '#F4F1E8'], true, 10), rough: 0.7 });
      root.add(geo.mesh(geo.roundedBox(x1 - x0 - 1, 0.12, 1.6, 0.04, 2), awning, { pos: [(x0 + x1) / 2, 2.95, z0 - 0.7], rot: [-0.28, 0, 0], cast: false }));
    }
  }
}

// ---------------------------------------------------------------------------------------------------- skyline
function skyline({ game, batch, group }, rand) {
  const tops = [];
  const N = 46;
  for (let i = 0; i < N; i++) {
    const a = (i / N) * Math.PI * 2 + (rand() - 0.5) * 0.08;
    const north = Math.max(0, -Math.sin(a));
    const r = 150 + rand() * 40;
    const x = CITY.x + Math.cos(a) * r, z = CITY.y + Math.sin(a) * r;
    const w = 10 + rand() * 14, d = 10 + rand() * 12;
    const h = 14 + rand() * 30 + north * 40 * rand();
    batch.box(G, 'skyline', [x - w / 2, -0.5, z - d / 2], [x + w / 2, h, z + d / 2], { skip: { ny: true } });
    tops.push([x, h, z]);
  }
  tops.sort((p, q) => q[1] - p[1]);
  const beacons = tops.slice(0, 8).map(([x, h, z]) => new THREE.SphereGeometry(0.6, 8, 6).translate(x, h + 1.2, z));
  const m = new THREE.Mesh(mergeGeometries(beacons), game.mats.glow('#FF3B30', 2.2, { fog: false }));
  m.userData.noMerge = true;
  group(G).add(m);
}

// ------------------------------------------------------------------------------------------------------ tower
function tower({ game, group }) {
  const M = game.mats;
  const [x0, z0, x1, z1] = ANCHORS.tower_base.rect;
  const cx = (x0 + x1) / 2, cz = (z0 + z1) / 2, half = (x1 - x0) / 2;
  const HGT = ANCHORS.tower_base.height, TOP = 0.45, LEVELS = 10;
  const red = M.toon('#E23B3B', { rough: 0.45, rimColor: '#9FB6FF', rim: 0.25 });
  const white = M.toon('#F4F1E8', { rough: 0.45, rimColor: '#9FB6FF', rim: 0.25 });
  const concrete = M.toon('#8C8894', { rough: 0.9 });
  const g = new THREE.Group();
  g.name = 'tower';
  const up = new THREE.Vector3(0, 1, 0);
  const strut = (a, b, r, mat) => {
    const d = new THREE.Vector3().subVectors(b, a);
    const m = geo.mesh(geo.cylinder(r, r, d.length(), 6), mat, { cast: r > 0.06 });
    m.position.addVectors(a, b).multiplyScalar(0.5);
    m.quaternion.setFromUnitVectors(up, d.normalize());
    g.add(m);
  };
  const corner = (i, lvl) => {
    const k = lvl / LEVELS, s = half + (TOP - half) * k;
    const sx = i === 0 || i === 3 ? -1 : 1, sz = i < 2 ? -1 : 1;
    return new THREE.Vector3(cx + sx * s, HGT * k, cz + sz * s);
  };
  for (let lvl = 0; lvl < LEVELS; lvl++) {
    const mat = lvl % 2 ? white : red;
    for (let i = 0; i < 4; i++) {
      const j = (i + 1) % 4;
      strut(corner(i, lvl), corner(i, lvl + 1), 0.1 - lvl * 0.005, mat);
      strut(corner(i, lvl + 1), corner(j, lvl + 1), 0.04, mat);
      strut(corner(i, lvl), corner(j, lvl + 1), 0.035, mat);
      strut(corner(j, lvl), corner(i, lvl + 1), 0.035, mat);
    }
  }
  for (let i = 0; i < 4; i++) {
    const c = corner(i, 0);
    g.add(geo.mesh(geo.roundedBox(0.8, 0.45, 0.8, 0.06, 2), concrete, { pos: [c.x, 0.2, c.z], cast: false }));
  }
  strut(new THREE.Vector3(cx, HGT, cz), new THREE.Vector3(cx, HGT + 4, cz), 0.07, white);
  geo.mergeByMaterial(g);
  group(G).add(g);

  const lamps = [];
  for (const lvl of [3.3, 6.6]) for (const i of [0, 2]) {
    const c = corner(i, lvl);
    lamps.push(new THREE.SphereGeometry(0.22, 12, 8).translate(c.x, c.y + 0.25, c.z));
  }
  lamps.push(new THREE.SphereGeometry(0.3, 12, 8).translate(cx, HGT + 4.2, cz));
  const dark = M.toon('#7A2222', { rough: 0.3 });
  const lit = M.glow('#FF3B30', 3.2);
  const beacon = new THREE.Mesh(mergeGeometries(lamps), dark);
  beacon.name = 'tower_beacons';
  beacon.userData.noMerge = true;
  group(G).add(beacon);
  return { mesh: beacon, set(on) { beacon.material = on ? lit : dark; } };
}

// ------------------------------------------------------------------------------------------------------- sky
const SKY_VERT = /* glsl */`
varying vec3 vDir;
void main() {
  vDir = normalize( position );
  gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 );
  gl_Position.z = gl_Position.w;
}`;

const SKY_FRAG = /* glsl */`
uniform vec3 uTop;
uniform vec3 uHorizon;
uniform vec3 uGlow;
uniform vec3 uGround;
varying vec3 vDir;
void main() {
  float h = vDir.y;
  vec3 c = mix( uHorizon, uTop, smoothstep( 0.0, 0.6, h ) );
  c += uGlow * exp( -max( h, 0.0 ) * 11.0 ) * 0.85;
  c = mix( uGround, c, smoothstep( -0.04, 0.01, h ) );
  gl_FragColor = vec4( c, 1.0 );
  #include <colorspace_fragment>
}`;

const STAR_VERT = /* glsl */`
attribute float aSize;
attribute float aPhase;
uniform float uTime;
varying float vTw;
void main() {
  gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 );
  gl_Position.z = gl_Position.w * 0.99999;
  vTw = 0.6 + 0.4 * sin( uTime * ( 1.3 + aPhase ) + aPhase * 40.0 );
  gl_PointSize = aSize * ( 0.8 + 0.3 * vTw );
}`;

const STAR_FRAG = /* glsl */`
varying float vTw;
void main() {
  float d = length( gl_PointCoord - 0.5 );
  float a = smoothstep( 0.5, 0.1, d );
  gl_FragColor = vec4( vec3( 1.0, 0.95, 0.82 ) * ( 0.5 + vTw ), a );
}`;

function moonTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 256;
  const x = c.getContext('2d');
  const g = x.createRadialGradient(128, 128, 60, 128, 128, 128);
  g.addColorStop(0, 'rgba(255,244,214,0.55)'); g.addColorStop(0.5, 'rgba(159,182,255,0.14)'); g.addColorStop(1, 'rgba(159,182,255,0)');
  x.fillStyle = g; x.fillRect(0, 0, 256, 256);
  x.fillStyle = '#FFF4D6';
  x.beginPath(); x.arc(128, 128, 62, 0, Math.PI * 2); x.fill();
  const r = mulberry32(77);
  for (let i = 0; i < 16; i++) {
    const a = r() * Math.PI * 2, d = r() * 48, s = 4 + r() * 12;
    x.fillStyle = `rgba(214,196,170,${0.35 + r() * 0.3})`;
    x.beginPath(); x.arc(128 + Math.cos(a) * d, 128 + Math.sin(a) * d, s, 0, Math.PI * 2); x.fill();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

function skyDome({ game }, rand) {
  const sky = new THREE.Group();
  sky.name = 'sky';
  const dome = new THREE.Mesh(new THREE.SphereGeometry(SKY_R, 32, 16), new THREE.ShaderMaterial({
    uniforms: {
      uTop: { value: new THREE.Color(PAL.skyTop) },
      uHorizon: { value: new THREE.Color(PAL.horizon) },
      uGlow: { value: new THREE.Color('#6B3F6E') },
      uGround: { value: new THREE.Color('#120E1E') },
    },
    vertexShader: SKY_VERT, fragmentShader: SKY_FRAG, side: THREE.BackSide, depthWrite: false, fog: false,
  }));
  dome.renderOrder = -10;
  dome.frustumCulled = false;
  sky.add(dome);

  const n = 900, pos = new Float32Array(n * 3), size = new Float32Array(n), phase = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const y = 0.06 + rand() * 0.94, a = rand() * Math.PI * 2, rr = Math.sqrt(1 - y * y);
    pos.set([Math.cos(a) * rr * (SKY_R - 10), y * (SKY_R - 10), Math.sin(a) * rr * (SKY_R - 10)], i * 3);
    size[i] = 1.2 + rand() ** 3 * 3.2;
    phase[i] = rand();
  }
  const sg = new THREE.BufferGeometry();
  sg.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  sg.setAttribute('aSize', new THREE.BufferAttribute(size, 1));
  sg.setAttribute('aPhase', new THREE.BufferAttribute(phase, 1));
  const stars = new THREE.Points(sg, new THREE.ShaderMaterial({
    uniforms: { uTime: game.mats.uniforms.uTime },
    vertexShader: STAR_VERT, fragmentShader: STAR_FRAG,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false,
  }));
  stars.frustumCulled = false;
  stars.renderOrder = -9;
  sky.add(stars);

  const dir = new THREE.Vector3(0.42, 0.52, -0.74).normalize();
  const moon = new THREE.Mesh(new THREE.PlaneGeometry(26, 26), new THREE.MeshBasicMaterial({
    map: moonTexture(), color: new THREE.Color(PAL.moon).multiplyScalar(1.35), transparent: true, depthWrite: false, fog: false,
  }));
  moon.position.copy(dir).multiplyScalar(SKY_R - 20);
  moon.lookAt(0, 0, 0);
  moon.renderOrder = -8;
  sky.add(moon);
  return sky;
}
