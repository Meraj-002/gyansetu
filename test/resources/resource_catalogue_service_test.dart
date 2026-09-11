import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/core/errors/app_exception.dart';
import 'package:gyan_setu_ai/core/utils/result.dart';
import 'package:gyan_setu_ai/models/resource_manifest.dart';
import 'package:gyan_setu_ai/services/resources/resource_catalogue_service.dart';

import '../api/api_test_doubles.dart';

Map<String, dynamic> manifestJson(String id, {String version = '1'}) => <String, dynamic>{
      'id': id,
      'kind': 'content',
      'name': id,
      'description': '',
      'classNumber': 1,
      'subject': 'foundationalLiteracy',
      'version': version,
      'sizeBytes': 10,
      'sha256': 'abcdef',
      'mimeType': 'application/json',
      'lessonId': null,
    };

void main() {
  late ScriptedApiClient api;

  setUp(() {
    api = ScriptedApiClient();
  });

  test('unwraps the array box and pages through the whole catalogue', () async {
    final List<Map<String, dynamic>> allRows = <Map<String, dynamic>>[
      manifestJson('one'),
      manifestJson('two'),
    ];
    api.onGet = () {
      final int offset = int.parse(api.lastQuery?['offset'] ?? '0');
      final List<Map<String, dynamic>> rows =
          allRows.skip(offset).take(1).toList();
      return Ok<Map<String, dynamic>>(<String, dynamic>{'value': rows});
    };

    final ResourceCatalogueService service = ResourceCatalogueService(
      api: api,
      pageSize: 1,
    );
    final Result<List<ResourceManifest>> result = await service.all();

    expect(result, isA<Ok<List<ResourceManifest>>>());
    final List<ResourceManifest> manifests = (result as Ok).value;
    expect(manifests.map((ResourceManifest m) => m.id), <String>['one', 'two']);
    // Three pages for two packs at page size 1: 2 pages of data, then the
    // empty page that terminates pagination.
    expect(api.getPaths.length, 3);
  });

  test('an empty first page means an empty catalogue', () async {
    api.onGet = () => const Ok<Map<String, dynamic>>(<String, dynamic>{'value': <Object>[]});
    final Result<List<ResourceManifest>> result =
        await ResourceCatalogueService(api: api).all();
    expect((result as Ok).value, isEmpty);
  });

  test('network errors surface instead of pretending success', () async {
    api.onGet = () => Err<Map<String, dynamic>>(
          NetworkException('offline'),
        );
    final Result<List<ResourceManifest>> result =
        await ResourceCatalogueService(api: api).all();
    expect(result, isA<Err<List<ResourceManifest>>>());
  });

  test('byId returns null for an unknown pack', () async {
    api.onGet = () => const Ok<Map<String, dynamic>>(<String, dynamic>{});
    final Result<ResourceManifest?> found =
        await ResourceCatalogueService(api: api).byId('ghost');
    expect((found as Ok).value, isNull);
  });

  test('resolve returns only the packs the server advertises', () async {
    api.onGet = () => api.getPaths.last.endsWith('/ghost')
        ? const Ok<Map<String, dynamic>>(<String, dynamic>{})
        : Ok<Map<String, dynamic>>(manifestJson('known'));
    final ResourceCatalogueService service = ResourceCatalogueService(api: api);

    // 'known' resolves; 'ghost' is absent (empty response → null manifest).
    final Map<String, ResourceManifest> resolved =
        await service.resolve(<String>['known', 'ghost', 'known']);

    expect(resolved.keys, <String>['known']);
    expect(api.getPaths, <String>['/api/v1/resources/known', '/api/v1/resources/ghost']);
  });

  test('diffWith reports version differences and missing packs', () async {
    final List<Map<String, dynamic>> catalogue = <Map<String, dynamic>>[
      manifestJson('same', version: '1'),
      manifestJson('newer', version: '3'),
      manifestJson('absent-locally', version: '1'),
    ];
    api.onGet = () => Ok<Map<String, dynamic>>(<String, dynamic>{'value': catalogue});

    final Result<Map<String, ResourceManifest>> diff =
        await ResourceCatalogueService(api: api).diffWith(
      <String, String>{
        'same': '1',
        'newer': '2',
      },
    );

    final Map<String, ResourceManifest> updates = (diff as Ok).value;
    expect(updates.keys.toSet(), <String>{'newer', 'absent-locally'});
    expect(updates['newer']!.version, '3');
  });
}