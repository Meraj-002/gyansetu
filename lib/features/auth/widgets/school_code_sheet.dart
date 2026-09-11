import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../models/auth_result.dart';
import '../services/login_controller.dart';
import 'login_form_widgets.dart';

/// School-code sign-in, kept in its own sheet so it does not complicate the
/// main login card.
///
/// Pops an [AuthSuccess] when the code is accepted; the caller owns navigation.
class SchoolCodeSheet extends StatefulWidget {
  const SchoolCodeSheet({required this.controller, super.key});

  final LoginController controller;

  static const Key codeFieldKey = Key('schoolCode.field.code');
  static const Key identifierFieldKey = Key('schoolCode.field.identifier');
  static const Key pinFieldKey = Key('schoolCode.field.pin');

  static Future<AuthSuccess?> show(
    BuildContext context,
    LoginController controller,
  ) {
    return showModalBottomSheet<AuthSuccess>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) =>
          SchoolCodeSheet(controller: controller),
    );
  }

  @override
  State<SchoolCodeSheet> createState() => _SchoolCodeSheetState();
}

class _SchoolCodeSheetState extends State<SchoolCodeSheet> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _identifier = TextEditingController();
  final TextEditingController _pin = TextEditingController();

  String? _codeError;
  String? _identifierError;
  String? _pinError;
  String? _formError;
  bool _busy = false;
  bool _pinVisible = false;

  @override
  void dispose() {
    _code.dispose();
    _identifier.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;

    setState(() {
      _codeError = LoginValidators.schoolCode(_code.text);
      _identifierError = _identifier.text.trim().isEmpty
          ? 'Enter your Teacher ID or registered mobile number.'
          : null;
      _pinError = LoginValidators.pin(_pin.text);
      _formError = null;
    });

    if (_codeError != null || _identifierError != null || _pinError != null) {
      return;
    }

    setState(() => _busy = true);
    final AuthResult result = await widget.controller.submitSchoolCode(
      schoolCode: _code.text,
      identifier: _identifier.text,
      pin: _pin.text,
    );
    if (!mounted) return;

    setState(() => _busy = false);

    switch (result) {
      case AuthSuccess():
        Navigator.of(context).pop(result);
      case AuthFailure():
        setState(() => _formError = LoginController.messageFor(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.authFieldBorder,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Login with school code',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'First-time verification needs an internet connection.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.brandNavy.withValues(alpha: 0.68),
                ),
              ),
              const SizedBox(height: 20),
              AuthField(
                key: SchoolCodeSheet.codeFieldKey,
                label: 'School Code',
                hint: 'Enter your school code',
                icon: Icons.account_balance_outlined,
                controller: _code,
                enabled: !_busy,
                errorText: _codeError,
                textInputAction: TextInputAction.next,
                inputFormatters: <TextInputFormatter>[
                  UpperCaseTextFormatter(),
                ],
                onChanged: (_) {
                  if (_codeError != null) setState(() => _codeError = null);
                },
              ),
              const SizedBox(height: 16),
              AuthField(
                key: SchoolCodeSheet.identifierFieldKey,
                label: 'Teacher ID or mobile number',
                hint: 'Enter your Teacher ID or mobile number',
                icon: Icons.person_outline,
                controller: _identifier,
                enabled: !_busy,
                errorText: _identifierError,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  if (_identifierError != null) {
                    setState(() => _identifierError = null);
                  }
                },
              ),
              const SizedBox(height: 16),
              AuthField(
                key: SchoolCodeSheet.pinFieldKey,
                label: 'Enter PIN',
                hint: 'Enter 4-digit PIN',
                icon: Icons.shield_outlined,
                controller: _pin,
                enabled: !_busy,
                errorText: _pinError,
                obscure: !_pinVisible,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                suffix: PinVisibilityButton(
                  visible: _pinVisible,
                  onPressed: () => setState(() => _pinVisible = !_pinVisible),
                ),
                onChanged: (_) {
                  if (_pinError != null) setState(() => _pinError = null);
                },
              ),
              if (_formError != null) ...<Widget>[
                const SizedBox(height: 16),
                FormErrorBanner(message: _formError!),
              ],
              const SizedBox(height: 22),
              ContinueButton(
                label: 'Continue',
                busy: _busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps school codes in a single case so the provisioned-code check is stable.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

/// Whole-form error message shown above the primary action.
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 18, color: AppColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: AppColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
