// EventBus: tiny synchronous pub/sub used by every system (ARCHITECTURE §4 lists the canonical events).
// A throwing listener is isolated (logged, rate-limited) so one broken subscriber never breaks the emitter.

export class EventBus {
  constructor() {
    this._map = new Map();
    this._lastLog = new Map();
  }

  // Subscribe; returns an unsubscribe function.
  on(name, fn) {
    let list = this._map.get(name);
    if (!list) this._map.set(name, (list = []));
    list.push(fn);
    return () => this.off(name, fn);
  }

  // Subscribe for a single emission.
  once(name, fn) {
    const off = this.on(name, (p) => { off(); fn(p); });
    return off;
  }

  off(name, fn) {
    const list = this._map.get(name);
    if (!list) return;
    const i = list.indexOf(fn);
    if (i >= 0) list.splice(i, 1);
  }

  emit(name, payload) {
    const list = this._map.get(name);
    if (!list || list.length === 0) return;
    // Iterate over a snapshot: listeners may unsubscribe while being called.
    const snapshot = list.length === 1 ? list : list.slice();
    for (let i = 0; i < snapshot.length; i++) {
      try {
        snapshot[i](payload);
      } catch (err) {
        const now = performance.now();
        if (now - (this._lastLog.get(name) || -1e9) > 5000) {
          this._lastLog.set(name, now);
          console.error(`[event:${name}]`, err);
        }
      }
    }
  }

  clear() {
    this._map.clear();
  }
}
