//! Update notice and `{{BINARY}} upgrade` for {{PRODUCT}} (from shipcrate). Standard library only:
//! it shells out to `curl` and `tar`, which macOS, Linux and Windows 10+ ship.
//!
//! Privacy: at most once a day, one anonymous GET of the release manifest (latest.json on GitHub Releases).
//! Nothing about the user or machine is sent; no telemetry. Off with `{{ENV}}_NO_UPDATE_CHECK=1`;
//! never runs in CI or without a terminal.
//!
//! Use (in main.rs):  `mod update;`
//!   built-in one-line notice after an interactive command:  update::notify(env!("CARGO_PKG_VERSION"));
//!   your own notification system instead:  if let Some(l) = update::check(env!("CARGO_PKG_VERSION")) { my_notify(&l) }
//!   `{{BINARY}} upgrade [--rollback]`:  update::upgrade(env!("CARGO_PKG_VERSION"), rollback)
//! Announcements (scripts/announce.sh) print once per message, inside `notify`; or read them with `announcement()`.
//! Beta channel: `{{ENV}}_CHANNEL=beta` reads the beta manifest (pre-releases plus every stable release).
//! Staged rollouts (`"rollout": N`) and pulled versions (`"yanked"`) are handled for you.
//! A mirror or your own update server: set `{{ENV}}_UPDATE_MANIFEST=https://…/latest.json` (same format).

use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub const REPO: &str = "{{REPO}}";
pub const BINARY: &str = "{{BINARY}}";
const OPT_OUT: &str = "{{ENV}}_NO_UPDATE_CHECK";
const MANIFEST_ENV: &str = "{{ENV}}_UPDATE_MANIFEST";
const CHANNEL_ENV: &str = "{{ENV}}_CHANNEL";
const CACHE_DIR: &str = "{{TOKEN}}";
const DAY: u64 = 86_400;

#[derive(Debug, Clone, PartialEq)]
pub struct Asset {
    pub name: String,
    pub url: String,
    pub sha256: String,
}

/// A one-off message from the publisher (scripts/announce.sh). Display-only text; never acted on.
#[derive(Debug, Clone, PartialEq)]
pub struct Announcement {
    pub id: String,
    pub level: String, // info | warning | security
    pub message: String,
    pub url: String,   // https only, or empty
    pub below: String, // only for versions older than this, or empty for everyone
}

#[derive(Debug, Clone, PartialEq)]
pub struct Latest {
    pub version: String,
    pub page: String,
    pub notes: String,
    pub security: bool,
    /// The build for this machine, if the release has one.
    pub asset: Option<Asset>,
    pub announcement: Option<Announcement>,
    /// Versions the publisher pulled (scripts/yank.sh). Copies on one of these are moved to `version`.
    pub yanked: Vec<String>,
    /// Staged rollout percent (scripts/rollout.sh); 100 = everyone.
    pub rollout: u8,
}

impl Latest {
    pub fn is_yanked(&self, current: &str) -> bool {
        self.yanked.iter().any(|y| y.trim_start_matches('v') == current.trim_start_matches('v'))
    }
    /// Should this copy be told about the release? Yanked → always; security → always; else by rollout bucket.
    pub fn offered_to(&self, current: &str, bucket: u8) -> bool {
        if self.is_yanked(current) {
            return self.version != current.trim_start_matches('v');
        }
        is_newer(&self.version, current) && (self.security || bucket < self.rollout)
    }
}

/// Remove control characters (terminal escape sequences) and cap the length: messages come from the network.
pub fn clean(s: &str, max: usize) -> String {
    s.chars().map(|c| if c == '\n' || c == '\t' { ' ' } else { c }).filter(|c| !c.is_control()).take(max).collect()
}

// ---------- tiny JSON reader (enough for latest.json; avoids a dependency) ----------
#[derive(Debug, Clone, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<Json>),
    Obj(BTreeMap<String, Json>),
}

impl Json {
    pub fn parse(s: &str) -> Option<Json> {
        let mut p = Parser { b: s.as_bytes(), i: 0 };
        let v = p.value()?;
        p.ws();
        (p.i == p.b.len()).then_some(v)
    }
    pub fn get(&self, k: &str) -> Option<&Json> {
        if let Json::Obj(m) = self { m.get(k) } else { None }
    }
    pub fn str(&self) -> Option<&str> {
        if let Json::Str(s) = self { Some(s) } else { None }
    }
}

