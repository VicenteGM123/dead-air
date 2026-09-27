// Tiny worker pool for the baker: every worker loads the same character scene (tools/bake/worker.mjs).
import { Worker } from 'worker_threads';
import os from 'os';

export class Pool {
  constructor(workerData, n = Math.max(1, Math.min(8, os.cpus().length))) {
    this.n = n;
    this.queue = [];
    this.idle = [];
    this.pending = new Map();
    this.seq = 0;
    this.ready = Promise.all(Array.from({ length: n }, () => new Promise((res, rej) => {
      const w = new Worker(new URL('./worker.mjs', import.meta.url), { workerData });
      w.on('message', (m) => {
        if (m.ready) { this.idle.push(w); res(); this._pump(); return; }
        const p = this.pending.get(m.id);
        this.pending.delete(m.id);
        this.idle.push(w);
        if (m.error) p.rej(new Error(m.error)); else p.res(m.result);
        this._pump();
      });
      w.on('error', (e) => { rej(e); for (const p of this.pending.values()) p.rej(e); });
      this._workers = (this._workers || []).concat(w);
    })));
  }
  run(task, transfer = []) {
    return new Promise((res, rej) => { this.queue.push({ task, transfer, res, rej }); this._pump(); });
  }
  _pump() {
    while (this.idle.length && this.queue.length) {
      const w = this.idle.pop();
      const { task, transfer, res, rej } = this.queue.shift();
      const id = ++this.seq;
      this.pending.set(id, { res, rej });
      w.postMessage({ id, task }, transfer);
    }
  }
  async map(tasks) { return Promise.all(tasks.map((t) => this.run(t.task || t, t.transfer || []))); }
  close() { for (const w of this._workers || []) w.terminate(); }
}
