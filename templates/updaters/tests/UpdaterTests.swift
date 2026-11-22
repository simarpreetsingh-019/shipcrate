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
expect(!Updater.downloadAllowed(URL(string: "http://127.0.0.1:8000/x.zip")!), "no local downloads unless the manifest is local")
expect(Updater.parseManifest(manifest("http://github.com/x.zip", String(repeating: "a", count: 64)), current: "1.0.0") == nil, "refuses plain http")
expect(Updater.parseManifest(manifest(good, "abc"), current: "1.0.0") == nil, "refuses a bad checksum")
func m2(_ extra: [String: Any]) -> Data {
    var j: [String: Any] = ["version": "1.2.0", "page": "https://github.com/x/y", "notes": "",
                            "assets": ["macos": ["name": "x.zip", "url": good, "sha256": String(repeating: "a", count: 64)]]]
    extra.forEach { j[$0.key] = $0.value }
    return try! JSONSerialization.data(withJSONObject: j)
}
expect(Updater.parseManifest(m2(["rollout": 25]), current: "1.0.0", bucket: 10) != nil, "rollout: inside the 25%")
expect(Updater.parseManifest(m2(["rollout": 25]), current: "1.0.0", bucket: 60) == nil, "rollout: outside the 25%")
expect(Updater.parseManifest(m2(["rollout": 0, "security": true]), current: "1.0.0", bucket: 99) != nil, "security ignores rollout")
let back = Updater.parseManifest(m2(["yanked": ["1.3.0"]]), current: "1.3.0", bucket: 99)
expect(back != nil && back!.replacesYanked, "yanked version is offered the older good release")
let t0 = ISO8601DateFormatter().date(from: "2026-11-20T00:00:00Z")!
let timed: [String: Any] = ["published": "2026-11-20T00:00:00Z", "rollout_days": 4]
expect(Updater.effectiveRollout(timed, now: t0) == 0, "timed rollout starts at 0%")
expect(Updater.effectiveRollout(timed, now: t0.addingTimeInterval(2 * 86400)) == 50, "timed rollout: 50% after 2 of 4 days")
expect(Updater.effectiveRollout(timed, now: t0.addingTimeInterval(9 * 86400)) == 100, "timed rollout: 100% when done")
Updater.channel = "beta"
expect(Updater.manifestURL.absoluteString.hasSuffix("/releases/download/channel/beta.json"), "beta channel URL")
Updater.channel = "stable"
let annJSON: [String: Any] = ["version": "1.0.0", "announcement": ["id": "a1", "level": "warning", "message": "hi\u{1b}[31m", "url": "javascript:x", "below": "2.0.0"]]
let annData = try! JSONSerialization.data(withJSONObject: annJSON)
let ann = Announcement.parse(annData, current: "1.5.0")
expect(ann?.message == "hi[31m", "announcement: control characters stripped")
expect(ann != nil && ann!.url == nil, "announcement: only https links")
expect(Announcement.parse(annData, current: "2.0.0") == nil, "announcement: skipped for versions at or above 'below'")
let spk = "MsAhEo6wDmN12G+ny87AFJjVvz611LJ3tvW4QaLBGyo=", smsg = Data(#"{"version":"9.9.9","assets":{}}"#.utf8)
let ssig = "lQbyJHY1BoYikkMnQdtFJZijL+YVBpR9Mv0X7vvoOjdip0r88LEPjqV2V8S1MYjn2tvlca+mn5FoEh0zosxCCg=="
expect(Updater.signatureOK(smsg, sig: ssig, key: spk), "signed updates: valid Ed25519 signature accepted")
expect(!Updater.signatureOK(Data(#"{"version":"9.9.8","assets":{}}"#.utf8), sig: ssig, key: spk), "signed updates: tampered manifest refused")
expect(!Updater.signatureOK(smsg, sig: "AAAA", key: spk), "signed updates: bad signature refused")
exit(failures == 0 ? 0 : 1)
