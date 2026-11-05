import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/book_models.dart';
import 'catalog_credential_store.dart';

class BooksNotConfiguredException implements Exception {
  const BooksNotConfiguredException([this.message = 'Books backend credentials not configured or disabled']);
  final String message;

  @override
  String toString() => 'Exception: $message';
}

class BooksApiClient {
  BooksApiClient({required CatalogCredentialStore credentials, http.Client? client})
    : _credentials = credentials,
      _client = client ?? http.Client();

  final CatalogCredentialStore _credentials;
  final http.Client _client;

  String? _resolveUrl(String? rawUrl, Uri endpoint) {
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final parsed = Uri.tryParse(rawUrl);
    if (parsed == null) return rawUrl;
    if (!parsed.hasScheme || parsed.host == '127.0.0.1' || parsed.host == 'localhost') {
      return endpoint.resolve(parsed.path + (parsed.hasQuery ? '?${parsed.query}' : '')).toString();
    }
    return rawUrl;
  }

  Future<Uri> _buildUri(String path, [Map<String, String>? queryParams]) async {
    final creds = await _credentials.read();
    if (creds == null) {
      throw const BooksNotConfiguredException();
    }
    return creds.endpoint.replace(path: path, queryParameters: queryParams);
  }

  Future<Map<String, String>> _authHeaders({bool jsonBody = false}) async {
    final creds = await _credentials.read();
    final headers = <String, String>{};
    if (creds != null && creds.token.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${creds.token}';
    }
    if (jsonBody) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  Future<List<BookSummary>> getBooks({String? query, String? formatFilter}) async {
    final queryParams = <String, String>{};
    if (query != null && query.trim().isNotEmpty) {
      queryParams['q'] = query.trim();
    }
    if (formatFilter != null && formatFilter.isNotEmpty) {
      queryParams['format'] = formatFilter;
    }

    final uri = await _buildUri('/v1/books', queryParams.isEmpty ? null : queryParams);
    final headers = await _authHeaders();
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Failed to load books: ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = data['books'] as List? ?? [];
    return list.map((e) {
      final map = Map<String, dynamic>.from(e as Map<String, dynamic>);
      if (map['cover_url'] is String) {
        map['cover_url'] = _resolveUrl(map['cover_url'] as String, uri);
      }
      return BookSummary.fromJson(map);
    }).toList();
  }

  Future<BookDetail> getBook(String workId) async {
    final uri = await _buildUri('/v1/books/$workId');
    final headers = await _authHeaders();
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Failed to load book $workId: ${resp.statusCode}');
    }

    final data = Map<String, dynamic>.from(jsonDecode(resp.body) as Map<String, dynamic>);
    if (data['cover_url'] is String) {
      data['cover_url'] = _resolveUrl(data['cover_url'] as String, uri);
    }
    if (data['editions'] is List) {
      data['editions'] = (data['editions'] as List).map((ed) {
        final edMap = Map<String, dynamic>.from(ed as Map<String, dynamic>);
        if (edMap['cover_url'] is String) {
          edMap['cover_url'] = _resolveUrl(edMap['cover_url'] as String, uri);
        }
        if (edMap['download_url'] is String) {
          edMap['download_url'] = _resolveUrl(edMap['download_url'] as String, uri);
        }
        if (edMap['stream_url'] is String) {
          edMap['stream_url'] = _resolveUrl(edMap['stream_url'] as String, uri);
        }
        if (edMap['tracks'] is List) {
          edMap['tracks'] = (edMap['tracks'] as List).map((tr) {
            final trMap = Map<String, dynamic>.from(tr as Map<String, dynamic>);
            if (trMap['stream_url'] is String) {
              trMap['stream_url'] = _resolveUrl(trMap['stream_url'] as String, uri);
            }
            return trMap;
          }).toList();
        }
        return edMap;
      }).toList();
    }
    return BookDetail.fromJson(data);
  }

