import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

import '../components/finamp_app_bar_back_button.dart';
import '../components/now_playing_bar.dart';
import '../models/catalog_models.dart';
import '../services/catalog_api_client.dart';
import '../services/catalog_playback_helper.dart';
import 'catalog_album_screen.dart';
import 'catalog_artist_screen.dart';
import 'catalog_settings_screen.dart';

enum CatalogSearchCategory { all, artists, albums, songs }

class CatalogSearchScreen extends StatefulWidget {
  const CatalogSearchScreen({super.key});
  static const routeName = '/catalog-search';

  @override
  State<CatalogSearchScreen> createState() => _CatalogSearchScreenState();
}

class _CatalogSearchScreenState extends State<CatalogSearchScreen> {
  final _controller = TextEditingController();
  CatalogSearchResponse? _response;
  String? _error;
  bool _loading = false;
  CatalogSearchCategory _category = CatalogSearchCategory.all;

  Future<void> _search({bool refresh = false}) async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _category = CatalogSearchCategory.all;
    });

    try {
      final client = GetIt.instance<CatalogApiClient>();
      _response = await client.search(query, refresh: refresh);
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Catalog Search'),
      leading: const FinampAppBarBackButton(),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Catalog Settings',
          onPressed: () async {
            final changed = await Navigator.of(context).pushNamed(CatalogSettingsScreen.routeName);
            if (changed == true && _controller.text.trim().isNotEmpty) {
              unawaited(_search());
            }
          },
        ),
      ],
    ),
    bottomNavigationBar: const NowPlayingBar(),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Artists, albums, and tracks',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _response = null);
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => _search(),
                  ),
                ],
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Theme.of(context).colorScheme.onErrorContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Catalog is currently unavailable. Your downloaded and local Jellyfin library remain fully functional.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onErrorContainer.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.settings),
                      label: const Text('Configure Catalog Connection'),
                      onPressed: () async {
                        final changed = await Navigator.of(context).pushNamed(CatalogSettingsScreen.routeName);
                        if (changed == true && _controller.text.trim().isNotEmpty) {
                          unawaited(_search());
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: _buildBodyContent(),
        ),
      ],
    ),
  );

  Widget _buildBodyContent() {
    if (_response == null && !_loading && _error == null) {
      return const Center(
        child: Text(
          'Search MusicBrainz and your Jellyfin library from one catalog.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final results = _response?.results ?? const [];
    if (results.isEmpty && !_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No catalog results found.'),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Fetch live MusicBrainz results'),
              onPressed: () => _search(refresh: true),
            ),
          ],
        ),
      );
    }

    final artists = results.where((r) => r.kind == 'artist').toList();
    final albums = results.where((r) => r.kind == 'album').toList();
    final tracks = results.where((r) => r.kind == 'track').toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              FilterChip(
                label: Text('All (${results.length})'),
                selected: _category == CatalogSearchCategory.all,
                onSelected: (_) => setState(() => _category = CatalogSearchCategory.all),
              ),
              if (artists.isNotEmpty) ...[
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(TablerIcons.user, size: 14),
                  label: Text('Artists (${artists.length})'),
                  selected: _category == CatalogSearchCategory.artists,
                  onSelected: (_) => setState(() => _category = CatalogSearchCategory.artists),
                ),
              ],
              if (albums.isNotEmpty) ...[
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(TablerIcons.disc, size: 14),
                  label: Text('Albums (${albums.length})'),
                  selected: _category == CatalogSearchCategory.albums,
                  onSelected: (_) => setState(() => _category = CatalogSearchCategory.albums),
                ),
              ],
              if (tracks.isNotEmpty) ...[
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(TablerIcons.music, size: 14),
                  label: Text('Songs (${tracks.length})'),
                  selected: _category == CatalogSearchCategory.songs,
                  onSelected: (_) => setState(() => _category = CatalogSearchCategory.songs),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (_category) {
            CatalogSearchCategory.artists => ListView.separated(
                itemCount: artists.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) => _tile(artists[index]),
              ),
            CatalogSearchCategory.albums => ListView.separated(
                itemCount: albums.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) => _tile(albums[index]),
              ),
            CatalogSearchCategory.songs => ListView.separated(
                itemCount: tracks.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) => _tile(tracks[index]),
              ),
            CatalogSearchCategory.all => _buildAllResultsView(
                artists: artists,
                albums: albums,
                tracks: tracks,
              ),
          },
        ),
      ],
    );
  }

  Widget _buildAllResultsView({
    required List<CatalogSearchResult> artists,
    required List<CatalogSearchResult> albums,
    required List<CatalogSearchResult> tracks,
  }) {
    CatalogSearchResult? topResult;
    final queryLower = _controller.text.trim().toLowerCase();

    if (artists.isNotEmpty) {
      topResult = artists.firstWhere(
        (a) => a.title.toLowerCase() == queryLower,
        orElse: () => artists.first,
      );
    } else if (albums.isNotEmpty) {
      topResult = albums.first;
    } else if (tracks.isNotEmpty) {
      topResult = tracks.first;
    }

    final otherArtists = topResult != null && topResult.kind == 'artist'
        ? artists.where((a) => a.id != topResult!.id).toList()
        : artists;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (topResult != null) ...[
          _buildSectionHeader('Top Result', null),
          _buildTopResultCard(topResult),
          const SizedBox(height: 12),
        ],
        if (albums.isNotEmpty) ...[
          _buildSectionHeader(
            'Albums',
            albums.length,
            onSeeAll: () => setState(() => _category = CatalogSearchCategory.albums),
          ),
          ...albums.take(4).map(_tile),
          if (albums.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text('See all ${albums.length} albums'),
                  onPressed: () => setState(() => _category = CatalogSearchCategory.albums),
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (tracks.isNotEmpty) ...[
          _buildSectionHeader(
            'Songs',
            tracks.length,
            onSeeAll: () => setState(() => _category = CatalogSearchCategory.songs),
          ),
          ...tracks.take(5).map(_tile),
          if (tracks.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text('See all ${tracks.length} songs'),
                  onPressed: () => setState(() => _category = CatalogSearchCategory.songs),
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (otherArtists.isNotEmpty) ...[
          _buildSectionHeader(
            'Artists',
            otherArtists.length,
            onSeeAll: () => setState(() => _category = CatalogSearchCategory.artists),
          ),
          ...otherArtists.take(3).map(_tile),
          if (otherArtists.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text('See all ${otherArtists.length} artists'),
                  onPressed: () => setState(() => _category = CatalogSearchCategory.artists),
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildTopResultCard(CatalogSearchResult result) {
    if (result.kind == 'artist') {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).pushNamed(
            CatalogArtistScreen.routeName,
            arguments: CatalogArtistScreenArguments.fromSearchResult(result),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: const Icon(TablerIcons.user, size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Artist',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 28),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).pushNamed(
          CatalogAlbumScreen.routeName,
          arguments: CatalogAlbumScreenArguments.fromSearchResult(result),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: result.imageUrl != null && result.imageUrl!.isNotEmpty
                    ? Image.network(
                        result.imageUrl!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 72,
                          height: 72,
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: const Icon(TablerIcons.disc, size: 36),
                        ),
                      )
                    : Container(
                        width: 72,
                        height: 72,
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: const Icon(TablerIcons.disc, size: 36),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (result.displayArtist != null) result.displayArtist!,
                        'Album',
                        if (result.firstDate != null && result.firstDate!.length >= 4)
                          result.firstDate!.substring(0, 4),
                      ].join(' • '),
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, int? count, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (count != null) ...[
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
          ],
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

  Widget _tile(CatalogSearchResult result) {
    if (result.kind == 'artist') {
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(TablerIcons.user, size: 20),
        ),
        title: Text(result.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Artist'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pushNamed(
          CatalogArtistScreen.routeName,
          arguments: CatalogArtistScreenArguments.fromSearchResult(result),
        ),
      );
    }

    if (result.kind == 'album') {
      final info = [
        if (result.displayArtist != null && result.displayArtist!.isNotEmpty) result.displayArtist!,
        if (result.primaryType != null) result.primaryType,
        if (result.firstDate != null && result.firstDate!.length >= 4) result.firstDate!.substring(0, 4) else if (result.firstDate != null) result.firstDate!,
        if (result.editionIds.isNotEmpty) '${result.editionIds.length} edition(s)',
      ].join(' • ');

      Widget leadingWidget;
      if (result.imageUrl != null && result.imageUrl!.isNotEmpty) {
        leadingWidget = ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            result.imageUrl!,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 44,
              height: 44,
              color: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(TablerIcons.disc, size: 24),
            ),
          ),
        );
      } else {
        leadingWidget = Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(TablerIcons.disc, size: 24),
        );
      }

      Widget trailingWidget;
      if (result.isFullyOwned) {
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
      } else if (result.isPartiallyOwned) {
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

      return ListTile(
        leading: leadingWidget,
        title: Text(result.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(info.isNotEmpty ? info : 'Album concept'),
        trailing: trailingWidget,
        onTap: () => Navigator.of(context).pushNamed(
          CatalogAlbumScreen.routeName,
          arguments: CatalogAlbumScreenArguments.fromSearchResult(result),
        ),
      );
    }

    // track
    final availability = result.availability;
    final canPlay = availability?.canPlay ?? false;
    final isAmbiguous = (availability?.selectionRequired ?? false) ||
        availability?.state == CatalogAvailabilityState.possiblyAvailable;

    String statusText;
    Color statusColor;
    Widget trailingIcon;

    if (canPlay) {
      statusText = 'Available in Jellyfin';
      statusColor = Colors.green;
      trailingIcon = const Icon(Icons.play_circle_fill, color: Colors.green);
    } else if (isAmbiguous) {
      statusText = 'Multiple local versions match';
      statusColor = Colors.orange;
      trailingIcon = const Icon(Icons.call_split, color: Colors.orange);
    } else if (availability?.state == CatalogAvailabilityState.pending) {
      statusText = 'Request pending';
      statusColor = Colors.blue;
      trailingIcon = const Icon(Icons.hourglass_empty, color: Colors.blue);
    } else {
      statusText = 'Not in library';
      statusColor = Colors.grey;
      trailingIcon = const Icon(Icons.cloud_off, color: Colors.grey);
    }

    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(TablerIcons.music, size: 22),
      ),
      title: Text(result.title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (result.displayArtist != null && result.displayArtist!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                result.displayArtist!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    statusText,
                    if (result.formattedDuration.isNotEmpty) result.formattedDuration,
                  ].join(' • '),
                  style: TextStyle(color: statusColor, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: trailingIcon,
      onTap: () => CatalogPlaybackHelper.handleTrackTap(
        context,
        title: result.title,
        availability: availability,
      ),
    );
  }
}
