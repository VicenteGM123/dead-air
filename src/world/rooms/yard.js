// Transmitter Yard dressing (GDD §5.7 "TRANSMITTER YARD", §3.3 lighting, §13 toy_van_radio, §18.13 ids).
// Owner: rooms-yard. build(game, area, root) is called by level.js after the graybox; the static meshes under `root`
// are merged per material afterwards (anything animated is flagged userData.noMerge, by the prop kit or below).
//
// Placed (GDD §5.6/§5.7, layout ANCHORS):
//   yd_tower [45,0,-12] (replaces the exterior.js placeholder tower at runtime and takes over level.beacons, so the
//   level's 1 Hz power blink drives the real beacons), kill_switch_cage = ee_kill_switch on its south face, yd_hut
//   (tube window + 2 scr_feed_yard monitors + SkyCam 13; shifted 1 m east of prop_hut, scaled 0.85 and SkyCam moved to
//   the roof's back-east corner so the cam_yard anchor view is clear — see buildHut), yd_news_van (rear TV scr_feed_yard; its
//   radio sits on a crate beside the cab = toy_van_radio), two sodium posts, the pink/blue WZTV 13 neon on the MC wall
//   above DY, drums / crates / film cans, the crew's break corner (lawn chair, cooler, cones), the DY landing apron,
//   wall packs + service panel + posters on the MC wall, the coax trench hut → tower, fence signs, puddles / gravel /
//   stones / weeds, fireflies and moths. Beyond the fence: a billboard, utility poles with wires, skyline strips, a car.
//   Left clear for other agents: uplink_* (dish r 2.5, cradle, crank, booth: x 35–41.5, z −20…−11.8),
//   set_roller_boogie (NE 3×3 + its camera), and 2 m in front of DY, C1–C3 and G1.
//
// game.level.objects (created if missing):
//   tower          { group, parts:{ upper, beacons[], beaconTop } }
//   tower_beacons  { group, parts:{ beacons[] (top → bottom) }, mode, set(on), setMode('blink'|'on'|'off'|'rainbow'),
//                    setColor(hex), offSequence(seconds = 1.5) }. 'blink' follows level.beacons (1 Hz after power).
//                    Automatic: egg:step {step:4} → 'rainbow'; machine:boss_start → offSequence(1.5); game:start → 'blink'.
//   ee_kill_switch { group, parts:{ door, switch }, pos, stand:Vector3, handle:Vector3, interact:Vector3 }
//                    (door: open = rotation.y ≈ -1.7; switch: thrown = rotation.x ≈ +1.9; the EE/boss code animates them)
//   yard_hut       { group, parts:{ skycam, skycamTilt, skycamTally, doorLight, ceilingLight, windowGlass,
//                    tubes_glowOrange, tubes_glowGreen } }
//   feed_cam_yard_prop { group, parts:{ pan, tilt, tally } }  SkyCam 13: pans ±20° over 8 s around [45,3,-12]
//                    (follows the screens' feed camera when one is exposed); tally lit while powered
//   news_van       { group, parts:{ doorL, doorR, mast, mastHead, domeLight, headlights } }
//   yard_neon      { group, parts:{ neonPink, neonBlue, haloPink, haloBlue }, set(on) }  lights up when the Sign-On
//                    colour wave reaches it (signon.waveReached(pos) if exposed, else lever distance / 15 m/s)
//   sodium_posts   { groups:[g1, g2], parts:{ lamp1, lamp2, beam1, beam2 } }
//   toy_van_radio  { group, parts:{ radio }, playing }
// Toy: toy_van_radio (key-only [E] prompt): 20 s funk loop 'toy_radio' from the radio, which bounces to the beat
// (pressing again stops it).
// Runtime: one render pre-pass tick (skipped while the yard is culled) animates the SkyCam, beacons, neon, radio,
// fireflies and moths. Nothing here allocates per frame.

import * as THREE from 'three';
import { placeProp, registerProp } from '../../props/index.js';
import * as K from '../../props/kit.js';
import { setTowerBeacons } from '../../props/outdoor.js';
import { PAL } from '../../core/config.js';
import { mulberry32 } from '../../core/rng.js';
import { getCard } from '../../gfx/cards.js';
import { ANCHORS } from '../layout.js';

const TAU = Math.PI * 2;
const PI = Math.PI;
const WAVE_SPEED = 15;
const LEVER = new THREE.Vector3(...ANCHORS.sign_on_lever.pos).setY(1);
const FEED = ANCHORS.feed_cam_yard;
const HUT_DX = 1.0;          // hut shifted east of prop_hut and scaled: keeps the cam_yard anchor clear (see buildHut)
const HUT_S = 0.85;
const RAINBOW = ['#FF3B30', '#FFB347', '#FFD23A', '#52E04A', '#3FD6E0', '#3A7BFF', '#D64FD6'];
const _v = new THREE.Vector3();
const _v2 = new THREE.Vector3();

// ------------------------------------------------------------------------------------------ local helpers
const tm = (geo, mat, color, o) => K.m(color ? K.tint(geo.clone(), color) : geo, mat, o);
const hexMul = (hex, k) => '#' + new THREE.Color(hex).multiplyScalar(k).getHexString();
const glowPart = (o) => { o.userData.noMerge = true; o.userData.noAO = true; o.userData.noOcclude = true; o.userData.noShadow = true; return o; };

function signTex(kind) {
  return K.tex.canvas(`yard_sign|${kind}`, 256, 160, (ctx, w, h, rand) => {
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    const round = (x, y, ww, hh, r) => { ctx.beginPath(); ctx.roundRect(x, y, ww, hh, r); };
    const font = (s, f = 'Bungee') => { ctx.font = `${s}px "${f}", "Arial Black", sans-serif`; };
    const fit = (t, max, s, f) => { font(s, f); while (ctx.measureText(t).width > max && s > 6) { s *= 0.93; font(s, f); } };
    if (kind === 'danger') {
      ctx.fillStyle = '#F4F1E8'; round(2, 2, w - 4, h - 4, 14); ctx.fill();
      ctx.fillStyle = '#1E1530'; round(10, 10, w - 20, 50, 8); ctx.fill();
      ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.ellipse(w / 2, 35, 96, 20, 0, 0, TAU); ctx.fill();
      ctx.fillStyle = '#F4F1E8'; fit('DANGER', 170, 34); ctx.fillText('DANGER', w / 2, 37);
      ctx.fillStyle = '#1E1530'; fit('HIGH VOLTAGE', 220, 30); ctx.fillText('HIGH VOLTAGE', w / 2, 90);
      fit('KEEP OUT · RF RADIATION', 220, 16, 'Titan One'); ctx.fillText('KEEP OUT · RF RADIATION', w / 2, 128);
    } else if (kind === 'wztv') {
      ctx.fillStyle = '#2F5BD3'; round(2, 2, w - 4, h - 4, 14); ctx.fill();
      ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.arc(58, 80, 44, 0, TAU); ctx.fill();
      ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(58, 80, 37, 0, TAU); ctx.fill();
      ctx.fillStyle = '#F4F1E8'; font(40, 'Titan One'); ctx.fillText('13', 58, 84);
      ctx.fillStyle = '#FFD23A'; fit('WZTV', 130, 42); ctx.fillText('WZTV', 172, 62);
      ctx.fillStyle = '#F4F1E8'; fit('TRANSMITTER SITE', 136, 17, 'Titan One'); ctx.fillText('TRANSMITTER SITE', 172, 102);
      fit('AUTHORIZED ONLY', 130, 13, 'Titan One'); ctx.fillText('AUTHORIZED ONLY', 172, 126);
    } else if (kind === 'gate') {
      ctx.fillStyle = '#F2C230'; round(2, 2, w - 4, h - 4, 14); ctx.fill();
      ctx.strokeStyle = '#2A1D2A'; ctx.lineWidth = 6; round(10, 10, w - 20, h - 20, 8); ctx.stroke();
      ctx.fillStyle = '#2A1D2A'; fit('KEEP GATE', 200, 34); ctx.fillText('KEEP GATE', w / 2, 56);
      fit('CLOSED', 200, 44); ctx.fillText('CLOSED', w / 2, 106);
    } else {
      ctx.fillStyle = '#F4F1E8'; round(2, 2, w - 4, h - 4, 14); ctx.fill();
      ctx.fillStyle = '#C8201E'; round(8, 8, w - 16, 50, 8); ctx.fill();
      ctx.fillStyle = '#F4F1E8'; fit('NO TRESPASSING', 220, 28); ctx.fillText('NO TRESPASSING', w / 2, 34);
      ctx.fillStyle = '#2A1D2A'; fit('WZTV PROPERTY', 220, 28, 'Titan One'); ctx.fillText('WZTV PROPERTY', w / 2, 92);
      fit('VIOLATORS WILL BE PROSECUTED', 220, 13, 'Titan One'); ctx.fillText('VIOLATORS WILL BE PROSECUTED', w / 2, 128);
    }
    ctx.globalAlpha = 0.12; ctx.fillStyle = '#7A4A2A';
    for (let i = 0; i < 14; i++) { ctx.beginPath(); ctx.arc(rand() * w, rand() * h, 2 + rand() * 9, 0, TAU); ctx.fill(); }
    ctx.globalAlpha = 1;
  }, { repeat: false, fonts: true });
}

