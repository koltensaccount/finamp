import 'dart:convert';

List<String> _parseStringList(dynamic raw) {
  if (raw == null) return const [];
  if (raw is List) {
    return raw.map((e) => e.toString()).toList(growable: false);
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList(growable: false);
        }
      } catch (_) {
        return const [];
      }
    }
    if (trimmed.isNotEmpty) {
      return [trimmed];
    }
  }
  return const [];
}

enum CatalogAvailabilityState { available, possiblyAvailable, notFound, pending }

CatalogAvailabilityState catalogAvailabilityStateFromJson(Object? value) {
  return switch (value) {
    'available' => CatalogAvailabilityState.available,
    'possibly_available' => CatalogAvailabilityState.possiblyAvailable,
    'pending' => CatalogAvailabilityState.pending,
    _ => CatalogAvailabilityState.notFound,
  };
}

class CatalogLocalItem {
  const CatalogLocalItem({required this.serverId, required this.itemId});

  factory CatalogLocalItem.fromJson(Map<String, dynamic> json) => CatalogLocalItem(
    serverId: (json['server_id'] ?? '') as String,
    itemId: (json['item_id'] ?? '') as String,
  );

  final String serverId;
  final String itemId;
}

class CatalogAvailability {
  const CatalogAvailability({
    required this.state,
    required this.candidateCount,
    this.playableItemId,
    this.selectionRequired = false,
    this.acquisitionPending = false,
    this.localItems = const [],
  });

  factory CatalogAvailability.fromJson(Map<String, dynamic> json) {
    final rawItems = json['local_items'] as List<dynamic>? ?? const [];
    return CatalogAvailability(
      state: catalogAvailabilityStateFromJson(json['state']),
      candidateCount: (json['candidate_count'] as num?)?.toInt() ?? 0,
      playableItemId: json['playable_item_id'] as String?,
      selectionRequired: json['selection_required'] as bool? ?? false,
      acquisitionPending: json['acquisition_pending'] as bool? ?? false,
      localItems: rawItems
          .whereType<Map<String, dynamic>>()
          .map((item) => CatalogLocalItem.fromJson(item))
          .toList(growable: false),
    );
  }

  final CatalogAvailabilityState state;
  final int candidateCount;
  final String? playableItemId;
  final bool selectionRequired;
  final bool acquisitionPending;
  final List<CatalogLocalItem> localItems;

  bool get canPlay => state == CatalogAvailabilityState.available && playableItemId != null && !selectionRequired;
}

class CatalogCredit {
  const CatalogCredit({
    required this.artistId,
    required this.name,
    this.joinphrase = '',
  });

  factory CatalogCredit.fromJson(Map<String, dynamic> json) => CatalogCredit(
    artistId: (json['artist_id'] ?? json['id'] ?? '') as String,
    name: (json['name'] ?? json['display_name'] ?? '') as String,
    joinphrase: (json['joinphrase'] ?? '') as String,
  );

  final String artistId;
  final String name;
  final String joinphrase;
}

class CatalogSearchResult {
  const CatalogSearchResult({
    required this.id,
    required this.kind,
    required this.title,
    this.availability,
    this.editionIds = const [],
    this.primaryType,
    this.firstDate,
    this.durationMs,
    this.displayArtist,
    this.artistCredits = const [],
    this.secondaryTypes = const [],
    this.category,
    this.imageUrl,
    this.ownership,
  });

  factory CatalogSearchResult.fromJson(Map<String, dynamic> json) {
    final rawEditions = json['edition_ids'] as List<dynamic>? ?? const [];
    final rawCredits = json['artist_credit'] as List<dynamic>? ?? const [];
    final secondaryTypes = _parseStringList(json['secondary_types']);
    return CatalogSearchResult(
      id: json['id'] as String,
      kind: json['kind'] as String,
      title: (json['name'] ?? json['title'] ?? '') as String,
      availability: json['availability'] is Map<String, dynamic>
          ? CatalogAvailability.fromJson(json['availability'] as Map<String, dynamic>)
          : null,
      editionIds: rawEditions.cast<String>(),
      primaryType: json['primary_type'] as String?,
      firstDate: json['first_date'] as String?,
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      displayArtist: json['display_artist'] as String?,
      artistCredits: rawCredits
          .whereType<Map<String, dynamic>>()
          .map((c) => CatalogCredit.fromJson(c))
          .toList(growable: false),
      secondaryTypes: secondaryTypes,
      category: json['category'] as String?,
      imageUrl: json['image_url'] as String?,
      ownership: json['ownership'] as String?,
    );
  }

