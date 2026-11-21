// Update notice and `hello-node upgrade` for hello-node (from shipcrate). Node 18+, no dependencies.
//
// Privacy: at most once a day, one anonymous GET of the release manifest (latest.json on GitHub Releases).
// Nothing about the user or machine is sent; no telemetry. Off with HELLO_NODE_NO_UPDATE_CHECK=1; never runs in CI
// or without a terminal.
//
// Use:  const update = require("./update-check");
//       await update.notify(version);                        // built-in one-line notice
//       const latest = await update.check(version);          // or feed your own notification system
//       console.log(await update.upgrade(version, rollback));  // `hello-node upgrade [--rollback]`
// Announcements (scripts/announce.sh) print once per message inside notify(); or read them with announcement().
// Beta channel: HELLO_NODE_CHANNEL=beta reads the beta manifest (pre-releases plus every stable release).
// Staged rollouts ("rollout": N) and pulled versions ("yanked") are handled for you.
// A mirror or your own update server: HELLO_NODE_UPDATE_MANIFEST=https://…/latest.json (same format).
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");
const { fileURLToPath } = require("node:url");

const REPO = "you/hello-node";
const BINARY = "hello-node";
const OPT_OUT = "HELLO_NODE_NO_UPDATE_CHECK";
const MANIFEST_ENV = "HELLO_NODE_UPDATE_MANIFEST";
const CHANNEL_ENV = "HELLO_NODE_CHANNEL";
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

// "http://127.0.0.1:8000/" for a loopback http URL (demos, local testing), else null. Never the network.
function loopbackOrigin(url) {
  const m = /^http:\/\/((127\.0\.0\.1|localhost|\[::1\])(:\d+)?)\//.exec(String(url));
  return m ? `http://${m[1]}/` : null;
}

// Where downloads may come from. The default manifest only allows this project's GitHub releases.
function policy(opts = {}) {
  const env = process.env[MANIFEST_ENV] || "";
  const custom = !opts.manifest && env.startsWith("https://");
  const local = !opts.manifest && !custom ? loopbackOrigin(env) : null;
  if (local) return { manifest: env, urlPrefix: local, allowFile: false, local };
  return {
    manifest: opts.manifest || (custom ? env : process.env[CHANNEL_ENV] === "beta"
      ? `https://github.com/${REPO}/releases/download/channel/beta.json`
      : `https://github.com/${REPO}/releases/latest/download/latest.json`),
    urlPrefix: opts.urlPrefix || (custom ? "https://" : `https://github.com/${REPO}/releases/download/`),
    allowFile: Boolean(opts.allowFile), // tests only
  };
}

async function get(url, p, timeout = 15000) {
  if (url.startsWith("file://") && p.allowFile) return fs.readFileSync(fileURLToPath(url));
  if (!url.startsWith("https://") && !(p.local && url.startsWith(p.local))) throw new Error(`refusing ${url}`);
  const r = await fetch(url, { headers: { "User-Agent": "hello-node-update-check" }, signal: AbortSignal.timeout(timeout) });
  if (!r.ok) throw new Error(`HTTP ${r.status} for ${url}`);
  return Buffer.from(await r.arrayBuffer());
}

// Strip control characters (terminal escape sequences) and cap length: messages come from the network.
const clean = (t, n) => String(t ?? "").replace(/[\n\t]/g, " ").replace(/[\u0000-\u001f\u007f-\u009f]/g, "").slice(0, n);

function parseAnnouncement(a) {
  if (!a || typeof a !== "object") return null;
  const url = String(a.url || "");
  const ann = { id: clean(a.id, 64), level: clean(a.level, 16), message: clean(a.message, 280),
    url: url.startsWith("https://") ? clean(url, 300) : "", below: clean(a.below, 32) };
  return ann.id && ann.message ? ann : null;
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
    security: j.security === true || notes.toLowerCase().includes("[security]"), asset, announcement: parseAnnouncement(j.announcement),
    yanked: (Array.isArray(j.yanked) ? j.yanked : []).filter((v) => typeof v === "string").map((v) => clean(v, 32).replace(/^v/, "")),
    rollout: typeof j.rollout === "number" ? Math.max(0, Math.min(100, Math.floor(j.rollout))) : (j.rollout_days > 0 ? 0 : 100),
    rollout_days: typeof j.rollout_days === "number" && j.rollout_days > 0 ? Math.min(365, Math.floor(j.rollout_days)) : 0,
    published: Number.isFinite(Date.parse(j.published)) ? Math.floor(Date.parse(j.published) / 1000) : 0 };
}

