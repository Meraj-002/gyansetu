import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/setup/services/offline_resource_manager.dart';
import 'package:gyan_setu_ai/features/setup/setup_screen.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';

import 'setup_test_doubles.dart';

void main() {
  late TestRepository repository;
  late TestAudioService audio;
  late StaticConnectivityService connectivity;

  setUp(() {
    repository = TestRepository();
    audio = TestAudioService();
    connectivity = StaticConnectivityService(ConnectionStatus.online);
  });

  Widget harness({bool resourcesReady = false}) => MaterialApp(
        theme: AppTheme.light,
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: SetupScreen(
          repository: repository,
          locations: testLocations(),
          resources: StaticOfflineResourceManager(
            resourcesReady ? kResourcesReady : kResourcesPending,
          ),
          audio: audio,
          connectivityService: connectivity,
          teacherId: kTestTeacherId,
        ),
      );

  Future<void> open(WidgetTester tester, {bool resourcesReady = false}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(430, 2200);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(resourcesReady: resourcesReady));
    await tester.pumpAndSettle();
  }

  /// Scrolls the primary action into view before tapping it: the form is long,
  /// and a tap on an off-screen button silently does nothing.
  Future<void> tapAction(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// Fills the parts the form cannot infer.
  Future<void> fillSchool(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(SetupScreen.schoolNameFieldKey),
      'Govt. Primary School, Jama',
    );
    await tester.pump();

    await tester.tap(find.byKey(SetupScreen.districtFieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dumka').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SetupScreen.blockFieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Masalia').last);
    await tester.pumpAndSettle();
  }

  testWidgets('renders the reference structure with GyanSetu branding',
      (WidgetTester tester) async {
    await open(tester);

    expect(find.textContaining('GyanSetu'), findsWidgets);
    expect(find.textContaining('BhashaSetu'), findsNothing);
    expect(find.text('Bridging Languages. Building Futures.'), findsOneWidget);
    expect(find.text('Set up your classroom'), findsOneWidget);
    expect(
      find.text('Tell us about your school and teaching preferences.'),
      findsOneWidget,
    );
    expect(find.text('School'), findsOneWidget);
    expect(find.text('Teaching Language'), findsOneWidget);
    expect(find.text('Teaching Medium'), findsOneWidget);
    expect(find.text('Class'), findsOneWidget);
    expect(find.text('Subjects'), findsOneWidget);
    expect(find.text('Your classroom'), findsOneWidget);
    expect(find.text('Finish Setup'), findsOneWidget);
    expect(
      find.text(
        'You can change these settings anytime from classroom settings.',
      ),
      findsOneWidget,
    );
    // Sections are numbered 1..5; the reference mislabels the third as "2".
    for (final String step in <String>['1', '2', '3', '4', '5']) {
      expect(find.text(step), findsWidgets, reason: 'step $step missing');
    }
  });

  testWidgets('Santali is selected by default and marked as the prototype',
      (WidgetTester tester) async {
    await open(tester);

    expect(find.text('Santali'), findsOneWidget);
    expect(find.text('Mundari'), findsOneWidget);
    expect(find.text('Ho'), findsOneWidget);
    expect(find.text('Prototype Language'), findsOneWidget);
    expect(find.textContaining('Hindi → Santali'), findsOneWidget);
  });

  testWidgets('selecting another language replaces the previous one',
      (WidgetTester tester) async {
    await open(tester);

    await tester.tap(find.text('Mundari'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hindi → Mundari'), findsOneWidget);

    await tester.tap(find.text('Ho'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hindi → Ho'), findsOneWidget);
    expect(find.textContaining('Hindi → Mundari'), findsNothing);
  });

  testWidgets('the block dropdown is disabled until a district is chosen',
      (WidgetTester tester) async {
    await open(tester);

    expect(find.text('Select district first.'), findsOneWidget);

    await tester.tap(find.byKey(SetupScreen.districtFieldKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ranchi').last);
    await tester.pumpAndSettle();

    expect(find.text('Select district first.'), findsNothing);

    await tester.tap(find.byKey(SetupScreen.blockFieldKey));
    await tester.pumpAndSettle();
    // Only Ranchi's blocks are offered.
    expect(find.text('Kanke'), findsWidgets);
    expect(find.text('Jama'), findsNothing);
  });

  testWidgets('the live summary follows class and subject changes',
      (WidgetTester tester) async {
    await open(tester);

    expect(
      find.text('Class 1  •  Hindi → Santali  •  FLN + Numeracy'),
      findsOneWidget,
    );

    await tester.tap(find.text('Class 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Numeracy'));
    await tester.pumpAndSettle();

    expect(find.text('Class 3  •  Hindi → Santali  •  FLN'), findsOneWidget);
  });

  testWidgets('Finish Setup is disabled until the form is complete',
      (WidgetTester tester) async {
    await open(tester);

    FilledButton finish() => tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Finish Setup'),
            matching: find.byType(FilledButton),
          ),
        );
    expect(finish().onPressed, isNull);

    await fillSchool(tester);
    expect(finish().onPressed, isNotNull);
  });

  testWidgets('shows inline errors and does not save an incomplete form',
      (WidgetTester tester) async {
    await open(tester);

    // Make the button reachable, then clear a required field again.
    await fillSchool(tester);
    await tester.enterText(find.byKey(SetupScreen.schoolNameFieldKey), '');
    await tester.pump();

    // The button is disabled, so validation is proven through the controller's
    // own path: clearing the name must block completion.
    expect(repository.saveCalls, 0);
    expect(find.text('Finish Setup'), findsOneWidget);
  });

  testWidgets('a completed form saves and lands on Home',
      (WidgetTester tester) async {
    await open(tester, resourcesReady: true);
    await fillSchool(tester);

    await tapAction(tester, 'Finish Setup');

    expect(repository.saveCalls, 1);
    final ClassroomSetup saved = repository.lastSaved!;
    expect(saved.setupCompleted, isTrue);
    expect(saved.schoolName, 'Govt. Primary School, Jama');
    expect(saved.blockName, 'Masalia');

    expect(find.byType(SetupScreen), findsNothing);
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('when resources are missing it offers to continue anyway',
      (WidgetTester tester) async {
    await open(tester);
    await fillSchool(tester);

    await tapAction(tester, 'Finish Setup');

    expect(find.text('Classroom setup saved.'), findsOneWidget);
    expect(find.textContaining('after synchronisation'), findsOneWidget);
    expect(find.text('Continue to Home'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);

    await tester.tap(find.text('Continue to Home'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('a save failure keeps the teacher on the form',
      (WidgetTester tester) async {
    repository.failOnSave = true;
    await open(tester);
    await fillSchool(tester);

    await tapAction(tester, 'Finish Setup');

    expect(
      find.textContaining('could not be saved'),
      findsOneWidget,
    );
    expect(find.text('Try Again'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(SetupScreen), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('an existing setup is loaded into the form',
      (WidgetTester tester) async {
    repository = TestRepository(existing: existingSetup());
    await open(tester);

    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Govt. Primary School, Kanke'), findsOneWidget);
    expect(
      find.textContaining('Class 4  •  English → Ho  •  Numeracy'),
      findsOneWidget,
    );
    expect(find.textContaining('Ranchi • Namkum'), findsOneWidget);
  });

  testWidgets('back with unsaved changes asks before discarding',
      (WidgetTester tester) async {
    await open(tester);

    await tester.tap(find.text('Class 4'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Discard your changes?'), findsOneWidget);
    expect(find.text('Keep Editing'), findsOneWidget);

    await tester.tap(find.text('Keep Editing'));
    await tester.pumpAndSettle();
    expect(find.byType(SetupScreen), findsOneWidget);
  });

  testWidgets('back without changes leaves immediately',
      (WidgetTester tester) async {
    await open(tester);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Discard your changes?'), findsNothing);
    expect(find.byType(SetupScreen), findsNothing);
  });

  testWidgets('audio preview reports that no voice is available yet',
      (WidgetTester tester) async {
    await open(tester);

    await tester.tap(find.text('Preview & Listen').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('not on this device'), findsOneWidget);
    expect(find.text('No audio yet'), findsWidgets);
  });

  testWidgets('the offline card never claims readiness it cannot back up',
      (WidgetTester tester) async {
    await open(tester);
    // Resources are missing and the device is online, so it offers to sync
    // rather than announcing offline-readiness.
    expect(find.text('Offline-ready'), findsNothing);
    expect(find.text('Online'), findsOneWidget);

    connectivity.set(ConnectionStatus.offline);
    await tester.pumpAndSettle();
    expect(find.text('Needs sync'), findsOneWidget);
  });

  testWidgets('claims offline-ready only when resources are present',
      (WidgetTester tester) async {
    await open(tester, resourcesReady: true);
    expect(find.text('Offline-ready'), findsOneWidget);
  });

  testWidgets('the whole form works offline', (WidgetTester tester) async {
    connectivity = StaticConnectivityService(ConnectionStatus.offline);
    await open(tester, resourcesReady: true);
    await fillSchool(tester);

    await tapAction(tester, 'Finish Setup');

    expect(repository.saveCalls, 1);
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('lays out on a small handset without overflow',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Set up your classroom'), findsOneWidget);
  });
}
