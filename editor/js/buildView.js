import { pickRepoDirectory, readRepoFile, repoFolderName, tryRestoreRepoDir } from "./io.js";

const REPORT_NAME = "build-report.json";
const VARIANT_ORDER = ["kernal", "krill"];
const VARIANT_LABEL = { kernal: "KERNAL", krill: "Krill" };

const panel = document.getElementById("build-panel");

/** @type {FileSystemDirectoryHandle | null} */
let dir = null;
/** @type {object | null} */
let report = null;
let missing = false;
let error = "";
let booted = false;

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

function hex(n) {
  return "$" + (Number(n) >>> 0).toString(16).toUpperCase().padStart(4, "0");
}

function variantKeys(data) {
  const variants = data?.variants;
  if (!variants || typeof variants !== "object") return [];
  return VARIANT_ORDER.filter((key) => variants[key] && typeof variants[key] === "object");
}

function variantLabel(key) {
  return VARIANT_LABEL[key] || key;
}

function gamesDiffer(data) {
  const keys = variantKeys(data);
  if (keys.length < 2) return false;
  const a = data.variants[keys[0]].game || {};
  const b = data.variants[keys[1]].game || {};
  return a.load !== b.load || a.end !== b.end || a.bytes !== b.bytes || a.heap !== b.heap;
}

function fieldDiffers(data, field) {
  const keys = variantKeys(data);
  if (keys.length < 2) return false;
  const a = data.variants[keys[0]].levels || {};
  const b = data.variants[keys[1]].levels || {};
  const names = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const name of names) {
    const av = a[name]?.[field] ?? null;
    const bv = b[name]?.[field] ?? null;
    if (JSON.stringify(av) !== JSON.stringify(bv)) return true;
  }
  return false;
}

function tightestOf(levels) {
  let best = null;
  for (const [name, lv] of Object.entries(levels || {})) {
    if (lv == null || !Number.isFinite(Number(lv.slack))) continue;
    if (!best || lv.slack < best.slack) best = { name, ...lv };
  }
  return best;
}

function tightestDiffer(data) {
  const keys = variantKeys(data);
  if (keys.length < 2) return false;
  const a = tightestOf(data.variants[keys[0]].levels);
  const b = tightestOf(data.variants[keys[1]].levels);
  if (!a || !b) return a !== b;
  return a.name !== b.name || a.slack !== b.slack;
}

function slackText(slack) {
  const n = Number(slack);
  if (!Number.isFinite(n)) return "";
  if (n <= 0) return `OVER ${-n}`;
  return String(n);
}

function worstText(lv) {
  if (!lv) return "";
  const types = (lv.worst_types || []).join(", ") || "-";
  const where = lv.where || (lv.worst_room >= 0 ? `room ${lv.worst_room}` : "no enemies");
  return `${where}: ${types}`;
}

function formatTime(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return String(iso);
  return d.toLocaleString();
}

function addCard(parent, kicker, value, danger) {
  const card = el("div", danger ? "build-card danger" : "build-card");
  card.append(el("div", "k", kicker));
  const body = el("div", "v");
  if (typeof value === "string") body.textContent = value;
  else body.append(value);
  card.append(body);
  parent.append(card);
  return card;
}

function gameValue(game) {
  const wrap = document.createDocumentFragment();
  wrap.append(document.createTextNode(`${hex(game.load)}–${hex(game.end)}`));
  wrap.append(el("div", "sub", `${game.bytes} bytes · heap ${game.heap}`));
  return wrap;
}

function tightValue(hit) {
  if (!hit) return "—";
  return `${hit.name} · ${hit.slack <= 0 ? slackText(hit.slack) : `slack ${hit.slack}`}`;
}

