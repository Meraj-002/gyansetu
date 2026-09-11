import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/routes.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/photo_fade.dart';
import '../../services/connectivity/connectivity_service.dart';
import '../../services/service_registry.dart';
import 'models/auth_result.dart';
import 'models/login_method.dart';
import 'models/teacher_account.dart';
import 'services/auth_session_store.dart';
import 'services/authentication_service.dart';
import 'services/login_controller.dart';
import 'services/offline_authentication_service.dart';
import 'widgets/login_chrome.dart';
import 'widgets/login_form_widgets.dart';
import 'widgets/privacy_card.dart';
import 'widgets/school_code_sheet.dart';

/// Teacher sign-in.
///
/// The screen renders a [LoginController] and routes on its result; it holds no
/// authentication or storage logic of its own. Services are injectable so tests
/// can drive every path without a keystore, a network, or a real backend.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    this.authenticationService,
    this.offlineService,
    this.connectivityService,
    this.sessionStore,
    super.key,
  });

  final AuthenticationService? authenticationService;
  final OfflineAuthenticationService? offlineService;
  final ConnectivityService? connectivityService;
  final AuthSessionStore? sessionStore;

  /// Field keys. Labels are not unique on this screen — 'Mobile Number' and
  /// 'Teacher ID' are tab captions too — so anything addressing a field does it
  /// by key.
  static const Key mobileFieldKey = Key('login.field.mobile');
  static const Key teacherIdFieldKey = Key('login.field.teacherId');
  static const Key pinFieldKey = Key('login.field.pin');

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final LoginController _controller;
  late final ConnectivityService _connectivity;
  final bool _ownsConnectivity;

  _LoginScreenState() : _ownsConnectivity = true;

  final TextEditingController _mobile = TextEditingController();
  final TextEditingController _teacherId = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  final FocusNode _pinFocus = FocusNode();

  @override
  void initState() {
    super.initState();

    final ServiceRegistry registry = ServiceRegistry.instance;
    final AuthSessionStore store = widget.sessionStore ?? registry.session;
    final OfflineAuthenticationService offline =
        widget.offlineService ?? registry.offline;

    _connectivity = widget.connectivityService ?? PlatformConnectivityService();

    _controller = LoginController(
      authentication:
          widget.authenticationService ??
          ServiceRegistry.instance.authentication,
      offline: offline,
      connectivity: _connectivity,
      store: store,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_ownsConnectivity && widget.connectivityService == null) {
      _connectivity.dispose();
    }
    _mobile.dispose();
    _teacherId.dispose();
    _pin.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final AuthResult? result = await _controller.submit();
    if (!mounted || result is! AuthSuccess) return;
    _routeAfter(result);
  }

  void _routeAfter(AuthSuccess result) {
    // The destination is decided by the service from stored setup state, not
    // guessed here, and it is reached through the central route table.
    AppRouter.replaceWithFade(context, switch (result.destination) {
      PostAuthDestination.home => AppRoutes.home,
      PostAuthDestination.setup => AppRoutes.setup,
    });
  }

  Future<void> _openSchoolCode() async {
    FocusScope.of(context).unfocus();
    final AuthSuccess? result = await SchoolCodeSheet.show(
      context,
      _controller,
    );
    if (!mounted || result == null) return;
    _routeAfter(result);
  }

  Future<void> _forgotPin() async {
    FocusScope.of(context).unfocus();
    final bool started = await _controller.requestPinRecovery();
    if (!mounted) return;

    if (started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recovery instructions are on their way.'),
        ),
      );
      return;
    }

    final bool offline =
        _controller.connectionStatus != ConnectionStatus.online;

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('PIN recovery needs the internet'),
        content: Text(
          offline
              ? 'You are offline. PIN recovery requires an internet '
                    'connection, because your PIN can only be reset by the '
                    'server — it is never reset on the device.'
              : 'PIN recovery is not available yet on this build. When it is, '
                    'it will run through the server; a PIN can never be reset on '
                    'the device alone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _controller.requestPinRecovery();
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.authNavy),
            child: const Text('Connect to Internet'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The backdrop must not be pushed around by the keyboard.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: LoginBackdrop()),
          SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (BuildContext context, Widget? _) => _body(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final double scale = (width / 390).clamp(0.86, 1.12).toDouble();
    // The card stops widening on large screens so line lengths stay readable.
    final double cardWidth = width.clamp(0.0, 560.0);
    final double sidePad = ((width - cardWidth) / 2) + 20;

    return SingleChildScrollView(
      // Room for the keyboard, since the Scaffold does not resize.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(sidePad, 12, sidePad, 0),
            // A Stack, not a Row: the reference centres the lock-up on the page
            // and tucks the status card into the corner over it. Sharing a Row
            // would pull the logo off centre as the card's text changes.
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Center(child: LoginMasthead(scale: scale)),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: cardWidth * 0.42),
                    child: ConnectivityChip(
                      status: _controller.connectionStatus,
                      hasOfflineAccount: _controller.hasOfflineAccount,
                      ready: _controller.ready,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const PhotoFade(
            top: 0.22,
            bottom: 0.30,
            child: Image(
              image: AssetImage(AppAssets.loginLandscape),
              width: double.infinity,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: sidePad),
            child: Column(
              children: <Widget>[
                Text(
                  'Welcome back, Teacher',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 27 * scale,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.brandNavy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Continue your mother-tongue classroom journey.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14 * scale,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: AppColors.brandNavy.withValues(alpha: 0.74),
                  ),
                ),
                const SizedBox(height: 14),
                const BrandRule(),
                const SizedBox(height: 22),
                _LoginCard(
                  controller: _controller,
                  mobile: _mobile,
                  teacherId: _teacherId,
                  pin: _pin,
                  pinFocus: _pinFocus,
                  onSubmit: _submit,
                  onForgotPin: _forgotPin,
                  onSchoolCode: _openSchoolCode,
                  onUseMethod: _controller.selectMethod,
                ),
                const SizedBox(height: 18),
                const PrivacyCard(),
                const SizedBox(height: 26),
                const LoginFooter(),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The elevated card holding the method tabs and the active form.
class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.controller,
    required this.mobile,
    required this.teacherId,
    required this.pin,
    required this.pinFocus,
    required this.onSubmit,
    required this.onForgotPin,
    required this.onSchoolCode,
    required this.onUseMethod,
  });

  final LoginController controller;
  final TextEditingController mobile;
  final TextEditingController teacherId;
  final TextEditingController pin;
  final FocusNode pinFocus;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPin;
  final VoidCallback onSchoolCode;
  final ValueChanged<LoginMethod> onUseMethod;

  bool get _busy => controller.busy;

  @override
  Widget build(BuildContext context) {
    final bool pinQuickLoginUnavailable =
        controller.method == LoginMethod.pin && !controller.hasOfflineAccount;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.brandNavy.withValues(alpha: 0.09),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.authIconCircle,
                ),
                child: const Icon(
                  Icons.person_outline,
                  size: 26,
                  color: AppColors.authNavy,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Login to your account',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandNavy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Choose your preferred login method',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.brandNavy.withValues(alpha: 0.66),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          LoginMethodTabs(
            selected: controller.method,
            enabled: !_busy,
            onChanged: onUseMethod,
          ),
          const SizedBox(height: 22),
          if (pinQuickLoginUnavailable)
            _NoOfflineAccountNotice(onUseMethod: onUseMethod)
          else ...<Widget>[
            ..._fieldsFor(controller.method),
            const SizedBox(height: 6),
            RememberMeRow(
              value: controller.rememberDevice,
              enabled: !_busy,
              onChanged: (bool v) => controller.setRememberDevice(value: v),
              onForgotPin: onForgotPin,
            ),
            if (controller.formError != null) ...<Widget>[
              const SizedBox(height: 6),
              FormErrorBanner(message: controller.formError!),
            ],
            const SizedBox(height: 18),
            ContinueButton(label: 'Continue', busy: _busy, onPressed: onSubmit),
          ],
          const SizedBox(height: 20),
          const OrDivider(),
          const SizedBox(height: 18),
          SizedBox(
            height: 58,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : onSchoolCode,
              icon: const Icon(Icons.account_balance_outlined, size: 21),
              label: const Text(
                'Login with school code',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.authNavy,
                side: const BorderSide(color: AppColors.authNavy, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _fieldsFor(LoginMethod method) {
    return switch (method) {
      LoginMethod.mobile => <Widget>[
        AuthField(
          key: LoginScreen.mobileFieldKey,
          label: 'Mobile Number',
          hint: 'Enter 10-digit mobile number',
          icon: Icons.call_outlined,
          controller: mobile,
          enabled: !_busy,
          errorText: controller.mobileError,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => pinFocus.requestFocus(),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          onChanged: controller.setMobile,
        ),
        const SizedBox(height: 18),
        _pinField(),
      ],
      LoginMethod.teacherId => <Widget>[
        AuthField(
          key: LoginScreen.teacherIdFieldKey,
          label: 'Teacher ID',
          hint: 'Enter your Teacher ID',
          icon: Icons.badge_outlined,
          controller: teacherId,
          enabled: !_busy,
          errorText: controller.teacherIdError,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => pinFocus.requestFocus(),
          onChanged: controller.setTeacherId,
        ),
        const SizedBox(height: 18),
        _pinField(),
      ],
      LoginMethod.pin => <Widget>[
        _ContinueAsCard(account: controller.provisionedAccount),
        const SizedBox(height: 18),
        _pinField(),
      ],
    };
  }

  Widget _pinField() {
    return AuthField(
      key: LoginScreen.pinFieldKey,
      label: 'Enter PIN',
      hint: 'Enter 4-digit PIN',
      icon: Icons.shield_outlined,
      controller: pin,
      focusNode: pinFocus,
      enabled: !_busy,
      errorText: controller.pinError,
      obscure: !controller.pinVisible,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmit(),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      suffix: PinVisibilityButton(
        visible: controller.pinVisible,
        onPressed: controller.togglePinVisibility,
      ),
      onChanged: controller.setPin,
    );
  }
}

/// Identity summary shown above the PIN field in quick-login mode.
class _ContinueAsCard extends StatelessWidget {
  const _ContinueAsCard({required this.account});

  final TeacherAccount? account;

  @override
  Widget build(BuildContext context) {
    final TeacherAccount? a = account;
    if (a == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.authChip,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Continue as',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: AppColors.brandNavy.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            a.displayName,
            style: const TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
              color: AppColors.brandNavy,
            ),
          ),
          Text(
            a.schoolName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.brandNavy.withValues(alpha: 0.68),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the PIN tab is chosen on a device that was never provisioned.
class _NoOfflineAccountNotice extends StatelessWidget {
  const _NoOfflineAccountNotice({required this.onUseMethod});

  final ValueChanged<LoginMethod> onUseMethod;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.info_outline,
                size: 19,
                color: AppColors.warning,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'No offline account is available on this device.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandNavy,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Sign in once with an internet connection to set this '
                      'device up. Quick PIN login works after that.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.brandNavy.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: () => onUseMethod(LoginMethod.mobile),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  foregroundColor: AppColors.authNavy,
                  side: const BorderSide(color: AppColors.authFieldBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const FittedBox(child: Text('Use Mobile Number')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => onUseMethod(LoginMethod.teacherId),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  foregroundColor: AppColors.authNavy,
                  side: const BorderSide(color: AppColors.authFieldBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const FittedBox(child: Text('Use Teacher ID')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
