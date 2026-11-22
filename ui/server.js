#!/usr/bin/env node
// shipcrate ui: a local release dashboard for one project. Node 18+, no dependencies.
//   shipcrate ui [--port 4747] [--no-open]      (run inside a project set up with shipcrate)
// Shows the live release (version, rollout, yanked, announcement), the beta channel, downloads, releases and the
// project's state, and runs the same scripts as the commands: checks, doctor, changelog, release preview,
// webhook test, and, after you confirm the exact command, rollout / announce / yank.
// Safety: listens on 127.0.0.1 only; every API call needs the random token from the URL it prints; the Host
// header must be local (no DNS rebinding); actions are a fixed list with checked arguments, run without a shell.
// Publishing a release stays in the terminal (sh scripts/release.sh X.Y.Z).
"use strict";
const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawn, execFile } = require("node:child_process");

const KIT = path.resolve(__dirname, "..");
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const DIR = path.resolve(argv.find((a, i) => !a.startsWith("--") && argv[i - 1] !== "--port") || process.cwd());
const PORT = Number(opt("--port", process.env.PORT || 4747));
const TOKEN = crypto.randomBytes(24).toString("hex");

if (!fs.existsSync(path.join(DIR, "release.conf"))) { console.error(`✗ ${DIR} has no release.conf: run this inside a project set up with shipcrate`); process.exit(1); }

// ---- release.conf (only plain KEY='value' lines; never sourced here)
function conf() {
  const out = {};
  for (const l of fs.readFileSync(path.join(DIR, "release.conf"), "utf8").split("\n")) {
    const m = l.match(/^([A-Z_]+)=(?:'([^']*)'|"([^"]*)"|(\S*))/);
    if (m) out[m[1]] = m[2] ?? m[3] ?? m[4] ?? "";
  }
  delete out.PUBLIC_KEY_PRIVATE; // never sent (and never in release.conf anyway)
  return out;
}
const C = conf();
const REPO = C.REPO || "";

const run = (cmd, args, timeout = 60000) => new Promise(r => execFile(cmd, args, { cwd: DIR, timeout, maxBuffer: 16 << 20, env: { ...process.env, NO_COLOR: "1" } },
  (e, out, err) => r({ ok: !e, out: String(out), err: String(err) })));
const json = s => { try { return JSON.parse(s); } catch { return null; } };

// ---- data
async function overview() {
  const c = conf();
  const [branch, head, dirty, tags, latest, beta, rels] = await Promise.all([
    run("git", ["rev-parse", "--abbrev-ref", "HEAD"]), run("git", ["log", "-1", "--format=%h %s"]),
    run("git", ["status", "--porcelain"]), run("git", ["tag", "-l", "v[0-9]*", "--sort=-v:refname"]),
    run("gh", ["release", "download", "--repo", REPO, "--pattern", "latest.json", "--output", "-"], 30000),
    run("gh", ["release", "download", "channel", "--repo", REPO, "--pattern", "beta.json", "--output", "-"], 30000),
    run("gh", ["release", "list", "--repo", REPO, "--limit", "15", "--json", "tagName,name,isPrerelease,isLatest,publishedAt"], 30000),
  ]);
  const lastTag = tags.out.split("\n").find(t => /^v\d+\.\d+\.\d+$/.test(t)) || "";
  const since = lastTag ? (await run("git", ["rev-list", "--count", `${lastTag}..HEAD`])).out.trim() : "";
  const gh = await run("gh", ["auth", "status"], 15000);
  const strip = m => { if (m) delete m.notes; return m; };
  return {
    product: c.PRODUCT, repo: REPO, type: c.TYPE, lang: c.KIT_LANG || c.LANG, targets: c.TARGETS, shipcrate: c.SHIPCRATE_VERSION || "",
    signed: /^[A-Za-z0-9+/=]{40,}$/.test(c.PUBLIC_KEY || ""), snapshots: c.STATS_SNAPSHOTS === "on", safeDays: Number(c.SAFE_ROLLOUT_DAYS || 7),
    git: { branch: branch.out.trim(), head: head.out.trim(), dirty: dirty.out.trim().split("\n").filter(Boolean).length, lastTag, since: Number(since || 0) },
    gh: gh.ok, latest: strip(json(latest.out)), beta: strip(json(beta.out)), releases: json(rels.out) || [],
  };
}

