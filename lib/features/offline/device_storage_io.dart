import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/utils/app_logger.dart';

/// Total bytes this app holds in its own documents, support and temporary
/// folders, or null when it could not be measured.
///
/// App-scoped only: it never reports device totals it did not measure, which
/// would only ever be a guess on Android.
Future<int?> measureAppStorageBytes() async {
  try {
    final List<Directory> roots = <Directory>[
      await getApplicationDocumentsDirectory(),
      await getApplicationSupportDirectory(),
      await getTemporaryDirectory(),
    ];
    final Set<String> seen = <String>{};
    int total = 0;
    for (final Directory root in roots) {
      final String path = root.path;
      if (!seen.add(path)) continue;
      total += await _directorySize(root);
    }
    return total;
  } on Object catch (error) {
    AppLogger.error('app storage size check failed', error: error);
    return null;
  }
}

Future<int> _directorySize(Directory directory) async {
  int total = 0;
  try {
    if (!await directory.exists()) return 0;
    await for (final FileSystemEntity entity
        in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on Object {
          // One unreadable cache file must not break the whole inventory.
        }
      }
    }
  } on Object {
    return total;
  }
  return total;
}