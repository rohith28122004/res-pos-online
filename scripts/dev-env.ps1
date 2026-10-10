# Dot-source this file in PowerShell to put the local toolchains on PATH for the
# current shell only:   . .\scripts\dev-env.ps1
# Adjust the paths if your SDKs live elsewhere. Nothing here is persisted.

# Flutter 3.47.6 (stable): on this PC Smart App Control blocks unsigned engine
# tools that have no reputation yet (the newest release's tools are blocked);
# 3.47.6's tools all run. See docs/BUILD_AND_RELEASE.md.
$env:FLUTTER_ROOT = if ($env:CAFEDESK_FLUTTER) { $env:CAFEDESK_FLUTTER } else { 'D:\dev\f3476\flutter' }
$env:ANDROID_HOME = if ($env:CAFEDESK_ANDROID_SDK) { $env:CAFEDESK_ANDROID_SDK } else { 'D:\dev\android-sdk' }
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
if (-not $env:JAVA_HOME) {
  $jdk = Get-ChildItem 'C:\Program Files\Eclipse Adoptium' -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($jdk) { $env:JAVA_HOME = $jdk.FullName }
}
# Keep large caches off the system drive when D: exists.
if (Test-Path 'D:\') {
  if (-not $env:PUB_CACHE) { $env:PUB_CACHE = 'D:\dev\pub-cache' }
  if (-not $env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME = 'D:\dev\gradle-home' }
  if (-not $env:ANDROID_AVD_HOME) { $env:ANDROID_AVD_HOME = 'D:\dev\avd' }
}
$env:PATH = "$env:FLUTTER_ROOT\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"
Write-Host "Flutter: $env:FLUTTER_ROOT  Android SDK: $env:ANDROID_HOME  JAVA_HOME: $env:JAVA_HOME"
