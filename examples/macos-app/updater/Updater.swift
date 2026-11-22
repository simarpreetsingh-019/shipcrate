// In-app updater for HelloShip (from shipcrate, extracted from Thermo's).
// Checks the release manifest (latest.json) at most once a day with one anonymous GET (no telemetry, nothing about the user is sent),
// shows an orange Update button (or calls your `onUpdateAvailable`), and on request downloads HelloShip.zip, verifies its
// SHA-256 against the manifest, checks the bundle ID and code signature, swaps the app in place and relaunches.
// Releases whose notes contain "[security]" (scripts/release.sh --security) get a stronger, red notice.
// Opt out: `defaults write com.example.helloship autoUpdateCheck -bool false` or the HELLOSHIP_NO_UPDATE_CHECK env var.
//
// Use:  @StateObject var updater = Updater.shared  …  UpdateButton(updater: updater)
//       call `Updater.shared.announceLaunch()` once at startup to show "What's new" after an update.

import AppKit
import CryptoKit
import SwiftUI

struct Release {
    let version: String
    let notes: String
    let zipURL: URL
    let sha256: String
    let pageURL: URL
    let security: Bool
    var isSecurity: Bool { security }
    /// The running version was pulled by the publisher (scripts/yank.sh); this release moves back to a good one.
    var replacesYanked = false
}

/// A one-off message from the publisher (scripts/announce.sh). Display-only; the app never acts on it.
struct Announcement: Equatable {
    let id: String
    let level: String      // info | warning | security
    let message: String
    let url: URL?          // https only
    let below: String      // only for versions older than this ("" = everyone)

    /// Strip control characters and cap the length: the text comes from the network.
    static func clean(_ s: Any?, _ max: Int) -> String {
        String((s as? String ?? "").unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(max).map(Character.init))
    }

    static func parse(_ data: Data, current: String) -> Announcement? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let a = j["announcement"] as? [String: Any] else { return nil }
        let url = (a["url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
        let ann = Announcement(id: clean(a["id"], 64), level: clean(a["level"], 16), message: clean(a["message"], 280), url: url, below: clean(a["below"], 32))
        guard !ann.id.isEmpty, !ann.message.isEmpty else { return nil }
        if !ann.below.isEmpty && !Updater.isNewer(ann.below, than: current) { return nil }
        return ann
    }
}

final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "you/HelloShip"
    static let bundleID = "com.example.helloship"
    static let asset = "HelloShip.zip"
    /// Signed updates: the publisher's Ed25519 public key (base64), set by scripts/keygen.sh. Empty = not signed.
    static let publicKey = "" // shipcrate:public-key

