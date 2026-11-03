import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';

import '../models/catalog_models.dart';
import '../models/finamp_models.dart';
import '../models/jellyfin_models.dart';
import 'jellyfin_api_helper.dart';
import 'queue_service.dart';

class CatalogPlaybackHelper {
  static Future<void> playConfidentItem(
    BuildContext context, {
    required String playableItemId,
    required String title,
  }) async {
    try {
      final jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
      final queueService = GetIt.instance<QueueService>();

      final item = await jellyfinApiHelper.getItemById(BaseItemId(playableItemId));
      await queueService.startPlayback(
        items: [item],
        source: QueueItemSource.fromBaseItem(item),
        order: FinampPlaybackOrder.linear,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.play_circle_filled, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(child: Text('Now playing: $title')),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback failed: $e')),
        );
      }
    }
  }

  static Future<void> handleTrackTap(
    BuildContext context, {
    required String title,
    required CatalogAvailability? availability,
    String? albumEditionId,
    VoidCallback? onRequestAlbum,
  }) async {
    if (availability == null) {
      await _showUnsupportedNotice(context, title, onRequestAlbum);
      return;
    }

    if (availability.canPlay) {
      await playConfidentItem(
        context,
        playableItemId: availability.playableItemId!,
        title: title,
      );
      return;
    }

    if (availability.selectionRequired || availability.state == CatalogAvailabilityState.possiblyAvailable) {
      await _showAmbiguousSelectionModal(context, title, availability.localItems);
      return;
    }

    // notFound
    await _showUnsupportedNotice(context, title, onRequestAlbum);
  }

  static Future<void> _showUnsupportedNotice(
    BuildContext context,
    String title,
    VoidCallback? onRequestAlbum,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Track Unavailable'),
        content: Text(
          '"$title" is not in your Jellyfin library.\n\n'
          'Single-track acquisition is not supported by the backend to prevent mismatched tracks. '
          'You can request the complete album instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (onRequestAlbum != null)
            FilledButton.icon(
              icon: const Icon(TablerIcons.disc),
              label: const Text('Request Album'),
              onPressed: () {
                Navigator.of(context).pop();
                onRequestAlbum();
              },
            ),
        ],
      ),
    );
  }

  static Future<void> _showAmbiguousSelectionModal(
    BuildContext context,
    String title,
    List<CatalogLocalItem> localItems,
  ) async {
    if (localItems.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ambiguous Match'),
          content: Text(
            'Multiple candidates or ambiguous metadata were found for "$title", '
            'but no local files could be resolved. To avoid playing an incorrect recording, '
            'automatic playback is disabled.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Fetch details for each local candidate item from Jellyfin
    final jellyfinApiHelper = GetIt.instance<JellyfinApiHelper>();
    final candidates = <BaseItemDto>[];

    for (final loc in localItems) {
      try {
        final item = await jellyfinApiHelper.getItemById(BaseItemId(loc.itemId));
        candidates.add(item);
      } catch (_) {
        // Skip unresolvable candidates
      }
    }

    if (!context.mounted) return;

    if (candidates.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ambiguous Match'),
          content: Text(
            'Multiple local candidates exist for "$title", but details could not be loaded from your server. '
            'Playback was prevented to avoid playing the wrong version.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Choose Local Version for "$title"',
                  style: Theme.of(bottomSheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'Multiple recordings match this catalog identity. Select which version to play:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const Divider(),
              ...candidates.map((item) {
                final album = item.album ?? 'Unknown Album';
                final artist = item.artists?.join(', ') ?? item.albumArtist ?? '';
                final container = item.container ?? '';
                return ListTile(
                  leading: const Icon(TablerIcons.music),
                  title: Text(item.name ?? title),
                  subtitle: Text('$artist • $album${container.isNotEmpty ? " ($container)" : ""}'),
                  trailing: const Icon(Icons.play_arrow),
                  onTap: () async {
                    Navigator.of(bottomSheetContext).pop();
                    await playConfidentItem(
                      context,
                      playableItemId: item.id.raw,
                      title: item.name ?? title,
                    );
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
