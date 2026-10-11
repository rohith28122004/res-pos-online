# Runs `flutter test` on a PC where Smart App Control blocks the downloaded,
# unsigned sqlite3.dll (it did on the dev PC from 2026-10-11): the tests then
# use Windows' own Microsoft-signed SQLite (C:\Windows\System32\winsqlite3.dll).
#
#   .\scripts\test-local.ps1                      # all tests
#   .\scripts\test-local.ps1 test/connected       # any flutter test arguments
#
# It adds `hooks: user_defines` for the sqlite3 package to pubspec.yaml for the
# run only and always restores the file. Builds (APK, Windows bundle) keep the
# bundled SQLite: older Windows 10 PCs may ship an old winsqlite3.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'dev-env.ps1') | Out-Null
$pubspec = Join-Path $root 'pubspec.yaml'
$original = [System.IO.File]::ReadAllText($pubspec)
if ($original -match '(?m)^hooks:') { throw 'pubspec.yaml already has a hooks: section; restore it first.' }
$defines = @"

hooks:
  user_defines:
    sqlite3:
      source:
        windows: system
        default: sqlite3
      name_windows: winsqlite3
"@
Push-Location $root
try {
  [System.IO.File]::WriteAllText($pubspec, $original.TrimEnd() + "`n" + $defines)
  flutter test @args
  $code = $LASTEXITCODE
} finally {
  [System.IO.File]::WriteAllText($pubspec, $original)
  Pop-Location
}
exit $code