    /// Does `sig` (contents of latest.json.sig) sign `body` with `key`? CryptoKit's Ed25519.
    static func signatureOK(_ body: Data, sig: String, key: String) -> Bool {
        guard let k = Data(base64Encoded: key), let s = Data(base64Encoded: sig.trimmingCharacters(in: .whitespacesAndNewlines)),
              let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: k) else { return false }
        return pub.isValidSignature(s, for: body)
    }
    /// The release manifest. Point it at your own server or CDN (same latest.json format) if you mirror releases,
    /// and add that host to `allowedHosts`.
    static var manifestURL: URL {
        get { manifestOverride ?? envManifest ?? URL(string: channel == "beta"
            ? "https://github.com/you/HelloShip/releases/download/channel/beta.json"
            : "https://github.com/you/HelloShip/releases/latest/download/latest.json")! }
        set { manifestOverride = newValue }
    }
    private static var manifestOverride: URL?
    /// "stable" or "beta" (pre-releases too). Let users pick it in your settings: `Updater.channel = "beta"`.
    static var channel: String {
        get { UserDefaults.standard.string(forKey: "updateChannel") ?? "stable" }
        set { UserDefaults.standard.set(newValue, forKey: "updateChannel") }
    }
    /// This copy's staged-rollout bucket, 0-99: random once, kept in UserDefaults, never sent anywhere.
    static var rolloutBucket: Int {
        if let b = UserDefaults.standard.object(forKey: "rolloutBucket") as? Int, (0..<100).contains(b) { return b }
        let b = Int.random(in: 0..<100); UserDefaults.standard.set(b, forKey: "rolloutBucket"); return b
    }
    static var allowedHosts: Set<String> = ["github.com"]
    /// `HELLOSHIP_UPDATE_MANIFEST`: a mirror (https) or a manifest on this machine (http://127.0.0.1 or localhost) for
    /// testing updates without touching GitHub (and without adding to its download counts).
    static var envManifest: URL? {
        guard let s = ProcessInfo.processInfo.environment["HELLOSHIP_UPDATE_MANIFEST"], let u = URL(string: s) else { return nil }
        return u.scheme == "https" || isLoopback(u) ? u : nil
    }
    static func isLoopback(_ u: URL) -> Bool {
        u.scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(u.host ?? "")
    }
    /// Downloads only from GitHub (or your allowedHosts), over https; from this machine when the manifest is local.
    static func downloadAllowed(_ z: URL) -> Bool {
        if let m = envManifest, z.host == m.host, z.scheme == m.scheme { return true }
        return z.scheme == "https" && allowedHosts.contains(z.host ?? "")
    }
    /// Set this to route update notices into your own notification system (UNUserNotificationCenter, an in-app
    /// inbox, your push service…). Called on the main thread for automatic checks. The built-in button still works.
    var onUpdateAvailable: ((Release) -> Void)?
    /// Set this to show publisher announcements in your own UI. By default they appear in `announcement`
    /// (shown by `AnnouncementBanner`). Each message is delivered once.
    var onAnnouncement: ((Announcement) -> Void)?
    @Published var announcement: Announcement?

    @Published var available: Release?
    @Published var status: String?          // progress / error text for the UI
    @Published var whatsNew: String?        // release notes to show once after an update
    @Published var autoCheck: Bool { didSet { UserDefaults.standard.set(autoCheck, forKey: "autoUpdateCheck") } }
    private var timer: Timer?

    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    init() {
        autoCheck = UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true
        if ProcessInfo.processInfo.environment["HELLOSHIP_NO_UPDATE_CHECK"] != nil { autoCheck = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.scheduledCheck() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.scheduledCheck() }
        timer?.tolerance = 600
    }

    private func scheduledCheck() {
        guard autoCheck else { return }
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        if Date().timeIntervalSince1970 - last > 20 * 3600 { check(userInitiated: false) }
    }

    /// Numeric dotted comparison: 1.10.0 > 1.9.3. Pre-release suffixes ("-beta") are ignored.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let parse = { (s: String) in s.split(separator: "-")[0].split(separator: ".").map { Int($0) ?? 0 } }
        let x = parse(a), y = parse(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    func request(_ path: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/\(path)")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("helloship-updater", forHTTPHeaderField: "User-Agent")   // generic; no user or machine data
        req.timeoutInterval = 15
        return req
    }

    /// Fetch latest.json and, with signed updates on, latest.json.sig. An unsigned or tampered manifest → nil.
    static func fetchManifest(_ done: @escaping (Data?, Error?) -> Void) {
        func get(_ url: URL, _ cb: @escaping (Data?, Error?) -> Void) {
            var req = URLRequest(url: url)
            req.setValue("helloship-updater", forHTTPHeaderField: "User-Agent")   // generic; no user or machine data
            req.timeoutInterval = 15
            URLSession.shared.dataTask(with: req) { d, r, e in
                cb((r as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false ? d : nil, e)
            }.resume()
        }
        get(manifestURL) { body, error in
            guard let body, !publicKey.isEmpty else { return done(body, error) }
            get(manifestURL.appendingPathExtension("sig")) { sig, e in
                let ok = sig.flatMap { String(data: $0, encoding: .utf8) }.map { signatureOK(body, sig: $0, key: publicKey) } ?? false
                if !ok { NSLog("HelloShip: update manifest signature invalid or missing: ignored") }
                done(ok ? body : nil, e)
            }
        }
    }

    /// Reads latest.json (the release manifest shipcrate publishes with every release) and picks the macOS build.
    func check(userInitiated: Bool, then done: ((Release?) -> Void)? = nil) {
        if userInitiated { status = "Checking for updates…" }
        Self.fetchManifest { [weak self] data, error in
            guard let self else { return }
            // A check the user asked for ignores staged rollout; automatic checks respect it.
            let found = data.flatMap { Self.parseManifest($0, current: self.current, bucket: userInitiated ? 0 : Self.rolloutBucket) }
            let ann = data.flatMap { Announcement.parse($0, current: self.current) }
            DispatchQueue.main.async {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
                self.available = found
                done?(found)
                if let found, done == nil { self.onUpdateAvailable?(found) }   // hand it to your own notification system
                if let ann, UserDefaults.standard.string(forKey: "seenAnnouncement") != ann.id {
                    UserDefaults.standard.set(ann.id, forKey: "seenAnnouncement")
                    if let hook = self.onAnnouncement { hook(ann) } else { self.announcement = ann }
                }
                if userInitiated {
                    self.status = error != nil ? "Couldn't reach the update server. Try again later."
                        : found == nil ? "You're on the latest version (\(self.current))." : nil
                    if found == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.status = nil } }
                }
            }
        }
    }

    /// Parse latest.json; returns a release only if it's newer and its download is from an allowed host.
    /// The rollout percent at `now`: fixed ("rollout"), or growing to 100% over "rollout_days" after "published".
    static func effectiveRollout(_ j: [String: Any], now: Date = Date()) -> Int {
        let days = (j["rollout_days"] as? Int).map { max(0, min(365, $0)) } ?? 0
        let start = (j["rollout"] as? Int).map { max(0, min(100, $0)) } ?? (days > 0 ? 0 : 100)
        guard days > 0, let p = (j["published"] as? String).flatMap({ ISO8601DateFormatter().date(from: $0) }) else { return start }
        let done = min(max(0, now.timeIntervalSince(p)), Double(days) * 86400)
        return min(100, start + Int(Double(100 - start) * done / (Double(days) * 86400)))
    }

    static func parseManifest(_ data: Data, current: String, bucket: Int = 0, now: Date = Date()) -> Release? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let v = (j["version"] as? String).map({ $0.hasPrefix("v") ? String($0.dropFirst()) : $0 }),
              let assets = j["assets"] as? [String: Any],
              let a = (assets["macos"] ?? assets["macos-universal"] ?? assets["macos-arm64"]) as? [String: Any],
              let z = (a["url"] as? String).flatMap(URL.init(string:)), Self.downloadAllowed(z),
              let sha = (a["sha256"] as? String)?.lowercased(), sha.count == 64 else { return nil }
        let yanked = ((j["yanked"] as? [String]) ?? []).map { $0.hasPrefix("v") ? String($0.dropFirst()) : $0 }.contains(current) && v != current
        let rollout = effectiveRollout(j, now: now)
        let notes = j["notes"] as? String ?? ""
        let security = (j["security"] as? Bool ?? false) || notes.range(of: "[security]", options: .caseInsensitive) != nil
        // Pulled version → always offer the way back; security → always; otherwise newer and inside the rollout.
        guard yanked || (isNewer(v, than: current) && (security || bucket < rollout)) else { return nil }
        let page = (j["page"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://github.com/\(repo)/releases")!
        var r = Release(version: v, notes: notes, zipURL: z, sha256: sha, pageURL: page, security: security)
        r.replacesYanked = yanked
        return r
    }

    /// Ask, then download → verify → replace → relaunch.
    func promptInstall() {
        guard let r = available else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = r.isSecurity ? .critical : .informational
        alert.messageText = r.replacesYanked ? "HelloShip \(current) was pulled: please switch to \(r.version)"
            : r.isSecurity ? "Security update: HelloShip \(r.version)" : "HelloShip \(r.version) is available"
        let notes = r.notes.count > 600 ? String(r.notes.prefix(600)) + "…" : r.notes
        alert.informativeText = "You have \(current).\n\n\(notes)"
        alert.addButton(withTitle: "Update & Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Release page")
        switch alert.runModal() {
        case .alertFirstButtonReturn: install(r)
        case .alertThirdButtonReturn: NSWorkspace.shared.open(r.pageURL)
        default: break
        }
    }

    /// First launch after an update: fetch this version's notes into `whatsNew`. Returns true if the version changed.
    @discardableResult
    func announceLaunch() -> Bool {
        let d = UserDefaults.standard
        let last = d.string(forKey: "lastSeenVersion")
        d.set(current, forKey: "lastSeenVersion")
        guard let last, last != current else { return false }
        URLSession.shared.dataTask(with: request("releases/tags/v\(current)")) { data, _, _ in
            let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["body"] as? String ?? ""
            DispatchQueue.main.async { self.whatsNew = body }
        }.resume()
        return true
    }

    private func fail(_ msg: String) {
        DispatchQueue.main.async { self.status = "Update failed: \(msg)"; NSLog("HelloShip update failed: %@", msg) }
    }

    /// Check and install right away, without asking (for a `--update-now` command-line flag or a menu item).
    func updateNow() {
        check(userInitiated: true) { [weak self] r in
            if let r { self?.install(r) } else { print(self?.status ?? "No update") }
        }
    }

    func install(_ r: Release) {
        status = "Downloading \(r.version)…"
        let target = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            return fail("no permission to replace \(target.path). Download it from the release page instead.")
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let expected = r.sha256
                let zip = try Data(contentsOf: r.zipURL)
                let actual = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
                guard actual == expected else { return self.fail("checksum mismatch — download rejected") }

                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("helloship-update-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                let zipFile = tmp.appendingPathComponent(Self.asset)
                try zip.write(to: zipFile)
                guard Self.run("/usr/bin/ditto", ["-x", "-k", zipFile.path, tmp.path]) == 0 else { return self.fail("couldn't unzip") }
                let newApp = tmp.appendingPathComponent(target.lastPathComponent)
                guard Bundle(url: newApp)?.bundleIdentifier == Self.bundleID,
                      Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]) == 0
                else { return self.fail("downloaded app failed verification") }

                // Swap after we quit, then relaunch. Paths are passed as arguments, never interpolated into the script.
                let script = """
                while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
                /bin/rm -rf "$2.old" && /bin/mv "$2" "$2.old" && /bin/mv "$3" "$2" && /bin/rm -rf "$2.old" "$4"
                /usr/bin/xattr -dr com.apple.quarantine "$2" 2>/dev/null
                /usr/bin/open "$2"
                """
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = ["-c", script, "helloship-update", String(getpid()), target.path, newApp.path, tmp.path]
                try p.run()
                DispatchQueue.main.async { NSApp.terminate(nil) }
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
    }
}

