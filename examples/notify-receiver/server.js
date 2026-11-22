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

function createServer() {
  return http.createServer((req, res) => {
    if (req.method !== "POST") { res.writeHead(405).end(); return; }
    const chunks = []; let size = 0;
    req.on("data", c => { size += c.length; if (size > MAX_BODY) { res.writeHead(413).end(); req.destroy(); } else chunks.push(c); });
    req.on("end", async () => {
      if (res.writableEnded) return;
      const raw = Buffer.concat(chunks);
      if (!verify(raw, req.headers["x-shipcrate-signature"])) { res.writeHead(401).end("bad signature\n"); return; }
      let m;
      try { m = JSON.parse(raw); } catch { res.writeHead(400).end("bad json\n"); return; }
      const event = ["announcement", "yank"].includes(req.headers["x-shipcrate-event"]) ? req.headers["x-shipcrate-event"] : "release";
      const text = summarize(event, m);
      console.log(`[${new Date().toISOString()}] ${event}: ${text}`);
      res.writeHead(202).end("ok\n");      // answer fast; shipcrate doesn't wait for your fan-out
      await forward(event, m, text);
    });
  });
}

if (require.main === module) {
  if (!SECRET) { console.error("Set RELEASE_WEBHOOK_SECRET (the same value as the GitHub secret)."); process.exit(1); }
  createServer().listen(PORT, () => console.log(`shipcrate receiver on http://localhost:${PORT} (put HTTPS in front of it)`));
}
module.exports = { createServer, verify, summarize };
