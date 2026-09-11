import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../models/classroom_setup.dart';
import '../services/setup_controller.dart';

/// The three teaching-language cards.
///
/// Single-select: choosing one replaces the previous choice.
class TeachingLanguageCards extends StatelessWidget {
  const TeachingLanguageCards({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final TargetLanguage selected;
  final ValueChanged<TargetLanguage> onSelected;

  static const Map<TargetLanguage, String> motifs = <TargetLanguage, String>{
    TargetLanguage.santali: AppAssets.motifSantali,
    TargetLanguage.mundari: AppAssets.motifMundari,
    TargetLanguage.ho: AppAssets.motifHo,
    TargetLanguage.english: AppAssets.motifEnglish,
  };

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight so the three cards match the tallest of them. A bare
    // `stretch` Row asks for infinite height inside the scroll view.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final TargetLanguage language in TargetLanguage.values) ...<Widget>[
            if (language != TargetLanguage.values.first)
              const SizedBox(width: 11),
            Expanded(
              child: _LanguageCard(
                language: language,
                selected: language == selected,
                onTap: () => onSelected(language),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final TargetLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${language.label} teaching language'
          '${language.isPrototype ? ', prototype language' : ''}',
      child: ExcludeSemantics(
        child: Material(
          color: selected ? AppColors.setupSelectedCream : Colors.white,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(15),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: selected
                      ? AppColors.brandOrange
                      : AppColors.authFieldBorder,
                  width: selected ? 1.8 : 1.2,
                ),
              ),
              child: Stack(
                children: <Widget>[
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Image.asset(
                        TeachingLanguageCards.motifs[language]!,
                        height: 38,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                      ),
                      const SizedBox(height: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          language.label,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brandNavy,
                          ),
                        ),
                      ),
                      if (language.isPrototype) ...<Widget>[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brandGold.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Prototype Language',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandNavy
                                    .withValues(alpha: 0.88),
                              ),
                            ),
                          ),
                        ),
                      ] else
                        const SizedBox(height: 26),
                      const SizedBox(height: 10),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.authIconCircle,
                        ),
                        child: Icon(
                          Icons.volume_up_outlined,
                          size: 17,
                          color: AppColors.brandNavy.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                  if (selected)
                    Positioned(
                      top: -6,
                      right: -2,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.brandOrange,
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
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

/// Preview & Listen action beside the language sections.
class PreviewListenButton extends StatelessWidget {
  const PreviewListenButton({
    required this.state,
    required this.onPressed,
    super.key,
  });

  final PreviewState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, String label}) c = switch (state) {
      PreviewState.idle => (icon: Icons.volume_up_outlined, label: 'Preview & Listen'),
      PreviewState.loading => (icon: Icons.hourglass_empty, label: 'Preparing…'),
      PreviewState.playing => (icon: Icons.stop_circle_outlined, label: 'Stop'),
      PreviewState.unavailable => (icon: Icons.volume_off_outlined, label: 'No audio yet'),
    };

    return Semantics(
      button: true,
      label: c.label,
      child: ExcludeSemantics(
        child: OutlinedButton(
          onPressed: state == PreviewState.loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            foregroundColor: AppColors.brandNavy,
            side: const BorderSide(color: AppColors.authFieldBorder),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (state == PreviewState.loading)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(c.icon, size: 17),
              const SizedBox(width: 7),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    c.label,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Class 1 to 5, single-select.
class ClassSelector extends StatelessWidget {
  const ClassSelector({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    // One row of five, as in the reference. Expanded shares the width evenly
    // and the labels scale down, so they never wrap onto a second line.
    return Row(
      children: <Widget>[
        for (final int level in kSupportedClasses) ...<Widget>[
          if (level != kSupportedClasses.first) const SizedBox(width: 8),
          Expanded(
            child: _ClassChip(
              level: level,
              selected: level == selected,
              onTap: () => onSelected(level),
            ),
          ),
        ],
      ],
    );
  }
}

class _ClassChip extends StatelessWidget {
  const _ClassChip({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final int level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Class $level',
      child: ExcludeSemantics(
        child: Material(
          color: selected ? AppColors.authNavy : Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? AppColors.authNavy
                      : AppColors.authFieldBorder,
                  width: 1.2,
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Class $level',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : AppColors.brandNavy,
                      ),
                    ),
                    // The check, not only the fill, carries the selected state.
                    if (selected) ...<Widget>[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Colors.white,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subject cards. Multi-select; at least one is required to finish.
class SubjectCards extends StatelessWidget {
  const SubjectCards({
    required this.selected,
    required this.onToggle,
    super.key,
  });

  final Set<ClassroomSubject> selected;
  final ValueChanged<ClassroomSubject> onToggle;

  static const Map<ClassroomSubject, ({Color accent, Color tint, IconData icon})>
      styles = <ClassroomSubject, ({Color accent, Color tint, IconData icon})>{
    ClassroomSubject.foundationalLiteracy: (
      accent: AppColors.setupLiteracy,
      tint: AppColors.setupLiteracyTint,
      icon: Icons.menu_book_outlined,
    ),
    ClassroomSubject.numeracy: (
      accent: AppColors.setupNumeracy,
      tint: AppColors.setupNumeracyTint,
      icon: Icons.calculate_outlined,
    ),
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Side by side where there is room, stacked on a narrow handset so the
        // titles never truncate.
        final bool side = constraints.maxWidth >= 380;
        final List<Widget> cards = <Widget>[
          for (final ClassroomSubject subject in ClassroomSubject.values)
            _SubjectCard(
              subject: subject,
              selected: selected.contains(subject),
              onTap: () => onToggle(subject),
            ),
        ];

        if (!side) {
          return Column(
            children: <Widget>[
              cards.first,
              const SizedBox(height: 11),
              cards.last,
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: cards.first),
              const SizedBox(width: 11),
              Expanded(child: cards.last),
            ],
          ),
        );
      },
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({
    required this.subject,
    required this.selected,
    required this.onTap,
  });

  final ClassroomSubject subject;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ({Color accent, Color tint, IconData icon}) style =
        SubjectCards.styles[subject]!;

    return Semantics(
      button: true,
      selected: selected,
      label: '${subject.label}. ${subject.subtitle}',
      child: ExcludeSemantics(
        child: Material(
          color: selected ? style.tint : Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 14, 12, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? style.accent.withValues(alpha: 0.55)
                      : AppColors.authFieldBorder,
                  width: 1.2,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(style.icon, size: 26, color: style.accent),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          subject.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? style.accent
                                : AppColors.brandNavy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '(${subject.subtitle})',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                            color: (selected ? style.accent : AppColors.brandNavy)
                                .withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 21,
                    color: selected
                        ? style.accent
                        : AppColors.brandNavy.withValues(alpha: 0.25),
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
