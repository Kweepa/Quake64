import { fft } from "./fft.js";
import {
  SOUND_MAX_TICKS,
  SOUND_TICK_HZ,
  SOUND_HZ_MIN,
  wolfByteToHz,
  hzToWolfByte,
  clampSoundVol,
  clampSoundFreqByte,
  alignSoundArrays,
} from "./model.js";

const FFT_SIZE = 512;
const FLATNESS_NOISE = 0.42;
const RMS_SILENCE = 0.04;
const ESTIMATE_HZ_MAX = 2000;
const NOISE_CENTROID_HZ_MAX = 800;
const PEAK_REL_DB = 12;

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

function hann(i, n) {
  return 0.5 * (1 - Math.cos((2 * Math.PI * i) / (n - 1)));
}

function spectralFlatness(mag, lo, hi) {
  let logSum = 0;
  let sum = 0;
  let n = 0;
  for (let i = lo; i < hi; i++) {
    const m = mag[i];
    if (m <= 1e-12) continue;
    logSum += Math.log(m);
    sum += m;
    n++;
  }
  if (n < 4 || sum <= 0) return 1;
  const geo = Math.exp(logSum / n);
  return geo / (sum / n);
}

function binRange(sr, fftSize, hzLo, hzHi) {
  const nyq = (fftSize >> 1) - 1;
  const lo = Math.max(1, Math.round((hzLo * fftSize) / sr));
  const hi = Math.min(nyq, Math.round((hzHi * fftSize) / sr));
  if (hi <= lo) return [1, Math.min(nyq, lo + 1)];
  return [lo, hi];
}

function interpPeakHz(mag, bin, sr, fftSize) {
  const prev = mag[bin - 1] || 0;
  const next = mag[bin + 1] || 0;
  const mid = mag[bin];
  const denom = prev - 2 * mid + next;
  const delta = denom !== 0 ? (0.5 * (prev - next)) / denom : 0;
  return ((bin + delta) * sr) / fftSize;
}

function peakHz(mag, sr, fftSize, lo, hi) {
  let maxM = 0;
  for (let i = lo; i < hi; i++) {
    if (mag[i] > maxM) maxM = mag[i];
  }
  if (maxM <= 0) return 0;
  const thresh = maxM * Math.pow(10, -PEAK_REL_DB / 20);
  let best = -1;
  for (let i = lo; i < hi; i++) {
    if (mag[i] < thresh) continue;
    const prev = i > lo ? mag[i - 1] : 0;
    const next = i + 1 < hi ? mag[i + 1] : 0;
    if (mag[i] >= prev && mag[i] >= next) {
      best = i;
      break;
    }
  }
  if (best < 0) {
    for (let i = lo; i < hi; i++) {
      if (mag[i] >= maxM) {
        best = i;
        break;
      }
    }
  }
  return interpPeakHz(mag, best, sr, fftSize);
}

function centroidHz(mag, sr, fftSize, lo, hi) {
  let num = 0;
  let den = 0;
  for (let i = lo; i < hi; i++) {
    num += i * mag[i];
    den += mag[i];
  }
  if (den <= 0) return 0;
  return ((num / den) * sr) / fftSize;
}

const SID_ATTACK_MS = [2, 8, 16, 24, 38, 56, 68, 80, 100];

function estimateAttack(frames, maxRms) {
  if (maxRms <= 0) return 0;
  let t10 = -1;
  let t90 = -1;
  for (let i = 0; i < frames.length; i++) {
    if (t10 < 0 && frames[i].rms >= maxRms * 0.1) t10 = i;
    if (t90 < 0 && frames[i].rms >= maxRms * 0.9) t90 = i;
  }
  if (t10 < 0 || t90 < 0 || t90 <= t10) return 0;
  const ms = (t90 - t10) * (1000 / SOUND_TICK_HZ);
  let best = 0;
  for (let i = 0; i < SID_ATTACK_MS.length; i++) {
    if (SID_ATTACK_MS[i] <= ms) best = i;
  }
  return best;
}

function clampEstimateHz(hz) {
  if (!(hz > 0)) return 0;
  if (hz < SOUND_HZ_MIN) return SOUND_HZ_MIN;
  if (hz > ESTIMATE_HZ_MAX) return ESTIMATE_HZ_MAX;
  return hz;
}

