import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/app_logger.dart';
import 'saved_file.dart';

/// Writes [bytes] into the app's own documents folder.
///
/// App-scoped storage, so no broad storage permission is needed on any
/// supported Android version, and the file is removed with the app.
Future<SavedFile?> writeDocument(
  Uint8List bytes,
  String fileName, {
  String folder = 'worksheets',
}) async {
  try {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory target = Directory(p.join(documents.path, folder));
    if (!target.existsSync()) target.createSync(recursive: true);

    final File file = File(p.join(target.path, fileName));
    await file.writeAsBytes(bytes, flush: true);

    // Checked rather than assumed: a save that reports success with no file
    // behind it is worse than one that failed loudly.
    final int written = await file.length();
    if (written <= 0) {
      AppLogger.error('document was written but is empty: $fileName');
      return null;
    }
    return SavedFile(path: file.path, fileName: fileName, bytes: written);
  } on Object catch (error) {
    AppLogger.error('document could not be written', error: error);
    return null;
  }
}
