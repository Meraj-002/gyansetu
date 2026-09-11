import 'translation_cache_defs.dart';

export 'translation_cache_defs.dart';

/// On platforms with no writable persistence (the web), caching genuinely
/// cannot survive a page reload, so the honest device store is the in-memory
/// one: it caches for the session and persists nothing.
final TranslationCacheStore deviceTranslationCacheStore =
    MemoryTranslationCacheStore();