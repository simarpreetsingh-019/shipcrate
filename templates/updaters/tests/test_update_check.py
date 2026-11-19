"""Tests for updater/update_check.py (shipped by shipcrate). Offline: fake releases on disk via file:// URLs."""
import hashlib, io, json, os, sys, tarfile, tempfile, unittest
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


if __name__ == "__main__":
    unittest.main()
