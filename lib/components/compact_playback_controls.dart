import 'package:finamp/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shared compact music workflow: previous, play/pause, next.
/// Uses the existing player callbacks; never creates a second playback engine.
class CompactPlaybackControls extends StatelessWidget {
  const CompactPlaybackControls({
    super.key,
    required this.isPlaying,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
    this.color,
  });

  final bool isPlaying;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePlayback;
  final VoidCallback onNext;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget control(String tooltip, IconData icon, VoidCallback action) => IconButton(
      tooltip: tooltip,
      onPressed: action,
      color: color,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: const EdgeInsets.all(10),
      style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      icon: Icon(icon, size: 24),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: [
        control(l10n.skipToPreviousTrackButtonTooltip, Icons.skip_previous_rounded, onPrevious),
        control(
          l10n.togglePlaybackButtonTooltip,
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onTogglePlayback,
        ),
        control(l10n.skipToNextTrackButtonTooltip, Icons.skip_next_rounded, onNext),
      ],
    );
  }
}
