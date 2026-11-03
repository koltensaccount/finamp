import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

import '../components/album_image.dart';
import '../components/now_playing_bar.dart';
import '../menus/track_menu.dart';
import '../models/finamp_models.dart';
import '../models/jellyfin_models.dart';
import '../services/favorite_provider.dart';
import '../services/liked_songs_service.dart';
import '../services/queue_service.dart';

class LikedSongsScreen extends ConsumerStatefulWidget {
  const LikedSongsScreen({super.key});
  static const routeName = '/liked-songs';

  @override
  ConsumerState<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends ConsumerState<LikedSongsScreen> {
  final _searchController = TextEditingController();
  final _queueService = GetIt.instance<QueueService>();

  String _query = '';
  String? _selectedGenre;

  static const Color appleAccentColor = Color(0xFFFA2D48);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(likedSongsProvider).syncWithJellyfin();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _playTracks(List<BaseItemDto> tracks, {bool shuffle = false, int startingIndex = 0}) async {
    if (tracks.isEmpty) return;
    final itemsToPlay = List<BaseItemDto>.from(tracks);
    if (shuffle) {
      itemsToPlay.shuffle(Random());
    }
    await _queueService.startPlayback(
      items: itemsToPlay,
      source: QueueItemSource.rawId(
        type: QueueItemSourceType.playlist,
        name: const QueueItemSourceName(
          type: QueueItemSourceNameType.yourLikes,
        ),
        id: 'liked-songs',
      ),
      startingIndex: shuffle ? 0 : startingIndex,
      order: shuffle ? FinampPlaybackOrder.shuffled : FinampPlaybackOrder.linear,
    );
  }

  String _formatTotalDuration(List<BaseItemDto> tracks) {
    int totalRunTimeTicks = 0;
    for (final t in tracks) {
      totalRunTimeTicks += (t.runTimeTicks ?? 0);
    }
    final totalSeconds = (totalRunTimeTicks ~/ 10000) ~/ 1000;
    final totalMinutes = totalSeconds ~/ 60;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) {
      return '$hours hr $minutes min';
    } else {
      return '$minutes min';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final likedSongs = ref.watch(likedSongsProvider);
    final allTracks = likedSongs.tracks;
    final loading = likedSongs.isLoading && allTracks.isEmpty;
    final error = likedSongs.error;

    // Extract sorted unique genres for Spotify-style mood/genre filter pills
    final genreCounts = <String, int>{};
    for (final t in allTracks) {
      if (t.genres != null) {
        for (final g in t.genres!) {
          final trimmed = g.trim();
          if (trimmed.isNotEmpty) {
            genreCounts[trimmed] = (genreCounts[trimmed] ?? 0) + 1;
          }
        }
      }
    }
    final sortedGenres = genreCounts.keys.toList()
      ..sort((a, b) => genreCounts[b]!.compareTo(genreCounts[a]!));

    // Filter tracks based on query and selected genre
    final filteredTracks = allTracks.where((t) {
      if (_selectedGenre != null) {
        final matchesGenre = t.genres?.any(
              (g) => g.trim().toLowerCase() == _selectedGenre!.toLowerCase(),
            ) ??
            false;
        if (!matchesGenre) return false;
      }
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        final nameMatch = t.name?.toLowerCase().contains(q) ?? false;
        final artistMatch = t.artists?.any((a) => a.toLowerCase().contains(q)) ?? false;
        final albumMatch = t.album?.toLowerCase().contains(q) ?? false;
        return nameMatch || artistMatch || albumMatch;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
      bottomNavigationBar: const NowPlayingBar(),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: isDark
                ? (innerBoxIsScrolled ? const Color(0xE61C1C1E) : Colors.transparent)
                : (innerBoxIsScrolled ? const Color(0xEEFFFFFF) : Colors.transparent),
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Center(
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.chevron_left,
                      color: isDark ? Colors.white : Colors.black87,
                      size: 26,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
            title: innerBoxIsScrolled
                ? Text(
                    'Liked Songs',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      letterSpacing: -0.3,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  )
                : null,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.refresh,
                      color: isDark ? Colors.white : Colors.black87,
                      size: 20,
                    ),
                    tooltip: 'Sync with Jellyfin',
                    onPressed: () => ref.read(likedSongsProvider).syncWithJellyfin(force: true),
                  ),
                ),
              ),
            ],
          ),
        ],
        body: _buildBody(
          allTracks: allTracks,
          filteredTracks: filteredTracks,
          sortedGenres: sortedGenres,
          loading: loading,
          error: error,
          isDark: isDark,
        ),
      ),
    );
  }

  Widget _buildBody({
    required List<BaseItemDto> allTracks,
    required List<BaseItemDto> filteredTracks,
    required List<String> sortedGenres,
    required bool loading,
    required String? error,
    required bool isDark,
  }) {
    if (loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (error != null && allTracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Could not load liked songs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(backgroundColor: appleAccentColor),
                onPressed: () => ref.read(likedSongsProvider).syncWithJellyfin(force: true),
              ),
            ],
          ),
        ),
      );
    }

    if (allTracks.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref.read(likedSongsProvider).syncWithJellyfin(force: true),
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 64),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: appleAccentColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.favorite_border, size: 40, color: appleAccentColor),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'No Liked Songs Yet',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Songs favorited on Jellyfin sync here automatically. Tap the heart icon on any song to add it to your Liked Songs.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync with Jellyfin'),
                    style: FilledButton.styleFrom(
                      backgroundColor: appleAccentColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => ref.read(likedSongsProvider).syncWithJellyfin(force: true),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final totalDuration = _formatTotalDuration(filteredTracks);

    return RefreshIndicator(
      onRefresh: () => ref.read(likedSongsProvider).syncWithJellyfin(force: true),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                // Apple Music Liked Songs Artwork Card
                Center(
                  child: Container(
                    width: 148,
                    height: 148,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF6B11FF), // Deep Electric Purple
                          Color(0xFFFA2D48), // Apple Music Red
                          Color(0xFFFF5252), // Coral Flame
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: appleAccentColor.withValues(alpha: 0.32),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.favorite, size: 68, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Liked Songs',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Made By You • ${filteredTracks.length} ${filteredTracks.length == 1 ? 'song' : 'songs'} • $totalDuration',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73),
                  ),
                ),
                const SizedBox(height: 16),
                // Dual Apple Music Action Buttons: [ ▶ Play ] [ 🔀 Shuffle ]
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildAppleActionButton(
                          icon: Icons.play_arrow_rounded,
                          label: 'Play',
                          isDark: isDark,
                          onTap: () => _playTracks(filteredTracks, shuffle: false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildAppleActionButton(
                          icon: TablerIcons.arrows_shuffle,
                          label: 'Shuffle',
                          isDark: isDark,
                          onTap: () => _playTracks(filteredTracks, shuffle: true),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Apple-style In-Playlist Search Field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1C1C1E)
                          : const Color(0xFFE5E5EA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search,
                          size: 20,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(
                              fontSize: 15,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Find in liked songs',
                              hintStyle: TextStyle(
                                fontSize: 14.5,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (val) => setState(() => _query = val.trim()),
                          ),
                        ),
                        if (_query.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            child: Icon(
                              Icons.cancel,
                              size: 18,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Spotify-style Genre / Mood Filter Chips
                if (sortedGenres.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: sortedGenres.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        final genre = sortedGenres[idx];
                        final isSelected = _selectedGenre == genre;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedGenre = isSelected ? null : genre;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? appleAccentColor
                                  : (isDark
                                      ? const Color(0xFF2C2C2E)
                                      : const Color(0xFFE5E5EA)),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text(
                                genre,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark ? Colors.white : Colors.black87),
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
          if (filteredTracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 48,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _selectedGenre != null
                            ? 'No "$_selectedGenre" tracks match "$_query"'
                            : 'No songs match "$_query"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 120),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = filteredTracks[index];
                    final artistName = item.artists?.join(', ') ?? (item.albumArtist ?? 'Unknown Artist');

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: AlbumImage(item: item),
                            ),
                          ),
                          title: Text(
                            item.name ?? 'Untitled',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              letterSpacing: -0.2,
                            ),
                          ),
                          subtitle: Text(
                            [
                              artistName,
                              if (item.album != null && item.album!.isNotEmpty) item.album!,
                            ].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73),
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Dedicated Red Heart Icon (stays active & syncs bi-directionally)
                              Consumer(
                                builder: (context, ref, _) {
                                  final isFav = ref.watch(isFavoriteProvider(item));
                                  return IconButton(
                                    icon: Icon(
                                      isFav ? Icons.favorite : Icons.favorite_border,
                                      color: isFav
                                          ? appleAccentColor
                                          : (isDark ? Colors.white54 : Colors.black45),
                                      size: 22,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: isFav ? 'Remove from Liked Songs' : 'Add to Liked Songs',
                                    onPressed: () {
                                      ref.read(isFavoriteProvider(item).notifier).updateFavorite(!isFav);
                                    },
                                  );
                                },
                              ),
                              // Context Menu ("...") for Track Actions
                              IconButton(
                                icon: Icon(
                                  Icons.more_horiz,
                                  color: isDark ? Colors.white54 : Colors.black45,
                                  size: 20,
                                ),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  showModalTrackMenu(
                                    context: context,
                                    item: item,
                                  );
                                },
                              ),
                            ],
                          ),
                          onTap: () => _playTracks(filteredTracks, shuffle: false, startingIndex: index),
                        ),
                        Divider(
                          height: 1,
                          indent: 76,
                          endIndent: 16,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06),
                        ),
                      ],
                    );
                  },
                  childCount: filteredTracks.length,
                ),
              ),
            ),
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
              Icon(icon, color: appleAccentColor, size: 24),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: appleAccentColor,
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
