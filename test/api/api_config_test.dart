import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/config/api_config.dart';

void main() {
  group('ApiConfig', () {
    test('web resolves to the host loopback', () {
      expect(
        ApiConfig.resolve(isWeb: true, platform: TargetPlatform.android),
        'http://localhost:8000',
      );
    });

    test('Android emulator uses the host-machine alias', () {
      expect(
        ApiConfig.resolve(isWeb: false, platform: TargetPlatform.android),
        'http://10.0.2.2:8000',
      );
    });

    test('iOS and desktop resolve to the host loopback', () {
      for (final TargetPlatform platform in <TargetPlatform>[
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        expect(
          ApiConfig.resolve(isWeb: false, platform: platform),
          'http://localhost:8000',
        );
      }
    });

    test('without an override the resolved default is used', () {
      expect(ApiConfig.baseUrl, ApiConfig.resolve());
    });
  });
}
