"""Update notice and `hello-py upgrade` for hello-py (from shipcrate). Standard library only.

Privacy: at most once a day, one anonymous GET of the release manifest (latest.json on GitHub Releases).
Nothing about the user or machine is sent; no telemetry. Off with HELLO_PY_NO_UPDATE_CHECK=1; never runs in CI
or without a terminal.

Use:
    from . import update_check
    update_check.notify(__version__)                 # built-in one-line notice after an interactive command
    latest = update_check.check(__version__)         # or feed your own notification system
    print(update_check.upgrade(__version__))         # `hello-py upgrade` (rollback=True for --rollback)
Announcements (scripts/announce.sh) print once per message inside notify(); or read them with announcement().
Beta channel: HELLO_PY_CHANNEL=beta reads the beta manifest (pre-releases plus every stable release).
Staged rollouts ("rollout": N) and pulled versions ("yanked") are handled for you.
A mirror or your own update server: HELLO_PY_UPDATE_MANIFEST=https://…/latest.json (same format).
"""
import hashlib, io, json, os, platform, shutil, sys, tarfile, tempfile, time, urllib.request, zipfile
from pathlib import Path

REPO = "you/hello-py"
BINARY = "hello-py"
OPT_OUT = "HELLO_PY_NO_UPDATE_CHECK"
MANIFEST_ENV = "HELLO_PY_UPDATE_MANIFEST"
CHANNEL_ENV = "HELLO_PY_CHANNEL"
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


def loopback_origin(url):
    """'http://127.0.0.1:8000/' for a loopback http URL (demos, local testing), else None. Never the network."""
    if not url.startswith("http://"):
        return None
    host = url[7:].split("/")[0]
    name = host.rsplit(":", 1)[0] if ":" in host and not host.endswith("]") else host
    return f"http://{host}/" if name in ("127.0.0.1", "localhost", "[::1]") else None


class Policy:
    """Where downloads may come from. The default manifest only allows this project's GitHub releases."""
    def __init__(self, manifest=None, url_prefix=None, allow_file=False):
        env = os.environ.get(MANIFEST_ENV, "")
        self.local = None
        if manifest is None and env.startswith("https://"):
            manifest, url_prefix = env, "https://"
        elif manifest is None and loopback_origin(env):
            manifest, url_prefix = env, loopback_origin(env)
            self.local = url_prefix
        beta = os.environ.get(CHANNEL_ENV) == "beta"
        self.manifest = manifest or (f"https://github.com/{REPO}/releases/download/channel/beta.json" if beta
                                     else f"https://github.com/{REPO}/releases/latest/download/latest.json")
        self.url_prefix = url_prefix or f"https://github.com/{REPO}/releases/download/"
        self.allow_file = allow_file  # tests only

    def get(self, url, timeout=15):
        if not (url.startswith("https://") or (self.allow_file and url.startswith("file://"))
                or (self.local and url.startswith(self.local))):
            raise ValueError(f"refusing {url}")
        req = urllib.request.Request(url, headers={"User-Agent": "hello-py-update-check"})
        with urllib.request.urlopen(req, timeout=timeout) as r:  # noqa: S310 (scheme checked above)
            return r.read()


def clean(text, limit):
    """Strip control characters (terminal escape sequences) and cap length: messages come from the network."""
    text = str(text or "").replace("\n", " ").replace("\t", " ")
    return "".join(c for c in text if c.isprintable())[:limit]


def _announcement(a):
    if not isinstance(a, dict):
        return None
    url = str(a.get("url") or "")
    ann = {"id": clean(a.get("id"), 64), "level": clean(a.get("level"), 16), "message": clean(a.get("message"), 280),
           "url": clean(url, 300) if url.startswith("https://") else "", "below": clean(a.get("below"), 32)}
    return ann if ann["id"] and ann["message"] else None


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
            "notes": notes, "security": bool(j.get("security")) or "[security]" in notes.lower(), "asset": asset,
            "announcement": _announcement(j.get("announcement")),
            "yanked": [clean(v, 32).lstrip("v") for v in (j.get("yanked") or []) if isinstance(v, str)],
            "rollout": max(0, min(100, int(j.get("rollout", 100)))) if isinstance(j.get("rollout", 100), (int, float)) else 100}


