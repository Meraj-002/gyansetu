import '../errors/app_exception.dart';

/// A success-or-failure return type.
///
/// Services return `Result<T>` instead of throwing across layer boundaries, so
/// a caller cannot forget to handle the failure path — `switch` on a [Result]
/// is exhaustive.
sealed class Result<T> {
  const Result();

  /// True when this holds a value.
  bool get isOk => this is Ok<T>;

  /// The value, or null when this is an [Err].
  T? get valueOrNull => switch (this) {
        Ok<T>(:final T value) => value,
        Err<T>() => null,
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.error);

  final AppException error;
}