function apronTex() {
  return K.tex.canvas('yard_apron', 256, 512, (ctx, w, h, rand) => {
    ctx.fillStyle = '#A9A39C'; ctx.fillRect(0, 0, w, h);
    for (let i = 0; i < 2200; i++) {
      ctx.globalAlpha = 0.06 + rand() * 0.12; ctx.fillStyle = rand() < 0.5 ? '#7E7870' : '#D2CCC2';
      ctx.fillRect(rand() * w, rand() * h, 1.5 + rand() * 2, 1.5 + rand() * 2);
    }
    ctx.globalAlpha = 0.25; ctx.strokeStyle = '#6E6860'; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.moveTo(0, h / 2); ctx.lineTo(w, h / 2); ctx.stroke();
    ctx.globalAlpha = 1;
    // yellow/black hazard band on the yard edge (+u = +x) and the KEEP CLEAR stencil
    const bw = 34;
    ctx.save(); ctx.beginPath(); ctx.rect(w - bw, 0, bw, h); ctx.clip();
    ctx.fillStyle = '#F2C230'; ctx.fillRect(w - bw, 0, bw, h);
    ctx.fillStyle = '#2A1D2A';
    for (let y = -40; y < h + 40; y += 44) { ctx.beginPath(); ctx.moveTo(w - bw, y); ctx.lineTo(w, y + 22); ctx.lineTo(w, y + 44); ctx.lineTo(w - bw, y + 22); ctx.fill(); }
    ctx.restore();
    ctx.save(); ctx.translate(w * 0.52, h / 2); ctx.rotate(-PI / 2);
    ctx.fillStyle = 'rgba(242,194,48,0.85)'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.font = '64px "Bungee", "Arial Black", sans-serif'; ctx.fillText('KEEP', 0, -40);
    ctx.fillText('CLEAR', 0, 36);
    ctx.restore();
    for (let i = 0; i < 40; i++) { ctx.globalAlpha = 0.05 + rand() * 0.08; ctx.fillStyle = '#4A443E'; ctx.beginPath(); ctx.ellipse(rand() * w, rand() * h, 4 + rand() * 18, 2 + rand() * 8, rand() * 3, 0, TAU); ctx.fill(); }
    ctx.globalAlpha = 1;
  }, { repeat: false, fonts: true });
}

// ------------------------------------------------------------------------------------------ local props
// Registered once (module load) in the shared prop registry under 'yard_*' ids so placeProp wires colliders,
// light anchors and cloning. Conventions as PROPKIT: floor at y = 0, front faces -z; 'wall' props have their origin
// on the wall and extend toward -z.

registerProp('yard_cone', (game) => {
  const g = K.prop('yard_cone');
  const pl = K.mat(game, 'plastic', '#ffffff', { rough: 0.45 });
  g.add(tm(K.box(0.42, 0.05, 0.42, 0.02), pl, '#B8481E', { pos: [0, 0.025, 0] }));
  const r = (y) => 0.15 - (0.108 / 0.6) * y;
  g.add(tm(K.lathe([[0.155, 0], [0.15, 0.02], [0.042, 0.6], [0.028, 0.64], [0, 0.645]], { seg: 16, round: 0.012 }), pl, PAL.burntOrange, { pos: [0, 0.045, 0] }));
  for (const [a, b] of [[0.22, 0.31], [0.38, 0.44]]) {
    g.add(tm(K.lathe([[r(a) + 0.005, a], [r(b) + 0.005, b]], { seg: 16 }), pl, '#F4F1E8', { pos: [0, 0.045, 0] }));
  }
  g.userData.colliders = [{ min: [-0.18, 0, -0.18], max: [0.18, 0.68, 0.18] }];
  return K.finish(game, g, { ao: { res: 24 } });
}, { category: 'rooms_yard', tags: ['yard', 'clutter'], size: [0.42, 0.69, 0.42], desc: 'traffic cone with reflective bands' });

registerProp('yard_lawn_chair', (game, opts = {}) => {
  const g = K.prop('yard_lawn_chair');
  const alu = K.mat(game, 'chrome', '#B8C0CA');
  const web = K.mat(game, 'plastic', '#ffffff', { rough: 0.55 });
  const cols = opts.colors ?? [PAL.burntOrange, '#F4F1E8', PAL.harvestGold, PAL.avocado];
  const W = 0.56, SY = 0.36, SD = 0.44, hw = W / 2;
  const T = (pts, r = 0.013) => g.add(K.m(K.tube(pts, r, { seg: Math.max(8, pts.length * 6), radial: 6 }), alu));
  // seat frame, back frame, arms, legs
  T([[-hw, SY, -SD / 2], [hw, SY, -SD / 2]]);
  T([[-hw, SY, SD / 2], [hw, SY, SD / 2]]);
  for (const s of [-1, 1]) {
    T([[s * hw, SY, -SD / 2], [s * hw, SY, SD / 2]]);
    T([[s * hw, SY, SD / 2], [s * hw, 0.62, SD / 2 + 0.1], [s * hw, 0.9, SD / 2 + 0.2]]);
    T([[s * hw, 0.02, -SD / 2 - 0.04], [s * hw, 0.3, -SD / 2 + 0.02], [s * hw, 0.56, -SD / 2 + 0.02]]);
    T([[s * hw, 0.02, SD / 2 + 0.06], [s * hw, SY, SD / 2 - 0.02]]);
    g.add(tm(K.box(0.07, 0.03, SD + 0.1, 0.012), web, '#F4F1E8', { pos: [s * (hw + 0.005), 0.575, 0.02] }));
  }
  T([[-hw, 0.9, SD / 2 + 0.2], [hw, 0.9, SD / 2 + 0.2]]);
  T([[-hw, 0.02, -SD / 2 - 0.04], [hw, 0.02, -SD / 2 - 0.04]], 0.011);
  // woven webbing: seat
  for (let i = 0; i < 5; i++) {
    const z = -SD / 2 + 0.05 + i * ((SD - 0.1) / 4);
    g.add(tm(K.box(W, 0.012, 0.062, 0.005), web, cols[i % cols.length], { pos: [0, SY + 0.004 + (i % 2) * 0.004, z] }));
  }
  for (let i = 0; i < 4; i++) {
    const x = -hw + 0.09 + i * ((W - 0.18) / 3);
    g.add(tm(K.box(0.058, 0.012, SD, 0.005), web, cols[(i + 1) % cols.length], { pos: [x, SY + 0.006, 0] }));
  }
  // woven webbing: back (reclined plane)
  const back = new THREE.Group();
  back.position.set(0, SY + 0.02, SD / 2 + 0.01);
  back.rotation.x = -0.36;
  for (let i = 0; i < 5; i++) back.add(tm(K.box(W, 0.062, 0.012, 0.005), web, cols[(i + 2) % cols.length], { pos: [0, 0.07 + i * 0.105, (i % 2) * 0.004] }));
  for (let i = 0; i < 4; i++) back.add(tm(K.box(0.058, 0.52, 0.012, 0.005), web, cols[(i + 3) % cols.length], { pos: [-hw + 0.09 + i * ((W - 0.18) / 3), 0.28, 0.003] }));
  g.add(back);
  g.userData.colliders = [{ min: [-hw - 0.05, 0, -SD / 2 - 0.08], max: [hw + 0.05, 0.9, SD / 2 + 0.22] }];
  return K.finish(game, g, { ao: { res: 36 } });
}, { category: 'rooms_yard', tags: ['yard', 'seat', 'clutter'], size: [0.66, 0.92, 0.75], desc: '70s webbed aluminum lawn chair' });

