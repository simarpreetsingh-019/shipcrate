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

test("no checks in CI", async () => {
  process.env.CI = "1";
  try { assert.strictEqual(u.checksAllowed(), false); assert.strictEqual(await u.check("0.0.1"), null); } finally { delete process.env.CI; }
});

test("upgrade: tampered refused, good swapped, rollback", { skip: process.platform === "win32" }, async () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), "upd-"));
  const exe = path.join(d, "{{BINARY}}");
  fs.writeFileSync(exe, "old");
  const rel = path.join(d, "rel"); fs.mkdirSync(rel);
  fs.writeFileSync(path.join(rel, "{{BINARY}}"), "new");
  execFileSync("tar", ["-czf", "x.tar.gz", "{{BINARY}}"], { cwd: rel });
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
  fs.rmSync(d, { recursive: true, force: true });
});
