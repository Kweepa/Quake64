const HANDLE_DB = "quake64-editor";
const HANDLE_STORE = "handles";
const HANDLE_KEY = "doc";
const SHAREWARE_KEY = "shareware";
const WEAPONS_PNG_KEY = "weapons-png";

export const DEFAULT_DOC_PATH = "quake64.json";

/** @type {FileSystemFileHandle | null} */
let docFileHandle = null;
/** @type {FileSystemDirectoryHandle | null} */
let sharewareDirHandle = null;
/** @type {FileSystemDirectoryHandle | null} */
let weaponsPngDirHandle = null;

export function docFileName() {
  return docFileHandle?.name || DEFAULT_DOC_PATH;
}

export function hasDocFileHandle() {
  return !!docFileHandle;
}

const EDITOR_SETTINGS_KEY = "quake64-editor-settings";

function isFlatEditorState(obj) {
  return !!obj && typeof obj === "object" && (obj.layoutCamera || obj.mode || obj.animOrbit);
}

export function loadEditorSettings(fileName) {
  try {
    const raw = localStorage.getItem(EDITOR_SETTINGS_KEY);
    if (!raw) return null;
    const all = JSON.parse(raw);
    if (!all || typeof all !== "object") return null;
    if (isFlatEditorState(all)) return all;
    const name = fileName || DEFAULT_DOC_PATH;
    return all[name] || null;
  } catch {
    return null;
  }
}

export function saveEditorSettings(fileName, state) {
  try {
    const name = fileName || DEFAULT_DOC_PATH;
    let all = {};
    try {
      all = JSON.parse(localStorage.getItem(EDITOR_SETTINGS_KEY) || "{}") || {};
    } catch {
      all = {};
    }
    if (isFlatEditorState(all)) all = { [name]: all };
    all[name] = state;
    localStorage.setItem(EDITOR_SETTINGS_KEY, JSON.stringify(all));
  } catch {
    /* private mode / quota */
  }
}

function openHandleDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(HANDLE_DB, 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(HANDLE_STORE)) {
        db.createObjectStore(HANDLE_STORE);
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function storeDocHandle(handle) {
  docFileHandle = handle;
  if (!window.indexedDB || !handle) return;
  const db = await openHandleDb();
  await new Promise((resolve, reject) => {
    const tx = db.transaction(HANDLE_STORE, "readwrite");
    tx.objectStore(HANDLE_STORE).put(handle, HANDLE_KEY);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
  db.close();
}

async function loadStoredDocHandle() {
  if (!window.indexedDB) return null;
  try {
    const db = await openHandleDb();
    const handle = await new Promise((resolve, reject) => {
      const tx = db.transaction(HANDLE_STORE, "readonly");
      const req = tx.objectStore(HANDLE_STORE).get(HANDLE_KEY);
      req.onsuccess = () => resolve(req.result || null);
      req.onerror = () => reject(req.error);
    });
    db.close();
    return handle || null;
  } catch {
    return null;
  }
}

async function queryPermission(handle, mode = "readwrite") {
  if (!handle?.queryPermission) return "granted";
  return handle.queryPermission({ mode });
}

async function ensurePermission(handle, mode = "readwrite") {
  if (!handle?.queryPermission || !handle?.requestPermission) return true;
  const opts = { mode };
  if ((await handle.queryPermission(opts)) === "granted") return true;
  return (await handle.requestPermission(opts)) === "granted";
}

function withoutEditor(doc) {
  if (!doc || typeof doc !== "object") return doc;
  const { editor: _editor, ...rest } = doc;
  return rest;
}

async function writeDocToHandle(handle, doc) {
  const text = JSON.stringify(withoutEditor(doc), null, 2);
  const writable = await handle.createWritable();
  await writable.write(text);
  await writable.close();
}

async function readDocFromHandle(handle) {
  const file = await handle.getFile();
  return JSON.parse(await file.text());
}

export async function getStoredDocHandle() {
  return loadStoredDocHandle();
}

export async function tryRestoreDocFile() {
  const handle = await loadStoredDocHandle();
  if (!handle) return null;
  const writeState = await queryPermission(handle, "readwrite");
  const readState = writeState === "granted" ? "granted" : await queryPermission(handle, "read");
  if (readState !== "granted") return null;
  docFileHandle = handle;
  return readDocFromHandle(handle);
}

export async function allowStoredDocFile(handle) {
  if (!handle) return null;
  if (!(await ensurePermission(handle, "readwrite"))) {
    if (!(await ensurePermission(handle, "read"))) return null;
  }
  await storeDocHandle(handle);
  return readDocFromHandle(handle);
}

export async function autosaveDocJSON(doc) {
  if (!docFileHandle) {
    throw new Error(`Load ${DEFAULT_DOC_PATH} once so autosave can write it`);
  }
  if (!(await ensurePermission(docFileHandle, "readwrite"))) {
    throw new Error(`No write permission for ${docFileHandle.name}`);
  }
  await writeDocToHandle(docFileHandle, doc);
  return "file";
}

const JSON_TYPE = {
  description: "Quake64 Editor",
  accept: { "application/json": [".json"] },
};

export async function saveDocJSON(doc, suggestedName = DEFAULT_DOC_PATH) {
  if (docFileHandle && (await ensurePermission(docFileHandle, "readwrite"))) {
    await writeDocToHandle(docFileHandle, doc);
    return "file";
  }

  if (window.showSaveFilePicker) {
    try {
      const handle = await window.showSaveFilePicker({
        suggestedName,
        types: [JSON_TYPE],
      });
      await storeDocHandle(handle);
      await writeDocToHandle(handle, doc);
      return "file";
    } catch (e) {
      if (e.name === "AbortError") return null;
    }
  }

  downloadJSON(doc, suggestedName);
  return "download";
}

export async function loadDocJSON() {
  if (window.showOpenFilePicker) {
    try {
      const [handle] = await window.showOpenFilePicker({
        types: [JSON_TYPE],
        multiple: false,
      });
      await storeDocHandle(handle);
      return readDocFromHandle(handle);
    } catch (e) {
      if (e.name === "AbortError") return null;
    }
  }
  return pickJsonFile();
}

function pickJsonFile() {
  return new Promise((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = "application/json,.json";
    input.addEventListener("change", () => {
      const file = input.files?.[0];
      if (!file) {
        resolve(null);
        return;
      }
      const reader = new FileReader();
      reader.onload = () => {
        try {
          resolve(JSON.parse(String(reader.result)));
        } catch {
          resolve(null);
        }
      };
      reader.onerror = () => resolve(null);
      reader.readAsText(file);
    });
    input.addEventListener("cancel", () => resolve(null));
    input.click();
  });
}

export function sharewareFolderName() {
  return sharewareDirHandle?.name || "";
}

export function hasSharewareDirHandle() {
  return !!sharewareDirHandle;
}

async function storeHandle(key, handle) {
  if (!window.indexedDB || !handle) return;
  const db = await openHandleDb();
  await new Promise((resolve, reject) => {
    const tx = db.transaction(HANDLE_STORE, "readwrite");
    tx.objectStore(HANDLE_STORE).put(handle, key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
  db.close();
}

async function loadStoredHandle(key) {
  if (!window.indexedDB) return null;
  try {
    const db = await openHandleDb();
    const handle = await new Promise((resolve, reject) => {
      const tx = db.transaction(HANDLE_STORE, "readonly");
      const req = tx.objectStore(HANDLE_STORE).get(key);
      req.onsuccess = () => resolve(req.result || null);
      req.onerror = () => reject(req.error);
    });
    db.close();
    return handle || null;
  } catch {
    return null;
  }
}

async function storeSharewareHandle(handle) {
  sharewareDirHandle = handle;
  await storeHandle(SHAREWARE_KEY, handle);
}

export async function getStoredSharewareHandle() {
  return loadStoredHandle(SHAREWARE_KEY);
}

export async function tryRestoreSharewareDir() {
  const handle = await loadStoredHandle(SHAREWARE_KEY);
  if (!handle) return null;
  const state = await queryPermission(handle, "read");
  if (state !== "granted") return null;
  sharewareDirHandle = handle;
  return handle;
}

export async function allowStoredSharewareDir(handle) {
  if (!handle) return null;
  if (!(await ensurePermission(handle, "read"))) return null;
  await storeSharewareHandle(handle);
  return handle;
}

export async function pickSharewareDirectory() {
  if (!window.showDirectoryPicker) {
    throw new Error("This browser cannot open a folder (needs Chromium file access)");
  }
  try {
    const handle = await window.showDirectoryPicker({
      id: "quake-shareware",
      mode: "read",
    });
    await storeSharewareHandle(handle);
    return handle;
  } catch (e) {
    if (e.name === "AbortError") return null;
    throw e;
  }
}

async function getFileInDir(dir, relPath) {
  const parts = relPath.split("/");
  let cur = dir;
  for (let i = 0; i < parts.length - 1; i++) {
    try {
      cur = await cur.getDirectoryHandle(parts[i]);
    } catch {
      return null;
    }
  }
  try {
    return await cur.getFileHandle(parts[parts.length - 1]);
  } catch {
    return null;
  }
}

/** Load pak0 then pak1 from the folder or an id1/ child. */
export async function loadSharewarePakBuffers(dirHandle) {
  const buffers = [];
  const seen = new Set();
  const candidates = ["pak0.pak", "id1/pak0.pak", "pak1.pak", "id1/pak1.pak"];
  for (const rel of candidates) {
    const fh = await getFileInDir(dirHandle, rel);
    if (!fh) continue;
    const file = await fh.getFile();
    const key = `${file.name}:${file.size}:${file.lastModified}`;
    if (seen.has(key)) continue;
    seen.add(key);
    buffers.push(await file.arrayBuffer());
  }
  return buffers;
}

export async function ensureWeaponsPngDirectory() {
  if (weaponsPngDirHandle && (await ensurePermission(weaponsPngDirHandle, "readwrite"))) {
    return weaponsPngDirHandle;
  }
  const stored = await loadStoredHandle(WEAPONS_PNG_KEY);
  if (stored && (await ensurePermission(stored, "readwrite"))) {
    weaponsPngDirHandle = stored;
    return stored;
  }
  return pickWeaponsPngDirectory();
}

export async function pickWeaponsPngDirectory() {
  if (!window.showDirectoryPicker) {
    throw new Error("This browser cannot open a folder (needs Chromium file access)");
  }
  try {
    const opts = { id: "quake-assets-weapons", mode: "readwrite" };
    const startIn = weaponsPngDirHandle || (await loadStoredHandle(WEAPONS_PNG_KEY));
    if (startIn) opts.startIn = startIn;
    const handle = await window.showDirectoryPicker(opts);
    weaponsPngDirHandle = handle;
    await storeHandle(WEAPONS_PNG_KEY, handle);
    return handle;
  } catch (e) {
    if (e.name === "AbortError") return null;
    throw e;
  }
}

export async function writePngFile(dirHandle, filename, blob) {
  const fh = await dirHandle.getFileHandle(filename, { create: true });
  const writable = await fh.createWritable();
  await writable.write(blob);
  await writable.close();
}

export function downloadJSON(doc, filename = DEFAULT_DOC_PATH) {
  const blob = new Blob([JSON.stringify(withoutEditor(doc), null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
