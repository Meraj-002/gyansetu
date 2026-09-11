import 'dart:convert';

/// The tribal mother tongue a teacher teaches *into*.
///
/// Distinct from the teaching medium: the medium is what the teacher speaks in
/// class, the target is the language the children understand.
enum TargetLanguage {
  santali(label: 'Santali', localeId: 'sat', isPrototype: true),
  mundari(label: 'Mundari', localeId: 'unr'),
  ho(label: 'Ho', localeId: 'hoc'),
  english(label: 'English', localeId: 'en');

  const TargetLanguage({
    required this.label,
    required this.localeId,
    this.isPrototype = false,
  });

  final String label;

  /// ISO 639-3 code. Used to ask the audio layer for a voice, and to key
  /// offline resource packs.
  final String localeId;

  /// The one language the prototype actually ships content for.
  final bool isPrototype;

  static TargetLanguage? byName(String? name) {
    for (final TargetLanguage v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// The language the teacher speaks in class.
///
/// An enum rather than a hard-coded 'Hindi' so adding English, Bengali or Odia
/// is a one-line change that the rest of the feature picks up.
enum TeachingMedium {
  hindi(label: 'Hindi', localeId: 'hi-IN'),
  english(label: 'English', localeId: 'en-IN'),
  bengali(label: 'Bengali', localeId: 'bn-IN'),
  odia(label: 'Odia', localeId: 'or-IN');

  const TeachingMedium({required this.label, required this.localeId});

  final String label;
  final String localeId;

  static TeachingMedium? byName(String? name) {
    for (final TeachingMedium v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// A subject the classroom focuses on.
enum ClassroomSubject {
  foundationalLiteracy(
    label: 'Foundational Literacy',
    subtitle: 'Padhna • Likhna • Samajhna',
    shortLabel: 'FLN',
  ),
  numeracy(
    label: 'Numeracy',
    subtitle: 'Ganit • Sankhya Gyan',
    shortLabel: 'Numeracy',
  );

  const ClassroomSubject({
    required this.label,
    required this.subtitle,
    required this.shortLabel,
  });

  final String label;
  final String subtitle;

  /// Used in the one-line classroom summary.
  final String shortLabel;

  static ClassroomSubject? byName(String? name) {
    for (final ClassroomSubject v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// Primary classes this build supports.
const List<int> kSupportedClasses = <int>[1, 2, 3, 4, 5];

/// The parts of a classroom that decide which offline content it needs.
///
/// Deliberately smaller than [ClassroomSetup]: the school, district and block
/// have no bearing on which lesson or audio packs must be on the device, so
/// the resource layer never has to wait for them.
class ResourceProfile {
  const ResourceProfile({
    required this.targetLanguage,
    required this.classLevel,
    required this.subjects,
  });

  final TargetLanguage targetLanguage;
  final int classLevel;
  final Set<ClassroomSubject> subjects;

  @override
  bool operator ==(Object other) =>
      other is ResourceProfile &&
      other.targetLanguage == targetLanguage &&
      other.classLevel == classLevel &&
      other.subjects.length == subjects.length &&
      other.subjects.containsAll(subjects);

  @override
  int get hashCode => Object.hash(
        targetLanguage,
        classLevel,
        Object.hashAllUnordered(subjects),
      );

  @override
  String toString() =>
      'ResourceProfile(${targetLanguage.localeId}, class $classLevel)';
}

/// A teacher's saved classroom configuration.
class ClassroomSetup {
  const ClassroomSetup({
    required this.teacherId,
    required this.schoolName,
    required this.districtId,
    required this.districtName,
    required this.blockId,
    required this.blockName,
    required this.teachingMedium,
    required this.targetLanguage,
    required this.classLevel,
    required this.subjects,
    required this.setupCompleted,
    this.setupCompletedAt,
    this.pendingSync = true,
    this.schemaVersion = currentSchemaVersion,
  });

  factory ClassroomSetup.fromJson(Map<String, dynamic> json) => ClassroomSetup(
        teacherId: json['teacherId'] as String,
        schoolName: json['schoolName'] as String,
        districtId: json['districtId'] as String,
        districtName: json['districtName'] as String,
        blockId: json['blockId'] as String,
        blockName: json['blockName'] as String,
        teachingMedium:
            TeachingMedium.byName(json['teachingMedium'] as String?) ??
                TeachingMedium.hindi,
        targetLanguage:
            TargetLanguage.byName(json['targetLanguage'] as String?) ??
                TargetLanguage.santali,
        classLevel: json['classLevel'] as int,
        subjects: <ClassroomSubject>{
          for (final dynamic s in (json['subjects'] as List<dynamic>? ??
              const <dynamic>[]))
            if (ClassroomSubject.byName(s as String?) case final ClassroomSubject v)
              v,
        },
        setupCompleted: json['setupCompleted'] as bool? ?? false,
        setupCompletedAt: DateTime.tryParse(
          json['setupCompletedAt'] as String? ?? '',
        ),
        pendingSync: json['pendingSync'] as bool? ?? true,
        schemaVersion: json['schemaVersion'] as int? ?? 1,
      );

  /// Bumped whenever the stored shape changes, so a future build can migrate
  /// rather than misread an old record.
  static const int currentSchemaVersion = 1;

  final String teacherId;
  final String schoolName;
  final String districtId;
  final String districtName;
  final String blockId;
  final String blockName;
  final TeachingMedium teachingMedium;
  final TargetLanguage targetLanguage;
  final int classLevel;
  final Set<ClassroomSubject> subjects;
  final bool setupCompleted;
  final DateTime? setupCompletedAt;

  /// True until a backend has acknowledged this record. Nothing syncs yet;
  /// the flag exists so the first sync run knows what to send.
  final bool pendingSync;

  final int schemaVersion;

  /// What this classroom needs stocked on the device.
  ResourceProfile get resourceProfile => ResourceProfile(
        targetLanguage: targetLanguage,
        classLevel: classLevel,
        subjects: subjects,
      );

  /// One-line description used on the summary card and the home screen.
  String get summaryLine {
    final String subjectText = subjects.isEmpty
        ? 'No subjects'
        : (<String>[
            for (final ClassroomSubject s in ClassroomSubject.values)
              if (subjects.contains(s)) s.shortLabel,
          ]).join(' + ');
    return 'Class $classLevel  •  ${teachingMedium.label} → '
        '${targetLanguage.label}  •  $subjectText';
  }

  ClassroomSetup copyWith({
    String? schoolName,
    String? districtId,
    String? districtName,
    String? blockId,
    String? blockName,
    TeachingMedium? teachingMedium,
    TargetLanguage? targetLanguage,
    int? classLevel,
    Set<ClassroomSubject>? subjects,
    bool? setupCompleted,
    DateTime? setupCompletedAt,
    bool? pendingSync,
  }) {
    return ClassroomSetup(
      teacherId: teacherId,
      schoolName: schoolName ?? this.schoolName,
      districtId: districtId ?? this.districtId,
      districtName: districtName ?? this.districtName,
      blockId: blockId ?? this.blockId,
      blockName: blockName ?? this.blockName,
      teachingMedium: teachingMedium ?? this.teachingMedium,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      classLevel: classLevel ?? this.classLevel,
      subjects: subjects ?? this.subjects,
      setupCompleted: setupCompleted ?? this.setupCompleted,
      setupCompletedAt: setupCompletedAt ?? this.setupCompletedAt,
      pendingSync: pendingSync ?? this.pendingSync,
      schemaVersion: schemaVersion,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'teacherId': teacherId,
        'schoolName': schoolName,
        'districtId': districtId,
        'districtName': districtName,
        'blockId': blockId,
        'blockName': blockName,
        'teachingMedium': teachingMedium.name,
        'targetLanguage': targetLanguage.name,
        'classLevel': classLevel,
        'subjects': <String>[for (final ClassroomSubject s in subjects) s.name],
        'setupCompleted': setupCompleted,
        'setupCompletedAt': setupCompletedAt?.toIso8601String(),
        'pendingSync': pendingSync,
        'schemaVersion': schemaVersion,
      };

  String encode() => jsonEncode(toJson());

  static ClassroomSetup? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return ClassroomSetup.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  String toString() => 'ClassroomSetup($teacherId, $summaryLine)';
}
