import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

import '../components/MusicScreen/item_wrapper.dart';
import '../components/now_playing_bar.dart';
import '../components/print_duration.dart';
import '../models/finamp_models.dart';
import '../models/jellyfin_models.dart';
import '../services/album_screen_provider.dart';
import '../services/favorite_provider.dart';
import '../services/jellyfin_api_helper.dart';
import '../services/queue_service.dart';
import 'artist_screen.dart';

class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key, this.parent, this.genreFilter});

  static const routeName = "/music/album";
  static const Color appleAccentColor = Color(0xFFFA2D48);

  final BaseItemDto? parent;
  final BaseItemDto? genreFilter;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final BaseItemDto resolvedParent = widget.parent ?? ModalRoute.settingsOf(context)!.arguments as BaseItemDto;

    final jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
    final queueService = GetIt.instance<QueueService>();

    final tracksAsync = ref.watch(getAlbumOrPlaylistTracksProvider(resolvedParent));
    final (allTracks, playableTracks) = tracksAsync.valueOrNull ?? (null, null);
    final tracks = playableTracks ?? allTracks ?? [];

    final isFavorite = ref.watch(isFavoriteProvider(resolvedParent));

    final albumArtUrl = jellyfinApiHelper.getImageUrl(item: resolvedParent)?.toString();
    final artistName = resolvedParent.albumArtist ??
        ((resolvedParent.artists?.isNotEmpty ?? false) ? resolvedParent.artists!.first : 'Unknown Artist');
    final year = resolvedParent.productionYear != null ? '${resolvedParent.productionYear}' : '';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: CircleAvatar(
              radius: 18,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.chevron_left, color: isDark ? Colors.white : Colors.black87, size: 26),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFavorite ? AlbumScreen.appleAccentColor : (isDark ? Colors.white : Colors.black87),
                  size: 20,
                ),
                onPressed: () {
                  ref.read(isFavoriteProvider(resolvedParent).notifier).updateFavorite(!isFavorite);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.more_horiz, color: isDark ? Colors.white : Colors.black87, size: 20),
                onPressed: () => openItemMenu(context: context, item: resolvedParent),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const NowPlayingBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          // Apple Music Hero Album Artwork
          Center(
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: albumArtUrl != null
                    ? Image.network(
                        albumArtUrl,
                        width: 210,
                        height: 210,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                          child: const Icon(Icons.album_rounded, size: 80, color: Colors.grey),
                        ),
                      )
                    : Container(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        child: const Icon(Icons.album_rounded, size: 80, color: Colors.grey),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Album Title
          Text(
            resolvedParent.name ?? 'Album',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          // Artist Name (Tappable with Apple Red accent)
          GestureDetector(
            onTap: () {
              if (resolvedParent.artistItems?.isNotEmpty ?? false) {
                final artistItem = resolvedParent.artistItems!.first;
                final artistStub = BaseItemDto(
                  id: artistItem.id,
                  name: artistItem.name,
                  type: 'MusicArtist',
                );
                Navigator.of(context).pushNamed(ArtistScreen.routeName, arguments: artistStub);
              }
            },
            child: Text(
              artistName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AlbumScreen.appleAccentColor,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Metadata: Album • Year • Lossless
          Text(
            [
              'Album',
              if (year.isNotEmpty) year,
              'Lossless',
            ].join(' • '),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          // Dual Apple Music Play & Shuffle Capsule Buttons
          Row(
            children: [
              Expanded(
                child: _buildAppleActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play',
                  isDark: isDark,
                  onTap: () async {
                    if (tracks.isNotEmpty) {
                      await queueService.startPlayback(
                        items: tracks,
                        source: QueueItemSource.fromBaseItem(resolvedParent),
                        order: FinampPlaybackOrder.linear,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAppleActionButton(
                  icon: TablerIcons.arrows_shuffle,
                  label: 'Shuffle',
                  isDark: isDark,
                  onTap: () async {
                    if (tracks.isNotEmpty) {
                      await queueService.startPlayback(
                        items: tracks,
                        source: QueueItemSource.fromBaseItem(resolvedParent),
                        order: FinampPlaybackOrder.shuffled,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Track List
          ...tracks.asMap().entries.map((entry) {
            final index = entry.key;
            final track = entry.value;
            final position = track.indexNumber ?? (index + 1);
            final durationText = printDuration(track.runTimeTicksDuration(), leadingZeroes: false);
            final trackArtist = (track.artists?.isNotEmpty ?? false) ? track.artists!.join(', ') : '';

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  leading: SizedBox(
                    width: 28,
                    child: Text(
                      '$position',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ),
                  title: Text(
                    track.name ?? 'Track',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: -0.2),
                  ),
                  subtitle: (track.artists?.isNotEmpty ?? false) && trackArtist != artistName
                      ? Text(
                          trackArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73),
                          ),
                        )
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (durationText.isNotEmpty)
                        Text(
                          durationText,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      const SizedBox(width: 6),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.more_horiz, size: 20, color: Colors.grey),
                        onPressed: () => openItemMenu(context: context, item: track),
                      ),
                    ],
                  ),
                  onTap: () async {
                    await queueService.startPlayback(
                      items: tracks,
                      startingIndex: index,
                      source: QueueItemSource.fromBaseItem(resolvedParent),
                      order: FinampPlaybackOrder.linear,
                    );
                  },
                ),
                Divider(
                  height: 1,
                  indent: 48,
                  color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAppleActionButton({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AlbumScreen.appleAccentColor, size: 24),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AlbumScreen.appleAccentColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
