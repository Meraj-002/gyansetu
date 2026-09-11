/// The phrasebook index store, resolved per platform.
///
/// io targets persist one row per record in SQLite (so a large phrasebook
/// never sits in RAM); platforms without it (the web) fall back to a
/// session-only in-memory store and say so. Callers import only this library
/// and read `devicePhrasebookIndexStore`.
library;

export 'phrasebook_index_store_web.dart'
    if (dart.library.io) 'phrasebook_index_store_device.dart';