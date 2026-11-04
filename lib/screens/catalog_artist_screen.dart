import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

import '../components/now_playing_bar.dart';
import '../models/catalog_models.dart';
import '../models/finamp_models.dart';
import '../models/jellyfin_models.dart';
import '../services/catalog_api_client.dart';
import '../services/catalog_playback_helper.dart';
import '../services/jellyfin_api_helper.dart';
import '../services/queue_service.dart';
import '../services/artist_image_service.dart';
import '../services/artist_resolution_helper.dart';
import 'artist_screen.dart';
import 'catalog_album_screen.dart';
import 'catalog_discography_screen.dart';

class CatalogArtistScreenArguments {
  const CatalogArtistScreenArguments({
    required this.artistMbid,
    this.initialName,
    this.fallbackArtist,
  });

  factory CatalogArtistScreenArguments.fromSearchResult(CatalogSearchResult result) =>
      CatalogArtistScreenArguments(
        artistMbid: result.id,
        initialName: result.title,
      );

  final String artistMbid;
  final String? initialName;
  final BaseItemDto? fallbackArtist;
}

class CatalogArtistScreen extends StatefulWidget {
  const CatalogArtistScreen({super.key});
  static const routeName = '/catalog/artist';

  @override
  State<CatalogArtistScreen> createState() => _CatalogArtistScreenState();
}

