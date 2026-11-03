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

  Future<void> _search({bool refresh = false}) async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
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
          child: _response == null && !_loading && _error == null
              ? const Center(
                  child: Text(
                    'Search MusicBrainz and your Jellyfin library from one catalog.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : _response != null && _response!.results.isEmpty
                  ? Center(
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
                    )
                  : ListView.separated(
                      itemCount: _response?.results.length ?? 0,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) => _tile(_response!.results[index]),
                    ),
        ),
      ],
    ),
  );

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
        if (result.firstDate != null) result.firstDate,
        if (result.editionIds.isNotEmpty) '${result.editionIds.length} edition(s)',
      ].join(' • ');

      return ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(TablerIcons.disc, size: 24),
        ),
        title: Text(result.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(info.isNotEmpty ? info : 'Album concept'),
        trailing: const Icon(Icons.chevron_right),
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
