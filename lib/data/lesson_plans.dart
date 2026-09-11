import '../features/setup/models/classroom_setup.dart';
import '../models/lesson_plan.dart';
import '../models/lesson_translation.dart';

/// Curated lesson bodies and translations for the prototype.
///
/// DEVELOPMENT DATA, but not throwaway data: every script, activity,
/// assessment and tip below was written by hand against the lesson's stated
/// learning outcome. Nothing here was produced by a model, which is why every
/// plan reports [ContentProvenance.authored] — the "AI-generated" badge stays
/// off until the AI layer actually writes something.
///
/// Coverage is deliberately partial. Class 1 and Class 2 have plans; Classes 3
/// to 5 do not, so the missing-content state on lesson detail is a state the
/// app really reaches rather than one that only exists in a test.
///
/// REPLACE WITH: `LessonContentRepository` reading the FastAPI content endpoint
/// (or the on-device generator) through `AiContentService`. Nothing above the
/// repository changes when it does.
abstract final class CuratedLessonContent {
  /// Fixed so cached copies compare equal across runs.
  static final DateTime _authoredAt = DateTime(2026, 6, 1);

  /// Plans keyed by lesson id.
  static Map<String, LessonPlan> plans() => <String, LessonPlan>{
        for (final LessonPlan plan in _plans) plan.lessonId: plan,
      };

