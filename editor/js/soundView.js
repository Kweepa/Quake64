import {
  SOUND_HZ_MIN,
  SOUND_HZ_MAX,
  SOUND_MAX_TICKS,
  SOUND_TICK_HZ,
  wolfByteToHz,
  hzToWolfByte,
  clampSoundVol,
  alignSoundArrays,
} from "./model.js";
import { decodeWav, mixMono, getAudioContext, pcmActiveLength } from "./pcsfx.js";

const PAD_L = 44;
const PAD_R = 12;
const PAD_T = 18;
const PAD_B = 4;
const GAP = 10;
const ORIG_H = 72;
const AXIS_H = 18;
const MIN_TICK_W = 6;
const AXIS_STEP_SEC = 0.5;

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

function yToHz(y, top, h) {
  const t = clamp(1 - (y - top) / h, 0, 1);
  return SOUND_HZ_MIN * Math.pow(SOUND_HZ_MAX / SOUND_HZ_MIN, t);
}

function hzToY(hz, top, h) {
  const z = clamp(hz, SOUND_HZ_MIN, SOUND_HZ_MAX);
  const t = Math.log(z / SOUND_HZ_MIN) / Math.log(SOUND_HZ_MAX / SOUND_HZ_MIN);
  return top + h * (1 - t);
}

export class SoundView {
  constructor(canvas, opts) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.opts = opts;
    this.enabled = false;
    this.scroll = 0;
    this.playTick = -1;
    this.selectedTick = 0;
    this.drag = null;
    this.cssW = 0;
    this.cssH = 0;
    this._pcm = null;
    this._pcmSr = 0;
    this._pcmLive = 0;
    this._pcmPath = null;
    this._pcmHadBuf = false;
    this._pcmGen = 0;
    this._ro = new ResizeObserver(() => this.resize());
    this._ro.observe(opts.stage || canvas.parentElement);
    this.resize();