registerProp('yard_cooler', (game) => {
  const g = K.prop('yard_cooler');
  const pl = K.mat(game, 'plastic', '#ffffff', { rough: 0.4 });
  const chrome = K.mat(game, 'chrome', '#A8B0BA');
  g.add(tm(K.box(0.62, 0.34, 0.38, 0.05), pl, '#C8342A', { pos: [0, 0.19, 0] }));
  g.add(tm(K.box(0.64, 0.06, 0.4, 0.03), pl, '#F4F1E8', { pos: [0, 0.035, 0] }));
  g.add(tm(K.box(0.64, 0.085, 0.4, 0.035), pl, '#F4F1E8', { pos: [0, 0.4, 0] }));
  g.add(tm(K.box(0.5, 0.05, 0.012, 0.006), pl, '#F4F1E8', { pos: [0, 0.2, -0.193] }));
  g.add(K.m(K.tube([[-0.24, 0.43, 0], [-0.24, 0.5, 0], [0.24, 0.5, 0], [0.24, 0.43, 0]], 0.012, { seg: 16, radial: 6 }), chrome));
  for (const s of [-1, 1]) g.add(K.m(K.box(0.03, 0.06, 0.12, 0.01), chrome, { pos: [s * 0.315, 0.3, 0] }));
  g.add(K.m(K.box(0.07, 0.05, 0.02, 0.008), chrome, { pos: [0, 0.36, -0.2] }));
  return K.finish(game, g, { ao: { res: 30 } });
}, { category: 'rooms_yard', tags: ['yard', 'clutter'], size: [0.64, 0.5, 0.4], desc: 'red steel-belted picnic cooler' });

registerProp('yard_wallpack', (game, opts = {}) => {
  const g = K.prop('yard_wallpack');
  const body = K.mat(game, 'metal', '#5A4E48', { rough: 0.5 });
  const galv = K.mat(game, 'metal', '#A8B0BA', { rough: 0.45 });
  const color = opts.color ?? PAL.sodium;
  g.add(K.m(K.box(0.36, 0.3, 0.05, 0.015), body, { pos: [0, 0.15, -0.025] }));
  g.add(K.m(K.taper(K.box(0.34, 0.22, 0.24, 0.035), { axis: 'z', k: 0.8 }), body, { pos: [0, 0.2, -0.16] }));
  g.add(K.m(K.box(0.4, 0.035, 0.3, 0.012), body, { pos: [0, 0.32, -0.16], rot: [-0.16, 0, 0] }));
  const lens = glowPart(K.m(K.box(0.28, 0.1, 0.18, 0.02), K.glow(game, color, 2.4), { pos: [0, 0.085, -0.18], name: 'lens' }));
  g.add(lens);
  for (let k = 0; k < 3; k++) {
    const x = (k - 1) * 0.1, pts = [];
    for (let s = 0; s <= 6; s++) { const a = (s / 6) * PI; pts.push([x, 0.09 - Math.sin(a) * 0.07, -0.08 - (1 - Math.cos(a)) * 0.1]); }
    g.add(K.m(K.tube(pts, 0.006, { seg: 10, radial: 4 }), galv));
  }
  g.add(K.m(K.tube([[0.12, 0.05, -0.02], [0.14, -0.2, -0.03], [0.14, -1.2, -0.03]], 0.018, { seg: 10, radial: 6 }), galv));
  g.userData.parts = { lens };
  g.userData.lightAnchors = [{ pos: [0, -0.15, -0.55], color, intensity: opts.intensity ?? 2.2, distance: opts.distance ?? 7, flicker: 0.02 }];
  g.userData.colliders = [];
  return K.finish(game, g, { ao: { res: 30, height: 0 } });
}, { category: 'rooms_yard', tags: ['yard', 'light', 'wall'], size: [0.4, 0.36, 0.34], desc: 'WALL: caged sodium wall-pack light (parts.lens)' });

registerProp('yard_service_panel', (game) => {
  const g = K.prop('yard_service_panel');
  const grey = K.mat(game, 'metal', '#8E959E', { rough: 0.5 });
  const galv = K.mat(game, 'metal', '#A8B0BA', { rough: 0.45 });
  const label = K.mat(game, 'paint', '#ffffff', { map: signTex('danger') });
  const Y0 = 1.25, PW = 0.72, PH = 0.95, PD = 0.22;
  g.add(K.m(K.box(PW, PH, PD, 0.03), grey, { pos: [0, Y0 + PH / 2, -PD / 2] }));
  g.add(K.m(K.box(PW - 0.08, PH - 0.08, 0.02, 0.008), grey, { pos: [0, Y0 + PH / 2, -PD - 0.005] }));
  g.add(K.m(K.box(0.03, 0.14, 0.03, 0.01), galv, { pos: [0.26, Y0 + 0.45, -PD - 0.03] }));
  const lp = new THREE.PlaneGeometry(0.34, 0.21).rotateY(PI);
  g.add(K.m(lp, label, { pos: [-0.05, Y0 + 0.66, -PD - 0.018] }));
  // meter socket beside it
  g.add(K.m(K.box(0.26, 0.4, 0.14, 0.02), grey, { pos: [-0.56, Y0 + 0.2, -0.07] }));
  g.add(tm(K.cyl(0.085, 0.09, 0.08, { seg: 16, bevel: 0.01 }).clone().rotateX(-PI / 2), galv, '#E8EEF2', { pos: [-0.56, Y0 + 0.24, -0.14] }));
  // conduits: three up to the coping, one down into the gravel, one across toward the door frame
  for (const [x, top] of [[-0.22, 4.35], [0, 4.35], [0.22, 4.35]]) {
    g.add(K.m(K.tube([[x, Y0 + PH, -0.1], [x, Y0 + PH + 0.25, -0.07], [x, top, -0.07]], 0.028, { seg: 8, radial: 6 }), galv));
    for (let y = Y0 + PH + 0.5; y < top; y += 0.9) g.add(K.m(K.box(0.09, 0.04, 0.05, 0.01), galv, { pos: [x, y, -0.05] }));
  }
  g.add(K.m(K.tube([[-0.56, Y0, -0.07], [-0.56, 0.2, -0.07], [-0.56, -0.1, -0.2]], 0.03, { seg: 8, radial: 6 }), galv));
  g.add(K.m(K.tube([[0.3, Y0 + 0.2, -0.1], [0.7, Y0 + 0.2, -0.07], [2.2, Y0 + 0.2, -0.07]], 0.022, { seg: 10, radial: 6 }), galv));
  g.userData.colliders = [{ min: [-0.72, 0, -0.18], max: [-0.4, Y0 + 0.4, 0] }];
  return K.finish(game, g, { ao: { res: 40, height: 0 } });
}, { category: 'rooms_yard', tags: ['yard', 'wall'], size: [1.5, 4.4, 0.25], desc: 'WALL: electrical service panel, meter socket and conduits (origin at the wall foot)' });

