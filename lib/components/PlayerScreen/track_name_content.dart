import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/jellyfin_models.dart' as jellyfin_models;
import '../../screens/artist_screen.dart';
import '../../screens/player_screen.dart';
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

    final artistName = trackBaseItemDto.artists?.firstOrNull ??
        trackBaseItemDto.albumArtist ??
        currentTrack.item.artist ??
        '';

    final artistItem = (trackBaseItemDto.artistItems ?? trackBaseItemDto.albumArtists)?.firstOrNull;
    final artistTarget = artistItem != null
        ? jellyfin_models.BaseItemDto(id: artistItem.id, name: artistItem.name, type: "MusicArtist")
        : (artistName.isNotEmpty
            ? jellyfin_models.BaseItemDto(id: trackBaseItemDto.id, name: artistName, type: "MusicArtist")
            : null);

    final title = currentTrack.item.title;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Apple Music Left-Aligned Title and Artist Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Track Title
                Semantics(
                  label: "$title (${AppLocalizations.of(context)!.title})",
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 3),
                // Artist Name
                GestureDetector(
                  onTap: () {
                    if (artistTarget != null) {
                      Navigator.of(context).pushNamed(
                        ArtistScreen.routeName,
                        arguments: artistTarget,
                      );
                    }
                  },
                  child: Text(
                    artistName.isNotEmpty ? artistName : AppLocalizations.of(context)!.unknownArtist,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Right: Favorite Heart & Three Dots Menu
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FavoriteButton(
                item: trackBaseItemDto,
                color: isFav ? appleAccentColor : Colors.white.withValues(alpha: 0.65),
                size: 26,
              ),
              const SizedBox(width: 4),
              PlayerButtonsMore(item: trackBaseItemDto, queueItem: currentTrack),
            ],
          ),
        ],
      ),
    );
  }
}
