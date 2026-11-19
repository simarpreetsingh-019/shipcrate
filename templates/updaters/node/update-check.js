// Update notice and `{{BINARY}} upgrade` for {{PRODUCT}} (from shipcrate). Node 18+, no dependencies.
//
// Privacy: at most once a day, one anonymous GET of the release manifest (latest.json on GitHub Releases).
// Nothing about the user or machine is sent; no telemetry. Off with {{ENV}}_NO_UPDATE_CHECK=1; never runs in CI
// or without a terminal.
//
// Use:  const update = require("./update-check");
//       await update.notify(version);                        // built-in one-line notice
//       const latest = await update.check(version);          // or feed your own notification system
//       console.log(await update.upgrade(version, rollback));  // `{{BINARY}} upgrade [--rollback]`
// A mirror or your own update server: {{ENV}}_UPDATE_MANIFEST=https://…/latest.json (same format).
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");
const { fileURLToPath } = require("node:url");

const REPO = "{{REPO}}";
const BINARY = "{{BINARY}}";
const OPT_OUT = "{{ENV}}_NO_UPDATE_CHECK";
const MANIFEST_ENV = "{{ENV}}_UPDATE_MANIFEST";
const DAY = 86400 * 1000;

function checksAllowed() {
  return !process.env[OPT_OUT] && !process.env.CI && Boolean(process.stderr.isTTY && process.stdout.isTTY);
}

// 1.10.0 > 1.9.3; a leading v is ignored; 1.0.0 > 1.0.0-beta.
function isNewer(a, b) {
  const parse = (s) => { const [core, pre] = String(s).trim().replace(/^v/, "").split(/-(.*)/); return [core.split(".").map((p) => parseInt(p, 10) || 0), Boolean(pre)]; };
  const [x, xp] = parse(a), [y, yp] = parse(b);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const p = x[i] || 0, q = y[i] || 0;
    if (p !== q) return p > q;
  }
  return yp && !xp;
}

function platformKey() {
  const o = { darwin: "macos", win32: "windows", linux: "linux" }[process.platform] || process.platform;
  const a = { arm64: "arm64", x64: "x64" }[process.arch] || process.arch;
  return `${o}-${a}`;
}

// Where downloads may come from. The default manifest only allows this project's GitHub releases.
function policy(opts = {}) {
  const env = process.env[MANIFEST_ENV] || "";
  const custom = !opts.manifest && env.startsWith("https://");
  return {
    manifest: opts.manifest || (custom ? env : `https://github.com/${REPO}/releases/latest/download/latest.json`),
    urlPrefix: opts.urlPrefix || (custom ? "https://" : `https://github.com/${REPO}/releases/download/`),
    allowFile: Boolean(opts.allowFile), // tests only
  };
}

async function get(url, p, timeout = 15000) {
  if (url.startsWith("file://") && p.allowFile) return fs.readFileSync(fileURLToPath(url));
  if (!url.startsWith("https://")) throw new Error(`refusing ${url}`);
  const r = await fetch(url, { headers: { "User-Agent": "{{TOKEN}}-update-check" }, signal: AbortSignal.timeout(timeout) });
  if (!r.ok) throw new Error(`HTTP ${r.status} for ${url}`);
  return Buffer.from(await r.arrayBuffer());
}

function parseManifest(body, key, p) {
  const j = JSON.parse(body);
  let asset = null;
  for (const k of [key, key.split("-")[0], "any"]) {
    const a = (j.assets || {})[k];
    if (!a) continue;
    const sha = String(a.sha256 || "").toLowerCase();
    const okUrl = String(a.url || "").startsWith(p.urlPrefix) || (p.allowFile && String(a.url).startsWith("file://"));
    const okName = a.name && !/[\\/]/.test(a.name) && !a.name.startsWith("..");
    if (okUrl && /^[0-9a-f]{64}$/.test(sha) && okName) asset = { name: a.name, url: a.url, sha256: sha };
    break;
  }
  const notes = j.notes || "";
  return { version: String(j.version).replace(/^v/, ""), page: j.page || `https://github.com/${REPO}/releases`, notes,
    security: j.security === true || notes.toLowerCase().includes("[security]"), asset };
}

