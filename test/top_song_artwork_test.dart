import 'package:finamp/models/catalog_models.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/services/top_song_artwork.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses playable track album when artwork id and inherited tags are absent', () async {
    final track = CatalogSearchResult(
      id: 'song',
      kind: 'track',
      title: 'Kick Stones (The Boys)',
      availability: CatalogAvailability(
        state: CatalogAvailabilityState.available,
        candidateCount: 1,
        playableItemId: 'track',
      ),
    );
    final items = {
      'track': BaseItemDto(id: const BaseItemId('track'), albumId: const BaseItemId('album')),
      'album': BaseItemDto(id: const BaseItemId('album'), imageTags: {'Primary': 'cover'}),
    };
    expect(await resolveTopSongArtwork(track, loadItem: (id) async => items[id]!, imageUrl: (item) => item.imageId), [
      'album',
    ]);
  });

  test('keeps all valid candidates in edition order despite a stale representative', () async {
    final track = CatalogSearchResult(
      id: 'song',
      kind: 'track',
      title: 'Beatles song',
      artworkItemId: 'stale',
      availability: CatalogAvailability(
        state: CatalogAvailabilityState.available,
        candidateCount: 4,
        selectionRequired: true,
        localItems: [
          'bare',
          'compilation',
          'remaster',
          'studio',
        ].map((id) => CatalogLocalItem(serverId: 'server', itemId: id)).toList(),
      ),
    );
    final items = {
      'bare': BaseItemDto(id: const BaseItemId('bare'), album: 'Album'),
      'compilation': BaseItemDto(id: const BaseItemId('compilation'), album: '1967–1970', imageTags: {'Primary': 'c'}),
      'remaster': BaseItemDto(
        id: const BaseItemId('remaster'),
        album: 'Album (Remastered)',
        imageTags: {'Primary': 'r'},
      ),
      'studio': BaseItemDto(id: const BaseItemId('studio'), album: 'Album', imageTags: {'Primary': 's'}),
    };
    expect(
      await resolveTopSongArtwork(
        track,
        albums: const [
          CatalogSearchResult(
            id: 'comp',
            kind: 'album',
            title: '1967–1970',
            primaryType: 'Album',
            secondaryTypes: ['Compilation'],
          ),
        ],
        loadItem: (id) async => items[id]!,
        imageUrl: (item) => item.imageId,
      ),
      ['studio', 'remaster', 'compilation'],
    );
    expect(track.availability!.selectionRequired, isTrue);
    expect(track.availability!.playableItemId, isNull);
  });
}
