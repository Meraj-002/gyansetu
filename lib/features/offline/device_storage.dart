/// Measures how many bytes the app itself occupies on this device.
///
/// Resolved through a conditional export because the answer needs `dart:io`,
/// which does not exist on the web. Importing `path_provider` directly from a
/// screen would break the web build outright; this keeps that import on the one
/// side that can have it.
library;

export 'device_storage_unsupported.dart'
    if (dart.library.io) 'device_storage_io.dart';