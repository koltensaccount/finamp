import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/jellyfin_models.dart' as jellyfin_models;
import '../../screens/player_screen.dart';
import '../../services/artist_resolution_helper.dart';
import '../../services/favorite_provider.dart';
import '../../services/queue_service.dart';
import '../favorite_button.dart';
import 'player_buttons_more.dart';

class TrackNameContent extends ConsumerWidget {
  const TrackNameContent(this.controller, {super.key});

  final PlayerHideableController controller;
  static const Color appleAccentColor = Color(0xFFFA2D48);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(QueueService.queueProvider);

    if (queue?.currentTrack == null) {
      return const CircularProgressIndicator();
    }
    final currentTrack = queue!.currentTrack!;
    final jellyfin_models.BaseItemDto trackBaseItemDto = currentTrack.baseItem;

    final isFav = ref.watch(isFavoriteProvider(trackBaseItemDto));

    final artistName =
        trackBaseItemDto.artists?.firstOrNull ?? trackBaseItemDto.albumArtist ?? currentTrack.item.artist ?? '';

    final artistTarget = ArtistResolutionHelper.resolveArtistNavigationTarget(
      track: trackBaseItemDto,
      fallbackArtistName: artistName,
    );

    final title = currentTrack.item.title;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: title,
            child: Semantics(
              label: "$title (${AppLocalizations.of(context)!.title})",
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: Colors.white,
                ),
                maxLines: 3,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ArtistResolutionHelper.navigateToArtist(
                  context,
                  artistItem: artistTarget,
                  artistName: artistName.isNotEmpty ? artistName : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    artistName.isNotEmpty ? artistName : AppLocalizations.of(context)!.unknownArtist,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.72)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FavoriteButton(
              item: trackBaseItemDto,
              color: isFav ? appleAccentColor : Colors.white.withValues(alpha: 0.65),
              size: 24,
            ),
            PlayerButtonsMore(item: trackBaseItemDto, queueItem: currentTrack),
          ]),
        ],
      ),
    );
  }
}
