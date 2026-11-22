# shipcrate-installer: 1
# hello-ship installer for Windows (PowerShell 5+). Reads the release manifest, downloads the build for this PC,
# checks its SHA-256, installs it to %LOCALAPPDATA%\Programs\hello-ship and adds that folder to your user PATH.
#
#   irm https://raw.githubusercontent.com/you/hello-ship/main/install.ps1 -OutFile install.ps1
#   notepad install.ps1      # read it first: it's short
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# Options (environment): $env:INSTALL_DIR, $env:VERSION (default latest), $env:MANIFEST_URL (a mirror you trust)
$ErrorActionPreference = "Stop"
$Repo = "you/hello-ship"; $Binary = "hello-ship"; $Name = "hello-ship"
function Fail($m) { Write-Host "x $m`n  Nothing was installed."; exit 1 }

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
$default = if ($env:VERSION) { "https://github.com/$Repo/releases/download/v$($env:VERSION.TrimStart('v'))/latest.json" }
           else { "https://github.com/$Repo/releases/latest/download/latest.json" }
$manifestUrl = if ($env:MANIFEST_URL) { $env:MANIFEST_URL } else { $default }
Write-Host "-> Reading the $Name release manifest..."
try { $m = Invoke-RestMethod -Uri $manifestUrl -UseBasicParsing } catch { Fail "couldn't read $manifestUrl" }
$a = $m.assets."windows-$arch"; if (-not $a) { $a = $m.assets.any }
if (-not $a) { Fail "release $($m.tag) has no build for windows-$arch." }
if ($a.sha256 -notmatch '^[0-9a-f]{64}$') { Fail "the manifest has no valid checksum." }
if ($a.name -match '[\\/]|^\.\.') { Fail "bad file name in the manifest." }
if ($manifestUrl -eq $default -and -not $a.url.StartsWith("https://github.com/$Repo/releases/download/")) { Fail "unexpected download location: $($a.url)" }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("$Binary-" + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
try {
  $file = Join-Path $tmp $a.name
  Write-Host "-> Downloading $Name $($m.tag) ($($a.name))..."
  Invoke-WebRequest -Uri $a.url -OutFile $file -UseBasicParsing
  $actual = (Get-FileHash -Algorithm SHA256 $file).Hash.ToLower()
  if ($actual -ne $a.sha256) { Fail "checksum mismatch: the download doesn't match the release." }
  Write-Host "ok Checksum matches the release ($actual)"
  if (Get-Command gh -ErrorAction SilentlyContinue) {
    gh attestation verify $file --repo $Repo *> $null
    if ($LASTEXITCODE -eq 0) { Write-Host "ok GitHub attestation: published by $Repo" } else { Write-Host "- GitHub attestation not checked" }
  }
  Expand-Archive -Path $file -DestinationPath (Join-Path $tmp "x")
  $exe = Join-Path $tmp "x\$Binary.exe"; if (-not (Test-Path $exe)) { Fail "no $Binary.exe inside the archive." }
  $dest = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\$Binary" }
  New-Item -ItemType Directory -Force $dest | Out-Null
  $target = Join-Path $dest "$Binary.exe"
  if (Test-Path $target) { Move-Item -Force $target (Join-Path $dest ".$Binary.old.exe") }   # kept for rollback
  Copy-Item $exe $target
  Write-Host "ok Installed $target ($($m.tag))"
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if (($userPath -split ';') -notcontains $dest) {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$dest", "User")
    Write-Host "  Added $dest to your PATH (open a new terminal)."
  }
} finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