struct Parser<'a> {
    b: &'a [u8],
    i: usize,
}

impl Parser<'_> {
    fn ws(&mut self) {
        while self.i < self.b.len() && self.b[self.i].is_ascii_whitespace() {
            self.i += 1;
        }
    }
    fn eat(&mut self, c: u8) -> Option<()> {
        self.ws();
        (self.b.get(self.i) == Some(&c)).then(|| self.i += 1)
    }
    fn value(&mut self) -> Option<Json> {
        self.ws();
        match *self.b.get(self.i)? {
            b'{' => {
                self.i += 1;
                let mut m = BTreeMap::new();
                if self.eat(b'}').is_some() {
                    return Some(Json::Obj(m));
                }
                loop {
                    self.ws();
                    let k = self.string()?;
                    self.eat(b':')?;
                    m.insert(k, self.value()?);
                    if self.eat(b',').is_none() {
                        self.eat(b'}')?;
                        return Some(Json::Obj(m));
                    }
                }
            }
            b'[' => {
                self.i += 1;
                let mut v = Vec::new();
                if self.eat(b']').is_some() {
                    return Some(Json::Arr(v));
                }
                loop {
                    v.push(self.value()?);
                    if self.eat(b',').is_none() {
                        self.eat(b']')?;
                        return Some(Json::Arr(v));
                    }
                }
            }
            b'"' => self.string().map(Json::Str),
            b't' => self.lit("true", Json::Bool(true)),
            b'f' => self.lit("false", Json::Bool(false)),
            b'n' => self.lit("null", Json::Null),
            _ => {
                let start = self.i;
                while self.i < self.b.len() && b"+-.eE0123456789".contains(&self.b[self.i]) {
                    self.i += 1;
                }
                std::str::from_utf8(&self.b[start..self.i]).ok()?.parse().ok().map(Json::Num)
            }
        }
    }
    fn lit(&mut self, w: &str, v: Json) -> Option<Json> {
        self.b[self.i..].starts_with(w.as_bytes()).then(|| { self.i += w.len(); v })
    }
    fn string(&mut self) -> Option<String> {
        if self.b.get(self.i) != Some(&b'"') {
            return None;
        }
        self.i += 1;
        let mut out = Vec::new();
        loop {
            let c = *self.b.get(self.i)?;
            self.i += 1;
            match c {
                b'"' => return String::from_utf8(out).ok(),
                b'\\' => {
                    let e = *self.b.get(self.i)?;
                    self.i += 1;
                    match e {
                        b'n' => out.push(b'\n'),
                        b't' => out.push(b'\t'),
                        b'r' => out.push(b'\r'),
                        b'b' | b'f' => {}
                        b'u' => {
                            let hex = std::str::from_utf8(self.b.get(self.i..self.i + 4)?).ok()?;
                            self.i += 4;
                            let ch = char::from_u32(u32::from_str_radix(hex, 16).ok()?).unwrap_or('\u{fffd}');
                            out.extend_from_slice(ch.to_string().as_bytes());
                        }
                        other => out.push(other),
                    }
                }
                c => out.push(c),
            }
        }
    }
}

// ---------- policy ----------
fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// Interactive use only: never in CI, scripts, pipes, or when opted out.
pub fn checks_allowed() -> bool {
    env::var_os(OPT_OUT).is_none() && env::var_os("CI").is_none() && std::io::stderr().is_terminal() && std::io::stdout().is_terminal()
}

/// Numeric dotted comparison: 1.10.0 > 1.9.3; a leading "v" is ignored; 1.0.0 > 1.0.0-beta.
pub fn is_newer(a: &str, b: &str) -> bool {
    let parse = |s: &str| -> (Vec<u64>, bool) {
        let s = s.trim().trim_start_matches('v');
        let (core, pre) = match s.split_once('-') { Some((c, _)) => (c, true), None => (s, false) };
        (core.split('.').map(|p| p.parse().unwrap_or(0)).collect(), pre)
    };
    let ((x, xp), (y, yp)) = (parse(a), parse(b));
    for i in 0..x.len().max(y.len()) {
        let (p, q) = (*x.get(i).unwrap_or(&0), *y.get(i).unwrap_or(&0));
        if p != q {
            return p > q;
        }
    }
    yp && !xp
}

