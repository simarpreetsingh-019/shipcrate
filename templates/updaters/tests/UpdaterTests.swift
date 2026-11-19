// Tests for updater/Updater.swift (shipped by shipcrate). Built with swiftc as a small runner; no network.
import Foundation

var failures = 0
func expect(_ ok: Bool, _ what: String) { if ok { print("  ✔ \(what)") } else { print("  ✗ \(what)"); failures += 1 } }

expect(Updater.isNewer("1.10.0", than: "1.9.9"), "1.10.0 > 1.9.9")
expect(!Updater.isNewer("1.0.0", than: "1.0.0"), "same version isn't newer")
expect(Updater.isNewer("2.0", than: "1.99.99"), "2.0 > 1.99.99")

func manifest(_ url: String, _ sha: String, security: Bool = false) -> Data {
    let j: [String: Any] = ["version": "9.9.9", "page": "https://github.com/x/y/releases/tag/v9.9.9", "security": security, "notes": "n",
                            "assets": ["macos": ["name": "x.zip", "url": url, "sha256": sha]]]
    return try! JSONSerialization.data(withJSONObject: j)
}
let good = "https://github.com/x/y/releases/download/v9.9.9/x.zip"
let r = Updater.parseManifest(manifest(good, String(repeating: "a", count: 64), security: true), current: "1.0.0")
expect(r != nil && r!.isSecurity, "accepts a newer GitHub release and sees the security flag")
expect(Updater.parseManifest(manifest(good, String(repeating: "a", count: 64)), current: "9.9.9") == nil, "no update when current")
expect(Updater.parseManifest(manifest("https://evil.example/x.zip", String(repeating: "a", count: 64)), current: "1.0.0") == nil, "refuses other hosts")
expect(Updater.parseManifest(manifest("http://github.com/x.zip", String(repeating: "a", count: 64)), current: "1.0.0") == nil, "refuses plain http")
expect(Updater.parseManifest(manifest(good, "abc"), current: "1.0.0") == nil, "refuses a bad checksum")
exit(failures == 0 ? 0 : 1)
