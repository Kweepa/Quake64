const HANDLE_DB = "quake64-editor";
const HANDLE_STORE = "handles";
const HANDLE_KEY = "doc";

export const DEFAULT_DOC_PATH = "quake64.json";

/** @type {FileSystemFileHandle | null} */
let docFileHandle = null;

export function docFileName() {
  return docFileHandle?.name || DEFAULT_DOC_PATH;
}

export function hasDocFileHandle() {
  return !!docFileHandle;
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

async function writeDocToHandle(handle, doc) {
  const text = JSON.stringify(doc, null, 2);
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

export function downloadJSON(doc, filename = DEFAULT_DOC_PATH) {
  const blob = new Blob([JSON.stringify(doc, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