/// This machine's target key in latest.json, e.g. "macos-arm64", "linux-x64", "windows-x64".
pub fn platform_key() -> String {
    let os = match env::consts::OS { "macos" => "macos", "windows" => "windows", "linux" => "linux", o => o };
    let arch = match env::consts::ARCH { "aarch64" => "arm64", "x86_64" => "x64", a => a };
    format!("{os}-{arch}")
}

pub fn default_manifest_url() -> String {
    if env::var(CHANNEL_ENV).map(|c| c == "beta").unwrap_or(false) {
        format!("https://github.com/{REPO}/releases/download/channel/beta.json")
    } else {
        format!("https://github.com/{REPO}/releases/latest/download/latest.json")
    }
}

/// Where downloads may come from. The default manifest only allows this project's GitHub releases.
#[derive(Clone)]
pub struct Policy {
    pub manifest: String,
    pub url_prefix: String,
    pub allow_file: bool, // tests only
}

impl Policy {
    pub fn from_env() -> Policy {
        match env::var(MANIFEST_ENV) {
            Ok(m) if m.starts_with("https://") => Policy { manifest: m, url_prefix: "https://".into(), allow_file: false },
            _ => Policy { manifest: default_manifest_url(), url_prefix: format!("https://github.com/{REPO}/releases/download/"), allow_file: false },
        }
    }
    fn proto(&self) -> &str {
        if self.allow_file { "=https,file" } else { "=https" }
    }
}

fn curl(p: &Policy, args: &[&str]) -> Option<Vec<u8>> {
    let out = Command::new("curl")
        .args(["-fsSL", "--max-time", "120", "--proto", p.proto(), "-A", "{{TOKEN}}-update-check"])
        .args(args)
        .output()
        .ok()?;
    out.status.success().then_some(out.stdout)
}

/// Turn manifest JSON into `Latest`, choosing this machine's asset (os-arch, then os, then any).
pub fn parse_manifest(body: &str, key: &str, p: &Policy) -> Option<Latest> {
    let j = Json::parse(body)?;
    let version = j.get("version")?.str()?.trim_start_matches('v').to_string();
    let os = key.split('-').next().unwrap_or("");
    let assets = j.get("assets");
    let asset = [key, os, "any"].iter().find_map(|k| assets?.get(k)).and_then(|a| {
        let asset = Asset { name: a.get("name")?.str()?.into(), url: a.get("url")?.str()?.into(), sha256: a.get("sha256")?.str()?.to_lowercase() };
        let ok_url = asset.url.starts_with(&p.url_prefix) || (p.allow_file && asset.url.starts_with("file://"));
        let ok_sha = asset.sha256.len() == 64 && asset.sha256.bytes().all(|c| c.is_ascii_hexdigit());
        let ok_name = !asset.name.is_empty() && !asset.name.contains(['/', '\\']) && !asset.name.starts_with("..");
        (ok_url && ok_sha && ok_name).then_some(asset)
    });
    let notes = j.get("notes").and_then(Json::str).unwrap_or("").to_string();
    let announcement = j.get("announcement").and_then(|a| {
        let f = |k: &str| a.get(k).and_then(Json::str).unwrap_or("").to_string();
        let url = f("url");
        let ann = Announcement { id: clean(&f("id"), 64), level: clean(&f("level"), 16), message: clean(&f("message"), 280),
            url: if url.starts_with("https://") { clean(&url, 300) } else { String::new() }, below: clean(&f("below"), 32) };
        (!ann.id.is_empty() && !ann.message.is_empty()).then_some(ann)
    });
    let yanked = match j.get("yanked") {
        Some(Json::Arr(v)) => v.iter().filter_map(Json::str).map(|s| clean(s, 32)).collect(),
        _ => Vec::new(),
    };
    let rollout = match j.get("rollout") { Some(Json::Num(n)) => n.clamp(0.0, 100.0) as u8, _ => 100 };
    Some(Latest {
        yanked,
        rollout,
        announcement,
        page: j.get("page").and_then(Json::str).map(String::from).unwrap_or_else(|| format!("https://github.com/{REPO}/releases")),
        security: matches!(j.get("security"), Some(Json::Bool(true))) || notes.to_lowercase().contains("[security]"),
        version,
        notes,
        asset,
    })
}

