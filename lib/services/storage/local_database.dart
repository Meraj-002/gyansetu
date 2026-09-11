import '../../core/utils/result.dart';

/// Contract for the on-device SQLite database.
///
/// This is the app's source of truth: every read a screen performs hits local
/// storage, and the network only ever refreshes it. That ordering is what makes
/// the app usable with no connectivity.
abstract interface class LocalDatabase {
  /// Opens the database and applies pending migrations.
  Future<Result<void>> open();

  Future<Result<List<Map<String, Object?>>>> query(
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  });

  Future<Result<int>> insert(String table, Map<String, Object?> values);

  Future<Result<int>> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  });

  Future<Result<int>> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  });

  Future<Result<void>> close();
}
