import 'package:finamp/models/jellyfin_models.dart';

class ArtistResolutionHelper {
  /// Resolves the first genuine artist with a valid, non-empty ID.
  /// Checks [artistItems] first; if empty or none has a valid ID, falls back to [albumArtists].
  static NameIdPair? resolveGenuineArtist({
    List<NameIdPair>? artistItems,
    List<NameIdPair>? albumArtists,
  }) {
    if (artistItems != null) {
      for (final item in artistItems) {
        if (item.id.raw.trim().isNotEmpty) {
          return item;
        }
      }
    }
    if (albumArtists != null) {
      for (final item in albumArtists) {
        if (item.id.raw.trim().isNotEmpty) {
          return item;
        }
      }
    }
    return null;
  }
}