pub fn fetch_latest(p: &Policy) -> Option<Latest> {
    let body = String::from_utf8(curl(p, &[&p.manifest])?).ok()?;
    parse_manifest(&body, &platform_key(), p)
}

fn cache_file() -> Option<PathBuf> {
    let base = env::var_os("XDG_CACHE_HOME").map(PathBuf::from)
        .or_else(|| env::var_os("LOCALAPPDATA").map(PathBuf::from))
        .or_else(|| env::var_os("HOME").map(|h| Path::new(&h).join(".cache")))?;
    Some(base.join(CACHE_DIR).join("update-check"))
}

fn to_cache(l: &Latest) -> String {
    let a = l.announcement.clone().unwrap_or(Announcement { id: String::new(), level: String::new(), message: String::new(), url: String::new(), below: String::new() });
    format!("{}\n{}\n{}\n{}\n{}\n{}\n{}\n{}\n{}\n{}\n{}\n", now(), l.version, l.page, l.security as u8, a.id, a.level, a.url, a.below, a.message, l.rollout, l.yanked.join(","))
}

fn from_cache(text: &str) -> Option<(u64, Option<Latest>)> {
    let v: Vec<&str> = text.lines().collect();
    let stamp = v.first()?.parse().ok()?;
    if v.len() < 4 {
        return Some((stamp, None));
    }
    let g = |i: usize| v.get(i).copied().unwrap_or("").to_string();
    let announcement = (!g(4).is_empty()).then(|| Announcement { id: g(4), level: g(5), url: g(6), below: g(7), message: g(8) });
    let yanked = g(10).split(',').filter(|s| !s.is_empty()).map(String::from).collect();
    Some((stamp, Some(Latest { version: g(1), page: g(2), notes: String::new(), security: g(3) == "1", asset: None, announcement, rollout: g(9).parse().unwrap_or(100), yanked })))
}

/// The manifest, fetched at most once a day (cached on disk). None when checks aren't allowed.
fn latest_cached() -> Option<Latest> {
    if !checks_allowed() {
        return None;
    }
    let path = cache_file()?;
    if let Some((stamp, l)) = fs::read_to_string(&path).ok().as_deref().and_then(from_cache) {
        if now().saturating_sub(stamp) < DAY {
            return l;
        }
    }
    let l = fetch_latest(&Policy::from_env());
    if let Some(dir) = path.parent() {
        let _ = fs::create_dir_all(dir);
    }
    let _ = fs::write(&path, l.as_ref().map(to_cache).unwrap_or_else(|| format!("{}\n", now())));
    l
}

/// Cached daily check for interactive use. Returns the newer release, if any. Use this to feed your own
/// notification system; `notify` is the built-in one-line version.
pub fn check(current: &str) -> Option<Latest> {
    latest_cached().filter(|l| l.offered_to(current, rollout_bucket()))
}

/// This copy's rollout bucket, 0-99: picked at random once and kept locally. Never sent anywhere.
pub fn rollout_bucket() -> u8 {
    let Some(f) = cache_file().map(|c| c.with_file_name("rollout-bucket")) else { return 0 };
    if let Some(b) = fs::read_to_string(&f).ok().and_then(|s| s.trim().parse::<u8>().ok()).filter(|b| *b < 100) {
        return b;
    }
    let seed = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.subsec_nanos() as u64 ^ d.as_secs()).unwrap_or(0) ^ std::process::id() as u64;
    let b = (seed % 100) as u8;
    let _ = fs::write(&f, b.to_string());
    b
}

/// The publisher's current announcement, if it applies to this version and hasn't been shown yet.
/// Marks it as shown. Use it to route messages into your own UI; `notify` prints it for you.
pub fn announcement(current: &str) -> Option<Announcement> {
    let a = latest_cached()?.announcement?;
    if !a.below.is_empty() && !is_newer(&a.below, current) {
        return None;
    }
    let seen = cache_file()?.with_file_name("announcement-seen");
    if fs::read_to_string(&seen).map(|s| s.trim() == a.id).unwrap_or(false) {
        return None;
    }
    let _ = fs::write(&seen, &a.id);
    Some(a)
}

