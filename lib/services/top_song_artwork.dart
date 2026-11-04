import '../models/catalog_models.dart';
import '../models/jellyfin_models.dart';

/// Artwork selection is independent of the version selected for playback.
Future<List<String>> resolveTopSongArtwork(
  CatalogSearchResult track, {
  List<CatalogSearchResult> albums = const [],
  required Future<BaseItemDto> Function(String) loadItem,
  required String? Function(BaseItemDto) imageUrl,
}) async {
  final ids = {
    if (track.artworkItemId?.isNotEmpty ?? false) track.artworkItemId!,
    if (track.availability?.playableItemId?.isNotEmpty ?? false) track.availability!.playableItemId!,
    ...?track.availability?.localItems.map((item) => item.itemId).where((id) => id.isNotEmpty),
  };
  final items = <BaseItemDto>[];
  for (final id in ids) {
    try {
      items.add(await loadItem(id));
    } catch (_) {
      // A stale candidate must not hide other local covers.
    }
  }
  int rank(BaseItemDto item) {
    final title = (item.album ?? '').toLowerCase();
    final metadata = albums
        .where(
          (album) => album.title.toLowerCase() == title || album.id == item.providerIds?['MusicBrainzReleaseGroup'],
        )
        .firstOrNull;
    final secondary = metadata?.secondaryTypes.map((type) => type.toLowerCase()).toSet() ?? <String>{};
    if (secondary.intersection({'compilation', 'live', 'remix', 'soundtrack', 'dj-mix'}).isNotEmpty) return 3;
    if ({'single', 'ep'}.contains(metadata?.primaryType?.toLowerCase())) return 2;
    if (RegExp(r'compilation|greatest hits|best of|anthology|live').hasMatch(title)) return 3;
    if (RegExp(r'\bsingle\b|\bep\b').hasMatch(title)) return 2;
    if (RegExp(r'remaster|reissue|deluxe|expanded|anniversary').hasMatch(title)) return 1;
    return 0;
  }

  // The catalog's representative already uses release types and edition data.
  // Keep it first; rank remaining candidates using the local edition label.
  final indexed = items.indexed.toList()
    ..sort((a, b) {
      final ar = a.$2.id.raw == track.artworkItemId ? -1 : rank(a.$2);
      final br = b.$2.id.raw == track.artworkItemId ? -1 : rank(b.$2);
      final comparison = ar.compareTo(br);
      return comparison != 0 ? comparison : a.$1.compareTo(b.$1);
    });
  final urls = <String>{};
  for (final entry in indexed) {
    final item = entry.$2;
    final url = imageUrl(item);
    if (url != null && url.isNotEmpty) urls.add(url);
    // Some track responses omit inherited image tags. Resolve the actual album
    // before giving up, using the same image resolver as the mini-player.
    if (item.albumId != null) {
      try {
        final albumUrl = imageUrl(await loadItem(item.albumId!.raw));
        if (albumUrl != null && albumUrl.isNotEmpty) urls.add(albumUrl);
      } catch (_) {}
    }
  }
  return urls.toList(growable: false);
}
