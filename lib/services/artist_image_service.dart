import 'dart:convert';
import 'package:http/http.dart' as http;

class ArtistImageService {
  static final Map<String, String> _cache = {
    // MusicBrainz MBIDs
    'b10bbbfc-cf9e-42e0-be17-e2c3e1d2600d':
        'https://e-cdns-images.dzcdn.net/images/artist/16925ed8f96eb621ecd56c2c8ba3da6e/500x500-000000-80-0-0.jpg',
    'e0c97a4d-c392-41a9-a374-57af3e3eeab3':
        'https://e-cdns-images.dzcdn.net/images/artist/f21589416d59cc1b172748ad72e8a3e9/500x500-000000-80-0-0.jpg',
    '83d91898-7763-47d7-b03b-b92132375c47':
        'https://cdn-images.dzcdn.net/images/artist/0aaad29662a33e33350f999d6b26e517/500x500-000000-80-0-0.jpg',
    'a74b1b7f-71a5-4011-9441-d0b5e4122711':
        'https://cdn-images.dzcdn.net/images/artist/0d58cfbc90f2e776608bcdc0c45a4711/500x500-000000-80-0-0.jpg',
    '678d88b2-87b0-403b-b63d-5da7465aecc3':
        'https://cdn-images.dzcdn.net/images/artist/2cf138b96a63da677ac6fb79846607c8/500x500-000000-80-0-0.jpg',
    'b071f9f8-14b0-4217-8e97-eb41da73f59e':
        'https://cdn-images.dzcdn.net/images/artist/cac467bef484959b4ad503c4cb7ef83d/500x500-000000-80-0-0.jpg',
    'f72671c6-11f2-452f-87a3-4889c6569106':
        'https://cdn-images.dzcdn.net/images/artist/5d8bf8877cefa207508196c2e61a2ad8/500x500-000000-80-0-0.jpg',

    // Normalized lowercase artist names
    'the beatles':
        'https://e-cdns-images.dzcdn.net/images/artist/16925ed8f96eb621ecd56c2c8ba3da6e/500x500-000000-80-0-0.jpg',
    'beatles':
        'https://e-cdns-images.dzcdn.net/images/artist/16925ed8f96eb621ecd56c2c8ba3da6e/500x500-000000-80-0-0.jpg',
    'geese':
        'https://e-cdns-images.dzcdn.net/images/artist/f21589416d59cc1b172748ad72e8a3e9/500x500-000000-80-0-0.jpg',
    'radiohead':
        'https://cdn-images.dzcdn.net/images/artist/0d58cfbc90f2e776608bcdc0c45a4711/500x500-000000-80-0-0.jpg',
    'pink floyd':
        'https://cdn-images.dzcdn.net/images/artist/0aaad29662a33e33350f999d6b26e517/500x500-000000-80-0-0.jpg',
    'black country, new road':
        'https://cdn-images.dzcdn.net/images/artist/5d8bf8877cefa207508196c2e61a2ad8/500x500-000000-80-0-0.jpg',
    'led zeppelin':
        'https://cdn-images.dzcdn.net/images/artist/2cf138b96a63da677ac6fb79846607c8/500x500-000000-80-0-0.jpg',
    'the rolling stones':
        'https://cdn-images.dzcdn.net/images/artist/cac467bef484959b4ad503c4cb7ef83d/500x500-000000-80-0-0.jpg',
    'rolling stones':
        'https://cdn-images.dzcdn.net/images/artist/cac467bef484959b4ad503c4cb7ef83d/500x500-000000-80-0-0.jpg',
    'drake':
        'https://cdn-images.dzcdn.net/images/artist/eb0ed5b21d1ea5af021fc074ded0e91f/500x500-000000-80-0-0.jpg',
    'mj lenderman':
        'https://cdn-images.dzcdn.net/images/artist/99d12aa8eef867cc63f2e7ba80414b88/500x500-000000-80-0-0.jpg',
    'billie eilish':
        'https://cdn-images.dzcdn.net/images/artist/8eab1a9a644889aabaca1e193e05f984/500x500-000000-80-0-0.jpg',
    'fleetwood mac':
        'https://cdn-images.dzcdn.net/images/artist/ef23278cf3a67a3ca8404ddaa38699d4/500x500-000000-80-0-0.jpg',
  };

  /// Returns a cached artist image URL if available synchronously.
  static String? getKnownArtistImageUrl(String nameOrId) {
    final key = nameOrId.trim().toLowerCase();
    if (_cache.containsKey(key)) return _cache[key];
    return null;
  }

  /// Fetches an artist image asynchronously if not cached, querying Deezer API.
  static Future<String?> fetchArtistImageUrl(String artistName) async {
    final key = artistName.trim().toLowerCase();
    if (_cache.containsKey(key)) return _cache[key];

    try {
      final uri = Uri.parse('https://api.deezer.com/search/artist?q=${Uri.encodeComponent(artistName)}');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['data'] is List && (data['data'] as List).isNotEmpty) {
          final first = data['data'][0] as Map<String, dynamic>;
          final url = first['picture_big'] ?? first['picture_medium'] ?? first['picture'];
          if (url is String && url.isNotEmpty) {
            _cache[key] = url;
            return url;
          }
        }
      }
    } catch (_) {
      // Ignore network errors gracefully
    }
    return null;
  }
}
