import 'dart:io';

import 'package:cafedesk/core/backup/backup_service.dart';
import 'package:cafedesk/core/database/app_database.dart';
import 'package:drift/native.dart';

/// A file-backed database that restore can close, swap and reopen.
class FileHost implements DatabaseHost {
  FileHost(this.databaseFile) : _db = _open(databaseFile);
  @override
  final File databaseFile;
  AppDatabase? _db;
  bool failNextOpen = false;

  static AppDatabase _open(File f) => AppDatabase(NativeDatabase(f, setup: configureConnection));

  @override
  AppDatabase get database => _db!;

  @override
  Future<void> closeDatabase() async {
    await _db?.close();
    _db = null;
  }

  @override
  Future<AppDatabase> reopenDatabase() async {
    final db = _open(databaseFile);
    if (failNextOpen) {
      failNextOpen = false;
      await db.close();
      throw StateError('simulated failure while opening');
    }
    _db = db;
    await db.select(db.restaurantSettings).get();
    return db;
  }
}