class _CatalogArtistScreenState extends State<CatalogArtistScreen> {
  CatalogArtist? _artist;
  String? _error;
  bool _loading = true;
  bool _isFavorite = false;
  BaseItemDto? _fallbackArtist;
  String? _bio;
  String? _heroImageUrl;
  List<Map<String, String>> _similarArtists = const [];
  bool _bioExpanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadArtist();
  }

  Future<void> _loadArtist() async {
    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    CatalogArtistScreenArguments args;
    if (rawArgs is CatalogArtistScreenArguments) {
      args = rawArgs;
    } else if (rawArgs is CatalogSearchResult) {
      args = CatalogArtistScreenArguments.fromSearchResult(rawArgs);
    } else if (rawArgs is String) {
      args = CatalogArtistScreenArguments(artistMbid: rawArgs);
    } else {
      const defaultMbid = String.fromEnvironment('DEBUG_ARTIST_MBID', defaultValue: 'e0c97a4d-c392-41a9-a374-57af3e3eeab3');
      args = const CatalogArtistScreenArguments(artistMbid: defaultMbid);
    }

    _fallbackArtist = args.fallbackArtist;

    if (args.artistMbid.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No artist MBID provided.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = GetIt.instance<CatalogApiClient>();
      final artist = await client.getArtist(args.artistMbid);
      _artist = artist;

      // Extract image & bio
      _heroImageUrl = artist.imageUrl ?? ArtistImageService.getKnownArtistImageUrl(artist.name);
      _bio = artist.bio;

      // Asynchronously load bio, image, and similar artists from legitimate APIs
      unawaited(_fetchEnrichedMetadata(artist));
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchEnrichedMetadata(CatalogArtist artist) async {
    if (_heroImageUrl == null || _heroImageUrl!.isEmpty) {
      final img = await ArtistImageService.fetchArtistImageUrl(artist.name);
      if (img != null && mounted) {
        setState(() => _heroImageUrl = img);
      }
    }

    if (_bio == null || _bio!.isEmpty) {
      final bio = await ArtistImageService.fetchArtistBio(artist.name);
      if (bio != null && mounted) {
        setState(() => _bio = bio);
      }
    }

    final similar = await ArtistImageService.fetchSimilarArtists(artist.name);
    if (similar.isNotEmpty && mounted) {
      setState(() => _similarArtists = similar);
    }
  }

  Future<void> _playArtistRecordings(CatalogArtist artist) async {
    final playable = artist.recordings.where((r) => r.availability?.canPlay ?? false).toList();
    if (playable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No tracks by ${artist.name} are available in your Jellyfin library yet.'),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      final jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
      final queueService = GetIt.instance<QueueService>();
      final items = <BaseItemDto>[];

      for (final rec in playable) {
        if (rec.availability?.playableItemId != null) {
          try {
            final item = await jellyfinApiHelper.getItemById(BaseItemId(rec.availability!.playableItemId!));
            items.add(item);
          } catch (_) {}
        }
      }

      if (items.isNotEmpty) {
        await queueService.startPlayback(
          items: items,
          source: QueueItemSource.fromBaseItem(items.first),
          order: FinampPlaybackOrder.linear,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.play_circle_filled, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Playing ${artist.name} (${items.length} tracks)')),
                ],
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback failed: $e')),
        );
      }
    }
  }

  void _showArtistInfoDialog(CatalogArtist artist, List<CatalogSearchResult> studioAlbums) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(artist.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('MusicBrainz ID', artist.id),
            const SizedBox(height: 8),
            _buildInfoRow('Studio Albums', '${studioAlbums.length}'),
            const SizedBox(height: 8),
            _buildInfoRow('Total Releases', '${artist.albums.length}'),
            const SizedBox(height: 8),
            _buildInfoRow('Library Tracks', '${artist.recordings.length}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _openOfflineLibrary() {
    if (_fallbackArtist != null) {
      Navigator.of(context).pushNamed(
        ArtistScreen.routeName,
        arguments: {'artist': _fallbackArtist, 'disableRedirect': true},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.black45,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
        actions: [
          if (_fallbackArtist != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.black45,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.download_done, color: Colors.white, size: 20),
                  tooltip: 'View Downloaded Music',
                  onPressed: _openOfflineLibrary,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.black45,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                onPressed: _loadArtist,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const NowPlayingBar(),
      body: _buildBody(),
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
              Text('Could not load artist.', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    onPressed: _loadArtist,
                  ),
                  if (_fallbackArtist != null) ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.library_music),
                      label: const Text('Browse Downloaded'),
                      onPressed: _openOfflineLibrary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }

    final artist = _artist!;

    final studioAlbums = artist.albums.where((a) => a.category == 'album').toList();
    final epsAndSingles = artist.albums.where((a) => a.category == 'ep' || a.category == 'single').toList();
    final compilations = artist.albums.where((a) => a.category == 'compilation').toList();
    final liveAndOther = artist.albums.where((a) =>
        a.category == 'live' ||
        a.category == 'other' ||
        (a.category == null && !['album', 'ep', 'single', 'compilation'].contains(a.category))).toList();

    // Determine latest release for the featured card
    CatalogSearchResult? latestRelease;
    final sortedByDate = List<CatalogSearchResult>.from(artist.albums)
      ..sort((a, b) => (b.firstDate ?? '').compareTo(a.firstDate ?? ''));
    if (sortedByDate.isNotEmpty) {
      latestRelease = sortedByDate.first;
    }

    // Hero backdrop image: prioritize real artist photo, fallback to top album art
    final heroImageAlbum = artist.albums.cast<CatalogSearchResult?>().firstWhere(
          (a) => a?.imageUrl != null && a!.imageUrl!.isNotEmpty,
          orElse: () => null,
        );
    final effectiveHeroImageUrl = _heroImageUrl ?? heroImageAlbum?.imageUrl;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // 1. Apple Music Full-Bleed Artist Hero Section
        _buildArtistHeroHeader(
          artist: artist,
          heroImageUrl: effectiveHeroImageUrl,
          studioAlbumsCount: studioAlbums.length,
        ),

        // 2. Featured Latest Release Card (like Apple Music 'Getting Killed' card)
        if (latestRelease != null) ...[
          const SizedBox(height: 8),
          _buildFeaturedLatestReleaseCard(latestRelease),
        ],

        // 3. Top Songs Section
        if (artist.recordings.isNotEmpty) ...[
          _buildTopSongsSection(artist),
        ],

        // 4. Horizontal Carousels for Albums and Singles & EPs
        if (studioAlbums.isNotEmpty)
          _buildAlbumCarouselSection(
            title: 'Albums',
            artistName: artist.name,
            items: studioAlbums,
          ),

        if (epsAndSingles.isNotEmpty)
          _buildAlbumCarouselSection(
            title: 'Singles & EPs',
            artistName: artist.name,
            items: epsAndSingles,
          ),

        if (compilations.isNotEmpty)
          _buildAlbumCarouselSection(
            title: 'Compilations',
            artistName: artist.name,
            items: compilations,
          ),

        if (liveAndOther.isNotEmpty)
          _buildAlbumCarouselSection(
            title: 'Live & Other Releases',
            artistName: artist.name,
            items: liveAndOther,
          ),

        // 5. Artist Biography Section (Wikipedia)
        if (_bio != null && _bio!.isNotEmpty) ...[
          _buildBioSection(artist),
        ],

        // 6. Similar Artists Section (Deezer)
        if (_similarArtists.isNotEmpty) ...[
          _buildSimilarArtistsSection(artist),
        ],

        const SizedBox(height: 36),
      ],
    );
  }

  Widget _buildBioSection(CatalogArtist artist) {
    final bioText = _bio!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About ${artist.name}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bioText,
                  maxLines: _bioExpanded ? 30 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (bioText.length > 200) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setState(() => _bioExpanded = !_bioExpanded),
                    child: Text(
                      _bioExpanded ? 'Show less' : 'Read more',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarArtistsSection(CatalogArtist artist) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              Text(
                'Similar Artists',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 22, color: Colors.grey),
            ],
          ),
        ),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _similarArtists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 20),
            itemBuilder: (context, i) {
              final a = _similarArtists[i];
              final name = a['name'] ?? '';
              final imageUrl = a['imageUrl'] ?? '';
              return InkWell(
                borderRadius: BorderRadius.circular(44),
                onTap: () {
                  ArtistResolutionHelper.navigateToArtist(
                    context,
                    artistName: name,
                  );
                },
                child: SizedBox(
                  width: 90,
                  child: Column(
                    children: [
                      ClipOval(
                        child: imageUrl.isNotEmpty
                            ? Image.network(
                                imageUrl,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => CircleAvatar(
                                  radius: 40,
                                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                  child: const Icon(TablerIcons.user, size: 36),
                                ),
                              )
                            : CircleAvatar(
                                radius: 40,
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                child: const Icon(TablerIcons.user, size: 36),
                              ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildArtistHeroHeader({
    required CatalogArtist artist,
    required String? heroImageUrl,
    required int studioAlbumsCount,
  }) {
    return Container(
      height: 330,
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Hero backdrop image
          if (heroImageUrl != null)
            Image.network(
              heroImageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: const Icon(TablerIcons.user, size: 72, color: Colors.white24),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.shade900, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: const Icon(TablerIcons.user, size: 72, color: Colors.white24),
            ),

          // Gradient scrim fade into background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 0.55),
                  Theme.of(context).scaffoldBackgroundColor,
                ],
                stops: const [0.0, 0.65, 1.0],
              ),
            ),
          ),

          // Artist name and action cluster
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  artist.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (studioAlbumsCount > 0) '$studioAlbumsCount Albums',
                    '${artist.albums.length} Releases',
                    if (artist.recordings.isNotEmpty)
                      '${artist.recordings.length} ${artist.recordings.length == 1 ? 'Song' : 'Songs'} in Library',
                  ].join(' • '),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Info button [ ℹ ]
                    _buildHeroCircleButton(
                      icon: Icons.info_outline_rounded,
                      tooltip: 'Artist Info',
                      onTap: () => _showArtistInfoDialog(
                        artist,
                        artist.albums.where((a) => a.category == 'album').toList(),
                      ),
                    ),
                    const SizedBox(width: 24),

                    // Giant white Play Button [ ▶ ]
                    GestureDetector(
                      onTap: () => _playArtistRecordings(artist),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.play_arrow_rounded, color: Colors.black, size: 38),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),

                    // Spotify-green Favorite Button [ 💚 / 🤍 ]
                    _buildHeroCircleButton(
                      icon: _isFavorite ? Icons.favorite : Icons.favorite_border_rounded,
                      iconColor: _isFavorite ? const Color(0xFF1DB954) : Colors.white,
                      tooltip: _isFavorite ? 'In Favorites' : 'Add to Favorites',
                      onTap: () {
                        setState(() => _isFavorite = !_isFavorite);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_isFavorite
                                ? 'Added ${artist.name} to favorites'
                                : 'Removed ${artist.name} from favorites'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCircleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
          ),
          child: Center(
            child: Icon(icon, color: iconColor, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedLatestReleaseCard(CatalogSearchResult latest) {
    final year = latest.firstDate != null && latest.firstDate!.length >= 4
        ? latest.firstDate!.substring(0, 4)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).pushNamed(
            CatalogAlbumScreen.routeName,
            arguments: CatalogAlbumScreenArguments.fromSearchResult(latest),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: latest.imageUrl != null && latest.imageUrl!.isNotEmpty
                      ? Image.network(
                          latest.imageUrl!,
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 68,
                            height: 68,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            child: const Icon(TablerIcons.disc, size: 32),
                          ),
                        )
                      : Container(
                          width: 68,
                          height: 68,
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: const Icon(TablerIcons.disc, size: 32),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        latest.firstDate ?? 'Latest Release',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        latest.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          latest.primaryType ?? 'Album',
                          ?year,
                          if (latest.isFullyOwned) 'In Library',
                        ].join(' • '),
                        style: TextStyle(
                          fontSize: 12,
                          color: latest.isFullyOwned ? Colors.green : Colors.grey,
                          fontWeight: latest.isFullyOwned ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: latest.isFullyOwned
                        ? Colors.green.withValues(alpha: 0.15)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  child: Icon(
                    latest.isFullyOwned ? Icons.check_circle : Icons.chevron_right,
                    size: 20,
                    color: latest.isFullyOwned ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopSongsSection(CatalogArtist artist) {
    final topTracks = artist.recordings.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              Text(
                'Top Songs',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 22, color: Colors.grey),
            ],
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          itemCount: topTracks.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 60),
          itemBuilder: (context, index) {
            final track = topTracks[index];
            final canPlay = track.availability?.canPlay ?? false;

            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${index + 1}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: track.imageUrl != null && track.imageUrl!.isNotEmpty
                        ? Image.network(
                            track.imageUrl!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 44,
                              height: 44,
                              color: Theme.of(context).colorScheme.primaryContainer,
                              child: const Icon(TablerIcons.music, size: 22),
                            ),
                          )
                        : Container(
                            width: 44,
                            height: 44,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            child: const Icon(TablerIcons.music, size: 22),
                          ),
                  ),
                ],
              ),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
              ),
              subtitle: Text(
                [
                  track.displayArtist ?? artist.name,
                  if (track.formattedDuration.isNotEmpty) track.formattedDuration,
                ].join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              trailing: canPlay
                  ? const Icon(Icons.play_circle_fill, color: Colors.green, size: 26)
                  : const Icon(Icons.play_circle_outline, color: Colors.grey, size: 24),
              onTap: () => CatalogPlaybackHelper.handleTrackTap(
                context,
                title: track.title,
                availability: track.availability,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAlbumCarouselSection({
    required String title,
    required String artistName,
    required List<CatalogSearchResult> items,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    final hasMore = items.length > 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              if (hasMore)
                InkWell(
                  onTap: () => Navigator.of(context).pushNamed(
                    CatalogDiscographyScreen.routeName,
                    arguments: CatalogDiscographyScreenArguments(
                      title: title,
                      artistName: artistName,
                      items: items,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('See All', style: TextStyle(fontWeight: FontWeight.w600)),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 205,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length > 10 ? 10 : items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final album = items[index];
              return _buildAlbumSquareCard(album);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumSquareCard(CatalogSearchResult album) {
    final year = album.firstDate != null && album.firstDate!.length >= 4
        ? album.firstDate!.substring(0, 4)
        : null;

    return SizedBox(
      width: 142,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(
          CatalogAlbumScreen.routeName,
          arguments: CatalogAlbumScreenArguments.fromSearchResult(album),
        ),
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: album.imageUrl != null && album.imageUrl!.isNotEmpty
                      ? Image.network(
                          album.imageUrl!,
                          width: 142,
                          height: 142,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 142,
                            height: 142,
                            color: Theme.of(context).colorScheme.primaryContainer,
                            child: const Icon(TablerIcons.disc, size: 48),
                          ),
                        )
                      : Container(
                          width: 142,
                          height: 142,
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: const Icon(TablerIcons.disc, size: 48),
                        ),
                ),
                if (album.isFullyOwned)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 12, color: Colors.white),
                    ),
                  )
                else if (album.isPartiallyOwned)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade800,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.pie_chart, size: 12, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              year ?? (album.primaryType ?? 'Album'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