/** 50 Hz STFT frames for Estimate. `pcm` is Float32 mono. */
export function analyzePcmTicks(pcm, sampleRate) {
  const sr = sampleRate || 11025;
  const hop = sr / SOUND_TICK_HZ;
  const live = pcmActiveLength(pcm);
  if (live <= 0) {
    const [lo0, hi0] = binRange(sr, FFT_SIZE, SOUND_HZ_MIN, ESTIMATE_HZ_MAX);
    return { frames: [], maxRms: 0, sr, lo: lo0, hi: hi0 };
  }
  const nTicks = Math.min(SOUND_MAX_TICKS, Math.max(1, Math.ceil(live / hop)));
  const frames = [];
  let maxRms = 0;
  for (let t = 0; t < nTicks; t++) {
    const start = Math.floor(t * hop);
    const re = new Float64Array(FFT_SIZE);
    const im = new Float64Array(FFT_SIZE);
    let sumSq = 0;
    const win = Math.min(FFT_SIZE, Math.max(8, Math.round(hop)));
    for (let i = 0; i < win; i++) {
      const src = start + i;
      const s = src < live ? pcm[src] * hann(i, win) : 0;
      re[i] = s;
      sumSq += s * s;
    }
    fft(re, im);
    const mag = new Float64Array(FFT_SIZE >> 1);
    for (let i = 0; i < mag.length; i++) mag[i] = Math.hypot(re[i], im[i]);
    const rms = Math.sqrt(sumSq / win);
    if (rms > maxRms) maxRms = rms;
    frames.push({ mag, rms });
  }
  const [lo, hi] = binRange(sr, FFT_SIZE, SOUND_HZ_MIN, ESTIMATE_HZ_MAX);
  return { frames, maxRms, sr, lo, hi };
}

/** 50 Hz FFT first pass. `pcm` is Float32 mono. */
export function estimateFromPcm(pcm, sampleRate) {
  const { frames, maxRms, sr, lo, hi } = analyzePcmTicks(pcm, sampleRate);
  const [nLo, nHi] = binRange(sr, FFT_SIZE, SOUND_HZ_MIN, NOISE_CENTROID_HZ_MAX);
  const freq = [];
  const vol = [];
  const floor = maxRms * RMS_SILENCE;
  for (const fr of frames) {
    if (fr.rms <= floor || maxRms <= 0) {
      freq.push(0);
      vol.push(0);
      continue;
    }
    const v = clampSoundVol(Math.max(1, Math.round((fr.rms / maxRms) * 15)));
    const flat = spectralFlatness(fr.mag, lo, hi);
    const rawHz =
      flat >= FLATNESS_NOISE
        ? centroidHz(fr.mag, sr, FFT_SIZE, nLo, nHi)
        : peakHz(fr.mag, sr, FFT_SIZE, lo, hi);
    const hz = clampEstimateHz(rawHz);
    freq.push(hzToWolfByte(hz));
    vol.push(v);
  }
  return { freq, vol, attack: estimateAttack(frames, maxRms), origin: "estimate" };
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
    const n = snd.freq.length;
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
      const v = snd.vol[i] | 0;
      const hz = wolfByteToHz(f);
      const amp = f && v ? v / 15 : 0;
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

export function reverseSound(snd) {
  alignSoundArrays(snd);
  snd.freq.reverse();
  snd.vol.reverse();
  snd.origin = "edit";
}

export function transposeSound(snd, delta) {
  alignSoundArrays(snd);
  const d = delta | 0;
  for (let i = 0; i < snd.freq.length; i++) {
    if (!snd.freq[i]) continue;
    snd.freq[i] = clampSoundFreqByte(Math.max(1, snd.freq[i] + d));
  }
  snd.origin = "edit";
}

export function fadeSound(snd, mode) {
  alignSoundArrays(snd);
  const n = snd.vol.length;
  if (n < 2) return;
  for (let i = 0; i < n; i++) {
    const t = mode === "out" ? 1 - i / (n - 1) : i / (n - 1);
    snd.vol[i] = clampSoundVol(Math.round(snd.vol[i] * t));
  }
  snd.origin = "edit";
}

export function insertSoundTick(snd, at) {
  alignSoundArrays(snd);
  if (snd.freq.length >= SOUND_MAX_TICKS) return false;
  const i = Math.max(0, Math.min(snd.freq.length, at | 0));
  const f = snd.freq[i] ?? snd.freq[i - 1] ?? 0;
  const v = snd.vol[i] ?? snd.vol[i - 1] ?? 0;
  snd.freq.splice(i, 0, f);
  snd.vol.splice(i, 0, v);
  snd.origin = "edit";
  return true;
}

export function deleteSoundTick(snd, at) {
  alignSoundArrays(snd);
  if (!snd.freq.length) return false;
  const i = Math.max(0, Math.min(snd.freq.length - 1, at | 0));
  snd.freq.splice(i, 1);
  snd.vol.splice(i, 1);
  snd.origin = "edit";
  return true;
}
