// ignore_for_file: prefer_initializing_formals

import 'package:sqflite/sqflite.dart';

import 'phrasebook_index_defs.dart';

export 'phrasebook_index_defs.dart';

/// The phrasebook index persisted in a single SQLite row per record.
///
/// 2 GB-device rule: building the index streams the pack line-by-line and
/// writes one row per record; a lookup is a single-row SELECT. The full dataset
/// is never decoded into RAM. This is what lets a verified phrasebook of tens
/// of thousands of phrases stay on an entry-level phone.
class SqflitePhrasebookIndexStore implements PhrasebookIndexStore {
  SqflitePhrasebookIndexStore({DatabaseFactory? factory})
      : _factory = factory;

  final DatabaseFactory? _factory;
  Database? _db;

  static const String _table = 'phrasebook_index';

  Future<Database> _open() async {
    final Database? held = _db;
    if (held != null) return held;
    final DatabaseFactory factory = _factory ?? databaseFactory;
    final String databasesPath = await factory.getDatabasesPath();
    final Database opened = await factory.openDatabase(
      '$databasesPath/gyansetu_phrasebook_index.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database db, int version) => db.execute('''
            CREATE TABLE $_table (
              pair TEXT NOT NULL,
              norm_key TEXT NOT NULL,
              record_json TEXT NOT NULL,
              PRIMARY KEY (pair, norm_key)
            )
          '''),
      ),
    );
    return _db = opened;
  }

  @override
  Future<String?> lookup({
    required String pair,
    required String normalizedKey,
  }) async {
    try {
      final Database db = await _open();
      final List<Map<String, Object?>> rows = await db.query(
        _table,
        columns: <String>['record_json'],
        where: 'pair = ? AND norm_key = ?',
        whereArgs: <Object?>[pair, normalizedKey],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.single['record_json']! as String;
    } on Object {
      // A storage failure is a miss, never a crash and never a fake answer.
      return null;
    }
  }

  @override
  Future<void> indexRecord({
    required String pair,
    required String normalizedKey,
    required String recordJson,
  }) async {
    final Database db = await _open();
    await db.insert(
      _table,
      <String, Object?>{
        'pair': pair,
        'norm_key': normalizedKey,
        'record_json': recordJson,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<int> count() async {
    try {
      final Database db = await _open();
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM $_table',
      );
      return rows.single['n']! as int;
    } on Object {
      return 0;
    }
  }

  @override
  Future<void> clear() async {
    try {
      final Database db = await _open();
      await db.delete(_table);
    } on Object {
      // Clearing a failing store is a no-op, never a crash.
    }
  }
}

/// The instance every platform caller uses (io targets).
final PhrasebookIndexStore devicePhrasebookIndexStore =
    SqflitePhrasebookIndexStore();