async function fetchLatest(p = policy()) {
  try { return parseManifest(await get(p.manifest, p), platformKey(), p); } catch { return null; }
}

const cacheFile = () => path.join(process.env.XDG_CACHE_HOME || process.env.LOCALAPPDATA || path.join(os.homedir(), ".cache"), "{{TOKEN}}", "update-check.json");
const exePath = () => fs.realpathSync(process.argv[1] || process.execPath);
const isHomebrew = () => /\/Cellar\/|\/homebrew\/|\/linuxbrew\//.test(exePath());
const isNpm = () => /node_modules/.test(exePath());
const how = () => (isHomebrew() ? `brew upgrade ${BINARY}` : isNpm() ? `npm install -g ${BINARY}@latest` : `${BINARY} upgrade`);

// Cached daily check for interactive use. Resolves to the newer release, or null.
async function check(current) {
  if (!checksAllowed()) return null;
  let cached = {};
  try { cached = JSON.parse(fs.readFileSync(cacheFile(), "utf8")); } catch {}
  let latest = cached.latest;
  if (Date.now() - (cached.checked || 0) >= DAY) {
    latest = await fetchLatest();
    try {
      fs.mkdirSync(path.dirname(cacheFile()), { recursive: true });
      fs.writeFileSync(cacheFile(), JSON.stringify({ checked: Date.now(), latest }));
    } catch {}
  }
  return latest && isNewer(latest.version, current) ? latest : null;
}

function noticeLine(l, current) {
  return l.security
    ? `⚠️  SECURITY UPDATE: ${BINARY} ${l.version} fixes a security issue (you have ${current}). Run \`${how()}\` · ${l.page}`
    : `${BINARY} ${l.version} is available (you have ${current}) · \`${how()}\` · what's new: ${l.page}`;
}

async function notify(current) {
  const l = await check(current);
  if (l) process.stderr.write(`\n${noticeLine(l, current)}\n`);
}

// For single-file installs (install.sh / release archive). npm and Homebrew installs are told what to run.
async function upgrade(current, rollback = false) {
  if (isHomebrew() || isNpm()) return `Installed with a package manager: run \`${how()}\`.`;
  return upgradeAt(exePath(), current, rollback, policy());
}

async function upgradeAt(exe, current, rollback, p) {
  const dir = path.dirname(exe), file = path.basename(exe);
  const old = path.join(dir, `.${file}.old`);
  if (rollback) {
    if (!fs.existsSync(old)) return "No previous version kept.";
    fs.renameSync(old, exe);
    return "Rolled back to the previous version.";
  }
  let latest;
  try { latest = parseManifest(await get(p.manifest, p), platformKey(), p); } catch { return "Couldn't read the release manifest."; }
  if (!isNewer(latest.version, current)) return `${BINARY} ${current} is the latest version.`;
  if (!latest.asset) return `Release ${latest.version} has no build for ${platformKey()}.`;
  const tmp = fs.mkdtempSync(path.join(dir, `.${BINARY}-upgrade-`));
  try {
    const data = await get(latest.asset.url, p, 120000);
    if (crypto.createHash("sha256").update(data).digest("hex") !== latest.asset.sha256)
      return "Checksum mismatch: download rejected, nothing changed.";
    const archive = path.join(tmp, latest.asset.name);
    fs.writeFileSync(archive, data);
    execFileSync("tar", ["-xf", archive, "-C", tmp]); // bsdtar on macOS/Windows also reads .zip
    const src = path.join(tmp, file);
    if (!fs.existsSync(src) || fs.lstatSync(src).isSymbolicLink()) return "Couldn't unpack the release.";
    const staged = path.join(dir, `.${file}.new`);
    fs.copyFileSync(src, staged);
    fs.chmodSync(staged, 0o755);
    fs.rmSync(old, { force: true });
    fs.renameSync(exe, old);   // keep the previous version for --rollback
    try { fs.renameSync(staged, exe); } catch { fs.renameSync(old, exe); return "Swap failed; nothing changed."; }
    return `Upgraded ${BINARY} ${current} → ${latest.version}. Undo with \`${BINARY} upgrade --rollback\`.`;
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

module.exports = { checksAllowed, isNewer, platformKey, policy, parseManifest, fetchLatest, check, noticeLine, notify, upgrade, upgradeAt };
