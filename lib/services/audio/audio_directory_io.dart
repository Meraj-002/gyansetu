import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/app_logger.dart';

/// The app's own audio folder, created if it is not there yet.
///
/// Inside the application documents directory, so the clips are private to the
/// app and are removed with it.
Future<String?> resolveAudioDirectory() async {
  try {
    final Directory documents = await getApplicationDocumentsDirectory();
    final Directory audio = Directory(p.join(documents.path, 'audio'));
    if (!audio.existsSync()) audio.createSync(recursive: true);
    return audio.path;
  } on Object catch (error) {
    AppLogger.error('audio directory could not be resolved', error: error);
    return null;
  }
}