registerProp('yard_utility_pole', (game, opts = {}) => {
  const g = K.prop('yard_utility_pole');
  const wood = K.mat(game, 'teak', '#ffffff', { map: K.tex.wood('#6E5238', { dark: 0.45, wear: 0.3 }) });
  const galv = K.mat(game, 'metal', '#8A9098', { rough: 0.5 });
  const glass = K.mat(game, 'crt', '#5FA88A', { rough: 0.12, rim: 0.6, rimColor: '#9FFFD0' });
  const H = opts.height ?? 9.2, AY = H - 0.55;
  g.add(K.m(K.cyl(0.12, 0.16, H, { seg: 12, bevel: 0.03 }), wood));
  g.add(K.m(K.box(2.3, 0.12, 0.13, 0.02, { uv: 1.2, swap: true }), wood, { pos: [0, AY, 0] }));
  for (const s of [-1, 1]) g.add(K.m(K.tube([[s * 0.8, AY - 0.05, 0.08], [0, AY - 0.8, 0.13]], 0.02, { seg: 4, radial: 4 }), galv));
  for (const x of [-1.0, -0.35, 1.0]) {
    g.add(K.m(K.cyl(0.012, 0.012, 0.1, { seg: 6 }), galv, { pos: [x, AY + 0.06, 0] }));
    g.add(K.m(K.lathe([[0, 0], [0.05, 0], [0.055, 0.03], [0.035, 0.05], [0.042, 0.08], [0.02, 0.12], [0, 0.125]], { seg: 10 }), glass, { pos: [x, AY + 0.1, 0] }));
  }
  if (opts.transformer) {
    g.add(tm(K.cyl(0.24, 0.24, 0.62, { seg: 16, bevel: 0.03 }), galv, '#9AA2AC', { pos: [0.3, AY - 1.5, 0] }));
    g.add(tm(K.cyl(0.26, 0.2, 0.08, { seg: 16, bevel: 0.02 }), galv, '#9AA2AC', { pos: [0.3, AY - 0.88, 0] }));
    g.add(K.m(K.box(0.08, 0.3, 0.08, 0.01), galv, { pos: [0.08, AY - 1.2, 0] }));
  }
  for (let y = 2.4; y < AY - 0.6; y += 0.45) g.add(K.m(K.cyl(0.012, 0.012, 0.2, { seg: 5 }).clone().rotateZ(PI / 2), galv, { pos: [(y * 7) % 2 > 1 ? 0.12 : -0.12, y, 0] }));
  g.userData.colliders = [];
  g.userData.wires = [[-1.0, AY + 0.2, 0], [-0.35, AY + 0.2, 0], [1.0, AY + 0.2, 0]];
  return K.finish(game, g, { ao: false });
}, { category: 'rooms_yard', tags: ['yard', 'backdrop'], size: [2.3, 9.3, 0.3], desc: 'wooden utility pole with crossarm and glass insulators (userData.wires = attach points)' });

registerProp('yard_sign', (game, opts = {}) => {
  const g = K.prop('yard_sign');
  const kind = opts.kind ?? 'trespass';
  const galv = K.mat(game, 'metal', '#A8B0BA', { rough: 0.45 });
  const face = K.mat(game, 'paint', '#ffffff', { map: signTex(kind), rough: 0.5 });
  const w = opts.w ?? 0.72, h = w * 0.625;
  g.add(K.m(K.box(w + 0.03, h + 0.03, 0.018, 0.006), galv, { pos: [0, 0, 0.012] }));
  g.add(K.m(new THREE.PlaneGeometry(w, h).rotateY(PI), face, { pos: [0, 0, 0.0] }));
  for (const [x, y] of [[-1, 1], [1, 1], [-1, -1], [1, -1]]) g.add(K.m(K.cyl(0.008, 0.008, 0.03, { seg: 5 }).clone().rotateX(PI / 2), galv, { pos: [x * (w / 2 - 0.03), y * (h / 2 - 0.03), 0.02] }));
  g.userData.colliders = [];
  return K.finish(game, g, { ao: false });
}, { category: 'rooms_yard', tags: ['yard', 'sign'], size: [0.75, 0.48, 0.03], desc: 'fence sign (opts.kind trespass|danger|wztv|gate); origin at its center, face toward -z' });

// ------------------------------------------------------------------------------------------ build
export function build(game, area, root) {
  const Y = new YardDresser(game, area, root);
  Y.build();
  return Y;
}

class YardDresser {
  constructor(game, area, root) {
    this.game = game;
    this.area = area;
    this.root = root;
    this.rand = mulberry32(0x9a2d13);
    this.objects = (game.level.objects ??= {});
    this.fails = [];
  }

  // placeProp, isolated: one broken prop must not lose the rest of the room.
  put(id, pos, rotY = 0, opts = {}, o = {}) {
    try {
      return placeProp(this.game, o.parent || this.root, id, { pos, rotY, opts, area: this.area.id, ...o });
    } catch (err) {
      this.fails.push(id);
      console.warn(`[rooms:yard] prop "${id}" failed`, err);
      return null;
    }
  }

  step(name, fn) {
    try { fn(); } catch (err) { console.error(`[rooms:yard] ${name}`, err); }
  }

  build() {
    const t0 = performance.now();
    this.step('tower', () => this.buildTower());
    this.step('hut', () => this.buildHut());
    this.step('van', () => this.buildVan());
    this.step('lamps', () => this.buildLamps());
    this.step('neon', () => this.buildNeon());
    this.step('wall', () => this.buildMcWall());
    this.step('clutter', () => this.buildClutter());
    this.step('ground', () => this.buildGround());
    this.step('trench', () => this.buildTrench());
    this.step('fence', () => this.buildFenceSigns());
    this.step('beyond', () => this.buildBeyond());
    this.step('critters', () => this.buildCritters());
    this.step('toy', () => this.buildRadioToy());
    this.step('runtime', () => this.startRuntime());
    this.objects.yard_meta = { buildMs: Math.round(performance.now() - t0), fails: this.fails };
  }

  // world position of a prop-local point
  world(g, local, out = new THREE.Vector3()) {
    g.updateMatrixWorld(true);
    return out.fromArray(local).applyMatrix4(g.matrixWorld);
  }

  // registers a prop's local light anchors with ids (so they can be switched)
  anchors(g, prefix, extra = {}) {
    const ids = [];
    (g.userData.lightAnchors || []).forEach((a, i) => {
      const id = `${prefix}_${i}`;
      this.game.lights?.addAnchor?.({ ...a, ...extra, id, pos: this.world(g, a.pos).toArray(), area: this.area.id });
      ids.push(id);
    });
    return ids;
  }

  pool(pos, radius, color, intensity) {
    return this.game.fx?.lightPool?.(new THREE.Vector3(pos[0], pos[1] ?? 0.02, pos[2]), radius, color, intensity) || { set() {}, remove() {} };
  }

  // ---------------------------------------------------------------------------------------- tower + cage
  buildTower() {
    const g = this.game;
    const tower = this.put('yd_tower', ANCHORS.tower_base.pos, 0, {}, { colliders: false, lights: false });
    if (!tower) return;
    // one see-through lattice blocker: stops bodies, lets bullets and the camera through the struts
    const [x0, z0, x1, z1] = ANCHORS.tower_base.rect;
    g.level.col.addBox([x0 - 0.2, 0, z0 - 0.2], [x1 + 0.2, 3, z1 + 0.2], { tag: 'lattice', camera: false });
    const P = tower.userData.parts;
    const beacons = [...(P.beacons || [])];
    beacons.sort((a, b) => this.world(b, [0, 0, 0], _v2).y - this.world(a, [0, 0, 0], _v).y);
    this.tower = tower;
    this.objects.tower = { group: tower, parts: { upper: P.upper, beacons, beaconTop: P.beaconTop } };
    this.beacons = this.makeBeacons(tower, beacons);
    this.objects.tower_beacons = this.beacons;
    // replace the exterior placeholder tower and take over the level's beacon switch
    const ext = g.level.groups?.ext;
    if (ext) for (const name of ['tower', 'tower_beacons']) { const o = ext.getObjectByName(name); if (o && o.parent) o.parent.remove(o); }
    g.level.beacons = { mesh: beacons[0] || null, set: (on) => this.beacons._level(on) };
    this.beacons.set(false);

    const cage = this.put('kill_switch_cage', ANCHORS.ee_kill_switch.pos, ANCHORS.ee_kill_switch.rotY);
    if (cage) {
      const u = cage.userData;
      this.objects.ee_kill_switch = {
        group: cage, parts: { door: u.parts.door, switch: u.parts.switch },
        pos: new THREE.Vector3(...ANCHORS.ee_kill_switch.pos),
        stand: new THREE.Vector3(...ANCHORS.ee_kill_switch.stand),
        handle: this.world(cage, u.anchors?.handle || [0, 1.6, 0.1]),
        interact: this.world(cage, u.interact?.point || [0, 1.2, -0.8]),
      };
      // a red work light clamped on the cage roof makes it read at night
      this.pool([45, 0.02, -9.0], 1.6, '#FF6A4A', 0.16);
    }
  }

