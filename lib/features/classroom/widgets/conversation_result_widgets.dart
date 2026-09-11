import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../setup/models/classroom_setup.dart';
import '../models/classroom_insights.dart';
import '../models/classroom_session.dart';
import '../models/conversation_turn.dart';
import '../services/conversation_result_controller.dart';

/// The navy header: back, branding, connectivity, session identity.
class ResultHeader extends StatelessWidget {
  const ResultHeader({
    required this.session,
    required this.offline,
    required this.onBack,
    required this.onMore,
    super.key,
  });

  final ClassroomSession session;

  /// The device's connectivity right now, used only when the session itself
  /// recorded nothing to go on.
  final bool offline;

  final VoidCallback onBack;
  final VoidCallback onMore;

  /// What the pill claims, read from what the session recorded rather than
  /// from a constant.
  ({String title, String value, Color tint}) get _status {
    return switch (session.connectivity) {
      SessionConnectivity.offline => (
          title: 'Offline Mode',
          value: 'Active',
          tint: AppColors.liveStudent,
        ),
      SessionConnectivity.partial => (
          title: 'Offline Mode',
          value: 'Partial',
          tint: AppColors.brandGold,
        ),
      SessionConnectivity.online => (
          title: 'Online Mode',
          value: 'Active',
          tint: AppColors.liveGlowCyan,
        ),
      // Nothing was recorded, so the device's present state is all that can be
      // said, and it is labelled as the device's rather than the session's.
      SessionConnectivity.unknown => (
          title: offline ? 'Offline' : 'Online',
          value: 'No turns recorded',
          tint: AppColors.liveTextMuted,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ({String title, String value, Color tint}) status = _status;

    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(color: AppColors.liveBackground),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool showWordmark = constraints.maxWidth >= 380;

            return Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 6, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      IconButton(
                        key: const Key('result-back'),
                        onPressed: onBack,
                        tooltip: 'Back',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.arrow_back, size: 23),
                        color: Colors.white,
                      ),
                      Image.asset(
                        AppAssets.loginBrandMark,
                        height: 30,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                      ),
                      if (showWordmark) ...<Widget>[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Semantics(
                            label: 'GyanSetu AI',
                            child: ExcludeSemantics(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text.rich(
                                  TextSpan(
                                    children: const <InlineSpan>[
                                      TextSpan(
                                        text: 'GyanSetu',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      TextSpan(text: ' '),
                                      TextSpan(
                                        text: 'AI',
                                        style: TextStyle(
                                          color: AppColors.brandGold,
                                        ),
                                      ),
                                    ],
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ] else
                        Semantics(
                          label: 'GyanSetu AI',
                          child: const SizedBox.shrink(),
                        ),
                      const Spacer(),
                      Semantics(
                        key: const Key('result-status'),
                        liveRegion: true,
                        label: '${status.title}: ${status.value}',
                        child: ExcludeSemantics(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.liveCardRaised,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.liveBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: status.tint,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 128),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          status.title,
                                          maxLines: 1,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.liveTextMuted,
                                          ),
                                        ),
                                      ),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          status.value,
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: status.tint,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('result-more'),
                        onPressed: onMore,
                        tooltip: 'Session options',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.more_vert, size: 21),
                        color: Colors.white,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _identity(context, constraints.maxWidth),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _identity(BuildContext context, double width) {
    final Widget title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Classroom Conversation',
            maxLines: 1,
            style: TextStyle(
              fontSize: 27,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            // Class and both languages, straight from the saved session.
            'Class ${session.classNumber}  •  '
            '${_languageName(session.teachingLanguage)} ↔ '
            '${_languageName(session.targetLanguage)}',
            maxLines: 1,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.liveGlowCyan,
            ),
          ),
        ),
      ],
    );

    final Widget meta = Column(
      crossAxisAlignment:
          width >= 420 ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: AppColors.liveTextMuted,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  // The session's own start time, formatted for the device.
                  '${_dateLabel(session.startedAt)}  •  '
                  '${TimeOfDay.fromDateTime(session.startedAt).format(context)}',
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.liveTextPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Session ID: ${session.sessionId}',
            maxLines: 1,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.liveTextMuted,
            ),
          ),
        ),
      ],
    );

    if (width < 420) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[title, const SizedBox(height: 10), meta],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(child: title),
        const SizedBox(width: 12),
        Flexible(child: meta),
      ],
    );
  }
}

/// The four-metric card that straddles the header.
class SessionMetricsCard extends StatelessWidget {
  const SessionMetricsCard({required this.session, super.key});

  final ClassroomSession session;

