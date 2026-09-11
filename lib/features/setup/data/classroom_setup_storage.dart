import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/utils/app_logger.dart';
import '../models/classroom_setup.dart';

/// Where a saved classroom lives on the device.
///
/// One record per teacher, keyed by teacher id, so a shared classroom tablet
/// can hold more than one teacher's configuration.
abstract interface class ClassroomSetupStorage {
  Future<ClassroomSetup?> load(String teacherId);

  /// Returns false when the record could not be written. The caller must not
  /// treat a failed save as success — the teacher's work would be lost.
  Future<bool> save(ClassroomSetup setup);

  Future<void> clear(String teacherId);
}

/// SQLite-backed storage, used on Android and iOS.
///
/// The classroom is a single small record today, but it is stored relationally
/// from the start because lessons, progress and sync queues will sit alongside
/// it in the same database, and moving them later would mean a migration.
class SqliteClassroomSetupStorage implements ClassroomSetupStorage {
  SqliteClassroomSetupStorage({this.databaseName = 'gyansetu.db'});

  final String databaseName;

  static const String _table = 'classroom_setup';

  Database? _db;

  Future<Database> _open() async {
    final Database? existing = _db;
    if (existing != null) return existing;

    final String path = p.join(await getDatabasesPath(), databaseName);
    return _db = await openDatabase(
      path,
      version: ClassroomSetup.currentSchemaVersion,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $_table (
            teacher_id       TEXT PRIMARY KEY,
            school_name      TEXT NOT NULL,
            district_id      TEXT NOT NULL,
            district_name    TEXT NOT NULL,
            block_id         TEXT NOT NULL,
            block_name       TEXT NOT NULL,
            teaching_medium  TEXT NOT NULL,
            target_language  TEXT NOT NULL,
            class_level      INTEGER NOT NULL,
            subjects         TEXT NOT NULL,
            setup_completed  INTEGER NOT NULL,
            completed_at     TEXT,
            pending_sync     INTEGER NOT NULL,
            schema_version   INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  @override
  Future<ClassroomSetup?> load(String teacherId) async {
    try {
      final Database db = await _open();
      final List<Map<String, Object?>> rows = await db.query(
        _table,
        where: 'teacher_id = ?',
        whereArgs: <Object?>[teacherId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'classroom setup load failed',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  @override
  Future<bool> save(ClassroomSetup setup) async {
    try {
      final Database db = await _open();
      await db.insert(
        _table,
        _toRow(setup),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'classroom setup save failed',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<void> clear(String teacherId) async {
    try {
      final Database db = await _open();
      await db.delete(
        _table,
        where: 'teacher_id = ?',
        whereArgs: <Object?>[teacherId],
      );
    } on Object catch (error) {
      AppLogger.error('classroom setup clear failed', error: error);
    }
  }

  static Map<String, Object?> _toRow(ClassroomSetup s) => <String, Object?>{
        'teacher_id': s.teacherId,
        'school_name': s.schoolName,
        'district_id': s.districtId,
        'district_name': s.districtName,
        'block_id': s.blockId,
        'block_name': s.blockName,
        'teaching_medium': s.teachingMedium.name,
        'target_language': s.targetLanguage.name,
        'class_level': s.classLevel,
        'subjects': <String>[
          for (final ClassroomSubject c in s.subjects) c.name,
        ].join(','),
        'setup_completed': s.setupCompleted ? 1 : 0,
        'completed_at': s.setupCompletedAt?.toIso8601String(),
        'pending_sync': s.pendingSync ? 1 : 0,
        'schema_version': s.schemaVersion,
      };

  static ClassroomSetup _fromRow(Map<String, Object?> row) => ClassroomSetup(
        teacherId: row['teacher_id']! as String,
        schoolName: row['school_name']! as String,
        districtId: row['district_id']! as String,
        districtName: row['district_name']! as String,
        blockId: row['block_id']! as String,
        blockName: row['block_name']! as String,
        teachingMedium:
            TeachingMedium.byName(row['teaching_medium'] as String?) ??
                TeachingMedium.hindi,
        targetLanguage:
            TargetLanguage.byName(row['target_language'] as String?) ??
                TargetLanguage.santali,
        classLevel: row['class_level']! as int,
        subjects: <ClassroomSubject>{
          for (final String name in (row['subjects'] as String? ?? '').split(','))
            if (ClassroomSubject.byName(name) case final ClassroomSubject v) v,
        },
        setupCompleted: (row['setup_completed'] as int? ?? 0) == 1,
        setupCompletedAt:
            DateTime.tryParse(row['completed_at'] as String? ?? ''),
        pendingSync: (row['pending_sync'] as int? ?? 1) == 1,
        schemaVersion: row['schema_version'] as int? ?? 1,
      );
}

/// Preferences-backed storage for platforms sqflite does not cover.
///
/// Used on the web, where `sqflite` throws on open. The record is stored as one
/// versioned JSON document under a per-teacher key — structured, not a scatter
/// of loose preference entries.
class PreferencesClassroomSetupStorage implements ClassroomSetupStorage {
  PreferencesClassroomSetupStorage([SharedPreferencesAsync? preferences])
      : _prefs = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  String _key(String teacherId) => 'classroom_setup.$teacherId';

  @override
  Future<ClassroomSetup?> load(String teacherId) async {
    try {
      return ClassroomSetup.tryDecode(await _prefs.getString(_key(teacherId)));
    } on Object catch (error) {
      AppLogger.error('classroom setup load failed', error: error);
      return null;
    }
  }

  @override
  Future<bool> save(ClassroomSetup setup) async {
    try {
      await _prefs.setString(_key(setup.teacherId), setup.encode());
      return true;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'classroom setup save failed',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<void> clear(String teacherId) async {
    try {
      await _prefs.remove(_key(teacherId));
    } on Object catch (error) {
      AppLogger.error('classroom setup clear failed', error: error);
    }
  }
}

/// In-memory storage for tests.
class MemoryClassroomSetupStorage implements ClassroomSetupStorage {
  MemoryClassroomSetupStorage({this.failOnSave = false});

  /// Test hook for exercising the save-failure path.
  bool failOnSave;

  final Map<String, ClassroomSetup> _records = <String, ClassroomSetup>{};

  @override
  Future<ClassroomSetup?> load(String teacherId) async => _records[teacherId];

  @override
  Future<bool> save(ClassroomSetup setup) async {
    if (failOnSave) return false;
    _records[setup.teacherId] = setup;
    return true;
  }

  @override
  Future<void> clear(String teacherId) async => _records.remove(teacherId);
}

/// Picks the storage that works on the current platform.
ClassroomSetupStorage defaultClassroomSetupStorage() =>
    kIsWeb ? PreferencesClassroomSetupStorage() : SqliteClassroomSetupStorage();