  static List<LessonPlan> get _plans => <LessonPlan>[
        LessonPlan(
          lessonId: 'c1-num-counting-1-10',
          scriptMedium: TeachingMedium.hindi,
          teacherScript: 'बच्चों, आज हम 1 से 10 तक गिनती सीखेंगे।',
          flnCompetency:
              'NIPUN Bharat • Numeracy • Counts objects up to 10 and tells how many',
          activity: const ClassroomActivity(
            id: 'act-c1-count-10',
            title: 'Count with real objects',
            summary: 'Show 5 objects and ask children to count them.',
            steps: <String>[
              'Put five seeds or stones on the desk where every child can see.',
              'Count them aloud together, touching each one as you say it.',
              'Add three more and count the whole group again from one.',
              'Ask two children to make their own group and count it aloud.',
            ],
            materials: <String>['Seeds', 'Small stones', 'Sticks'],
            minutes: 6,
          ),
          assessment: const QuickAssessment(
            id: 'qa-c1-count-10',
            title: 'Quick Assessment',
            summary: 'Ask the child to show 3 objects.',
            questions: <AssessmentQuestion>[
              AssessmentQuestion(
                id: 'q1',
                prompt: 'Ask the child to show 3 objects.',
                successCriteria: 'Picks up exactly three, without recounting.',
                concept: 'Counting 1–10',
              ),
              AssessmentQuestion(
                id: 'q2',
                prompt: 'Ask the child to count these 7 stones aloud.',
                successCriteria: 'Says one number for each stone, up to seven.',
                concept: 'Number Sequence',
              ),
              AssessmentQuestion(
                id: 'q3',
                prompt: 'Ask the child how many there are, without recounting.',
                successCriteria: 'Answers with the last number counted.',
                concept: 'After, Before, Between',
              ),
            ],
          ),
          tip: const TeachingTip(
            text: 'Use real objects like seeds, sticks, or stones for better '
                'understanding.',
          ),
          generatedAt: _authoredAt,
        ),
        LessonPlan(
          lessonId: 'c1-lit-swar-a-aa-i',
          scriptMedium: TeachingMedium.hindi,
          teacherScript: 'बच्चों, आज हम तीन स्वर सीखेंगे — अ, आ और इ।',
          flnCompetency:
              'NIPUN Bharat • Foundational Literacy • Recognises letters and '
              'their sounds',
          activity: const ClassroomActivity(
            id: 'act-c1-swar',
            title: 'Say it, then shape it',
            summary: 'Say each vowel aloud, then draw it in the sand.',
            steps: <String>[
              'Say अ slowly, three times. The class repeats each time.',
              'Draw अ large on the board and trace it with your finger.',
              'Children draw the same letter in sand or on a slate.',
              'Repeat for आ and इ, then mix the three and ask which is which.',
            ],
            materials: <String>['Slate', 'Chalk', 'Sand tray'],
            minutes: 8,
          ),
          assessment: const QuickAssessment(
            id: 'qa-c1-swar',
            title: 'Quick Assessment',
            summary: 'Point to a letter and ask the child to say its sound.',
            questions: <AssessmentQuestion>[
              AssessmentQuestion(
                id: 'q1',
                prompt: 'Point to अ and ask the child to say its sound.',
                successCriteria: 'Says the sound, not the letter name.',
                concept: 'Vowel sounds',
              ),
              AssessmentQuestion(
                id: 'q2',
                prompt: 'Ask the child to find आ among the three letters.',
                successCriteria: 'Points to the right letter first time.',
                concept: 'Letter shapes',
              ),
            ],
          ),
          tip: const TeachingTip(
            text: 'Let children trace letters in sand before writing on a '
                'slate — the hand learns the shape before the pencil does.',
          ),
          generatedAt: _authoredAt,
        ),
        LessonPlan(
          lessonId: 'c1-num-shapes',
          scriptMedium: TeachingMedium.hindi,
          teacherScript:
              'बच्चों, आज हम अपने आसपास गोल, चौकोर और तिकोनी चीज़ें ढूँढेंगे।',
          flnCompetency:
              'NIPUN Bharat • Numeracy • Identifies basic shapes in the '
              'immediate environment',
          activity: const ClassroomActivity(
            id: 'act-c1-shapes',
            title: 'Shape hunt',
            summary: 'Find one round, one square and one three-sided thing.',
            steps: <String>[
              'Name the three shapes and draw each one on the board.',
              'Send children in pairs to find one object of each shape.',
              'Each pair holds up what they found and names the shape.',
              'Sort everything the class found into three groups.',
            ],
            materials: <String>['Classroom objects'],
            minutes: 10,
          ),
          assessment: const QuickAssessment(
            id: 'qa-c1-shapes',
            title: 'Quick Assessment',
            summary: 'Ask the child to point to something round.',
            questions: <AssessmentQuestion>[
              AssessmentQuestion(
                id: 'q1',
                prompt: 'Ask the child to point to something round.',
                successCriteria: 'Points to a genuinely circular object.',
                concept: 'Circle, square, triangle',
              ),
              AssessmentQuestion(
                id: 'q2',
                prompt: 'Ask the child how many sides a triangle has.',
                successCriteria: 'Answers three.',
                concept: 'Shapes around us',
              ),
            ],
          ),
          tip: const TeachingTip(
            text: 'Shapes children can hold are remembered better than shapes '
                'drawn on a board.',
          ),
          generatedAt: _authoredAt,
        ),
        LessonPlan(
          lessonId: 'c1-lit-story-horen',
          scriptMedium: TeachingMedium.hindi,
          teacherScript:
              'बच्चों, आज मैं होरेन और आम के पेड़ की कहानी सुनाऊँगी। ध्यान से सुनो।',
          flnCompetency:
              'NIPUN Bharat • Foundational Literacy • Listens to and retells a '
              'short story',
          activity: const ClassroomActivity(
            id: 'act-c1-story',
            title: 'Retell it together',
            summary: 'Children retell the story in their own words, in turn.',
            steps: <String>[
              'Tell the story once, slowly, without stopping.',
              'Ask what happened first. Then what happened next.',
              'Four children each tell one part, in order.',
              'Ask what Horen should have done differently.',
            ],
            minutes: 12,
          ),
          assessment: const QuickAssessment(
            id: 'qa-c1-story',
            title: 'Quick Assessment',
            summary: 'Ask the child who the story was about.',
            questions: <AssessmentQuestion>[
              AssessmentQuestion(
                id: 'q1',
                prompt: 'Ask the child who the story was about.',
                successCriteria: 'Names Horen.',
                concept: 'Listening',
              ),
              AssessmentQuestion(
                id: 'q2',
                prompt: 'Ask what happened at the end.',
                successCriteria: 'Describes the ending in their own words.',
                concept: 'Retelling a story',
              ),
            ],
          ),
          tip: const TeachingTip(
            text: 'Pause once in the middle and ask the class what happens '
                'next — guessing keeps them listening.',
          ),
          generatedAt: _authoredAt,
        ),
        LessonPlan(
          lessonId: 'c1-num-counting-1-20',
          scriptMedium: TeachingMedium.hindi,
          teacherScript:
              'बच्चों, कल हमने 10 तक गिना था। आज हम 20 तक गिनती करेंगे।',
          flnCompetency:
              'NIPUN Bharat • Numeracy • Counts objects up to 20 and tells how '
              'many',
          activity: const ClassroomActivity(
            id: 'act-c1-count-20',
            title: 'Two groups of ten',
            summary: 'Count ten sticks, then ten more, and join them.',
            steps: <String>[
              'Count ten sticks into one bundle. Tie it.',
              'Count ten more into a second bundle.',
              'Put them together and count on from ten to twenty.',
              'Ask children to make their own bundle of ten.',
            ],
            materials: <String>['Sticks', 'String'],
            minutes: 9,
          ),
          assessment: const QuickAssessment(
            id: 'qa-c1-count-20',
            title: 'Quick Assessment',
            summary: 'Ask the child to count from 11 to 20.',
            questions: <AssessmentQuestion>[
              AssessmentQuestion(
                id: 'q1',
                prompt: 'Ask the child to count from 11 to 20.',
                successCriteria: 'Says every number in order, none skipped.',
                concept: 'Counting 1–20',
              ),
              AssessmentQuestion(
                id: 'q2',
                prompt: 'Ask the child to show you 14 sticks.',
                successCriteria: 'Counts out exactly fourteen.',
                concept: 'Groups of ten',
              ),
            ],
          ),
          tip: const TeachingTip(
            text: 'A tied bundle of ten makes the jump past ten visible '
                'instead of abstract.',
          ),
          generatedAt: _authoredAt,
        ),
        LessonPlan(
          lessonId: 'c1-lit-my-family',
          scriptMedium: TeachingMedium.hindi,
          teacherScript:
              'बच्चों, आज हम अपने परिवार के लोगों के नाम बोलना सीखेंगे।',
          flnCompetency:
              'NIPUN Bharat • Foundational Literacy • Uses familiar oral '
              'vocabulary',
          activity: const ClassroomActivity(
            id: 'act-c1-family',
            title: 'Who is in your home?',
            summary: 'Each child names five people in their home.',
            steps: <String>[
              'Name the members of your own family aloud first.',
              'Each child names five people at home, in their mother tongue.',
              'Write the words that repeat on the board.',
              'The class says each word together, twice.',
            ],
            minutes: 7,
          ),
          assessment: const QuickAssessment(
            id: 'qa-c1-family',
            title: 'Quick Assessment',
            summary: 'Ask the child to name five family members.',
            questions: <AssessmentQuestion>[
              AssessmentQuestion(
                id: 'q1',
                prompt: 'Ask the child to name five family members.',
                successCriteria: 'Names five different people aloud.',
                concept: 'Family words',
              ),
            ],
          ),
          tip: const TeachingTip(
            text: 'Accept the mother-tongue word first, then give the Hindi '
                'one beside it. Correcting the home word discourages speaking.',
          ),
          generatedAt: _authoredAt,
        ),
        LessonPlan(
          lessonId: 'c2-num-addition-10',
          scriptMedium: TeachingMedium.hindi,
          teacherScript:
              'बच्चों, आज हम दो छोटे समूहों को मिलाकर जोड़ना सीखेंगे।',
          flnCompetency:
              'NIPUN Bharat • Numeracy • Adds two numbers with sums up to 10',
          activity: const ClassroomActivity(
            id: 'act-c2-add-10',
            title: 'Join two groups',
            summary: 'Put three stones with four stones and count them all.',
            steps: <String>[
              'Make a group of three stones and a group of four.',
              'Ask how many altogether. Let the class count.',
              'Write 3 + 4 = 7 on the board beside the stones.',
              'Repeat with two other pairs that add to less than ten.',
            ],
            materials: <String>['Stones', 'Seeds'],
            minutes: 10,
          ),
          assessment: const QuickAssessment(
            id: 'qa-c2-add-10',
            title: 'Quick Assessment',
            summary: 'Ask the child what 5 and 3 make together.',
            questions: <AssessmentQuestion>[
              AssessmentQuestion(
                id: 'q1',
                prompt: 'Ask the child what 5 and 3 make together.',
                successCriteria: 'Answers eight, with or without counting.',
                concept: 'Joining two groups',
              ),
              AssessmentQuestion(
                id: 'q2',
                prompt: 'Ask the child to make 6 using two groups.',
                successCriteria: 'Makes any two groups totalling six.',
                concept: 'Sums up to 10',
              ),
            ],
          ),
          tip: const TeachingTip(
            text: 'Let children move the objects themselves. Watching you '
                'move them teaches far less.',
          ),
          generatedAt: _authoredAt,
        ),
        LessonPlan(
          lessonId: 'c2-lit-matra',
          scriptMedium: TeachingMedium.hindi,
          teacherScript:
              'बच्चों, आज हम आ और इ की मात्रा वाले शब्द पढ़ना सीखेंगे।',
          flnCompetency:
              'NIPUN Bharat • Foundational Literacy • Reads simple words with '
              'matra',
          activity: const ClassroomActivity(
            id: 'act-c2-matra',
            title: 'Add the matra',
            summary: 'Turn a letter into a word by adding the vowel sign.',
            steps: <String>[
              'Write क on the board and read it aloud.',
              'Add the आ matra and read का. Ask what changed.',
              'Do the same with the इ matra.',
              'Children build three words each and read them out.',
            ],
            materials: <String>['Slate', 'Chalk'],
            minutes: 12,
          ),
          assessment: const QuickAssessment(
            id: 'qa-c2-matra',
            title: 'Quick Assessment',
            summary: 'Ask the child to read three matra words aloud.',
            questions: <AssessmentQuestion>[
              AssessmentQuestion(
                id: 'q1',
                prompt: 'Ask the child to read का, कि and का\u200Cम aloud.',
                successCriteria: 'Reads all three without help.',
                concept: 'Reading words',
              ),
              AssessmentQuestion(
                id: 'q2',
                prompt: 'Ask the child to write one word with an आ matra.',
                successCriteria: 'Writes a readable word with the sign in the '
                    'right place.',
                concept: 'Aa matra',
              ),
            ],
          ),
          tip: const TeachingTip(
            text: 'Say the bare letter and the matra word one after the other '
                'so children hear exactly what the sign adds.',
          ),
          generatedAt: _authoredAt,
        ),

        // --- Python (SIH Demo) ---
        LessonPlan(
          lessonId: 'python-intro',
          scriptMedium: TeachingMedium.english,
          teacherScript:
              'Today we will learn about Python, a beginner-friendly '
              'programming language used to build apps, automate tasks, '
              'and create AI systems.',
          flnCompetency:
              'Introduction to Programming • Python basics • Variables and output',
          activity: const ClassroomActivity(
            id: 'act-python-intro',
            title: 'Write your first Python program',
            summary: 'Use print() to display Hello World and variable examples.',
            steps: <String>[
              'Open Python and type: print("Hello World")',
              'Run the program and see the output.',
              'Create a variable: name = "Meraj"',
              'Print the variable: print(name)',
              'Try: print("Hello " + name)',
            ],
            materials: <String>['Python environment', 'Computer or tablet'],
            minutes: 15,
          ),
          assessment: const QuickAssessment(
            id: 'qa-python-intro',
            title: 'Quick Assessment',
            summary: 'Check basic Python understanding.',
            questions: <AssessmentQuestion>[
              AssessmentQuestion(
                id: 'q1',
                prompt: 'What does print() do in Python?',
                successCriteria: 'Displays output on the screen.',
                concept: 'Python basics',
              ),
              AssessmentQuestion(
                id: 'q2',
                prompt: 'Write a Python variable called name with value "Riya".',
                successCriteria: 'Writes: name = "Riya"',
                concept: 'Variables',
              ),
              AssessmentQuestion(
                id: 'q3',
                prompt: 'What is the output of: print("Hello")?',
                successCriteria: 'Hello',
                concept: 'print()',
              ),
            ],
          ),
          tip: const TeachingTip(
            text: 'Start with print() — seeing output immediately keeps '
                'students engaged. Variables feel less abstract when tied to '
                'their own names.',
          ),
          generatedAt: _authoredAt,
        ),
      ];