  @override
  Widget build(BuildContext context) {
    final Duration? average = session.averageLatency;
    final int? offlinePercentage = session.offlinePercentage;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.authFieldBorder),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.brandNavy.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final List<Widget> metrics = <Widget>[
            _Metric(
              icon: Icons.schedule,
              tint: AppColors.setupNumeracy,
              label: 'Duration',
              value: session.durationLabel,
              unit: 'min',
            ),
            _Metric(
              icon: Icons.translate,
              tint: AppColors.liveGlowViolet,
              label: 'Translations',
              value: '${session.translationCount}',
              unit: 'total',
            ),
            _Metric(
              icon: Icons.graphic_eq,
              tint: AppColors.setupLiteracy,
              label: 'Average Latency',
              // A dash where nothing was measured. Never a plausible number.
              value: average == null
                  ? '--'
                  : (average.inMilliseconds / 1000).toStringAsFixed(1),
              unit: average == null ? '' : 'sec',
            ),
            _Metric(
              icon: Icons.cloud_off,
              tint: AppColors.brandGold,
              label: session.connectivity == SessionConnectivity.online
                  ? 'Online Mode'
                  : 'Offline Mode',
              value: session.connectivity.label,
              // The percentage only appears when there were turns to measure.
              footnote:
                  offlinePercentage == null ? null : '$offlinePercentage%',
            ),
          ];

