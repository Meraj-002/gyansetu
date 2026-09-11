import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/lesson.dart';
import '../../setup/models/classroom_setup.dart';
import '../models/home_dashboard.dart';
import '../services/home_controller.dart';

/// Logo lock-up, notification bell and profile avatar.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    required this.unreadCount,
    required this.onNotifications,
    required this.onProfile,
    super.key,
  });

  final int unreadCount;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Image.asset(
          AppAssets.loginBrandMark,
          height: 40,
          filterQuality: FilterQuality.medium,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            label: 'GyanSetu AI',
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: const <InlineSpan>[
                          TextSpan(
                            text: 'GyanSetu',
                            style: TextStyle(color: AppColors.brandNavy),
                          ),
                          TextSpan(text: ' '),
                          TextSpan(
                            text: 'AI',
                            style: TextStyle(color: AppColors.brandOrange),
                          ),
                        ],
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Bridging Languages. Building Futures.',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandNavy.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _BellButton(unreadCount: unreadCount, onTap: onNotifications),
        const SizedBox(width: 6),
        Semantics(
          button: true,
          label: 'Profile',
          child: ExcludeSemantics(
            child: InkWell(
              onTap: onProfile,
              customBorder: const CircleBorder(),
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandCreamWarm,
                ),
                child: const Icon(
                  Icons.person,
                  size: 24,
                  color: AppColors.brandOrange,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.unreadCount, required this.onTap});

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: unreadCount > 0
          ? 'Notifications, $unreadCount unread'
          : 'Notifications',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                const Icon(
                  Icons.notifications_none_rounded,
                  size: 26,
                  color: AppColors.brandNavy,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 17),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
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

/// The strip showing the current classroom and what it can do offline.
class ClassroomStatusCard extends StatelessWidget {
  const ClassroomStatusCard({
    required this.classroom,
    required this.offlineState,
    super.key,
  });

  final ClassroomSetup classroom;
  final HomeOfflineState offlineState;

  Color get _tint => switch (offlineState) {
        HomeOfflineState.offlineReady => AppColors.success,
        HomeOfflineState.onlineSyncAvailable => AppColors.info,
        HomeOfflineState.partial => AppColors.warning,
        HomeOfflineState.missing => AppColors.warning,
        HomeOfflineState.error => AppColors.error,
        HomeOfflineState.unknown => AppColors.brandMuted,
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Class ${classroom.classLevel}, '
          '${classroom.targetLanguage.label}. ${offlineState.shortLabel}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.authFieldBorder),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.groups_outlined,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Class ${classroom.classLevel}  •  '
                    '${classroom.targetLanguage.label}',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandNavy,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              const SizedBox(width: 8),
              // A dot plus a word: the state never rests on colour alone.
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _tint),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    offlineState.shortLabel,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _tint,
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

/// The navy hero carrying today's lesson and its two actions.
class TodayLessonCard extends StatelessWidget {
  const TodayLessonCard({
    required this.lesson,
    required this.targetLanguage,
    required this.listenState,
    required this.onStart,
    required this.onListen,
    required this.onChooseLesson,
    super.key,
  });

  /// Null shows the empty state rather than a fabricated lesson.
  final Lesson? lesson;

  final TargetLanguage targetLanguage;
  final ListenState listenState;
  final VoidCallback onStart;
  final VoidCallback onListen;
  final VoidCallback onChooseLesson;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: AppColors.homeHeroNavy,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(child: _ShapesIllustration()),
            lesson == null ? _empty(context) : _content(context),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _HeroEyebrow(),
          const SizedBox(height: 14),
          const Text(
            'No lesson planned for today',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pick one from the lesson library to get started.',
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 18),
          _GoldButton(
            icon: Icons.auto_stories_outlined,
            label: 'Choose a lesson',
            onPressed: onChooseLesson,
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The artwork only earns its place when there is room beside the text.
        final bool showArtwork = constraints.maxWidth >= 380;

        final Widget text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _HeroEyebrow(),
            const SizedBox(height: 14),
            Text(
              lesson!.title,
              style: const TextStyle(
                fontSize: 25,
                height: 1.15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Learning outcome',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.brandGold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              lesson!.learningOutcome,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _GoldButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Start Lesson',
                  onPressed: onStart,
                ),
                _ListenButton(
                  language: targetLanguage,
                  state: listenState,
                  onPressed: onListen,
                ),
              ],
            ),
          ],
        );

        if (!showArtwork) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            child: text,
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 8, 22),
                child: text,
              ),
            ),
            Expanded(
              flex: 4,
              child: Image.asset(
                AppAssets.homeLessonTablet,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HeroEyebrow extends StatelessWidget {
  const _HeroEyebrow();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          "TODAY'S LESSON",
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: AppColors.brandGold,
          ),
        ),
        const SizedBox(height: 6),
        Container(width: 34, height: 2.5, color: AppColors.brandGold),
      ],
    );
  }
}