  makeBeacons(tower, list) {
    const game = this.game;
    const cache = new Map();
    const matOf = (on, color) => {
      const key = `${on}|${color}`;
      let m = cache.get(key);
      if (!m) cache.set(key, (m = on ? K.glow(game, color, 2.6) : K.mat(game, 'crt', hexMul(color, 0.35), { rough: 0.15, rim: 0.5 })));
      return m;
    };
    const B = {
      group: tower, parts: { beacons: list }, mode: 'blink', color: PAL.onAirRed,
      _lv: false, _state: '', _t: 0, _seq: 0,
      apply(on) {
        const key = `${on}|${this.color}`;
        if (key === this._state) return;
        this._state = key;
        for (const b of list) b.material = matOf(on, this.color);
      },
      set(on) { this.apply(!!on); },
      _level(on) { this._lv = !!on; if (this.mode === 'blink') this.apply(this._lv); },
      setMode(m) {
        this.mode = m;
        this._state = '';
        if (m === 'on') this.apply(true);
        else if (m === 'off') this.apply(false);
        else if (m === 'blink') this.apply(this._lv);
      },
      setColor(hex) { this.color = hex || PAL.onAirRed; this._state = ''; if (this.mode !== 'rainbow') this.setMode(this.mode); },
      offSequence(seconds = 1.5) { this.mode = 'seq'; this._seq = Math.max(0.05, seconds); this._t = 0; this._state = ''; },
      tick(dt) {
        if (this.mode === 'rainbow') {
          this._t += dt;
          const k = Math.floor(this._t * 5);
          if (k === this._rk) return;
          this._rk = k;
          list.forEach((b, i) => { b.material = matOf(true, RAINBOW[(k + i) % RAINBOW.length]); });
          this._state = '';
        } else if (this.mode === 'seq') {
          this._t += dt;
          const n = list.length;
          list.forEach((b, i) => { b.material = matOf(this._t < (i / Math.max(1, n - 1)) * this._seq, this.color); });
          if (this._t > this._seq) { this.mode = 'off'; this._state = ''; this.apply(false); }
        }
      },
    };
    return B;
  }

  // ---------------------------------------------------------------------------------------- hut + SkyCam
  buildHut() {
    // cam_yard [36,3,-3] used to sit INSIDE the hut's roof slab (y 2.85–3.05) with SkyCam 13 filling its lens. The hut
    // is now HUT_DX east of the layout rect and scaled HUT_S (x 36.7–39.5, roof top 2.59): the anchor looks over the roof
    // edge at the yard, and SkyCam rides a mast on the roof's back-east corner, outside that frustum (the virtual feed
    // camera stays at feed_cam_yard; the old centre mast stub stays as a cable mast).
    const a = ANCHORS.prop_hut;
    const hut = this.put('yd_hut', [a.pos[0] + HUT_DX, 0, a.pos[2]], a.rotY, { camYaw: this.feedYaw(), camTilt: -0.05 }, { colliders: false, lights: false });
    if (!hut) return;
    hut.scale.setScalar(HUT_S);
    hut.updateMatrixWorld(true);
    for (const c of hut.userData.colliders || []) {
      const bb = new THREE.Box3();
      for (let i = 0; i < 8; i++) bb.expandByPoint(_v.set(i & 1 ? c.max[0] : c.min[0], i & 2 ? c.max[1] : c.min[1], i & 4 ? c.max[2] : c.min[2]).applyMatrix4(hut.matrixWorld));
      this.game.level?.col?.addBox(bb.min.toArray(), bb.max.toArray(), { tag: 'prop', ...(c.opts || {}) });
    }
    for (const la of hut.userData.lightAnchors || []) this.game.lights?.addAnchor?.({ ...la, pos: this.world(hut, la.pos).toArray(), area: this.area.id });
    const P = hut.userData.parts;
    this.hut = hut;
    const RT = 3.05;                                   // roof top in hut space (HUT.H 2.75 + 0.1 + 0.2)
    if (P.skycam) {
      P.skycam.position.set(1.5, P.skycam.position.y, 0.95);
      const galv = K.mat(this.game, 'metal', '#A8B0BA', { rough: 0.45 });
      const mast = new THREE.Group();
      mast.add(K.m(K.cyl(0.13, 0.15, 0.06, { seg: 12, bevel: 0.015 }), galv, { pos: [1.5, RT, 0.95] }));
      mast.add(K.m(K.cyl(0.045, 0.05, 0.42, { seg: 10, bevel: 0.008 }), galv, { pos: [1.5, RT + 0.05, 0.95] }));
      hut.add(mast);
    }
    this.objects.yard_hut = { group: hut, parts: { ...P } };
    this.skycam = { pan: P.skycam, tilt: P.skycamTilt, tally: P.skycamTally, base: this.feedYaw() };
    this.objects.feed_cam_yard_prop = { group: P.skycam, parts: { pan: P.skycam, tilt: P.skycamTilt, tally: P.skycamTally } };
    // warm spill from the window and the door bulb on the gravel
    this.pool([37.1 + HUT_DX, 0.02, -5.45], 1.4, '#FFD9A0', 0.14);
    this.pool([39.9, 0.02, -3.4], 1.4, PAL.tungsten, 0.18);
  }

  feedYaw() {
    const p = FEED.pos, t = FEED.target;
    return Math.atan2(-(t[0] - p[0]), -(t[2] - p[2]));
  }

  // ---------------------------------------------------------------------------------------- news van
  buildVan() {
    const a = ANCHORS.prop_van;
    const van = this.put('yd_news_van', a.pos, 0, {});
    if (!van) return;
    const P = van.userData.parts;
    this.van = van;
    this.radio = P.radio || null;
    this.objects.news_van = { group: van, parts: { doorL: P.doorL, doorR: P.doorR, mast: P.mast, mastHead: P.mastHead, domeLight: P.domeLight, headlights: P.headlights } };
    this.pool([46.2, 0.02, -3.7], 1.7, PAL.tungsten, 0.2);
  }

  // ---------------------------------------------------------------------------------------- sodium posts
  buildLamps() {
    const p1 = this.put('yd_sodium_post', ANCHORS.prop_lamp_post_1.pos, PI);
    const p2 = this.put('yd_sodium_post', ANCHORS.prop_lamp_post_2.pos, PI / 2);
    const groups = [p1, p2].filter(Boolean);
    const parts = {};
    groups.forEach((g, i) => {
      parts[`lamp${i + 1}`] = g.userData.parts.lamp;
      parts[`beam${i + 1}`] = g.userData.parts.beam;
      const head = this.world(g, [0, 0, -1.94]);
      this.pool([head.x, 0.02, head.z], 4.2, PAL.sodium, 0.34);
      this.pool([head.x, 0.02, head.z], 1.8, '#FFD08A', 0.2);
    });
    this.lamps = groups;
    this.objects.sodium_posts = { groups, parts };
    this.lampHeads = groups.map((g) => this.world(g, [0, 6.35, -1.94]));
  }

  // ---------------------------------------------------------------------------------------- neon on the MC wall
  buildNeon() {
    const neon = this.put('yd_neon_wztv', [35.16, 2.95, -8.0], -PI / 2, {}, { lights: false });
    if (!neon) return;
    this.neon = neon;
    this.neonIds = this.anchors(neon, 'yard_neon');
    this.neonPools = [this.pool([36.4, 0.02, -8.7], 2.6, PAL.neonPink, 0.0), this.pool([36.3, 0.02, -6.9], 2.0, '#3F76FF', 0.0)];
    const M = {
      pinkOn: K.glow(this.game, PAL.neonPink, 2.6), blueOn: K.glow(this.game, '#3F76FF', 2.6),
      pinkOff: K.mat(this.game, 'plastic', '#E8B8C8', { transparent: true, opacity: 0.7 }),
      blueOff: K.mat(this.game, 'plastic', '#B8C8E8', { transparent: true, opacity: 0.7 }),
    };
    const P = neon.userData.parts;
    const S = { pink: null, blue: null };
    this.neonSet = (pink, blue) => {
      if (pink === S.pink && blue === S.blue) return;
      S.pink = pink; S.blue = blue;
      if (P.neonPink) P.neonPink.material = pink ? M.pinkOn : M.pinkOff;
      if (P.neonBlue) P.neonBlue.material = blue ? M.blueOn : M.blueOff;
      if (P.haloPink) P.haloPink.visible = pink;
      if (P.haloBlue) P.haloBlue.visible = blue;
      this.neonIds.forEach((id, i) => this.game.lights?.setAnchor?.(id, { enabled: i === 0 ? pink : blue }));
      this.neonPools[0].set({ intensity: pink ? 0.16 : 0 });
      this.neonPools[1].set({ intensity: blue ? 0.14 : 0 });
    };
    this.neonSet(false, false);
    this.neonPos = new THREE.Vector3(35.4, 3.5, -8.0);
    this.objects.yard_neon = { group: neon, parts: { ...P }, set: (on) => this.neonSet(!!on, !!on) };
  }

