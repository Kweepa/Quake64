// Decode Wolf, Doom, Dave, and Keen PC sounds to Wolf inverse-freq bytes.
// Audition only. Cues do not store these bytes; the build reads ref/ via tools/pcsrc.py.

import { PC_TIMER } from "./model.js";
const DECIMATE = 3;
const TICK_HZ = 50;
const MAX_TICKS = 255;
const KEEN_PIT = 0x2000;

function decimate(data) {
  const samples = [];
  for (let i = 0; i < data.length; i += DECIMATE) {
    const group = data.slice(i, i + DECIMATE);
    samples.push(group.find((x) => x) || 0);
    if (samples.length > MAX_TICKS) throw new Error("decimated sound is longer than 255 ticks");
  }
  return samples;
}

function pitchHz(pitch) {
  if (pitch <= 0) return 0;
  return 175 * 2 ** ((pitch - 1) / 24);
}

function hzToWolf(hz) {
  if (hz <= 0) return 0;
  return Math.max(1, Math.min(255, Math.round(PC_TIMER / (hz * 60))));
}

function divisorToWolf(divisor) {
  if (divisor <= 0) return 0;
  return Math.max(1, Math.min(255, Math.round(divisor / 60)));
}

function resample(samples, pitDiv) {
  if (!samples.length) return [];
  const div = pitDiv > 0 ? pitDiv : 65536;
  const step = TICK_HZ * div;
  const out = [];
  let acc = 0;
  let bucket = [];
  let hold = 0;
  for (const sample of samples) {
    bucket.push(sample);
    acc += step;
    while (acc >= PC_TIMER && out.length < MAX_TICKS) {
      acc -= PC_TIMER;
      if (bucket.length) {
        hold = bucket.find((x) => x) || 0;
        bucket = [];
      }
      out.push(hold);
    }
    if (out.length >= MAX_TICKS) return out;
  }
  if (bucket.length && out.length < MAX_TICKS) out.push(bucket.find((x) => x) || 0);
  return out;
}

function u16(bytes, offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function u32(bytes, offset) {
  return (
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24)
  ) >>> 0;
}

export function loadWolf(hedBuffer, audBuffer, names) {
  const hed = new Uint8Array(hedBuffer);
  const aud = new Uint8Array(audBuffer);
  const offs = [];
  for (let i = 0; i + 4 <= hed.length; i += 4) offs.push(u32(hed, i));
  if (offs.length < names.length + 1) throw new Error("AUDIOHED is too short");
  const out = new Map();
  for (let i = 0; i < names.length; i++) {
    const start = offs[i];
    const length = u32(aud, start);
    const data = [];
    for (let j = 0; j < length; j++) data.push(aud[start + 6 + j]);
    out.set(names[i], decimate(data));
  }
  return out;
}

export function loadDoom(wadBuffer) {
  const blob = new Uint8Array(wadBuffer);
  const ident = String.fromCharCode(blob[0], blob[1], blob[2], blob[3]);
  if (ident !== "IWAD" && ident !== "PWAD") throw new Error("DOOM.WAD is not a WAD");
  const numlumps = u32(blob, 4);
  const dirofs = u32(blob, 8);
  const order = [];
  const lumps = new Map();
  for (let i = 0; i < numlumps; i++) {
    const o = dirofs + i * 16;
    const filepos = u32(blob, o);
    const size = u32(blob, o + 4);
    let name = "";
    for (let c = 0; c < 8; c++) {
      const ch = blob[o + 8 + c];
      if (!ch) break;
      name += String.fromCharCode(ch);
    }
    name = name.toUpperCase();
    if (!name.startsWith("DP") || lumps.has(name)) continue;
    order.push(name);
    lumps.set(name, blob.subarray(filepos, filepos + size));
  }
  const out = new Map();
  for (const name of order) {
    const buf = lumps.get(name);
    const length = buf[2] | (buf[3] << 8);
    const data = [];
    for (let j = 0; j < length; j++) data.push(buf[4 + j]);
    out.set(name, decimate(data).map((p) => hzToWolf(pitchHz(p))));
  }
  return out;
}

