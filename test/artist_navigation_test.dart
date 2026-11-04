import 'package:finamp/models/jellyfin_models.dart';
import 'package:flutter_test/flutter_test.dart';

BaseItemDto? resolveArtistNavigationTarget({
  required BaseItemDto track,
  required String fallbackArtistName,
}) {
  final artistItem = (track.artistItems ?? track.albumArtists)?.firstOrNull;
  final genuineArtistId = artistItem?.id;
  final hasGenuineArtist = genuineArtistId != null && genuineArtistId.raw.isNotEmpty;

  if (hasGenuineArtist) {
    return BaseItemDto(
      id: genuineArtistId,
      name: artistItem?.name ?? fallbackArtistName,
      type: "MusicArtist",
    );
  }
  // Never fabricate an artist target with track's ID!
  return null;
}

void main() {
  group('Artist Navigation ID Resolution Regression Tests', () {
    test('resolves genuine artist when artistItems provides valid ID', () {
      final track = BaseItemDto(
        id: BaseItemId('track-uuid-1234'),
        name: 'Track Title',
        type: 'Audio',
        artistItems: [
          NameIdPair(id: BaseItemId('artist-uuid-5678'), name: 'Real Artist'),
        ],
      );

      final target = resolveArtistNavigationTarget(
        track: track,
        fallbackArtistName: 'Real Artist',
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('artist-uuid-5678'));
      expect(target.id.raw, isNot(equals('track-uuid-1234')));
      expect(target.name, equals('Real Artist'));
      expect(target.type, equals('MusicArtist'));
    });

    test('resolves genuine artist from albumArtists when artistItems is null', () {
      final track = BaseItemDto(
        id: BaseItemId('track-uuid-1234'),
        name: 'Track Title',
        type: 'Audio',
        artistItems: null,
        albumArtists: [
          NameIdPair(id: BaseItemId('album-artist-uuid-9999'), name: 'Album Artist'),
        ],
      );

      final target = resolveArtistNavigationTarget(
        track: track,
        fallbackArtistName: 'Album Artist',
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('album-artist-uuid-9999'));
      expect(target.id.raw, isNot(equals('track-uuid-1234')));
      expect(target.name, equals('Album Artist'));
    });

    test('refuses to fabricate artist target when artist has empty ID', () {
      final track = BaseItemDto(
        id: BaseItemId('track-uuid-1234'),
        name: 'Track Title',
        type: 'Audio',
        artistItems: [
          NameIdPair(id: BaseItemId(''), name: 'Blank ID Artist'),
        ],
      );

      final target = resolveArtistNavigationTarget(
        track: track,
        fallbackArtistName: 'Blank ID Artist',
      );

      // Must be null (safe fallback to search or non-interactive, never track ID)
      expect(target, isNull);
    });

    test('refuses to fabricate artist target when artistItems and albumArtists are missing', () {
      final track = BaseItemDto(
        id: BaseItemId('track-uuid-1234'),
        name: 'Track Title',
        type: 'Audio',
        artists: ['String-Only Artist'],
        artistItems: null,
        albumArtists: null,
      );

      final target = resolveArtistNavigationTarget(
        track: track,
        fallbackArtistName: 'String-Only Artist',
      );

      expect(target, isNull);
    });
  });
}
