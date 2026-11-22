# Shared helpers for shipcrate scripts (sourced, not run). POSIX sh.
# Targets are "<os>-<arch>" (macos-arm64, macos-x64, linux-x64, linux-arm64, windows-x64, windows-arm64),
# "macos" for a macOS app, or "any" for platform-independent builds (Python zipapp, JS bundle).

# This machine's target, e.g. macos-arm64.
host_target() {
  case "$(uname -s)" in Darwin) os=macos ;; Linux) os=linux ;; MINGW*|MSYS*|CYGWIN*|Windows_NT) os=windows ;; *) os=unknown ;; esac
  case "$(uname -m)" in arm64|aarch64) arch=arm64 ;; x86_64|amd64) arch=x64 ;; *) arch=unknown ;; esac
  echo "$os-$arch"
}

# Release file name for a target: ASSET with {target} filled in; Windows gets .zip instead of .tar.gz.
asset_for() {
  a=$(printf '%s' "$ASSET" | sed "s/{target}/$1/g")
  case "$1" in windows-*) a=$(printf '%s' "$a" | sed 's/\.tar\.gz$/.zip/; s/\.tgz$/.zip/') ;; esac
  echo "$a"
}

# GitHub Actions runner that builds a target natively.
runner_for() {
  case "$1" in
    macos|macos-arm64) echo macos-latest ;;   macos-x64) echo macos-15-intel ;;
    linux-x64|any) echo ubuntu-latest ;;      linux-arm64) echo ubuntu-24.04-arm ;;
    windows-x64) echo windows-latest ;;       windows-arm64) echo windows-11-arm ;;
    *) echo "unknown target $1" >&2; return 1 ;;
  esac
}

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"
  else openssl dgst -sha256 -r "$1"; fi | cut -d' ' -f1 | tr -d '*'
}

# JSON string literal of stdin (escapes \ " control characters, joins lines with \n).
json_string() {
  # sed for the escaping (awk implementations disagree about backslashes in gsub; mawk on Debian/Ubuntu differs)
  TAB=$(printf '\t'); CR=$(printf '\r')
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$TAB/\\\\t/g" -e "s/$CR//g" | awk 'BEGIN{ORS=""; print "\""} { if (NR>1) print "\\n"; print } END{print "\""}'
}

# Set (or with an empty value, remove) a top-level key in a manifest written by manifest.sh.
#   manifest_set FILE KEY 'raw-json-value'
manifest_set() {
  KEY="$2" VAL="$3" awk '
    BEGIN { key = ENVIRON["KEY"]; val = ENVIRON["VAL"]; pat = "^  \"" key "\":" }
    $0 ~ pat { next }
    { lines[++n] = $0 }
    END {
      last = n; while (last > 0 && lines[last] !~ /^}/) last--
      for (i = 1; i < last; i++) {
        l = lines[i]
        if (i == last - 1) { if (val != "") sub(/,?[ ]*$/, ",", l); else sub(/,[ ]*$/, "", l) }
        print l
      }
      if (val != "") print "  \"" key "\": " val
      for (i = last; i <= n; i++) print lines[i]
    }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# Download a release's latest.json into DIR (prints the path).
fetch_manifest() { gh release download "$1" --repo "$REPO" --pattern latest.json --dir "$2" --clobber >/dev/null && echo "$2/latest.json"; }

# ver_gt A B: true if version A is newer than B (semantic versioning: 1.10.0 > 1.10.0-rc.1 > 1.10.0-beta.2 > 1.10.0-beta.1).
ver_gt() {
  awk -v a="${1#v}" -v b="${2#v}" 'function isnum(s) { return s ~ /^[0-9]+$/ }
  BEGIN {
    sub(/\+.*/, "", a); sub(/\+.*/, "", b)
    ca = a; pa = ""; if ((i = index(a, "-")) > 0) { ca = substr(a, 1, i - 1); pa = substr(a, i + 1) }
    cb = b; pb = ""; if ((i = index(b, "-")) > 0) { cb = substr(b, 1, i - 1); pb = substr(b, i + 1) }
    n = split(ca, x, "."); m = split(cb, y, "."); k = n > m ? n : m
    for (i = 1; i <= k; i++) { p = (i <= n ? x[i] + 0 : 0); q = (i <= m ? y[i] + 0 : 0); if (p != q) exit !(p > q) }
    if (pa == "" || pb == "") exit !(pa == "" && pb != "")
    n = split(pa, x, "."); m = split(pb, y, "."); k = n < m ? n : m
    for (i = 1; i <= k; i++) {
      if (x[i] == y[i]) continue
      if (isnum(x[i]) && isnum(y[i])) exit !(x[i] + 0 > y[i] + 0)
      if (isnum(x[i]) != isnum(y[i])) exit !(!isnum(x[i]))
      exit !(x[i] > y[i])
    }
    exit !(n > m)
  }'
}
