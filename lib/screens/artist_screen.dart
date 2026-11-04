import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

import '../components/MusicScreen/item_wrapper.dart';
import '../components/now_playing_bar.dart';
import '../components/print_duration.dart';
import '../models/finamp_models.dart';
import '../models/jellyfin_models.dart';
import '../services/artist_content_provider.dart';
import '../services/artist_image_service.dart';
import '../services/favorite_provider.dart';
import '../services/finamp_user_helper.dart';
import '../services/jellyfin_api_helper.dart';
import '../services/queue_service.dart';
import 'album_screen.dart';

class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen({super.key, this.widgetArtist, this.genreFilter});

  static const routeName = "/music/artist";
  static const Color appleAccentColor = Color(0xFFFA2D48);

  final BaseItemDto? widgetArtist;
  final BaseItemDto? genreFilter;

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final BaseItemDto artist = widget.widgetArtist ?? ModalRoute.settingsOf(context)!.arguments as BaseItemDto;

    final finampUserHelper = GetIt.instance<FinampUserHelper>();
    final library = finampUserHelper.currentUser?.currentView;
    final jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
    final queueService = GetIt.instance<QueueService>();

    final tracksAsync = ref.watch(getArtistTracksSectionProvider(artist: artist, libraryFilter: library));
    final (tracks, _, _) = tracksAsync.valueOrNull ?? (null, null, null);

    final albumsAsync = ref.watch(getArtistAlbumsProvider(artist: artist, libraryFilter: library?.id));
    final albums = albumsAsync.valueOrNull ?? [];

    final isFavorite = ref.watch(isFavoriteProvider(artist));

    final knownArtistPhoto = ArtistImageService.getKnownArtistImageUrl(artist.name ?? '');
    final jellyfinPhoto = jellyfinApiHelper.getImageUrl(item: artist)?.toString();
    final artistPhotoUrl = knownArtistPhoto ?? jellyfinPhoto;

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
                  color: isFavorite ? ArtistScreen.appleAccentColor : (isDark ? Colors.white : Colors.black87),
                  size: 20,
                ),
                onPressed: () {
                  ref.read(isFavoriteProvider(artist).notifier).updateFavorite(!isFavorite);
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
                onPressed: () => openItemMenu(context: context, item: artist),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const NowPlayingBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          // Apple Music Hero Artist Section
          Center(
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipOval(
                child: artistPhotoUrl != null && artistPhotoUrl.isNotEmpty
                    ? Image.network(
                        artistPhotoUrl,
                        width: 150,
                        height: 150,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                          child: const Icon(Icons.person, size: 70, color: Colors.grey),
                        ),
                      )
                    : Container(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        child: const Icon(Icons.person, size: 70, color: Colors.grey),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Artist Name
          Text(
            artist.name ?? 'Artist',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          // Metadata: Albums & Songs
          Text(
            [
              if (albums.isNotEmpty) '${albums.length} ${albums.length == 1 ? 'Album' : 'Albums'}',
              if (tracks != null && tracks.isNotEmpty) '${tracks.length} Songs',
            ].join(' • '),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          // Dual Apple Music Play & Shuffle Capsule Buttons
          Row(
            children: [
              Expanded(
                child: _buildAppleActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play',
                  isDark: isDark,
                  onTap: () async {
                    if (tracks != null && tracks.isNotEmpty) {
                      await queueService.startPlayback(
                        items: tracks,
                        source: QueueItemSource.fromBaseItem(artist),
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
                    if (tracks != null && tracks.isNotEmpty) {
                      await queueService.startPlayback(
                        items: tracks,
                        source: QueueItemSource.fromBaseItem(artist),
                        order: FinampPlaybackOrder.shuffled,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Top Songs Section
          if (tracks != null && tracks.isNotEmpty) ...[
            const Text(
              'Top Songs',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3),
            ),
            const SizedBox(height: 10),
            ...tracks.take(8).toList().asMap().entries.map((entry) {
              final index = entry.key;
              final track = entry.value;
              final durationText = printDuration(track.runTimeTicksDuration(), leadingZeroes: false);
              final subtitle = track.album ?? '';

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    leading: SizedBox(
                      width: 24,
                      child: Text(
                        '${index + 1}',
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
                    subtitle: subtitle.isNotEmpty
                        ? Text(
                            subtitle,
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
                        source: QueueItemSource.fromBaseItem(artist),
                        order: FinampPlaybackOrder.linear,
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    indent: 44,
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                  ),
                ],
              );
            }),
            const SizedBox(height: 24),
          ],

          // Albums Section
          if (albums.isNotEmpty) ...[
            const Text(
              'Albums',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 195,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: albums.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final album = albums[index];
                  final albumArtUrl = jellyfinApiHelper.getImageUrl(item: album)?.toString();
                  final year = album.productionYear != null ? '${album.productionYear}' : '';

                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushNamed(AlbumScreen.routeName, arguments: album);
                    },
                    child: SizedBox(
                      width: 135,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: albumArtUrl != null
                                ? Image.network(
                                    albumArtUrl,
                                    width: 135,
                                    height: 135,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      width: 135,
                                      height: 135,
                                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                                      child: const Icon(Icons.album_rounded, size: 48, color: Colors.grey),
                                    ),
                                  )
                                : Container(
                                    width: 135,
                                    height: 135,
                                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                                    child: const Icon(Icons.album_rounded, size: 48, color: Colors.grey),
                                  ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            album.name ?? 'Album',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                          if (year.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              year,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
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
              Icon(icon, color: ArtistScreen.appleAccentColor, size: 24),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: ArtistScreen.appleAccentColor,
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
