import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// SQLITE_CONSTRAINT_UNIQUE / SQLITE_CONSTRAINT_PRIMARYKEY extended codes.
const _uniqueCodes = {2067, 1555};

/// True if [error] is a UNIQUE/PRIMARY KEY violation, whether raised directly
/// or relayed from drift's background isolate (where it arrives wrapped and
/// only its text survives).
bool isUniqueViolation(Object error) {
  if (error is SqliteException) {
    return _uniqueCodes.contains(error.extendedResultCode) || error.message.contains('UNIQUE constraint failed');
  }
  final text = error.toString();
  return text.contains('UNIQUE constraint failed') || text.contains('SQLITE_CONSTRAINT_UNIQUE');
}
