import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/services/artist_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ArtistIdentityService Tests', () {
    test('strictly distinguishes MusicBrainz MBIDs from Jellyfin IDs', () {
      const mbId = '59db3d82-86ea-451f-881f-dffc8ec387c9';
      const jfId = '3abb1a64b01694b0df1411d4f6ee051e';
      const beatlesMbId = 'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d';
      const beatlesJfId = '53912e3d80ecb47934b66105c8b092c6';

      expect(ArtistIdentityService.isMbid(mbId), isTrue);
      expect(ArtistIdentityService.isMbid(beatlesMbId), isTrue);

      // Jellyfin IDs must NEVER match MBID regex
      expect(ArtistIdentityService.isMbid(jfId), isFalse);
      expect(ArtistIdentityService.isMbid(beatlesJfId), isFalse);
      expect(ArtistIdentityService.isMbid(''), isFalse);
      expect(ArtistIdentityService.isMbid('not-a-uuid'), isFalse);
      expect(ArtistIdentityService.isMbid(null), isFalse);
    });

    test('resolves MBID directly from item providerIds', () async {
      final item = BaseItemDto(
        id: const BaseItemId('3abb1a64b01694b0df1411d4f6ee051e'),
        name: 'Metro Boomin',
        type: 'MusicArtist',
        providerIds: {
          'MusicBrainzArtist': '59db3d82-86ea-451f-881f-dffc8ec387c9',
        },
      );

      final resolved = await ArtistIdentityService.resolveArtistMbid(artistItem: item);
      expect(resolved, equals('59db3d82-86ea-451f-881f-dffc8ec387c9'));
    });

    test('records and retrieves cached mappings', () async {
      const jfId = 'custom-jf-id-12345';
      const mbId = 'e0c97a4d-c392-41a9-a374-57af3e3eeab3';

      ArtistIdentityService.recordMapping(
        jellyfinId: jfId,
        name: 'Custom Artist',
        mbid: mbId,
      );

      final resolvedById = await ArtistIdentityService.resolveArtistMbid(jellyfinId: jfId);
      expect(resolvedById, equals(mbId));

      final resolvedByName = await ArtistIdentityService.resolveArtistMbid(name: 'custom artist');
      expect(resolvedByName, equals(mbId));
    });

    test('returns null when offline if not cached', () async {
      try {
        ArtistIdentityService.mockIsOffline = true;

        final item = BaseItemDto(
          id: const BaseItemId('uncached-offline-artist-id'),
          name: 'Uncached Offline Artist',
          type: 'MusicArtist',
        );

        final resolved = await ArtistIdentityService.resolveArtistMbid(artistItem: item);
        expect(resolved, isNull);
      } finally {
        ArtistIdentityService.mockIsOffline = null;
      }
    });

    test('does not record mapping for ambiguous artist names', () async {
      // Ensure SharedPreferences is empty
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);

      // Verify that recordMapping ignores invalid MBIDs
      ArtistIdentityService.recordMapping(
        jellyfinId: 'test-jf-id',
        name: 'Ambiguous Artist',
        mbid: 'not-a-valid-mbid',
      );
      expect(prefs.getKeys(), isEmpty);
    });

    test('init purges known poisoned mappings for Steve Lacy (jazz) and "The Mamas"', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('artist_mbid_by_jf:jf-steve-lacy', 'ca9766a0-1c30-43e6-a213-bac1334efc4a');
      await prefs.setString('artist_mbid_by_name:steve lacy', 'ca9766a0-1c30-43e6-a213-bac1334efc4a');
      await prefs.setString('artist_mbid_by_name:the mamas', 'ff294730-0315-440d-a543-54005779c15b');
      await prefs.setString('artist_mbid_by_name:the mamas & the papas', 'ff294730-0315-440d-a543-54005779c15b');

      ArtistIdentityService.resetForTesting();
      await ArtistIdentityService.init();

      // Poisoned keys must be removed from prefs
      expect(prefs.containsKey('artist_mbid_by_jf:jf-steve-lacy'), isFalse);
      expect(prefs.containsKey('artist_mbid_by_name:steve lacy'), isFalse);
      expect(prefs.containsKey('artist_mbid_by_name:the mamas'), isFalse);

      // Canonical valid key must remain intact
      expect(prefs.containsKey('artist_mbid_by_name:the mamas & the papas'), isTrue);
      expect(prefs.getString('artist_mbid_by_name:the mamas & the papas'), equals('ff294730-0315-440d-a543-54005779c15b'));

      // Resolving "The Mamas & the Papas" returns the canonical MBID
      final resolvedMamas = await ArtistIdentityService.resolveArtistMbid(name: 'The Mamas & the Papas');
      expect(resolvedMamas, equals('ff294730-0315-440d-a543-54005779c15b'));

      // Resolving poisoned "The Mamas" returns null
      final resolvedPoison = await ArtistIdentityService.resolveArtistMbid(name: 'the mamas');
      expect(resolvedPoison, isNull);
    });
  });
}
