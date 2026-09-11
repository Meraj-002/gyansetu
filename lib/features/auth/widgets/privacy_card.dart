import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

/// The reassurance card below the login card.
///
/// Interactive: tapping it opens the detail sheet, so the claim on the card is
/// backed by an explanation rather than left as a slogan.
class PrivacyCard extends StatelessWidget {
  const PrivacyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Your classroom data is protected. '
          'Open data privacy and security details.',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => showPrivacyDetails(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.authIconCircle,
                    ),
                    child: const Icon(
                      Icons.verified_user,
                      size: 24,
                      color: AppColors.authNavy,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text(
                          'Your classroom data is protected.',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandNavy,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'We follow strict data privacy and security '
                          'standards.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color:
                                AppColors.brandNavy.withValues(alpha: 0.66),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right,
                    color: AppColors.brandNavy.withValues(alpha: 0.55),
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

/// Explains, in plain terms, what the app actually does with credentials.
///
/// Every line here describes behaviour that is implemented. Nothing claims a
/// certification, audit or legal standard the project does not hold.
Future<void> showPrivacyDetails(BuildContext context) {
  const List<({IconData icon, String title, String body})> points =
      <({IconData icon, String title, String body})>[
    (
      icon: Icons.password,
      title: 'Your PIN is never stored',
      body: 'Only a scrambled verifier derived from it is kept, and it cannot '
          'be turned back into your PIN.',
    ),
    (
      icon: Icons.lock_outline,
      title: 'Credentials live in secure storage',
      body: 'Sign-in material is held in the device keystore, not in ordinary '
          'app settings or the lesson database.',
    ),
    (
      icon: Icons.wifi_off,
      title: 'Your classroom work stays on the device',
      body: 'Lessons, worksheets and progress are saved locally so they keep '
          'working without a connection.',
    ),
    (
      icon: Icons.cloud_sync_outlined,
      title: 'The server is used only when needed',
      body: 'First-time setup and PIN recovery need the internet. Everyday '
          'teaching does not.',
    ),
    (
      icon: Icons.logout,
      title: 'You can remove this device',
      body: 'Signing out clears the stored session and the offline sign-in '
          'material from this device.',
    ),
  ];

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (BuildContext context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: SingleChildScrollView(
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
                  'How your data is protected',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
                const SizedBox(height: 18),
                for (final ({IconData icon, String title, String body}) p
                    in points)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(p.icon, size: 20, color: AppColors.authNavy),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                p.title,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brandNavy,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.body,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: AppColors.brandNavy
                                      .withValues(alpha: 0.70),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.authNavy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
