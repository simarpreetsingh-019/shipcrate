// Tests for updater/update-check.js (shipped by shipcrate). Offline: fake releases on disk via file:// URLs.
"use strict";
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");
const { pathToFileURL } = require("node:url");
const u = require("../../updater/update-check.js");

const manifest = (url, sha, security = false) => JSON.stringify({ version: "9.9.9", page: "https://example.invalid/r", security, notes: "n",
  assets: { [u.platformKey()]: { name: "x.tar.gz", url, sha256: sha } } });

test("versions", () => {
  assert.ok(u.isNewer("1.10.0", "1.9.9"));
  assert.ok(u.isNewer("v2.0.0", "1.99"));
  assert.ok(u.isNewer("1.0.0", "1.0.0-beta"));
  assert.ok(!u.isNewer("1.0.0", "1.0.0"));
  assert.ok(!u.isNewer("1.0.0-rc.1", "1.0.0"));
});

test("manifest: only this project's releases, valid checksums", () => {
  const p = u.policy({ manifest: "x", urlPrefix: "https://github.com/o/r/releases/download/" });
  const good = "https://github.com/o/r/releases/download/v9.9.9/x.tar.gz";
  assert.ok(u.parseManifest(manifest(good, "a".repeat(64), true), u.platformKey(), p).asset);
  assert.ok(u.parseManifest(manifest(good, "a".repeat(64), true), u.platformKey(), p).security);
  for (const [url, sha] of [["https://evil.example/x", "a".repeat(64)], [good, "abc"], ["file:///tmp/x", "a".repeat(64)]])
    assert.strictEqual(u.parseManifest(manifest(url, sha), u.platformKey(), p).asset, null);
});

test("announcements: cleaned, https-only links", () => {
  const p = u.policy({ manifest: "x", urlPrefix: "https://github.com/" });
  const body = JSON.stringify({ version: "1.0.0", announcement: { id: "a1", level: "warning", message: "hi\u001b[31m there\nok", url: "javascript:x" } });
  const a = u.parseManifest(body, u.platformKey(), p).announcement;
  assert.strictEqual(a.message, "hi[31m there ok");
  assert.strictEqual(a.url, "");
  assert.strictEqual(u.parseManifest(JSON.stringify({ version: "1", announcement: { id: "", message: "x" } }), "k", p).announcement, null);
});

test("rollout, yank, security, beta channel", () => {
  const p = u.policy({ manifest: "x", urlPrefix: "https://github.com/" });
  const l = u.parseManifest(JSON.stringify({ version: "1.2.0", rollout: 25, yanked: ["1.3.0"] }), "k", p);
  assert.ok(u.offeredTo(l, "1.0.0", 10) && !u.offeredTo(l, "1.0.0", 60));
  assert.ok(u.offeredTo(l, "1.3.0", 99));
  assert.match(u.noticeLine(l, "1.3.0"), /pulled/);
  assert.ok(u.offeredTo(u.parseManifest(JSON.stringify({ version: "1.2.0", rollout: 0, security: true }), "k", p), "1.0.0", 99));
  process.env["HELLO_NODE_CHANNEL"] = "beta";
  try { assert.match(u.policy().manifest, /\/releases\/download\/channel\/beta\.json$/); } finally { delete process.env["HELLO_NODE_CHANNEL"]; }
});

test("timed rollout grows over days", () => {
  const p = u.policy({ manifest: "x", urlPrefix: "https://github.com/" });
  const l = u.parseManifest(JSON.stringify({ version: "2.0.0", published: "2026-11-20T00:00:00Z", rollout_days: 4 }), "k", p);
  const t0 = 1795132800;
  assert.strictEqual(l.published, t0);
  assert.strictEqual(u.effectiveRollout(l, t0), 0);
  assert.strictEqual(u.effectiveRollout(l, t0 + 2 * 86400), 50);
  assert.strictEqual(u.effectiveRollout(l, t0 + 9 * 86400), 100);
});

test("loopback manifest only for this machine", () => {
  assert.strictEqual(u.loopbackOrigin("http://127.0.0.1:8123/latest.json"), "http://127.0.0.1:8123/");
  assert.strictEqual(u.loopbackOrigin("http://127.0.0.1.evil.com/x"), null);
  assert.strictEqual(u.loopbackOrigin("http://example.com/x"), null);
});

test("no checks in CI", async () => {
  process.env.CI = "1";
  try { assert.strictEqual(u.checksAllowed(), false); assert.strictEqual(await u.check("0.0.1"), null); } finally { delete process.env.CI; }
});

test("upgrade: tampered refused, good swapped, rollback", { skip: process.platform === "win32" }, async () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), "upd-"));
  const exe = path.join(d, "hello-node");
  fs.writeFileSync(exe, "old");
  const rel = path.join(d, "rel"); fs.mkdirSync(rel);
  fs.writeFileSync(path.join(rel, "hello-node"), "new");
  execFileSync("tar", ["-czf", "x.tar.gz", "hello-node"], { cwd: rel });
  const url = pathToFileURL(path.join(rel, "x.tar.gz")).href;
  const m = path.join(d, "latest.json");
  const p = u.policy({ manifest: pathToFileURL(m).href, urlPrefix: "https://github.com/", allowFile: true });
  fs.writeFileSync(m, manifest(url, "0".repeat(64)));
  assert.match(await u.upgradeAt(exe, "1.0.0", false, p), /Checksum mismatch/);
  assert.strictEqual(fs.readFileSync(exe, "utf8"), "old");
  const sha = crypto.createHash("sha256").update(fs.readFileSync(path.join(rel, "x.tar.gz"))).digest("hex");
  fs.writeFileSync(m, manifest(url, sha));
  assert.match(await u.upgradeAt(exe, "1.0.0", false, p), /9\.9\.9/);
  assert.strictEqual(fs.readFileSync(exe, "utf8"), "new");
  await u.upgradeAt(exe, "9.9.9", true, p);
  assert.strictEqual(fs.readFileSync(exe, "utf8"), "old");
  fs.writeFileSync(m, manifest(url, sha).replace('"notes":"n"', '"notes":"n","yanked":["10.0.0"]'));
  assert.match(await u.upgradeAt(exe, "10.0.0", false, p), /9\.9\.9/);
  assert.strictEqual(fs.readFileSync(exe, "utf8"), "new");
  fs.rmSync(d, { recursive: true, force: true });
});
