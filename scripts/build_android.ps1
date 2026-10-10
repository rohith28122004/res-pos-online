# Builds the Android release APK.
#   .\scripts\build_android.ps1
# Signing: uses android\key.properties when present (owner's private key —
# never committed). Without it the APK is signed with the local DEBUG key and
# is labelled "debug-signed" — fine for testing, not for distribution.
# Native tools write warnings to stderr; judge success by exit codes, not stderr.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'dev-env.ps1')
Set-Location $root

$signed = Test-Path (Join-Path $root 'android\key.properties')
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build apk failed' }

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$label = if ($signed) { 'release-signed' } else { 'debug-signed' }
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$out = Join-Path $dist "CafeDeskOnline-$version-android-$label.apk"
Copy-Item 'build\app\outputs\flutter-apk\app-release.apk' $out -Force
$hash = (Get-FileHash $out -Algorithm SHA256).Hash.ToLower()
"$hash  $(Split-Path $out -Leaf)" | Set-Content -Encoding ascii "$out.sha256"
Write-Host "APK: $out ($label)"
Write-Host "SHA-256: $hash"
if (-not $signed) { Write-Warning 'Debug-signed: for testing only. Configure android\key.properties for a distributable build.' }
