// Update notice and `{{BINARY}} upgrade` for {{PRODUCT}} (from shipcrate). Node 18+, no dependencies.
//
// Privacy: at most once a day, one anonymous GET to GitHub's latest-release API. Nothing about the user or
// machine is sent; no telemetry. Off with {{ENV}}_NO_UPDATE_CHECK=1, and never in CI or without a terminal.
//
// Use:  const update = require("./update-check");
//       await update.notify(version);                       // after an interactive command
//       console.log(await update.upgrade(version, rollback)); // `{{BINARY}} upgrade [--rollback]`
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");

const REPO = "{{REPO}}";
const ASSET = "{{ASSET}}";
const BINARY = "{{BINARY}}";
const OPT_OUT = "{{ENV}}_NO_UPDATE_CHECK";
const DAY = 86400 * 1000;
const HEADERS = { "User-Agent": "{{TOKEN}}-update-check", Accept: "application/vnd.github+json" };

function checksAllowed() {
  return !process.env[OPT_OUT] && !process.env.CI && process.stderr.isTTY && process.stdout.isTTY;
}

function isNewer(a, b) {
  const parse = (s) => s.replace(/^v/, "").split("-")[0].split(".").map((p) => parseInt(p, 10) || 0);
  const x = parse(a), y = parse(b);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const p = x[i] || 0, q = y[i] || 0;
    if (p !== q) return p > q;
  }
  return false;
}

async function fetchLatest() {
  try {
    const r = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers: HEADERS, signal: AbortSignal.timeout(10000) });
    if (!r.ok) return null;
    const j = await r.json();
    return { version: j.tag_name.replace(/^v/, ""), page: `https://github.com/${REPO}/releases/tag/${j.tag_name}`,
      security: (j.body || "").toLowerCase().includes("[security]") };
  } catch { return null; }
}

const cacheFile = () => path.join(process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache"), "{{TOKEN}}", "update-check.json");
const exePath = () => fs.realpathSync(process.argv[1] || process.execPath);
const isHomebrew = () => /\/Cellar\/|\/homebrew\//.test(exePath());
const isNpm = () => /node_modules/.test(exePath());
const how = () => (isHomebrew() ? `brew upgrade ${BINARY}` : isNpm() ? `npm install -g ${BINARY}@latest` : `${BINARY} upgrade`);

async function notify(current) {
  if (!checksAllowed()) return;
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
  if (latest && isNewer(latest.version, current)) {
    process.stderr.write(latest.security
      ? `\n⚠️  SECURITY UPDATE: ${BINARY} ${latest.version} fixes a security issue (you have ${current}). Run \`${how()}\` · ${latest.page}\n`
      : `\n${BINARY} ${latest.version} is available (you have ${current}) · \`${how()}\` · what's new: ${latest.page}\n`);
  }
}

// For single-file installs (install.sh / release archive). npm and Homebrew installs are told what to run.
async function upgrade(current, rollback = false) {
  if (isHomebrew() || isNpm()) return `Installed with a package manager: run \`${how()}\`.`;
  const exe = exePath();
  const old = path.join(path.dirname(exe), `.${path.basename(exe)}.old`);
  if (rollback) {
    if (!fs.existsSync(old)) return "No previous version kept.";
    fs.renameSync(old, exe);
    return "Rolled back to the previous version.";
  }
  const latest = await fetchLatest();
  if (!latest) return "Couldn't reach GitHub.";
  if (!isNewer(latest.version, current)) return `${BINARY} ${current} is the latest version.`;
  const base = `https://github.com/${REPO}/releases/download/v${latest.version}`;
  const get = async (u) => { const r = await fetch(u, { headers: HEADERS }); if (!r.ok) throw new Error(`download failed: ${u}`); return Buffer.from(await r.arrayBuffer()); };
  const tmp = fs.mkdtempSync(path.join(path.dirname(exe), `.${BINARY}-upgrade-`));
  try {
    const archive = await get(`${base}/${ASSET}`);
    const expected = (await get(`${base}/${ASSET}.sha256`)).toString().split(/\s+/)[0].toLowerCase();
    if (expected.length !== 64 || crypto.createHash("sha256").update(archive).digest("hex") !== expected)
      return "Checksum mismatch: download rejected, nothing changed.";
    fs.writeFileSync(path.join(tmp, ASSET), archive);
    execFileSync("tar", ["-xzf", path.join(tmp, ASSET), "-C", tmp]);
    const staged = path.join(path.dirname(exe), `.${path.basename(exe)}.new`);
    fs.copyFileSync(path.join(tmp, BINARY), staged);
    fs.chmodSync(staged, 0o755);
    fs.copyFileSync(exe, old);   // keep the previous version for --rollback
    fs.renameSync(staged, exe);  // atomic on the same filesystem
    return `Upgraded ${BINARY} ${current} → ${latest.version}. Undo with \`${BINARY} upgrade --rollback\`.`;
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

module.exports = { checksAllowed, isNewer, fetchLatest, notify, upgrade };
