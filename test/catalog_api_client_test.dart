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
    });
    final ambiguous = CatalogAvailability.fromJson({
      'state': 'possibly_available',
      'candidate_count': 2,
      'selection_required': true,
    });

    expect(available.canPlay, isTrue);
    expect(ambiguous.canPlay, isFalse);
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
