import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

import '../components/finamp_app_bar_back_button.dart';
import '../components/now_playing_bar.dart';
import '../models/catalog_models.dart';
import '../services/catalog_api_client.dart';
import '../services/catalog_playback_helper.dart';
import 'catalog_artist_screen.dart';

class CatalogAlbumScreenArguments {
  const CatalogAlbumScreenArguments({
    this.releaseGroupId,
    this.releaseId,
    this.initialTitle,
    this.editionIds = const [],
  });

  factory CatalogAlbumScreenArguments.fromSearchResult(CatalogSearchResult result) =>
      CatalogAlbumScreenArguments(
        releaseGroupId: result.kind == 'album' ? result.id : null,
        initialTitle: result.title,
        editionIds: result.editionIds,
      );

  final String? releaseGroupId;
  final String? releaseId;
  final String? initialTitle;
  final List<String> editionIds;
}

class CatalogAlbumScreen extends StatefulWidget {
  const CatalogAlbumScreen({super.key});
  static const routeName = '/catalog/album';

  @override
  State<CatalogAlbumScreen> createState() => _CatalogAlbumScreenState();
}

class _CatalogAlbumScreenState extends State<CatalogAlbumScreen> {
  CatalogAlbumGroup? _albumGroup;
  CatalogRelease? _activeRelease;
  String? _error;
  bool _loading = true;
  bool _requesting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAlbum();
  }

  Future<void> _loadAlbum() async {
    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    CatalogAlbumScreenArguments args;
    if (rawArgs is CatalogAlbumScreenArguments) {
      args = rawArgs;
    } else if (rawArgs is CatalogSearchResult) {
      args = CatalogAlbumScreenArguments.fromSearchResult(rawArgs);
    } else if (rawArgs is String) {
      args = CatalogAlbumScreenArguments(releaseGroupId: rawArgs);
    } else {
      args = const CatalogAlbumScreenArguments();
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final client = GetIt.instance<CatalogApiClient>();

    try {
      if (args.releaseGroupId != null) {
        final group = await client.getAlbumGroup(args.releaseGroupId!);
        _albumGroup = group;
        if (group.editions.isNotEmpty) {
          _activeRelease = group.editions.first;
        } else if (args.editionIds.isNotEmpty) {
          _activeRelease = await client.getRelease(args.editionIds.first);
        }
      } else if (args.releaseId != null) {
        _activeRelease = await client.getRelease(args.releaseId!);
      } else if (args.editionIds.isNotEmpty) {
        _activeRelease = await client.getRelease(args.editionIds.first);
      } else {
        throw Exception('No album or release ID provided.');
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectEdition(CatalogRelease release) async {
    setState(() => _activeRelease = release);
  }

  Future<void> _requestAlbum() async {
    final releaseId = _activeRelease?.id;
    if (releaseId == null) return;

    setState(() => _requesting = true);
    try {
      final client = GetIt.instance<CatalogApiClient>();
      final status = await client.requestAlbum(releaseId);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Album Request Submitted'),
            content: Text(
              status.dispatchEnabled
                  ? 'Request status: ${status.state}.'
                  : 'Request state: "${status.state}".\n\n'
                      'Note: Automatic acquisition dispatch is currently disabled on the server. '
                      'Your request has been queued in the server outbox without initiating an unmonitored download.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit request: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _albumGroup?.title ?? _activeRelease?.title ?? 'Album Details';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: const FinampAppBarBackButton(),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAlbum,
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
              Text(
                'Could not load catalog album.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: _loadAlbum,
              ),
            ],
          ),
        ),
      );
    }

    final release = _activeRelease;
    if (release == null) {
      return const Center(child: Text('No editions found for this album.'));
    }

    final editions = _albumGroup?.editions ?? [release];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // Album Header Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ((release.imageUrl != null && release.imageUrl!.isNotEmpty) ||
                              (_albumGroup?.imageUrl != null && _albumGroup!.imageUrl!.isNotEmpty))
                          ? Image.network(
                              release.imageUrl ?? _albumGroup!.imageUrl!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 80,
                                height: 80,
                                color: Theme.of(context).colorScheme.primaryContainer,
                                child: const Icon(TablerIcons.disc, size: 40),
                              ),
                            )
                          : Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(TablerIcons.disc, size: 40),
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            release.title,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (release.displayArtist != null && release.displayArtist!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                release.displayArtist!,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          if (release.artistCredits.length > 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: release.artistCredits.map((c) => ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(c.name, style: const TextStyle(fontSize: 12)),
                                  onPressed: () => Navigator.of(context).pushNamed(
                                    CatalogArtistScreen.routeName,
                                    arguments: CatalogArtistScreenArguments(artistMbid: c.artistId, initialName: c.name),
                                  ),
                                )).toList(),
                              ),
                            ),
                          if (_albumGroup?.primaryType != null || _albumGroup?.firstDate != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                [
                                  if (_albumGroup?.primaryType != null) _albumGroup!.primaryType,
                                  if (_albumGroup?.firstDate != null) _albumGroup!.firstDate,
                                ].join(' • '),
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                          const SizedBox(height: 8),
                          _buildOwnershipChip(release),
                        ],
                      ),
                    ),
                  ],
                ),
                if (editions.length > 1) ...[
                  const SizedBox(height: 16),
                  const Text('Edition:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: release.id,
                    items: editions.map((ed) {
                      final badge = ed.isFullyOwned
                          ? 'Owned'
                          : ed.isPartiallyOwned
                              ? '${ed.ownedTracks}/${ed.totalTracks} Owned'
                              : 'Not in library';
                      return DropdownMenuItem(
                        value: ed.id,
                        child: Text('${ed.title} ($badge)'),
                      );
                    }).toList(),
                    onChanged: (id) {
                      if (id != null) {
                        final found = editions.firstWhere((e) => e.id == id);
                        _selectEdition(found);
                      }
                    },
                  ),
                ],
                const SizedBox(height: 16),
                if (!release.isFullyOwned)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: _requesting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_shopping_cart),
                      label: Text(
                        release.isPartiallyOwned
                            ? 'Request Missing Tracks (${release.ownedTracks}/${release.totalTracks} owned)'
                            : 'Request Album via Server',
                      ),
                      onPressed: _requesting ? null : _requestAlbum,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Tracks (${release.tracks.length})',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...release.tracks.map((track) => _buildTrackTile(track, release.id)),
      ],
    );
  }

  Widget _buildOwnershipChip(CatalogRelease release) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    if (release.isFullyOwned) {
      bg = Colors.green.withValues(alpha: 0.15);
      fg = Colors.green;
      label = 'Fully Owned (${release.ownedTracks}/${release.totalTracks})';
      icon = Icons.check_circle;
    } else if (release.isPartiallyOwned) {
      bg = Colors.amber.withValues(alpha: 0.15);
      fg = Colors.amber.shade800;
      label = 'Partially Owned (${release.ownedTracks}/${release.totalTracks})';
      icon = Icons.pie_chart;
    } else {
      bg = Colors.grey.withValues(alpha: 0.15);
      fg = Colors.grey;
      label = 'Not in Library (0/${release.totalTracks})';
      icon = Icons.cloud_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackTile(CatalogTrack track, String releaseId) {
    final availability = track.availability;
    final canPlay = availability?.canPlay ?? false;
    final isAmbiguous = availability?.selectionRequired ?? false;

    Widget trailing;
    if (canPlay) {
      trailing = const Icon(Icons.play_circle_fill, color: Colors.green);
    } else if (isAmbiguous) {
      trailing = const Tooltip(
        message: 'Multiple local recordings match; tap to choose',
        child: Icon(Icons.call_split, color: Colors.orange),
      );
    } else {
      trailing = const Tooltip(
        message: 'Not in library',
        child: Icon(Icons.cloud_off, color: Colors.grey),
      );
    }

    return ListTile(
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Text(
          '${track.position}',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(track.title),
      subtitle: Text(
        [
          if (track.displayArtist != null && track.displayArtist!.isNotEmpty) track.displayArtist!,
          if (canPlay) 'Available' else if (isAmbiguous) 'Choose version' else 'Not in library',
          if (track.formattedDuration.isNotEmpty) track.formattedDuration,
        ].join(' • '),
      ),
      trailing: trailing,
      onTap: () => CatalogPlaybackHelper.handleTrackTap(
        context,
        title: track.title,
        availability: availability,
        albumEditionId: releaseId,
        onRequestAlbum: _requestAlbum,
      ),
    );
  }
}