  // ---------------------------------------------------------------------------------------- MC exterior wall (x = 35)
  buildMcWall() {
    const game = this.game, root = this.root;
    const WX = 35.15;
    // DY landing apron: concrete slab with the hazard band and a KEEP CLEAR stencil
    const apron = K.mat(game, 'paint', '#ffffff', { map: apronTex(), rough: 0.85 });
    const slab = K.box(2.4, 0.04, 3.8, 0.012).clone();
    root.add(K.m(slab, apron, { pos: [WX + 1.2, 0.02, -8.0] }));
    // top face UVs of a rounded box are box-projected poorly: lay a decal plane on top
    const top = new THREE.PlaneGeometry(2.34, 3.74).rotateX(-PI / 2);
    root.add(K.m(top, apron, { pos: [WX + 1.2, 0.044, -8.0] }));
    // wall packs flanking DY and the service panel north of it
    const wp1 = this.put('yard_wallpack', [WX, 3.0, -11.0], -PI / 2);
    const wp2 = this.put('yard_wallpack', [WX, 3.0, -5.6], -PI / 2);
    this.wallPacks = [wp1, wp2].filter(Boolean);
    this.pool([36.3, 0.02, -11.0], 2.8, PAL.sodium, 0.22);
    this.pool([36.3, 0.02, -5.6], 2.4, PAL.sodium, 0.2);
    this.put('yard_service_panel', [WX, 0, -12.6], -PI / 2);
    // wheat-pasted posters on the block wall
    const poster = (card, z, y, w, tilt) => {
      const tex = getCard(card);
      const m = K.mat(game, 'paint', '#ffffff', { map: tex, rough: 0.7 });
      const h = w * 4 / 3;
      root.add(K.m(new THREE.PlaneGeometry(w, h).rotateY(PI / 2), m, { pos: [WX + 0.012, y, z], rot: [tilt, 0, 0] }));
    };
    poster('poster_spooktacular', -13.55, 1.55, 0.72, 0.03);
    poster('poster_boogie_down', -6.1, 1.35, 0.5, -0.04);
    // hose bib + coiled garden hose under the south wall pack
    const galv = K.mat(game, 'metal', '#A8B0BA', { rough: 0.45 });
    const rub = K.mat(game, 'rubber', '#4E8A3A', { rough: 0.6 });
    root.add(K.m(K.cyl(0.03, 0.03, 0.12, { seg: 8 }).clone().rotateZ(-PI / 2), galv, { pos: [WX, 0.6, -6.0] }));
    const coil = [];
    for (let i = 0; i <= 40; i++) { const a = (i / 40) * TAU * 2.6; coil.push([WX + 0.28 + Math.cos(a) * 0.2, 0.05 + i * 0.0035, -5.95 + Math.sin(a) * 0.2]); }
    root.add(K.m(K.tube([[WX + 0.1, 0.6, -6.0], [WX + 0.2, 0.35, -6.0], ...coil], 0.018, { seg: 120, radial: 5 }), rub));
  }

  // ---------------------------------------------------------------------------------------- props with colliders
  buildClutter() {
    // oil drums on a pallet against the MC wall, north of DY (clear of the uplink crank zone)
    this.put('yd_drum_group', [36.35, 0, -10.75], -PI / 2 + 0.12, { set: 'a' });
    // crate stack on the north fence between C1 and the roller rink
    this.put('yd_crate_stack', [45.55, 0, -19.1], PI + 0.06);
    this.put('yd_film_cans', [46.95, 0, -18.95], 0.4, {}, { colliders: false });
    // loose drums
    this.put('yd_oil_drum', [50.45, 0, -11.55], 0.6, { color: 'red', seed: 3 });
    this.put('yd_oil_drum', [49.85, 0, -8.2], 1.2, { color: 'yellow', tipped: true, seed: 4 });
    this.put('yd_oil_drum', [39.3, 0, -5.75], 2.1, { color: 'green', seed: 5 });
    // the shifted hut leaves a 1.3 m alley along the MC wall: a drum + crate close its mouth (no dead-end camp spot)
    this.put('yd_oil_drum', [35.5, 0, -5.2], 0.4, { color: 'blue', seed: 9 });
    this.put('yd_crate', [36.22, 0, -5.28], 0.18, { size: 'md', seed: 11 });
    // crew break corner beside the van's cab: crate with the radio, lawn chair, cooler
    this.put('yd_crate', [41.0, 0, -5.45], 0.12, { size: 'md', seed: 7 });
    this.put('yd_crate', [41.05, 0.7, -5.5], -0.25, { size: 'sm', seed: 8 }, { colliders: false });
    this.put('yard_lawn_chair', [42.35, 0, -5.75], PI + 0.55);
    this.put('yard_cooler', [43.35, 0, -5.3], 0.2);
    this.put('bc_cable_coil', [46.3, 0, -5.05], 0.3, {}, { colliders: false });
    // cones: one by the gate, two marking the van's open rear, one knocked over near the trench
    this.put('yard_cone', [46.75, 0, -2.45], 0.2);
    this.put('yard_cone', [46.55, 0, -5.0], 0.8);
    this.put('yard_cone', [40.32, 0, -2.3], -0.4);
    const fallen = this.put('yard_cone', [44.4, 0.16, -7.3], 0, {}, { colliders: false });
    if (fallen) { fallen.rotation.set(0, 0.9, PI / 2 - 0.1); fallen.position.y = 0.16; }
  }

  // ---------------------------------------------------------------------------------------- ground detail (no colliders)
  buildGround() {
    const nc = { colliders: false };
    for (const [x, z, r, s] of [[40.6, -9.0, 0.3, 1.3], [48.0, -7.2, 1.9, 1], [44.2, -16.4, 0.7, 0.9], [38.6, -7.4, 2.4, 0.7]]) {
      this.put('yd_puddle', [x, 0, z], r, { size: s, seed: Math.round(x * 3) }, nc);
    }
    for (const [x, z, s] of [[42.0, -12.2, 1.2], [47.8, -13.0, 1.0], [45.0, -7.9, 1.4], [39.8, -15.8, 1], [48.8, -16.0, 0.9], [37.6, -9.6, 1.1], [43.0, -18.0, 1]]) {
      this.put('yd_gravel_patch', [x, 0, z], 0, { size: s, seed: Math.round(z * 5) }, nc);
    }
    for (const [x, z] of [[42.6, -9.6], [47.6, -14.5], [46.2, -6.2], [39.2, -11.6], [50.2, -17.0], [36.2, -13.0], [44.0, -3.0 - 1.9]]) {
      this.put('yd_stones', [x, 0, z], this.rand() * TAU, { seed: Math.round(x * 7 + z), count: 7 }, nc);
    }
    for (const [x, z] of [[35.5, -19.6], [50.6, -19.5], [50.6, -2.4], [42.9, -14.25], [47.1, -9.95], [40.2, -2.25], [50.6, -12.6], [35.4, -14.2], [44.1, -19.7]]) {
      this.put('yd_weeds', [x, 0, z], this.rand() * TAU, { seed: Math.round(x * 11 + z * 3) }, nc);
    }
  }

