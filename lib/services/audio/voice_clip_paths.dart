import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/app_logger.dart';

/// Files the live translate screen can play: a recorded source clip and a
/// downloaded mother-tongue clip.
///
/// Written under the app's private temporary directory so a huge recording or
/// a downloaded WAV never lingers past the app; the same folder also lets a
/// [Duration]-keyed clip to be replaced without piling up output.
abstract final class VoiceClipPaths {
  /// A fresh absolute path for a recorded source clip, e.g. `voice_in_12.wav`.
  static Future<String> recording() =>
      _fresh(basename: 'voice_in_{n}.wav');

  /// A fresh absolute path for the translated (Santalí) clip, e.g.
  /// `voice_out_12.wav`.
  static Future<String> translated() =>
      _fresh(basename: 'voice_out_{n}.wav');

  static Future<String> _fresh({required String basename}) async {
    try {
      final Directory temp = await getTemporaryDirectory();
      final String n = DateTime.now().millisecondsSinceEpoch.toString();
      return p.join(temp.path, basename.replaceAll('{n}', n));
    } on Object catch (error) {
      AppLogger.error('voice clip directory could not be resolved', error: error);
      rethrow;
    }
  }
}