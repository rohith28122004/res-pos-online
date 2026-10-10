/// Build identity. Keep [version] in step with pubspec.yaml `version:`.
class AppInfo {
  static const String name = 'CaféDesk Online';
  static const String version = '1.0.0';
  static const int build = 1;

  /// Backups declare this format; restore refuses anything newer.
  static const int backupFormatVersion = 1;
}
