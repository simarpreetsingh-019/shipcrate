# Parses a PowerShell script without running it; exits 1 on syntax errors. Used by tests/test-init.sh and CI.
param([string]$Path)
$errs = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $Path), [ref]$null, [ref]$errs) | Out-Null
if ($errs) { $errs | ForEach-Object { Write-Host $_ }; exit 1 }
