// ignore_for_file: prefer_initializing_formals
// Private fields cannot be initialising formals: a named parameter may not
// start with an underscore.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/result.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../audio/voice_clip_paths.dart';
import 'voice_translation_service.dart';

/// The online half of the live speech-to-speech flow: uploads one recorded
/// clip to the backend's `/api/v1/translation/speech`, which proxies Adi Vaani.
///
/// The response's `audio` field is the provider's own WAV payload as base64.
/// It is decoded here and written to a private temp file so the speaker button
/// can replay the answer without hitting the network again. Adi Vaani may
/// answer with either a complete WAV payload or bare PCM frames; both are
/// normalised to a playable file (see [_ensureWav]). Exactly three fields are
/// trusted (`transcript`, `translatedText`, `audio`); everything else the
/// provider reports is left behind.
class FastApiVoiceTranslationService implements VoiceTranslationService {
  FastApiVoiceTranslationService({
    required ApiClient api,
    Future<String> Function()? translatedClipPath,
  }) : _api = api,
       _translatedClipPath = translatedClipPath ?? VoiceClipPaths.translated;

  final ApiClient _api;
  final Future<String> Function() _translatedClipPath;

  @override
  Future<VoiceTranslationResult> translateVoice({
    required String audioPath,
  }) async {
    AppLogger.debug(
      '[LIVE] speech API called (${ApiEndpoints.speechTranslation}, audio=$audioPath)',
    );
    final Result<Map<String, dynamic>> result = await _api.postMultipart(
      ApiEndpoints.speechTranslation,
      fields: const <String, String>{},
      fileField: 'file',
      filePath: audioPath,
      filename: 'speech.wav',
    );

    return switch (result) {
      Ok<Map<String, dynamic>>(:final Map<String, dynamic> value) => _decode(
        value,
      ),
      Err<Map<String, dynamic>>(:final AppException error) => throw _failure(
        error,
      ),
    };
  }

  Future<VoiceTranslationResult> _decode(Map<String, dynamic> json) async {
    final String? transcript = json['transcript'] as String?;
    final String? translated = json['translatedText'] as String?;
    final String? audioBase64 = json['audio'] as String?;
    if (translated == null || translated.isEmpty || audioBase64 == null) {
      throw const VoiceTranslationFailure(
        VoiceTranslationFailureReason.failed,
        'The speech-translation service returned an incomplete answer.',
      );
    }

    final Uint8List? audioBytes = _decodeAudio(audioBase64);
    if (audioBytes == null || audioBytes.isEmpty) {
      throw const VoiceTranslationFailure(
        VoiceTranslationFailureReason.failed,
        'The spoken translation could not be read.',
      );
    }

    final Uint8List wavBytes = _ensureWav(audioBytes);
    AppLogger.debug(
      '[LIVE] transcript=$transcript translatedText=$translated '
      'audioBase64Length=${audioBase64.length} '
      'decodedWavBytes=${wavBytes.length}',
    );

    final String audioPath;
    try {
      audioPath = await _writeClip(wavBytes);
    } on Object {
      throw const VoiceTranslationFailure(
        VoiceTranslationFailureReason.failed,
        'The spoken translation could not be saved.',
      );
    }
    AppLogger.debug('[LIVE] WAV written path=$audioPath');

    return VoiceTranslationResult(
      transcript: transcript ?? '',
      translatedText: translated,
      audioPath: audioPath,
      contentType: json['contentType'] as String? ?? 'audio/wav',
      provider: json['provider'] as String? ?? 'adivaani',
    );
  }

  /// Adi Vaani returns `audio` as base64 of a WAV payload. The string may be
  /// clean base64 or, defensively, a data-URL (`data:audio/wav;base64,...`);
  /// both are accepted and normalised safely.
  Uint8List? _decodeAudio(String value) {
    final String cleaned = value.trim();
    final Match? dataUrl = RegExp(
      r'^data:[^;]+;base64,(.+)$',
      caseSensitive: false,
    ).firstMatch(cleaned);
    final String body = dataUrl?.group(1) ?? cleaned;
    if (body.isEmpty) return null;
    try {
      return base64.decode(body);
    } on FormatException catch (error) {
      AppLogger.error('voice audio payload was not valid base64', error: error);
      return null;
    }
  }

  Future<String> _writeClip(Uint8List wavBytes) async {
    final String path = await _translatedClipPath();
    final File file = File(path);
    await file.writeAsBytes(wavBytes, flush: true);
    return path;
  }

  /// Adi Vaani can answer with either a complete WAV payload or bare PCM frames
  /// without any file header. The official client plays both by wrapping the
  /// PCM frames in a 22050 Hz mono 16-bit WAV header when the payload lacks the
  /// RIFF magic. Mirror that so the returned clip is always playable.
  Uint8List _ensureWav(Uint8List bytes) {
    if (bytes.length > 4 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return bytes;
    }

    const int sampleRate = 22050;
    const int channels = 1;
    const int bitsPerSample = 16;
    final int dataSize = bytes.length;
    final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final int blockAlign = channels * bitsPerSample ~/ 8;

    final ByteData header = ByteData(44);
    void writeAscii(int offset, String text) {
      for (int i = 0; i < text.length; i++) {
        header.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, dataSize, Endian.little);

    final Uint8List wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, Uint8List.view(header.buffer));
    wav.setRange(44, 44 + dataSize, bytes);
    return wav;
  }

  /// Turns a transport/server failure into the honest reason.
  VoiceTranslationFailure _failure(AppException error) {
    if (error is NetworkException) {
      return const VoiceTranslationFailure(
        VoiceTranslationFailureReason.needsConnection,
        'No internet connection. Check your network and try again.',
      );
    }
    if (error is UnauthorizedException) {
      return const VoiceTranslationFailure(
        VoiceTranslationFailureReason.unauthorized,
        'Your session has expired. Please sign in again.',
      );
    }
    if (error is ServerException) {
      return VoiceTranslationFailure(
        VoiceTranslationFailureReason.failed,
        error.message == 'The server rejected the request.'
            ? 'The speech translation could not be completed right now.'
            : error.message,
      );
    }
    return VoiceTranslationFailure(
      VoiceTranslationFailureReason.failed,
      error.message,
    );
  }
}