  // ---------------------------------------------------------------------------------------- coax trench hut → tower
  buildTrench() {
    const game = this.game, root = this.root;
    const conc = K.mat(game, 'paint', '#ffffff', { map: apronTex(), rough: 0.9 });
    const rub = K.mat(game, 'rubber', '#2E2A36', { rough: 0.7 });
    const a = new THREE.Vector2(39.95, -5.1), b = new THREE.Vector2(42.3, -9.3);
    const dir = b.clone().sub(a);
    const len = dir.length();
    dir.normalize();
    const yaw = Math.atan2(dir.x, dir.y);
    const n = Math.floor(len / 0.52);
    const slab = K.box(0.44, 0.05, 0.5, 0.012);
    for (let i = 0; i < n; i++) {
      if (i === 5) continue;                         // one cover missing: the cables show
      const t = (i + 0.5) / n;
      const x = a.x + (b.x - a.x) * t, z = a.y + (b.y - a.y) * t;
      const j = (this.rand() - 0.5) * 0.08;
      root.add(tm(slab, conc, i % 3 === 0 ? '#C8C2BA' : '#B4AEA6', { pos: [x, 0.018, z], rot: [(this.rand() - 0.5) * 0.04, yaw + j, (this.rand() - 0.5) * 0.05] }));
    }
    // three coax lines running along under the covers (visible at both ends and in the gap)
    for (let k = 0; k < 3; k++) {
      const off = (k - 1) * 0.08;
      const pts = [];
      for (let s = 0; s <= 8; s++) {
        const t = s / 8;
        pts.push([a.x + (b.x - a.x) * t + dir.y * off, 0.015, a.y + (b.y - a.y) * t - dir.x * off]);
      }
      pts.unshift([a.x - dir.x * 0.3 + dir.y * off, 0.0, a.y - dir.y * 0.3 - dir.x * off]);
      root.add(K.m(K.tube(pts, 0.03, { seg: 36, radial: 6 }), rub));
    }
    // crew cable: van rear → hut door, snaking over the gravel
    const snake = [[45.7, 0.03, -3.0], [46.2, 0.02, -4.4], [45.4, 0.02, -5.0], [43.9, 0.02, -4.97], [42.8, 0.02, -4.93], [41.8, 0.02, -4.95], [40.4, 0.02, -4.9], [40.1, 0.02, -4.3], [39.98, 0.02, -3.8], [39.8, 0.13, -3.5]];
    root.add(K.m(K.tube(snake, 0.022, { seg: 60, radial: 5 }), K.mat(game, 'rubber', '#E3662B', { rough: 0.6 })));
  }

  // ---------------------------------------------------------------------------------------- fence signs
  buildFenceSigns() {
    this.put('yard_sign', [38.2, 1.7, -19.93], PI, { kind: 'trespass' });
    this.put('yard_sign', [50.93, 1.8, -11.2], PI / 2, { kind: 'danger' });
    this.put('yard_sign', [45.9, 1.7, -2.07], 0, { kind: 'wztv' });
    this.put('yard_sign', [50.93, 1.5, -3.6], PI / 2, { kind: 'gate', w: 0.5 });
  }

  // ---------------------------------------------------------------------------------------- beyond the fence
  buildBeyond() {
    const game = this.game, root = this.root;
    const nc = { colliders: false, lights: false };
    this.put('sky_billboard', [44.5, 0, -31.5], PI - 0.08, { ad: 'wztv' }, nc);
    this.put('sky_skyline', [40, 0, -112], PI, { seed: 5, w: 100, ad: 'roller_boogie' }, nc);
    this.put('sky_skyline', [128, 0, -14], PI / 2, { seed: 9, w: 90, ad: 'double_vision' }, nc);
    this.put('st_car_70s', [55.2, 0, 2.6], 0.3, { color: '#E8A92E' }, nc);
    this.put('st_hydrant', [52.4, 0, 0.8], 0.5, {}, nc);
    // utility poles with sagging wires along the north and east outside the fence
    const polesAt = [[37.5, -24.5, 0.05, false], [47.0, -24.5, 0, true], [56.5, -18.5, PI / 2 - 0.5, false], [57.0, -6.0, PI / 2, false], [57.0, 6.5, PI / 2, true]];
    const poles = polesAt.map(([x, z, r, tr]) => this.put('yard_utility_pole', [x, 0, z], r, { transformer: tr }, nc)).filter(Boolean);
    const wire = K.mat(game, 'rubber', '#241E2C', { rough: 0.6 });
    for (let i = 0; i < poles.length - 1; i++) {
      const pa = poles[i], pb = poles[i + 1];
      for (let k = 0; k < 3; k++) {
        const A = this.world(pa, pa.userData.wires[k]), B = this.world(pb, pb.userData.wires[k]);
        const pts = [];
        for (let s = 0; s <= 10; s++) {
          const t = s / 10;
          pts.push([A.x + (B.x - A.x) * t, A.y + (B.y - A.y) * t - Math.sin(t * PI) * 0.75, A.z + (B.z - A.z) * t]);
        }
        const m = K.m(K.tube(pts, 0.016, { seg: 20, radial: 4 }), wire, { cast: false });
        root.add(m);
      }
    }
    // service drop from the NE pole to the hut roof... too far; drop to the tower instead (feeds the transmitter)
    if (poles[1]) {
      const A = this.world(poles[1], poles[1].userData.wires[2]);
      const B = new THREE.Vector3(46.2, 8.2, -13.2);
      const pts = [];
      for (let s = 0; s <= 10; s++) { const t = s / 10; pts.push([A.x + (B.x - A.x) * t, A.y + (B.y - A.y) * t - Math.sin(t * PI) * 1.1, A.z + (B.z - A.z) * t]); }
      root.add(K.m(K.tube(pts, 0.018, { seg: 20, radial: 4 }), wire, { cast: false }));
    }
  }

