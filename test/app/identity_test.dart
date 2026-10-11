import 'dart:io';

import 'package:cafedesk/app/runtime.dart';
import 'package:cafedesk/core/backup/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

/// CONNECTED_BUILD_SPEC §1 rule 7 and §12: CaféDesk Online installs next to the
/// offline CaféDesk without sharing or overwriting its app, data or backups
/// (docs/BASELINE.md, identity table). Runs from the project root.
void main() {
  test('database, lock and phone files are not the offline app\'s', () {
    final paths = AppPaths(Directory('root'), Directory('backups'));
    final names = [
      paths.lockFile,
      paths.databaseFile,
      paths.deviceDatabaseFile,
    ].map((f) => p.basename(f.path)).toList();
    expect(names, ['cafedesk_online.lock', 'cafedesk_online.sqlite', 'cafedesk_online_device.sqlite']);
    for (final offline in ['cafedesk.lock', 'cafedesk.sqlite', 'cafedesk_demo.sqlite']) {
      expect(names, isNot(contains(offline)));
    }
  });

  test('the Android app installs as a separate app', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('applicationId = "com.cafedesk.online"'));
    // The offline app is com.cafedesk.cafedesk; `namespace` is only the Kotlin
    // code package and does not decide the installed identity.
    expect(gradle, isNot(contains('applicationId = "com.cafedesk.cafedesk"')));
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:label="CaféDesk Online"'));
  });

  test('the Windows app has its own executable and data folder', () {
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('set(BINARY_NAME "cafedesk_online")'));
    final rc = File('windows/runner/Runner.rc').readAsStringSync();
    // Company + product name decide %APPDATA%\CafeDesk\CafeDesk Online.
    expect(rc, contains('VALUE "ProductName", "CafeDesk Online"'));
    expect(rc, contains('VALUE "OriginalFilename", "cafedesk_online.exe"'));
    expect(File('windows/runner/main.cpp').readAsStringSync(), contains('L"CaféDesk Online"'));
  });

  test('backup files are named for the online app', () async {
    final h = await Harness.create();
    addTearDown(h.dispose);
    final tmp = await Directory.systemTemp.createTemp('cafedesk_identity');
    addTearDown(() => tmp.delete(recursive: true));
    final file = await BackupService(
      h.ctx,
      databaseFile: File(p.join(tmp.path, 'unused.sqlite')),
      defaultBackupDir: Directory(p.join(tmp.path, 'backups')),
      workDir: Directory(p.join(tmp.path, 'work')),
    ).createBackup(actor: h.owner);
    expect(p.basename(file.path), startsWith('cafedesk-online-'));
  });
}
