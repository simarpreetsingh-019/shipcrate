// In-app updater for {{PRODUCT}} (from shipcrate, extracted from Thermo's).
// Checks GitHub Releases at most once a day with one anonymous GET (no telemetry, nothing about the user is sent),
// shows an orange Update button, and on request downloads {{ASSET}}, verifies its SHA-256 against the checksum file
// published with the release, checks the bundle ID and code signature, swaps the app in place and relaunches.
// Releases whose notes contain "[security]" (scripts/release.sh --security) get a stronger, red notice.
// Opt out: `defaults write {{BUNDLE_ID}} autoUpdateCheck -bool false` or the {{ENV}}_NO_UPDATE_CHECK env var.
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
    let shaURL: URL
    let pageURL: URL
    var isSecurity: Bool { notes.range(of: "[security]", options: .caseInsensitive) != nil }
}

final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "{{REPO}}"
    static let bundleID = "{{BUNDLE_ID}}"
    static let asset = "{{ASSET}}"

    @Published var available: Release?
    @Published var status: String?          // progress / error text for the UI
    @Published var whatsNew: String?        // release notes to show once after an update
    @Published var autoCheck: Bool { didSet { UserDefaults.standard.set(autoCheck, forKey: "autoUpdateCheck") } }
    private var timer: Timer?

    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    init() {
        autoCheck = UserDefaults.standard.object(forKey: "autoUpdateCheck") as? Bool ?? true
        if ProcessInfo.processInfo.environment["{{ENV}}_NO_UPDATE_CHECK"] != nil { autoCheck = false }
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

    private func request(_ path: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/\(path)")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("{{TOKEN}}-updater", forHTTPHeaderField: "User-Agent")   // generic; no user or machine data
        req.timeoutInterval = 15
        return req
    }

    func check(userInitiated: Bool, then done: ((Release?) -> Void)? = nil) {
        if userInitiated { status = "Checking for updates…" }
        URLSession.shared.dataTask(with: request("releases/latest")) { [weak self] data, _, error in
            guard let self else { return }
            var found: Release?
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String,
               let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
               let assets = json["assets"] as? [[String: Any]] {
                let url = { (name: String) in
                    (assets.first { $0["name"] as? String == name }?["browser_download_url"] as? String).flatMap(URL.init(string:))
                }
                let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                if let z = url(Self.asset), let s = url(Self.asset + ".sha256"),
                   z.host == "github.com", s.host == "github.com",       // only ever download from GitHub
                   Self.isNewer(v, than: self.current) {
                    found = Release(version: v, notes: json["body"] as? String ?? "", zipURL: z, shaURL: s, pageURL: page)
                }
            }
            DispatchQueue.main.async {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
                self.available = found
                done?(found)
                if userInitiated {
                    self.status = error != nil ? "Couldn't reach GitHub. Try again later."
                        : found == nil ? "You're on the latest version (\(self.current))." : nil
                    if found == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.status = nil } }
                }
            }
        }.resume()
    }

    /// Ask, then download → verify → replace → relaunch.
    func promptInstall() {
        guard let r = available else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = r.isSecurity ? .critical : .informational
        alert.messageText = r.isSecurity ? "Security update: {{PRODUCT}} \(r.version)" : "{{PRODUCT}} \(r.version) is available"
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
        DispatchQueue.main.async { self.status = "Update failed: \(msg)"; NSLog("{{PRODUCT}} update failed: %@", msg) }
    }

    private func install(_ r: Release) {
        status = "Downloading \(r.version)…"
        let target = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            return fail("no permission to replace \(target.path). Download it from the release page instead.")
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let shaText = try String(contentsOf: r.shaURL, encoding: .utf8)
                guard let expected = shaText.split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init)?.lowercased(),
                      expected.count == 64 else { return self.fail("invalid checksum file") }
                let zip = try Data(contentsOf: r.zipURL)
                let actual = SHA256.hash(data: zip).map { String(format: "%02x", $0) }.joined()
                guard actual == expected else { return self.fail("checksum mismatch — download rejected") }

                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("{{TOKEN}}-update-\(UUID().uuidString)")
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
                p.arguments = ["-c", script, "{{TOKEN}}-update", String(getpid()), target.path, newApp.path, tmp.path]
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
                Label(r.isSecurity ? "Security update" : "Update", systemImage: r.isSecurity ? "exclamationmark.shield.fill" : "arrow.down.circle.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(r.isSecurity ? Color.red : Color.orange))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .help("\(r.version) is available — you have \(updater.current)")
        } else if let s = updater.status {
            Text(s).font(.caption).foregroundColor(.secondary)
        }
    }
}
