/// Where saved lesson audio is written.
///
/// Resolved through a conditional export because the answer needs `dart:io`,
/// which does not exist on the web. Importing `path_provider` directly from the
/// audio service would break the web build outright; this keeps that import on
/// the one side that can have it.
library;

export 'audio_directory_unsupported.dart'
    if (dart.library.io) 'audio_directory_io.dart';
