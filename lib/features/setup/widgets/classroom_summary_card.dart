import 'package:flutter/material.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';

/// The navy card that mirrors the current selections back to the teacher.
///
/// Everything on it is derived from live form state — nothing here is a fixed
/// string, so it cannot drift from what will actually be saved.
class ClassroomSummaryCard extends StatelessWidget {
  const ClassroomSummaryCard({
    required this.summaryLine,
    required this.detailLine,
    super.key,
  });

  final String summaryLine;
  final String detailLine;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Your classroom. $summaryLine. $detailLine',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.setupSummaryNavy,
              border: Border(
                top: BorderSide(color: AppColors.brandGold, width: 3),
              ),
            ),
            child: Stack(
              children: <Widget>[
                Positioned(
                  right: -30,
                  top: -10,
                  bottom: -10,
                  child: Opacity(
                    opacity: 0.06,
                    child: Image.asset(
                      AppAssets.tribalCorner,
                      fit: BoxFit.fitHeight,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 18, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      ClipOval(
                        child: Image.asset(
                          AppAssets.setupClassroomAvatar,
                          width: 62,
                          height: 62,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Text(
                              'Your classroom',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brandGold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              summaryLine,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.3,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              detailLine,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.78),
                              ),
                            ),
                          ],
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
    );
  }
}
