/// Writes a generated document to the device.
///
/// Resolved through a conditional export because the answer needs `dart:io`,
/// which does not exist on the web. Importing `path_provider` directly from a
/// screen would break the web build outright; this keeps that import on the one
/// side that can have it.
library;

export 'document_writer_unsupported.dart'
    if (dart.library.io) 'document_writer_io.dart';
