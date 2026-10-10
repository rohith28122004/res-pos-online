# Format check, static analysis and all automated tests.
#   .\scripts\check.ps1
# Native tools write warnings to stderr; judge success by exit codes, not stderr.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'dev-env.ps1')
Set-Location $root

dart format --output=none --set-exit-if-changed lib test tool
if ($LASTEXITCODE -ne 0) { Write-Warning 'Formatting differs (run: dart format lib test tool)' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze reported problems' }


flutter test
if ($LASTEXITCODE -ne 0) { throw 'tests failed' }
Write-Host 'All checks passed.'
