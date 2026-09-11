import 'app_exception.dart';

/// Turns an [AppException] into copy a teacher can act on.
///
/// Kept separate from the exception classes so that the strings can move into
/// ARB localisation files without touching the error hierarchy.
abstract final class ErrorMessages {
  static String of(AppException exception) => switch (exception) {
        NetworkException() =>
          'No internet connection. Your work is saved on this device and will '
              'sync automatically.',
        ServerException() => 'The server could not complete that request. Please try again.',
        UnauthorizedException() => 'Your session has expired. Please sign in again.',
        StorageException() => 'Could not save to this device. Check available storage.',
        SyncException() => 'Sync could not finish. It will retry when you are back online.',
        AudioException() => 'Audio is unavailable. Check the microphone permission.',
        ValidationException() => exception.message,
        UnexpectedException() => 'Something went wrong. Please try again.',
      };
}
