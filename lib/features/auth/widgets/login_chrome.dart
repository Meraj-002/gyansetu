import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/connectivity/connectivity_service.dart';

/// Cream ground plus the tribal motifs that frame the login screen.
class LoginBackdrop extends StatelessWidget {
  const LoginBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                AppColors.authPageTop,
                AppColors.authPageTop,
                AppColors.authPageBottom,
              ],
              stops: <double>[0.0, 0.55, 1.0],
            ),
          ),
        ),
        const _TribalCorner(alignment: Alignment.topLeft),
        const _TribalCorner(alignment: Alignment.topRight, flipX: true),
        const _TribalCorner(
          alignment: Alignment.bottomLeft,
          flipY: true,
          fraction: 0.16,
        ),
        const _TribalCorner(
          alignment: Alignment.bottomRight,
          flipX: true,
          flipY: true,
          fraction: 0.16,
        ),
      ],
    );
  }
}

class _TribalCorner extends StatelessWidget {
  const _TribalCorner({
    required this.alignment,
    this.flipX = false,
    this.flipY = false,
    this.fraction = 0.30,
  });

  final Alignment alignment;
  final bool flipX;
  final bool flipY;

  /// Height of the motif as a share of the screen.
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);

    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Transform.scale(
          scaleX: flipX ? -1 : 1,
          scaleY: flipY ? -1 : 1,
          child: Opacity(
            opacity: 0.55,
            child: Image.asset(
              AppAssets.tribalCorner,
              height: screen.height * fraction,
              fit: BoxFit.contain,
              alignment: Alignment.topLeft,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bridge mark, wordmark and strapline.
class LoginMasthead extends StatelessWidget {
  const LoginMasthead({this.scale = 1, super.key});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'GyanSetu AI',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Image.asset(
              AppAssets.loginBrandMark,
              height: 76 * scale,
              filterQuality: FilterQuality.medium,
            ),
            SizedBox(height: 8 * scale),
            Text.rich(
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
                  fontSize: 34 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.05,
                ),
              ),
            ),
            SizedBox(height: 6 * scale),
            Text(
              'AI-powered  •  Offline-first  •  Mother Tongue Education',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5 * scale,
                fontWeight: FontWeight.w600,
                color: AppColors.brandNavy.withValues(alpha: 0.80),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The status card in the top-right corner.
///
/// It reports what is actually true. It only promises offline access when this
/// device has really been provisioned, and it says nothing at all until the
/// local state has been read.
class ConnectivityChip extends StatelessWidget {
  const ConnectivityChip({
    required this.status,
    required this.hasOfflineAccount,
    required this.ready,
    super.key,
  });

  final ConnectionStatus status;
  final bool hasOfflineAccount;
  final bool ready;

  ({IconData icon, String title, String detail, Color tint}) get _content {
    if (!ready) {
      return (
        icon: Icons.sync,
        title: 'Checking',
        detail: 'connection status',
        tint: AppColors.brandMuted,
      );
    }
    return switch (status) {
      ConnectionStatus.online => (
          icon: Icons.cloud_done_outlined,
          title: 'Online',
          detail: 'connected to the network',
          tint: AppColors.success,
        ),
      ConnectionStatus.offline when hasOfflineAccount => (
          icon: Icons.cloud_off,
          title: 'Offline',
          detail: 'access available\non this device',
          tint: AppColors.brandNavy,
        ),
      ConnectionStatus.offline => (
          icon: Icons.cloud_off,
          title: 'Offline',
          detail: 'login unavailable\nuntil first setup',
          tint: AppColors.warning,
        ),
      ConnectionStatus.unknown => (
          icon: Icons.cloud_queue,
          title: 'Offline',
          detail: 'access available\nafter first setup',
          tint: AppColors.brandMuted,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, String title, String detail, Color tint}) c =
        _content;

    return Semantics(
      liveRegion: true,
      label: '${c.title}. ${c.detail.replaceAll('\n', ' ')}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.authChip,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(c.icon, size: 17, color: c.tint),
                  const SizedBox(width: 7),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        c.title,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandNavy,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                c.detail,
                softWrap: true,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  color: AppColors.brandNavy.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The short saffron rule under the welcome subtitle.
class BrandRule extends StatelessWidget {
  const BrandRule({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 3.5,
      decoration: BoxDecoration(
        color: AppColors.brandOrange,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// Footer strapline.
///
/// The reference places the State Emblem of India here. It is deliberately not
/// reproduced: the emblem is restricted under the State Emblem of India
/// (Prohibition of Improper Use) Act, 2005, and showing it would imply an
/// official endorsement this product does not have. A neutral tricolour rule
/// carries the same intent without the claim.
class LoginFooter extends StatelessWidget {
  const LoginFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: 54,
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: const LinearGradient(
              colors: <Color>[
                Color(0xFFFF9933),
                Color(0xFFF4F4F4),
                Color(0xFF138808),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Designed for low-connectivity schools',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.brandNavy.withValues(alpha: 0.88),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Built for Bharat. By Bharat.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.brandNavy.withValues(alpha: 0.62),
          ),
        ),
      ],
    );
  }
}
