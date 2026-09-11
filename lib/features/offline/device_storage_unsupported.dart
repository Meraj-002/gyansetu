/// No writable folder is exposed on this platform (the web).
///
/// Callers treat null as "cannot be measured here" and show an honest
/// Unavailable message instead of inventing a number.
Future<int?> measureAppStorageBytes() async => null;