  // --- Translations --------------------------------------------------------

  /// Prototype mother-tongue translations, keyed by lesson id and language.
  ///
  /// IMPORTANT: these are grounded, not invented. The Santali entry below uses
  /// the documented Santali numerals one to ten; it is deliberately a short,
  /// checkable line rather than a fluent paragraph the app cannot vouch for.
  /// Every entry carries `reviewedBySpeaker: false`, and lesson detail says so
  /// on screen, because no Santali speaker has signed these off yet.
  ///
  /// Coverage is one lesson in one language on purpose. A translation this app
  /// cannot stand behind is worse in a classroom than an honest "not available
  /// yet", so the rest of the catalogue reports exactly that.
  static Map<String, LessonTranslation> translations() =>
      <String, LessonTranslation>{
        for (final LessonTranslation t in _translations) t.cacheKey: t,
      };

  static List<LessonTranslation> get _translations => <LessonTranslation>[
        LessonTranslation(
          lessonId: 'c1-num-counting-1-10',
          sourceMedium: TeachingMedium.hindi,
          targetLanguage: TargetLanguage.santali,
          text: "Johar gidra'ko! Ale mit' khon gel dhabic lekha bo.\n"
              "Mit', bar, pe, pon, more, turui, eae, iril, are, gel.",
          // Devanagari, which is how Santali is written in Jharkhand school
          // material, so an Indic voice can pronounce it. Without this the
          // audio layer has nothing speakable and says so.
          spokenText: 'जोहार गिड़ाको! आले मित् खोन गेल धाबिच् लेखा बो।\n'
              'मित्, बार, पे, पोन, मोड़े, तुरुइ, एयाए, इरिल, आरे, गेल।',
          createdAt: _authoredAt,
        ),
      ];
}
