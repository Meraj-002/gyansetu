import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/photo_fade.dart';

/// Page 2's illustration: the teacher on the left, and the speech-to-translation
/// flow rebuilt as live widgets on the right.
///
/// Only the photography is an asset. The bubble, the waveform and the language
/// chips are real widgets, so their text is reachable by screen readers and
/// scales with the layout instead of being baked into a picture.
class TranslationShowcase extends StatelessWidget {
  const TranslationShowcase({super.key});

  static const List<String> languages = <String>['Santali', 'Mundari', 'Ho'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        final double scale = (w / 360).clamp(0.80, 1.20);

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: h * 0.26,
                width: double.infinity,
                child: const PhotoFade(
                  top: 0.45,
                  child: Image(
                    image: AssetImage(AppAssets.onboardingClassBlur),
                    fit: BoxFit.cover,
                    alignment: Alignment.bottomCenter,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              // Feathered on the right and top: the crop is a straight cut out
              // of the reference sheet, and unmasked it leaves a hard vertical
              // seam down the middle of the page.
              child: SizedBox(
                height: h * 0.86,
                child: const PhotoFade(
                  right: 0.22,
                  top: 0.10,
                  child: Image(
                    image: AssetImage(AppAssets.onboardingTeacher),
                    fit: BoxFit.fitHeight,
                    alignment: Alignment.bottomLeft,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
            Positioned(
              left: w * 0.25,
              right: w * 0.03,
              top: h * 0.02,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _SpeechBubble(scale: scale),
                  SizedBox(height: 5 * scale),
                  Icon(
                    Icons.south,
                    size: 25 * scale,
                    color: AppColors.brandOrangeBright,
                  ),
                  SizedBox(height: 5 * scale),
                  _WaveformCard(scale: scale),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 11 * scale,
        vertical: 10 * scale,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17 * scale),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.brandNavy.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 32 * scale,
            height: 32 * scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandNavy.withValues(alpha: 0.10),
            ),
            child: Icon(
              Icons.mic,
              size: 18 * scale,
              color: AppColors.brandNavy,
            ),
          ),
          SizedBox(width: 9 * scale),
          Flexible(
            child: Text(
              'बच्चों, आज हम\nपक्षियों के बारे में सीखेंगे।',
              style: TextStyle(
                fontSize: 12.5 * scale,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: AppColors.brandNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformCard extends StatelessWidget {
  const _WaveformCard({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(11 * scale),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17 * scale),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.brandNavy.withValues(alpha: 0.94),
            AppColors.brandNavyDeep.withValues(alpha: 0.92),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.brandNavyDeep.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: 40 * scale,
            width: double.infinity,
            child: const CustomPaint(painter: _WaveformPainter()),
          ),
          SizedBox(height: 11 * scale),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6 * scale,
            runSpacing: 6 * scale,
            children: <Widget>[
              for (final String language in TranslationShowcase.languages)
                _LanguageChip(label: language, scale: scale),
            ],
          ),
        ],
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({required this.label, required this.scale});

  final String label;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 12 * scale,
        vertical: 6 * scale,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
        color: Colors.white.withValues(alpha: 0.10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12 * scale,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Static voice trace.
///
/// Deliberately not animated: the page should read as a calm product screen,
/// and a looping animation would also make widget goldens non-deterministic.
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter();

  /// Envelope sampled by eye from the key art: quiet at the edges, loudest just
  /// past the middle where the translated half begins.
  static const List<double> _amplitudes = <double>[
    0.12, 0.20, 0.14, 0.30, 0.22, 0.42, 0.34, 0.56, 0.46, 0.70,
    0.58, 0.84, 0.72, 0.96, 0.80, 1.00, 0.86, 0.94, 0.74, 0.88,
    0.62, 0.78, 0.52, 0.66, 0.44, 0.56, 0.36, 0.46, 0.28, 0.38,
    0.22, 0.30, 0.18, 0.24, 0.14, 0.19, 0.11, 0.15,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final int count = _amplitudes.length;
    final double gap = size.width / count;
    final double barWidth = gap * 0.45;
    final double mid = size.height / 2;

    for (int i = 0; i < count; i++) {
      final double t = i / (count - 1);
      // Warm where the teacher speaks, cooling towards the translated output.
      final Color colour = Color.lerp(
        AppColors.brandOrangeBright,
        Colors.white,
        (t * 1.15).clamp(0.0, 1.0),
      )!;
      final double half = (_amplitudes[i] * size.height * 0.46).clamp(1.5, mid);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            i * gap + (gap - barWidth) / 2,
            mid - half,
            i * gap + (gap + barWidth) / 2,
            mid + half,
          ),
          Radius.circular(barWidth),
        ),
        Paint()..color = colour,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => false;
}
