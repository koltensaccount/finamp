import 'package:flutter/material.dart';

import '../models/jellyfin_models.dart';
import '../screens/artist_screen.dart';
import '../screens/catalog_artist_screen.dart';
import 'artist_identity_service.dart';
import 'finamp_settings_helper.dart';

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

  /// Centralized artist router and resolver.
  /// When online and identity is confident, navigates to the canonical [CatalogArtistScreen].
  /// When offline, catalog is unavailable, or identity is ambiguous, falls back to local [ArtistScreen].
  static Future<void> navigateToArtist(
    BuildContext context, {
    BaseItemDto? artistItem,
    String? jellyfinId,
    String? artistMbid,
    String? artistName,
    BaseItemDto? genreFilter,
    bool popFirst = false,
  }) async {
    final effectiveName = artistName ?? artistItem?.name;
    final effectiveJfId = jellyfinId ?? artistItem?.id.raw;

    // 1. If currently in offline mode, bypass all catalog resolution and open local ArtistScreen
    if (ArtistIdentityService.isOffline) {
      final target = artistItem ??
          (effectiveJfId != null
              ? BaseItemDto(
                  id: BaseItemId(effectiveJfId),
                  name: effectiveName,
                  type: 'MusicArtist',
                )
              : null);
      if (target != null && context.mounted) {
        if (genreFilter != null) {
          final route = MaterialPageRoute<ArtistScreen>(
            builder: (_) => ArtistScreen(
              widgetArtist: target,
              genreFilter: genreFilter,
            ),
          );
          if (popFirst) {
            Navigator.of(context).pop();
            Navigator.of(context).push(route);
          } else {
            Navigator.of(context).push(route);
          }
        } else {
          if (popFirst) {
            Navigator.of(context).popAndPushNamed(ArtistScreen.routeName, arguments: target);
          } else {
            Navigator.of(context).pushNamed(ArtistScreen.routeName, arguments: target);
          }
        }
      }
      return;
    }

    // 2. Try to resolve confident MusicBrainz MBID
    String? resolvedMbid = artistMbid;
    if (resolvedMbid == null || !ArtistIdentityService.isMbid(resolvedMbid)) {
      resolvedMbid = await ArtistIdentityService.resolveArtistMbid(
        artistItem: artistItem,
        jellyfinId: effectiveJfId,
        name: effectiveName,
      );
    }

    if (!context.mounted) return;

    // 3. If confident MBID found, navigate to canonical CatalogArtistScreen
    if (resolvedMbid != null && ArtistIdentityService.isMbid(resolvedMbid)) {
      final args = CatalogArtistScreenArguments(
        artistMbid: resolvedMbid,
        initialName: effectiveName,
        fallbackArtist: artistItem ??
            (effectiveJfId != null
                ? BaseItemDto(
                    id: BaseItemId(effectiveJfId),
                    name: effectiveName,
                    type: 'MusicArtist',
                  )
                : null),
      );
      if (popFirst) {
        Navigator.of(context).popAndPushNamed(CatalogArtistScreen.routeName, arguments: args);
      } else {
        Navigator.of(context).pushNamed(CatalogArtistScreen.routeName, arguments: args);
      }
      return;
    }

    // 4. Fallback: navigate to local ArtistScreen
    final target = artistItem ??
        (effectiveJfId != null
            ? BaseItemDto(
                id: BaseItemId(effectiveJfId),
                name: effectiveName,
                type: 'MusicArtist',
              )
            : null);
    if (target != null && context.mounted) {
      if (genreFilter != null) {
        final route = MaterialPageRoute<ArtistScreen>(
          builder: (_) => ArtistScreen(
            widgetArtist: target,
            genreFilter: genreFilter,
          ),
        );
        if (popFirst) {
          Navigator.of(context).pop();
          Navigator.of(context).push(route);
        } else {
          Navigator.of(context).push(route);
        }
      } else {
        if (popFirst) {
          Navigator.of(context).popAndPushNamed(ArtistScreen.routeName, arguments: target);
        } else {
          Navigator.of(context).pushNamed(ArtistScreen.routeName, arguments: target);
        }
      }
    }
  }
}
