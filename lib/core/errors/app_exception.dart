/// Every error a service layer throws is one of these.
///
/// Sealed so that `switch` over an [AppException] is exhaustive: adding a new
/// case makes the compiler point at every place that must handle it.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  /// Developer-facing detail. Never rendered directly to a teacher — map it
  /// through `ErrorMessages.of` first.
  final String message;

  /// The lower-level error this wraps, if any.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// The device could not reach the server (airplane mode, no signal, DNS).
final class NetworkException extends AppException {
  const NetworkException(super.message, {super.cause});
}

/// The server was reached but answered with an error status.
final class ServerException extends AppException {
  const ServerException(super.message, {this.statusCode, super.cause});

  final int? statusCode;
}

/// Credentials are missing, expired, or rejected.
final class UnauthorizedException extends AppException {
  const UnauthorizedException(super.message, {super.cause});
}

/// A local SQLite or file-system operation failed.
final class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

/// Offline content could not be reconciled with the server.
final class SyncException extends AppException {
  const SyncException(super.message, {super.cause});
}

/// Speech-to-text or text-to-speech failed, including permission denials.
final class AudioException extends AppException {
  const AudioException(super.message, {super.cause});
}

/// Input failed validation before it reached a service.
final class ValidationException extends AppException {
  const ValidationException(super.message, {super.cause});
}

/// Anything that does not fit the cases above.
final class UnexpectedException extends AppException {
  const UnexpectedException(super.message, {super.cause});
}
