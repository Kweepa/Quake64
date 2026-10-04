import {
  SOUND_TICK_HZ,
  wolfByteToHz,
  alignSoundArrays,
} from "./model.js";

/** Last sample index + 1 with |s| above 8-bit LSB. Trailing digital silence dropped. */
export function pcmActiveLength(pcm) {
  if (!pcm || !pcm.length) return 0;
  const eps = 1 / 256;
  let end = pcm.length;
  while (end > 0 && Math.abs(pcm[end - 1]) <= eps) end--;
  return end;
}

export function mixMono(buffer) {
  const n = buffer.length;
  const chs = buffer.numberOfChannels;
  if (chs === 1) return buffer.getChannelData(0);
  const out = new Float32Array(n);
  for (let c = 0; c < chs; c++) {
    const data = buffer.getChannelData(c);
    for (let i = 0; i < n; i++) out[i] += data[i];
  }
  const inv = 1 / chs;
  for (let i = 0; i < n; i++) out[i] *= inv;
  return out;
}

export async function decodeWav(ctx, buffer) {
  const copy = buffer.slice(0);
  return ctx.decodeAudioData(copy);
}

let audioCtx = null;

export function getAudioContext() {
  if (!audioCtx) audioCtx = new AudioContext();
  return audioCtx;
}

export class SfxPreview {
  constructor() {
    this._nodes = [];
    this._tickTimer = 0;
    this.onTick = null;
    this.playing = false;
    this.kind = null;
  }

  stop() {
    if (this._tickTimer) {
      clearInterval(this._tickTimer);
      this._tickTimer = 0;
    }
    for (const n of this._nodes) {
      try {
        n.stop?.();
      } catch {
        /* already stopped */
      }
      try {
        n.disconnect?.();
      } catch {
        /* ok */
      }
    }
    this._nodes = [];
    this.playing = false;
    this.kind = null;
    this.onTick?.(-1);
  }

  async playOriginal(arrayBuffer, loop) {
    this.stop();
    const ctx = getAudioContext();
    if (ctx.state === "suspended") await ctx.resume();
    const decoded = await decodeWav(ctx, arrayBuffer);
    const src = ctx.createBufferSource();
    src.buffer = decoded;
    src.loop = !!loop;
    src.connect(ctx.destination);
    src.onended = () => {
      if (this.kind === "wav") this.stop();
    };
    src.start();
    this._nodes = [src];
    this.playing = true;
    this.kind = "wav";
  }

  async playSpeaker(snd, loop) {
    this.stop();
    const ctx = getAudioContext();
    if (ctx.state === "suspended") await ctx.resume();
    alignSoundArrays(snd);
    const n = snd.freq?.length || 0;
    if (!n) return;
    const tick = 1 / SOUND_TICK_HZ;
    const master = ctx.createGain();
    master.gain.value = 0.22;
    master.connect(ctx.destination);

    const osc = ctx.createOscillator();
    osc.type = "square";
    osc.frequency.value = 440;
    const gain = ctx.createGain();
    gain.gain.value = 0;
    osc.connect(gain);
    gain.connect(master);
    osc.start();
    this._nodes = [osc, gain, master];

    const start = ctx.currentTime + 0.02;
    const applyTick = (i, at) => {
      const f = snd.freq[i] | 0;
      const hz = wolfByteToHz(f);
      const amp = f ? 1 : 0;
      gain.gain.setValueAtTime(amp, at);
      osc.frequency.setValueAtTime(Math.max(hz, 1), at);
    };
    const scheduleOnce = (origin) => {
      for (let i = 0; i < n; i++) applyTick(i, origin + i * tick);
      gain.gain.setValueAtTime(0, origin + n * tick);
    };
    scheduleOnce(start);
    if (loop) {
      const period = n * tick;
      for (let r = 1; r < 32; r++) scheduleOnce(start + r * period);
    }

    let tickI = 0;
    this.onTick?.(0);
    this._tickTimer = setInterval(() => {
      tickI++;
      if (tickI >= n) {
        if (loop) {
          tickI = 0;
          this.onTick?.(0);
        } else {
          this.stop();
        }
        return;
      }
      this.onTick?.(tickI);
    }, 1000 / SOUND_TICK_HZ);

    this.playing = true;
    this.kind = "speaker";
    if (!loop) {
      const srcEnd = ctx.createBufferSource();
      srcEnd.buffer = ctx.createBuffer(1, 1, ctx.sampleRate);
      srcEnd.connect(ctx.createGain());
      srcEnd.onended = () => {
        if (this.kind === "speaker") this.stop();
      };
      srcEnd.start(start + n * tick + 0.02);
      this._nodes.push(srcEnd);
    }
  }
}

