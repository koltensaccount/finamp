import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

import '../components/album_image.dart';
import '../components/favorite_button.dart';
import '../components/finamp_app_bar_back_button.dart';
import '../components/now_playing_bar.dart';
import '../models/finamp_models.dart';
import '../models/jellyfin_models.dart';
import '../services/finamp_user_helper.dart';
import '../services/jellyfin_api_helper.dart';
import '../services/queue_service.dart';

class LikedSongsScreen extends ConsumerStatefulWidget {
  const LikedSongsScreen({super.key});
  static const routeName = '/liked-songs';

  @override
  ConsumerState<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends ConsumerState<LikedSongsScreen> {
  final _searchController = TextEditingController();
  final _jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
  final _queueService = GetIt.instance<QueueService>();

  List<BaseItemDto>? _tracks;
  String? _error;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadLikedSongs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLikedSongs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _jellyfinApiHelper.getItems(
        includeItemTypes: 'Audio',
        recursive: true,
        isFavorite: true,
        sortBy: 'DateCreated',
        sortOrder: 'Descending',
      );
      if (mounted) {
        setState(() {
          _tracks = items ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _playTracks({bool shuffle = false}) async {
    if (_tracks == null || _tracks!.isEmpty) return;
    final itemsToPlay = List<BaseItemDto>.from(_tracks!);
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
      order: shuffle ? FinampPlaybackOrder.shuffled : FinampPlaybackOrder.linear,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userName = ref.watch(UserInfoProviders.currentUserInfoProvider).valueOrNull?.jellyfinUser?.name ?? 'You';

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            leading: const FinampAppBarBackButton(),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _loadLikedSongs,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
              title: innerBoxIsScrolled
                  ? const Text('Liked Songs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))
                  : null,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF4A148C), // Deep Purple
                      Color(0xFF1A237E), // Deep Indigo
                      Color(0xFF004D40), // Dark Teal
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF7B1FA2), Color(0xFF3F51B5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.favorite, size: 44, color: Colors.white),
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Liked Songs',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$userName • ${_tracks?.length ?? 0} songs',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        body: _buildBody(),
      ),
      bottomNavigationBar: const NowPlayingBar(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Could not load liked songs.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: _loadLikedSongs,
              ),
            ],
          ),
        ),
      );
    }

    final tracks = _tracks ?? [];
    if (tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.favorite_border, size: 36),
              ),
              const SizedBox(height: 16),
              const Text('No liked songs yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Songs you like will appear here. Tap the heart on any song to add it to your Liked Songs.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _query.isEmpty
        ? tracks
        : tracks.where((t) {
            final q = _query.toLowerCase();
            final nameMatch = t.name?.toLowerCase().contains(q) ?? false;
            final artistMatch = t.artists?.any((a) => a.toLowerCase().contains(q)) ?? false;
            final albumMatch = t.album?.toLowerCase().contains(q) ?? false;
            return nameMatch || artistMatch || albumMatch;
          }).toList();

    return Column(
      children: [
        // Action Bar with Play/Shuffle & Search
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Find in liked songs...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (val) => setState(() => _query = val.trim()),
                ),
              ),
              const SizedBox(width: 12),
              // Spotify-style Green Play/Shuffle Button
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954), // Spotify Green
                  foregroundColor: Colors.black,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                ),
                onPressed: () => _playTracks(shuffle: true),
                child: const Icon(TablerIcons.arrows_shuffle, size: 22, color: Colors.black),
              ),
              const SizedBox(width: 6),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954), // Spotify Green
                  foregroundColor: Colors.black,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                ),
                onPressed: () => _playTracks(shuffle: false),
                child: const Icon(Icons.play_arrow, size: 26, color: Colors.black),
              ),
            ],
          ),
        ),
        const Divider(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text('No songs match "$_query"', style: const TextStyle(color: Colors.grey)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 68),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final durationMs = item.runTimeTicks != null ? (item.runTimeTicks! ~/ 10000) : 0;
                    final totalSeconds = durationMs ~/ 1000;
                    final minutes = totalSeconds ~/ 60;
                    final seconds = totalSeconds % 60;
                    final durationStr = '$minutes:${seconds.toString().padLeft(2, '0')}';

                    final artistName = item.artists?.join(', ') ?? (item.albumArtist ?? 'Unknown Artist');

                    return ListTile(
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
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        [
                          artistName,
                          if (item.album != null && item.album!.isNotEmpty) item.album!,
                        ].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(durationStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(width: 4),
                          FavoriteButton(
                            item: item,
                            color: const Color(0xFF1DB954),
                            size: 22,
                          ),
                        ],
                      ),
                      onTap: () async {
                        await _queueService.startPlayback(
                          items: filtered,
                          source: QueueItemSource.rawId(
                            type: QueueItemSourceType.playlist,
                            name: const QueueItemSourceName(
                              type: QueueItemSourceNameType.yourLikes,
                            ),
                            id: 'liked-songs',
                          ),
                          startingIndex: index,
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
