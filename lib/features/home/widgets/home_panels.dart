import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../models/home_dashboard.dart';

/// One of the four shortcuts under Quick Actions.
class QuickAction {
  const QuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final String title;

  /// Dynamic on the Translate card, which names the classroom's language pair.
  final String subtitle;

  final IconData icon;
  final Color tint;
  final VoidCallback onTap;
}

/// The four quick-action cards.
class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({required this.actions, super.key});

  final List<QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Four across, as in the reference, wherever each card can hold about
        // 90dp. Below that they go two-by-two so the labels stay readable
        // rather than shrinking away.
        final int columns = constraints.maxWidth >= 380 ? 4 : 2;
        const double gap = 11;
        final double width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final QuickAction action in actions)
              SizedBox(width: width, child: _QuickActionCard(action: action)),
          ],
        );
      },
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.action});

  final QuickAction action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${action.title}. ${action.subtitle}',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            onTap: action.onTap,
            borderRadius: BorderRadius.circular(15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: AppColors.authFieldBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: action.tint.withValues(alpha: 0.14),
                    ),
                    child: Icon(action.icon, size: 24, color: action.tint),
                  ),
                  const SizedBox(height: 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      action.title,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandNavy,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    action.subtitle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.25,
                      color: AppColors.brandNavy.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.authFieldBorder),
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      size: 17,
                      color: AppColors.brandNavy.withValues(alpha: 0.7),
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

/// Today's teaching progress.
class ProgressPanel extends StatelessWidget {
  const ProgressPanel({
    required this.progress,
    required this.onViewReport,
    super.key,
  });

  final LearningProgress progress;
  final VoidCallback onViewReport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.show_chart_rounded,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      "Today's Progress",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandNavy,
                      ),
                    ),
                    Text(
                      progress.hasData
                          ? 'Great going! Keep it up.'
                          : 'Nothing recorded yet today.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.brandNavy.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!progress.hasData)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Complete a lesson or an assessment and it will show up here.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.brandNavy.withValues(alpha: 0.7),
                ),
              ),
            )
          else ...<Widget>[
            _ProgressRow(
              icon: Icons.menu_book_outlined,
              tint: AppColors.authNavy,
              label: 'Lessons completed',
              value: '${progress.lessonsCompleted}/${progress.lessonsPlanned}',
              fraction: progress.lessonFraction,
            ),
            const SizedBox(height: 14),
            _ProgressRow(
              icon: Icons.groups_outlined,
              tint: AppColors.setupLiteracy,
              label: 'Students engaged',
              value: '${progress.studentsEngaged}',
              // No roll target exists yet, so the bar shows presence rather
              // than a proportion of an invented class size.
              fraction: progress.studentsEngaged > 0 ? 0.72 : 0,
            ),
            const SizedBox(height: 14),
            _ProgressRow(
              icon: Icons.workspace_premium_outlined,
              tint: AppColors.brandOrange,
              label: 'Assessment',
              value: progress.assessmentPercent == null
                  ? '—'
                  : '${progress.assessmentPercent}%',
              fraction: (progress.assessmentPercent ?? 0) / 100,
            ),
          ],
          const SizedBox(height: 6),
          const Divider(color: AppColors.authFieldBorder, height: 18),
          Semantics(
            button: true,
            label: 'View detailed report',
            child: ExcludeSemantics(
              child: InkWell(
                onTap: onViewReport,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'View detailed report',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.authNavy,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: AppColors.brandNavy.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    required this.fraction,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String value;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label, $value',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.12),
              ),
              child: Icon(icon, size: 19, color: tint),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandNavy,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandNavy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: AppColors.authFieldBorder,
                      valueColor: AlwaysStoppedAnimation<Color>(tint),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Offline readiness, described from the real resource check.
class OfflinePanel extends StatelessWidget {
  const OfflinePanel({
    required this.state,
    required this.onManage,
    super.key,
  });

  final HomeOfflineState state;
  final VoidCallback onManage;

  ({Color accent, IconData icon}) get _style => switch (state) {
        HomeOfflineState.offlineReady =>
          (accent: AppColors.setupLiteracy, icon: Icons.cloud_done_outlined),
        HomeOfflineState.onlineSyncAvailable =>
          (accent: AppColors.info, icon: Icons.cloud_sync_outlined),
        HomeOfflineState.partial =>
          (accent: AppColors.warning, icon: Icons.cloud_queue),
        HomeOfflineState.missing =>
          (accent: AppColors.warning, icon: Icons.cloud_off),
        HomeOfflineState.error =>
          (accent: AppColors.error, icon: Icons.error_outline),
        HomeOfflineState.unknown =>
          (accent: AppColors.brandMuted, icon: Icons.cloud_queue),
      };

  @override
  Widget build(BuildContext context) {
    final ({Color accent, IconData icon}) s = _style;

    return Semantics(
      label: '${state.title}. ${state.description}',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.homeOfflineTint,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: s.accent.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: s.accent.withValues(alpha: 0.13),
                        ),
                        child: Icon(s.icon, size: 23, color: s.accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              state.title,
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: s.accent,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              state.description,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: AppColors.brandNavy
                                    .withValues(alpha: 0.78),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Capped: the scene is a 1.7:1 band, and at full card width it
                // would tower over the text it belongs to.
                SizedBox(
                  height: 118,
                  width: double.infinity,
                  child: Image.asset(
                    AppAssets.homeOfflineScene,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    excludeFromSemantics: true,
                  ),
                ),
                Material(
                  color: Colors.white.withValues(alpha: 0.85),
                  child: InkWell(
                    onTap: onManage,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      child: Row(
                        children: <Widget>[
                          const Expanded(
                            child: Text(
                              'Manage Offline Content',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.setupLiteracy,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: AppColors.setupLiteracy
                                .withValues(alpha: 0.8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The closing informational strip.
///
/// Describes what the product is, and claims nothing it does not do.
class AiBanner extends StatelessWidget {
  const AiBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.verified_user_outlined,
            size: 27,
            color: AppColors.brandNavy.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'AI-Powered  •  Offline-First  •  Mother Tongue Education',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandNavy.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your trusted AI assistant for inclusive classrooms.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.brandNavy.withValues(alpha: 0.66),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
