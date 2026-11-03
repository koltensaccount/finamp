import 'dart:convert';

import 'package:finamp/models/catalog_models.dart';
import 'package:finamp/services/catalog_api_client.dart';
import 'package:finamp/services/catalog_credential_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('plays only a single confidently mapped recording', () {
    final available = CatalogAvailability.fromJson({
      'state': 'available',
      'candidate_count': 1,
      'playable_item_id': 'jellyfin-item',
      'selection_required': false,
      'local_items': [
        {'server_id': 'srv1', 'item_id': 'jellyfin-item'},
      ],
    });
    final ambiguous = CatalogAvailability.fromJson({
      'state': 'possibly_available',
      'candidate_count': 2,
      'selection_required': true,
      'local_items': [
        {'server_id': 'srv1', 'item_id': 'item-1'},
        {'server_id': 'srv1', 'item_id': 'item-2'},
      ],
    });
    final missing = CatalogAvailability.fromJson({
      'state': 'not_found',
      'candidate_count': 0,
      'playable_item_id': null,
      'selection_required': false,
    });

    expect(available.canPlay, isTrue);
    expect(available.localItems.length, 1);
    expect(available.localItems.first.itemId, 'jellyfin-item');

    expect(ambiguous.canPlay, isFalse);
    expect(ambiguous.selectionRequired, isTrue);
    expect(ambiguous.localItems.length, 2);

    expect(missing.canPlay, isFalse);
    expect(missing.localItems, isEmpty);
  });

  test('uses bearer authentication and parses unified search results', () async {
    final client = CatalogApiClient(
      credentials: _Credentials(),
      client: _Client((request) async {
        expect(request.headers['authorization'], 'Bearer scoped-token');
        expect(request.url.path, '/v1/search');
        expect(request.url.queryParameters['q'], 'song');
        return http.Response(
          jsonEncode({
            'cached': true,
            'results': [
              {
                'id': 'recording-id',
                'kind': 'track',
                'title': 'Song',
                'availability': {'state': 'available', 'candidate_count': 1, 'playable_item_id': 'local-item'},
              },
            ],
          }),
          200,
        );
      }),
    );

    final response = await client.search('song');
    expect(response.cached, isTrue);
    expect(response.results.single.availability?.playableItemId, 'local-item');
  });

  test('keeps disabled acquisition dispatch visible in the request response', () async {
    final client = CatalogApiClient(
      credentials: _Credentials(),
      client: _Client((request) async {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body)['scope'], 'album');
        return http.Response(jsonEncode({'id': 3, 'state': 'queued', 'dispatch_enabled': false}), 200);
      }),
    );

    final status = await client.requestAlbum('release-id');
    expect(status.state, 'queued');
    expect(status.dispatchEnabled, isFalse);
  });

  test('fetches and parses album group and release details', () async {
    final client = CatalogApiClient(
      credentials: _Credentials(),
      client: _Client((request) async {
        if (request.url.path == '/v1/albums/group-123') {
          return http.Response(
            jsonEncode({
              'id': 'group-123',
              'title': 'Test Album',
              'primary_type': 'Album',
              'first_date': '2024-01-01',
              'editions': [
                {
                  'id': 'release-abc',
                  'group_id': 'group-123',
                  'title': 'Test Album (Deluxe)',
                  'tracks': [
                    {
                      'id': 'track-1',
                      'release_id': 'release-abc',
                      'recording_id': 'rec-1',
                      'disc': 1,
                      'position': 1,
                      'title': 'Track One',
                      'duration_ms': 180000,
                      'availability': {
                        'state': 'available',
                        'candidate_count': 1,
                        'playable_item_id': 'jf-item-1',
                      },
                    },
                    {
                      'id': 'track-2',
                      'release_id': 'release-abc',
                      'recording_id': 'rec-2',
                      'disc': 1,
                      'position': 2,
                      'title': 'Track Two',
                      'duration_ms': 200000,
                      'availability': {
                        'state': 'not_found',
                        'candidate_count': 0,
                      },
                    },
                  ],
                  'owned_tracks': 1,
                  'total_tracks': 2,
                  'ownership': 'partial',
                },
              ],
            }),
            200,
          );
        } else if (request.url.path == '/v1/releases/release-abc') {
          return http.Response(
            jsonEncode({
              'id': 'release-abc',
              'group_id': 'group-123',
              'title': 'Test Album (Deluxe)',
              'tracks': <Map<String, dynamic>>[],
              'owned_tracks': 0,
              'total_tracks': 0,
              'ownership': 'none',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      }),
    );

    final albumGroup = await client.getAlbumGroup('group-123');
    expect(albumGroup.title, 'Test Album');
    expect(albumGroup.editions.length, 1);
    expect(albumGroup.editions.first.isPartiallyOwned, isTrue);
    expect(albumGroup.editions.first.tracks.length, 2);
    expect(albumGroup.editions.first.tracks.first.formattedDuration, '3:00');
    expect(albumGroup.editions.first.tracks.first.availability?.canPlay, isTrue);
    expect(albumGroup.editions.first.tracks.last.availability?.canPlay, isFalse);

    final release = await client.getRelease('release-abc');
    expect(release.title, 'Test Album (Deluxe)');
    expect(release.isNoneOwned, isTrue);
  });

  test('fetches artist details with albums and recordings', () async {
    final client = CatalogApiClient(
      credentials: _Credentials(),
      client: _Client((request) async {
        expect(request.url.path, '/v1/artists/artist-mbid-1');
        return http.Response(
          jsonEncode({
            'id': 'artist-mbid-1',
            'name': 'Test Artist',
            'albums': [
              {
                'id': 'rg-1',
                'title': 'Debut',
                'primary_type': 'Album',
                'first_date': '2020-05-10',
              },
            ],
            'recordings': [
              {
                'id': 'rec-1',
                'title': 'Hit Song',
                'duration_ms': 210000,
              },
            ],
          }),
          200,
        );
      }),
    );

    final artist = await client.getArtist('artist-mbid-1');
    expect(artist.name, 'Test Artist');
    expect(artist.albums.length, 1);
    expect(artist.albums.first.title, 'Debut');
    expect(artist.recordings.length, 1);
    expect(artist.recordings.first.title, 'Hit Song');
  });

  test('fetches request status by id', () async {
    final client = CatalogApiClient(
      credentials: _Credentials(),
      client: _Client((request) async {
        expect(request.url.path, '/v1/requests/42');
        return http.Response(
          jsonEncode({
            'id': 42,
            'release_id': 'rel-42',
            'scope': 'album',
            'state': 'queued',
            'origin': 'explicit_user',
            'created_at': 1700000000.0,
          }),
          200,
        );
      }),
    );

    final req = await client.getRequest(42);
    expect(req, isNotNull);
    expect(req!.id, 42);
    expect(req.releaseId, 'rel-42');
    expect(req.state, 'queued');
  });

  test('parses structured artist_credit and display_artist', () {
    final result = CatalogSearchResult.fromJson({
      'id': 'rec-1',
      'kind': 'track',
      'title': "It's Crazy",
      'display_artist': 'A Boogie Wit da Hoodie feat. Melody',
      'artist_credit': [
        {'artist_id': 'artist-1', 'name': 'A Boogie Wit da Hoodie', 'joinphrase': ' feat. '},
        {'artist_id': 'artist-2', 'name': 'Melody', 'joinphrase': ''},
      ],
    });
    expect(result.displayArtist, 'A Boogie Wit da Hoodie feat. Melody');
    expect(result.artistCredits.length, 2);
    expect(result.artistCredits[0].artistId, 'artist-1');
    expect(result.artistCredits[0].name, 'A Boogie Wit da Hoodie');
    expect(result.artistCredits[0].joinphrase, ' feat. ');
    expect(result.artistCredits[1].artistId, 'artist-2');
    expect(result.artistCredits[1].name, 'Melody');
  });
}

class _Credentials implements CatalogCredentialStore {
  @override
  Future<void> clear() async {}

  @override
  Future<CatalogCredentials?> read() async =>
      CatalogCredentials(endpoint: Uri.parse('https://catalog.example/'), token: 'scoped-token');

  @override
  Future<void> save(CatalogCredentials credentials) async {}
}

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request as http.Request);
    return http.StreamedResponse(Stream.value(response.bodyBytes), response.statusCode, headers: response.headers);
  }
}
