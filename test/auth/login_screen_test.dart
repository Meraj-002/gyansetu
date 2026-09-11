import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyan_setu_ai/app/routes.dart';
import 'package:gyan_setu_ai/app/theme.dart';
import 'package:gyan_setu_ai/features/auth/login_screen.dart';
import 'package:gyan_setu_ai/features/auth/models/auth_result.dart';
import 'package:gyan_setu_ai/features/auth/services/auth_session_store.dart';
import 'package:gyan_setu_ai/features/auth/services/login_controller.dart';
import 'package:gyan_setu_ai/features/auth/services/offline_authentication_service.dart';
import 'package:gyan_setu_ai/features/auth/widgets/school_code_sheet.dart';
import 'package:gyan_setu_ai/features/setup/setup_screen.dart';
import 'package:gyan_setu_ai/services/connectivity/connectivity_service.dart';

import 'auth_test_doubles.dart';

void main() {
  late AuthSessionStore store;
  late OfflineAuthenticationService offline;
  late FakeAuthenticationService auth;
  late StaticConnectivityService connectivity;

  setUp(() {
    store = memoryStore();
    offline = OfflineAuthenticationService(store: store, hasher: kFastHasher);
    auth = FakeAuthenticationService(offline: offline);
    connectivity = StaticConnectivityService(ConnectionStatus.online);
  });

  Widget harness() => MaterialApp(
        theme: AppTheme.light,
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: LoginScreen(
          authenticationService: auth,
          offlineService: offline,
          connectivityService: connectivity,
          sessionStore: store,
        ),
      );

  /// Pumps the screen at a size tall enough that everything is laid out.
  Future<void> openLogin(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(430, 1400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
  }

  group('validation', () {
    test('mobile number rules', () {
      expect(LoginValidators.mobile(''), 'Enter your mobile number.');
      expect(
        LoginValidators.mobile('98765'),
        'Enter a valid 10-digit mobile number.',
      );
      expect(
        LoginValidators.mobile('98765abcde'),
        'Enter a valid 10-digit mobile number.',
      );
      expect(
        LoginValidators.mobile('12345678901'),
        'Enter a valid 10-digit mobile number.',
      );
      expect(
        LoginValidators.mobile('1234567890'),
        'Indian mobile numbers start with 6, 7, 8 or 9.',
      );
      expect(LoginValidators.mobile('9876543210'), isNull);
      expect(LoginValidators.mobile(' 9876543210 '), isNull);
    });

    test('teacher ID rules', () {
      expect(LoginValidators.teacherId('   '), 'Enter your Teacher ID.');
      expect(LoginValidators.teacherId('ab'), 'Teacher ID looks too short.');
      expect(LoginValidators.teacherId('a' * 33), 'Teacher ID looks too long.');
      expect(LoginValidators.teacherId('  JH-2291  '), isNull);
    });

    test('PIN rules', () {
      expect(LoginValidators.pin(''), 'Enter your PIN.');
      expect(LoginValidators.pin('12'), 'PIN must be 4 digits.');
      expect(LoginValidators.pin('12345'), 'PIN must be 4 digits.');
      expect(LoginValidators.pin('12a4'), 'PIN must be 4 digits.');
      expect(LoginValidators.pin('9310'), isNull);
    });
  });

  testWidgets('renders the reference structure with GyanSetu branding',
      (WidgetTester tester) async {
    await openLogin(tester);

    expect(find.textContaining('GyanSetu'), findsWidgets);
    expect(find.textContaining('BhashaSetu'), findsNothing);
    expect(find.text('Welcome back, Teacher'), findsOneWidget);
    expect(find.text('Login to your account'), findsOneWidget);
    expect(find.text('Mobile Number'), findsWidgets);
    expect(find.text('Teacher ID'), findsWidgets);
    expect(find.text('PIN'), findsWidgets);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Login with school code'), findsOneWidget);
    expect(find.text('Remember me on this device'), findsOneWidget);
    expect(find.text('Forgot PIN?'), findsOneWidget);
    expect(find.text('Your classroom data is protected.'), findsOneWidget);
    expect(find.text('Built for Bharat. By Bharat.'), findsOneWidget);
  });

  testWidgets('tabs switch which fields the form shows',
      (WidgetTester tester) async {
    await openLogin(tester);

    expect(find.text('Enter 10-digit mobile number'), findsOneWidget);

    await tester.tap(find.text('Teacher ID').last);
    await tester.pumpAndSettle();
    expect(find.text('Enter your Teacher ID'), findsOneWidget);
    expect(find.text('Enter 10-digit mobile number'), findsNothing);

    await tester.tap(find.text('PIN').last);
    await tester.pumpAndSettle();
    // Nothing is provisioned, so quick login must say so rather than offer it.
    expect(
      find.text('No offline account is available on this device.'),
      findsOneWidget,
    );
    expect(find.text('Use Mobile Number'), findsOneWidget);
    expect(find.text('Use Teacher ID'), findsOneWidget);
  });

  testWidgets('shows inline errors and does not call the service',
      (WidgetTester tester) async {
    await openLogin(tester);

    await tester.enterText(_field(LoginScreen.mobileFieldKey), '12345');
    await tester.enterText(_field(LoginScreen.pinFieldKey), '12');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid 10-digit mobile number.'), findsOneWidget);
    expect(find.text('PIN must be 4 digits.'), findsOneWidget);
    expect(auth.signInCalls, 0);
  });

  testWidgets('PIN is obscured until the visibility control is used',
      (WidgetTester tester) async {
    await openLogin(tester);

    TextField pinField() => tester.widget<TextField>(_field(LoginScreen.pinFieldKey));
    expect(pinField().obscureText, isTrue);

    await tester.tap(find.byTooltip('Show PIN'));
    await tester.pumpAndSettle();
    expect(pinField().obscureText, isFalse);

    await tester.tap(find.byTooltip('Hide PIN'));
    await tester.pumpAndSettle();
    expect(pinField().obscureText, isTrue);
  });

  testWidgets('remember me toggles and defaults to on',
      (WidgetTester tester) async {
    await openLogin(tester);

    Checkbox box() => tester.widget<Checkbox>(find.byType(Checkbox));
    expect(box().value, isTrue);

    await tester.tap(find.text('Remember me on this device'));
    await tester.pumpAndSettle();
    expect(box().value, isFalse);
  });

  testWidgets('shows a spinner and blocks repeat taps while authenticating',
      (WidgetTester tester) async {
    auth.latency = const Duration(milliseconds: 400);
    await openLogin(tester);

    await tester.enterText(_field(LoginScreen.mobileFieldKey), '9876543210');
    await tester.enterText(_field(LoginScreen.pinFieldKey), '4417');
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    // Fields are locked so values cannot change mid-request.
    expect(tester.widget<TextField>(_field(LoginScreen.pinFieldKey)).enabled, isFalse);

    // A second tap on the disabled button must not start another request.
    await tester.tap(find.byType(FilledButton).first, warnIfMissed: false);
    await tester.pump();
    expect(auth.signInCalls, 1);

    await tester.pumpAndSettle();
    expect(auth.signInCalls, 1);
  });

  testWidgets('successful sign-in with setup incomplete goes to Setup',
      (WidgetTester tester) async {
    await openLogin(tester);

    await tester.enterText(_field(LoginScreen.mobileFieldKey), '9876543210');
    await tester.enterText(_field(LoginScreen.pinFieldKey), '4417');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(SetupScreen), findsOneWidget);
  });

  testWidgets('successful sign-in with setup complete goes to Home',
      (WidgetTester tester) async {
    auth.result = const AuthSuccess(
      account: kTestTeacher,
      destination: PostAuthDestination.home,
      verifiedOnline: true,
    );
    await openLogin(tester);

    await tester.enterText(_field(LoginScreen.mobileFieldKey), '9876543210');
    await tester.enterText(_field(LoginScreen.pinFieldKey), '4417');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('failed sign-in keeps the form and shows a safe message',
      (WidgetTester tester) async {
    auth.result = const AuthFailure(AuthFailureReason.invalidCredentials);
    await openLogin(tester);

    await tester.enterText(_field(LoginScreen.mobileFieldKey), '9876543210');
    await tester.enterText(_field(LoginScreen.pinFieldKey), '4417');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Incorrect PIN. Please try again.'), findsOneWidget);
    // The entered values survive the failure.
    expect(find.text('9876543210'), findsOneWidget);
  });

  testWidgets('a transport failure never leaks the underlying error',
      (WidgetTester tester) async {
    auth.throwOnSignIn = true;
    await openLogin(tester);

    await tester.enterText(_field(LoginScreen.mobileFieldKey), '9876543210');
    await tester.enterText(_field(LoginScreen.pinFieldKey), '4417');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('couldn’t connect'), findsOneWidget);
    expect(find.textContaining('transport failed'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
  });

  testWidgets('offline with no provisioned device refuses to sign in',
      (WidgetTester tester) async {
    connectivity.set(ConnectionStatus.offline);
    await openLogin(tester);

    await tester.enterText(_field(LoginScreen.mobileFieldKey), '9876543210');
    await tester.enterText(_field(LoginScreen.pinFieldKey), '4417');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('not available for offline login'),
      findsOneWidget,
    );
    expect(auth.signInCalls, 0, reason: 'must not attempt the network');
  });

  testWidgets('offline quick PIN login works once the device is provisioned',
      (WidgetTester tester) async {
    await offline.provisionAfterOnlineSignIn(
      account: kTestTeacher,
      pin: '4417',
    );
    connectivity.set(ConnectionStatus.offline);
    await openLogin(tester);

    await tester.tap(find.text('PIN').last);
    await tester.pumpAndSettle();

    expect(find.text('Continue as'), findsOneWidget);
    expect(find.text(kTestTeacher.displayName), findsOneWidget);
    expect(find.text(kTestTeacher.schoolName), findsOneWidget);

    await tester.enterText(_field(LoginScreen.pinFieldKey), '4417');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsNothing);
    expect(auth.signInCalls, 0, reason: 'offline path must stay local');
  });

  testWidgets('offline quick PIN login rejects the wrong PIN',
      (WidgetTester tester) async {
    await offline.provisionAfterOnlineSignIn(
      account: kTestTeacher,
      pin: '4417',
    );
    connectivity.set(ConnectionStatus.offline);
    await openLogin(tester);

    await tester.tap(find.text('PIN').last);
    await tester.pumpAndSettle();
    await tester.enterText(_field(LoginScreen.pinFieldKey), '0000');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect PIN. Please try again.'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('the offline chip only promises access once provisioned',
      (WidgetTester tester) async {
    connectivity.set(ConnectionStatus.offline);
    await openLogin(tester);

    expect(find.textContaining('login unavailable'), findsOneWidget);

    await offline.provisionAfterOnlineSignIn(
      account: kTestTeacher,
      pin: '4417',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.textContaining('access available'), findsOneWidget);
  });

  testWidgets('school code sheet signs in and routes onward',
      (WidgetTester tester) async {
    await openLogin(tester);

    await tester.tap(find.text('Login with school code'));
    await tester.pumpAndSettle();

    expect(find.text('Login with school code'), findsWidgets);
    await tester.enterText(_field(SchoolCodeSheet.codeFieldKey), 'DUM-114');
    await tester.enterText(
      _field(SchoolCodeSheet.identifierFieldKey),
      'JH-2291',
    );
    await tester.enterText(_field(SchoolCodeSheet.pinFieldKey), '4417');
    await tester.tap(
      find.descendant(
        of: find.byType(SchoolCodeSheet),
        matching: find.text('Continue'),
      ),
    );
    await tester.pumpAndSettle();

    expect(auth.schoolCodeCalls, 1);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('school code offline without provisioning is refused',
      (WidgetTester tester) async {
    connectivity.set(ConnectionStatus.offline);
    await openLogin(tester);

    await tester.tap(find.text('Login with school code'));
    await tester.pumpAndSettle();

    await tester.enterText(_field(SchoolCodeSheet.codeFieldKey), 'DUM-114');
    await tester.enterText(
      _field(SchoolCodeSheet.identifierFieldKey),
      'JH-2291',
    );
    await tester.enterText(_field(SchoolCodeSheet.pinFieldKey), '4417');
    await tester.tap(
      find.descendant(
        of: find.byType(SchoolCodeSheet),
        matching: find.text('Continue'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('has not been verified'), findsOneWidget);
    expect(auth.schoolCodeCalls, 0);
  });

  testWidgets('Forgot PIN offline explains that recovery needs the internet',
      (WidgetTester tester) async {
    connectivity.set(ConnectionStatus.offline);
    await openLogin(tester);

    await tester.tap(find.text('Forgot PIN?'));
    await tester.pumpAndSettle();

    expect(find.text('PIN recovery needs the internet'), findsOneWidget);
    expect(find.textContaining('You are offline'), findsOneWidget);
    expect(find.text('Connect to Internet'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the privacy card opens the explanation sheet',
      (WidgetTester tester) async {
    await openLogin(tester);

    await tester.tap(find.text('Your classroom data is protected.'));
    await tester.pumpAndSettle();

    expect(find.text('How your data is protected'), findsOneWidget);
    expect(find.text('Your PIN is never stored'), findsOneWidget);
  });

  testWidgets('lays out on a small handset without overflow',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Welcome back, Teacher'), findsOneWidget);
  });
}

/// Addresses a field by key. Labels are ambiguous here: 'Mobile Number' and
/// 'Teacher ID' are also tab captions, and 'Enter PIN' appears in the school
/// code sheet as well.
Finder _field(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(TextField));