// The rollout percent right now: fixed, or growing linearly to 100% over rollout_days.
function effectiveRollout(l, at = Date.now() / 1000) {
  const start = l.rollout ?? 100;
  if (!l.rollout_days || !l.published) return start;
  const span = l.rollout_days * 86400, done = Math.min(Math.max(0, at - l.published), span);
  return Math.min(100, Math.floor(start + (100 - start) * done / span));
}

const isYanked = (l, current) => (l.yanked || []).includes(String(current).replace(/^v/, ""));

// Yanked → always (if there's somewhere to go); security → always; otherwise by rollout bucket.
function offeredTo(l, current, bucket) {
  if (isYanked(l, current)) return l.version !== String(current).replace(/^v/, "");
  return isNewer(l.version, current) && (l.security || bucket < effectiveRollout(l));
}

// This copy's bucket, 0-99: random once, kept locally, never sent anywhere.
function rolloutBucket() {
  const f = path.join(path.dirname(cacheFile()), "rollout-bucket");
  try { const b = parseInt(fs.readFileSync(f, "utf8"), 10); if (b >= 0 && b < 100) return b; } catch {}
  const b = crypto.randomInt(100);
  try { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, String(b)); } catch {}
  return b;
}

async function fetchLatest(p = policy()) {
  try { return parseManifest(await get(p.manifest, p), platformKey(), p); } catch { return null; }
}

const cacheFile = () => path.join(process.env.XDG_CACHE_HOME || process.env.LOCALAPPDATA || path.join(os.homedir(), ".cache"), "hello-node", "update-check.json");
const exePath = () => fs.realpathSync(process.argv[1] || process.execPath);
const isHomebrew = () => /\/Cellar\/|\/homebrew\/|\/linuxbrew\//.test(exePath());
const isNpm = () => /node_modules/.test(exePath());
const how = () => (isHomebrew() ? `brew upgrade ${BINARY}` : isNpm() ? `npm install -g ${BINARY}@latest` : `${BINARY} upgrade`);

// The manifest, fetched at most once a day. null when checks aren't allowed.
async function latestCached() {
  if (!checksAllowed()) return null;
  let cached = {};
  try { cached = JSON.parse(fs.readFileSync(cacheFile(), "utf8")); } catch {}
  if (Date.now() - (cached.checked || 0) < DAY) return cached.latest || null;
  const latest = await fetchLatest();
  try {
    fs.mkdirSync(path.dirname(cacheFile()), { recursive: true });
    fs.writeFileSync(cacheFile(), JSON.stringify({ checked: Date.now(), latest }));
  } catch {}
  return latest;
}

// Cached daily check for interactive use. Resolves to the newer release, or null.
async function check(current) {
  const l = await latestCached();
  return l && offeredTo(l, current, rolloutBucket()) ? l : null;
}

// The publisher's announcement if it applies to this version and wasn't shown yet; marks it shown.
async function announcement(current) {
  const a = (await latestCached())?.announcement;
  if (!a || (a.below && !isNewer(a.below, current))) return null;
  const seen = path.join(path.dirname(cacheFile()), "announcement-seen");
  try { if (fs.readFileSync(seen, "utf8").trim() === a.id) return null; } catch {}
  try { fs.writeFileSync(seen, a.id); } catch {}
  return a;
}

function announcementLine(a) {
  const tag = { security: "⚠️  SECURITY NOTICE", warning: "⚠️  NOTICE" }[a.level] || "ℹ️ ";
  return `${tag} ${BINARY}: ${a.message}` + (a.url ? ` · ${a.url}` : "");
}

function noticeLine(l, current) {
  if (isYanked(l, current)) return `⚠️  ${BINARY} ${current} was pulled by its publisher. Run \`${how()}\` to move to ${l.version} · ${l.page}`;
  return l.security
    ? `⚠️  SECURITY UPDATE: ${BINARY} ${l.version} fixes a security issue (you have ${current}). Run \`${how()}\` · ${l.page}`
    : `${BINARY} ${l.version} is available (you have ${current}) · \`${how()}\` · what's new: ${l.page}`;
}

async function notify(current) {
  const l = await check(current);
  if (l) process.stderr.write(`\n${noticeLine(l, current)}\n`);
  const a = await announcement(current);
  if (a) process.stderr.write(`${announcementLine(a)}\n`);
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
  // An explicit upgrade ignores staged rollout; a pulled (yanked) version may move back to an older good one.
  if (!isNewer(latest.version, current) && !(isYanked(latest, current) && latest.version !== String(current).replace(/^v/, "")))
    return `${BINARY} ${current} is the latest version.`;
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

module.exports = { effectiveRollout, loopbackOrigin, isYanked, offeredTo, rolloutBucket, clean, announcement, announcementLine, checksAllowed, isNewer, platformKey, policy, parseManifest, fetchLatest, check, noticeLine, notify, upgrade, upgradeAt };
