import 'dart:io';

import 'package:flutter/material.dart';

/// Wide-screen navigation for macOS and iPad landscape.
///
/// Shares the same four destinations and selection state as the compact
/// floating bottom bar; switching layouts does not reset any tab or player.
class AppleSidebarNavigation extends StatelessWidget {
  const AppleSidebarNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onSettingsTap,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onSettingsTap;

  static const _accent = Color(0xFFFA2D48);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF17171A);
    final muted = isDark ? Colors.white54 : Colors.black45;
    final topPadding = Platform.isMacOS
        ? 36.0
        : (MediaQuery.paddingOf(context).top > 0 ? MediaQuery.paddingOf(context).top + 6 : 22.0);

    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161618) : const Color(0xFFF5F5F7),
        border: Border(right: BorderSide(color: isDark ? Colors.white12 : Colors.black12, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(14, topPadding, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 0, 22),
            child: Text(
              'Music',
              style: TextStyle(color: foreground, fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -0.7),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 0, 10),
            child: Text(
              'EXPLORE',
              style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2),
            ),
          ),
          _SidebarDestination(
            label: 'Home',
            icon: Icons.home_rounded,
            selected: selectedIndex == 0,
            accent: _accent,
            foreground: foreground,
            onTap: () => onDestinationSelected(0),
          ),
          _SidebarDestination(
            label: 'Library',
            icon: Icons.library_music_rounded,
            selected: selectedIndex == 1,
            accent: _accent,
            foreground: foreground,
            onTap: () => onDestinationSelected(1),
          ),
          _SidebarDestination(
            label: 'Books',
            icon: Icons.auto_stories_rounded,
            selected: selectedIndex == 2,
            accent: _accent,
            foreground: foreground,
            onTap: () => onDestinationSelected(2),
          ),
          _SidebarDestination(
            label: 'Search',
            icon: Icons.search_rounded,
            selected: selectedIndex == 3,
            accent: _accent,
            foreground: foreground,
            onTap: () => onDestinationSelected(3),
          ),
          const Spacer(),
          SafeArea(
            top: false,
            child: _SidebarDestination(
              label: 'Settings',
              icon: Icons.settings_outlined,
              selected: false,
              accent: _accent,
              foreground: foreground,
              onTap: onSettingsTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarDestination extends StatelessWidget {
  const _SidebarDestination({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = selected ? accent : foreground;

    return Semantics(
      button: true,
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: selected ? accent.withValues(alpha: isDark ? 0.18 : 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            mouseCursor: SystemMouseCursors.click,
            hoverColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 13),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: -0.2,
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