  Future<BookDetail> updateProgress(
    String workId, {
    String? readingCfi,
    double? readingPercentage,
    double? listeningSeconds,
    String? listeningTrackId,
    double? listeningPercentage,
    String? activeFormat,
    bool? isFinished,
  }) async {
    final uri = await _buildUri('/v1/books/$workId/progress');
    final headers = await _authHeaders(jsonBody: true);
    final body = <String, dynamic>{};
    if (readingCfi != null) body['reading_cfi'] = readingCfi;
    if (readingPercentage != null) body['reading_percentage'] = readingPercentage;
    if (listeningSeconds != null) body['listening_seconds'] = listeningSeconds;
    if (listeningTrackId != null) body['listening_track_id'] = listeningTrackId;
    if (listeningPercentage != null) body['listening_percentage'] = listeningPercentage;
    if (activeFormat != null) body['active_format'] = activeFormat;
    if (isFinished != null) body['is_finished'] = isFinished;

    final resp = await _client.post(uri, headers: headers, body: jsonEncode(body));
    if (resp.statusCode != 200) {
      throw Exception('Failed to update progress for $workId: ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return BookDetail.fromJson(data);
  }

  Future<List<BookAnnotation>> getAnnotations(String workId) async {
    final uri = await _buildUri('/v1/books/$workId/annotations');
    final headers = await _authHeaders();
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Failed to get annotations: ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = data['annotations'] as List? ?? [];
    return list.map((e) => BookAnnotation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> addAnnotation(
    String workId, {
    required String editionId,
    required String kind,
    String? cfiRange,
    String? highlightColor,
    String? selectedText,
    String? note,
    double? audioTimestamp,
  }) async {
    final uri = await _buildUri('/v1/books/$workId/annotations');
    final headers = await _authHeaders(jsonBody: true);
    final body = {
      'edition_id': editionId,
      'kind': kind,
      if (cfiRange != null) 'cfi_range': cfiRange,
      if (highlightColor != null) 'highlight_color': highlightColor,
      if (selectedText != null) 'selected_text': selectedText,
      if (note != null) 'note': note,
      if (audioTimestamp != null) 'audio_timestamp': audioTimestamp,
    };

    final resp = await _client.post(uri, headers: headers, body: jsonEncode(body));
    if (resp.statusCode != 200) {
      throw Exception('Failed to add annotation: ${resp.statusCode}');
    }
  }

  Future<void> deleteAnnotation(String workId, String annotationId) async {
    final uri = await _buildUri('/v1/books/$workId/annotations/$annotationId');
    final headers = await _authHeaders();
    final resp = await _client.delete(uri, headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Failed to delete annotation: ${resp.statusCode}');
    }
  }

  Future<Uint8List> downloadEpub(String workId) async {
    final uri = await _buildUri('/v1/books/$workId/epub');
    final headers = await _authHeaders();
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Failed to download EPUB for $workId: ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  Future<Uint8List> downloadAudioTrack(String workId, int trackNumber) async {
    final uri = await _buildUri('/v1/books/$workId/audio/$trackNumber');
    final headers = await _authHeaders();
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      throw Exception('Failed to download audio track $trackNumber for $workId: ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  Future<Uint8List> downloadCoverBytes(String workId) async {
    final uri = await _buildUri('/v1/books/$workId/cover');
    final headers = await _authHeaders();
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Failed to download cover for $workId: ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  Future<Map<String, dynamic>?> getAlignment(String workId) async {
    final uri = await _buildUri('/v1/books/$workId/alignment');
    final headers = await _authHeaders();
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode != 200) return null;
    return jsonDecode(resp.body) as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>?> mapAudioToReadingLocation(
    String workId, {
    required int track,
    required double seconds,
  }) async {
    final uri = await _buildUri('/v1/books/$workId/align/audio-to-cfi', {
      'track': track.toString(),
      'sec': seconds.toString(),
    });
    final headers = await _authHeaders();
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode != 200) return null;
    return jsonDecode(resp.body) as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>?> mapReadingLocationToAudio(String workId, {required String cfi}) async {
    final uri = await _buildUri('/v1/books/$workId/align/cfi-to-audio', {'cfi': cfi});
    final headers = await _authHeaders();
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode != 200) return null;
    return jsonDecode(resp.body) as Map<String, dynamic>?;
  }

  Future<void> triggerSync() async {
    final uri = await _buildUri('/v1/books/sync');
    final headers = await _authHeaders();
    await _client.post(uri, headers: headers);
  }

  Future<List<WorldwideBookResult>> searchWorldwideBooks({
    required String query,
    String? formatFilter,
    bool refresh = false,
  }) async {
    final queryParams = <String, String>{'q': query};
    if (formatFilter != null && formatFilter != 'all') {
      queryParams['format'] = formatFilter;
    }
    if (refresh) {
      queryParams['refresh'] = 'true';
    }

    final uri = await _buildUri('/v1/books/search', queryParams);
    final headers = await _authHeaders();
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode != 200) {
      throw Exception('Failed to search books: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = data['results'] as List<dynamic>? ?? [];
    return list.map((e) {
      final map = Map<String, dynamic>.from(e as Map<String, dynamic>);
      if (map['cover_url'] is String) {
        map['cover_url'] = _resolveUrl(map['cover_url'] as String, uri);
      }
      return WorldwideBookResult.fromJson(map);
    }).toList();
  }

  Future<BookRequestItem> submitBookRequest({
    required String title,
    required String author,
    String? isbn,
    String format = 'paired',
  }) async {
    final uri = await _buildUri('/v1/books/requests');
    final headers = await _authHeaders(jsonBody: true);
    final payload = {'title': title, 'author': author, if (isbn != null) 'isbn': isbn, 'format_requested': format};
    final resp = await _client.post(uri, headers: headers, body: jsonEncode(payload));
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('Failed to request book: ${resp.statusCode}');
    }
    return BookRequestItem.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<BookRequestItem?> getBookRequest(String requestId) async {
    final uri = await _buildUri('/v1/books/requests/$requestId');
    final headers = await _authHeaders();
    final resp = await _client.get(uri, headers: headers);
    if (resp.statusCode != 200) return null;
    return BookRequestItem.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }
}