pub fn announcement_line(a: &Announcement) -> String {
    let tag = match a.level.as_str() { "security" => "⚠️  SECURITY NOTICE", "warning" => "⚠️  NOTICE", _ => "ℹ️ " };
    if a.url.is_empty() { format!("{tag} {BINARY}: {}", a.message) } else { format!("{tag} {BINARY}: {} · {}", a.message, a.url) }
}

/// Built-in notice: one line on stderr after a command when a newer version exists.
pub fn notify(current: &str) {
    if let Some(l) = check(current) {
        eprintln!("\n{}", notice_line(&l, current));
    }
    if let Some(a) = announcement(current) {
        eprintln!("{}", announcement_line(&a));
    }
}

pub fn notice_line(l: &Latest, current: &str) -> String {
    let how = if is_homebrew() { format!("brew upgrade {BINARY}") } else { format!("{BINARY} upgrade") };
    if l.is_yanked(current) {
        format!("⚠️  {BINARY} {current} was pulled by its publisher. Run `{how}` to move to {} · {}", l.version, l.page)
    } else if l.security {
        format!("⚠️  SECURITY UPDATE: {BINARY} {} fixes a security issue (you have {current}). Run `{how}` · {}", l.version, l.page)
    } else {
        format!("{BINARY} {} is available (you have {current}) · `{how}` · what's new: {}", l.version, l.page)
    }
}

fn current_exe() -> Result<PathBuf, String> {
    env::current_exe().and_then(|p| p.canonicalize()).map_err(|e| format!("can't find this executable: {e}"))
}

pub fn is_homebrew() -> bool {
    current_exe().map(|p| { let s = p.to_string_lossy(); s.contains("/Cellar/") || s.contains("/homebrew/") || s.contains("/linuxbrew/") }).unwrap_or(false)
}

/// SHA-256 of a file via the system tools (shasum, sha256sum, or certutil on Windows).
pub fn sha256_file(path: &Path) -> Option<String> {
    let run = |cmd: &str, pre: &[&str], post: &[&str]| {
        Command::new(cmd).args(pre).arg(path).args(post).output().ok().filter(|o| o.status.success()).and_then(|o| String::from_utf8(o.stdout).ok())
    };
    if let Some(s) = run("shasum", &["-a", "256"], &[]).or_else(|| run("sha256sum", &[], &[])) {
        return s.split_whitespace().next().map(str::to_lowercase);
    }
    let s = run("certutil", &["-hashfile"], &["SHA256"])?;
    s.lines().nth(1).map(|l| l.replace(' ', "").to_lowercase())
}

/// `upgrade`: download, verify the checksum, swap atomically, keep the previous binary for `--rollback`.
pub fn upgrade(current: &str, rollback: bool) -> Result<String, String> {
    if is_homebrew() {
        return Err(format!("installed with Homebrew: run `brew upgrade {BINARY}`"));
    }
    upgrade_at(&current_exe()?, current, rollback, &Policy::from_env())
}

