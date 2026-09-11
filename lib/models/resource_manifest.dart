/// A downloadable content pack advertised by the backend resource catalogue.
///
/// Mirrors the FastAPI ``ResourceOut`` (camelCase wire format). ``sha256`` and
/// ``sizeBytes`` are the server's promise about the exact bytes at
/// ``/resources/{id}/content``; a device may mark a pack Ready only after it
/// has that content on disk and verified both fields against it.
class ResourceManifest {
  const ResourceManifest({
    required this.id,
    required this.kind,
    required this.name,
    required this.description,
    required this.classNumber,
    required this.subject,
    required this.version,
    required this.sizeBytes,
    required this.sha256,
    required this.mimeType,
    this.lessonId,
  });

  factory ResourceManifest.fromJson(Map<String, dynamic> json) {
    return ResourceManifest(
      id: json['id'] as String,
      kind: ResourceKind.fromWire(json['kind'] as String?),
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      classNumber: json['classNumber'] as int,
      subject: json['subject'] as String? ?? '',
      version: json['version'] as String? ?? '1',
      sizeBytes: json['sizeBytes'] as int,
      sha256: json['sha256'] as String,
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      lessonId: json['lessonId'] as String?,
    );
  }

  final String id;

  /// What the pack contains, so a device can decide what to fetch and where to
  /// keep it (worksheet packs vs lesson content vs audio plans).
  final ResourceKind kind;

  final String name;
  final String description;
  final int classNumber;
  final String subject;
  final String version;
  final int sizeBytes;
  final String sha256;
  final String mimeType;

  /// The lesson this pack belongs to, when it does.
  final String? lessonId;

  /// All packs a lesson needs for offline teaching, in a stable order.
  List<String> packIdsForLesson(List<String> resourceIds, {
    String? audioResourceId,
    String? worksheetResourceId,
    String? flashcardResourceId,
  }) =>
      <String>[
        ...resourceIds,
        ?audioResourceId,
        ?worksheetResourceId,
        ?flashcardResourceId,
      ];

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.wire,
        'name': name,
        'description': description,
        'classNumber': classNumber,
        'subject': subject,
        'version': version,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'mimeType': mimeType,
        'lessonId': lessonId,
      };

  @override
  bool operator ==(Object other) => other is ResourceManifest && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ResourceManifest($id v$version, ${sizeBytes}b)';
}

/// The pack categories the backend seeds. Wire values match the backend's
/// ``kind`` field exactly.
enum ResourceKind {
  content('content'),
  audio('audio'),
  worksheet('worksheet'),
  flashcard('flashcard'),
  translation('translation');

  const ResourceKind(this.wire);

  final String wire;

  static ResourceKind fromWire(String? value) {
    for (final ResourceKind kind in ResourceKind.values) {
      if (kind.wire == value) return kind;
    }
    return ResourceKind.content;
  }
}