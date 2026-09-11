import '../features/setup/models/classroom_setup.dart';
import '../models/flashcard.dart';

/// The bundled flashcard set.
///
/// DEVELOPMENT DATA, but written on purpose rather than filled in. Every Hindi
/// word here was typed deliberately, and every picture is a public-domain or
/// CC0 photograph bundled with the app.
///
/// IMPORTANT — the mother-tongue words. Santali numerals one to five are well
/// documented, so those are here. Nothing else is: a Santali, Mundari or Ho
/// word this project cannot vouch for would be read aloud to a class as if it
/// were correct, which is worse than an honest "not available yet". Cards
/// without a word for the chosen language say exactly that, and the map below
/// is what a curated language database or a translation model replaces.
///
/// The Actions category deliberately ships no cards. No public-domain picture
/// found for running, eating, reading or writing showed the action clearly
/// enough to teach from, so the category shows its empty state rather than a
/// misleading photograph.
///
/// REPLACE WITH: `RemoteFlashcardDataSource` reading the FastAPI catalogue.
/// Nothing above `FlashcardDataSource` changes when it does.
abstract final class FlashcardData {
  static const String _art = 'assets/flashcards';

  /// Keyed by [TargetLanguage.name].
  static const String _santali = 'santali';

  static List<Flashcard> all() => <Flashcard>[
        // --- Numbers ---------------------------------------------------------
        // Drawn rather than photographed: a numeral is not a thing a camera can
        // point at, and counters are how a Class 1 child reads it anyway.
        _number(1, 'एक', "mit'", 'मित्', order: 1),
        _number(2, 'दो', 'bar', 'बार', order: 2),
        _number(3, 'तीन', 'pe', 'पे', order: 3),
        _number(4, 'चार', 'pon', 'पोन', order: 4),
        _number(5, 'पाँच', 'more', 'मोड़े', order: 5),
        _number(6, 'छह', 'turui', 'तुरुइ', order: 6),
        _number(7, 'सात', 'eae', 'एयाए', order: 7),
        _number(8, 'आठ', 'iril', 'इरिल', order: 8),
        _number(9, 'नौ', 'are', 'आरे', order: 9),
        _number(10, 'दस', 'gel', 'गेल', order: 10),

        // --- Animals ---------------------------------------------------------
        _card(
          id: 'animals-cow',
          category: FlashcardCategory.animals,
          hindi: 'गाय',
          asset: '$_art/animals/cow.jpg',
          order: 1,
        ),
        _card(
          id: 'animals-goat',
          category: FlashcardCategory.animals,
          hindi: 'बकरी',
          asset: '$_art/animals/goat.jpg',
          order: 2,
        ),
        _card(
          id: 'animals-hen',
          category: FlashcardCategory.animals,
          hindi: 'मुर्गी',
          asset: '$_art/animals/hen.jpg',
          order: 3,
        ),
        _card(
          id: 'animals-dog',
          category: FlashcardCategory.animals,
          hindi: 'कुत्ता',
          asset: '$_art/animals/dog.jpg',
          order: 4,
        ),

        // --- Nature ----------------------------------------------------------
        _card(
          id: 'nature-tree',
          category: FlashcardCategory.nature,
          hindi: 'पेड़',
          asset: '$_art/nature/tree.png',
          order: 1,
        ),
        _card(
          id: 'nature-leaf',
          category: FlashcardCategory.nature,
          hindi: 'पत्ता',
          asset: '$_art/nature/leaf.jpg',
          order: 2,
        ),
        _card(
          id: 'nature-river',
          category: FlashcardCategory.nature,
          hindi: 'नदी',
          asset: '$_art/nature/river.png',
          order: 3,
        ),
        _card(
          id: 'nature-sun',
          category: FlashcardCategory.nature,
          hindi: 'सूरज',
          asset: '$_art/nature/sun.jpg',
          order: 4,
        ),

        // --- Objects ---------------------------------------------------------
        _card(
          id: 'objects-apple',
          category: FlashcardCategory.objects,
          hindi: 'सेब',
          asset: '$_art/objects/apple.jpg',
          order: 1,
        ),
        _card(
          id: 'objects-cup',
          category: FlashcardCategory.objects,
          hindi: 'कप',
          asset: '$_art/objects/cup.jpg',
          order: 2,
        ),
        _card(
          id: 'objects-pencil',
          category: FlashcardCategory.objects,
          hindi: 'पेंसिल',
          asset: '$_art/objects/pencil.jpg',
          order: 3,
        ),
        _card(
          id: 'objects-chair',
          category: FlashcardCategory.objects,
          hindi: 'कुर्सी',
          asset: '$_art/objects/chair.png',
          order: 4,
        ),

        // --- Programming (Python) --------------------------------------------
        _programming(
          id: 'prog-what-is-python',
          hindi: 'Python क्या है?',
          english: 'What is Python?',
          order: 1,
        ),
        _programming(
          id: 'prog-print',
          hindi: 'print() क्या करता है?',
          english: 'print()',
          order: 2,
        ),
        _programming(
          id: 'prog-variable',
          hindi: 'Variable (चर)',
          english: 'Variable',
          order: 3,
        ),
        _programming(
          id: 'prog-assign-variable',
          hindi: 'Variable बनाना',
          english: 'name = "Meraj"',
          order: 4,
        ),
        _programming(
          id: 'prog-hello-world',
          hindi: 'Hello World प्रिंट करना',
          english: 'print("Hello World")',
          order: 5,
        ),
        _programming(
          id: 'prog-string',
          hindi: 'String (स्ट्रिंग)',
          english: 'String',
          order: 6,
        ),
        _programming(
          id: 'prog-integer',
          hindi: 'Integer (पूर्णांक)',
          english: 'Integer',
          order: 7,
        ),
        _programming(
          id: 'prog-input',
          hindi: 'input() क्या है?',
          english: 'input()',
          order: 8,
        ),
      ];

  /// A counting card, with its documented Santali numeral.
  static Flashcard _number(
    int value,
    String hindi,
    String santali,
    String santaliDevanagari, {
    required int order,
  }) =>
      Flashcard(
        id: 'numbers-$value',
        category: FlashcardCategory.numbers,
        hindiWord: hindi,
        numeral: value,
        counters: value,
        order: order,
        classNumber: 1,
        subject: ClassroomSubject.numeracy,
        lessonIds: const <String>[
          'c1-num-counting-1-10',
          'c1-num-counting-1-20',
        ],
        translations: <String, FlashcardTranslation>{
          _santali: FlashcardTranslation(
            word: santali,
            // Devanagari, which is how Santali is written in Jharkhand school
            // material, so an Indic voice can pronounce it.
            spokenText: santaliDevanagari,
            // Nobody who speaks Santali has checked these yet, and the card
            // says so.
          ),
        },
      );

  static Flashcard _card({
    required String id,
    required FlashcardCategory category,
    required String hindi,
    required String asset,
    required int order,
  }) =>
      Flashcard(
        id: id,
        category: category,
        hindiWord: hindi,
        imageAsset: asset,
        order: order,
        classNumber: 1,
        // No mother-tongue word: see the note at the top of this file.
        translations: const <String, FlashcardTranslation>{},
      );

  static Flashcard _programming({
    required String id,
    required String hindi,
    required String english,
    required int order,
  }) =>
      Flashcard(
        id: id,
        category: FlashcardCategory.programming,
        hindiWord: hindi,
        order: order,
        classNumber: 5,
        subject: ClassroomSubject.numeracy,
        lessonIds: const <String>['python-intro'],
        translations: const <String, FlashcardTranslation>{},
      );
}