async function stats() {
  const r = await run("gh", ["api", `repos/${REPO}/releases?per_page=100`, "--paginate", "--jq",
    '.[] | . as $r | .assets[] | [$r.tag_name, ($r.prerelease|tostring), .name, (.download_count|tostring), $r.published_at] | @tsv'], 60000);
  if (!r.ok) return { ok: false, error: (r.err || r.out).split("\n")[0] || "needs the GitHub CLI (gh), signed in: gh auth login" };
  const base = {};
  const bf = path.join(process.env.XDG_CONFIG_HOME || path.join(process.env.HOME || "", ".config"), "shipcrate/stats", REPO.replace("/", "-") + ".baseline.csv");
  if (fs.existsSync(bf)) for (const l of fs.readFileSync(bf, "utf8").split("\n")) { const [t, f, n] = l.split(","); if (t) base[t + "/" + f] = Number(n) || 0; }
  const rows = r.out.trim().split("\n").filter(Boolean).map(l => { const [tag, pre, file, n, at] = l.split("\t");
    return { tag, beta: pre === "true", file, count: Math.max(0, Number(n) - (base[tag + "/" + file] || 0)), at }; });
  return { ok: true, baseline: Object.keys(base).length > 0, rows };
}

// ---- actions: fixed list, checked arguments, no shell
const VER = /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/;
const need = (ok, msg) => { if (!ok) throw new Error(msg); };
// Free text goes to the scripts as an argument: it must not look like a flag (--clear, -y) or hold control characters.
const textArg = (v, max, what) => { need(typeof v === "string" && v.trim() && v.length <= max, `${what}: 1-${max} characters`);
  need(!/^\s*-/.test(v), `${what} can't start with "-"`); need(!/[\u0000-\u001f\u007f]/.test(v), `${what}: one line, no control characters`); return v.trim(); };
const hasScript = n => need(fs.existsSync(path.join(DIR, "scripts", n)), `scripts/${n} is missing in this project: run shipcrate sync to add it`);
const ACTIONS = {
  check:     a => hasScript("check.sh") || ["sh", ["scripts/check.sh", ...(a.quick ? ["--quick"] : [])]],
  doctor:    () => ["sh", [path.join(KIT, "bin/shipcrate"), "doctor"]],
  changelog: () => hasScript("changelog.sh") || ["sh", ["scripts/changelog.sh"]],
  stats:     () => hasScript("stats.sh") || ["sh", ["scripts/stats.sh"]],
  preview:   a => { hasScript("release.sh"); need(VER.test(a.version || ""), "version must look like 1.2.3 or 1.2.3-beta.1"); return ["sh", ["scripts/release.sh", a.version, "--dry-run"]]; },
  webhook:   a => { hasScript("webhook-test.sh"); need(!a.event || ["all", "release", "security", "announcement", "yank"].includes(a.event), "unknown event"); need(/^https:\/\/[^\s]+$|^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?(\/\S*)?$/.test(a.url || ""), "URL must be https (http only for localhost)");
                    return ["sh", ["scripts/webhook-test.sh", "--url", a.url, ...(a.event && a.event !== "all" ? ["--event", a.event] : [])]]; },
  rollout:   a => { hasScript("rollout.sh"); const p = Number(a.percent); need(Number.isInteger(p) && p >= 0 && p <= 100, "percent must be 0-100");
                    const d = a.days ? Number(a.days) : 0; need(Number.isInteger(d) && d >= 0 && d <= 365, "days must be 0-365");
                    return ["sh", ["scripts/rollout.sh", String(p), ...(d ? ["--days", String(d)] : []), "--yes"]]; },
  announce:  a => { hasScript("announce.sh"); if (a.clear) return ["sh", ["scripts/announce.sh", "--clear", "--yes"]];
                    const msg = textArg(a.message, 300, "message");
                    need(["info", "warning", "security"].includes(a.level || "info"), "level: info, warning or security");
                    need(!a.url || /^https:\/\/\S+$/.test(a.url), "link must be https"); need(!a.below || VER.test(a.below), "below must be a version");
                    return ["sh", ["scripts/announce.sh", msg, "--level", a.level || "info", ...(a.url ? ["--url", a.url] : []), ...(a.below ? ["--below", a.below] : []), "--yes"]]; },
  yank:      a => { hasScript("yank.sh"); need(VER.test(a.version || ""), "version to yank must look like 1.2.3"); need(!a.to || VER.test(a.to), "--to must be a version");
                    const reason = a.reason ? textArg(a.reason, 200, "reason") : "";
                    return ["sh", ["scripts/yank.sh", a.version, ...(a.to ? ["--to", a.to] : []), ...(reason ? ["--reason", reason] : []), "--yes"]]; },
};
const PUBLISHES = new Set(["rollout", "announce", "yank"]);   // change what installed copies see: need confirm
const shown = (cmd, args) => [cmd, ...args].filter(x => x !== "--yes").map(x => /^[\w./:=@%+-]+$/.test(x) ? x : `'${x.replace(/'/g, "'\\''")}'`).join(" ")
  .replace(path.join(KIT, "bin/shipcrate"), "shipcrate");

