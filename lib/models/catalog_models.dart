enum CatalogAvailabilityState { available, possiblyAvailable, notFound, pending }

CatalogAvailabilityState catalogAvailabilityStateFromJson(Object? value) {
  return switch (value) {
    'available' => CatalogAvailabilityState.available,
    'possibly_available' => CatalogAvailabilityState.possiblyAvailable,
    'pending' => CatalogAvailabilityState.pending,
    _ => CatalogAvailabilityState.notFound,
  };
}

class CatalogAvailability {
  const CatalogAvailability({
    required this.state,
    required this.candidateCount,
    this.playableItemId,
    this.selectionRequired = false,
    this.acquisitionPending = false,
  });

  factory CatalogAvailability.fromJson(Map<String, dynamic> json) => CatalogAvailability(
    state: catalogAvailabilityStateFromJson(json['state']),
    candidateCount: (json['candidate_count'] as num?)?.toInt() ?? 0,
    playableItemId: json['playable_item_id'] as String?,
    selectionRequired: json['selection_required'] as bool? ?? false,
    acquisitionPending: json['acquisition_pending'] as bool? ?? false,
  );

  final CatalogAvailabilityState state;
  final int candidateCount;
  final String? playableItemId;
  final bool selectionRequired;
  final bool acquisitionPending;

  bool get canPlay => state == CatalogAvailabilityState.available && playableItemId != null && !selectionRequired;
}

class CatalogSearchResult {
  const CatalogSearchResult({
    required this.id,
    required this.kind,
    required this.title,
    this.availability,
    this.editionIds = const [],
  });

  factory CatalogSearchResult.fromJson(Map<String, dynamic> json) {
    final rawEditions = json['edition_ids'] as List<dynamic>? ?? const [];
    return CatalogSearchResult(
      id: json['id'] as String,
      kind: json['kind'] as String,
      title: (json['name'] ?? json['title'] ?? '') as String,
      availability: json['availability'] is Map<String, dynamic>
          ? CatalogAvailability.fromJson(json['availability'] as Map<String, dynamic>)
          : null,
      editionIds: rawEditions.cast<String>(),
    );
  }

  final String id;
  final String kind;
  final String title;
  final CatalogAvailability? availability;
  final List<String> editionIds;
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
