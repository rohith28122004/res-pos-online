# Baseline — what CaféDesk Online was built from

| | |
|---|---|
| Source repository | https://github.com/rohith28122004/res-pos (offline CaféDesk) |
| Baseline commit | `f65c4bbc37516a05c3a9625e5d9b9f18de54e3ee` — "feat(auth): email + password sign-in replaces PINs; readable chip labels" |
| Cloned on | 2026-10-11, over HTTPS from GitHub (not from the local offline checkout) |
| This repository | https://github.com/rohith28122004/res-pos-online (private), development branch `connected-pos` |

## Isolation from the offline app

- The clone's `origin` (the source repo) was removed straight after cloning; `origin` now points
  only to `res-pos-online`. Every push is checked against that URL first.
- The source history is kept (`main` here starts at the baseline commit).
- The local offline checkout `C:\Users\rohit\projects\cafedesk`, its GitHub repo, releases and
  installed app data are never read or written by this project.
- No production data is copied. A later, optional import works from a backup **copy** the owner
  picks, with a preview and confirmation; the offline database is never opened.

## Separate application identity

| | CaféDesk (offline, source) | CaféDesk Online (this repo) |
|---|---|---|
| Display name | CaféDesk | CaféDesk Online |
| Android application ID | `com.cafedesk.cafedesk` | `com.cafedesk.online` |
| Windows executable | `cafedesk.exe` | `cafedesk_online.exe` |
| Windows product name (sets the data folder) | `CafeDesk\CafeDesk` | `CafeDesk\CafeDesk Online` |
| Database files | `cafedesk.sqlite`, `cafedesk_demo.sqlite` | `cafedesk_online.sqlite`, `cafedesk_online_demo.sqlite` |
| Single-instance lock | `cafedesk.lock` | `cafedesk_online.lock` |
| Backup file names | `cafedesk-<name>-<time>-<reason>.cdbackup` | `cafedesk-online-<name>-<time>-<reason>.cdbackup` |
| Release files | `CafeDesk-<ver>-…` | `CafeDeskOnline-<ver>-…` |

On Android the application ID alone gives each app its own private data folder and lets both
be installed side by side. On Windows the data folder comes from the product name in
`windows/runner/Runner.rc` (`%APPDATA%\CafeDesk\CafeDesk Online`), so the two apps never share
a database even on the same PC. The Dart package name stays `cafedesk` (it only affects
imports).

The backup archive format (`cafedesk-backup`, database entry `cafedesk.sqlite` inside the zip)
is unchanged, so an offline backup copy can be imported later.

## Checks run on the untouched baseline (2026-10-11, this PC)

Toolchain: Flutter 3.47.6 (pinned in `scripts/dev-env.ps1` because Smart App Control blocks
other releases' engine tools on this PC), Dart 3.13.5.

| Check | Result |
|---|---|
| `dart format --set-exit-if-changed lib test tool integration_test` | 0 changed |
| `flutter analyze` | No issues found |
| `flutter test` | **168 passed, 0 failed** |

After the identity changes above: `flutter analyze` no issues, `flutter test` 168 passed.

The offline progress log (`docs/OFFLINE_PROGRESS.md`) and specification
(`docs/OFFLINE_POS_BUILD_SPEC.md`) are kept as history. Their check results were recorded in
earlier sessions and are evidence about the baseline, not checks run for this repository.
