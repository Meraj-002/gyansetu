import 'dart:convert';

import '../storage/secure_storage_service.dart';

/// Which device-local records the server has already acknowledged, per type.
///
/// Some local stores keep the whole record even after sync (worksheets,
/// assessment results, progress events, support reports), so a finished push
/// has to be remembered or every run would re-send the same bytes. Sessions and
/// classroom setup carry their own per-record state and do not need this.
///
/// An ack is only ever written after the server explicitly accepted the item;
/// never optimistically.
class SyncAckStore {
  SyncAckStore(this._storage);

  /// Stable namespaces for ack-tracked document types.
  static const String worksheets = 'worksheets';
  static const String assessments = 'assessments';
  static const String progressEvents = 'progressEvents';
  static const String supportReports = 'supportReports';

  final SecureStorageService _storage;

  String _key(String namespace) => 'sync.acked.$namespace';

  Future<Set<String>> _ids(String namespace) async {
    final String? raw = await _storage.read(_key(namespace));
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      return (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
    } on FormatException {
      return <String>{};
    } on TypeError {
      return <String>{};
    }
  }

  Future<bool> has(String namespace, String id) async =>
      (await _ids(namespace)).contains(id);

  Future<void> mark(String namespace, String id) async {
    final Set<String> ids = await _ids(namespace);
    ids.add(id);
    await _storage.write(_key(namespace), jsonEncode(ids.toList()));
  }
}