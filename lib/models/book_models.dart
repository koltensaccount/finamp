class BookProgress {
  const BookProgress({
    this.readingCfi,
    this.readingPercentage = 0.0,
    this.readingUpdatedAt,
    this.listeningSeconds = 0.0,
    this.listeningTrackId,
    this.listeningPercentage = 0.0,
    this.listeningUpdatedAt,
    this.lastActiveFormat,
    this.isFinished = false,
  });

  factory BookProgress.fromJson(Map<String, dynamic> json) => BookProgress(
    readingCfi: json['reading_cfi'] as String?,
    readingPercentage: (json['reading_percentage'] as num?)?.toDouble() ?? 0.0,
    readingUpdatedAt: (json['reading_updated_at'] as num?)?.toDouble(),
    listeningSeconds: (json['listening_seconds'] as num?)?.toDouble() ?? 0.0,
    listeningTrackId: json['listening_track_id'] as String?,
    listeningPercentage: (json['listening_percentage'] as num?)?.toDouble() ?? 0.0,
    listeningUpdatedAt: (json['listening_updated_at'] as num?)?.toDouble(),
    lastActiveFormat: json['last_active_format'] as String?,
    isFinished: (json['is_finished'] as bool?) ?? false,
  );

  final String? readingCfi;
  final double readingPercentage;
  final double? readingUpdatedAt;
  final double listeningSeconds;
  final String? listeningTrackId;
  final double listeningPercentage;
  final double? listeningUpdatedAt;
  final String? lastActiveFormat;
  final bool isFinished;

  bool get hasReadingProgress => readingCfi != null || readingPercentage > 0.0;
  bool get hasListeningProgress => listeningSeconds > 0.0 || listeningPercentage > 0.0;
  bool get hasProgress => hasReadingProgress || hasListeningProgress;

  Map<String, dynamic> toJson() => {
    'reading_cfi': readingCfi,
    'reading_percentage': readingPercentage,
    'reading_updated_at': readingUpdatedAt,
    'listening_seconds': listeningSeconds,
    'listening_track_id': listeningTrackId,
    'listening_percentage': listeningPercentage,
    'listening_updated_at': listeningUpdatedAt,
    'last_active_format': lastActiveFormat,
    'is_finished': isFinished,
  };
}

class BookAsset {
  const BookAsset({
    required this.id,
    required this.editionId,
    required this.kind,
    this.filePath,
    this.fileSize,
    this.mimeType,
    this.format,
    this.durationSeconds,
    this.trackNumber,
    this.absItemId,
    this.absFileIno,
  });

  factory BookAsset.fromJson(Map<String, dynamic> json) => BookAsset(
    id: json['id'] as String? ?? '',
    editionId: json['edition_id'] as String? ?? '',
    kind: json['kind'] as String? ?? '',
    filePath: json['file_path'] as String?,
    fileSize: json['file_size'] as int?,
    mimeType: json['mime_type'] as String?,
    format: json['format'] as String?,
    durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
    trackNumber: json['track_number'] as int?,
    absItemId: json['abs_item_id'] as String?,
    absFileIno: json['abs_file_ino'] as String?,
  );

  final String id;
  final String editionId;
  final String kind;
  final String? filePath;
  final int? fileSize;
  final String? mimeType;
  final String? format;
  final double? durationSeconds;
  final int? trackNumber;
  final String? absItemId;
  final String? absFileIno;
}

class BookChapter {
  const BookChapter({
    required this.id,
    required this.editionId,
    required this.indexNum,
    required this.title,
    this.startSeconds,
    this.endSeconds,
    this.epubHref,
    this.epubCfi,
  });

  factory BookChapter.fromJson(Map<String, dynamic> json) => BookChapter(
    id: json['id'] as String? ?? '',
    editionId: json['edition_id'] as String? ?? '',
    indexNum: json['index_num'] as int? ?? 1,
    title: json['title'] as String? ?? '',
    startSeconds: (json['start_seconds'] as num?)?.toDouble(),
    endSeconds: (json['end_seconds'] as num?)?.toDouble(),
    epubHref: json['epub_href'] as String?,
    epubCfi: json['epub_cfi'] as String?,
  );

