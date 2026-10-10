# Builds the Windows release bundle and zips the whole folder (EXE + DLLs + data).
#   .\scripts\build_windows.ps1
# Requires Visual Studio 2022 "Desktop development with C++" and Windows
# Developer Mode (Flutter needs symlinks for plugins).
# The output is UNSIGNED. Smart App Control / SmartScreen block unsigned apps on
# many PCs; sign cafedesk_online.exe and the DLLs with your code-signing certificate
# before distributing (see docs/BUILD_AND_RELEASE.md).
# Native tools write warnings to stderr; judge success by exit codes, not stderr.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'dev-env.ps1')
Set-Location $root

flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$bundle = Join-Path $root 'build\windows\x64\runner\Release'
$required = @('cafedesk_online.exe', 'flutter_windows.dll', 'data\icudtl.dat', 'data\app.so', 'data\flutter_assets')
foreach ($r in $required) {
  if (-not (Test-Path (Join-Path $bundle $r))) { throw "Bundle is missing $r" }
}
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "CafeDeskOnline-$version-windows-x64-unsigned.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $zip
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
"$hash  $(Split-Path $zip -Leaf)" | Set-Content -Encoding ascii "$zip.sha256"
Write-Host "Windows bundle folder: $bundle"
Write-Host "Zip: $zip"
Write-Host "Files in bundle:"
Get-ChildItem -Recurse -File $bundle | ForEach-Object { '  ' + $_.FullName.Substring($bundle.Length + 1) }
