import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// Numbered circle plus title, and optionally a subtitle and a trailing action,
/// used to open each section of the form.
class SetupSectionHeader extends StatelessWidget {
  const SetupSectionHeader({
    required this.step,
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final int step;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // On a narrow handset the title and a Preview & Listen button cannot
        // share a line, so the action drops beneath rather than overflowing.
        final bool inline = trailing == null || constraints.maxWidth >= 380;
        final Widget heading = _heading(inline: inline);

        if (inline) return heading;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            heading,
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: trailing),
          ],
        );
      },
    );
  }

  Widget _heading({required bool inline}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.authNavy,
          ),
          child: Text(
            '$step',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: AppColors.brandNavy.withValues(alpha: 0.66),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (inline && trailing != null) ...<Widget>[
          const SizedBox(width: 10),
          Flexible(child: trailing!),
        ],
      ],
    );
  }
}

/// Small label above a field, matching the reference's field treatment.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.brandNavy,
      ),
    );
  }
}

/// Inline validation message. Paired with an icon so the error is not carried
/// by colour alone.
class FieldError extends StatelessWidget {
  const FieldError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, size: 14, color: AppColors.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A bordered box shared by the text field and the two dropdowns, so all three
/// have identical height, radius and border treatment.
class FieldShell extends StatelessWidget {
  const FieldShell({
    required this.child,
    this.hasError = false,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final bool hasError;
  final bool enabled;

  static const double height = 54;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: enabled ? Colors.white : const Color(0xFFF6F6F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError ? AppColors.error : AppColors.authFieldBorder,
          width: hasError ? 1.5 : 1.2,
        ),
      ),
      child: child,
    );
  }
}

/// Dropdown styled to match the reference, with a leading icon and a chevron.
class SetupDropdown<T> extends StatelessWidget {
  const SetupDropdown({
    required this.icon,
    required this.hint,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.enabled = true,
    this.hasError = false,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String hint;
  final T? value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?>? onChanged;
  final bool enabled;
  final bool hasError;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final bool active = enabled && items.isNotEmpty;

    return Semantics(
      label: semanticLabel ?? hint,
      enabled: active,
      child: FieldShell(
        hasError: hasError,
        enabled: active,
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: 19,
              color: active
                  ? AppColors.brandNavy
                  : AppColors.brandNavy.withValues(alpha: 0.35),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  focusColor: Colors.transparent,
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: active
                        ? AppColors.brandNavy.withValues(alpha: 0.7)
                        : AppColors.brandNavy.withValues(alpha: 0.3),
                  ),
                  hint: Text(
                    hint,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: AppColors.authHint,
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandNavy,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  onChanged: active ? onChanged : null,
                  selectedItemBuilder: (BuildContext context) => <Widget>[
                    for (final T item in items)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          labelOf(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandNavy,
                          ),
                        ),
                      ),
                  ],
                  items: <DropdownMenuItem<T>>[
                    for (final T item in items)
                      DropdownMenuItem<T>(
                        value: item,
                        child: Text(
                          labelOf(item),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The saffron primary action at the foot of the form.
class FinishSetupButton extends StatelessWidget {
  const FinishSetupButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final String label;

  /// Null disables the button; [busy] also blocks a second tap.
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bool active = onPressed != null && !busy;

    return Semantics(
      button: true,
      enabled: active,
      label: busy ? 'Saving your classroom' : label,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 62,
          width: double.infinity,
          child: FilledButton(
            onPressed: active ? onPressed : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.setupCta,
              disabledBackgroundColor:
                  AppColors.setupCta.withValues(alpha: 0.40),
              foregroundColor: AppColors.brandNavy,
              disabledForegroundColor:
                  AppColors.brandNavy.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.brandNavy,
                      ),
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
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.arrow_forward, size: 21),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
