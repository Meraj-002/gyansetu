import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../constants/app_colors.dart';

/// The five primary destinations.
///
/// Declared once here rather than inside a screen, so this bar can become the
/// application shell without the list being copied.
enum AppDestination {
  home(label: 'Home', icon: Icons.home_rounded, route: AppRoutes.home),
  lessons(
    label: 'Lessons',
    icon: Icons.menu_book_outlined,
    route: AppRoutes.lessons,
  ),
  offline(label: 'Offline', icon: Icons.download_rounded, route: AppRoutes.offline),
  flashcards(
    label: 'Flashcards',
    icon: Icons.style_outlined,
    route: AppRoutes.flashcards,
  ),
  profile(label: 'Profile', icon: Icons.person_outline, route: AppRoutes.profile);

  const AppDestination({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;
}

/// Deep navy navigation bar with a warm-gold selected state.
///
/// Only the selected item is gold — a soft translucent gold pill behind a gold
/// icon and label — while the rest stay light on navy. Selection is carried by
/// the pill and the filled icon as well as the colour, so it does not depend on
/// hue alone.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    required this.current,
    this.onSelected,
    super.key,
  });

  final AppDestination current;

  /// Defaults to routing through [AppRouter]; overridable for tests and for a
  /// future shell that swaps the body instead of pushing a route.
  final void Function(AppDestination destination)? onSelected;

  void _select(BuildContext context, AppDestination destination) {
    final void Function(AppDestination)? handler = onSelected;
    if (handler != null) {
      handler(destination);
      return;
    }
    // Tapping the current destination is a no-op rather than a reload.
    if (destination == current) return;
    AppRouter.replaceWithFade(context, destination.route);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.navShellNavy),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: <Widget>[
              for (final AppDestination destination in AppDestination.values)
                Expanded(
                  child: _NavItem(
                    destination: destination,
                    selected: destination == current,
                    onTap: () => _select(context, destination),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground =
        selected ? AppColors.navShellActive : Colors.white.withValues(alpha: 0.86);

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected
                  ? AppColors.navShellActive.withValues(alpha: 0.16)
                  : Colors.transparent,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(destination.icon, size: 23, color: foreground),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                      color: foreground,
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