  final String id;
  final String kind;
  final String title;
  final CatalogAvailability? availability;
  final List<String> editionIds;
  final String? primaryType;
  final String? firstDate;
  final int? durationMs;
  final String? displayArtist;
  final List<CatalogCredit> artistCredits;
  final List<String> secondaryTypes;
  final String? category;
  final String? imageUrl;
  final String? ownership;

  bool get isFullyOwned => ownership == 'full';
  bool get isPartiallyOwned => ownership == 'partial';
  bool get isNoneOwned => ownership == null || ownership == 'none';

  String get formattedDuration {
    if (durationMs == null) return '';
    final totalSeconds = durationMs! ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class CatalogSearchResponse {
  const CatalogSearchResponse({required this.results, required this.cached});

  factory CatalogSearchResponse.fromJson(Map<String, dynamic> json) => CatalogSearchResponse(
    results: (json['results'] as List<dynamic>? ?? const [])
        .map((result) => CatalogSearchResult.fromJson(result as Map<String, dynamic>))
        .toList(growable: false),
    cached: json['cached'] as bool? ?? false,
  );

  final List<CatalogSearchResult> results;
  final bool cached;
}

class CatalogTrack {
  const CatalogTrack({
    required this.id,
    required this.releaseId,
    required this.recordingId,
    required this.disc,
    required this.position,
    required this.title,
    this.durationMs,
    this.availability,
    this.displayArtist,
    this.artistCredits = const [],
  });

  factory CatalogTrack.fromJson(Map<String, dynamic> json) {
    final rawCredits = json['artist_credit'] as List<dynamic>? ?? const [];
    return CatalogTrack(
      id: json['id'] as String,
      releaseId: (json['release_id'] ?? '') as String,
      recordingId: (json['recording_id'] ?? '') as String,
      disc: (json['disc'] as num?)?.toInt() ?? 1,
      position: (json['position'] as num?)?.toInt() ?? 1,
      title: (json['title'] ?? '') as String,
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      availability: json['availability'] is Map<String, dynamic>
          ? CatalogAvailability.fromJson(json['availability'] as Map<String, dynamic>)
          : null,
      displayArtist: json['display_artist'] as String?,
      artistCredits: rawCredits
          .whereType<Map<String, dynamic>>()
          .map((c) => CatalogCredit.fromJson(c))
          .toList(growable: false),
    );
  }

  final String id;
  final String releaseId;
  final String recordingId;
  final int disc;
  final int position;
  final String title;
  final int? durationMs;
  final CatalogAvailability? availability;
  final String? displayArtist;
  final List<CatalogCredit> artistCredits;

  String get formattedDuration {
    if (durationMs == null) return '';
    final totalSeconds = durationMs! ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class CatalogRelease {
  const CatalogRelease({
    required this.id,
    this.groupId,
    required this.title,
    this.tracks = const [],
    this.ownedTracks = 0,
    this.totalTracks = 0,
    this.ownership = 'none',
    this.displayArtist,
    this.artistCredits = const [],
    this.imageUrl,
    this.groupImageUrl,
  });

  factory CatalogRelease.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] as List<dynamic>? ?? const [];
    final rawCredits = json['artist_credit'] as List<dynamic>? ?? const [];
    return CatalogRelease(
      id: json['id'] as String,
      groupId: json['group_id'] as String?,
      title: (json['title'] ?? '') as String,
      tracks: rawTracks
          .whereType<Map<String, dynamic>>()
          .map((t) => CatalogTrack.fromJson(t))
          .toList(growable: false),
      ownedTracks: (json['owned_tracks'] as num?)?.toInt() ?? 0,
      totalTracks: (json['total_tracks'] as num?)?.toInt() ?? 0,
      ownership: (json['ownership'] ?? 'none') as String,
      displayArtist: json['display_artist'] as String?,
      artistCredits: rawCredits
          .whereType<Map<String, dynamic>>()
          .map((c) => CatalogCredit.fromJson(c))
          .toList(growable: false),
      imageUrl: json['image_url'] as String?,
      groupImageUrl: json['group_image_url'] as String?,
    );
  }

  final String id;
  final String? groupId;
  final String title;
  final List<CatalogTrack> tracks;
  final int ownedTracks;
  final int totalTracks;
  final String ownership;
  final String? displayArtist;
  final List<CatalogCredit> artistCredits;
  final String? imageUrl;
  final String? groupImageUrl;

  bool get isFullyOwned => ownership == 'full';
  bool get isPartiallyOwned => ownership == 'partial';
  bool get isNoneOwned => ownership == 'none';
}

class CatalogAlbumGroup {
  const CatalogAlbumGroup({
    required this.id,
    required this.title,
    this.primaryType,
    this.firstDate,
    this.editions = const [],
    this.displayArtist,
    this.artistCredits = const [],
    this.imageUrl,
    this.ownership,
    this.secondaryTypes = const [],
  });

  factory CatalogAlbumGroup.fromJson(Map<String, dynamic> json) {
    final rawEditions = json['editions'] as List<dynamic>? ?? const [];
    final rawCredits = json['artist_credit'] as List<dynamic>? ?? const [];
    final secondaryTypes = _parseStringList(json['secondary_types']);
    return CatalogAlbumGroup(
      id: json['id'] as String,
      title: (json['title'] ?? '') as String,
      primaryType: json['primary_type'] as String?,
      firstDate: json['first_date'] as String?,
      editions: rawEditions
          .whereType<Map<String, dynamic>>()
          .map((e) => CatalogRelease.fromJson(e))
          .toList(growable: false),
      displayArtist: json['display_artist'] as String?,
      artistCredits: rawCredits
          .whereType<Map<String, dynamic>>()
          .map((c) => CatalogCredit.fromJson(c))
          .toList(growable: false),
      imageUrl: json['image_url'] as String?,
      ownership: json['ownership'] as String?,
      secondaryTypes: secondaryTypes,
    );
  }

  final String id;
  final String title;
  final String? primaryType;
  final String? firstDate;
  final List<CatalogRelease> editions;
  final String? displayArtist;
  final List<CatalogCredit> artistCredits;
  final String? imageUrl;
  final String? ownership;
  final List<String> secondaryTypes;

  bool get isFullyOwned => ownership == 'full';
  bool get isPartiallyOwned => ownership == 'partial';
  bool get isNoneOwned => ownership == null || ownership == 'none';
}

class CatalogArtist {
  const CatalogArtist({
    required this.id,
    required this.name,
    this.albums = const [],
    this.recordings = const [],
  });

  factory CatalogArtist.fromJson(Map<String, dynamic> json) {
    final rawAlbums = json['albums'] as List<dynamic>? ?? const [];
    final rawRecordings = json['recordings'] as List<dynamic>? ?? const [];
    return CatalogArtist(
      id: json['id'] as String,
      name: (json['name'] ?? '') as String,
      albums: rawAlbums
          .whereType<Map<String, dynamic>>()
          .map((a) => CatalogSearchResult.fromJson({...a, 'kind': 'album'}))
          .toList(growable: false),
      recordings: rawRecordings
          .whereType<Map<String, dynamic>>()
          .map((r) => CatalogSearchResult.fromJson({...r, 'kind': 'track'}))
          .toList(growable: false),
    );
  }

  final String id;
  final String name;
  final List<CatalogSearchResult> albums;
  final List<CatalogSearchResult> recordings;
}

class CatalogRequestStatus {
  const CatalogRequestStatus({required this.id, required this.state, required this.dispatchEnabled});

  factory CatalogRequestStatus.fromJson(Map<String, dynamic> json) => CatalogRequestStatus(
    id: (json['id'] as num).toInt(),
    state: json['state'] as String,
    dispatchEnabled: json['dispatch_enabled'] as bool? ?? false,
  );

  final int id;
  final String state;
  final bool dispatchEnabled;
}

class CatalogRequestDetail {
  const CatalogRequestDetail({
    required this.id,
    required this.releaseId,
    required this.scope,
    required this.state,
    required this.origin,
    this.backendId,
    this.createdAt,
  });

  factory CatalogRequestDetail.fromJson(Map<String, dynamic> json) => CatalogRequestDetail(
    id: (json['id'] as num).toInt(),
    releaseId: (json['release_id'] ?? '') as String,
    scope: (json['scope'] ?? 'album') as String,
    state: (json['state'] ?? 'queued') as String,
    origin: (json['origin'] ?? '') as String,
    backendId: json['backend_id'] as String?,
    createdAt: (json['created_at'] as num?)?.toDouble(),
  );

  final int id;
  final String releaseId;
  final String scope;
  final String state;
  final String origin;
  final String? backendId;
  final double? createdAt;
}
