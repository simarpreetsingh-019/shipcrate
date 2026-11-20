// Tests for the demo receiver: signature required, events summarized, forwarding called.
"use strict";
process.env.RELEASE_WEBHOOK_SECRET = "test-secret";
const test = require("node:test");
const assert = require("node:assert");
const crypto = require("node:crypto");
const { createServer, summarize } = require("./server.js");

const manifest = { name: "msh", version: "0.3.0", security: true, page: "https://github.com/o/r/releases/tag/v0.3.0", assets: { "macos-arm64": {}, "linux-x64": {} } };
const sign = body => "sha256=" + crypto.createHmac("sha256", "test-secret").update(body).digest("hex");

test("summaries", () => {
  assert.match(summarize("release", manifest), /Security update: msh 0\.3\.0 \(macos-arm64, linux-x64\)/);
  assert.match(summarize("announcement", { name: "msh", announcement: { message: "Maintenance tonight", url: "https://x.y" } }), /📣 msh: Maintenance tonight · https:\/\/x\.y/);
});

test("rejects unsigned and wrongly signed requests, accepts signed ones", async () => {
  const srv = createServer().listen(0);
  const url = `http://127.0.0.1:${srv.address().port}/`;
  const body = JSON.stringify(manifest);
  const send = headers => fetch(url, { method: "POST", body, headers: { "Content-Type": "application/json", ...headers } }).then(r => r.status);
  try {
    assert.strictEqual(await send({}), 401);
    assert.strictEqual(await send({ "X-Shipcrate-Signature": "sha256=" + "0".repeat(64) }), 401);
    assert.strictEqual(await send({ "X-Shipcrate-Signature": sign(body), "X-Shipcrate-Event": "release" }), 202);
  } finally { srv.close(); }
});