    canvas.addEventListener("pointerdown", (e) => this.#onDown(e));
    canvas.addEventListener("pointermove", (e) => this.#onMove(e));
    canvas.addEventListener("pointerup", (e) => this.#onUp(e));
    canvas.addEventListener("pointerleave", (e) => this.#onUp(e));
    canvas.addEventListener("wheel", (e) => this.#onWheel(e), { passive: false });
    canvas.addEventListener("contextmenu", (e) => e.preventDefault());
  }

  resize() {
    if (!this.enabled) return;
    const stage = this.opts.stage || this.canvas.parentElement;
    const rect = stage.getBoundingClientRect();
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = Math.max(64, Math.floor(rect.width));
    const h = Math.max(64, Math.floor(rect.height));
    this.canvas.width = Math.floor(w * dpr);
    this.canvas.height = Math.floor(h * dpr);
    this.canvas.style.width = `${w}px`;
    this.canvas.style.height = `${h}px`;
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.cssW = w;
    this.cssH = h;
    this.draw();
  }

  setPlayTick(i) {
    this.playTick = i;
    if (this.enabled) this.draw();
  }

  draw() {
    if (!this.enabled) return;
    const ctx = this.ctx;
    const w = this.cssW;
    const h = this.cssH;
    ctx.fillStyle = "#0a0a0c";
    ctx.fillRect(0, 0, w, h);
    const snd = this.opts.getSound?.();
    if (!snd) {
      this.#label(ctx, "Select a sound", 16, 28);
      return;
    }
    alignSoundArrays(snd);
    this.#ensurePcm();
    const layout = this.#layout(snd);
    this.#drawOrig(ctx, snd, layout);
    this.#drawTimeAxis(ctx, layout, layout.orig.top + layout.orig.h);
    this.#drawVol(ctx, snd, layout);
    this.#drawTimeAxis(ctx, layout, layout.vol.top + layout.vol.h);
    this.#drawFreq(ctx, snd, layout);
    this.#drawTimeAxis(ctx, layout, layout.freq.top + layout.freq.h);
    if (!snd.freq.length) {
      this.#label(ctx, "Empty — Estimate from Quake or click to draw", 16, layout.freq.top + 22);
    }
  }

  #label(ctx, text, x, y) {
    ctx.fillStyle = "#8b91a0";
    ctx.font = "13px Segoe UI, sans-serif";
    ctx.fillText(text, x, y);
  }

  #layout(snd) {
    const w = this.cssW;
    const h = this.cssH;
    const innerW = Math.max(40, w - PAD_L - PAD_R);
    const rest = h - PAD_T - ORIG_H - AXIS_H * 3 - GAP * 2 - PAD_B;
    const freqH = Math.max(48, Math.floor(rest * 0.68));
    const volH = Math.max(28, rest - freqH);
    const n = Math.max(1, snd.freq.length, this.#wavTicks());
    const tickW = Math.max(MIN_TICK_W, Math.min(14, innerW / n));
    const vis = Math.max(1, Math.floor(innerW / tickW));
    const maxScroll = Math.max(0, n - vis);
    this.scroll = clamp(this.scroll, 0, maxScroll);
    const cols = Math.min(vis, Math.max(0, n - this.scroll));
    const origTop = PAD_T;
    const volTop = origTop + ORIG_H + AXIS_H + GAP;
    const freqTop = volTop + volH + AXIS_H + GAP;
    return {
      innerW,
      tickW,
      vis,
      cols,
      orig: { top: origTop, h: ORIG_H },
      vol: { top: volTop, h: volH },
      freq: { top: freqTop, h: freqH },
      n,
    };
  }

  #wavTicks() {
    if (!this._pcm || !(this._pcmSr > 0) || !(this._pcmLive > 0)) return 0;
    const hop = this._pcmSr / SOUND_TICK_HZ;
    return Math.min(SOUND_MAX_TICKS, Math.max(1, Math.ceil(this._pcmLive / hop)));
  }

  #ensurePcm() {
    const path = this.opts.getSoundPath?.() || "";
    const buf = path ? this.opts.getWavBuffer?.() : null;
    const hasBuf = !!buf;
    if (path === this._pcmPath && hasBuf === this._pcmHadBuf) return;
    this._pcmPath = path;
    this._pcmHadBuf = hasBuf;
    this._pcm = null;
    this._pcmSr = 0;
    this._pcmLive = 0;
    if (!buf) return;
    const gen = ++this._pcmGen;
    const ctx = getAudioContext();
    const start = () => {
      decodeWav(ctx, buf)
        .then((decoded) => {
          if (gen !== this._pcmGen) return;
          this._pcm = mixMono(decoded);
          this._pcmSr = decoded.sampleRate || 11025;
          this._pcmLive = pcmActiveLength(this._pcm);
          if (this.enabled) this.draw();
        })
        .catch(() => {
          if (gen !== this._pcmGen) return;
          this._pcm = null;
          this._pcmLive = 0;
        });
    };
    if (ctx.state === "suspended") ctx.resume().then(start, start);
    else start();
  }

  #tickAt(x, layout) {
    const col = Math.floor((x - PAD_L) / layout.tickW);
    if (col < 0) return -1;
    return this.scroll + col;
  }

