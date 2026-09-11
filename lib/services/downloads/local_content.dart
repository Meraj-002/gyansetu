/// Local file access for downloaded content packs.
///
/// Resolved through a conditional export: writing real bytes needs `dart:io`
/// and `path_provider`, neither of which exists on the web. Screens and the
/// download manager import only this library, so the web build never pulls in
/// the platform imports. Callers treat a null root / false result honestly
/// ("storage unavailable here") instead of faking a download.
library;

export 'local_content_unsupported.dart'
    if (dart.library.io) 'local_content_io.dart';