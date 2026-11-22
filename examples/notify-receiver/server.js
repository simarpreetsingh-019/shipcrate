#!/usr/bin/env node
// shipcrate release webhook receiver: a small, dependency-free demo (Node 18+).
//
// shipcrate POSTs your release manifest (latest.json) here on every release (and every scripts/announce.sh).
// This server checks the HMAC signature, then forwards a short message to wherever your users or team listen:
//   SLACK_WEBHOOK_URL    Slack incoming webhook
//   DISCORD_WEBHOOK_URL  Discord webhook
//   FORWARD_URL          your own push service (APNs/FCM gateway, in-app inbox…): receives a small JSON event
// With none set, it just logs. Replace forward() with your own code; keep verify() as it is.
//
//   RELEASE_WEBHOOK_SECRET=… PORT=8787 node server.js
//   (then set the same RELEASE_WEBHOOK_SECRET and RELEASE_WEBHOOK_URL=https://your-host/shipcrate in GitHub secrets)
"use strict";
const http = require("node:http");
const crypto = require("node:crypto");

const SECRET = process.env.RELEASE_WEBHOOK_SECRET || "";
const PORT = Number(process.env.PORT || 8787);
const MAX_BODY = 1024 * 1024;

// Constant-time check of "X-Shipcrate-Signature: sha256=<hex HMAC-SHA256 of the raw body>".
function verify(raw, header) {
  if (!SECRET) return false;
  const want = Buffer.from("sha256=" + crypto.createHmac("sha256", SECRET).update(raw).digest("hex"));
  const got = Buffer.from(String(header || ""));
  return got.length === want.length && crypto.timingSafeEqual(got, want);
}

// Turn the manifest into one human line.
function summarize(event, m) {
  const name = m.name || "your app";
  if (event === "yank") {
    return `⚠️ ${name}: ${m.announcement ? m.announcement.message : `${(m.yanked || []).join(", ") || "a version"} was withdrawn`}`;
  }
  if (event === "announcement") {
    const a = m.announcement;
    return a ? `📣 ${name}: ${a.message}${a.url ? " · " + a.url : ""}` : `📣 ${name}: announcement cleared`;
  }
  const platforms = Object.keys(m.assets || {}).join(", ");
  return `${m.security ? "⚠️ Security update" : "🚀 New release"}: ${name} ${m.version}${platforms ? ` (${platforms})` : ""} · ${m.page}`;
}

async function forward(event, m, text) {
  const post = (url, body) => fetch(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const jobs = [];
  if (process.env.SLACK_WEBHOOK_URL) jobs.push(post(process.env.SLACK_WEBHOOK_URL, { text }));
  if (process.env.DISCORD_WEBHOOK_URL) jobs.push(post(process.env.DISCORD_WEBHOOK_URL, { content: text }));
  if (process.env.FORWARD_URL) jobs.push(post(process.env.FORWARD_URL, {
    event, name: m.name, version: m.version, security: !!m.security, page: m.page, announcement: m.announcement || null, text,
  }));
  const results = await Promise.allSettled(jobs);
  results.forEach((r, i) => r.status === "rejected" && console.error(`forward ${i} failed:`, r.reason.message));
}

// Optional live page (VIEW=1): the last 50 messages, accepted or refused. Only served to this machine.
const VIEW = process.env.VIEW === "1";
const seen = [];
const note = (event, ok, text) => { seen.unshift({ time: new Date().toISOString(), event, ok, text }); seen.length = Math.min(seen.length, 50); };
const esc = t => String(t).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
function page() {
  const rows = seen.map(e => `<tr class="${e.ok ? "ok" : "no"}"><td>${esc(e.time.slice(11, 19))}</td><td>${esc(e.event)}</td><td>${e.ok ? "✔ accepted" : "✗ refused"}</td><td>${esc(e.text)}</td></tr>`).join("");
  return `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="2">
<title>Webhook receiver</title><style>
:root{--bg:#fff;--fg:#1d1d1f;--mut:#6e6e73;--line:#e5e5ea;--ok:#1a7f37;--no:#c62828}
@media (prefers-color-scheme:dark){:root{--bg:#111;--fg:#f5f5f7;--mut:#a1a1a6;--line:#2c2c2e;--ok:#3fb950;--no:#ff6b6b}}
body{background:var(--bg);color:var(--fg);font:15px/1.45 -apple-system,system-ui,sans-serif;margin:0;padding:24px 16px;max-width:960px;margin:auto}
h1{font-size:22px;margin:0 0 4px}p{color:var(--mut);margin:0 0 20px}table{width:100%;border-collapse:collapse}
td,th{text-align:left;padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}th{color:var(--mut);font-weight:500;font-size:13px}
td:nth-child(3){white-space:nowrap}tr.ok td:nth-child(3){color:var(--ok)}tr.no td:nth-child(3){color:var(--no)}td:first-child{font-variant-numeric:tabular-nums;color:var(--mut)}
</style><h1>shipcrate webhook receiver</h1><p>Port ${PORT} · signature check ${SECRET ? "on" : "off"} · ${seen.length} message(s) · refreshes every 2 s.
Send some: <code>shipcrate webhook test --url http://localhost:${PORT}</code></p>
<table><tr><th>Time (UTC)</th><th>Event</th><th>Result</th><th>Message</th></tr>${rows || '<tr><td colspan="4">Nothing yet.</td></tr>'}</table>`;
}

function createServer() {
  return http.createServer((req, res) => {
    if (req.method === "GET" && VIEW) {
      const local = ["127.0.0.1", "::1", "::ffff:127.0.0.1"].includes(req.socket.remoteAddress);
      if (!local) { res.writeHead(403).end(); return; }
      if (req.url === "/events.json") { res.writeHead(200, { "Content-Type": "application/json" }).end(JSON.stringify(seen)); return; }
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'" }).end(page()); return;
    }
    if (req.method !== "POST") { res.writeHead(405).end(); return; }
    const chunks = []; let size = 0;
    req.on("data", c => { size += c.length; if (size > MAX_BODY) { res.writeHead(413).end(); req.destroy(); } else chunks.push(c); });
    req.on("end", async () => {
      if (res.writableEnded) return;
      const raw = Buffer.concat(chunks);
      if (!verify(raw, req.headers["x-shipcrate-signature"])) {
        note(String(req.headers["x-shipcrate-event"] || "?"), false, req.headers["x-shipcrate-signature"] ? "wrong signature" : "no signature");
        res.writeHead(401).end("bad signature\n"); return;
      }
      let m;
      try { m = JSON.parse(raw); } catch { res.writeHead(400).end("bad json\n"); return; }
      const event = ["announcement", "yank"].includes(req.headers["x-shipcrate-event"]) ? req.headers["x-shipcrate-event"] : "release";
      const text = summarize(event, m);
      console.log(`[${new Date().toISOString()}] ${event}: ${text}`); note(event, true, text);
      res.writeHead(202).end("ok\n");      // answer fast; shipcrate doesn't wait for your fan-out
      await forward(event, m, text);
    });
  });
}

if (require.main === module) {
  if (!SECRET) { console.error("Set RELEASE_WEBHOOK_SECRET (the same value as the GitHub secret)."); process.exit(1); }
  createServer().listen(PORT, () => console.log(`shipcrate receiver on http://localhost:${PORT} (put HTTPS in front of it)${VIEW ? " · live page: http://localhost:" + PORT + "/" : ""}`));
}
module.exports = { createServer, verify, summarize };
