"""Update notice and `{{BINARY}} upgrade` for {{PRODUCT}} (from shipcrate). Standard library only.

Privacy: at most once a day, one anonymous GET to GitHub's latest-release API. Nothing about the user or
machine is sent; no telemetry. Off with {{ENV}}_NO_UPDATE_CHECK=1, and never in CI or without a terminal.

Use:
    from . import update_check
    update_check.notify(__version__)              # after an interactive command
    print(update_check.upgrade(__version__))      # `{{BINARY}} upgrade` (rollback=True for --rollback)
"""
import hashlib, json, os, shutil, sys, tarfile, tempfile, time, urllib.request
from pathlib import Path

REPO = "{{REPO}}"
ASSET = "{{ASSET}}"
BINARY = "{{BINARY}}"
OPT_OUT = "{{ENV}}_NO_UPDATE_CHECK"
DAY = 86400


def checks_allowed():
    return not os.environ.get(OPT_OUT) and not os.environ.get("CI") and sys.stderr.isatty() and sys.stdout.isatty()


def is_newer(a, b):
    def parse(s):
        return [int(p) if p.isdigit() else 0 for p in s.lstrip("v").split("-")[0].split(".")]
    x, y = parse(a), parse(b)
    n = max(len(x), len(y))
    return (x + [0] * (n - len(x))) > (y + [0] * (n - len(y)))


def _get(url, timeout=10):
    req = urllib.request.Request(url, headers={"User-Agent": "{{TOKEN}}-update-check", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:  # noqa: S310 (fixed https URLs only)
        return r.read()


def fetch_latest():
    try:
        data = json.loads(_get(f"https://api.github.com/repos/{REPO}/releases/latest"))
        tag = data["tag_name"]
        return {"version": tag.lstrip("v"), "page": f"https://github.com/{REPO}/releases/tag/{tag}",
                "security": "[security]" in (data.get("body") or "").lower()}
    except Exception:
        return None


def _cache_file():
    base = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    return base / "{{TOKEN}}" / "update-check.json"


def is_homebrew():
    p = str(Path(sys.argv[0]).resolve())
    return "/Cellar/" in p or "/homebrew/" in p


def _how():
    if is_homebrew():
        return f"brew upgrade {BINARY}"
    if "site-packages" in __file__ or "dist-packages" in __file__:
        return f"pipx upgrade {BINARY}  (or pip install -U {BINARY})"
    return f"{BINARY} upgrade"


def notify(current):
    """Cached daily check; prints one line to stderr when a newer version exists."""
    if not checks_allowed():
        return
    f = _cache_file()
    try:
        cached = json.loads(f.read_text())
    except Exception:
        cached = {}
    if time.time() - cached.get("checked", 0) < DAY:
        latest = cached.get("latest")
    else:
        latest = fetch_latest()
        try:
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text(json.dumps({"checked": time.time(), "latest": latest}))
        except OSError:
            pass
    if latest and is_newer(latest["version"], current):
        if latest["security"]:
            print(f"\n⚠️  SECURITY UPDATE: {BINARY} {latest['version']} fixes a security issue (you have {current}). "
                  f"Run `{_how()}` · {latest['page']}", file=sys.stderr)
        else:
            print(f"\n{BINARY} {latest['version']} is available (you have {current}) · `{_how()}` · what's new: {latest['page']}",
                  file=sys.stderr)


def upgrade(current, rollback=False):
    """For single-file installs (install.sh / release archive). pip/pipx/Homebrew installs are told what to run."""
    if is_homebrew() or "site-packages" in __file__:
        return f"Installed with a package manager: run `{_how()}`."
    exe = Path(sys.argv[0]).resolve()
    old = exe.with_name(f".{exe.name}.old")
    if rollback:
        if not old.exists():
            return "No previous version kept."
        os.replace(old, exe)
        return "Rolled back to the previous version."
    latest = fetch_latest()
    if not latest:
        return "Couldn't reach GitHub."
    if not is_newer(latest["version"], current):
        return f"{BINARY} {current} is the latest version."
    base = f"https://github.com/{REPO}/releases/download/v{latest['version']}"
    with tempfile.TemporaryDirectory(dir=exe.parent) as tmp:
        archive = Path(tmp) / ASSET
        archive.write_bytes(_get(f"{base}/{ASSET}", timeout=120))
        expected = _get(f"{base}/{ASSET}.sha256").decode().split()[0].lower()
        if len(expected) != 64 or hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
            return "Checksum mismatch: download rejected, nothing changed."
        with tarfile.open(archive) as t:
            member = t.getmember(f"./{BINARY}") if f"./{BINARY}" in t.getnames() else t.getmember(BINARY)
            src = t.extractfile(member)
            if src is None:
                return "Couldn't unpack the release."
            staged = exe.with_name(f".{exe.name}.new")
            staged.write_bytes(src.read())
        staged.chmod(0o755)
        shutil.copy2(exe, old)          # keep the previous version for --rollback
        os.replace(staged, exe)         # atomic on the same filesystem
    return f"Upgraded {BINARY} {current} → {latest['version']}. Undo with `{BINARY} upgrade --rollback`."
