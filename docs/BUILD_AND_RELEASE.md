# Build and release

## Toolchain

| Tool | Version used | Where (dev PC) |
|---|---|---|
| Flutter (stable) | 3.47.6 (Dart 3.13.5) | `D:\dev\f3476\flutter` |
| Android SDK | platform 36, build-tools 36.0.0, platform-tools 37 (Gradle fetches anything else) | `D:\dev\android-sdk` |
| JDK | Temurin 21 | `C:\Program Files\Eclipse Adoptium\jdk-21…` |
| Visual Studio | Build Tools 2022 17.14, "Desktop development with C++" (MSVC 14.44, Windows SDK 10.0.26100) | default location |

`scripts/dev-env.ps1` puts these on PATH for the current PowerShell session only and keeps the
pub and Gradle caches on `D:\dev`. Override locations with `CAFEDESK_FLUTTER` and
`CAFEDESK_ANDROID_SDK`.

`android/gradle.properties` sets `kotlin.incremental=false`: with the pub cache on a different
drive from the project, Kotlin's incremental compiler fails ("this and base files have different
roots"). Full Kotlin compiles of the few plugin sources cost only seconds.

Windows desktop builds also need **Developer Mode** (Settings → System → For developers),
because Flutter links plugins with symlinks.

CaféDesk Online also needs the Visual Studio component **C++ ATL for latest v143 build tools
(x86 & x64)** (`Microsoft.VisualStudio.Component.VC.ATL`): `flutter_secure_storage_windows`
(where the POS keeps its TLS and signing keys) includes `atlstr.h`. Without it the Windows
build stops with `error C1083: Cannot open include file: 'atlstr.h'`. Add it in the Visual
Studio Installer → Modify → Individual components (needs administrator approval).

### Why not the newest Flutter release?

The development PC has **Windows Smart App Control** enforcing. It blocks unsigned executables
that have no reputation yet. Flutter's engine tools (`flutter_tester.exe`, `impellerc.exe`,
`gen_snapshot.exe`) are unsigned, and each release ships new binaries. On 2026-10-10 the newest
stable (3.47.7, one day old) had `impellerc` and `gen_snapshot` blocked; 3.44.9 had
`flutter_tester` blocked; **3.47.6 had every tool allowed**, so the project pins 3.47.6. On a
machine without Smart App Control any current stable works. Re-check before upgrading:
run `flutter test --no-test-assets` and `flutter build apk` once.

The verdicts can change without any change on our side: on **2026-10-11** Smart App Control
started blocking 3.47.6's `android-arm64-release` and `android-arm-release` `gen_snapshot.exe`
(Code Integrity events 3033/3077, the Smart App Control policy), which had built the offline
APK the day before. The Windows release and Android *profile* `gen_snapshot.exe` still ran. A
release APK then has to be built on another machine (or later, once allowed). For phone
testing in the meantime:

```powershell
flutter build apk --profile --target-platform android-arm64   # AOT-compiled, same behaviour
# build\app\outputs\flutter-apk\app-profile.apk — label it a TEST build, not a release
```

The app has no mode-dependent code, so a profile build behaves like a release build; it also
carries the profiling engine (Dart VM service on the phone's loopback only), so it is for
testing, not distribution. Do not turn Smart App Control off to get a build through: on many
Windows 11 versions it cannot be turned back on without a clean install of Windows.

The same policy applies to the app you build: **an unsigned `cafedesk.exe` is blocked on PCs
with Smart App Control enforcing** and triggers SmartScreen warnings elsewhere. Sign it (below).

## Commands

```powershell
. .\scripts\dev-env.ps1
flutter pub get
dart run build_runner build            # after editing Drift tables
.\scripts\check.ps1                    # dart format check + flutter analyze + flutter test --no-test-assets
dart run tool/perf_benchmark.dart      # database timings with 1,000 items / 50,000 bills
.\scripts\build_android.ps1            # release APK into dist\
.\scripts\build_windows.ps1            # release bundle + zip into dist\
flutter test integration_test -d windows   # end-to-end demo sale on a device (see note)
```

The integration test needs a runnable app on the target: on this PC the unsigned debug
`cafedesk.exe` is blocked by Smart App Control, so run it on an Android device or a Windows
PC without Smart App Control.

## Android signing

The repository never contains a signing key. For a distributable APK/AAB the owner creates (or
already has) an upload/release keystore and adds `android/key.properties` (git-ignored):

```properties
storeFile=C:/secure/cafedesk-release.jks
storePassword=…
keyAlias=cafedesk
keyPassword=…
```

Create a keystore (keep it and its passwords backed up offline — losing it means users cannot
update the app):

```powershell
& "$env:JAVA_HOME\bin\keytool.exe" -genkeypair -v -keystore C:\secure\cafedesk-release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias cafedesk
```

Without `key.properties`, `build_android.ps1` signs with the local **debug** key and names the
file `…-debug-signed.apk`: fine for testing and pilots via sideloading, not for Play Store or
long-term distribution (it cannot be updated by a properly signed build without reinstalling,
which deletes app data — back up first).

Sideload: copy the APK to the device and open it (allow "install unknown apps" for the file
manager), or `adb install -r dist\CafeDesk-….apk`.

## Windows bundle

`build\windows\x64\runner\Release\` is the app. Ship the **whole folder** — `cafedesk.exe`,
`flutter_windows.dll`, plugin DLLs, the SQLite DLL produced by the `sqlite3` package's build
hook, and the `data\` folder (`app.so`, `icudtl.dat`, `flutter_assets\`). A lone EXE does not
run. `build_windows.ps1` checks the core files exist and zips the folder.

Clean-machine install: unzip to e.g. `C:\Program Files\CafeDesk\` (or any local folder), create
a shortcut to `cafedesk.exe`. The Visual C++ runtime DLLs Flutter needs are not part of the
bundle; if a PC lacks them, install the "Microsoft Visual C++ 2015–2022 Redistributable (x64)"
from Microsoft. Data goes to `%APPDATA%\com.cafedesk\cafedesk\` automatically.

### Code signing (needed for Smart App Control / SmartScreen)

Get an Authenticode code-signing certificate (an OV/EV certificate from a public CA, or Azure
Trusted Signing), then sign every EXE/DLL in the bundle before zipping:

```powershell
signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /a build\windows\x64\runner\Release\cafedesk.exe
signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /a build\windows\x64\runner\Release\*.dll
```

A self-signed certificate does not satisfy Smart App Control.

An installer (MSIX or Inno Setup) is optional; MSIX also requires a trusted signature. The zip
plus shortcut is the documented install path for the pilot.

## Versioning

Bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`) and `AppInfo.version/build` in
`lib/core/app_info.dart` together. Android uses the build number as `versionCode`.

## Release checklist

1. `.\scripts\check.ps1` green.
2. Build both targets; record artifact names, sizes and SHA-256 in `docs/PROGRESS.md`.
3. Sign (Android key, Windows certificate).
4. Run `docs/MANUAL_TEST_CHECKLIST.md` on the real café devices and printers.
5. Back up the café's data before upgrading an installed version.