function addCards(parent, data) {
  const keys = variantKeys(data);
  const splitGame = gamesDiffer(data);
  const splitTight = tightestDiffer(data);
  for (const key of keys) {
    const game = data.variants[key].game;
    if (!game) continue;
    if (!splitGame && key !== keys[0]) continue;
    addCard(parent, splitGame ? `GAME ${variantLabel(key)}` : "GAME", gameValue(game), false);
  }
  for (const key of keys) {
    if (!splitTight && key !== keys[0]) continue;
    const hit = tightestOf(data.variants[key].levels);
    addCard(
      parent,
      splitTight ? `Tightest ${variantLabel(key)}` : "Tightest",
      tightValue(hit),
      !!hit && hit.slack <= 0
    );
  }
  const disks = data.disks && typeof data.disks === "object" ? data.disks : {};
  for (const name of Object.keys(disks)) {
    const disk = disks[name];
    if (!disk || disk.free == null) continue;
    addCard(parent, name, `${disk.free} blocks free`, Number(disk.free) <= 0);
  }
}

function fillWidth(bytes, scale) {
  return `${Math.min(100, (bytes / scale) * 100)}%`;
}

function singleBar(bytes, scale) {
  const track = el("span", "build-bar");
  const fill = el("span");
  fill.style.width = fillWidth(bytes, scale);
  track.append(fill);
  return track;
}

function stackedBar(parts, scale) {
  const track = el("span", "build-bar stack");
  for (const part of parts) {
    const bytes = Number(part.bytes) || 0;
    if (bytes <= 0) continue;
    const fill = el("span", part.cls);
    fill.style.width = fillWidth(bytes, scale);
    track.append(fill);
  }
  return track;
}

function pairText(base, other, krillOnly) {
  if (krillOnly) return `krill ${other}`;
  if (other == null || other === base) return String(base);
  return `${base} · krill ${other}`;
}

function moduleAddr(base, other, krillOnly) {
  if (krillOnly) return `${hex(other.start)}–${hex(other.end)}`;
  if (!other || (other.start === base.start && other.end === base.end)) {
    return `${hex(base.start)}–${hex(base.end)}`;
  }
  if (other.start === base.start) {
    return `${hex(base.start)}–${hex(base.end)} · krill ${hex(other.end)}`;
  }
  return `${hex(base.start)}–${hex(base.end)} · krill ${hex(other.start)}–${hex(other.end)}`;
}

function mergedByName(primary, secondary) {
  const byName = new Map((secondary || []).map((item) => [item.name, item]));
  const rows = [];
  const seen = new Set();
  for (const item of primary || []) {
    seen.add(item.name);
    rows.push({ name: item.name, base: item, other: byName.get(item.name) || null, krillOnly: false });
  }
  for (const item of secondary || []) {
    if (seen.has(item.name)) continue;
    rows.push({ name: item.name, base: null, other: item, krillOnly: true });
  }
  return rows;
}

function diskPair(disks) {
  const names = Object.keys(disks || {});
  const krillName = names.find((name) => name.includes("krill"));
  const baseName = names.find((name) => name !== krillName) || null;
  return {
    base: baseName ? disks[baseName] : null,
    krill: krillName ? disks[krillName] : null,
  };
}

function addModules(parent, data) {
  const keys = variantKeys(data);
  if (!keys.length) return;
  const primary = data.variants[keys[0]].modules || [];
  const secondary = keys[1] ? data.variants[keys[1]].modules || [] : [];
  const rows = mergedByName(primary, secondary);
  if (!rows.length) return;
  const scale = rows.reduce((n, row) => {
    const bytes = Number(row.base?.bytes ?? row.other?.bytes) || 0;
    return Math.max(n, bytes);
  }, 1);
  const section = el("section", "build-section");
  section.append(el("h2", null, "Modules"));
  const list = el("div", "build-mods");
  for (const row of rows) {
    const bytes = Number(row.base?.bytes ?? row.other?.bytes) || 0;
    const byteLabel = row.krillOnly
      ? `krill ${row.other.bytes}`
      : pairText(row.base.bytes, row.other ? row.other.bytes : null, false);
    const line = el("div", "build-mod");
    line.append(el("span", "name", row.name || ""));
    line.append(el("span", "addr", moduleAddr(row.base, row.other, row.krillOnly)));
    line.append(singleBar(bytes, scale));
    line.append(el("span", "bytes", byteLabel));
    list.append(line);
  }
  section.append(list);
  parent.append(section);
}

