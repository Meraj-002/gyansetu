import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/models/app_language.dart';

void main() {
  group('AppLanguage', () {
    test('byCodeStatic resolves every official code case-insensitively',
        () {
      expect(AppLanguage.byCodeStatic('hi-IN'), AppLanguage.hindi);
      expect(AppLanguage.byCodeStatic('hi-in'), AppLanguage.hindi);
      expect(AppLanguage.byCodeStatic('Hi_IN'), AppLanguage.hindi);
      expect(AppLanguage.byCodeStatic('hi'), AppLanguage.hindi);
      expect(AppLanguage.byCodeStatic('sat'), AppLanguage.santali);
      expect(AppLanguage.byCodeStatic('SAT'), AppLanguage.santali);
      expect(AppLanguage.byCodeStatic('en-IN'), AppLanguage.english);
      expect(AppLanguage.byCodeStatic('nonsense'), isNull);
    });

    test('fromAny resolves legacy name spellings', () {
      expect(AppLanguage.fromAny('santali'), AppLanguage.santali);
      expect(AppLanguage.fromAny('hindi'), AppLanguage.hindi);
      expect(AppLanguage.fromAny('english'), AppLanguage.english);
    });

    test('byCode resolves null to null rather than throwing', () {
      expect(AppLanguage.hindi.byCode(null), isNull);
    });

    test('fromAny resolves stored variant spellings loosely', () {
      expect(AppLanguage.fromAny('sat-Olck'), AppLanguage.santali);
      expect(AppLanguage.fromAny('santhali'), AppLanguage.santali);
      expect(AppLanguage.fromAny(' Hindi '), AppLanguage.hindi);
      expect(AppLanguage.fromAny(null), isNull);
      expect(AppLanguage.fromAny(''), isNull);
      expect(AppLanguage.fromAny('  '), isNull);
    });

    test('the canonical pair for the classroom is hindi to santali', () {
      expect(AppLanguage.hindi.code, 'hi-IN');
      expect(AppLanguage.santali.code, 'sat');
      expect(AppLanguage.hindi.iso639, 'hi');
      expect(AppLanguage.santali.iso639, 'sat');
      expect(AppLanguage.hindi.label, isNotEmpty);
      expect(AppLanguage.santali.label, isNotEmpty);
    });
  });
}