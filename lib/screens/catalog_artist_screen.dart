import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

import '../components/finamp_app_bar_back_button.dart';
import '../components/now_playing_bar.dart';
import '../models/catalog_models.dart';
import '../services/catalog_api_client.dart';
import '../services/catalog_playback_helper.dart';
import 'catalog_album_screen.dart';

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
                        '${artist.albums.length} releases • ${artist.recordings.length} recordings',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (artist.albums.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Albums & Releases',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...artist.albums.map((album) => ListTile(
                leading: const Icon(TablerIcons.disc),
                title: Text(album.title),
                subtitle: Text(
                  [
                    if (album.primaryType != null) album.primaryType,
                    if (album.firstDate != null) album.firstDate,
                  ].join(' • '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pushNamed(
                  CatalogAlbumScreen.routeName,
                  arguments: CatalogAlbumScreenArguments.fromSearchResult(album),
                ),
              )),
        ],
        if (artist.recordings.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Recordings',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...artist.recordings.map((rec) => ListTile(
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
        ],
      ],
    );
  }
}
