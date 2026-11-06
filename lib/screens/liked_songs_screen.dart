import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

import '../components/album_image.dart';
import '../components/AlbumScreen/track_list_tile.dart';
import '../components/now_playing_bar.dart';
import '../menus/track_menu.dart';
import '../models/finamp_models.dart';
import '../models/jellyfin_models.dart';
import '../services/favorite_provider.dart';
import '../services/finamp_settings_helper.dart';
import '../services/liked_songs_service.dart';
import '../services/queue_service.dart';

enum _LikedSongsSort { libraryNewest, libraryOldest, title, artist, album, lastPlayed }

extension _LikedSongsSortLabel on _LikedSongsSort {
  String get label => switch (this) {
    _LikedSongsSort.libraryNewest => 'Recently added to library',
    _LikedSongsSort.libraryOldest => 'Oldest in library',
    _LikedSongsSort.title => 'Title',
    _LikedSongsSort.artist => 'Artist',
    _LikedSongsSort.album => 'Album',
    _LikedSongsSort.lastPlayed => 'Recently played',
  };
}

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
  _LikedSongsSort _sort = _LikedSongsSort.libraryNewest;

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
        name: const QueueItemSourceName(type: QueueItemSourceNameType.yourLikes),
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
    final sortedGenres = genreCounts.keys.toList()..sort((a, b) => genreCounts[b]!.compareTo(genreCounts[a]!));

    // Filter tracks based on query and selected genre
    final filteredTracks = allTracks.where((t) {
      if (_selectedGenre != null) {
        final matchesGenre = t.genres?.any((g) => g.trim().toLowerCase() == _selectedGenre!.toLowerCase()) ?? false;
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

    // Jellyfin DateCreated is the library-import date, NOT the date favorited.
    // Do not mislabel it as "Date liked" until the account backend supplies
    // an authoritative liked_at event for this user's favorites.
    int compareText(String? a, String? b) => (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase());
    int compareDate(String? a, String? b) {
      final first = DateTime.tryParse(a ?? '');
      final second = DateTime.tryParse(b ?? '');
      if (first == null && second == null) return 0;
      if (first == null) return 1;
      if (second == null) return -1;
      return first.compareTo(second);
    }

    filteredTracks.sort((a, b) {
      final order = switch (_sort) {
        _LikedSongsSort.libraryNewest => compareDate(b.dateCreated, a.dateCreated),
        _LikedSongsSort.libraryOldest => compareDate(a.dateCreated, b.dateCreated),
        _LikedSongsSort.title => compareText(a.name, b.name),
        _LikedSongsSort.artist => compareText(a.artists?.firstOrNull ?? a.albumArtist, b.artists?.firstOrNull ?? b.albumArtist),
        _LikedSongsSort.album => compareText(a.album, b.album),
        _LikedSongsSort.lastPlayed => compareDate(b.userData?.lastPlayedDate, a.userData?.lastPlayedDate),
      };
      return order != 0 ? order : compareText(a.name, b.name);
    });

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
                    icon: Icon(Icons.chevron_left, color: isDark ? Colors.white : Colors.black87, size: 26),
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
                    icon: Icon(Icons.refresh, color: isDark ? Colors.white : Colors.black87, size: 20),
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
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
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
                    decoration: BoxDecoration(color: appleAccentColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: const Icon(Icons.favorite_border, size: 40, color: appleAccentColor),
                  ),
                  const SizedBox(height: 20),
                  const Text('No Liked Songs Yet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
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
                    style: FilledButton.styleFrom(backgroundColor: appleAccentColor, foregroundColor: Colors.white),
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
                _buildLikedHeader(filteredTracks, totalDuration, isDark),
                const SizedBox(height: 16),
                // Apple-style In-Playlist Search Field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 20, color: isDark ? Colors.white60 : Colors.black54),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Find in liked songs',
                              hintStyle: TextStyle(fontSize: 14.5, color: isDark ? Colors.white38 : Colors.black38),
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
                            child: Icon(Icons.cancel, size: 18, color: isDark ? Colors.white54 : Colors.black54),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: MediaQuery.sizeOf(context).width >= 900 ? 24 : 16),
                  child: Row(
                    children: [
                      Text(
                        '${filteredTracks.length} ${filteredTracks.length == 1 ? 'song' : 'songs'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                      const Spacer(),
                      PopupMenuButton<_LikedSongsSort>(
                        initialValue: _sort,
                        tooltip: 'Sort liked songs',
                        onSelected: (value) => setState(() => _sort = value),
                        itemBuilder: (context) => _LikedSongsSort.values
                            .map((value) => PopupMenuItem<_LikedSongsSort>(
                                  value: value,
                                  child: Row(
                                    children: [
                                      if (_sort == value) const Icon(Icons.check, size: 16),
                                      if (_sort == value) const SizedBox(width: 8),
                                      Text(value.label),
                                    ],
                                  ),
                                ))
                            .toList(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.sort, size: 17),
                              const SizedBox(width: 8),
                              Text(_sort.label, style: const TextStyle(fontSize: 13)),
                              const SizedBox(width: 4),
                              const Icon(Icons.expand_more, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
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
                                  : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA)),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text(
                                genre,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : (isDark ? Colors.white : Colors.black87),
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
          if (MediaQuery.sizeOf(context).width >= 900 && filteredTracks.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  children: [
                    Row(
                      children: const [
                        SizedBox(width: 38, child: Text('#')),
                        Expanded(flex: 5, child: Text('TITLE')),
                        Expanded(flex: 3, child: Text('ALBUM')),
                        Expanded(flex: 2, child: Text('ADDED TO LIBRARY')),
                        SizedBox(width: 66, child: Align(alignment: Alignment.centerRight, child: Icon(Icons.schedule, size: 17))),
                        SizedBox(width: 92),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                  ],
                ),
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
                      Icon(Icons.search_off_rounded, size: 48, color: isDark ? Colors.white24 : Colors.black26),
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
                delegate: SliverChildBuilderDelegate((context, index) {
                  final item = filteredTracks[index];
                  final wide = MediaQuery.sizeOf(context).width >= 900;
                  return wide
                      ? _buildDesktopLikedRow(item, index, filteredTracks, isDark)
                      : TrackListItem(
                          key: ValueKey('liked-${item.id}'),
                          baseItem: item,
                          listIndex: index,
                          actualIndex: null,
                          onTap: (playable) {
                            if (playable) _playTracks(filteredTracks, startingIndex: index);
                          },
                          confirmDismiss: (direction) => onConfirmPlayableDismiss(
                            followUpAction: direction == DismissDirection.startToEnd
                                ? ref.read(finampSettingsProvider.itemSwipeActionLeftToRight)
                                : ref.read(finampSettingsProvider.itemSwipeActionRightToLeft),
                            item: Track(item, source: QueueItemSource.fromBaseItem(item)),
                          ),
                          leftSwipeBackground: buildSwipeActionBackground(
                            context: context,
                            direction: DismissDirection.startToEnd,
                            action: ref.watch(finampSettingsProvider.itemSwipeActionLeftToRight),
                          ),
                          rightSwipeBackground: buildSwipeActionBackground(
                            context: context,
                            direction: DismissDirection.endToStart,
                            action: ref.watch(finampSettingsProvider.itemSwipeActionRightToLeft),
                          ),
                          features: const [
                            TrackListItemFeatures.cover,
                            TrackListItemFeatures.addToPlaylistOrFavorite,
                            TrackListItemFeatures.swipeableInTrackList,
                          ],
                        );
                }, childCount: filteredTracks.length),
              ),
            ),
        ],
      ),
    );
  }

  String _formatLibraryAdded(String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    return date == null ? '—' : '${date.month}/${date.day}/${date.year}';
  }

  String _formatTrackDuration(int? ticks) {
    if (ticks == null || ticks <= 0) return '—';
    final seconds = ticks ~/ 10000000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _buildDesktopLikedRow(BaseItemDto item, int index, List<BaseItemDto> tracks, bool isDark) {
    final textSecondary = isDark ? Colors.white60 : Colors.black54;
    final artist = item.artists?.join(', ') ?? item.albumArtist ?? 'Unknown Artist';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () => _playTracks(tracks, startingIndex: index),
          onSecondaryTap: () => showModalTrackMenu(context: context, item: item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 38, child: Text('${index + 1}', style: TextStyle(color: textSecondary))),
                Expanded(
                  flex: 5,
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(width: 42, height: 42, child: AlbumImage(item: item)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(item.name ?? 'Untitled', maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: Text(item.album ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: textSecondary)),
                ),
                Expanded(
                  flex: 2,
                  child: Text(_formatLibraryAdded(item.dateCreated),
                      style: TextStyle(fontSize: 12, color: textSecondary)),
                ),
                SizedBox(
                  width: 66,
                  child: Text(_formatTrackDuration(item.runTimeTicks),
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12, color: textSecondary)),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: Row(
                    children: [
                      Consumer(
                        builder: (context, ref, _) {
                          final isFav = ref.watch(isFavoriteProvider(item));
                          return IconButton(
                            icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, size: 19),
                            color: isFav ? appleAccentColor : textSecondary,
                            tooltip: isFav ? 'Remove Favorite' : 'Add Favorite',
                            onPressed: () => ref.read(isFavoriteProvider(item).notifier).updateFavorite(!isFav),
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'More song actions',
                        icon: Icon(Icons.more_horiz, size: 20, color: textSecondary),
                        onPressed: () => showModalTrackMenu(context: context, item: item),
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

  /// One semantic collection header with adaptive presentation for every client.
  /// Narrow views use stacked artwork and actions; wide views use a compact
  /// desktop/table header instead of stretching the phone composition.
  Widget _buildLikedHeader(List<BaseItemDto> filteredTracks, String totalDuration, bool isDark) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final artSide = wide ? 192.0 : 148.0;
    final artwork = Container(
      width: artSide,
      height: artSide,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(wide ? 8 : 16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B11FF), Color(0xFF9F4BBD), Color(0xFFB6E4D1)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(child: Icon(Icons.favorite, size: wide ? 80 : 68, color: Colors.white)),
    );

    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (wide) ...[
          const Text('Playlist', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
        ],
        Text(
          'Liked Songs',
          style: TextStyle(
            fontSize: wide ? 56 : 26,
            fontWeight: FontWeight.w800,
            letterSpacing: wide ? -2.0 : -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Made By You · ${filteredTracks.length} ${filteredTracks.length == 1 ? 'song' : 'songs'} · $totalDuration',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFFCBC8D1) : const Color(0xFF6E6E73),
          ),
        ),
      ],
    );

    final playActions = wide
        ? Row(
            children: [
              IconButton.filled(
                onPressed: () => _playTracks(filteredTracks),
                tooltip: 'Play liked songs',
                icon: const Icon(Icons.play_arrow_rounded, size: 32),
                iconSize: 32,
                style: IconButton.styleFrom(
                  backgroundColor: appleAccentColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(56, 56),
                ),
              ),
              const SizedBox(width: 14),
              OutlinedButton.icon(
                onPressed: () => _playTracks(filteredTracks, shuffle: true),
                icon: const Icon(TablerIcons.arrows_shuffle),
                label: const Text('Shuffle'),
              ),
            ],
          )
        : Row(
            children: [
              Expanded(
                child: _buildAppleActionButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play',
                  isDark: isDark,
                  onTap: () => _playTracks(filteredTracks),
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
          );

    if (!wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 8),
            artwork,
            const SizedBox(height: 16),
            details,
            const SizedBox(height: 18),
            playActions,
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF35214F), const Color(0xFF19141F)]
              : [const Color(0xFFE9DCF8), const Color(0xFFF6F4F8)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              artwork,
              const SizedBox(width: 24),
              Expanded(child: details),
            ],
          ),
          const SizedBox(height: 20),
          playActions,
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
