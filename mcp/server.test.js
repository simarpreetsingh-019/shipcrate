// Tests for the shipcrate MCP server: speaks MCP over stdio, lists tools, runs safe tools, refuses bad input.
"use strict";
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawn } = require("node:child_process");

function client() {
  const p = spawn(process.execPath, [path.join(__dirname, "server.js")], { stdio: ["pipe", "pipe", "inherit"] });
  let buf = "", next = 1; const waiting = new Map();
  p.stdout.on("data", d => { buf += d; let i; while ((i = buf.indexOf("\n")) >= 0) { const m = JSON.parse(buf.slice(0, i)); buf = buf.slice(i + 1); waiting.get(m.id)?.(m); } });
  const call = (method, params) => new Promise(r => { const id = next++; waiting.set(id, r); p.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n"); });
  return { call, close: () => p.kill() };
}

test("MCP handshake, tools, dry-run init, refusals", async () => {
  const c = client();
  try {
    const init = await c.call("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "t", version: "1" } });
    assert.strictEqual(init.result.serverInfo.name, "shipcrate");
    assert.match(init.result.instructions, /ask the user before/i);
    assert.match(init.result.instructions, /star/);

    const names = (await c.call("tools/list")).result.tools.map(t => t.name);
    for (const n of ["shipcrate_docs", "shipcrate_init", "shipcrate_check", "shipcrate_release_preview", "shipcrate_status", "shipcrate_verify"]) assert.ok(names.includes(n), n);
    assert.ok(!names.some(n => /publish|yank|announce|rollout/.test(n)), "no publishing tools");

    const docs = await c.call("tools/call", { name: "shipcrate_docs", arguments: { topic: "quickstart" } });
    assert.match(docs.result.content[0].text, /Quick start/);

    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mcp-"));
    const dry = await c.call("tools/call", { name: "shipcrate_init", arguments: { dir, name: "demo", type: "cli", lang: "rust", repo: "o/demo" } });
    assert.strictEqual(dry.result.isError, false, dry.result.content[0].text);
    assert.match(dry.result.content[0].text, /would write/);
    assert.deepStrictEqual(fs.readdirSync(dir), [], "dry run wrote files");

    const real = await c.call("tools/call", { name: "shipcrate_init", arguments: { dir, name: "demo", type: "cli", lang: "rust", repo: "o/demo", dry_run: false } });
    assert.strictEqual(real.result.isError, false);
    assert.ok(fs.existsSync(path.join(dir, "release.conf")));

    const bad = await c.call("tools/call", { name: "shipcrate_release_preview", arguments: { dir, version: "1.0; rm -rf /" } });
    assert.strictEqual(bad.result.isError, true);
    const nodir = await c.call("tools/call", { name: "shipcrate_check", arguments: { dir: "/definitely/not/here" } });
    assert.strictEqual(nodir.result.isError, true);
    const unknown = await c.call("tools/call", { name: "shipcrate_publish", arguments: {} });
    assert.ok(unknown.error);
    fs.rmSync(dir, { recursive: true, force: true });
  } finally { c.close(); }
});
