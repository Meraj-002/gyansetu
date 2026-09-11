import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/app_settings.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/features/auth/services/auth_session_store.dart';
import 'package:gyan_setu_ai/features/auth/login_screen.dart';
import 'package:gyan_setu_ai/features/auth/services/pin_verifier.dart';
import 'package:gyan_setu_ai/features/lessons/lesson_library_screen.dart';
import 'package:gyan_setu_ai/features/offline/offline_center_screen.dart';
import 'package:gyan_setu_ai/features/profile/models/profile_settings.dart';
import 'package:gyan_setu_ai/features/profile/profile_screen.dart';
import 'package:gyan_setu_ai/features/profile/services/profile_settings_store.dart';
import 'package:gyan_setu_ai/features/profile/services/support_report_store.dart';
import 'package:gyan_setu_ai/features/setup/models/classroom_setup.dart';
import 'package:gyan_setu_ai/features/setup/setup_screen.dart';
import 'package:gyan_setu_ai/features/sync/sync_center_screen.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';
import 'package:gyan_setu_ai/services/storage/secure_storage_service.dart';
import 'package:provider/provider.dart';

import '../auth/auth_test_doubles.dart' as auth_doubles;
import '../setup/setup_test_doubles.dart' as setup_doubles;

/// A classroom matching the fictional teacher's id, so the profile card reads
/// the account and the classroom together.
ClassroomSetup profileClassroom() => ClassroomSetup(
  teacherId: auth_doubles.kTestTeacher.id,
  schoolName: 'Uparari Primary School',
  districtId: setup_doubles.kDumka.id,
  districtName: setup_doubles.kDumka.name,
  blockId: 'dumka.jama',
  blockName: 'Jama',
  teachingMedium: TeachingMedium.hindi,
  targetLanguage: TargetLanguage.santali,
  classLevel: 1,
  subjects: const <ClassroomSubject>{
    ClassroomSubject.foundationalLiteracy,
    ClassroomSubject.numeracy,
  },
  setupCompleted: true,
);

/// Everything the tests need a handle on after [open] has pumped the screen.
class Wiring {
  Wiring({
    required this.session,
    required this.classrooms,
    required this.storage,
    required this.settingsStore,
    required this.supportReports,
    required this.appSettings,
  });

  final AuthSessionStore session;
  final setup_doubles.TestRepository classrooms;
  final InMemorySecureStorageService storage;
  final LocalProfileSettingsStore settingsStore;
  final LocalSupportReportStore supportReports;
  final AppSettings appSettings;
}

/// Provisions the fictional teacher using a trivial verifier — the profile
/// never checks it, so the PBKDF2 work factor is irrelevant here.
Future<void> seedAccount(AuthSessionStore session) => session.provision(
  account: auth_doubles.kTestTeacher,
  verifier: PinVerifier(salt: Uint8List(1), hash: Uint8List(1), iterations: 1),
  deviceId: 'test-device',
);

