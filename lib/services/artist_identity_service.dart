import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/jellyfin_models.dart';
import 'catalog_api_client.dart';
import 'finamp_settings_helper.dart';

/// Centralized service to deterministically resolve Jellyfin artist items, IDs, or names
/// to canonical MusicBrainz MBIDs with persistent caching.
class ArtistIdentityService {
  static final Map<String, String> _jellyfinToMbid = {};
  static final Map<String, String> _nameToMbid = {};
  static bool _initialized = false;

  static final RegExp _mbidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Allows unit tests to override offline state without needing Hive box initialization.
  static bool? mockIsOffline;

  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
    _jellyfinToMbid.clear();
    _nameToMbid.clear();
  }

  static bool get isOffline {
    if (mockIsOffline != null) return mockIsOffline!;
    try {
      return FinampSettingsHelper.finampSettings.isOffline;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if [value] is a valid MusicBrainz MBID (standard 36-character hyphenated UUID).
  static bool isMbid(String? value) {
    if (value == null) return false;
    return _mbidRegex.hasMatch(value.trim());
  }

  /// Initialize persistent cache from SharedPreferences.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (key.startsWith('artist_mbid_by_jf:')) {
          final jfId = key.substring('artist_mbid_by_jf:'.length);
          final mbid = prefs.getString(key);
          if (mbid != null && isMbid(mbid)) {
            // Guard: purge known poisoned mappings (e.g. jazz saxophonist Steve Lacy)
            if (mbid == 'ca9766a0-1c30-43e6-a213-bac1334efc4a') {
              prefs.remove(key);
              continue;
            }
            _jellyfinToMbid[jfId] = mbid;
          }
        } else if (key.startsWith('artist_mbid_by_name:')) {
          final name = key.substring('artist_mbid_by_name:'.length);
          final mbid = prefs.getString(key);
          if (mbid != null && isMbid(mbid)) {
            // Guard: purge known poisoned mappings
            if (mbid == 'ca9766a0-1c30-43e6-a213-bac1334efc4a' || name == 'the mamas') {
              prefs.remove(key);
              continue;
            }
            _nameToMbid[name.toLowerCase()] = mbid;
          }
        }
      }
      _initialized = true;
    } catch (_) {}
  }

  /// Records a verified mapping into both memory and persistent storage.
  static void recordMapping({String? jellyfinId, String? name, required String mbid}) {
    if (!isMbid(mbid)) return;
    if (jellyfinId != null && jellyfinId.isNotEmpty) {
      _jellyfinToMbid[jellyfinId] = mbid;
      SharedPreferences.getInstance()
          .then((prefs) {
            prefs.setString('artist_mbid_by_jf:$jellyfinId', mbid);
          })
          .catchError((_) {});
    }
    if (name != null && name.trim().isNotEmpty) {
      final normName = name.trim().toLowerCase();
      _nameToMbid[normName] = mbid;
      SharedPreferences.getInstance()
          .then((prefs) {
            prefs.setString('artist_mbid_by_name:$normName', mbid);
          })
          .catchError((_) {});
    }
  }

  /// Deterministically resolves an artist to a verified MusicBrainz MBID.
  /// Returns null if offline, unresolvable, or ambiguous.
  static Future<String?> resolveArtistMbid({BaseItemDto? artistItem, String? jellyfinId, String? name}) async {
    await init();

    // 0. If input jellyfinId is actually already a MusicBrainz MBID
    if (isMbid(jellyfinId)) return jellyfinId;

    final targetJfId = jellyfinId ?? artistItem?.id.raw;
    final targetName = name ?? artistItem?.name;

    // 1. When online, query authoritative catalog resolve endpoint first if available
    if (!isOffline && GetIt.instance.isRegistered<CatalogApiClient>()) {
      try {
        final catalogClient = GetIt.instance<CatalogApiClient>();
        final res = await catalogClient.resolveArtist(itemId: targetJfId, name: targetName);
        if (res != null) {
          final confidence = res['confidence'] as String?;
          if (confidence != 'ambiguous') {
            final resolvedMbid = res['artist_id'] ?? res['id'];
            if (resolvedMbid is String && isMbid(resolvedMbid)) {
              if (confidence == 'verified' ||
                  confidence == 'exact' ||
                  confidence == 'direct_mbid' ||
                  confidence == 'disambiguated_local_presence' ||
                  confidence == 'name_match' ||
                  confidence == 'canonical_identity' ||
                  confidence == 'credited_identity' ||
                  confidence == 'registered_alias' ||
                  confidence == 'primary_credit') {
                recordMapping(jellyfinId: targetJfId, name: targetName ?? (res['name'] as String?), mbid: resolvedMbid);
              }
              return resolvedMbid;
            }
          }
        }
      } catch (_) {}
    }

    // 2. Check artistItem ProviderIds
    if (artistItem?.providerIds != null) {
      final pids = artistItem!.providerIds!;
      final mbId = pids['MusicBrainzArtist'] ?? pids['MusicBrainzAlbumArtist'] ?? pids['MusicBrainz'];
      if (mbId is String && isMbid(mbId)) {
        recordMapping(jellyfinId: artistItem.id.raw, name: artistItem.name, mbid: mbId);
        return mbId;
      }
    }

    // 3. Check cached mappings
    if (targetJfId != null && _jellyfinToMbid.containsKey(targetJfId)) {
      return _jellyfinToMbid[targetJfId];
    }
    if (targetName != null && _nameToMbid.containsKey(targetName.trim().toLowerCase())) {
      return _nameToMbid[targetName.trim().toLowerCase()];
    }

    // If offline, cannot query remote catalog
    if (isOffline) {
      return null;
    }

    // 4. Query catalog search endpoint for exact normalized name match.
    // Strictly guard against ambiguity: if multiple artists share the exact name, NEVER route blindly.
    // Also NEVER persist an unverified search-derived mapping into storage.
    if (targetName != null && targetName.trim().isNotEmpty) {
      try {
        final catalogClient = GetIt.instance<CatalogApiClient>();
        final searchRes = await catalogClient.search(targetName.trim());
        final normTarget = targetName.trim().toLowerCase();
        final matchingArtists = searchRes.results
            .where((item) => item.kind == 'artist' && item.title.trim().toLowerCase() == normTarget && isMbid(item.id))
            .toList();

        // Exactly one matching artist across catalog search results -> route for UI, but DO NOT persist
        if (matchingArtists.length == 1) {
          return matchingArtists.first.id;
        }
        // If 0 or >1 (ambiguous), return null so the app falls back safely to local ArtistScreen
      } catch (_) {}
    }

    return null;
  }
}
