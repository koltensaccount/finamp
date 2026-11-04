import 'package:flutter/material.dart';

/// Keeps the mini-player's contents together while its route anchor moves.
class MiniPlayerAnchor extends StatelessWidget {
  const MiniPlayerAnchor({super.key, required this.child, this.includeBottomSafeArea = true});

  final Widget child;
  final bool includeBottomSafeArea;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: includeBottomSafeArea,
      // Keep route-specific insets outside the flying rectangle. Both bars
      // therefore have the same artwork/text geometry in the overlay.
      child: Hero(
        tag: 'nowplaying',
        transitionOnUserGestures: true,
        createRectTween: (from, to) => RectTween(begin: from, end: to),
        flightShuttleBuilder: (context, animation, direction, from, to) {
          // Freeze the source subtree for the flight rather than swapping its
          // theme, text layout, or artwork as the destination comes on screen.
          final source = from;
          return MediaQuery(data: MediaQuery.of(source), child: (source.widget as Hero).child);
        },
        child: child,
      ),
    );
  }
}

/// A reversible sheet motion: dismissal follows the same path as presentation.
class PlayerSheetTransition extends StatelessWidget {
  const PlayerSheetTransition({super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;

    return SlideTransition(
      position: animation.drive(
        Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeInOutCubic)),
      ),
      child: child,
    );
  }
}