function levelRows(data) {
  const keys = variantKeys(data);
  const names = new Set();
  for (const key of keys) {
    for (const name of Object.keys(data.variants[key].levels || {})) names.add(name);
  }
  const rows = [...names].map((name) => {
    const cells = {};
    let slack = Infinity;
    for (const key of keys) {
      const lv = data.variants[key].levels?.[name] || null;
      cells[key] = lv;
      if (lv && Number.isFinite(Number(lv.slack))) slack = Math.min(slack, Number(lv.slack));
    }
    return { name, cells, slack };
  });
  rows.sort((a, b) => a.slack - b.slack || a.name.localeCompare(b.name));
  return rows;
}

function numCell(text, danger) {
  const td = el("td", danger ? "num danger" : "num", text);
  return td;
}

function addLevels(parent, data) {
  const keys = variantKeys(data);
  const rows = levelRows(data);
  if (!rows.length) return;
  const splitSlack = fieldDiffers(data, "slack");
  const splitNeed = fieldDiffers(data, "need");
  const section = el("section", "build-section");
  section.append(el("h2", null, "Levels"));
  const first = keys[0];
  const barScale = rows.reduce((n, row) => {
    const lv = row.cells[first];
    if (!lv) return n;
    return Math.max(n, (Number(lv.map_bytes) || 0) + (Number(lv.room_assets) || 0));
  }, 1);
  const table = el("table", "build-table");
  const head = el("tr");
  head.append(el("th", null, "Level"));
  head.append(el("th", "bar-cell", ""));
  head.append(el("th", "num", "Map"));
  head.append(el("th", null, "Worst"));
  head.append(el("th", "num", "Assets"));
  if (splitNeed) {
    for (const key of keys) head.append(el("th", "num", `Need ${variantLabel(key)}`));
  } else {
    head.append(el("th", "num", "Need"));
  }
  if (splitSlack) {
    for (const key of keys) head.append(el("th", "num", variantLabel(key)));
  } else {
    head.append(el("th", "num", "Slack"));
  }
  const thead = el("thead");
  thead.append(head);
  table.append(thead);
  const body = el("tbody");
  for (const row of rows) {
    const base = row.cells[first];
    const tr = el("tr");
    tr.append(el("td", null, row.name));
    const barCell = el("td", "bar-cell");
    if (base) {
      barCell.append(
        stackedBar(
          [
            { cls: "seg-map", bytes: base.map_bytes },
            { cls: "seg-assets", bytes: base.room_assets },
          ],
          barScale
        )
      );
    }
    tr.append(barCell);
    tr.append(numCell(base ? String(base.map_bytes) : ""));
    tr.append(el("td", null, worstText(base)));
    tr.append(numCell(base ? String(base.room_assets) : ""));
    if (splitNeed) {
      for (const key of keys) {
        const lv = row.cells[key];
        tr.append(numCell(lv ? String(lv.need) : ""));
      }
    } else {
      tr.append(numCell(base ? String(base.need) : ""));
    }
    if (splitSlack) {
      for (const key of keys) {
        const lv = row.cells[key];
        const slack = lv ? Number(lv.slack) : NaN;
        tr.append(numCell(lv ? slackText(slack) : "", Number.isFinite(slack) && slack <= 0));
      }
    } else {
      const slack = base ? Number(base.slack) : NaN;
      tr.append(numCell(base ? slackText(slack) : "", Number.isFinite(slack) && slack <= 0));
    }
    body.append(tr);
  }
  table.append(body);
  section.append(table);
  parent.append(section);
}

