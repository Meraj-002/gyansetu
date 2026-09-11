import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/photo_fade.dart';

/// Page 3's illustration: the photograph of a device held up in a rural
/// classroom, with the device's screen rebuilt as live widgets.
///
/// The photograph carries the hands, the device body and the room. Everything
/// inside the screen — the product name, the offline badge and the four
/// capability tiles — is drawn on top as real widgets. That is not only an
/// accessibility requirement; the artwork still carries the retired brand name,
/// so the baked screen has to be covered rather than shown.
class OfflineShowcase extends StatelessWidget {
  const OfflineShowcase({super.key});

  static const List<({IconData icon, String label})> capabilities =
      <({IconData icon, String label})>[
    (icon: Icons.menu_book_outlined, label: 'Multilingual\nLessons'),
    (icon: Icons.translate, label: 'Hindi ↔ Tribal\nTranslation'),
    (icon: Icons.volume_up_outlined, label: 'Native Language\nAudio'),
    (icon: Icons.description_outlined, label: 'Worksheets\n& Activities'),
  ];

  /// Where the device's screen sits inside [AppAssets.onboardingOffline],
  /// measured from the artwork and padded outwards so the overlay fully covers
  /// the baked screen at every size.
  static const Rect screenRect = Rect.fromLTRB(0.183, 0.113, 0.889, 0.935);

  @override
  Widget build(BuildContext context) {
    return Column(
      // Centred rather than bottom-aligned. The photograph is a 1.6:1 band and
      // cannot fill a tall handset's illustration area without cropping the
      // hands away, so the slack is split above and below instead of collecting
      // into one gap under the text.
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        // Flexible around the AspectRatio directly, with no Align in between:
        // an Align expands to its whole allotment, which would drive the card
        // below it down under the wave panel.
        Flexible(
          child: AspectRatio(
            // Locking the aspect ratio is what lets the fractional overlay
            // below land on the device screen at any width: the image then
            // fills its box exactly rather than being cropped.
            aspectRatio: AppAssets.onboardingOfflineAspectRatio,
            child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double w = constraints.maxWidth;
                  final double h = constraints.maxHeight;

                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      const PhotoFade(
                        top: 0.10,
                        bottom: 0.10,
                        child: Image(
                          image: AssetImage(AppAssets.onboardingOffline),
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        ),
                      ),
                      Positioned(
                        left: screenRect.left * w,
                        top: screenRect.top * h,
                        width: (screenRect.right - screenRect.left) * w,
                        height: (screenRect.bottom - screenRect.top) * h,
                        child: const _DeviceScreen(),
                      ),
                    ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _ReassuranceCard(),
      ],
    );
  }
}

/// The GyanSetu AI home screen as it appears on the device in the photograph.
class _DeviceScreen extends StatelessWidget {
  const _DeviceScreen();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The overlay is small, so everything scales off its own width rather
        // than off the screen's.
        final double scale = constraints.maxWidth / 300;
        final double gap = 7 * scale;

        return Container(
          padding: EdgeInsets.all(9 * scale),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10 * scale),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF20356B), Color(0xFF16294F)],
            ),
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Image.asset(
                    AppAssets.brandMark,
                    height: 14 * scale,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                  SizedBox(width: 5 * scale),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'GyanSetu AI',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11 * scale,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 5 * scale),
                  _OfflineBadge(scale: scale),
                ],
              ),
              SizedBox(height: gap),
              // Two Expanded rows rather than a GridView: the tiles then divide
              // whatever height the device screen actually has, so the bottom
              // pair can never be clipped off the end of a scroll extent.
              Expanded(
                child: Column(
                  children: <Widget>[
                    Expanded(child: _TileRow(from: 0, gap: gap, scale: scale)),
                    SizedBox(height: gap),
                    Expanded(child: _TileRow(from: 2, gap: gap, scale: scale)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.from, required this.gap, required this.scale});

  final int from;
  final double gap;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _CapabilityTile(
            icon: OfflineShowcase.capabilities[from].icon,
            label: OfflineShowcase.capabilities[from].label,
            scale: scale,
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: _CapabilityTile(
            icon: OfflineShowcase.capabilities[from + 1].icon,
            label: OfflineShowcase.capabilities[from + 1].label,
            scale: scale,
          ),
        ),
      ],
    );
  }
}

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 8 * scale,
        vertical: 4 * scale,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandOfflineGreen,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.wifi_off, size: 10 * scale, color: Colors.white),
          SizedBox(width: 4 * scale),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Offline Mode',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 9.5 * scale,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({
    required this.icon,
    required this.label,
    required this.scale,
  });

  final IconData icon;
  final String label;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 3 * scale, vertical: 4 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FC),
        borderRadius: BorderRadius.circular(8 * scale),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16 * scale, color: AppColors.brandNavy),
          SizedBox(height: 3 * scale),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9 * scale,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandNavy,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReassuranceCard extends StatelessWidget {
  const _ReassuranceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.brandCream.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.brandNavy.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.verified_user_outlined,
            size: 19,
            color: AppColors.brandNavy,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Reliable learning, even in remote areas.',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.brandNavy.withValues(alpha: 0.92),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
