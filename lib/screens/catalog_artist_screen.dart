import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

import '../components/finamp_app_bar_back_button.dart';
import '../components/now_playing_bar.dart';
import '../models/catalog_models.dart';
import '../services/catalog_api_client.dart';
import '../services/catalog_playback_helper.dart';
import 'catalog_album_screen.dart';
import 'catalog_discography_screen.dart';

class CatalogArtistScreenArguments {
  const CatalogArtistScreenArguments({required this.artistMbid, this.initialName});

  factory CatalogArtistScreenArguments.fromSearchResult(CatalogSearchResult result) =>
      CatalogArtistScreenArguments(
        artistMbid: result.id,
        initialName: result.title,
      );

  final String artistMbid;
  final String? initialName;
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
      args = const CatalogArtistScreenArguments(artistMbid: '');
    }

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
      _artist = await client.getArtist(args.artistMbid);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _artist?.name ?? 'Artist Details';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: const FinampAppBarBackButton(),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadArtist,
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
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: _loadArtist,
              ),
            ],
          ),
        ),
      );
    }

    final artist = _artist!;

    final studioAlbums = artist.albums.where((a) => a.category == 'album').toList();
    final eps = artist.albums.where((a) => a.category == 'ep').toList();
    final singles = artist.albums.where((a) => a.category == 'single').toList();
    final compilations = artist.albums.where((a) => a.category == 'compilation').toList();
    final liveAndOther = artist.albums.where((a) =>
        a.category == 'live' ||
        a.category == 'other' ||
        (a.category == null && !['album', 'ep', 'single', 'compilation'].contains(a.category))).toList();

    final hasCategorizedSections = studioAlbums.isNotEmpty || eps.isNotEmpty || singles.isNotEmpty || compilations.isNotEmpty || liveAndOther.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: const Icon(TablerIcons.user, size: 40),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (studioAlbums.isNotEmpty) '${studioAlbums.length} studio albums',
                          '${artist.albums.length} total releases',
                          if (artist.recordings.isNotEmpty) '${artist.recordings.length} in library',
                        ].join(' • '),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        if (hasCategorizedSections) ...[
          _buildDiscographySection(
            title: 'Albums',
            artistName: artist.name,
            items: studioAlbums,
            limit: 5,
          ),
          _buildDiscographySection(
            title: 'EPs',
            artistName: artist.name,
            items: eps,
            limit: 4,
          ),
          _buildDiscographySection(
            title: 'Singles',
            artistName: artist.name,
            items: singles,
            limit: 4,
          ),
          _buildDiscographySection(
            title: 'Compilations',
            artistName: artist.name,
            items: compilations,
            limit: 3,
          ),
          _buildDiscographySection(
            title: 'Live & Other Releases',
            artistName: artist.name,
            items: liveAndOther,
            limit: 3,
          ),
        ] else if (artist.albums.isNotEmpty) ...[
          _buildDiscographySection(
            title: 'Albums & Releases',
            artistName: artist.name,
            items: artist.albums,
            limit: 5,
          ),
        ],

        if (artist.recordings.isNotEmpty) ...[
          _buildSectionHeader(
            'Available Songs in Library',
            artist.recordings.length,
          ),
          ...artist.recordings.take(8).map((rec) => ListTile(
                leading: const Icon(TablerIcons.music),
                title: Text(rec.title),
                subtitle: rec.formattedDuration.isNotEmpty ? Text(rec.formattedDuration) : null,
                trailing: (rec.availability?.canPlay ?? false)
                    ? const Icon(Icons.play_circle_fill, color: Colors.green)
                    : null,
                onTap: () => CatalogPlaybackHelper.handleTrackTap(
                  context,
                  title: rec.title,
                  availability: rec.availability,
                ),
              )),
          if (artist.recordings.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Center(
                child: Text(
                  '+ ${artist.recordings.length - 8} more songs available in library',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildDiscographySection({
    required String title,
    required String artistName,
    required List<CatalogSearchResult> items,
    int limit = 5,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    final visible = items.take(limit).toList();
    final hasMore = items.length > limit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title,
          items.length,
          onSeeAll: hasMore
              ? () => Navigator.of(context).pushNamed(
                    CatalogDiscographyScreen.routeName,
                    arguments: CatalogDiscographyScreenArguments(
                      title: title,
                      artistName: artistName,
                      items: items,
                    ),
                  )
              : null,
        ),
        ...visible.map(_buildAlbumTile),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Center(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text('Show all ${items.length} ${title.toLowerCase()}'),
                onPressed: () => Navigator.of(context).pushNamed(
                  CatalogDiscographyScreen.routeName,
                  arguments: CatalogDiscographyScreenArguments(
                    title: title,
                    artistName: artistName,
                    items: items,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('See All'),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAlbumTile(CatalogSearchResult album) {
    Widget leadingWidget;
    if (album.imageUrl != null && album.imageUrl!.isNotEmpty) {
      leadingWidget = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          album.imageUrl!,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: 50,
            height: 50,
            color: Theme.of(context).colorScheme.primaryContainer,
            child: const Icon(TablerIcons.disc, size: 28),
          ),
        ),
      );
    } else {
      leadingWidget = Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(TablerIcons.disc, size: 28),
      );
    }

    Widget trailingWidget;
    if (album.isFullyOwned) {
      trailingWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green, width: 1),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 12, color: Colors.green),
            SizedBox(width: 4),
            Text('In Library', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else if (album.isPartiallyOwned) {
      trailingWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade800, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pie_chart, size: 12, color: Colors.amber.shade800),
            const SizedBox(width: 4),
            Text('Partial', style: TextStyle(color: Colors.amber.shade800, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else {
      trailingWidget = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_outlined, size: 16, color: Colors.grey),
          SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        ],
      );
    }

    final year = album.firstDate != null && album.firstDate!.length >= 4 ? album.firstDate!.substring(0, 4) : null;
    final info = [
      ?year,
      if (album.primaryType != null) album.primaryType,
      if (album.secondaryTypes.isNotEmpty) album.secondaryTypes.join(', '),
    ].join(' • ');

    return ListTile(
      leading: leadingWidget,
      title: Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(info.isNotEmpty ? info : 'Album', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailingWidget,
      onTap: () => Navigator.of(context).pushNamed(
        CatalogAlbumScreen.routeName,
        arguments: CatalogAlbumScreenArguments.fromSearchResult(album),
      ),
    );
  }
}