  final String id;
  final String editionId;
  final int indexNum;
  final String title;
  final double? startSeconds;
  final double? endSeconds;
  final String? epubHref;
  final String? epubCfi;
}

class BookEdition {
  const BookEdition({
    required this.id,
    required this.workId,
    required this.format,
    required this.title,
    this.subtitle,
    this.authors = const [],
    this.narrators = const [],
    this.publisher,
    this.publishedYear,
    this.language,
    this.isbn,
    this.asin,
    this.description,
    this.coverUrl,
    this.assets = const [],
    this.chapters = const [],
  });

  factory BookEdition.fromJson(Map<String, dynamic> json) => BookEdition(
    id: json['id'] as String? ?? '',
    workId: json['work_id'] as String? ?? '',
    format: json['format'] as String? ?? '',
    title: json['title'] as String? ?? '',
    subtitle: json['subtitle'] as String?,
    authors: (json['authors'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    narrators: (json['narrators'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    publisher: json['publisher'] as String?,
    publishedYear: json['published_year'] as int?,
    language: json['language'] as String?,
    isbn: json['isbn'] as String?,
    asin: json['asin'] as String?,
    description: json['description'] as String?,
    coverUrl: json['cover_url'] as String?,
    assets: (json['assets'] as List?)?.map((e) => BookAsset.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
    chapters:
        (json['chapters'] as List?)?.map((e) => BookChapter.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
  );

  final String id;
  final String workId;
  final String format; // 'epub', 'audiobook', 'paired'
  final String title;
  final String? subtitle;
  final List<String> authors;
  final List<String> narrators;
  final String? publisher;
  final int? publishedYear;
  final String? language;
  final String? isbn;
  final String? asin;
  final String? description;
  final String? coverUrl;
  final List<BookAsset> assets;
  final List<BookChapter> chapters;
}

class BookSummary {
  const BookSummary({
    required this.id,
    required this.title,
    required this.author,
    this.description,
    this.genres = const [],
    this.seriesName,
    this.seriesOrder,
    this.coverUrl,
    this.availableFormats = const [],
    this.isPaired = false,
    required this.progress,
  });

  factory BookSummary.fromJson(Map<String, dynamic> json) => BookSummary(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    author: json['author'] as String? ?? '',
    description: json['description'] as String?,
    genres: (json['genres'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    seriesName: json['series_name'] as String?,
    seriesOrder: (json['series_order'] as num?)?.toDouble(),
    coverUrl: json['cover_url'] as String?,
    availableFormats: (json['available_formats'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    isPaired: (json['is_paired'] as bool?) ?? false,
    progress: BookProgress.fromJson(json['progress'] as Map<String, dynamic>? ?? {}),
  );

  final String id;
  final String title;
  final String author;
  final String? description;
  final List<String> genres;
  final String? seriesName;
  final double? seriesOrder;
  final String? coverUrl;
  final List<String> availableFormats;
  final bool isPaired;
  final BookProgress progress;

  bool get hasEpub => availableFormats.contains('epub');
  bool get hasAudiobook => availableFormats.contains('audiobook');
}

class BookDetail {
  const BookDetail({
    required this.id,
    required this.title,
    required this.author,
    this.description,
    this.genres = const [],
    this.seriesName,
    this.seriesOrder,
    this.coverUrl,
    this.availableFormats = const [],
    this.isPaired = false,
    this.editions = const [],
    required this.progress,
    this.alignment,
  });

  factory BookDetail.fromJson(Map<String, dynamic> json) => BookDetail(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    author: json['author'] as String? ?? '',
    description: json['description'] as String?,
    genres: (json['genres'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    seriesName: json['series_name'] as String?,
    seriesOrder: (json['series_order'] as num?)?.toDouble(),
    coverUrl: json['cover_url'] as String?,
    availableFormats: (json['available_formats'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    isPaired: (json['is_paired'] as bool?) ?? false,
    editions:
        (json['editions'] as List?)?.map((e) => BookEdition.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
    progress: BookProgress.fromJson(json['progress'] as Map<String, dynamic>? ?? {}),
    alignment: json['alignment'] as Map<String, dynamic>?,
  );

  final String id;
  final String title;
  final String author;
  final String? description;
  final List<String> genres;
  final String? seriesName;
  final double? seriesOrder;
  final String? coverUrl;
  final List<String> availableFormats;
  final bool isPaired;
  final List<BookEdition> editions;
  final BookProgress progress;
  final Map<String, dynamic>? alignment;

  bool get hasEpub => availableFormats.contains('epub');
  bool get hasAudiobook => availableFormats.contains('audiobook');

  BookEdition? get epubEdition => editions.firstWhere((e) => e.format == 'epub', orElse: () => editions.first);
  BookEdition? get audioEdition => editions.firstWhere((e) => e.format == 'audiobook', orElse: () => editions.first);
}

class BookAnnotation {
  const BookAnnotation({
    required this.id,
    required this.workId,
    required this.editionId,
    required this.kind, // 'bookmark', 'highlight', 'note'
    this.cfiRange,
    this.highlightColor,
    this.selectedText,
    this.note,
    this.audioTimestamp,
    this.createdAt,
  });

  factory BookAnnotation.fromJson(Map<String, dynamic> json) => BookAnnotation(
    id: json['id'] as String? ?? '',
    workId: json['work_id'] as String? ?? '',
    editionId: json['edition_id'] as String? ?? '',
    kind: json['kind'] as String? ?? 'bookmark',
    cfiRange: json['cfi_range'] as String?,
    highlightColor: json['highlight_color'] as String?,
    selectedText: json['selected_text'] as String?,
    note: json['note'] as String?,
    audioTimestamp: (json['audio_timestamp'] as num?)?.toDouble(),
    createdAt: (json['created_at'] as num?)?.toDouble(),
  );

  final String id;
  final String workId;
  final String editionId;
  final String kind;
  final String? cfiRange;
  final String? highlightColor;
  final String? selectedText;
  final String? note;
  final double? audioTimestamp;
  final double? createdAt;
}

enum BookDownloadMode { both, epubOnly, audioOnly }

class BookDownloadManifest {
  const BookDownloadManifest({
    required this.workId,
    required this.downloadedAt,
    required this.mode,
    required this.totalBytes,
    this.files = const [],
  });

  factory BookDownloadManifest.fromJson(Map<String, dynamic> json) => BookDownloadManifest(
    workId: json['work_id'] as String? ?? '',
    downloadedAt: (json['downloaded_at'] as num?)?.toDouble() ?? 0.0,
    mode: json['mode'] as String? ?? 'both',
    totalBytes: json['total_bytes'] as int? ?? 0,
    files: (json['files'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );

  final String workId;
  final double downloadedAt;
  final String mode;
  final int totalBytes;
  final List<String> files;

  Map<String, dynamic> toJson() => {
    'work_id': workId,
    'downloaded_at': downloadedAt,
    'mode': mode,
    'total_bytes': totalBytes,
    'files': files,
  };
}

class WorldwideBookResult {
  const WorldwideBookResult({
    required this.source,
    this.externalId,
    required this.title,
    required this.author,
    this.authors = const [],
    this.publishedYear,
    this.coverUrl,
    this.isbns = const [],
    this.editionCount = 1,
    this.languages = const [],
    this.description,
    this.genres = const [],
    this.isLocal = false,
    this.localWorkId,
    this.ownedFormats = const [],
    this.readingPercentage = 0.0,
    this.listeningPercentage = 0.0,
    this.requestId,
    this.requestState,
    this.formatRequested,
    this.acquiredFormats = const [],
    this.acquisitionProgress = 0.0,
  });

  factory WorldwideBookResult.fromJson(Map<String, dynamic> json) => WorldwideBookResult(
    source: json['source'] as String? ?? 'unknown',
    externalId: json['external_id'] as String?,
    title: json['title'] as String? ?? '',
    author: json['author'] as String? ?? '',
    authors: (json['authors'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    publishedYear: (json['published_year'] as num?)?.toInt(),
    coverUrl: json['cover_url'] as String?,
    isbns: (json['isbns'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    editionCount: (json['edition_count'] as num?)?.toInt() ?? 1,
    languages: (json['languages'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    description: json['description'] as String?,
    genres: (json['genres'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    isLocal: (json['is_local'] as bool?) ?? false,
    localWorkId: json['local_work_id'] as String?,
    ownedFormats: (json['owned_formats'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    readingPercentage: (json['reading_percentage'] as num?)?.toDouble() ?? 0.0,
    listeningPercentage: (json['listening_percentage'] as num?)?.toDouble() ?? 0.0,
    requestId: json['request_id'] as String?,
    requestState: json['request_state'] as String?,
    formatRequested: json['format_requested'] as String?,
    acquiredFormats: (json['acquired_formats'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    acquisitionProgress: (json['acquisition_progress'] as num?)?.toDouble() ?? 0.0,
  );

  final String source;
  final String? externalId;
  final String title;
  final String author;
  final List<String> authors;
  final int? publishedYear;
  final String? coverUrl;
  final List<String> isbns;
  final int editionCount;
  final List<String> languages;
  final String? description;
  final List<String> genres;
  final bool isLocal;
  final String? localWorkId;
  final List<String> ownedFormats;
  final double readingPercentage;
  final double listeningPercentage;
  final String? requestId;
  final String? requestState;
  final String? formatRequested;
  final List<String> acquiredFormats;
  final double acquisitionProgress;

  bool get isOwned => isLocal && ownedFormats.isNotEmpty;
  bool get hasEpub => ownedFormats.contains('epub') || acquiredFormats.contains('epub');
  bool get hasAudiobook => ownedFormats.contains('audiobook') || acquiredFormats.contains('audiobook');
  bool get isAcquiring =>
      requestId != null && requestState != null && !const ['available', 'failed', 'imported'].contains(requestState);
}

class BookRequestItem {
  const BookRequestItem({
    required this.id,
    this.workId,
    required this.title,
    required this.author,
    this.isbn,
    required this.formatRequested,
    required this.state,
    this.acquiredFormats = const [],
    this.progressPercentage = 0.0,
    this.errorMessage,
    this.createdAt,
    this.updatedAt,
  });

  factory BookRequestItem.fromJson(Map<String, dynamic> json) => BookRequestItem(
    id: json['id'] as String? ?? '',
    workId: json['work_id'] as String?,
    title: json['title'] as String? ?? '',
    author: json['author'] as String? ?? '',
    isbn: json['isbn'] as String?,
    formatRequested: json['format_requested'] as String? ?? 'paired',
    state: json['state'] as String? ?? 'requested',
    acquiredFormats: (json['acquired_formats'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    progressPercentage: (json['progress_percentage'] as num?)?.toDouble() ?? 0.0,
    errorMessage: json['error_message'] as String?,
    createdAt: (json['created_at'] as num?)?.toDouble(),
    updatedAt: (json['updated_at'] as num?)?.toDouble(),
  );

  final String id;
  final String? workId;
  final String title;
  final String author;
  final String? isbn;
  final String formatRequested;
  final String state;
  final List<String> acquiredFormats;
  final double progressPercentage;
  final String? errorMessage;
  final double? createdAt;
  final double? updatedAt;

  bool get isCompleted => state == 'available' || state == 'imported';
  bool get isFailed => state == 'failed';
  bool get isNeedsReview => state == 'needs_review';
}
