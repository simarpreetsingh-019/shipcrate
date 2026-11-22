"""Tests for updater/update_check.py (shipped by shipcrate). Offline: fake releases on disk via file:// URLs."""
import hashlib, io, json, os, sys, tarfile, tempfile, time, unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "updater"))
import update_check as u  # noqa: E402


def manifest(url, sha, security=False):
    return json.dumps({"version": "9.9.9", "page": "https://example.invalid/r", "security": security, "notes": "n",
                       "assets": {u.platform_key(): {"name": "x.tar.gz", "url": url, "sha256": sha}}})


class Versions(unittest.TestCase):
    def test_compare(self):
        self.assertTrue(u.is_newer("1.10.0", "1.9.9"))
        self.assertTrue(u.is_newer("v2.0.0", "1.99"))
        self.assertTrue(u.is_newer("1.0.0", "1.0.0-beta"))
        self.assertFalse(u.is_newer("1.0.0", "1.0.0"))
        self.assertFalse(u.is_newer("1.0.0-rc.1", "1.0.0"))
        for a, b in (("1.10.0-beta.2", "1.10.0-beta.1"), ("1.10.0-beta.10", "1.10.0-beta.9"), ("1.10.0-rc.1", "1.10.0-beta.3"),
                     ("1.10.0", "1.10.0-rc.1"), ("1.0.0-beta.1", "1.0.0-beta")):
            self.assertTrue(u.is_newer(a, b), (a, b))
            self.assertFalse(u.is_newer(b, a), (b, a))


class Manifest(unittest.TestCase):
    def setUp(self):
        self.p = u.Policy(manifest="x", url_prefix=f"https://github.com/{u.REPO}/releases/download/")
        self.good = f"https://github.com/{u.REPO}/releases/download/v9.9.9/x.tar.gz"

    def test_accepts_project_release(self):
        l = u.parse_manifest(manifest(self.good, "a" * 64, True), u.platform_key(), self.p)
        self.assertTrue(l["security"])
        self.assertIsNotNone(l["asset"])

    def test_refuses_other_hosts_bad_checksums_and_files(self):
        for url, sha in (("https://evil.example/x.tar.gz", "a" * 64), (self.good, "abc"), ("file:///tmp/x", "a" * 64)):
            self.assertIsNone(u.parse_manifest(manifest(url, sha), u.platform_key(), self.p)["asset"])

    def test_no_checks_in_ci(self):
        os.environ["CI"] = "1"
        try:
            self.assertFalse(u.checks_allowed())
            self.assertIsNone(u.check("0.0.1"))
        finally:
            del os.environ["CI"]

    def test_opt_out(self):
        os.environ[u.OPT_OUT] = "1"
        try:
            self.assertFalse(u.checks_allowed())
        finally:
            del os.environ[u.OPT_OUT]


class Announcements(unittest.TestCase):
    def test_cleaned_https_only_and_shown_once(self):
        p = u.Policy(manifest="x", url_prefix="https://github.com/")
        body = json.dumps({"version": "1.0.0", "announcement": {"id": "a1", "level": "warning",
                           "message": "hi\x1b[31m there\nok", "url": "javascript:x", "below": "2.0.0"}})
        a = u.parse_manifest(body, u.platform_key(), p)["announcement"]
        self.assertEqual(a["message"], "hi[31m there ok")
        self.assertEqual(a["url"], "")
        with tempfile.TemporaryDirectory() as d:
            os.environ["XDG_CACHE_HOME"] = d
            orig = u.checks_allowed
            u.checks_allowed = lambda: True
            try:
                f = u._cache_file(); f.parent.mkdir(parents=True)
                f.write_text(json.dumps({"checked": time.time(), "latest": {"version": "1.0.0", "announcement": a}}))
                self.assertIsNone(u.announcement("2.0.0"))       # not for versions at or above "below"
                self.assertEqual(u.announcement("1.5.0")["id"], "a1")
                self.assertIsNone(u.announcement("1.5.0"))       # only once
            finally:
                u.checks_allowed = orig
                del os.environ["XDG_CACHE_HOME"]


