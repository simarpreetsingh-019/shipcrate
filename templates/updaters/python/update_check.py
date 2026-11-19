"""Update notice and `{{BINARY}} upgrade` for {{PRODUCT}} (from shipcrate). Standard library only.

Privacy: at most once a day, one anonymous GET of the release manifest (latest.json on GitHub Releases).
Nothing about the user or machine is sent; no telemetry. Off with {{ENV}}_NO_UPDATE_CHECK=1; never runs in CI
or without a terminal.

Use:
    from . import update_check
    update_check.notify(__version__)                 # built-in one-line notice after an interactive command
    latest = update_check.check(__version__)         # or feed your own notification system
    print(update_check.upgrade(__version__))         # `{{BINARY}} upgrade` (rollback=True for --rollback)
A mirror or your own update server: {{ENV}}_UPDATE_MANIFEST=https://…/latest.json (same format).
"""
import hashlib, io, json, os, platform, shutil, sys, tarfile, tempfile, time, urllib.request, zipfile
from pathlib import Path

REPO = "{{REPO}}"
BINARY = "{{BINARY}}"
OPT_OUT = "{{ENV}}_NO_UPDATE_CHECK"
MANIFEST_ENV = "{{ENV}}_UPDATE_MANIFEST"
DAY = 86400


def checks_allowed():
    return not os.environ.get(OPT_OUT) and not os.environ.get("CI") and sys.stderr.isatty() and sys.stdout.isatty()


def is_newer(a, b):
    """1.10.0 > 1.9.3; a leading v is ignored; 1.0.0 > 1.0.0-beta."""
    def parse(s):
        s = s.strip().lstrip("v")
        core, _, pre = s.partition("-")
        return [int(p) if p.isdigit() else 0 for p in core.split(".")], bool(pre)
    (x, xp), (y, yp) = parse(a), parse(b)
    n = max(len(x), len(y))
    x, y = x + [0] * (n - len(x)), y + [0] * (n - len(y))
    return x > y if x != y else (yp and not xp)


def platform_key():
    s = sys.platform
    os_ = "macos" if s == "darwin" else "windows" if s.startswith("win") else "linux"
    m = platform.machine().lower()
    arch = "arm64" if m in ("arm64", "aarch64") else "x64" if m in ("x86_64", "amd64") else m
    return f"{os_}-{arch}"


class Policy:
    """Where downloads may come from. The default manifest only allows this project's GitHub releases."""
    def __init__(self, manifest=None, url_prefix=None, allow_file=False):
        env = os.environ.get(MANIFEST_ENV, "")
        if manifest is None and env.startswith("https://"):
            manifest, url_prefix = env, "https://"
        self.manifest = manifest or f"https://github.com/{REPO}/releases/latest/download/latest.json"
        self.url_prefix = url_prefix or f"https://github.com/{REPO}/releases/download/"
        self.allow_file = allow_file  # tests only

    def get(self, url, timeout=15):
        if not (url.startswith("https://") or (self.allow_file and url.startswith("file://"))):
            raise ValueError(f"refusing {url}")
        req = urllib.request.Request(url, headers={"User-Agent": "{{TOKEN}}-update-check"})
        with urllib.request.urlopen(req, timeout=timeout) as r:  # noqa: S310 (scheme checked above)
            return r.read()


def parse_manifest(body, key, policy):
    j = json.loads(body)
    asset = None
    for k in (key, key.split("-")[0], "any"):
        a = (j.get("assets") or {}).get(k)
        if not a:
            continue
        name, url, sha = a.get("name", ""), a.get("url", ""), a.get("sha256", "").lower()
        ok_url = url.startswith(policy.url_prefix) or (policy.allow_file and url.startswith("file://"))
        ok_sha = len(sha) == 64 and all(c in "0123456789abcdef" for c in sha)
        ok_name = name and "/" not in name and "\\" not in name and not name.startswith("..")
        if ok_url and ok_sha and ok_name:
            asset = {"name": name, "url": url, "sha256": sha}
        break
    notes = j.get("notes") or ""
    return {"version": str(j["version"]).lstrip("v"), "page": j.get("page") or f"https://github.com/{REPO}/releases",
            "notes": notes, "security": bool(j.get("security")) or "[security]" in notes.lower(), "asset": asset}


