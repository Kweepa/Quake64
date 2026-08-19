const PAK_ENTRY = 64;
const PAK_NAME = 56;

/** Parse a Quake PACK buffer into a Map of lowercase path → ArrayBuffer. */
export function parsePak(buffer) {
  const view = new DataView(buffer);
  if (buffer.byteLength < 12) throw new Error("PAK too small");
  const magic = String.fromCharCode(
    view.getUint8(0),
    view.getUint8(1),
    view.getUint8(2),
    view.getUint8(3)
  );
  if (magic !== "PACK") throw new Error("Not a PACK file");
  const dirOfs = view.getInt32(4, true);
  const dirSize = view.getInt32(8, true);
  if (dirOfs < 0 || dirSize < 0 || dirOfs + dirSize > buffer.byteLength) {
    throw new Error("PAK directory out of range");
  }
  const n = (dirSize / PAK_ENTRY) | 0;
  const files = new Map();
  for (let i = 0; i < n; i++) {
    const off = dirOfs + i * PAK_ENTRY;
    let name = "";
    for (let j = 0; j < PAK_NAME; j++) {
      const c = view.getUint8(off + j);
      if (!c) break;
      name += String.fromCharCode(c);
    }
    const dataOfs = view.getInt32(off + PAK_NAME, true);
    const dataSize = view.getInt32(off + PAK_NAME + 4, true);
    if (dataOfs < 0 || dataSize < 0 || dataOfs + dataSize > buffer.byteLength) continue;
    const key = name.replace(/\\/g, "/").toLowerCase();
    files.set(key, buffer.slice(dataOfs, dataOfs + dataSize));
  }
  return files;
}

/** Later PAKs override earlier ones (pak0 then pak1). */
export function mergePaks(pakMaps) {
  const all = new Map();
  for (const m of pakMaps) {
    for (const [k, v] of m) all.set(k, v);
  }
  return all;
}

export function parsePakBuffers(buffers) {
  return mergePaks(buffers.map(parsePak));
}
