// DEAD AIR — kit sample props (reference quality bar for the prop artists; docs/PROPKIT.md).
//   sample_floor_lamp   70s teak tripod floor lamp: pleated burnt-orange drum shade, brass hardware, lit bulb
//   sample_portable_tv  1970s portable CRT: harvest-orange ABS shell, cream face, dials, grille, rabbit ears
//   sample_side_table   teak cube side table with a walnut-burl top inlay (set-dressing helper)
// Scene 'samples' (tools/propview): the three on shag against wood paneling.

import * as K from './kit.js';
import { registerProp, registerScene, PAL, THREE } from './kit.js';

// ------------------------------------------------------------------------------------------ floor lamp
registerProp('sample_floor_lamp', (game) => {
  const g = K.prop('sample_floor_lamp');
  const teak = K.mat(game, 'teak', '#ffffff', { map: K.tex.wood(PAL.teak, { dark: 0.38 }) });
  const brass = K.mat(game, 'brass', '#C8963C');
  // emissive = fake translucency of a lit linen shade
  const shadeMat = K.mat(game, 'fabric', '#ffffff', { map: K.tex.weave(PAL.burntOrange, { pattern: 'plain', scale: 3 }), side: THREE.DoubleSide, emissive: '#FF7A30', emissiveIntensity: 0.28 });
  const lining = K.glow(game, '#FFD9A0', 1.15);
  const bulb = K.glow(game, PAL.tungsten, 4);

  // tripod: three tapered teak legs splayed from a brass collar
  const collarY = 0.6, footR = 0.27;
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * Math.PI * 2 + Math.PI / 6;
    const foot = new THREE.Vector3(Math.sin(a) * footR, 0.02, Math.cos(a) * footR);
    const top = new THREE.Vector3(Math.sin(a) * 0.035, collarY, Math.cos(a) * 0.035);
    const len = foot.distanceTo(top);
    const leg = K.m(K.uvScale(K.cyl(0.027, 0.016, len, { bevel: 0.008, seg: 12 }).clone(), 1, 3), teak);
    leg.position.copy(foot);
    leg.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), top.clone().sub(foot).normalize());
    g.add(leg);
    const cap = K.m(K.cyl(0.018, 0.02, 0.03, { bevel: 0.006, seg: 10 }), brass);
    cap.position.copy(foot).setY(0);
    g.add(cap);
  }
  g.add(K.m(K.lathe([[0, 0], [0.066, 0], [0.072, 0.035], [0.056, 0.08], [0.03, 0.115], [0, 0.115]], { round: 0.014, seg: 16 }), brass, { pos: [0, collarY - 0.06, 0] }));
  // pole with a knurled coupling
  g.add(K.m(K.cyl(0.016, 0.016, 0.72, { bevel: 0.004, seg: 12 }), brass, { pos: [0, collarY + 0.04, 0] }));
  g.add(K.m(K.lathe([[0, 0], [0.028, 0], [0.034, 0.018], [0.034, 0.042], [0.028, 0.06], [0, 0.06]], { round: 0.008, seg: 14, steps: 1 }), brass, { pos: [0, 0.98, 0] }));
  // socket + bulb
  const bulbY = 1.43;
  g.add(K.m(K.lathe([[0, 0], [0.022, 0], [0.026, 0.02], [0.026, 0.06], [0.018, 0.075], [0, 0.075]], { round: 0.006, seg: 14, steps: 1 }), brass, { pos: [0, bulbY - 0.13, 0] }));
  g.add(K.m(K.lathe([[0, 0], [0.018, 0.005], [0.04, 0.045], [0.045, 0.075], [0.03, 0.11], [0, 0.12]], { round: 0.01, seg: 14 }), bulb, { pos: [0, bulbY - 0.06, 0], cast: false }));

  // pleated drum shade (lathe + radial pleat displacement), glowing lining, piped rims
  const y0 = 1.28, y1 = 1.68, rb = 0.3, rt = 0.22;
  const pleat = (geo, amp) => {
    const gg = geo.clone();
    const p = gg.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const x = p.getX(i), z = p.getZ(i), th = Math.atan2(z, x);
      const k = 1 + amp * Math.abs(Math.cos(th * 14));
      p.setX(i, x * k); p.setZ(i, z * k);
    }
    gg.computeVertexNormals();
    return gg;
  };
  const shell = new THREE.LatheGeometry([new THREE.Vector2(rb, 0), new THREE.Vector2((rb + rt) / 2 + 0.006, (y1 - y0) / 2), new THREE.Vector2(rt, y1 - y0)], 84);
  g.add(K.m(K.uvScale(pleat(shell, 0.05), 10, 1.4), shadeMat, { pos: [0, y0, 0], name: 'shade' }));
  const lin = new THREE.LatheGeometry([new THREE.Vector2(rt - 0.006, y1 - y0 - 0.004), new THREE.Vector2(rb - 0.006, 0.004)], 36);
  const linMesh = K.m(lin, lining, { pos: [0, y0, 0], cast: false });
  g.add(linMesh);
  const rimMat = K.mat(game, 'fabric', '#9E3D17');
  g.add(K.m(K.tube(ring(rb * 1.035, 28), 0.013, { seg: 40, radial: 6, closed: true }), rimMat, { pos: [0, y0, 0] }));
  g.add(K.m(K.tube(ring(rt * 1.035, 28), 0.011, { seg: 36, radial: 6, closed: true }), rimMat, { pos: [0, y1, 0] }));
  // spider (harp) arms to the top ring + finial
  for (let i = 0; i < 3; i++) {
    const a = (i / 3) * Math.PI * 2;
    g.add(K.m(K.tube([[0, bulbY + 0.12, 0], [Math.sin(a) * rt * 0.6, y1 - 0.01, Math.cos(a) * rt * 0.6], [Math.sin(a) * rt, y1, Math.cos(a) * rt]], 0.005, { seg: 8, radial: 5 }), brass));
  }
  g.add(K.m(K.lathe([[0, 0], [0.012, 0], [0.02, 0.018], [0.014, 0.034], [0, 0.04]], { round: 0.006, seg: 12, steps: 1 }), brass, { pos: [0, bulbY + 0.12, 0] }));
  // pull chain
  g.add(K.m(K.tube([[0.03, bulbY - 0.09, 0], [0.034, bulbY - 0.2, -0.01]], 0.002, { seg: 4, radial: 4 }), brass));
  g.add(K.m(K.cyl(0.006, 0.006, 0.018, { bevel: 0.003, seg: 8 }), brass, { pos: [0.034, bulbY - 0.22, -0.01] }));

  g.userData.lightAnchors = [{ pos: [0, bulbY - 0.05, 0], color: PAL.tungsten, intensity: 1.8, distance: 4.5 }]; // small fixture: pooled lights cast no shadows
  g.userData.colliders = [{ min: [-0.2, 0, -0.2], max: [0.2, 1.68, 0.2] }];
  linMesh.userData.noOcclude = true;
  return K.finish(game, g);
}, { category: 'samples', tags: ['lamp', 'light', 'living'], size: [0.56, 1.7, 0.56], desc: '70s teak tripod floor lamp' });