def fetch_latest(policy=None):
    policy = policy or Policy()
    try:
        return parse_manifest(policy.get(policy.manifest), platform_key(), policy)
    except Exception:
        return None


def _cache_file():
    base = os.environ.get("XDG_CACHE_HOME") or os.environ.get("LOCALAPPDATA") or Path.home() / ".cache"
    return Path(base) / "{{TOKEN}}" / "update-check.json"


def is_homebrew():
    p = str(Path(sys.argv[0]).resolve())
    return any(s in p for s in ("/Cellar/", "/homebrew/", "/linuxbrew/"))


def _package_managed():
    return "site-packages" in __file__ or "dist-packages" in __file__


def _how():
    if is_homebrew():
        return f"brew upgrade {BINARY}"
    if _package_managed():
        return f"pipx upgrade {BINARY}  (or pip install -U {BINARY})"
    return f"{BINARY} upgrade"


def check(current):
    """Cached daily check for interactive use. Returns the newer release (dict) or None."""
    if not checks_allowed():
        return None
    f = _cache_file()
    try:
        cached = json.loads(f.read_text(encoding="utf-8"))
    except Exception:
        cached = {}
    if time.time() - cached.get("checked", 0) < DAY:
        latest = cached.get("latest")
    else:
        latest = fetch_latest()
        try:
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text(json.dumps({"checked": time.time(), "latest": latest}), encoding="utf-8")
        except OSError:
            pass
    return latest if latest and is_newer(latest["version"], current) else None


def notice_line(latest, current):
    if latest["security"]:
        return (f"⚠️  SECURITY UPDATE: {BINARY} {latest['version']} fixes a security issue (you have {current}). "
                f"Run `{_how()}` · {latest['page']}")
    return f"{BINARY} {latest['version']} is available (you have {current}) · `{_how()}` · what's new: {latest['page']}"


def notify(current):
    latest = check(current)
    if latest:
        print("\n" + notice_line(latest, current), file=sys.stderr)


def upgrade(current, rollback=False):
    """For single-file installs (install.sh / release archive). pip/pipx/Homebrew installs are told what to run."""
    if is_homebrew() or _package_managed():
        return f"Installed with a package manager: run `{_how()}`."
    return upgrade_at(Path(sys.argv[0]).resolve(), current, rollback, Policy())


def upgrade_at(exe, current, rollback, policy):
    exe = Path(exe)
    old = exe.with_name(f".{exe.name}.old")
    if rollback:
        if not old.exists():
            return "No previous version kept."
        os.replace(old, exe)
        return "Rolled back to the previous version."
    try:
        latest = parse_manifest(policy.get(policy.manifest), platform_key(), policy)
    except Exception:
        return "Couldn't read the release manifest."
    if not is_newer(latest["version"], current):
        return f"{BINARY} {current} is the latest version."
    a = latest["asset"]
    if not a:
        return f"Release {latest['version']} has no build for {platform_key()}."
    data = policy.get(a["url"], timeout=120)
    if hashlib.sha256(data).hexdigest() != a["sha256"]:
        return "Checksum mismatch: download rejected, nothing changed."
    want = {exe.name, f"./{exe.name}"}
    if a["name"].endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            names = [n for n in z.namelist() if n in want]
            payload = z.read(names[0]) if names else None
    else:
        with tarfile.open(fileobj=io.BytesIO(data)) as t:
            m = next((m for m in t.getmembers() if m.name in want and m.isfile()), None)
            f = t.extractfile(m) if m else None
            payload = f.read() if f else None
    if payload is None:
        return "Couldn't unpack the release."
    staged = exe.with_name(f".{exe.name}.new")
    staged.write_bytes(payload)
    staged.chmod(0o755)
    if old.exists():
        old.unlink()
    os.replace(exe, old)          # keep the previous version for --rollback
    try:
        os.replace(staged, exe)   # atomic on the same filesystem
    except OSError:
        os.replace(old, exe)
        return "Swap failed; nothing changed."
    return f"Upgraded {BINARY} {current} → {latest['version']}. Undo with `{BINARY} upgrade --rollback`."
