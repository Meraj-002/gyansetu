import '../features/setup/models/classroom_setup.dart';

/// The kinds of card a teacher can flip through.
enum FlashcardCategory {
  numbers(label: 'Numbers'),
  animals(label: 'Animals'),
  nature(label: 'Nature'),
  objects(label: 'Objects'),
  actions(label: 'Actions'),
  programming(label: 'Programming');

  const FlashcardCategory({required this.label});

  final String label;

  static FlashcardCategory? byName(String? name) {
    for (final FlashcardCategory v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// One word in one mother tongue.
///
/// Stored explicitly rather than derived, because a translation shown to a
/// class has to be one somebody wrote down on purpose.
class FlashcardTranslation {
  const FlashcardTranslation({
    required this.word,
    this.pronunciation,
    this.spokenText,
    this.reviewedBySpeaker = false,
  });

  factory FlashcardTranslation.fromJson(Map<String, dynamic> json) =>
      FlashcardTranslation(
        word: json['word'] as String,
        pronunciation: json['pronunciation'] as String?,
        spokenText: json['spokenText'] as String?,
        reviewedBySpeaker: json['reviewedBySpeaker'] as bool? ?? false,
      );

  final String word;

  /// How to say it, where somebody has written that down. Never guessed.
  final String? pronunciation;

  /// The same word in a script a voice can pronounce — Devanagari for the
  /// tribal languages. Null when there is none, in which case the card does not
  /// offer to read it aloud in that language.
  final String? spokenText;

  /// True only when a speaker of the language has checked this.
  final bool reviewedBySpeaker;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'word': word,
        'pronunciation': pronunciation,
        'spokenText': spokenText,
        'reviewedBySpeaker': reviewedBySpeaker,
      };
}

/// One flashcard: a picture, a word in the teaching medium, and whatever
/// mother-tongue words have been written for it.
///
/// Per-device state — whether it is bookmarked, whether it was added to a
/// lesson — deliberately does NOT live here. This is catalogue data that will
/// one day come from a server; that is one teacher's phone.
class Flashcard {
  const Flashcard({
    required this.id,
    required this.category,
    required this.hindiWord,
    required this.order,
    this.imageAsset,
    this.numeral,
    this.counters = 0,
    this.hindiPronunciation,
    this.translations = const <String, FlashcardTranslation>{},
    this.lessonIds = const <String>[],
    this.classNumber,
    this.subject,
    this.culturallyRelevant = true,
  });

  factory Flashcard.fromJson(Map<String, dynamic> json) => Flashcard(
        id: json['id'] as String,
        category: FlashcardCategory.byName(json['category'] as String?) ??
            FlashcardCategory.objects,
        hindiWord: json['hindiWord'] as String,
        order: json['order'] as int,
        imageAsset: json['imageAsset'] as String?,
        numeral: json['numeral'] as int?,
        counters: json['counters'] as int? ?? 0,
        hindiPronunciation: json['hindiPronunciation'] as String?,
        translations: <String, FlashcardTranslation>{
          for (final MapEntry<String, dynamic> e
              in (json['translations'] as Map<String, dynamic>? ??
                      const <String, dynamic>{})
                  .entries)
            e.key: FlashcardTranslation.fromJson(e.value as Map<String, dynamic>),
        },
        lessonIds: <String>[
          for (final dynamic l
              in json['lessonIds'] as List<dynamic>? ?? const <dynamic>[])
            l as String,
        ],
        classNumber: json['classNumber'] as int?,
        subject: ClassroomSubject.byName(json['subject'] as String?),
        culturallyRelevant: json['culturallyRelevant'] as bool? ?? true,
      );

  final String id;
  final FlashcardCategory category;

  /// The word in the teaching medium.
  final String hindiWord;

  final String? hindiPronunciation;

  /// A bundled picture. Null for a card that has none — a numeral, for
  /// instance, is not a thing that can be photographed.
  final String? imageAsset;

  /// The digit a Numbers card teaches.
  final int? numeral;

  /// How many counters to draw beside it.
  final int counters;

  /// Mother-tongue words, keyed by [TargetLanguage.name].
  ///
  /// A language missing from this map has no word written for this card, and
  /// the card says so rather than showing something that might be wrong.
  final Map<String, FlashcardTranslation> translations;

  /// Lessons this card belongs with, used to put the right cards first.
  final List<String> lessonIds;

  final int? classNumber;
  final ClassroomSubject? subject;

  /// Whether this is an everyday object a Jharkhand classroom already knows.
  final bool culturallyRelevant;

  final int order;

  /// The word in [language], or null when nobody has written one.
  FlashcardTranslation? translationFor(TargetLanguage language) =>
      translations[language.name];

  bool hasTranslationFor(TargetLanguage language) =>
      translations.containsKey(language.name);

  bool get hasImage => (imageAsset ?? '').isNotEmpty;

  bool get isDrawn => !hasImage && numeral != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'category': category.name,
        'hindiWord': hindiWord,
        'hindiPronunciation': hindiPronunciation,
        'imageAsset': imageAsset,
        'numeral': numeral,
        'counters': counters,
        'translations': <String, dynamic>{
          for (final MapEntry<String, FlashcardTranslation> e
              in translations.entries)
            e.key: e.value.toJson(),
        },
        'lessonIds': lessonIds,
        'classNumber': classNumber,
        'subject': subject?.name,
        'culturallyRelevant': culturallyRelevant,
        'order': order,
      };

  @override
  bool operator ==(Object other) => other is Flashcard && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Flashcard($id, $hindiWord)';
}

/// A flashcard plus the state that belongs to this device and this teacher.
class FlashcardView {
  const FlashcardView({
    required this.card,
    this.bookmarked = false,
    this.inClassroom = false,
  });

  final Flashcard card;

  final bool bookmarked;

  /// True once the teacher has added it to the lesson they are teaching.
  final bool inClassroom;

  FlashcardView copyWith({bool? bookmarked, bool? inClassroom}) =>
      FlashcardView(
        card: card,
        bookmarked: bookmarked ?? this.bookmarked,
        inClassroom: inClassroom ?? this.inClassroom,
      );
}

/// A card the teacher put into a lesson.
class ClassroomFlashcard {
  const ClassroomFlashcard({
    required this.flashcardId,
    required this.lessonId,
    required this.classNumber,
    required this.addedAt,
  });

  factory ClassroomFlashcard.fromJson(Map<String, dynamic> json) =>
      ClassroomFlashcard(
        flashcardId: json['flashcardId'] as String,
        lessonId: json['lessonId'] as String,
        classNumber: json['classNumber'] as int,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );

  final String flashcardId;
  final String lessonId;
  final int classNumber;
  final DateTime addedAt;

  String get key => '$lessonId#$flashcardId';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'flashcardId': flashcardId,
        'lessonId': lessonId,
        'classNumber': classNumber,
        'addedAt': addedAt.toIso8601String(),
      };
}