let job = null; // one at a time
function start(name, a) {
  const [cmd, args] = ACTIONS[name](a);
  job = { id: crypto.randomBytes(6).toString("hex"), name, command: shown(cmd, args), out: "", done: false, code: null, started: Date.now() };
  const p = spawn(cmd, args, { cwd: DIR, env: { ...process.env, NO_COLOR: "1", CI: "" }, stdio: ["ignore", "pipe", "pipe"] });
  const add = d => { job.out = (job.out + d).slice(-200000); };
  p.stdout.on("data", add); p.stderr.on("data", add);
  p.on("close", code => { job.done = true; job.code = code; });
  return job;
}

// ---- HTTP
const PAGE = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
function body(req) { return new Promise((res, rej) => { let b = "", big = false;
  req.on("data", d => { if (big) return; b += d; if (b.length > 65536) { big = true; rej(Object.assign(new Error("request too big"), { code: 413 })); } });
  req.on("end", () => big || res(b)); }); }
const send = (res, code, obj) => res.writeHead(code, { "Content-Type": "application/json", "Cache-Control": "no-store" }).end(JSON.stringify(obj));

const server = http.createServer(async (req, res) => {
  const host = String(req.headers.host || "");
  if (!new RegExp(`^(127\\.0\\.0\\.1|localhost):${server.address().port}$`).test(host)) { res.writeHead(403).end("forbidden host"); return; }
  const u = new URL(req.url, `http://${host}`);
  if (req.method === "GET" && u.pathname === "/") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "Referrer-Policy": "no-referrer",
      "Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src data:; frame-ancestors 'none'" }).end(PAGE);
    return;
  }
  if (!u.pathname.startsWith("/api/")) { res.writeHead(404).end(); return; }
  const tok = Buffer.from(String(req.headers["x-token"] || "")), want = Buffer.from(TOKEN);
  if (tok.length !== want.length || !crypto.timingSafeEqual(tok, want)) { send(res, 401, { error: "missing or wrong token: open the URL shipcrate ui printed" }); return; }
  try {
    if (req.method === "GET" && u.pathname === "/api/overview") return send(res, 200, await overview());
    if (req.method === "GET" && u.pathname === "/api/stats") return send(res, 200, await stats());
    if (req.method === "GET" && u.pathname === "/api/job") return send(res, 200, job || {});
    if (req.method === "POST" && (u.pathname === "/api/plan" || u.pathname === "/api/run")) {
      if (!/^application\/json/.test(req.headers["content-type"] || "")) return send(res, 415, { error: "JSON only" });
      const parsed = json(await body(req));
      if (!parsed || typeof parsed !== "object") return send(res, 400, { error: "invalid JSON" });
      const { action, args = {}, confirm } = parsed;
      if (typeof args !== "object" || args === null || Array.isArray(args)) return send(res, 400, { error: "args must be an object" });
      if (!Object.prototype.hasOwnProperty.call(ACTIONS, action)) return send(res, 400, { error: "unknown action" });
      const [cmd, a] = ACTIONS[action](args);           // validates; throws with a readable message
      const command = shown(cmd, a), publishes = PUBLISHES.has(action);
      if (u.pathname === "/api/plan") return send(res, 200, { command, publishes });
      if (publishes && confirm !== command) return send(res, 400, { error: "confirm the exact command first" });
      if (job && !job.done) return send(res, 409, { error: `already running: ${job.command}` });
      return send(res, 200, start(action, args));
    }
    send(res, 404, { error: "not found" });
  } catch (e) { send(res, e.code === 413 ? 413 : 400, { error: String(e.message || e) }); }
});

server.on("error", e => {
  console.error(e.code === "EADDRINUSE" ? `✗ port ${PORT} is in use (another shipcrate ui?): try shipcrate ui --port ${PORT + 1}` : `✗ ${e.message}`);
  process.exit(1);
});
server.listen(PORT, "127.0.0.1", () => {
  const url = `http://127.0.0.1:${server.address().port}/#t=${TOKEN}`;
  console.log(`shipcrate ui for ${C.PRODUCT || path.basename(DIR)} (${REPO})\n  ${url}\n  local only; Ctrl-C to stop`);
  if (!argv.includes("--no-open") && process.platform === "darwin") spawn("open", [url], { stdio: "ignore", detached: true }).unref();
});
module.exports = { ACTIONS, shown };
