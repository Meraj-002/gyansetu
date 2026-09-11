import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/services/translation/offline_phrasebook_translation_service.dart';
import 'package:gyan_setu_ai/services/translation/phrasebook_index/phrasebook_index_defs.dart';
import 'package:gyan_setu_ai/services/translation/text_translation_service.dart';

import 'translation_test_doubles.dart';

/// Builds one pack line with full control over the wire fields, so the tests
/// can push deliberately-hostile JSON (a placeholder claiming to be verified,
/// a "verified" development record, etc.) at the reader.
String line({
  String sourceLanguage = 'hindi',
  String targetLanguage = 'santali',
  required String sourceText,
  String? target,
  String? spoken,
  String? category,
  String? provenance,
  bool? verified,
  String? id,
  String? context,
  String? dialect,
  int? version,
}) =>
    jsonEncode(<String, dynamic>{
      'id': ?id,
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'sourceText': sourceText,
      'targetText': ?target,
      'spokenText': ?spoken,
      'category': ?category,
      'provenance': provenance ?? 'authored-development',
      'verified': verified ?? false,
      'context': ?context,
      'dialect': ?dialect,
      'version': version ?? 1,
    });

OfflinePhrasebookTranslationService serviceWith(String pack) {
  const String packPath = '/memory/translation-hindi-santali.jsonl';
  final MemoryLocalContentIo io = MemoryLocalContentIo();
  final FixedPackSource source = FixedPackSource()..path = packPath;
  io.put(packPath, pack);
  return OfflinePhrasebookTranslationService(
    source: source,
    io: io,
  );
}