  #localXY(e) {
    const r = this.canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  }

  #growTo(snd, tick) {
    if (tick < 0 || tick >= SOUND_MAX_TICKS) return false;
    alignSoundArrays(snd);
    while (snd.freq.length <= tick) {
      snd.freq.push(0);
      snd.vol.push(0);
    }
    return true;
  }

  #paint(e) {
    const snd = this.opts.ensureSound?.();
    if (!snd) return;
    const layout = this.#layout(snd);
    const { x, y } = this.#localXY(e);
    const tick = this.#tickAt(x, layout);
    if (tick < 0) return;
    if (!this.#growTo(snd, tick)) return;
    this.selectedTick = tick;
    if (this.drag === "freq") {
      const hz = yToHz(y, layout.freq.top, layout.freq.h);
      snd.freq[tick] = hzToWolfByte(hz);
      if (!snd.vol[tick]) snd.vol[tick] = 12;
    } else if (this.drag === "vol") {
      const t = clamp(1 - (y - layout.vol.top) / layout.vol.h, 0, 1);
      snd.vol[tick] = clampSoundVol(Math.round(t * 15));
      if (!snd.vol[tick]) snd.freq[tick] = 0;
    }
    snd.origin = "edit";
    this.opts.onChange?.();
    this.draw();
  }

  #onDown(e) {
    if (!this.enabled || e.button !== 0) return;
    const snd = this.opts.getSound?.();
    if (!snd) return;
    const layout = this.#layout(snd);
    const { y } = this.#localXY(e);
    if (y >= layout.orig.top && y <= layout.orig.top + layout.orig.h) {
      const tick = this.#tickAt(this.#localXY(e).x, layout);
      if (tick >= 0) {
        this.selectedTick = tick;
        this.draw();
        this.opts.onSelect?.();
      }
      return;
    }
    if (y >= layout.freq.top && y <= layout.freq.top + layout.freq.h) this.drag = "freq";
    else if (y >= layout.vol.top && y <= layout.vol.top + layout.vol.h) this.drag = "vol";
    else return;
    this.opts.beginUndo?.();
    this.canvas.setPointerCapture(e.pointerId);
    this.#paint(e);
  }

  #onMove(e) {
    if (!this.enabled) return;
    if (this.drag) this.#paint(e);
  }

  #onUp(e) {
    if (!this.enabled) return;
    if (this.drag) {
      this.drag = null;
      this.opts.endUndo?.();
      this.opts.onSelect?.();
    }
  }

  #onWheel(e) {
    if (!this.enabled) return;
    const snd = this.opts.getSound?.();
    if (!snd) return;
    if (!snd.freq.length && !this._pcm) return;
    e.preventDefault();
    const layout = this.#layout(snd);
    this.scroll = clamp(this.scroll + Math.sign(e.deltaY), 0, Math.max(0, layout.n - layout.vis));
    this.draw();
  }

  #drawTimeAxis(ctx, layout, y) {
    const { tickW, cols } = layout;
    const plotW = cols * tickW;
    ctx.strokeStyle = "#2e3340";
    ctx.beginPath();
    ctx.moveTo(PAD_L, y);
    ctx.lineTo(PAD_L + plotW, y);
    ctx.stroke();
    const t0 = this.scroll / SOUND_TICK_HZ;
    const t1 = (this.scroll + cols) / SOUND_TICK_HZ;
    let t = Math.ceil(t0 / AXIS_STEP_SEC - 1e-9) * AXIS_STEP_SEC;
    ctx.fillStyle = "#8b91a0";
    ctx.font = "10px Segoe UI, sans-serif";
    while (t <= t1 + 1e-9) {
      const x = PAD_L + (t * SOUND_TICK_HZ - this.scroll) * tickW;
      ctx.strokeStyle = "#2e3340";
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x, y + 4);
      ctx.stroke();
      const col = t * SOUND_TICK_HZ - this.scroll;
      ctx.textAlign = col <= 0.5 ? "left" : col >= cols - 0.5 ? "right" : "center";
      ctx.fillText(t.toFixed(1), x, y + 14);
      t += AXIS_STEP_SEC;
    }
    ctx.textAlign = "left";
  }

  #drawOrig(ctx, snd, layout) {
    const { tickW, cols, orig } = layout;
    const plotW = cols * tickW;
    ctx.fillStyle = "#12141a";
    ctx.fillRect(PAD_L, orig.top, plotW, orig.h);
    ctx.strokeStyle = "#2e3340";
    ctx.strokeRect(PAD_L, orig.top, plotW, orig.h);
    ctx.fillStyle = "#8b91a0";
    ctx.font = "10px Segoe UI, sans-serif";
    ctx.textAlign = "left";
    ctx.fillText("ORIG", 6, orig.top + 10);
    const mid = orig.top + orig.h / 2;
    ctx.strokeStyle = "#1c1f28";
    ctx.beginPath();
    ctx.moveTo(PAD_L, mid);
    ctx.lineTo(PAD_L + plotW, mid);
    ctx.stroke();
    for (let c = 0; c < cols; c++) {
      const i = this.scroll + c;
      const x = PAD_L + c * tickW;
      if (i === this.selectedTick) {
        ctx.fillStyle = "rgba(212,160,23,0.15)";
        ctx.fillRect(x, orig.top, tickW, orig.h);
      }
      if (this.playTick === i) {
        ctx.fillStyle = "rgba(212,160,23,0.35)";
        ctx.fillRect(x, orig.top, tickW, orig.h);
      }
    }
    if (!this._pcm || !(this._pcmSr > 0)) {
      ctx.fillStyle = "#8b91a0";
      ctx.font = "12px Segoe UI, sans-serif";
      ctx.fillText(this.opts.getWavBuffer?.() ? "Loading…" : "No original WAV", PAD_L + 8, mid + 4);
      return;
    }
    const hop = this._pcmSr / SOUND_TICK_HZ;
    const live = this._pcmLive || 0;
    const startSamp = Math.floor(this.scroll * hop);
    const endSamp = Math.max(startSamp + 1, Math.min(live, Math.floor((this.scroll + cols) * hop)));
    const sampSpan = endSamp - startSamp;
    const amp = orig.h / 2 - 3;
    ctx.fillStyle = "#7eb8d4";
    for (let px = 0; px < plotW; px++) {
      const s0 = startSamp + Math.floor((px * sampSpan) / plotW);
      const s1 = Math.max(s0 + 1, startSamp + Math.floor(((px + 1) * sampSpan) / plotW));
      let mn = 0;
      let mx = 0;
      for (let s = s0; s < s1 && s < live; s++) {
        const v = this._pcm[s];
        if (v < mn) mn = v;
        if (v > mx) mx = v;
      }
      const y0 = mid - mx * amp;
      const y1 = mid - mn * amp;
      ctx.fillRect(PAD_L + px, y0, 1, Math.max(1, y1 - y0));
    }
  }

  #drawFreq(ctx, snd, layout) {
    const { tickW, cols, freq } = layout;
    ctx.fillStyle = "#12141a";
    ctx.fillRect(PAD_L, freq.top, cols * tickW, freq.h);
    ctx.strokeStyle = "#2e3340";
    ctx.strokeRect(PAD_L, freq.top, cols * tickW, freq.h);
    const marks = [125, 250, 500, 1000, 2000, 4000];
    ctx.fillStyle = "#8b91a0";
    ctx.font = "10px Segoe UI, sans-serif";
    ctx.textAlign = "right";
    for (const hz of marks) {
      if (hz < SOUND_HZ_MIN || hz > SOUND_HZ_MAX) continue;
      const y = hzToY(hz, freq.top, freq.h);
      ctx.strokeStyle = "#1c1f28";
      ctx.beginPath();
      ctx.moveTo(PAD_L, y);
      ctx.lineTo(PAD_L + cols * tickW, y);
      ctx.stroke();
      ctx.fillStyle = "#8b91a0";
      ctx.fillText(hz >= 1000 ? `${hz / 1000}k` : String(hz), PAD_L - 4, y + 3);
    }
    ctx.textAlign = "left";
    ctx.fillText("FREQ", 6, freq.top + 10);
    for (let c = 0; c < cols; c++) {
      const i = this.scroll + c;
      if (i >= snd.freq.length) break;
      const hz = wolfByteToHz(snd.freq[i]);
      const x = PAD_L + c * tickW;
      if (i === this.selectedTick) {
        ctx.fillStyle = "rgba(212,160,23,0.15)";
        ctx.fillRect(x, freq.top, tickW, freq.h);
      }
      if (this.playTick === i) {
        ctx.fillStyle = "rgba(212,160,23,0.35)";
        ctx.fillRect(x, freq.top, tickW, freq.h);
      }
      if (hz > 0 && snd.vol[i]) {
        const y = hzToY(hz, freq.top, freq.h);
        ctx.fillStyle = "#d4a017";
        ctx.fillRect(x + 1, y, Math.max(1, tickW - 2), freq.top + freq.h - y);
      }
    }
  }

  #drawVol(ctx, snd, layout) {
    const { tickW, cols, vol } = layout;
    ctx.fillStyle = "#12141a";
    ctx.fillRect(PAD_L, vol.top, cols * tickW, vol.h);
    ctx.strokeStyle = "#2e3340";
    ctx.strokeRect(PAD_L, vol.top, cols * tickW, vol.h);
    ctx.fillStyle = "#8b91a0";
    ctx.font = "10px Segoe UI, sans-serif";
    ctx.textAlign = "left";
    ctx.fillText("VOL", 6, vol.top + 10);
    ctx.textAlign = "right";
    ctx.fillText("15", PAD_L - 4, vol.top + 8);
    ctx.fillText("0", PAD_L - 4, vol.top + vol.h - 2);
    ctx.textAlign = "left";
    for (let c = 0; c < cols; c++) {
      const i = this.scroll + c;
      if (i >= snd.vol.length) break;
      const x = PAD_L + c * tickW;
      if (i === this.selectedTick) {
        ctx.fillStyle = "rgba(212,160,23,0.15)";
        ctx.fillRect(x, vol.top, tickW, vol.h);
      }
      if (this.playTick === i) {
        ctx.fillStyle = "rgba(212,160,23,0.35)";
        ctx.fillRect(x, vol.top, tickW, vol.h);
      }
      const v = snd.vol[i] | 0;
      if (v > 0) {
        const bh = (v / 15) * vol.h;
        ctx.fillStyle = "#6a9";
        ctx.fillRect(x + 1, vol.top + vol.h - bh, Math.max(1, tickW - 2), bh);
      }
    }
  }
}