function ring(r, n) {
  const pts = [];
  for (let i = 0; i < n; i++) { const a = (i / n) * Math.PI * 2; pts.push([Math.cos(a) * r, 0, Math.sin(a) * r]); }
  return pts;
}

// ------------------------------------------------------------------------------------------ portable TV
registerProp('sample_portable_tv', (game, opts = {}) => {
  const g = K.prop('sample_portable_tv');
  const shellColor = opts.color ?? PAL.harvestGold;
  const shell = K.mat(game, 'plastic', shellColor);
  const face = K.mat(game, 'plastic', PAL.cream);
  const dark = K.mat(game, 'plastic', '#2A2230');
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  const rubber = dark;

  const W = 0.48, H = 0.36, D = 0.3, footH = 0.022;
  const cy = footH + H / 2;
  // shell: chunky front block + tapered rear housing (the tube's neck)
  g.add(K.m(K.box(W, H, D, 0.07), shell, { pos: [0, cy, 0] }));
  g.add(K.m(K.taper(K.box(W * 0.86, H * 0.84, 0.2, 0.065), { axis: 'z', k: 0.55, ease: 0.8 }), shell, { pos: [0, cy + 0.004, D / 2 + 0.08] }));
  // vent slots on the back housing
  for (let i = 0; i < 4; i++) g.add(K.m(K.box(0.014, 0.09, 0.012, 0.005), dark, { pos: [-0.045 + i * 0.03, cy + 0.01, D / 2 + 0.18] }));
  // cream face plate
  const fz = -D / 2;
  g.add(K.m(K.box(W - 0.03, H - 0.03, 0.02, 0.035), face, { pos: [0, cy, fz - 0.002] }));
  // screen bezel: extruded frame with a rounded hole, sunk into the face
  const sx = -0.058, sw = 0.3, sh = 0.245;
  const outer = K.roundRect(sw + 0.04, sh + 0.04, 0.05);
  outer.holes.push(new THREE.Path(K.roundRect(sw, sh, 0.035).getPoints(8)));
  g.add(K.m(K.extrude(outer, 0.03, { bevel: 0.008, bevelSeg: 1, curveSeg: 6 }), dark, { pos: [sx, cy + 0.005, fz - 0.012] }));
  const scr = K.screen(game, sw, sh, { card: opts.card ?? 'show_4', group: opts.group ?? 'scr_decor', dome: 0.014 });
  scr.position.set(sx, cy + 0.005, fz - 0.004);
  g.add(scr);
  // control column: two channel dials with printed faces, knobs, a grille and a nameplate
  const cx = 0.165;
  // one atlas for both dial faces + the speaker grille (fewer materials): [VHF | UHF | grille], 768x256
  const atlas = K.tex.canvas('sample_tv_atlas', 768, 256, (ctx) => {
    [['VHF', 2, 13], ['UHF', 14, 25]].forEach(([label, n0, n1], c) => {
      const ox = c * 256, w = 256;
      ctx.fillStyle = PAL.capWhite; ctx.beginPath(); ctx.arc(ox + w / 2, w / 2, w / 2, 0, 7); ctx.fill();
      ctx.fillStyle = '#2A2230'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.font = '26px "Titan One", "Arial Black", sans-serif';
      const count = n1 - n0 + 1;
      for (let i = 0; i < count; i++) {
        const a = -Math.PI * 0.8 + (i / (count - 1)) * Math.PI * 1.6;
        ctx.fillText(String(n0 + i), ox + w / 2 + Math.sin(a) * w * 0.38, w / 2 - Math.cos(a) * w * 0.38);
      }
      ctx.fillStyle = PAL.channelRed; ctx.font = '22px "Bungee", "Arial Black", sans-serif';
      ctx.fillText(label, ox + w / 2, w * 0.86);
    });
    ctx.fillStyle = '#3A3040'; ctx.fillRect(512, 0, 256, 256);
    for (let y = 0; y < 9; y++) for (let x = 0; x < 9; x++) {
      ctx.fillStyle = '#120C16'; ctx.beginPath(); ctx.arc(512 + 20 + x * 27, 20 + y * 27, 8, 0, 7); ctx.fill();
      ctx.fillStyle = 'rgba(255,255,255,0.12)'; ctx.beginPath(); ctx.arc(512 + 20 + x * 27, 22 + y * 27, 8, 0.2, 2.9); ctx.fill();
    }
  }, { repeat: false, fonts: true });
  const atlasMat = K.mat(game, 'plastic', '#ffffff', { map: atlas });
  const knob = K.lathe([[0, 0], [0.034, 0], [0.036, 0.01], [0.03, 0.03], [0.026, 0.036], [0, 0.036]], { round: 0.006, seg: 14, steps: 1 });
  const parts = {};
  [['VHF', 2, 13, 0.07], ['UHF', 14, 25, -0.02]].forEach(([label, n0, n1, dy], i) => {
    const disc = K.m(K.uvRect(new THREE.CircleGeometry(0.045, 28), i / 3, 0, (i + 1) / 3, 1), atlasMat,
      { pos: [cx, cy + dy, fz - 0.0135], rot: [0, Math.PI, 0] });
    g.add(disc);
    const k = new THREE.Group();
    k.position.set(cx, cy + dy, fz - 0.013);
    k.userData.noMerge = true;
    const body = K.m(knob, i ? chrome : dark, { rot: [-Math.PI / 2, 0, 0] });
    const ptr = K.m(K.box(0.008, 0.028, 0.008, 0.003), i ? dark : face, { pos: [0, 0.012, -0.036] });
    k.add(body, ptr);
    k.rotation.z = (i ? -0.6 : 0.9);
    g.add(k);
    parts[i ? 'dialUHF' : 'dialVHF'] = k;
  });
  g.add(K.m(K.uvRect(K.box(0.08, 0.07, 0.01, 0.005).clone(), 2 / 3, 0, 1, 1), atlasMat, { pos: [cx, cy - 0.105, fz - 0.011] }));
  const plate = K.mat(game, 'metal', '#ffffff', { map: K.tex.label('VISTRONIC  ·  SOLID STATE', { bg: '#E8E4DA', fg: '#2A2230', accent: '#B9BEC6', w: 512, h: 64, border: 0.1, wear: 0.1 }) });
  g.add(K.m(K.box(0.19, 0.021, 0.006, 0.003), plate, { pos: [sx, cy - 0.152, fz - 0.014] }));
  // power button + indicator
  g.add(K.m(K.box(0.03, 0.018, 0.014, 0.005), dark, { pos: [cx, cy + 0.14, fz - 0.013] }));
  g.add(K.m(K.cyl(0.005, 0.005, 0.006, { bevel: 0.002, seg: 10 }), K.glow(game, PAL.onAirRed, 3), { pos: [cx + 0.03, cy + 0.14, fz - 0.009], rot: [-Math.PI / 2, 0, 0] }));
  // carry handle: chrome bail with black grip on pivot bosses
  const top = footH + H;
  const hx = W / 2 + 0.013;
  for (const s of [-1, 1]) g.add(K.m(K.cyl(0.024, 0.026, 0.018, { bevel: 0.006, seg: 12 }), dark, { pos: [s * (W / 2 - 0.004), top - 0.06, 0], rot: [0, 0, -s * Math.PI / 2] }));
  g.add(K.m(K.tube([[-hx, top - 0.06, 0], [-hx, top + 0.01, -0.004], [-W / 2 + 0.03, top + 0.07, -0.012], [-0.12, top + 0.085, -0.015], [0.12, top + 0.085, -0.015], [W / 2 - 0.03, top + 0.07, -0.012], [hx, top + 0.01, -0.004], [hx, top - 0.06, 0]], 0.009, { seg: 32, radial: 6 }), chrome));
  g.add(K.m(K.tube([[-0.1, top + 0.085, -0.015], [0.1, top + 0.085, -0.015]], 0.016, { seg: 4, radial: 10 }), rubber));
  // rabbit ears: swivel ball + telescoping chrome rods with ball tips
  const ax = 0.02, ay = top + 0.005, az = 0.1;
  g.add(K.m(K.lathe([[0, 0], [0.04, 0], [0.042, 0.012], [0.02, 0.03], [0, 0.034]], { round: 0.008, seg: 14, steps: 1 }), dark, { pos: [ax, ay - 0.01, az] }));
  const ant = new THREE.Group();
  ant.position.set(ax, ay + 0.02, az);
  ant.userData.noMerge = true;
  for (const s of [-1, 1]) {
    const dir = new THREE.Vector3(s * 0.55, 1, 0.22).normalize();
    const segs = [[0.0055, 0.2], [0.0042, 0.18], [0.003, 0.16]];
    let dpos = 0.0;
    for (const [r, l] of segs) {
      const rod = K.m(K.cyl(r, r, l, { bevel: 0.0015, seg: 6 }), chrome);
      rod.position.copy(dir).multiplyScalar(dpos);
      rod.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir);
      ant.add(rod);
      dpos += l - 0.01;
    }
    ant.add(K.m(G_SPHERE(0.009), chrome, { pos: dir.clone().multiplyScalar(dpos + 0.005).toArray() }));
  }
  g.add(ant);
  parts.antenna = ant;
  // rubber feet
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) g.add(K.m(K.cyl(0.022, 0.026, footH, { bevel: 0.005, seg: 10 }), rubber, { pos: [x * (W / 2 - 0.06), 0, z * (D / 2 - 0.05)] }));

  g.userData.parts = parts;
  g.userData.colliders = [{ min: [-W / 2, 0, -D / 2 - 0.02], max: [W / 2, top + 0.08, D / 2 + 0.17] }];
  g.userData.interact = { point: [0, cy, fz - 0.05], radius: 1.2 };
  return K.finish(game, g);
}, { category: 'samples', tags: ['tv', 'crt', 'screen', 'living'], size: [0.48, 0.46, 0.5], desc: '1970s portable CRT television', hero: true });

