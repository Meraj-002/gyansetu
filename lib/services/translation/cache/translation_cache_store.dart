/// The translation cache store, resolved per platform.
///
/// io targets persist one row per entry in SQLite; platforms without it (the
/// web) fall back to a session-only in-memory store and say so. Callers import
/// only this library and read `deviceTranslationCacheStore`.
library;

export 'translation_cache_store_web.dart'
    if (dart.library.io) 'translation_cache_store_device.dart';