pub fn upgrade_at(exe: &Path, current: &str, rollback: bool, p: &Policy) -> Result<String, String> {
    let dir = exe.parent().ok_or("no parent folder")?.to_path_buf();
    let file = exe.file_name().ok_or("bad path")?.to_string_lossy().to_string();
    let old = dir.join(format!(".{file}.old"));
    if rollback {
        if !old.exists() {
            return Err("no previous version kept".into());
        }
        fs::rename(&old, exe).map_err(|e| format!("rollback failed: {e}"))?;
        return Ok("Rolled back to the previous version.".into());
    }
    let body = String::from_utf8(curl(p, &[&p.manifest]).ok_or("couldn't read the release manifest")?).map_err(|_| "bad manifest")?;
    let latest = parse_manifest(&body, &platform_key(), p).ok_or("bad manifest")?;
    // An explicit upgrade ignores staged rollout; a pulled (yanked) version may move back to an older good one.
    if !is_newer(&latest.version, current) && !(latest.is_yanked(current) && latest.version != current.trim_start_matches('v')) {
        return Ok(format!("{BINARY} {current} is the latest version."));
    }
    let asset = latest.asset.ok_or(format!("release {} has no build for {}", latest.version, platform_key()))?;
    let tmp = dir.join(format!(".{BINARY}-upgrade-{}", std::process::id()));
    fs::create_dir_all(&tmp).map_err(|e| format!("can't write to {}: {e}", dir.display()))?;
    let result = (|| {
        let archive = tmp.join(&asset.name);
        let a = archive.to_string_lossy().to_string();
        curl(p, &["-o", &a, &asset.url]).ok_or("download failed")?;
        if sha256_file(&archive).as_deref() != Some(asset.sha256.as_str()) {
            return Err("checksum mismatch: download rejected, nothing changed".to_string());
        }
        let ok = Command::new("tar").args(["-xf", &a, "-C"]).arg(&tmp).status().map(|s| s.success()).unwrap_or(false);
        let new = tmp.join(&file);
        if !ok || !new.is_file() || fs::symlink_metadata(&new).map(|m| m.file_type().is_symlink()).unwrap_or(true) {
            return Err("couldn't unpack the release".into());
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&new, fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
        }
        let staged = dir.join(format!(".{file}.new"));
        fs::rename(&new, &staged).map_err(|e| e.to_string())?;
        let _ = fs::remove_file(&old);
        // Keep the current binary as .old (rename works even while it's running, on Windows too), then move the new one in.
        fs::rename(exe, &old).map_err(|e| format!("couldn't keep the previous version: {e}"))?;
        if let Err(e) = fs::rename(&staged, exe) {
            let _ = fs::rename(&old, exe); // put the old one back
            return Err(format!("swap failed: {e}"));
        }
        Ok(format!("Upgraded {BINARY} {current} → {}. Undo with `{BINARY} upgrade --rollback`.", latest.version))
    })();
    let _ = fs::remove_dir_all(&tmp);
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_policy(manifest: &Path) -> Policy {
        Policy { manifest: format!("file://{}", manifest.display()), url_prefix: "https://github.com/".into(), allow_file: true }
    }

    #[test]
    fn versions() {
        assert!(is_newer("1.10.0", "1.9.9"));
        assert!(is_newer("v2.0.0", "1.99"));
        assert!(is_newer("1.0.0", "1.0.0-beta.2"));
        assert!(!is_newer("1.0.0", "1.0.0"));
        assert!(!is_newer("1.0.0-beta", "1.0.0"));
        assert!(!is_newer("garbage", "0.0.1"));
    }

    #[test]
    fn json_parser() {
        let j = Json::parse(r#"{"a": [1, true, null, "x\"\né"], "b": {"c": "d"}}"#).unwrap();
        assert_eq!(j.get("b").and_then(|b| b.get("c")).and_then(Json::str), Some("d"));
        assert!(Json::parse("{\"a\": 1").is_none());
        assert!(Json::parse("{} trailing").is_none());
    }

    fn manifest(url: &str, sha: &str) -> String {
        format!(r#"{{"version":"9.9.9","page":"https://github.com/{REPO}/releases/tag/v9.9.9","security":true,"notes":"fix","assets":{{"{}":{{"name":"x.tar.gz","url":"{url}","sha256":"{sha}"}}}}}}"#, platform_key())
    }

    #[test]
    fn manifest_rules() {
        let p = Policy { manifest: String::new(), url_prefix: format!("https://github.com/{REPO}/releases/download/"), allow_file: false };
        let good = format!("https://github.com/{REPO}/releases/download/v9.9.9/x.tar.gz");
        let l = parse_manifest(&manifest(&good, &"a".repeat(64)), &platform_key(), &p).unwrap();
        assert!(l.security && l.asset.is_some());
        // downloads from anywhere else, bad checksums and file:// are refused
        assert!(parse_manifest(&manifest("https://evil.example/x.tar.gz", &"a".repeat(64)), &platform_key(), &p).unwrap().asset.is_none());
        assert!(parse_manifest(&manifest(&good, "abc"), &platform_key(), &p).unwrap().asset.is_none());
        assert!(parse_manifest(&manifest("file:///tmp/x.tar.gz", &"a".repeat(64)), &platform_key(), &p).unwrap().asset.is_none());
    }

    #[test]
    fn rollout_yank_and_cache() {
        let p = Policy { manifest: String::new(), url_prefix: "https://github.com/".into(), allow_file: false };
        let l = parse_manifest(r#"{"version":"1.2.0","rollout":25,"yanked":["1.3.0"]}"#, "k", &p).unwrap();
        assert!(l.offered_to("1.0.0", 10) && !l.offered_to("1.0.0", 60)); // inside / outside the 25%
        assert!(l.offered_to("1.3.0", 99)); // pulled version: always told, even outside the rollout
        assert!(!l.offered_to("1.2.0", 0));
        let sec = parse_manifest(r#"{"version":"1.2.0","rollout":0,"security":true}"#, "k", &p).unwrap();
        assert!(sec.offered_to("1.0.0", 99)); // security ignores rollout
        let back = from_cache(&to_cache(&l)).unwrap().1.unwrap();
        assert_eq!((back.rollout, back.yanked.clone()), (25, vec!["1.3.0".to_string()]));
        assert!(notice_line(&l, "1.3.0").contains("pulled"));
    }

    #[test]
    fn announcements_are_cleaned_and_cached() {
        let p = Policy { manifest: String::new(), url_prefix: "https://github.com/".into(), allow_file: false };
        let body = r#"{"version":"1.0.0","announcement":{"id":"a1","level":"warning","message":"hi\u001b[31m there\nok","url":"javascript:x","below":"2.0.0"}}"#;
        let l = parse_manifest(body, &platform_key(), &p).unwrap();
        let a = l.announcement.clone().unwrap();
        assert_eq!(a.message, "hi[31m there ok"); // escape sequence and newline stripped
        assert_eq!(a.url, ""); // only https links
        let back = from_cache(&to_cache(&l)).unwrap().1.unwrap();
        assert_eq!(back.announcement, l.announcement);
        assert!(parse_manifest(r#"{"version":"1.0.0","announcement":{"id":"","message":"x"}}"#, "x", &p).unwrap().announcement.is_none());
    }

    #[cfg(unix)]
    #[test]
    fn upgrade_end_to_end_with_checksum_and_rollback() {
        let root = env::temp_dir().join(format!("{BINARY}-upgrade-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let (bin, rel) = (root.join("bin"), root.join("rel"));
        fs::create_dir_all(&bin).unwrap();
        fs::create_dir_all(&rel).unwrap();
        let exe = bin.join(BINARY);
        fs::write(&exe, "old").unwrap();
        fs::write(rel.join(BINARY), "new").unwrap();
        assert!(Command::new("tar").args(["-czf", "x.tar.gz", BINARY]).current_dir(&rel).status().unwrap().success());
        let url = format!("file://{}", rel.join("x.tar.gz").display());
        let m = rel.join("latest.json");

        // tampered: wrong checksum → nothing changes
        fs::write(&m, manifest(&url, &"0".repeat(64))).unwrap();
        assert!(upgrade_at(&exe, "1.0.0", false, &test_policy(&m)).unwrap_err().contains("checksum"));
        assert_eq!(fs::read_to_string(&exe).unwrap(), "old");

        // good: swapped, previous kept, rollback restores
        let sha = sha256_file(&rel.join("x.tar.gz")).unwrap();
        fs::write(&m, manifest(&url, &sha)).unwrap();
        assert!(upgrade_at(&exe, "1.0.0", false, &test_policy(&m)).unwrap().contains("9.9.9"));
        assert_eq!(fs::read_to_string(&exe).unwrap(), "new");
        assert!(upgrade_at(&exe, "9.9.9", false, &test_policy(&m)).unwrap().contains("latest"));
        upgrade_at(&exe, "9.9.9", true, &test_policy(&m)).unwrap();
        assert_eq!(fs::read_to_string(&exe).unwrap(), "old");
        // a yanked newer version moves back to the manifest's (older) good version
        fs::write(&m, manifest(&url, &sha).replace(r#""notes":"fix""#, r#""notes":"fix","yanked":["10.0.0"]"#)).unwrap();
        assert!(upgrade_at(&exe, "10.0.0", false, &test_policy(&m)).unwrap().contains("9.9.9"));
        assert_eq!(fs::read_to_string(&exe).unwrap(), "new");
        let _ = fs::remove_dir_all(&root);
    }
}