          // Two rows of two unless there is real room. Four metrics across a
          // normal phone leave each about 90dp, which cannot hold "Average
          // Latency" without the label shrinking to nothing.
          if (constraints.maxWidth < 420) {
            return Column(
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: metrics[0]),
                    const _Divider(),
                    Expanded(child: metrics[1]),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: metrics[2]),
                    const _Divider(),
                    Expanded(child: metrics[3]),
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: metrics[0]),
              const _Divider(),
              Expanded(child: metrics[1]),
              const _Divider(),
              Expanded(child: metrics[2]),
              const _Divider(),
              Expanded(child: metrics[3]),
            ],
          );
        },
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 76,
        color: AppColors.outlineVariant,
      );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.tint,
    required this.label,
    required this.value,
    this.unit,
    this.footnote,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String value;
  final String? unit;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value ${unit ?? ''} ${footnote ?? ''}'.trim(),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.brandNavy.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      value,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.brandNavy,
                      ),
                    ),
                    if ((unit ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(width: 4),
                      Text(
                        unit!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.brandNavy.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (footnote != null)
                Text(
                  footnote!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandNavy.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of the recorded conversation, on its timeline rail.
class TimelineRow extends StatelessWidget {
  const TimelineRow({
    required this.entry,
    required this.playKey,
    required this.isLast,
    required this.onPlay,
    super.key,
  });

  final ResultTimelineEntry entry;
  final Key playKey;
  final bool isLast;
  final VoidCallback onPlay;

  ({Color tint, Color tone, IconData icon}) get _identity =>
      switch (entry.speaker) {
        TurnSpeaker.teacher => (
            tint: AppColors.setupNumeracy,
            tone: AppColors.setupNumeracyTint,
            icon: Icons.co_present_outlined,
          ),
        TurnSpeaker.ai => (
            tint: AppColors.liveGlowViolet,
            tone: const Color(0xFFF4F1FE),
            icon: Icons.smart_toy_outlined,
          ),
        TurnSpeaker.student => (
            tint: AppColors.setupLiteracy,
            tone: AppColors.homeOfflineTint,
            icon: Icons.person_outline,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final ({Color tint, Color tone, IconData icon}) style = _identity;
    final double? confidence = entry.confidence;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: style.tint,
                ),
                child: Icon(style.icon, size: 21, color: Colors.white),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.outlineVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 13),
                decoration: BoxDecoration(
                  color: entry.failed
                      ? AppColors.error.withValues(alpha: 0.06)
                      : style.tone,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: entry.failed
                        ? AppColors.error.withValues(alpha: 0.3)
                        : style.tint.withValues(alpha: 0.22),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              entry.title,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: style.tint,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeLabel(entry.timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.brandNavy.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                entry.text,
                                style: TextStyle(
                                  fontSize: 17,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                  color: entry.failed
                                      ? AppColors.error
                                      : AppColors.brandNavy,
                                ),
                              ),
                              if (entry.secondaryText != null) ...<Widget>[
                                const SizedBox(height: 4),
                                Text(
                                  '(${entry.secondaryText})',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.35,
                                    color: AppColors.brandNavy
                                        .withValues(alpha: 0.62),
                                  ),
                                ),
                              ],
                              // The badge appears only when the provider gave a
                              // number. An absent confidence is not a high one.
                              if (confidence != null) ...<Widget>[
                                const SizedBox(height: 8),
                                ConfidenceBadge(confidence: confidence),
                              ],
                            ],
                          ),
                        ),
                        if (entry.playable) ...<Widget>[
                          const SizedBox(width: 8),
                          Semantics(
                            button: true,
                            label: 'Play this line aloud',
                            child: ExcludeSemantics(
                              child: Material(
                                color: Colors.white,
                                shape: CircleBorder(
                                  side: BorderSide(
                                    color:
                                        style.tint.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: InkWell(
                                  key: playKey,
                                  onTap: onPlay,
                                  customBorder: const CircleBorder(),
                                  child: SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: Icon(
                                      Icons.volume_up_outlined,
                                      size: 20,
                                      color: style.tint,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How sure the provider was, shown only when it said.
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({required this.confidence, super.key});

  /// 0..1.
  final double confidence;

  @override
  Widget build(BuildContext context) {
    final int percent = (confidence * 100).round();
    final bool low = confidence < ConversationTurn.lowConfidenceThreshold;
    final Color tint = low ? AppColors.warning : AppColors.setupLiteracy;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Not colour alone: a low reading is spelled out.
          if (low) ...<Widget>[
            Icon(Icons.help_outline, size: 13, color: tint),
            const SizedBox(width: 5),
          ],
          // Flexible so the longer low-confidence wording wraps on a narrow
          // phone instead of running off the badge.
          Flexible(
            child: Text(
              low
                  ? 'Confidence $percent% — please verify'
                  : 'Confidence $percent%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The insights card.
class InsightsCard extends StatelessWidget {
  const InsightsCard({required this.insights, required this.onReport, super.key});

  final ClassroomInsights? insights;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final ClassroomInsights? value = insights;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
                Icons.insights_outlined,
                size: 22,
                color: AppColors.setupNumeracy,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Classroom Insights',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (value == null)
            Text(
              "Classroom insights aren't available yet.",
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.brandNavy.withValues(alpha: 0.7),
              ),
            )
          else ...<Widget>[
            _stats(value),
            const SizedBox(height: 16),
            _concepts(value),
            if (value.recommendation != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                value.recommendation!,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.brandNavy.withValues(alpha: 0.72),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _stats(ClassroomInsights value) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final List<Widget> cells = <Widget>[
          _InsightStat(
            icon: Icons.groups_outlined,
            tint: AppColors.setupNumeracy,
            value: '${value.interactionsCompleted}',
            label: 'Interactions completed',
            note: value.interactionsCompleted > 0
                ? 'Great participation!'
                : 'No completed interactions',
          ),
          _InsightStat(
            icon: Icons.track_changes,
            tint: AppColors.brandGold,
            // Null and zero are different: nobody has checked, versus nothing
            // needs work.
            value: value.conceptsNeedingReinforcement?.toString(),
            label: 'Concepts need reinforcement',
            note: value.hasAssessment
                ? "We'll help you practise"
                : 'Complete an assessment to identify reinforcement areas.',
          ),
          _InsightStat(
            icon: Icons.sentiment_satisfied_alt_outlined,
            tint: AppColors.setupLiteracy,
            valueText: value.engagement.label,
            label: '',
            note: value.engagement == EngagementLevel.active
                ? 'Keep up the good work!'
                : null,
          ),
        ];

        if (constraints.maxWidth < 400) {
          return Column(
            children: <Widget>[
              for (int i = 0; i < cells.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == cells.length - 1 ? 0 : 14),
                  child: cells[i],
                ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: cells[0]),
            const _Divider(),
            Expanded(child: cells[1]),
            const _Divider(),
            Expanded(child: cells[2]),
          ],
        );
      },
    );
  }

  Widget _concepts(ClassroomInsights value) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.homePage,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Top Concepts Discussed',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 10),
          if (value.concepts.isEmpty)
            Text(
              'This lesson does not name its concepts yet, so none can be '
              'listed.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.brandNavy.withValues(alpha: 0.68),
              ),
            )
          else
            Wrap(
              spacing: 16,
              runSpacing: 10,
              children: <Widget>[
                for (final ConceptOutcome concept in value.concepts)
                  _Concept(outcome: concept),
              ],
            ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: Semantics(
              button: true,
              label: 'View the detailed session report',
              child: ExcludeSemantics(
                child: OutlinedButton(
                  key: const Key('result-detailed-report'),
                  onPressed: onReport,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandNavy,
                    minimumSize: const Size(0, 46),
                    side: const BorderSide(color: AppColors.authFieldBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'View Detailed Report',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right, size: 20),
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

class _InsightStat extends StatelessWidget {
  const _InsightStat({
    required this.icon,
    required this.tint,
    required this.label,
    this.value,
    this.valueText,
    this.note,
  });

  final IconData icon;
  final Color tint;

  /// Null renders an em dash, which is what "nobody checked" looks like.
  final String? value;

  final String? valueText;
  final String label;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
                child: Icon(icon, size: 19, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (valueText != null)
                      Text(
                        valueText!,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: tint,
                        ),
                      )
                    else
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value ?? '—',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 26,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: tint,
                          ),
                        ),
                      ),
                    if (label.isNotEmpty)
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandNavy.withValues(alpha: 0.78),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              note!,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.brandNavy.withValues(alpha: 0.62),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Concept extends StatelessWidget {
  const _Concept({required this.outcome});

  final ConceptOutcome outcome;

  ({Color tint, IconData icon}) get _style => switch (outcome.status) {
        ConceptStatus.completed => (
            tint: AppColors.setupNumeracy,
            icon: Icons.check_circle,
          ),
        ConceptStatus.needsReinforcement => (
            tint: AppColors.warning,
            icon: Icons.error_outline,
          ),
        ConceptStatus.discussed => (
            tint: AppColors.brandMuted,
            icon: Icons.radio_button_unchecked,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final ({Color tint, IconData icon}) style = _style;

    return Semantics(
      label: '${outcome.concept}: ${outcome.status.label}',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(style.icon, size: 17, color: style.tint),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  outcome.concept,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandNavy,
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

/// One of the three bottom actions.
class ResultAction extends StatelessWidget {
  const ResultAction({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
    this.outlined = false,
    this.busy = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(13),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                border: outlined
                    ? Border.all(color: AppColors.authFieldBorder)
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (busy)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: foreground,
                      ),
                    )
                  else
                    Icon(icon, size: 20, color: foreground),
                  const SizedBox(width: 9),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 15,
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

/// The navy footer.
class ResultFooter extends StatelessWidget {
  const ResultFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.liveBackground),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.shield_outlined,
                size: 18,
                color: AppColors.liveTextMuted,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    // Only what the app actually does: the session is written
                    // to this device and needs no connection to be read back.
                    'This session is stored on this device. No internet needed.',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.liveTextMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.auto_awesome,
                size: 15,
                color: AppColors.brandGold,
              ),
              const SizedBox(width: 6),
              Semantics(
                label: 'GyanSetu AI',
                child: const ExcludeSemantics(
                  child: Text(
                    'GyanSetu AI',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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

/// Shown when a session recorded nothing.
class EmptyConversation extends StatelessWidget {
  const EmptyConversation({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.authFieldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.forum_outlined,
            size: 28,
            color: AppColors.brandMuted,
          ),
          const SizedBox(height: 10),
          const Text(
            'No conversation data was recorded for this session.',
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: AppColors.brandNavy,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'The session can still be saved, and the lesson can be continued.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.brandNavy.withValues(alpha: 0.68),
            ),
          ),
        ],
      ),
    );
  }
}

class ResultNotice extends StatelessWidget {
  const ResultNotice({
    required this.message,
    required this.onDismiss,
    super.key,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.homeBannerTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.secondaryDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.brandNavy.withValues(alpha: 0.85),
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 17),
            color: AppColors.brandNavy.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}

/// First-paint placeholder while the session is read from the device.
class ResultSkeleton extends StatelessWidget {
  const ResultSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
        );

    return ListView(
      key: const Key('result-skeleton'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        bar(double.infinity, 96),
        const SizedBox(height: 12),
        bar(180, 22),
        bar(double.infinity, 88),
        bar(double.infinity, 88),
        bar(double.infinity, 140),
      ],
    );
  }
}

class ResultMessage extends StatelessWidget {
  const ResultMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 38, color: AppColors.brandMuted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.brandNavy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.brandNavy.withValues(alpha: 0.7),
              ),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.authNavy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _languageName(String localeId) {
  for (final TargetLanguage v in TargetLanguage.values) {
    if (v.localeId == localeId) return v.label;
  }
  for (final TeachingMedium v in TeachingMedium.values) {
    if (v.localeId == localeId) return v.label;
  }
  return localeId;
}

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dateLabel(DateTime value) =>
    '${value.day} ${_months[value.month - 1]} ${value.year}';

String _timeLabel(DateTime value) {
  final int hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
  String two(int v) => v.toString().padLeft(2, '0');
  return '$hour12:${two(value.minute)}:${two(value.second)} '
      '${value.hour < 12 ? 'AM' : 'PM'}';
}
