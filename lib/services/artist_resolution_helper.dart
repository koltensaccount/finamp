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

  /// Resolves an artist [BaseItemDto] target for navigation from a track/album [BaseItemDto].
  /// Truthfully falls back from [artistItems] to [albumArtists] when [artistItems] is empty
  /// or contains invalid/whitespace IDs. Returns null if no genuine artist ID exists,
  /// avoiding fabricating an artist target using the track's ID.
  static BaseItemDto? resolveArtistNavigationTarget({
    required BaseItemDto track,
    String? fallbackArtistName,
  }) {
    final genuine = resolveGenuineArtist(
      artistItems: track.artistItems,
      albumArtists: track.albumArtists,
    );
    if (genuine != null) {
      return BaseItemDto(
        id: genuine.id,
        name: genuine.name ?? fallbackArtistName ?? track.name,
        type: "MusicArtist",
      );
    }
    return null;
  }
}