function unpackLz91(buffer) {
  const data = new Uint8Array(buffer);
  if (data[0x1c] !== 0x4c || data[0x1d] !== 0x5a || data[0x1e] !== 0x39 || data[0x1f] !== 0x31) {
    throw new Error("not an LZ91 executable");
  }
  const hdrsize = u16(data, 8);
  const initcs = u16(data, 0x16);
  const loader = initcs * 0x10 + hdrsize * 0x10;
  const indata = data.subarray(0x20, loader);
  const out = [];
  let si = 0;
  let dx = 0x10;
  let bp = u16(indata, si);
  si += 2;
  const getbit = () => {
    const bit = bp & 1;
    bp >>= 1;
    dx -= 1;
    if (dx === 0) {
      bp = u16(indata, si);
      si += 2;
      dx = 0x10;
    }
    return bit;
  };
  const copyFrom = (bx, count) => {
    for (let n = 0; n < count; n++) {
      const i = bx < 0 ? out.length + bx : bx;
      out.push(out[i]);
    }
  };
  while (true) {
    if (getbit()) {
      out.push(indata[si]);
      si += 1;
      continue;
    }
    if (getbit() === 0) {
      const cx = (getbit() << 1) + getbit() + 2;
      const bx = indata[si] - 0x100;
      si += 1;
      copyFrom(bx, cx);
      continue;
    }
    const ax = u16(indata, si);
    si += 2;
    const bx = (((ax >> 11) & 0xff) << 8) + (ax & 0xff) - 0x2000;
    const ah = (ax >> 8) & 7;
    if (ah) {
      copyFrom(bx, ah + 2);
      continue;
    }
    const al = indata[si];
    si += 1;
    if (al === 0) break;
    if (al !== 1) copyFrom(bx, al + 1);
  }
  return new Uint8Array(out);
}

function readWords(blob, offset) {
  const words = [];
  let p = offset;
  while (p + 1 < blob.length) {
    const word = u16(blob, p);
    p += 2;
    if (word === 0xffff) return words;
    words.push(word);
  }
  throw new Error("sound has no terminator");
}

function identOf(name) {
  return name.replace(/[^A-Za-z0-9]+/g, "").toUpperCase();
}

function parseBank(blob, base, mode, blankPrefix) {
  const sig = String.fromCharCode(blob[base], blob[base + 1], blob[base + 2], blob[base + 3]);
  if (sig !== "SPK\0" && sig !== "SND\0") throw new Error("sound bank is not SPK or SND");
  let count = u16(blob, base + 8);
  if (count === 0) count = (u16(blob, base + 16) >> 4) - 1;
  const used = new Set();
  let invented = 0;
  const out = new Map();
  for (let i = 0; i < count; i++) {
    const off = base + 16 * (i + 1);
    const doff = u16(blob, off);
    const rate = blob[off + 3];
    let raw = "";
    for (let c = 0; c < 12; c++) {
      const ch = blob[off + 4 + c];
      if (!ch) break;
      raw += String.fromCharCode(ch);
    }
    const ident0 = identOf(raw);
    if (ident0.includes("UNUSED") || ident0 === "UNNAMED") continue;
    let ident = ident0;
    if (!ident) {
      invented += 1;
      ident = `${blankPrefix}${String(invented).padStart(2, "0")}`;
    }
    const baseName = ident;
    let n = 2;
    while (used.has(ident)) {
      ident = `${baseName}${n}`;
      n += 1;
    }
    used.add(ident);
    const words = readWords(blob, base + doff);
    const pit = mode === "dave" ? (rate <= 1 ? 65536 : Math.floor(65536 / rate)) : KEEN_PIT;
    out.set(ident, resample(words.map(divisorToWolf), pit));
  }
  return out;
}

export function loadDave(exeBuffer) {
  const image = unpackLz91(exeBuffer);
  const sig = [0x53, 0x50, 0x4b, 0x00];
  let base = -1;
  for (let i = 0; i + 4 <= image.length; i++) {
    if (sig.every((b, k) => image[i + k] === b)) {
      base = i;
      break;
    }
  }
  if (base < 0) throw new Error("DAVE.EXE has no SPK sound bank");
  return parseBank(image, base, "dave", "DAVE");
}

export function loadKeen(buffer) {
  const blob = new Uint8Array(buffer);
  if (blob[0] !== 0x53 || blob[1] !== 0x4e || blob[2] !== 0x44) throw new Error("SOUNDS.CK1 is not an SND bank");
  return parseBank(blob, 0, "keen", "KEEN");
}