def is_yanked(latest, current):
    return current.lstrip("v") in (latest.get("yanked") or [])


def offered_to(latest, current, bucket):
    """Yanked → always (if there's somewhere to go); security → always; otherwise by rollout bucket."""
    if is_yanked(latest, current):
        return latest["version"] != current.lstrip("v")
    return is_newer(latest["version"], current) and (latest.get("security") or bucket < latest.get("rollout", 100))


def rollout_bucket():
    """This copy's bucket, 0-99: random once, kept locally, never sent anywhere."""
    f = _cache_file().with_name("rollout-bucket")
    try:
        b = int(f.read_text().strip())
        if 0 <= b < 100:
            return b
    except (OSError, ValueError):
        pass
    import random
    b = random.SystemRandom().randrange(100)
    try:
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(str(b))
    except OSError:
        pass
    return b


def fetch_latest(policy=None):
    policy = policy or Policy()
    try:
        return parse_manifest(policy.get(policy.manifest), platform_key(), policy)
    except Exception:
        return None


def _cache_file():
    base = os.environ.get("XDG_CACHE_HOME") or os.environ.get("LOCALAPPDATA") or Path.home() / ".cache"
    return Path(base) / "hello-py" / "update-check.json"


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


def _latest_cached():
    """The manifest, fetched at most once a day. None when checks aren't allowed."""
    if not checks_allowed():
        return None
    f = _cache_file()
    try:
        cached = json.loads(f.read_text(encoding="utf-8"))
    except Exception:
        cached = {}
    if time.time() - cached.get("checked", 0) < DAY:
        return cached.get("latest")
    latest = fetch_latest()
    try:
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(json.dumps({"checked": time.time(), "latest": latest}), encoding="utf-8")
    except OSError:
        pass
    return latest


def check(current):
    """Cached daily check for interactive use. Returns the newer release (dict) or None."""
    latest = _latest_cached()
    return latest if latest and offered_to(latest, current, rollout_bucket()) else None


def announcement(current):
    """The publisher's announcement if it applies to this version and wasn't shown yet; marks it shown."""
    a = (_latest_cached() or {}).get("announcement")
    if not a or (a.get("below") and not is_newer(a["below"], current)):
        return None
    seen = _cache_file().with_name("announcement-seen")
    try:
        if seen.read_text(encoding="utf-8").strip() == a["id"]:
            return None
    except OSError:
        pass
    try:
        seen.write_text(a["id"], encoding="utf-8")
    except OSError:
        pass
    return a


def announcement_line(a):
    tag = {"security": "⚠️  SECURITY NOTICE", "warning": "⚠️  NOTICE"}.get(a["level"], "ℹ️ ")
    return f"{tag} {BINARY}: {a['message']}" + (f" · {a['url']}" if a["url"] else "")


def notice_line(latest, current):
    if is_yanked(latest, current):
        return (f"⚠️  {BINARY} {current} was pulled by its publisher. Run `{_how()}` to move to {latest['version']} · "
                f"{latest['page']}")
    if latest["security"]:
        return (f"⚠️  SECURITY UPDATE: {BINARY} {latest['version']} fixes a security issue (you have {current}). "
                f"Run `{_how()}` · {latest['page']}")
    return f"{BINARY} {latest['version']} is available (you have {current}) · `{_how()}` · what's new: {latest['page']}"


def notify(current):
    latest = check(current)
    if latest:
        print("\n" + notice_line(latest, current), file=sys.stderr)
    a = announcement(current)
    if a:
        print(announcement_line(a), file=sys.stderr)


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
    # An explicit upgrade ignores staged rollout; a pulled (yanked) version may move back to an older good one.
    if not is_newer(latest["version"], current) and not (is_yanked(latest, current) and latest["version"] != current.lstrip("v")):
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