void main() {
  group('MemoryPhrasebookIndexStore keeps one row per (pair, key)', () {
    test('indexes, looks up distinct pairs and keys, counts and clears',
        () async {
      final MemoryPhrasebookIndexStore store = MemoryPhrasebookIndexStore();

      await store.indexRecord(
          pair: 'hi-IN>sat', normalizedKey: 'one', recordJson: '{"a":1}');
      await store.indexRecord(
          pair: 'hi-IN>sat', normalizedKey: 'two', recordJson: '{"a":2}');
      await store.indexRecord(
          pair: 'sat>hi-IN', normalizedKey: 'one', recordJson: '{"a":3}');

      expect(await store.count(), 3);
      expect(await store.lookup(pair: 'hi-IN>sat', normalizedKey: 'one'),
          '{"a":1}');
      expect(await store.lookup(pair: 'hi-IN>sat', normalizedKey: 'two'),
          '{"a":2}');
      expect(await store.lookup(pair: 'sat>hi-IN', normalizedKey: 'one'),
          '{"a":3}');
      // The same key re-sent replaces, never duplicates.
      await store.indexRecord(
          pair: 'hi-IN>sat', normalizedKey: 'one', recordJson: '{"a":9}');
      expect(await store.count(), 3);
      expect(await store.lookup(pair: 'hi-IN>sat', normalizedKey: 'one'),
          '{"a":9}');

      await store.clear();
      expect(await store.count(), 0);
    });

    test('serves every row of a large synthetic phrasebook by key', () async {
      final MemoryPhrasebookIndexStore store = MemoryPhrasebookIndexStore();
      const int rows = 5000;
      for (int i = 0; i < rows; i += 1) {
        await store.indexRecord(
          pair: 'hi-IN>sat',
          normalizedKey: 'key-$i',
          recordJson: '{"i":$i}',
        );
      }
      expect(await store.count(), rows);
      // A lookup is exactly one row read — never a scan.
      expect(await store.lookup(pair: 'hi-IN>sat', normalizedKey: 'key-0'),
          '{"i":0}');
      expect(await store.lookup(pair: 'hi-IN>sat', normalizedKey: 'key-4999'),
          '{"i":4999}');
      expect(
        await store.lookup(pair: 'hi-IN>sat', normalizedKey: 'missing'),
        isNull,
      );
    });
  });

  group('PhrasebookRecord fromJson never over-claims verification', () {
    test('a record from an authoritative source can be verified', () {
      final PhrasebookRecord record = PhrasebookRecord.fromJson(
        jsonDecode(line(
          sourceText: 'पानी दो',
          target: "Daka' meya",
          provenance: 'verifiedSource',
          verified: true,
        )) as Map<String, dynamic>,
      )!;
      expect(record.verified, isTrue);
      expect(record.provenance, PhrasebookProvenance.verifiedSource);
      expect(record.canAnswer, isTrue);
    });

    test('a development record claiming verified stays unverified', () {
      final PhrasebookRecord record = PhrasebookRecord.fromJson(
        jsonDecode(line(
          sourceText: 'पानी दो',
          target: "Daka' meya",
          provenance: 'authored-development',
          verified: true,
        )) as Map<String, dynamic>,
      )!;
      expect(record.verified, isFalse);
      expect(record.provenance, PhrasebookProvenance.authoredDevelopment);
      // "authored" (older files), unknown, absent: all development.
      for (final String? provenanceValue in <String?>[
        'authored',
        'unknown',
        null,
      ]) {
        final PhrasebookRecord r = PhrasebookRecord.fromJson(
          jsonDecode(line(
            sourceText: 'पानी दो',
            target: "Daka' meya",
            provenance: provenanceValue,
            verified: true,
          )) as Map<String, dynamic>,
        )!;
        expect(r.verified, isFalse);
        expect(r.provenance, PhrasebookProvenance.authoredDevelopment);
      }
    });

    test('a placeholder can never be verified, even with the flag set', () {
      final PhrasebookRecord record = PhrasebookRecord.fromJson(
        jsonDecode(line(
          sourceText: 'जल्दी आओ',
          target: null,
          provenance: 'verifiedSource',
          verified: true,
        )) as Map<String, dynamic>,
      )!;
      expect(record.verified, isFalse);
      expect(record.canAnswer, isFalse);
      expect(record.provenance, PhrasebookProvenance.verifiedSource);
    });

    test('a verified-source record marked unverified stays unverified', () {
      final PhrasebookRecord record = PhrasebookRecord.fromJson(
        jsonDecode(line(
          sourceText: 'पानी दो',
          target: "Daka' meya",
          provenance: 'verifiedSource',
          verified: false,
        )) as Map<String, dynamic>,
      )!;
      expect(record.verified, isFalse);
      expect(record.provenance, PhrasebookProvenance.verifiedSource);
    });
  });

  group('OfflinePhrasebookTranslationService verified handling', () {
    test('answers a verified sourced record as reviewed by a speaker',
        () async {
      final OfflinePhrasebookTranslationService service = serviceWith(
        line(
          id: 'pb-000001',
          sourceText: 'पानी दो',
          target: "Daka' meya",
          spoken: 'दका मेंया',
          category: 'basicActions',
          provenance: 'verifiedSource',
          verified: true,
          context: 'classroom-instruction',
          dialect: 'santal-pargana',
          version: 3,
        ),
      );

      final TranslationResult result = await service.translate(
        TranslationRequest(
          sourceText: 'पानी दो',
          sourceLanguage: 'hi-IN',
          targetLanguage: 'sat',
        ),
      );
      expect(result.translatedText, "Daka' meya");
      expect(result.spokenText, 'दका मेंया');
      expect(result.reviewedBySpeaker, isTrue);
      expect(result.source, TranslationSource.phrasebook);
    });

    test('carries id, context, dialect and version through the index',
        () async {
      final MemoryPhrasebookIndexStore store = MemoryPhrasebookIndexStore();
      const String packPath = '/memory/translation-hindi-santali.jsonl';
      final MemoryLocalContentIo io = MemoryLocalContentIo();
      final FixedPackSource source = FixedPackSource()..path = packPath;
      io.put(
        packPath,
        line(
          id: 'pb-000079',
          sourceText: 'दरवाज़ा बंद करो',
          target: "Khola'o kara",
          provenance: 'verifiedSource',
          verified: true,
          context: 'classroom-instruction',
          dialect: 'santal-pargana',
          version: 2,
        ),
      );
      final OfflinePhrasebookTranslationService service =
          OfflinePhrasebookTranslationService(
        source: source,
        io: io,
        indexStore: store,
      );

      await service.translate(
        TranslationRequest(
          sourceText: 'दरवाज़ा बंद करो',
          sourceLanguage: 'hi-IN',
          targetLanguage: 'sat',
        ),
      );

      final String? raw = await store.lookup(
        pair: 'hi-IN>sat',
        normalizedKey: 'दरवाज़ा बंद करो',
      );
      expect(raw, isNotNull);
      final Map<String, dynamic> stored =
          jsonDecode(raw!) as Map<String, dynamic>;
      expect(stored['id'], 'pb-000079');
      expect(stored['context'], 'classroom-instruction');
      expect(stored['dialect'], 'santal-pargana');
      expect(stored['version'], 2);
      expect(stored['verified'], isTrue);
    });

    test('a placeholder is stored but never answered from, and count reflects '
        'the whole pack', () async {
      final OfflinePhrasebookTranslationService service = serviceWith([
        line(sourceText: 'पानी दो', target: "Daka' meya"),
        line(
          sourceText: 'जल्दी आओ',
          target: null,
          provenance: 'verifiedSource',
          verified: true,
        ),
      ].join('\n'));

      expect(await service.indexedRecords(), 0);
      final TranslationResult answer = await service.translate(
        TranslationRequest(
          sourceText: 'पानी दो',
          sourceLanguage: 'hi-IN',
          targetLanguage: 'sat',
        ),
      );
      expect(answer.translatedText, "Daka' meya");
      expect(await service.indexedRecords(), 2); // placeholder is counted

      await expectLater(
        service.translate(
          TranslationRequest(
            sourceText: 'जल्दी आओ',
            sourceLanguage: 'hi-IN',
            targetLanguage: 'sat',
          ),
        ),
        throwsA(
          isA<TextTranslationFailure>().having(
            (TextTranslationFailure failure) => failure.reason,
            'reason',
            TranslationFailureReason.notConfigured,
          ),
        ),
      );
    });

    test('an unverified development record answers but says it was not '
        'reviewed', () async {
      final OfflinePhrasebookTranslationService service = serviceWith(
        line(sourceText: 'पानी दो', target: "Daka' meya"),
      );

      final TranslationResult result = await service.translate(
        TranslationRequest(
          sourceText: 'पानी दो',
          sourceLanguage: 'hi-IN',
          targetLanguage: 'sat',
        ),
      );
      expect(result.reviewedBySpeaker, isFalse);
    });

    test('forget() clears the index so the pack is read again', () async {
      final MemoryPhrasebookIndexStore store = MemoryPhrasebookIndexStore();
      const String packPath = '/memory/translation-hindi-santali.jsonl';
      final MemoryLocalContentIo io = MemoryLocalContentIo();
      final FixedPackSource source = FixedPackSource()..path = packPath;
      io.put(packPath, line(sourceText: 'पानी दो', target: "Daka' meya"));
      final OfflinePhrasebookTranslationService standalone =
          OfflinePhrasebookTranslationService(
        source: source,
        io: io,
        indexStore: store,
      );

      Future<void> askOut() => standalone.translate(
            TranslationRequest(
              sourceText: 'पानी दो',
              sourceLanguage: 'hi-IN',
              targetLanguage: 'sat',
            ),
          );

      await askOut();
      expect(await store.count(), 1);

      standalone.forget();
      expect(await store.count(), 0);

      await askOut();
      expect(await store.count(), 1);
    });
  });
}