const G_SPHERE = (r) => new THREE.SphereGeometry(r, 10, 6);

// ------------------------------------------------------------------------------------------ side table
registerProp('sample_side_table', (game) => {
  const g = K.prop('sample_side_table');
  const teak = K.mat(game, 'lacquer', '#ffffff', { map: K.tex.wood(PAL.teak, { dark: 0.35 }) });
  const burl = K.mat(game, 'lacquer', '#ffffff', { map: K.tex.burl(PAL.walnut) });
  const S = 0.56, Hh = 0.5;
  g.add(K.m(K.box(S, 0.05, S, 0.02, { uv: 1.6 }), teak, { pos: [0, Hh - 0.025, 0] }));
  g.add(K.m(K.box(S - 0.1, 0.006, S - 0.1, 0.003, { uv: 1.5 }), burl, { pos: [0, Hh + 0.001, 0] }));
  g.add(K.m(K.box(S - 0.06, 0.03, S - 0.06, 0.012, { uv: 1.6 }), teak, { pos: [0, 0.16, 0] }));
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
    g.add(K.m(K.box(0.05, Hh - 0.05, 0.05, 0.014, { uv: 1.6, swap: true }), teak, { pos: [x * (S / 2 - 0.035), (Hh - 0.05) / 2, z * (S / 2 - 0.035)] }));
  }
  return K.finish(game, g);
}, { category: 'samples', tags: ['table', 'living'], size: [0.56, 0.5, 0.56], desc: 'teak cube side table, burl inlay' });

registerScene('samples', {
  floor: 'shag', wall: 'panel', room: [4.4, 3.4],
  items: [
    { id: 'sample_floor_lamp', pos: [-1.0, 0.6], rotY: 0.3 },
    { id: 'sample_side_table', pos: [0.15, 0.55], rotY: 0 },
    { id: 'sample_portable_tv', pos: [0.15, 0.5, 0.52], rotY: -0.25 },
    { id: 'sample_portable_tv', pos: [1.25, 0.9], rotY: -0.7, opts: { color: PAL.avocado, card: 'station_id' } },
  ],
  cam: { pos: [0.6, 1.45, -2.6], target: [0, 0.6, 0.7], fov: 50 },
});
