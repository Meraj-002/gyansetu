// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'translation_cache_defs.dart';

export 'translation_cache_defs.dart';

/// The translation cache persisted in a single SQLite row per entry.
///
/// Why a row per entry rather than one JSON blob in secure storage: a 2 GB
/// phone must never load the entire cache to answer one sentence. Lookup is a
/// single-row SELECT, writes upsert one row, and trimming is one ordered DELETE
/// in the store — the cache stays bounded and only the requested entry is ever
/// in memory.
class SqfliteTranslationCacheStore implements TranslationCacheStore {
  SqfliteTranslationCacheStore({DatabaseFactory? factory})
      : _factory = factory;

  final DatabaseFactory? _factory;
  Database? _db;

  static const String _table = 'translation_cache';

  Future<Database> _open() async {
    final Database? held = _db;
    if (held != null) return held;
    final DatabaseFactory factory = _factory ?? databaseFactory;
    final String databasesPath = await factory.getDatabasesPath();
    final Database opened = await factory.openDatabase(
      '$databasesPath/gyansetu_translation_cache.db',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database db, int version) => db.execute('''
            CREATE TABLE $_table (
              key TEXT PRIMARY KEY,
              saved_at INTEGER NOT NULL,
              data TEXT NOT NULL
            )
          '''),
      ),
    );
    return _db = opened;
  }

  @override
  Future<CachedTranslationEntry?> read(String key) async {
    try {
      final Database db = await _open();
      final List<Map<String, Object?>> rows = await db.query(
        _table,
        columns: <String>['data'],
        where: 'key = ?',
        whereArgs: <Object?>[key],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final String raw = rows.single['data']! as String;
      return CachedTranslationEntry.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      // A storage failure is a cache miss, never a crash and never a fake
      // answer.
      return null;
    }
  }

  @override
  Future<void> write(CachedTranslationEntry entry) async {
    final Database db = await _open();
    await db.insert(
      _table,
      <String, Object?>{
        'key': entry.key,
        'saved_at': (entry.savedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'data': jsonEncode(entry.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> trim(int maxEntries) async {
    final Database db = await _open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT key FROM $_table ORDER BY saved_at ASC',
    );
    final int overflow = rows.length - maxEntries;
    if (overflow <= 0) return;
    final List<Object?> oldest = <Object?>[
      for (int i = 0; i < overflow; i++) rows[i]['key'],
    ];
    if (oldest.isEmpty) return;
    final String placeholders =
        List<String>.filled(oldest.length, '?').join(',');
    await db.rawDelete(
      'DELETE FROM $_table WHERE key IN ($placeholders)',
      oldest,
    );
  }

  @override
  Future<int> count() async {
    final Database db = await _open();
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $_table',
    );
    return rows.single['n']! as int;
  }

  @override
  Future<void> clear() async {
    final Database db = await _open();
    await db.delete(_table);
  }
}

/// The instance every platform caller uses (io targets).
final TranslationCacheStore deviceTranslationCacheStore =
    SqfliteTranslationCacheStore();