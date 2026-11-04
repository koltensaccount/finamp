import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/catalog_models.dart';
import 'catalog_credential_store.dart';

class CatalogUnavailableException implements Exception {
  const CatalogUnavailableException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CatalogApiClient {
  CatalogApiClient({required CatalogCredentialStore credentials, http.Client? client})
    : _credentials = credentials,
      _client = client ?? http.Client();

  final CatalogCredentialStore _credentials;
  final http.Client _client;

  Future<CatalogSearchResponse> search(String query, {bool refresh = false}) async {
    final response = await _get('/v1/search', {'q': query, if (refresh) 'refresh': 'true'});
    return CatalogSearchResponse.fromJson(_jsonObject(response));
  }

  Future<CatalogAvailability> availability(String recordingId) async {
    final response = await _get('/v1/recordings/$recordingId/availability');
    return CatalogAvailability.fromJson(_jsonObject(response));
  }

  Future<Map<String, dynamic>?> resolveArtist({String? itemId, String? name}) async {
    final query = <String, String>{};
    if (itemId != null && itemId.isNotEmpty) query['item_id'] = itemId;
    if (name != null && name.isNotEmpty) query['name'] = name;
    if (query.isEmpty) return null;
    try {
      final response = await _get('/v1/artists/resolve', query);
      return _jsonObject(response);
    } catch (_) {
      return null;
    }
  }

  Future<CatalogArtist> getArtist(String artistMbid) async {
    final response = await _get('/v1/artists/$artistMbid');
    return CatalogArtist.fromJson(_jsonObject(response));
  }

  Future<CatalogAlbumGroup> getAlbumGroup(String releaseGroupMbid) async {
    final response = await _get('/v1/albums/$releaseGroupMbid');
    return CatalogAlbumGroup.fromJson(_jsonObject(response));
  }

  Future<CatalogRelease> getRelease(String releaseMbid) async {
    final response = await _get('/v1/releases/$releaseMbid');
    return CatalogRelease.fromJson(_jsonObject(response));
  }

  Future<CatalogRequestDetail?> getRequest(int requestId) async {
    final response = await _get('/v1/requests/$requestId');
    return CatalogRequestDetail.fromJson(_jsonObject(response));
  }

  Future<CatalogRequestStatus> requestAlbum(String releaseId) async {
    final credentials = await _requireCredentials();
    final uri = credentials.endpoint.resolve('/v1/requests');
    final response = await _client
        .post(
          uri,
          headers: {'Authorization': 'Bearer ${credentials.token}', 'Content-Type': 'application/json'},
          body: jsonEncode({'release_id': releaseId, 'scope': 'album'}),
        )
        .timeout(const Duration(seconds: 10));
    _requireSuccess(response);
    return CatalogRequestStatus.fromJson(_jsonObject(response));
  }

  Future<http.Response> _get(String path, [Map<String, String> query = const {}]) async {
    final credentials = await _requireCredentials();
    final uri = credentials.endpoint.resolve(path).replace(queryParameters: query);
    final response = await _client
        .get(uri, headers: {'Authorization': 'Bearer ${credentials.token}'})
        .timeout(const Duration(seconds: 10));
    _requireSuccess(response);
    return response;
  }

  Future<CatalogCredentials> _requireCredentials() async {
    final credentials = await _credentials.read();
    if (credentials == null) {
      throw const CatalogUnavailableException('Catalog connection is not configured.');
    }
    return credentials;
  }

  static Map<String, dynamic> _jsonObject(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const CatalogUnavailableException('Catalog returned an invalid response.');
    }
    return decoded;
  }

  static void _requireSuccess(http.Response response) {
    if (response.statusCode == 401) throw const CatalogUnavailableException('Catalog authentication failed.');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CatalogUnavailableException('Catalog is unavailable (HTTP ${response.statusCode}).');
    }
  }
}