function addAdvanced(parent, data) {
  const kernal = data?.variants?.kernal;
  if (!kernal || typeof kernal !== "object") return;
  const modules = Array.isArray(kernal.modules) ? kernal.modules : [];
  const section = el("section", "build-section build-advanced");
  section.append(el("h2", null, "Advanced"));
  section.append(el("p", "build-empty", "KERNAL build, by size."));
  const hasSymbols = modules.some((mod) => Array.isArray(mod.symbols));
  if (!modules.length || !hasSymbols) {
    section.append(el("p", "build-empty", "Rebuild to list KERNAL symbols."));
    parent.append(section);
    return;
  }
  const ranked = modules
    .map((mod) => ({
      name: mod.name || "",
      bytes: Number(mod.bytes) || 0,
      symbols: Array.isArray(mod.symbols) ? mod.symbols : [],
    }))
    .sort((a, b) => b.bytes - a.bytes || a.name.localeCompare(b.name));
  const scale = ranked.reduce((n, mod) => Math.max(n, mod.bytes), 1);
  const list = el("div", "build-tree");
  for (const mod of ranked) {
    const block = el("details", "build-mod-block");
    const summary = el("summary");
    summary.append(el("span", "chev"));
    summary.append(el("span", "name", mod.name));
    summary.append(singleBar(mod.bytes, scale));
    summary.append(el("span", "bytes", String(mod.bytes)));
    block.append(summary);
    const syms = mod.symbols
      .map((sym) => ({
        name: sym.name || "",
        bytes: Number(sym.bytes) || 0,
      }))
      .sort((a, b) => b.bytes - a.bytes || a.name.localeCompare(b.name));
    const body = el("div", "build-syms");
    for (const sym of syms) {
      const line = el("div", "build-sym");
      line.append(el("span", "name", sym.name));
      line.append(singleBar(sym.bytes, mod.bytes || 1));
      line.append(el("span", "bytes", String(sym.bytes)));
      body.append(line);
    }
    block.append(body);
    list.append(block);
  }
  section.append(list);
  parent.append(section);
}

function addBanks(parent, data) {
  const banks = Array.isArray(data.banks) ? data.banks : [];
  if (!banks.length) return;
  const section = el("section", "build-section");
  section.append(el("h2", null, "AI banks"));
  const table = el("table", "build-table");
  const head = el("tr");
  head.append(el("th", null, "Name"));
  head.append(el("th", "bar-cell", ""));
  for (const label of ["Bank", "Code", "Pose", "Reloc", "Map"]) head.append(el("th", "num", label));
  const thead = el("thead");
  thead.append(head);
  table.append(thead);
  const body = el("tbody");
  for (const bank of banks) {
    const size = Number(bank.bank) || 0;
    const max = Number(bank.max) || 1;
    const over = size > max;
    const tr = el("tr");
    tr.append(el("td", null, bank.name || ""));
    const barCell = el("td", "bar-cell");
    barCell.append(
      stackedBar(
        [
          { cls: "seg-code", bytes: bank.code },
          { cls: "seg-pose", bytes: bank.pose },
          { cls: "seg-reloc", bytes: (Number(bank.reloc) || 0) * 2 },
          { cls: "seg-sites", bytes: (Number(bank.map) || 0) * 2 },
        ],
        max
      )
    );
    tr.append(barCell);
    tr.append(numCell(`${size} / ${max}`, over));
    tr.append(numCell(String(bank.code ?? "")));
    tr.append(numCell(String(bank.pose ?? "")));
    tr.append(numCell(String(bank.reloc ?? "")));
    tr.append(numCell(String(bank.map ?? "")));
    body.append(tr);
  }
  table.append(body);
  section.append(table);
  parent.append(section);
}

function freeLabel(base, krill) {
  if (base?.free == null && krill?.free == null) return "";
  if (base?.free == null) return `${krill.free} free`;
  if (krill?.free == null || krill.free === base.free) return `${base.free} free`;
  return `${base.free} free · krill ${krill.free}`;
}

