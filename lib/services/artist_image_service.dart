import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ArtistImageService {
  static final Map<String, String> _imageCache = {};
  static final Map<String, String> _bioCache = {};
  static final Map<String, List<Map<String, String>>> _similarCache = {};
  static bool _initialized = false;

  /// Initialize persistent caches from SharedPreferences.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (key.startsWith('artist_img:')) {
          final k = key.substring('artist_img:'.length);
          final v = prefs.getString(key);
          if (v != null) _imageCache[k] = v;
        } else if (key.startsWith('artist_bio:')) {
          final k = key.substring('artist_bio:'.length);
          final v = prefs.getString(key);
          if (v != null) _bioCache[k] = v;
        } else if (key.startsWith('artist_similar:')) {
          final k = key.substring('artist_similar:'.length);
          final v = prefs.getString(key);
          if (v != null) {
            try {
              final list = (jsonDecode(v) as List).map((e) => Map<String, String>.from(e as Map)).toList();
              _similarCache[k] = list;
            } catch (_) {}
          }
        }
      }
      _initialized = true;
    } catch (_) {}
  }

  /// Returns a cached artist image URL if available synchronously in memory.
  static String? getKnownArtistImageUrl(String nameOrId) {
    final key = nameOrId.trim().toLowerCase();
    if (_imageCache.containsKey(key)) return _imageCache[key];
    return null;
  }

  /// Fetches an artist image asynchronously if not cached, querying legitimate public sources
  /// (Wikipedia REST API first for verified canonical photos, Deezer API for high-resolution backup).
  static Future<String?> fetchArtistImageUrl(String artistName) async {
    await init();
    final key = artistName.trim().toLowerCase();
    if (_imageCache.containsKey(key) && _imageCache[key]!.isNotEmpty) {
      return _imageCache[key];
    }

    // 1. Try Wikipedia REST API summary
    try {
      final cleanTitle = Uri.encodeComponent(artistName.trim().replaceAll(' ', '_'));
      final wikiUri = Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/$cleanTitle');
      final wikiRes = await http
          .get(wikiUri, headers: {'User-Agent': 'KBMusicCatalog/0.1'})
          .timeout(const Duration(seconds: 4));
      if (wikiRes.statusCode == 200) {
        final data = jsonDecode(wikiRes.body);
        if (data is Map<String, dynamic>) {
          final orig = data['originalimage']?['source'] as String?;
          final thumb = data['thumbnail']?['source'] as String?;
          final url = orig ?? thumb;
          if (url != null && url.isNotEmpty) {
            _saveImage(key, url);
            return url;
          }
        }
      }
    } catch (_) {}

    // 2. Try Deezer Search API
    try {
      final uri = Uri.parse('https://api.deezer.com/search/artist?q=${Uri.encodeComponent(artistName)}');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['data'] is List && (data['data'] as List).isNotEmpty) {
          final first = data['data'][0] as Map<String, dynamic>;
          final url = first['picture_xl'] ?? first['picture_big'] ?? first['picture_medium'];
          if (url is String && url.isNotEmpty) {
            _saveImage(key, url);
            return url;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Fetches legitimate artist biography from Wikipedia REST API.
  static Future<String?> fetchArtistBio(String artistName) async {
    await init();
    final key = artistName.trim().toLowerCase();
    if (_bioCache.containsKey(key) && _bioCache[key]!.isNotEmpty) {
      return _bioCache[key];
    }

    try {
      final cleanTitle = Uri.encodeComponent(artistName.trim().replaceAll(' ', '_'));
      final wikiUri = Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/$cleanTitle');
      final wikiRes = await http
          .get(wikiUri, headers: {'User-Agent': 'KBMusicCatalog/0.1'})
          .timeout(const Duration(seconds: 4));
      if (wikiRes.statusCode == 200) {
        final data = jsonDecode(wikiRes.body);
        if (data is Map<String, dynamic>) {
          final extract = data['extract'] as String?;
          if (extract != null && extract.isNotEmpty) {
            _bioCache[key] = extract;
            unawaited(
              SharedPreferences.getInstance()
                  .then((prefs) {
                    prefs.setString('artist_bio:$key', extract);
                  })
                  .catchError((_) {}),
            );
            return extract;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Fetches legitimate related/similar artists from Deezer API dynamically without hardcoding.
  static Future<List<Map<String, String>>> fetchSimilarArtists(String artistName) async {
    await init();
    final key = artistName.trim().toLowerCase();
    if (_similarCache.containsKey(key) && _similarCache[key]!.isNotEmpty) {
      return _similarCache[key]!;
    }

    try {
      final uri = Uri.parse('https://api.deezer.com/search/artist?q=${Uri.encodeComponent(artistName)}');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['data'] is List && (data['data'] as List).isNotEmpty) {
          final first = data['data'][0] as Map<String, dynamic>;
          final dzId = first['id'];
          if (dzId != null) {
            final relUri = Uri.parse('https://api.deezer.com/artist/$dzId/related');
            final relRes = await http.get(relUri).timeout(const Duration(seconds: 4));
            if (relRes.statusCode == 200) {
              final relData = jsonDecode(relRes.body);
              if (relData is Map<String, dynamic> && relData['data'] is List) {
                final list = <Map<String, String>>[];
                for (final item in (relData['data'] as List).take(10)) {
                  if (item is Map<String, dynamic>) {
                    final name = item['name'] as String?;
                    final pic = (item['picture_medium'] ?? item['picture_big'] ?? item['picture']) as String?;
                    if (name != null && name.isNotEmpty) {
                      list.add({'name': name, 'imageUrl': pic ?? ''});
                    }
                  }
                }
                if (list.isNotEmpty) {
                  _similarCache[key] = list;
                  unawaited(
                    SharedPreferences.getInstance()
                        .then((prefs) {
                          prefs.setString('artist_similar:$key', jsonEncode(list));
                        })
                        .catchError((_) {}),
                  );
                  return list;
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    return const [];
  }

  static void _saveImage(String key, String url) {
    _imageCache[key] = url;
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) {
            prefs.setString('artist_img:$key', url);
          })
          .catchError((_) {}),
    );
  }
}
