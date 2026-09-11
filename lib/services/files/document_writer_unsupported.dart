import 'dart:typed_data';

import 'saved_file.dart';

/// No writable folder on this platform (the web).
///
/// Callers treat null as "this device cannot keep the file" and offer the
/// browser download instead of reporting a save that never happened.
Future<SavedFile?> writeDocument(
  Uint8List bytes,
  String fileName, {
  String folder = 'worksheets',
}) async =>
    null;
