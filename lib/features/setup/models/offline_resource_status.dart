/// What the device can actually offer offline for a given classroom.
enum OfflineReadiness {
  /// Local state has not been checked yet.
  unknown,

  /// A check or preparation pass is running.
  preparing,

  /// Every resource the classroom needs is present on the device.
  ready,

  /// The setup is saved, but some resources are not on the device yet and can
  /// only arrive over the network.
  needsSync,

  /// The check itself failed.
  failed,
}

/// One category of content a classroom needs to work without a connection.
enum OfflineResourceKind {
  curriculum(label: 'Curriculum'),
  lessons(label: 'Lessons'),
  vocabulary(label: 'Vocabulary'),
  audio(label: 'Native-language audio'),
  worksheets(label: 'Worksheets'),
  flashcards(label: 'Flashcards'),
  assessments(label: 'Assessments'),
  languageModel(label: 'Translation model');

  const OfflineResourceKind({required this.label});

  final String label;
}

/// Result of checking one resource category.
class OfflineResource {
  const OfflineResource({
    required this.kind,
    required this.available,
    this.detail,
  });

  final OfflineResourceKind kind;

  /// True only when the content is genuinely present on the device.
  final bool available;

  /// Why it is not available, when it is not.
  final String? detail;
}

/// A snapshot of offline readiness for the saved classroom.
class OfflineResourceStatus {
  const OfflineResourceStatus({
    required this.readiness,
    this.resources = const <OfflineResource>[],
    this.message,
  });

  const OfflineResourceStatus.unknown()
      : readiness = OfflineReadiness.unknown,
        resources = const <OfflineResource>[],
        message = null;

  final OfflineReadiness readiness;
  final List<OfflineResource> resources;

  /// User-facing summary. Never claims more than [resources] supports.
  final String? message;

  Iterable<OfflineResource> get missing =>
      resources.where((OfflineResource r) => !r.available);

  bool get isReady => readiness == OfflineReadiness.ready;
}