class _GoldButton extends StatelessWidget {
  const _GoldButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 21),
      label: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.setupCta,
        foregroundColor: AppColors.brandNavy,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _ListenButton extends StatelessWidget {
  const _ListenButton({
    required this.language,
    required this.state,
    required this.onPressed,
  });

  final TargetLanguage language;
  final ListenState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, String label}) c = switch (state) {
      ListenState.idle => (
          icon: Icons.volume_up_outlined,
          label: 'Listen in ${language.label}',
        ),
      ListenState.loading => (icon: Icons.hourglass_empty, label: 'Preparing…'),
      ListenState.playing => (icon: Icons.stop_circle_outlined, label: 'Stop'),
      ListenState.unavailable => (
          icon: Icons.volume_off_outlined,
          label: 'No audio yet',
        ),
    };

    return OutlinedButton.icon(
      onPressed: state == ListenState.loading ? null : onPressed,
      icon: state == ListenState.loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Icon(c.icon, size: 20),
      label: Text(
        c.label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Subtle educational shapes (circle, square, triangle, rectangle) drawn as a
/// decorative background layer on the navy hero card.
class _ShapesIllustration extends StatelessWidget {
  const _ShapesIllustration();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _ShapesPainter(),
      size: Size.infinite,
    );
  }
}

class _ShapesPainter extends CustomPainter {
  const _ShapesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    // Circle — top-right
    final double circleRadius = size.width * 0.12;
    paint.color = Colors.white.withValues(alpha: 0.10);
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.18),
      circleRadius,
      paint,
    );

    // Square — bottom-left
    final double squareSide = size.width * 0.11;
    final double squareLeft = size.width * 0.07;
    final double squareTop = size.height * 0.62;
    paint.color = Colors.white.withValues(alpha: 0.08);
    final RRect square = RRect.fromRectAndRadius(
      Rect.fromLTWH(squareLeft, squareTop, squareSide, squareSide),
      const Radius.circular(4),
    );
    canvas.drawRRect(square, paint);

    // Triangle — top-left
    paint.color = Colors.white.withValues(alpha: 0.09);
    final double triSize = size.width * 0.10;
    final double triCx = size.width * 0.22;
    final double triCy = size.height * 0.14;
    final Path triangle = Path()
      ..moveTo(triCx, triCy - triSize)
      ..lineTo(triCx + triSize * 0.87, triCy + triSize * 0.5)
      ..lineTo(triCx - triSize * 0.87, triCy + triSize * 0.5)
      ..close();
    canvas.drawPath(triangle, paint);

    // Rectangle — bottom-right
    paint.color = Colors.white.withValues(alpha: 0.07);
    final double rectW = size.width * 0.18;
    final double rectH = size.width * 0.10;
    final RRect rectangle = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.68,
        size.height * 0.72,
        rectW,
        rectH,
      ),
      const Radius.circular(5),
    );
    canvas.drawRRect(rectangle, paint);
  }

  @override
  bool shouldRepaint(covariant _ShapesPainter oldDelegate) => false;
}
