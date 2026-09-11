/// The store the phrasebook index lives in.
///
/// The phrasebook reader answers one sentence by reading *one* stored row, so a
/// substantially larger verified phrasebook never needs its full dataset in RAM
/// on a 2 GB phone. The store deals in record JSON, not model objects, so it
/// has no dependency on the phrasebook reader (and no import cycle).
abstract interface class PhrasebookIndexStore {
  /// The stored record for (pair, normalised source key), or null.
  ///
  /// Single-row read: this is the whole 2 GB design — a lookup touches only the
  /// row that can answer.
  Future<String?> lookup({
    required String pair,
    required String normalizedKey,
  });

  /// Stores (or replaces) one record as a JSON string, one row per key.
  Future<void> indexRecord({
    required String pair,
    required String normalizedKey,
    required String recordJson,
  });

  /// How many records are stored (all of them, placeholders included: a
  /// placeholder is stored so the reader can definitively refuse it, but never
  /// answered from).
  Future<int> count();

  /// Empties the store. Used by `forget()` when a pack is re-downloaded.
  Future<void> clear();
}

/// In-memory store: for tests and sessions on platforms with no persistent
/// local storage (the web). Lookup is one map read.
class MemoryPhrasebookIndexStore implements PhrasebookIndexStore {
  final Map<String, String> _rows = <String, String>{};

  static String _key(String pair, String normalizedKey) =>
      '$pair#$normalizedKey';

  @override
  Future<String?> lookup({
    required String pair,
    required String normalizedKey,
  }) async =>
      _rows[_key(pair, normalizedKey)];

  @override
  Future<void> indexRecord({
    required String pair,
    required String normalizedKey,
    required String recordJson,
  }) async {
    _rows[_key(pair, normalizedKey)] = recordJson;
  }

  @override
  Future<int> count() async => _rows.length;

  @override
  Future<void> clear() async => _rows.clear();
}