class Signatures(unittest.TestCase):
    def test_rfc8032_and_tampering(self):
        h = bytes.fromhex
        pk1 = h("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        sig1 = h("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
        self.assertTrue(u.ed25519_verify(pk1, b"", sig1))
        pk2 = h("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
        sig2 = h("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00")
        self.assertTrue(u.ed25519_verify(pk2, b"\x72", sig2))
        self.assertFalse(u.ed25519_verify(pk2, b"\x73", sig2))
        pk, msg, sig = ("MsAhEo6wDmN12G+ny87AFJjVvz611LJ3tvW4QaLBGyo=", b'{"version":"9.9.9","assets":{}}',
                        "lQbyJHY1BoYikkMnQdtFJZijL+YVBpR9Mv0X7vvoOjdip0r88LEPjqV2V8S1MYjn2tvlca+mn5FoEh0zosxCCg==")
        self.assertTrue(u.signature_ok(msg, sig, pk))
        self.assertFalse(u.signature_ok(msg.replace(b"9.9.9", b"9.9.8"), sig, pk))
        self.assertFalse(u.signature_ok(msg, "AAAA", pk))


class Loopback(unittest.TestCase):
    def test_only_this_machine(self):
        self.assertEqual(u.loopback_origin("http://127.0.0.1:8123/latest.json"), "http://127.0.0.1:8123/")
        self.assertIsNone(u.loopback_origin("http://127.0.0.1.evil.com/x"))
        self.assertIsNone(u.loopback_origin("http://example.com/x"))
        os.environ[u.MANIFEST_ENV] = "http://example.com/latest.json"
        try:
            self.assertTrue(u.Policy().manifest.startswith("https://github.com/"))  # plain http elsewhere is ignored
        finally:
            del os.environ[u.MANIFEST_ENV]


class RolloutAndYank(unittest.TestCase):
    def test_rules(self):
        p = u.Policy(manifest="x", url_prefix="https://github.com/")
        l = u.parse_manifest(json.dumps({"version": "1.2.0", "rollout": 25, "yanked": ["1.3.0"]}), "k", p)
        self.assertTrue(u.offered_to(l, "1.0.0", 10))
        self.assertFalse(u.offered_to(l, "1.0.0", 60))
        self.assertTrue(u.offered_to(l, "1.3.0", 99))
        self.assertIn("pulled", u.notice_line(l, "1.3.0"))
        sec = u.parse_manifest(json.dumps({"version": "1.2.0", "rollout": 0, "security": True}), "k", p)
        self.assertTrue(u.offered_to(sec, "1.0.0", 99))
        req = u.parse_manifest(json.dumps({"version": "2.0.0", "rollout": 0, "min_version": "v1.5.0"}), "k", p)
        self.assertTrue(u.offered_to(req, "1.4.9", 99))
        self.assertFalse(u.offered_to(req, "1.5.0", 99))
        self.assertFalse(u.is_required(req, "2.0.0"))
        self.assertIn("UPDATE REQUIRED", u.notice_line(req, "1.4.9"))

    def test_timed_rollout(self):
        p = u.Policy(manifest="x", url_prefix="https://github.com/")
        l = u.parse_manifest(json.dumps({"version": "2.0.0", "published": "2026-11-20T00:00:00Z", "rollout_days": 4}), "k", p)
        t0 = 1795132800
        self.assertEqual(l["published"], t0)
        self.assertEqual(u.effective_rollout(l, t0), 0)
        self.assertEqual(u.effective_rollout(l, t0 + 2 * 86400), 50)
        self.assertEqual(u.effective_rollout(l, t0 + 9 * 86400), 100)

    def test_beta_channel_url(self):
        os.environ[u.CHANNEL_ENV] = "beta"
        try:
            self.assertTrue(u.Policy().manifest.endswith("/releases/download/channel/beta.json"))
        finally:
            del os.environ[u.CHANNEL_ENV]
        self.assertTrue(u.Policy().manifest.endswith("/releases/latest/download/latest.json"))


class Upgrade(unittest.TestCase):
    def test_tampered_refused_good_swapped_rollback(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            exe = d / u.BINARY
            exe.write_text("old")
            buf = io.BytesIO()
            with tarfile.open(fileobj=buf, mode="w:gz") as t:
                info = tarfile.TarInfo(u.BINARY); data = b"new"; info.size = len(data)
                t.addfile(info, io.BytesIO(data))
            (d / "x.tar.gz").write_bytes(buf.getvalue())
            url = (d / "x.tar.gz").as_uri()
            m = d / "latest.json"
            p = u.Policy(manifest=m.as_uri(), url_prefix="https://github.com/", allow_file=True)

            m.write_text(manifest(url, "0" * 64))
            self.assertIn("Checksum mismatch", u.upgrade_at(exe, "1.0.0", False, p))
            self.assertEqual(exe.read_text(), "old")

            m.write_text(manifest(url, hashlib.sha256(buf.getvalue()).hexdigest()))
            self.assertIn("9.9.9", u.upgrade_at(exe, "1.0.0", False, p))
            self.assertEqual(exe.read_text(), "new")
            self.assertIn("latest", u.upgrade_at(exe, "9.9.9", False, p))
            u.upgrade_at(exe, "9.9.9", True, p)
            self.assertEqual(exe.read_text(), "old")
            # a yanked newer version moves back to the manifest's good version
            m.write_text(manifest(url, hashlib.sha256(buf.getvalue()).hexdigest()).replace('"notes": "n"', '"notes": "n", "yanked": ["10.0.0"]'))
            self.assertIn("9.9.9", u.upgrade_at(exe, "10.0.0", False, p))
            self.assertEqual(exe.read_text(), "new")


if __name__ == "__main__":
    unittest.main()