  // ---------------------------------------------------------------------------------------- fireflies + moths
  buildCritters() {
    const game = this.game;
    const rnd = this.rand;
    const FF = 34;
    const moths = (this.lampHeads || []).length * 6 + 5;
    const n = FF + moths;
    const pos = new Float32Array(n * 3), col = new Float32Array(n * 3);
    const home = [];
    const zones = [[38.5, -8.8, 3.5], [47.8, -7.4, 3], [44.5, -17.2, 3], [49.0, -12.8, 2], [41.0, -12.5, 2.5], [37.5, -18.8, 2]];
    for (let i = 0; i < FF; i++) {
      const [cx, cz, r] = zones[i % zones.length];
      const a = rnd() * TAU, d = Math.sqrt(rnd()) * r;
      home.push({ x: cx + Math.cos(a) * d, y: 0.4 + rnd() * 1.6, z: cz + Math.sin(a) * d, ph: rnd() * 100, sp: 0.4 + rnd() * 0.5, blink: 0.25 + rnd() * 0.4, kind: 0 });
    }
    const centers = [...(this.lampHeads || []).map((h) => h.clone().setY(h.y - 0.2)), new THREE.Vector3(39.8, 2.05, -3.4)];
    for (let i = 0; i < moths; i++) {
      const c = centers[i % centers.length];
      home.push({ x: c.x, y: c.y, z: c.z, ph: rnd() * 100, sp: 2.5 + rnd() * 2, r: 0.25 + rnd() * 0.4, kind: 1 });
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3).setUsage(THREE.DynamicDrawUsage));
    geo.setAttribute('color', new THREE.BufferAttribute(col, 3).setUsage(THREE.DynamicDrawUsage));
    geo.boundingSphere = new THREE.Sphere(new THREE.Vector3(43, 3, -11), 16);
    const mat = new THREE.PointsMaterial({
      size: 0.14, map: game.tex.radial(), vertexColors: true, transparent: true, depthWrite: false,
      blending: THREE.AdditiveBlending, sizeAttenuation: true,
    });
    const pts = new THREE.Points(geo, mat);
    pts.name = 'yard_critters';
    pts.userData.noMerge = true;
    pts.frustumCulled = true;
    this.root.add(pts);
    this.critters = { pts, home, pos, col, n, FF };
  }

  // ---------------------------------------------------------------------------------------- toy: van radio
  buildRadioToy() {
    const game = this.game;
    const radio = this.radio;
    if (!radio) return;
    // the crew took the radio out of the van: it sits on the crates beside the cab (GDD toy_van_radio [41,1,-4.9])
    this.root.attach(radio);
    radio.position.set(41.02, 1.155, -5.5);
    radio.rotation.set(0, 0.42, 0);
    radio.updateMatrixWorld(true);
    K.merge(radio);
    const T = { playing: false, t: 0, voice: null, beat: 0 };
    this.radioToy = T;
    const pos = new THREE.Vector3(41.0, 1.2, -5.4);
    const stop = () => {
      T.playing = false;
      try { T.voice?.stop?.(0.25); } catch (e) { /* voice gone */ }
      T.voice = null;
      radio.scale.set(1, 1, 1);
      radio.rotation.z = 0;
    };
    T.stop = stop;
    game.interact?.register?.({
      id: 'toy_van_radio', pos, radius: 1.6, height: 2.0,
      prompt: () => ({}),
      use: () => {
        if (T.playing) { stop(); return; }
        T.playing = true; T.t = 0; T.beat = 0;
        T.voice = game.audio?.play?.('toy_radio', { pos }) || null;
        game.fx?.burst?.(pos.clone().setY(1.45), { shape: 'star', count: 4, size: 0.07, speed: 1.4, life: 0.6, gravity: -1 });
      },
    });
    this.objects.toy_van_radio = { group: radio, parts: { radio }, get playing() { return T.playing; } };
  }

  // ---------------------------------------------------------------------------------------- runtime
  startRuntime() {
    const game = this.game;
    this.powerSeen = false;
    this.powerT = 0;
    this.neonState = 0;         // 0 off, 1 flickering in, 2 on
    this.neonT = 0;
    this.buzzT = 4 + this.rand() * 6;
    this.clock = 0;
    this.feedCamT = 0;
    game.events?.on?.('game:start', () => {
      this.beacons?.setColor(PAL.onAirRed);
      this.beacons?.setMode('blink');
      this.radioToy?.stop?.();
      const cage = this.objects.ee_kill_switch;
      if (cage?.parts.door) cage.parts.door.rotation.y = 0;
      if (cage?.parts.switch) cage.parts.switch.rotation.x = 0;
    });
    game.events?.on?.('egg:step', (e) => { if (e && e.step === 4) this.beacons?.setMode('rainbow'); });
    game.events?.on?.('machine:boss_start', () => this.beacons?.offSequence(1.5));
    this.unsub = game.render?.addPrePass?.(() => this.tick());
  }

  tick() {
    const game = this.game;
    const t = game.time;
    const real = t.realDt || 0;
    const dt = t.dt || 0;
    const lv = game.level;
    this.clock += dt;
    this.updatePower(real);
    this.beacons?.tick(dt);
    const rootVisible = lv.areaRoots?.yard ? lv.areaRoots.yard.visible : true;
    if (!rootVisible) return;
    this.updateSkycam(real);
    this.updateRadio(dt);
    this.updateCritters(dt);
  }

  updatePower(dt) {
    const game = this.game;
    const on = !!(game.level?.powered || game.machines?.powerOn);
    if (!on) {
      if (this.powerSeen) { this.powerSeen = false; this.neonState = 0; this.neonSet?.(false, false); this.setTally(false); }
      return;
    }
    if (!this.powerSeen) { this.powerSeen = true; this.powerT = 0; }
    this.powerT += dt;
    if (!this.neonSet) return;
    if (this.neonState === 0) {
      const sig = game.signon?.waveReached;
      const reached = typeof sig === 'function' ? !!sig.call(game.signon, this.neonPos) : this.powerT >= LEVER.distanceTo(this.neonPos) / WAVE_SPEED;
      if (reached || this.powerT > 8) { this.neonState = 1; this.neonT = 0; this.setTally(true); }
    } else if (this.neonState === 1) {
      this.neonT += dt;
      const k = this.neonT;
      const onNow = k < 0.06 || (k > 0.14 && k < 0.2) || k > 0.3;
      this.neonSet(onNow, k > 0.18 ? onNow : false);
      if (k > 0.45) { this.neonState = 2; this.neonSet(true, true); }
    } else {
      // an occasional buzz: the pink tube stutters twice
      this.buzzT -= dt;
      if (this.buzzT < 0) {
        const k = -this.buzzT;
        this.neonSet(!(k < 0.05 || (k > 0.11 && k < 0.15)), true);
        if (k > 0.2) { this.buzzT = 5 + this.rand() * 9; this.neonSet(true, true); }
      }
    }
  }

  setTally(on) {
    const tally = this.skycam?.tally;
    if (!tally) return;
    tally.material = on ? K.glow(this.game, PAL.onAirRed, 2.6) : K.mat(this.game, 'crt', '#5A1A1A');
  }

  updateSkycam(dt) {
    const S = this.skycam;
    if (!S?.pan) return;
    // follow the screens' feed camera when it exposes one, else the GDD pan: ±20° over 8 s
    this.feedCamT -= dt;
    if (!this.feedCam && this.feedCamT <= 0) { this.feedCamT = 2; this.feedCam = this.findFeedCam(); }
    const cam = this.feedCam;
    if (cam && cam.isObject3D) {
      cam.getWorldDirection(_v);
      if (cam.isCamera) { /* cameras look down -z: getWorldDirection already returns the view direction */ }
      S.pan.rotation.y = Math.atan2(-_v.x, -_v.z);
      if (S.tilt) S.tilt.rotation.x = Math.asin(THREE.MathUtils.clamp(_v.y, -1, 1));
      return;
    }
    S.pan.rotation.y = S.base + (20 * PI / 180) * Math.sin((this.game.time.realNow * TAU) / 8);
  }

  findFeedCam() {
    const s = this.game.screens;
    if (!s) return null;
    const c = s.feedCams?.yard || s.feedCameras?.yard || s.cams?.yard || s.cameras?.yard || s.cameras?.feed_cam_yard
      || s.feeds?.yard?.camera || s.feeds?.feed_yard?.camera || (typeof s.feedCamera === 'function' ? s.feedCamera('yard') : null);
    return c && c.isObject3D ? c : null;
  }

  updateRadio(dt) {
    const T = this.radioToy, r = this.radio;
    if (!T || !T.playing || !r) return;
    T.t += dt;
    const beat = T.t * (96 / 60);
    const ph = beat % 1;
    const bump = Math.exp(-ph * 7);
    r.scale.set(1 + bump * 0.05, 1 + bump * 0.12 - 0.03, 1 + bump * 0.05);
    r.rotation.z = Math.sin(beat * PI) * 0.06;
    if (Math.floor(beat / 2) !== T.beat) {
      T.beat = Math.floor(beat / 2);
      this.game.fx?.burst?.(_v.set(41.0, 1.45, -5.5), { shape: 'star', count: 1, size: 0.05, speed: 0.9, life: 0.7, gravity: -1.2, colors: [RAINBOW[T.beat % RAINBOW.length]] });
    }
    if (T.t > 20) T.stop();
  }

  updateCritters(dt) {
    const C = this.critters;
    if (!C) return;
    const time = this.game.time.realNow;
    const { home, pos, col, n, FF } = C;
    for (let i = 0; i < n; i++) {
      const h = home[i];
      let x, y, z, b;
      if (h.kind === 0) {
        const s = time * h.sp + h.ph;
        x = h.x + Math.sin(s * 0.7) * 0.9 + Math.sin(s * 1.9) * 0.25;
        y = h.y + Math.sin(s * 1.1) * 0.35;
        z = h.z + Math.cos(s * 0.6) * 0.9 + Math.cos(s * 2.3) * 0.2;
        const bl = Math.sin(time * TAU * h.blink + h.ph);
        b = bl > 0.35 ? (bl - 0.35) * 2.6 : 0;
        col[i * 3] = 0.9 * b; col[i * 3 + 1] = 1.25 * b; col[i * 3 + 2] = 0.25 * b;
      } else {
        const s = time * h.sp + h.ph;
        x = h.x + Math.cos(s) * h.r + Math.sin(s * 3.7) * 0.06;
        y = h.y + Math.sin(s * 1.7) * 0.18;
        z = h.z + Math.sin(s * 1.3) * h.r;
        b = 0.35 + 0.15 * Math.sin(s * 9);
        col[i * 3] = 1.1 * b; col[i * 3 + 1] = 0.95 * b; col[i * 3 + 2] = 0.7 * b;
      }
      pos[i * 3] = x; pos[i * 3 + 1] = y; pos[i * 3 + 2] = z;
    }
    C.pts.geometry.attributes.position.needsUpdate = true;
    C.pts.geometry.attributes.color.needsUpdate = true;
    void FF; void dt;
  }
}