/// The orange "Update" pill (red for security releases). Shows nothing when you're up to date.
struct UpdateButton: View {
    @ObservedObject var updater: Updater
    var body: some View {
        if let r = updater.available {
            Button(action: { updater.promptInstall() }) {
                Label(r.replacesYanked ? "Switch version" : r.isSecurity ? "Security update" : "Update", systemImage: r.isSecurity ? "exclamationmark.shield.fill" : "arrow.down.circle.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(r.isSecurity || r.replacesYanked ? Color.red : Color.orange))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .help("\(r.version) is available — you have \(updater.current)")
        } else if let s = updater.status {
            Text(s).font(.caption).foregroundColor(.secondary)
        }
    }
}

/// A dismissible banner for publisher announcements (scripts/announce.sh).
struct AnnouncementBanner: View {
    @ObservedObject var updater: Updater
    var body: some View {
        if let a = updater.announcement {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: a.level == "info" ? "info.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(a.level == "security" ? .red : a.level == "warning" ? .orange : .accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.message).font(.caption)
                    if let u = a.url { Link("Learn more", destination: u).font(.caption.weight(.semibold)) }
                }
                Spacer(minLength: 0)
                Button { updater.announcement = nil } label: { Image(systemName: "xmark").font(.caption2) }.buttonStyle(.plain)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        }
    }
}