Future<Wiring> open(
  WidgetTester tester, {
  bool withAccount = false,
  bool includeClassroom = true,
  ClassroomSetup? classroom,
  ConnectivityService? connectivity,
  AppSettings? appSettings,
  auth_doubles.FakeAuthenticationService? authentication,
}) async {
  final InMemorySecureStorageService storage = InMemorySecureStorageService();
  final AuthSessionStore session = AuthSessionStore(storage);
  if (withAccount) {
    await seedAccount(session);
  }
  final setup_doubles.TestRepository classrooms = setup_doubles.TestRepository(
    existing: classroom ??
        (withAccount && includeClassroom ? profileClassroom() : null),
  );
  final LocalProfileSettingsStore settingsStore = LocalProfileSettingsStore(
    storage,
  );
  final LocalSupportReportStore supportReports = LocalSupportReportStore(
    storage,
  );
  final AppSettings settings = appSettings ?? AppSettings();

  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(430, 2400);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AppSettings>(
      create: (_) => settings,
      child: MaterialApp(
        theme: AppTheme.light,
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: ProfileScreen(
          storage: storage,
          session: session,
          classrooms: classrooms,
          settingsStore: settingsStore,
          supportReports: supportReports,
          locations: setup_doubles.testLocations(),
          connectivity:
              connectivity ??
              StaticConnectivityService(ConnectionStatus.offline),
          authentication: authentication,
        ),
      ),
    ),
  );
  // Bounded pumps, not pumpAndSettle: the "checking connection" banner carries
  // an indefinitely animated spinner that pumpAndSettle would wait on forever.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));

  return Wiring(
    session: session,
    classrooms: classrooms,
    storage: storage,
    settingsStore: settingsStore,
    supportReports: supportReports,
    appSettings: settings,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('profile card', () {
    testWidgets('shows account and classroom data', (
      WidgetTester tester,
    ) async {
      await open(tester, withAccount: true);

      expect(find.text('Asha Murmu'), findsOneWidget);
      expect(find.text('Primary Teacher'), findsOneWidget);
      expect(find.text('Uparari Primary School'), findsOneWidget);
      expect(find.text('Dumka • Jama'), findsOneWidget);
      expect(find.text('Class 1'), findsOneWidget);
      expect(find.text('Hindi'), findsOneWidget);
      expect(find.text('Santali'), findsOneWidget);
      expect(find.byKey(ProfileScreen.editButtonKey), findsOneWidget);
    });

    testWidgets('falls back safely when no classroom data exists', (
      WidgetTester tester,
    ) async {
      await open(tester, withAccount: true, includeClassroom: false);

      expect(find.text('Asha Murmu'), findsOneWidget);
      expect(find.text('Primary Teacher'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(find.byKey(ProfileScreen.settingsLinkKey), findsOneWidget);
    });

    testWidgets('falls back safely when there is no account either', (
      WidgetTester tester,
    ) async {
      await open(tester, includeClassroom: false);

      expect(find.text('Teacher'), findsOneWidget);
      expect(find.text('Primary Teacher'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('edit profile', () {
    testWidgets('saves the teacher name and persists it', (
      WidgetTester tester,
    ) async {
      final w = await open(tester, withAccount: true);

      await tester.tap(find.byKey(ProfileScreen.editButtonKey));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ProfileScreen.editTeacherNameKey),
        'Anita Murmu',
      );
      await tester.tap(find.byKey(ProfileScreen.saveEditKey));
      await tester.pumpAndSettle();

      expect(find.text('Profile updated.'), findsOneWidget);
      expect(find.text('Anita Murmu'), findsOneWidget);

      // Reopened later the stored record still carries the new name.
      final String? stored = await w.storage.read('auth.account');
      expect(stored, contains('Anita Murmu'));
    });

    testWidgets('saves classroom changes through the repository', (
      WidgetTester tester,
    ) async {
      final w = await open(tester, withAccount: true);

      await tester.tap(find.byKey(ProfileScreen.editButtonKey));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ProfileScreen.editSchoolKey),
        'Kanke Primary School',
      );
      await tester.tap(find.byKey(ProfileScreen.editDistrictKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ranchi').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.editBlockKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Namkum').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.editClassKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Class 3').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.saveEditKey));
      await tester.pumpAndSettle();

      final ClassroomSetup? saved = w.classrooms.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.schoolName, 'Kanke Primary School');
      expect(saved.districtName, 'Ranchi');
      expect(saved.blockName, 'Namkum');
      expect(saved.classLevel, 3);

      expect(find.text('Kanke Primary School'), findsOneWidget);
    });

    testWidgets('rejects an empty teacher name without saving', (
      WidgetTester tester,
    ) async {
      await open(tester, withAccount: true);

      await tester.tap(find.byKey(ProfileScreen.editButtonKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ProfileScreen.editTeacherNameKey),
        '   ',
      );
      await tester.tap(find.byKey(ProfileScreen.saveEditKey));
      await tester.pumpAndSettle();

      expect(find.text('Enter the teacher name.'), findsOneWidget);
      expect(find.text('Asha Murmu'), findsOneWidget);
    });

    testWidgets('flags classroom edits so they re-sync with the server', (
      WidgetTester tester,
    ) async {
      final w = await open(tester, withAccount: true);

      await tester.tap(find.byKey(ProfileScreen.editButtonKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ProfileScreen.editSchoolKey),
        'Kanke Primary School',
      );
      await tester.tap(find.byKey(ProfileScreen.saveEditKey));
      await tester.pumpAndSettle();

      final ClassroomSetup? saved = w.classrooms.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.pendingSync, isTrue);
    });
  });

  group('theme', () {
    testWidgets('the header toggle flips the app theme', (
      WidgetTester tester,
    ) async {
      final w = await open(tester);

      expect(w.appSettings.themeMode, ThemeMode.light);
      await tester.tap(find.byKey(ProfileScreen.themeToggleKey));
      await tester.pump();
      expect(w.appSettings.themeMode, ThemeMode.dark);
    });
  });

  group('connectivity banner', () {
    testWidgets('shows the offline state and offline AI badge', (
      WidgetTester tester,
    ) async {
      final ConnectivityService c = StaticConnectivityService(
        ConnectionStatus.offline,
      );
      await open(tester, connectivity: c);

      expect(find.text('You are in Offline Mode'), findsOneWidget);
      expect(
        find.text('All core features are available offline.'),
        findsOneWidget,
      );
      expect(find.text('Offline AI Active'), findsOneWidget);
    });

    testWidgets('shows the checking state while unknown', (
      WidgetTester tester,
    ) async {
      final ConnectivityService c = StaticConnectivityService(
        ConnectionStatus.unknown,
      );
      await open(tester, connectivity: c);

      expect(find.text('Checking connection…'), findsOneWidget);
    });

    testWidgets('updates live when connectivity changes', (
      WidgetTester tester,
    ) async {
      final StaticConnectivityService c = StaticConnectivityService(
        ConnectionStatus.offline,
      );
      await open(tester, connectivity: c);

      expect(find.text('You are in Offline Mode'), findsOneWidget);

      c.set(ConnectionStatus.online);
      await tester.pump();
      await tester.pump();

      expect(find.text('You are Online'), findsOneWidget);
      expect(find.text('You are in Offline Mode'), findsNothing);
    });
  });

  group('settings sections', () {
    testWidgets('classroom settings navigates to the setup flow', (
      WidgetTester tester,
    ) async {
      await open(tester, withAccount: true);

      await tester.tap(find.byKey(ProfileScreen.settingsLinkKey));
      await tester.pumpAndSettle();

      expect(find.byType(SetupScreen), findsOneWidget);
    });

    testWidgets('language & audio sheet lists voice controls', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.tap(find.byKey(ProfileScreen.languageAudioLinkKey));
      await tester.pumpAndSettle();

      expect(find.text('Language & Audio'), findsNWidgets(2));
      expect(find.text('Voice Speed'), findsOneWidget);
      expect(find.text('Pronunciation'), findsOneWidget);
    });

    testWidgets('offline & storage sheet lists both destinations', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.tap(find.byKey(ProfileScreen.offlineStorageLinkKey));
      await tester.pumpAndSettle();

      expect(find.text('Offline Center'), findsOneWidget);
      expect(find.text('Content Sync'), findsOneWidget);
    });
  });

  group('offline & storage destinations', () {
    testWidgets('opens the Offline Center', (WidgetTester tester) async {
      await open(tester);

      await tester.tap(find.byKey(ProfileScreen.offlineStorageLinkKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.offlineLinkKey));
      await tester.pumpAndSettle();

      expect(find.byType(OfflineCenterScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens the Content Sync screen', (WidgetTester tester) async {
      await open(tester);

      await tester.tap(find.byKey(ProfileScreen.offlineStorageLinkKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.syncLinkKey));
      await tester.pumpAndSettle();

      expect(find.byType(SyncCenterScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('language & audio', () {
    testWidgets('translation language change persists to the classroom', (
      WidgetTester tester,
    ) async {
      final w = await open(tester, withAccount: true);

      await tester.tap(find.byKey(ProfileScreen.languageAudioLinkKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.translationLanguageKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ho').last);
      await tester.pumpAndSettle();

      expect(w.classrooms.lastSaved!.targetLanguage, TargetLanguage.ho);
    });

    testWidgets('voice speed choice persists', (WidgetTester tester) async {
      final w = await open(tester);

      await tester.tap(find.byKey(ProfileScreen.languageAudioLinkKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ProfileScreen.voiceSpeedKey(VoiceSpeed.fast)),
      );
      await tester.pumpAndSettle();

      final ProfileSettings loaded = await w.settingsStore.load();
      expect(loaded.voiceSpeed, VoiceSpeed.fast);

      final String? raw = await w.storage.read('profile.settings');
      expect(raw, contains('voiceSpeed'));
    });

    testWidgets('pronunciation choice persists', (WidgetTester tester) async {
      final w = await open(tester);

      await tester.tap(find.byKey(ProfileScreen.languageAudioLinkKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ProfileScreen.pronunciationKey(PronunciationPreference.clear),
        ),
      );
      await tester.pumpAndSettle();

      final ProfileSettings loaded = await w.settingsStore.load();
      expect(loaded.pronunciation, PronunciationPreference.clear);
    });
  });

  group('accessibility', () {
    testWidgets('text size persists and is applied app-wide', (
      WidgetTester tester,
    ) async {
      final w = await open(tester);

      await tester.tap(find.byKey(ProfileScreen.accessibilityLinkKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.textSizeKey(TextSize.large)));
      await tester.pumpAndSettle();

      final ProfileSettings loaded = await w.settingsStore.load();
      expect(loaded.textSize, TextSize.large);
      expect(w.appSettings.textScale, closeTo(1.2, 0.001));
    });

    testWidgets('high contrast persists and is applied app-wide', (
      WidgetTester tester,
    ) async {
      final w = await open(tester);

      await tester.tap(find.byKey(ProfileScreen.accessibilityLinkKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.contrastKey));
      await tester.pumpAndSettle();

      final ProfileSettings loaded = await w.settingsStore.load();
      expect(loaded.highContrast, isTrue);
      expect(w.appSettings.highContrast, isTrue);
    });

    testWidgets('audio assistance persists', (WidgetTester tester) async {
      final w = await open(tester);

      await tester.tap(find.byKey(ProfileScreen.accessibilityLinkKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.audioKey));
      await tester.pumpAndSettle();

      final ProfileSettings loaded = await w.settingsStore.load();
      expect(loaded.audioAssistance, isFalse);
    });
  });

  group('support', () {
    testWidgets('help center opens a local help sheet', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.tap(find.byKey(ProfileScreen.supportLinkKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.helpKey));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Translation issues can be reported in Settings → Support, '
          'even offline.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('contact support opens a local sheet', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.tap(find.byKey(ProfileScreen.supportLinkKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.contactKey));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Your block resource centre supports this device and its '
          'content packs.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('reporting saves the issue on the device', (
      WidgetTester tester,
    ) async {
      final w = await open(tester);

      await tester.tap(find.byKey(ProfileScreen.supportLinkKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.reportKey));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ProfileScreen.reportFieldKey),
        'The Santali word on the seed flashcard sounds wrong.',
      );
      await tester.tap(find.byKey(ProfileScreen.reportSubmitKey));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Report saved on this device. It will be sent when you '
          'are online.',
        ),
        findsOneWidget,
      );

      final String? stored = await w.storage.read('profile.support.reports');
      expect(stored, contains('seed'));
    });

    testWidgets('an empty report shows an inline error', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.tap(find.byKey(ProfileScreen.supportLinkKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.reportKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.reportSubmitKey));
      await tester.pumpAndSettle();

      expect(find.text('Describe the problem first.'), findsOneWidget);
    });
  });

  group('feature hub', () {
    testWidgets('reaches existing feature screens', (
      WidgetTester tester,
    ) async {
      await open(tester);

      await tester.tap(find.byKey(ProfileScreen.lessonsLinkKey));
      await tester.pumpAndSettle();
      expect(find.byType(LessonLibraryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('app info', () {
    testWidgets('shows version, offline-first line and copyright', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(find.text('Version 1.0.0 • Offline First'), findsOneWidget);
      expect(find.textContaining('Offline First'), findsOneWidget);
      expect(find.text('© 2025 GyanSetu AI'), findsOneWidget);
    });
  });

  group('sign out', () {
    testWidgets('clears account, classroom and offline material', (
      WidgetTester tester,
    ) async {
      final auth_doubles.FakeAuthenticationService authentication =
          auth_doubles.FakeAuthenticationService();
      final w = await open(tester, withAccount: true, authentication: authentication);

      await tester.tap(find.byKey(ProfileScreen.logoutButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileScreen.logoutConfirmKey));
      await tester.pumpAndSettle();

      expect(authentication.signOutCalls, 1);
      expect(await w.session.account(), isNull);
      expect(await w.session.deviceId(), isNull);
      expect(w.classrooms.recordFor(auth_doubles.kTestTeacher.id), isNull);

      // The profile screen is gone; the auth route replaced it.
      expect(find.byType(ProfileScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
