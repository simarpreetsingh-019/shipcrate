// Tests for shipcrate ui: local only, token required, local Host only, JSON only, checked arguments, and
// actions that change what users see need the exact command confirmed.
"use strict";
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const http = require("node:http");
const { spawn, execFileSync } = require("node:child_process");

const KIT = path.resolve(__dirname, "..");
const req = (port, p, { method = "GET", headers = {}, body } = {}) => new Promise((res, rej) => {
  const r = http.request({ host: "127.0.0.1", port, path: p, method, headers }, x => { let b = ""; x.on("data", d => b += d); x.on("end", () => res({ code: x.statusCode, body: b })); });
  r.on("error", rej); if (body) r.write(body); r.end();
});

test("ui server guards", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ui-"));
  execFileSync("sh", [path.join(KIT, "bin/shipcrate"), "init", dir, "--yes", "--name", "uit", "--type", "cli", "--lang", "python", "--repo", "o/uit"], { stdio: "ignore" });
  const p = spawn(process.execPath, [path.join(__dirname, "server.js"), dir, "--no-open", "--port", "0"], { stdio: ["ignore", "pipe", "inherit"] });
  try {
    const url = await new Promise((res, rej) => { let b = ""; p.stdout.on("data", d => { b += d; const m = b.match(/http:\/\/127\.0\.0\.1:(\d+)\/#t=([0-9a-f]+)/); if (m) res(m); }); p.on("exit", () => rej(new Error("exited"))); });
    const port = Number(url[1]), tok = url[2], H = { "X-Token": tok, "Content-Type": "application/json" };
    assert.strictEqual((await req(port, "/")).code, 200);
    assert.strictEqual((await req(port, "/api/job")).code, 401, "no token");
    assert.strictEqual((await req(port, "/api/job", { headers: { "X-Token": "0".repeat(48) } })).code, 401, "wrong token");
    assert.strictEqual((await req(port, "/api/job", { headers: { "X-Token": tok, Host: "evil.example:" + port } })).code, 403, "foreign Host");
    assert.strictEqual((await req(port, "/api/run", { method: "POST", headers: { "X-Token": tok, "Content-Type": "application/x-www-form-urlencoded" }, body: "action=yank" })).code, 415, "form posts");
    const plan = await req(port, "/api/plan", { method: "POST", headers: H, body: JSON.stringify({ action: "rollout", args: { percent: 50, days: 7 } }) });
    assert.deepStrictEqual(JSON.parse(plan.body), { command: "sh scripts/rollout.sh 50 --days 7", publishes: true });
    const noconf = await req(port, "/api/run", { method: "POST", headers: H, body: JSON.stringify({ action: "yank", args: { version: "1.0.0" } }) });
    assert.strictEqual(noconf.code, 400); assert.match(noconf.body, /confirm/);
    const bad = await req(port, "/api/plan", { method: "POST", headers: H, body: JSON.stringify({ action: "preview", args: { version: "1.0; rm -rf /" } }) });
    assert.strictEqual(bad.code, 400);
    for (const action of ["constructor", "__proto__", "release"]) {
      const u = await req(port, "/api/plan", { method: "POST", headers: H, body: JSON.stringify({ action }) });
      assert.match(u.body, /unknown action/, action);
    }
    const hook = await req(port, "/api/plan", { method: "POST", headers: H, body: JSON.stringify({ action: "webhook", args: { url: "http://example.com" } }) });
    assert.strictEqual(hook.code, 400, "plain http outside localhost");
    const planErr = async (action, args) => { const x = await req(port, "/api/plan", { method: "POST", headers: H, body: JSON.stringify({ action, args }) }); return [x.code, JSON.parse(x.body).error || ""]; };
    // free text must never become a flag of the script (a message "--clear" would clear the live announcement)
    for (const message of ["--clear", "-y", "  --yes"]) assert.deepStrictEqual((await planErr("announce", { message }))[0], 400, message);
    assert.match((await planErr("announce", { message: "two\nlines" }))[1], /one line/);
    assert.match((await planErr("yank", { version: "1.0.0", reason: "--to 0.0.1" }))[1], /can't start/);
    assert.match((await planErr("announce", { message: "x".repeat(301) }))[1], /1-300/);
    assert.match((await planErr("webhook", { url: "https://a.b", event: "evil" }))[1], /unknown event/);
    assert.match((await planErr("check", "--release"))[1], /args must be an object/);
    const ok = await req(port, "/api/plan", { method: "POST", headers: H, body: JSON.stringify({ action: "announce", args: { message: "Hi 👋 it's \"ok\"" } }) });
    assert.strictEqual(ok.code, 200, "normal text with quotes and emoji is fine");
    assert.match((await req(port, "/api/plan", { method: "POST", headers: H, body: "{nope" })).body, /invalid JSON/);
    assert.strictEqual((await req(port, "/api/plan", { method: "POST", headers: H, body: "a".repeat(70000) })).code, 413);
    fs.rmSync(path.join(dir, "scripts/yank.sh"));
    assert.match((await planErr("yank", { version: "1.0.0" }))[1], /missing.*shipcrate sync/, "old projects without a script get a clear message");
  } finally { p.kill(); fs.rmSync(dir, { recursive: true, force: true }); }
});
