import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/services/artist_resolution_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Artist Navigation ID Resolution Regression Tests', () {
    test('resolves genuine artist when artistItems provides valid ID', () {
      final target = ArtistResolutionHelper.resolveGenuineArtist(
        artistItems: [
          NameIdPair(id: BaseItemId('artist-uuid-5678'), name: 'Real Artist'),
        ],
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('artist-uuid-5678'));
      expect(target.name, equals('Real Artist'));
    });

    test('resolves genuine artist from albumArtists when artistItems is null', () {
      final target = ArtistResolutionHelper.resolveGenuineArtist(
        artistItems: null,
        albumArtists: [
          NameIdPair(id: BaseItemId('album-artist-uuid-9999'), name: 'Album Artist'),
        ],
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('album-artist-uuid-9999'));
      expect(target.name, equals('Album Artist'));
    });

    test('falls back to albumArtists when artistItems is an empty list', () {
      final target = ArtistResolutionHelper.resolveGenuineArtist(
        artistItems: [],
        albumArtists: [
          NameIdPair(id: BaseItemId('album-artist-uuid-1111'), name: 'Fallback Album Artist'),
        ],
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('album-artist-uuid-1111'));
      expect(target.name, equals('Fallback Album Artist'));
    });

    test('falls back to albumArtists when artistItems has only empty or whitespace IDs', () {
      final target = ArtistResolutionHelper.resolveGenuineArtist(
        artistItems: [
          NameIdPair(id: BaseItemId('   '), name: 'Empty ID Artist'),
          NameIdPair(id: BaseItemId(''), name: 'Blank Artist'),
        ],
        albumArtists: [
          NameIdPair(id: BaseItemId('album-artist-uuid-2222'), name: 'Valid Album Artist'),
        ],
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('album-artist-uuid-2222'));
      expect(target.name, equals('Valid Album Artist'));
    });

    test('returns null when all artistItems and albumArtists IDs are empty', () {
      final target = ArtistResolutionHelper.resolveGenuineArtist(
        artistItems: [
          NameIdPair(id: BaseItemId(''), name: 'Blank'),
        ],
        albumArtists: [
          NameIdPair(id: BaseItemId('  '), name: 'Whitespace'),
        ],
      );

      expect(target, isNull);
    });

    test('returns null when artistItems and albumArtists are both null or empty', () {
      expect(ArtistResolutionHelper.resolveGenuineArtist(), isNull);
      expect(
        ArtistResolutionHelper.resolveGenuineArtist(artistItems: [], albumArtists: []),
        isNull,
      );
    });

    test('resolveArtistNavigationTarget resolves valid target from track artistItems', () {
      final track = BaseItemDto(
        id: BaseItemId('track-uuid-1234'),
        name: 'Track Title',
        type: 'Audio',
        artistItems: [
          NameIdPair(id: BaseItemId('artist-uuid-5678'), name: 'Real Artist'),
        ],
      );

      final target = ArtistResolutionHelper.resolveArtistNavigationTarget(
        track: track,
        fallbackArtistName: 'Real Artist',
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('artist-uuid-5678'));
      expect(target.id.raw, isNot(equals('track-uuid-1234')));
      expect(target.name, equals('Real Artist'));
      expect(target.type, equals('MusicArtist'));
    });

    test('resolveArtistNavigationTarget falls back to albumArtists when artistItems is an empty list', () {
      // Direct regression test for empty-list vs albumArtists fallback:
      // A naive `(track.artistItems ?? track.albumArtists)` evaluates to `[]` when artistItems is `[]`,
      // completely missing albumArtists. ArtistResolutionHelper correctly checks and falls back.
      final track = BaseItemDto(
        id: BaseItemId('track-uuid-1234'),
        name: 'Track Title',
        type: 'Audio',
        artistItems: [],
        albumArtists: [
          NameIdPair(id: BaseItemId('album-artist-uuid-3333'), name: 'Album Artist 3333'),
        ],
      );

      final target = ArtistResolutionHelper.resolveArtistNavigationTarget(
        track: track,
        fallbackArtistName: 'Album Artist 3333',
      );

      expect(target, isNotNull);
      expect(target!.id.raw, equals('album-artist-uuid-3333'));
      expect(target.id.raw, isNot(equals('track-uuid-1234')));
      expect(target.name, equals('Album Artist 3333'));
      expect(target.type, equals('MusicArtist'));
    });

    test('resolveArtistNavigationTarget refuses to fabricate artist target with track ID', () {
      final track = BaseItemDto(
        id: BaseItemId('track-uuid-1234'),
        name: 'Track Title',
        type: 'Audio',
        artists: ['String-Only Artist'],
        artistItems: [],
        albumArtists: [
          NameIdPair(id: BaseItemId('   '), name: 'Whitespace ID'),
        ],
      );

      final target = ArtistResolutionHelper.resolveArtistNavigationTarget(
        track: track,
        fallbackArtistName: 'String-Only Artist',
      );

      expect(target, isNull);
    });
  });
}
