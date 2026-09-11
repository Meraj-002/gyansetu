import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../models/login_method.dart';

/// The three-way method selector at the top of the login card.
///
/// A real control, not decoration: the selection drives which fields the form
/// shows. State is carried by more than colour — the selected segment also
/// announces itself to screen readers.
class LoginMethodTabs extends StatelessWidget {
  const LoginMethodTabs({
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final LoginMethod selected;
  final ValueChanged<LoginMethod> onChanged;
  final bool enabled;

  static const Map<LoginMethod, IconData> icons = <LoginMethod, IconData>{
    LoginMethod.mobile: Icons.smartphone,
    LoginMethod.teacherId: Icons.badge_outlined,
    LoginMethod.pin: Icons.lock_outline,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: <Widget>[
          for (final LoginMethod method in LoginMethod.values)
            Expanded(
              child: _Segment(
                method: method,
                selected: method == selected,
                enabled: enabled,
                onTap: () => onChanged(method),
                showLeftDivider: method != LoginMethod.values.first,
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.method,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.showLeftDivider,
  });

  final LoginMethod method;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final bool showLeftDivider;

  @override
  Widget build(BuildContext context) {
    final Color foreground =
        selected ? Colors.white : AppColors.brandNavy;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${method.label} login',
      child: ExcludeSemantics(
        child: Material(
          color: selected ? AppColors.authNavy : Colors.white,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Container(
              // Comfortably past the 48dp minimum target.
              height: 54,
              decoration: BoxDecoration(
                border: showLeftDivider && !selected
                    ? const Border(
                        left: BorderSide(color: AppColors.authFieldBorder),
                      )
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    LoginMethodTabs.icons[method],
                    size: 16,
                    color: foreground,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        method.label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled input matching the reference's field treatment.
class AuthField extends StatelessWidget {
  const AuthField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    required this.onChanged,
    this.errorText,
    this.keyboardType,
    this.inputFormatters,
    this.obscure = false,
    this.suffix,
    this.enabled = true,
    this.textInputAction,
    this.onSubmitted,
    this.focusNode,
    super.key,
  });

  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscure;
  final Widget? suffix;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final bool hasError = errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.brandNavy,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          enabled: enabled,
          obscureText: obscure,
          obscuringCharacter: '•',
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w500,
            color: AppColors.brandNavy,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppColors.authHint,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Icon(icon, size: 20, color: AppColors.brandNavy),
            suffixIcon: suffix,
            filled: true,
            fillColor: enabled ? Colors.white : const Color(0xFFF6F6F8),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
            border: _border(AppColors.authFieldBorder),
            enabledBorder: _border(
              hasError ? AppColors.error : AppColors.authFieldBorder,
            ),
            disabledBorder: _border(AppColors.authFieldBorder),
            focusedBorder: _border(
              hasError ? AppColors.error : AppColors.authNavy,
              width: 1.6,
            ),
            // The message is rendered below so the field keeps a fixed height
            // and the card does not jump as errors appear.
            errorStyle: const TextStyle(height: 0, fontSize: 0),
          ),
        ),
        if (hasError) ...<Widget>[
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.error_outline,
                size: 15,
                color: AppColors.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  errorText!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static OutlineInputBorder _border(Color colour, {double width = 1.2}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(color: colour, width: width),
    );
  }
}

/// Visibility toggle for the PIN field.
class PinVisibilityButton extends StatelessWidget {
  const PinVisibilityButton({
    required this.visible,
    required this.onPressed,
    super.key,
  });

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      // The value is announced, so the state is not carried by the icon alone.
      tooltip: visible ? 'Hide PIN' : 'Show PIN',
      icon: Icon(
        visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 21,
        color: AppColors.brandNavy.withValues(alpha: 0.75),
      ),
    );
  }
}

/// Remember-me checkbox paired with the Forgot PIN action.
class RememberMeRow extends StatelessWidget {
  const RememberMeRow({
    required this.value,
    required this.onChanged,
    required this.onForgotPin,
    this.enabled = true,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback onForgotPin;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Flexible(
          child: InkWell(
            onTap: enabled ? () => onChanged(!value) : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 6, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: value,
                      onChanged: enabled
                          ? (bool? next) => onChanged(next ?? false)
                          : null,
                      activeColor: AppColors.authNavy,
                      side: const BorderSide(
                        color: AppColors.authFieldBorder,
                        width: 1.6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      'Remember me on this device',
                      // Two lines rather than an ellipsis: truncating a
                      // checkbox label hides what is being agreed to.
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.brandNavy.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: enabled ? onForgotPin : null,
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 44),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            foregroundColor: AppColors.authNavy,
          ),
          child: const Text(
            'Forgot PIN?',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// The full-width navy Continue button, with its loading and disabled states.
class ContinueButton extends StatelessWidget {
  const ContinueButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final String label;

  /// Null disables the button. While [busy] the tap handler is dropped too, so
  /// a second tap cannot start a second request.
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !busy;

    return Semantics(
      button: true,
      enabled: enabled,
      label: busy ? 'Signing in' : label,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 58,
          width: double.infinity,
          child: FilledButton(
            onPressed: enabled ? onPressed : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.authNavy,
              disabledBackgroundColor:
                  AppColors.authNavy.withValues(alpha: 0.45),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.arrow_forward, size: 20),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// "OR" rule between the primary action and the school-code route.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Expanded(child: Divider(color: AppColors.authFieldBorder)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OR',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.brandNavy.withValues(alpha: 0.55),
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.authFieldBorder)),
      ],
    );
  }
}
