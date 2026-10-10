# Dependencies

Exact versions are pinned in `pubspec.lock` (committed). Every package below is pure Dart or
supports both Android and Windows unless noted. No package talks to the internet at runtime.

| Package | Why | Android | Windows | License |
|---|---|---|---|---|
| flutter (SDK) | UI | ✓ | ✓ | BSD-3-Clause |
| flutter_riverpod | app state / dependency wiring | ✓ | ✓ | MIT |
| drift | typed SQLite access, migrations, transactions | ✓ | ✓ | MIT |
| sqlite3 | SQLite bindings; bundles SQLite through build hooks (no system SQLite needed) | ✓ | ✓ | MIT (SQLite itself: public domain) |
| path_provider | app-support / external-storage directories | ✓ | ✓ | BSD-3-Clause |
| path | path joining | ✓ | ✓ | BSD-3-Clause |
| uuid | UUID v7 primary keys | ✓ | ✓ | MIT |
| timezone | bundled IANA time-zone database (offline) for business days | ✓ | ✓ | BSD-2-Clause |
| archive | ZIP for backups | ✓ | ✓ | MIT |
| crypto | SHA-256 backup checksums | ✓ | ✓ | BSD-3-Clause |
| hashlib | Argon2id PIN hashing (maintained, pure Dart) | ✓ | ✓ | BSD-3-Clause |
| file_picker | open/save dialogs for CSV and backup files | ✓ (SAF) | ✓ | MIT |
| fl_chart | dashboard bar charts | ✓ | ✓ | MIT |
| ffi | native strings/allocation for the Windows spooler bindings | n/a | ✓ | BSD-3-Clause |
| meta | `@visibleForTesting` | ✓ | ✓ | BSD-3-Clause |
| drift_dev, build_runner (dev) | code generation, schema dumps, migration tests | — | — | MIT / BSD-3-Clause |
| flutter_lints (dev) | lint rules | — | — | BSD-3-Clause |

## Native integrations written for this app (no plugin)

| Component | Platform | Implementation |
|---|---|---|
| Bluetooth Classic printing | Android | `android/app/src/main/kotlin/com/cafedesk/cafedesk/BluetoothPrinterPlugin.kt` (MethodChannel `cafedesk/bluetooth_printer`, RFCOMM SPP, runtime permission flow) |
| Windows spooler RAW + GDI printing | Windows | `lib/core/printing/transports/windows_spooler.dart` (dart:ffi to `winspool.drv`, `gdi32.dll`, on a background isolate) |
| LAN ESC/POS | both | `lib/core/printing/transports/tcp_transport.dart` (dart:io sockets) |

Printing plugins from pub.dev were not used: the available ones either cover only one
platform, only BLE, or produce PDFs (which is not thermal printing).

## Removed / avoided

`intl` and `drift_flutter` (not needed), `win32` (its v6 API was replaced with a small hand-written FFI surface), `csv` (own RFC 4180
module with formula guarding and no automatic number conversion), `sqlite3_flutter_libs`
(end-of-life; the `sqlite3` package bundles SQLite itself).
