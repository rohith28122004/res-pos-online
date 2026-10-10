/// Domain errors shown to staff. Messages are written to be actionable on a
/// café counter, not for developers. Never put PINs or backup contents here.
sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Bad input (amounts, names, CSV rows...).
class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// The acting staff member is not allowed to do this.
class PermissionDeniedException extends AppException {
  const PermissionDeniedException(super.message);
}

/// An owner must approve this action (discount over limit, refund, void after
/// KOT, reopening a shift...).
class ApprovalRequiredException extends AppException {
  const ApprovalRequiredException(super.message);
}

/// The record changed or is in the wrong state (order already billed, table
/// already occupied, shift already open...).
class ConflictException extends AppException {
  const ConflictException(super.message);
}

class NotFoundException extends AppException {
  const NotFoundException(super.message);
}

/// Login throttling after repeated wrong PINs.
class LockedOutException extends AppException {
  const LockedOutException(super.message, this.retryAfter);
  final Duration retryAfter;
}

/// Backup/restore problems (corrupt archive, unsupported version...).
class BackupException extends AppException {
  const BackupException(super.message);
}

/// Printer configuration or encoding problems that need operator action.
class PrintException extends AppException {
  const PrintException(super.message);
}
