// Tiny animation kit for the level's set pieces (doors, windows): easing curves, a timeline of spans, and a
// ballistic debris simulator (pieces fly, spin, bounce once or twice on the floor, shrink away and hide).
// Everything runs in the parent's local space and is driven by the owner's update(dt).
//
//   ease.outBack(t, s) ease.inOutSine(t) ease.outCubic(t)
//   new Timeline(): span(start, dur, fn(k)), at(time, fn), update(dt) → busy, finish(), clear(), t
//   new Debris(): launch(obj, vel[3], spin[3], {delay, life, gravity, floorY, radius}), update(dt) → busy,
//                 finish() (hides every piece now), clear()

export const ease = {
  outBack: (t, s = 1.70158) => { const u = t - 1; return 1 + (s + 1) * u * u * u + s * u * u; },
  inOutSine: (t) => 0.5 - 0.5 * Math.cos(Math.PI * t),
  outCubic: (t) => 1 - (1 - t) ** 3,
};

export class Timeline {
  constructor() {
    this.items = [];
    this.t = 0;
  }

  span(start, dur, fn) {
    this.items.push({ start, dur, fn, done: false });
    return this;
  }

  at(time, fn) {
    return this.span(time, 0, () => fn());
  }

  update(dt) {
    this.t += dt;
    let busy = false;
    for (const it of this.items) {
      if (it.done) continue;
      if (this.t < it.start) { busy = true; continue; }
      const k = it.dur > 0 ? Math.min(1, (this.t - it.start) / it.dur) : 1;
      it.fn(k);
      if (k >= 1) it.done = true; else busy = true;
    }
    return busy;
  }

  // Jump to the end state: every pending item runs once with k = 1, in start order.
  finish() {
    const pending = this.items.filter((it) => !it.done).sort((a, b) => a.start - b.start);
    for (const it of pending) { it.fn(1); it.done = true; }
  }

  clear() {
    this.items.length = 0;
    this.t = 0;
  }
}

const SHRINK = 0.22;

export class Debris {
  constructor() {
    this.items = [];
  }

  launch(obj, vel, spin, { delay = 0, life = 1.0, gravity = 18, floorY = 0, radius = 0.1 } = {}) {
    this.items.push({
      obj, vx: vel[0], vy: vel[1], vz: vel[2], wx: spin[0], wy: spin[1], wz: spin[2],
      delay, life, gravity, floorY, radius, t: 0, s0: obj.scale.clone(), done: false,
    });
  }

  update(dt) {
    let busy = false;
    for (const d of this.items) {
      if (d.done) continue;
      busy = true;
      d.t += dt;
      if (d.t < d.delay) continue;
      const o = d.obj;
      d.vy -= d.gravity * dt;
      o.position.x += d.vx * dt;
      o.position.y += d.vy * dt;
      o.position.z += d.vz * dt;
      o.rotation.x += d.wx * dt;
      o.rotation.y += d.wy * dt;
      o.rotation.z += d.wz * dt;
      if (o.position.y < d.floorY + d.radius && d.vy < 0) {
        o.position.y = d.floorY + d.radius;
        d.vy *= -0.35;
        d.vx *= 0.6; d.vz *= 0.6;
        d.wx *= 0.5; d.wy *= 0.5; d.wz *= 0.5;
      }
      const age = d.t - d.delay;
      if (age > d.life) {
        const k = 1 - Math.min(1, (age - d.life) / SHRINK);
        o.scale.copy(d.s0).multiplyScalar(Math.max(1e-3, k));
        if (k <= 0) { o.visible = false; d.done = true; }
      }
    }
    return busy;
  }

  finish() {
    for (const d of this.items) {
      d.obj.visible = false;
      d.done = true;
    }
  }

  clear() {
    this.items.length = 0;
  }
}
