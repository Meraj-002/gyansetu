import 'phrasebook_index_defs.dart';

export 'phrasebook_index_defs.dart';

/// On platforms with no persistent local storage (the web), the honest device
/// store is the in-memory one: it indexes for the session only.
final PhrasebookIndexStore devicePhrasebookIndexStore =
    MemoryPhrasebookIndexStore();