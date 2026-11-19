//! Update notice and `{{BINARY}} upgrade` for {{PRODUCT}} (from shipcrate). Standard library only:
//! it shells out to `curl`, `tar` and `shasum`/`sha256sum`, which macOS and Linux ship.
//!
//! Privacy: at most once a day, one anonymous GET to GitHub's latest-release API. Nothing about the user
//! or machine is sent; no telemetry. Off with `{{ENV}}_NO_UPDATE_CHECK=1`, and never in CI or without a terminal.
//!
//! Use (in main.rs):  `mod update;`
//!   after an interactive command:   update::notify(env!("CARGO_PKG_VERSION"));
//!   `{{BINARY}} upgrade`:           update::upgrade(env!("CARGO_PKG_VERSION"), false)
//!   `{{BINARY}} upgrade --rollback`: update::upgrade(env!("CARGO_PKG_VERSION"), true)

use std::env;
use std::fs;
use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub const REPO: &str = "{{REPO}}";
pub const ASSET: &str = "{{ASSET}}";
pub const BINARY: &str = "{{BINARY}}";
const OPT_OUT: &str = "{{ENV}}_NO_UPDATE_CHECK";
const CACHE_DIR: &str = "{{TOKEN}}";
const DAY: u64 = 86_400;

#[derive(Debug, Clone, PartialEq)]
pub struct Latest {
    pub version: String,
    pub page: String,
    pub security: bool,
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// Interactive use only: never in CI, scripts, pipes, or when opted out.
pub fn checks_allowed() -> bool {
    env::var_os(OPT_OUT).is_none()
        && env::var_os("CI").is_none()
        && std::io::stderr().is_terminal()
        && std::io::stdout().is_terminal()
}

/// Numeric dotted comparison: 1.10.0 > 1.9.3; a leading "v" and pre-release suffixes are ignored.
pub fn is_newer(a: &str, b: &str) -> bool {
    let parse = |s: &str| -> Vec<u64> {
        s.trim_start_matches('v').split('-').next().unwrap_or("").split('.').map(|p| p.parse().unwrap_or(0)).collect()
    };
    let (x, y) = (parse(a), parse(b));
    for i in 0..x.len().max(y.len()) {
        let (p, q) = (*x.get(i).unwrap_or(&0), *y.get(i).unwrap_or(&0));
        if p != q {
            return p > q;
        }
    }
    false
}

fn cache_file() -> Option<PathBuf> {
    let base = env::var_os("XDG_CACHE_HOME").map(PathBuf::from).or_else(|| env::var_os("HOME").map(|h| Path::new(&h).join(".cache")))?;
    Some(base.join(CACHE_DIR).join("update-check"))
}

fn curl(args: &[&str]) -> Option<Vec<u8>> {
    let out = Command::new("curl").args(["-fsSL", "--max-time", "10", "-A", concat!("{{TOKEN}}-update-check")]).args(args).output().ok()?;
    out.status.success().then_some(out.stdout)
}

/// Value of a top-level JSON string field. Enough for GitHub's release JSON; avoids a JSON dependency.
pub fn json_str(body: &str, key: &str) -> Option<String> {
    let start = body.find(&format!("\"{key}\""))? + key.len() + 2;
    let rest = body[start..].trim_start().strip_prefix(':')?.trim_start().strip_prefix('"')?;
    let (mut out, mut esc) = (String::new(), false);
    for c in rest.chars() {
        match (esc, c) {
            (true, 'n') => { out.push('\n'); esc = false }
            (true, c) => { out.push(c); esc = false }
            (false, '\\') => esc = true,
            (false, '"') => return Some(out),
            (false, c) => out.push(c),
        }
    }
    None
}

pub fn fetch_latest() -> Option<Latest> {
    let body = String::from_utf8(curl(&["-H", "Accept: application/vnd.github+json", &format!("https://api.github.com/repos/{REPO}/releases/latest")])?).ok()?;
    let tag = json_str(&body, "tag_name")?;
    let notes = json_str(&body, "body").unwrap_or_default();
    Some(Latest {
        version: tag.trim_start_matches('v').to_string(),
        page: format!("https://github.com/{REPO}/releases/tag/{tag}"),
        security: notes.to_lowercase().contains("[security]"),
    })
}

/// Cached daily check; prints one line to stderr when a newer version exists.
pub fn notify(current: &str) {
    if !checks_allowed() {
        return;
    }
    let Some(path) = cache_file() else { return };
    let cached = fs::read_to_string(&path).unwrap_or_default();
    let mut lines = cached.lines();
    let stamp: u64 = lines.next().and_then(|s| s.parse().ok()).unwrap_or(0);
    let latest = if now().saturating_sub(stamp) < DAY {
        match (lines.next(), lines.next(), lines.next()) {
            (Some(v), Some(p), Some(s)) => Some(Latest { version: v.into(), page: p.into(), security: s == "1" }),
            _ => None,
        }
    } else {
        let l = fetch_latest();
        if let Some(dir) = path.parent() {
            let _ = fs::create_dir_all(dir);
        }
        let text = match &l {
            Some(l) => format!("{}\n{}\n{}\n{}\n", now(), l.version, l.page, l.security as u8),
            None => format!("{}\n", now()),
        };
        let _ = fs::write(&path, text);
        l
    };
    if let Some(l) = latest.filter(|l| is_newer(&l.version, current)) {
        let how = if is_homebrew() { format!("brew upgrade {BINARY}") } else { format!("{BINARY} upgrade") };
        if l.security {
            eprintln!("\n⚠️  SECURITY UPDATE: {BINARY} {} fixes a security issue (you have {current}). Run `{how}` · {}", l.version, l.page);
        } else {
            eprintln!("\n{BINARY} {} is available (you have {current}) · `{how}` · what's new: {}", l.version, l.page);
        }
    }
}

fn current_exe() -> Result<PathBuf, String> {
    env::current_exe().and_then(|p| p.canonicalize()).map_err(|e| format!("can't find this executable: {e}"))
}

pub fn is_homebrew() -> bool {
    current_exe().map(|p| { let s = p.to_string_lossy(); s.contains("/Cellar/") || s.contains("/homebrew/") }).unwrap_or(false)
}

fn sha256(path: &Path) -> Option<String> {
    let run = |cmd: &str, args: &[&str]| Command::new(cmd).args(args).arg(path).output().ok().filter(|o| o.status.success());
    let out = run("shasum", &["-a", "256"]).or_else(|| run("sha256sum", &[]))?;
    String::from_utf8(out.stdout).ok()?.split_whitespace().next().map(str::to_lowercase)
}

/// Download, verify the checksum, swap atomically, keep the previous binary as `.<name>.old` for `--rollback`.
pub fn upgrade(current: &str, rollback: bool) -> Result<String, String> {
    let exe = current_exe()?;
    let dir = exe.parent().ok_or("no parent folder")?.to_path_buf();
    let old = dir.join(format!(".{BINARY}.old"));
    if is_homebrew() {
        return Err(format!("installed with Homebrew: run `brew upgrade {BINARY}`{}", if rollback { " (or `brew install` an older version)" } else { "" }));
    }
    if rollback {
        if !old.exists() {
            return Err("no previous version kept".into());
        }
        fs::rename(&old, &exe).map_err(|e| format!("rollback failed: {e}"))?;
        return Ok("Rolled back to the previous version.".into());
    }
    let latest = fetch_latest().ok_or("couldn't reach GitHub")?;
    if !is_newer(&latest.version, current) {
        return Ok(format!("{BINARY} {current} is the latest version."));
    }
    let base = format!("https://github.com/{REPO}/releases/download/v{}", latest.version);
    let tmp = dir.join(format!(".{BINARY}-upgrade-{}", std::process::id()));
    fs::create_dir_all(&tmp).map_err(|e| format!("can't write to {}: {e}", dir.display()))?;
    let result = (|| {
        let archive = tmp.join(ASSET);
        let a = archive.to_string_lossy().to_string();
        curl(&["-o", &a, &format!("{base}/{ASSET}")]).ok_or("download failed")?;
        let sums = String::from_utf8(curl(&[&format!("{base}/{ASSET}.sha256")]).ok_or("couldn't get the checksum")?).map_err(|_| "bad checksum file")?;
        let expected = sums.split_whitespace().next().unwrap_or("").to_lowercase();
        if expected.len() != 64 || sha256(&archive).as_deref() != Some(expected.as_str()) {
            return Err("checksum mismatch: download rejected, nothing changed".to_string());
        }
        let ok = Command::new("tar").args(["-xzf", &a, "-C"]).arg(&tmp).status().map(|s| s.success()).unwrap_or(false);
        let new = tmp.join(BINARY);
        if !ok || !new.is_file() {
            return Err("couldn't unpack the release".into());
        }
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&new, fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
        }
        let staged = dir.join(format!(".{BINARY}.new"));
        fs::rename(&new, &staged).map_err(|e| e.to_string())?;
        let _ = fs::remove_file(&old);
        fs::hard_link(&exe, &old).or_else(|_| fs::copy(&exe, &old).map(|_| ())).map_err(|e| format!("couldn't keep the previous version: {e}"))?;
        fs::rename(&staged, &exe).map_err(|e| format!("swap failed: {e}"))?; // atomic on the same filesystem
        Ok(format!("Upgraded {BINARY} {current} → {}. Undo with `{BINARY} upgrade --rollback`.", latest.version))
    })();
    let _ = fs::remove_dir_all(&tmp);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn versions() {
        assert!(is_newer("1.10.0", "1.9.9"));
        assert!(is_newer("v2.0.0", "1.99"));
        assert!(!is_newer("1.0.0", "1.0.0"));
        assert!(!is_newer("1.0.0-beta", "1.0.0"));
    }
    #[test]
    fn json() {
        let b = r#"{"tag_name": "v1.2.3", "body":"fix \"x\"\n[security]"}"#;
        assert_eq!(json_str(b, "tag_name").as_deref(), Some("v1.2.3"));
        assert_eq!(json_str(b, "body").as_deref(), Some("fix \"x\"\n[security]"));
    }
}