function addDisks(parent, data) {
  const disks = data.disks && typeof data.disks === "object" ? data.disks : null;
  if (!disks || !Object.keys(disks).length) return;
  const { base, krill } = diskPair(disks);
  const rows = mergedByName(base?.files, krill?.files);
  if (!rows.length && base?.free == null && krill?.free == null) return;
  const scale = rows.reduce((n, row) => {
    const a = Number(row.base?.blocks) || 0;
    const b = Number(row.other?.blocks) || 0;
    return Math.max(n, a, b);
  }, 1);
  const section = el("section", "build-section");
  const free = freeLabel(base, krill);
  section.append(el("h2", null, free ? `Disk · ${free}` : "Disk"));
  const list = el("div", "build-mods");
  for (const row of rows) {
    const blocks = Math.max(Number(row.base?.blocks) || 0, Number(row.other?.blocks) || 0);
    const label = row.krillOnly
      ? `krill ${row.other.blocks}`
      : pairText(row.base.blocks, row.other ? row.other.blocks : null, false);
    const line = el("div", "build-mod short");
    line.append(el("span", "name", row.name || ""));
    line.append(singleBar(blocks, scale));
    line.append(el("span", "bytes", label));
    list.append(line);
  }
  section.append(list);
  parent.append(section);
}

function render() {
  if (!panel) return;
  panel.replaceChildren();
  const bar = el("div", "build-toolbar");
  const open = el("button", null, "Open repo");
  open.type = "button";
  open.id = "btn-build-open";
  const reloadBtn = el("button", null, "Reload");
  reloadBtn.type = "button";
  reloadBtn.id = "btn-build-reload";
  bar.append(open, reloadBtn);
  const meta = [];
  const folder = repoFolderName();
  if (folder) meta.push(folder);
  if (report?.time) meta.push(formatTime(report.time));
  if (meta.length) bar.append(el("span", "build-meta", meta.join(" · ")));
  panel.append(bar);

  if (!dir) {
    panel.append(el("p", "build-empty", "Open the repo folder to read build-report.json."));
    return;
  }
  if (error) {
    panel.append(el("p", "build-fail", error));
    return;
  }
  if (missing || !report) {
    panel.append(
      el(
        "p",
        "build-empty",
        `No ${REPORT_NAME} in ${folder || "the repo"}. Run the build, then reload.`
      )
    );
    return;
  }
  if (report.ok === false) {
    const step = report.step ? ` during ${report.step}` : "";
    panel.append(el("p", "build-fail", `Build failed${step}`));
  }
  const keys = variantKeys(report);
  const hasDisks = report.disks && Object.keys(report.disks).length;
  const hasBanks = Array.isArray(report.banks) && report.banks.length;
  if (!keys.length && !hasDisks && !hasBanks) {
    panel.append(el("p", "build-empty", "No completed build in this report."));
    return;
  }
  const cards = el("div", "build-cards");
  addCards(cards, report);
  if (cards.childElementCount) panel.append(cards);
  const split = el("div", "build-cols");
  addModules(split, report);
  addDisks(split, report);
  if (split.childElementCount) panel.append(split);
  addLevels(panel, report);
  addBanks(panel, report);
  addAdvanced(panel, report);
}

async function reload() {
  if (!dir) {
    report = null;
    missing = false;
    error = "";
    render();
    return;
  }
  try {
    const text = await readRepoFile(dir, REPORT_NAME);
    if (text == null) {
      report = null;
      missing = true;
      error = "";
    } else {
      report = JSON.parse(text);
      missing = false;
      error = "";
    }
  } catch (e) {
    report = null;
    missing = false;
    error = e.message || String(e);
  }
  render();
}

async function openRepo() {
  try {
    const handle = await pickRepoDirectory();
    if (!handle) return;
    dir = handle;
    await reload();
  } catch (e) {
    error = e.message || String(e);
    report = null;
    missing = false;
    render();
  }
}

if (panel) {
  panel.addEventListener("click", (e) => {
    const id = e.target?.id;
    if (id === "btn-build-open") void openRepo();
    else if (id === "btn-build-reload") void reload();
  });
}

export function showBuildView() {
  if (!booted) {
    booted = true;
    void (async () => {
      try {
        dir = await tryRestoreRepoDir();
      } catch {
        dir = null;
      }
      if (dir) await reload();
      else render();
    })();
    return;
  }
  render();
}
