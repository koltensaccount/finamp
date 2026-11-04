import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/book_models.dart';
import 'books_api_client.dart';

class BooksDownloadService {
  BooksDownloadService({required BooksApiClient apiClient, Directory? baseDirectory})
      : _apiClient = apiClient,
        _baseDirectoryOverride = baseDirectory;

  final BooksApiClient _apiClient;
  final Directory? _baseDirectoryOverride;

  final ValueNotifier<Set<String>> downloadedWorkIds = ValueNotifier<Set<String>>({});
  final ValueNotifier<Map<String, double>> downloadProgress = ValueNotifier<Map<String, double>>({});
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final dir = await _getStorageDir();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final entries = dir.listSync();
      final ids = <String>{};
      for (final entity in entries) {
        if (entity is Directory) {
          final workId = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
          final manifestFile = File('${entity.path}/download_manifest.json');
          final epubFile = File('${entity.path}/book.epub');
          final audioDir = Directory('${entity.path}/audio');
          // Check if valid download exists (either manifest or book.epub or audio files)
          if (manifestFile.existsSync() || epubFile.existsSync() || (audioDir.existsSync() && audioDir.listSync().isNotEmpty)) {
            ids.add(workId);
          }
        } else if (entity is File && entity.path.endsWith('.epub')) {
          // Backward compatibility with Phase 1 flat storage
          final fileName = entity.uri.pathSegments.last;
          final workId = fileName.replaceAll('.epub', '');
          ids.add(workId);
        }
      }
      downloadedWorkIds.value = ids;
      _isInitialized = true;
    } catch (e) {
      debugPrint('BooksDownloadService init error: $e');
    }
  }

  Future<Directory> _getStorageDir() async {
    if (_baseDirectoryOverride != null) {
      final d = Directory('${_baseDirectoryOverride.path}/books');
      if (!await d.exists()) await d.create(recursive: true);
      return d;
    }
    final baseDir = Platform.isIOS
        ? await getApplicationDocumentsDirectory()
        : await getApplicationSupportDirectory();
    final booksDir = Directory('${baseDir.path}/books');
    if (!await booksDir.exists()) {
      await booksDir.create(recursive: true);
    }
    return booksDir;
  }

  bool isDownloaded(String workId) => downloadedWorkIds.value.contains(workId);

  bool isDownloading(String workId) => downloadProgress.value.containsKey(workId);

  Future<Directory> _getWorkDir(String workId) async {
    final root = await _getStorageDir();
    return Directory('${root.path}/$workId');
  }

  Future<bool> hasOfflineEpub(String workId) async {
    final file = await getLocalEpubFile(workId);
    return file != null && await file.exists() && (await file.length()) > 512;
  }

  Future<bool> hasOfflineAudio(String workId) async {
    final workDir = await _getWorkDir(workId);
    final audioDir = Directory('${workDir.path}/audio');
    if (!await audioDir.exists()) return false;
    final files = audioDir.listSync();
    return files.any((f) => f is File && f.lengthSync() > 1024);
  }

  Future<File?> getLocalEpubFile(String workId) async {
    final workDir = await _getWorkDir(workId);
    final newFile = File('${workDir.path}/book.epub');
    if (await newFile.exists()) return newFile;

    // Phase 1 flat file backward compatibility
    final root = await _getStorageDir();
    final flatFile = File('${root.path}/$workId.epub');
    if (await flatFile.exists()) return flatFile;

    return null;
  }

  Future<Uint8List?> getLocalEpubBytes(String workId) async {
    final file = await getLocalEpubFile(workId);
    if (file != null && await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  Future<File?> getLocalAudioFile(String workId, int trackNumber) async {
    final workDir = await _getWorkDir(workId);
    final audioDir = Directory('${workDir.path}/audio');
    if (!await audioDir.exists()) return null;

    final files = audioDir.listSync();
    for (final f in files) {
      if (f is File && f.path.contains('track_$trackNumber.')) {
        return f;
      }
    }
    return null;
  }

  Future<File?> getLocalCoverFile(String workId) async {
    final workDir = await _getWorkDir(workId);
    final file = File('${workDir.path}/cover.jpg');
    if (await file.exists()) return file;
    return null;
  }

  Future<BookDetail?> getLocalBookDetail(String workId) async {
    try {
      final workDir = await _getWorkDir(workId);
      final metaFile = File('${workDir.path}/metadata.json');
      if (await metaFile.exists()) {
        final content = await metaFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        return BookDetail.fromJson(json);
      }
    } catch (e) {
      debugPrint('Error reading local book detail for $workId: $e');
    }
    return null;
  }

  Future<List<BookSummary>> listDownloadedBooks() async {
    final result = <BookSummary>[];
    try {
      final root = await _getStorageDir();
      final entries = root.listSync();
      for (final entity in entries) {
        if (entity is Directory) {
          final workId = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
          final metaFile = File('${entity.path}/metadata.json');
          if (await metaFile.exists()) {
            final content = await metaFile.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final detail = BookDetail.fromJson(json);
            final coverFile = File('${entity.path}/cover.jpg');
            result.add(BookSummary(
              id: detail.id,
              title: detail.title,
              author: detail.author,
              description: detail.description,
              genres: detail.genres,
              seriesName: detail.seriesName,
              seriesOrder: detail.seriesOrder,
              coverUrl: coverFile.existsSync() ? 'file://${coverFile.path}' : detail.coverUrl,
              availableFormats: detail.availableFormats,
              isPaired: detail.isPaired,
              progress: detail.progress,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('Error listing downloaded books: $e');
    }
    return result;
  }

  Future<int> getTotalStorageBytes() async {
    int total = 0;
    try {
      final root = await _getStorageDir();
      if (await root.exists()) {
        for (final f in root.listSync(recursive: true)) {
          if (f is File) {
            total += f.lengthSync();
          }
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> downloadWork(
    String workId, {
    BookDownloadMode mode = BookDownloadMode.both,
    BookDetail? bookDetail,
  }) async {
    if (isDownloading(workId)) return;
    downloadProgress.value = {...downloadProgress.value, workId: 0.05};

    final workDir = await _getWorkDir(workId);
    try {
      // 1. Get metadata
      final detail = bookDetail ?? await _apiClient.getBook(workId);
      if (!await workDir.exists()) {
        await workDir.create(recursive: true);
      }

      // Save metadata.json
      final metaFile = File('${workDir.path}/metadata.json');
      await metaFile.writeAsString(jsonEncode({
        'id': detail.id,
        'title': detail.title,
        'author': detail.author,
        'description': detail.description,
        'genres': detail.genres,
        'series_name': detail.seriesName,
        'series_order': detail.seriesOrder,
        'cover_url': detail.coverUrl,
        'available_formats': detail.availableFormats,
        'is_paired': detail.isPaired,
        'progress': detail.progress.toJson(),
        'editions': detail.editions.map((e) => {
          'id': e.id,
          'work_id': e.workId,
          'format': e.format,
          'title': e.title,
          'publisher': e.publisher,
          'published_year': e.publishedYear,
          'language': e.language,
          'isbn': e.isbn,
          'chapters': e.chapters.map((c) => {
            'id': c.id,
            'edition_id': c.editionId,
            'index_num': c.indexNum,
            'title': c.title,
            'start_seconds': c.startSeconds,
            'end_seconds': c.endSeconds,
            'epub_cfi': c.epubCfi,
          }).toList(),
          'assets': e.assets.map((a) => {
            'id': a.id,
            'edition_id': a.editionId,
            'kind': a.kind,
            'format': a.format,
            'duration_seconds': a.durationSeconds,
            'track_number': a.trackNumber,
          }).toList(),
        }).toList(),
        'alignment': detail.alignment,
      }));

      final savedFiles = <String>['metadata.json'];
      int totalBytes = metaFile.lengthSync();

      // 2. Download Cover artwork
      if (detail.coverUrl != null && detail.coverUrl!.isNotEmpty) {
        try {
          final coverBytes = await _apiClient.downloadCoverBytes(workId);
          if (coverBytes.isNotEmpty) {
            final coverFile = File('${workDir.path}/cover.jpg');
            await coverFile.writeAsBytes(coverBytes);
            savedFiles.add('cover.jpg');
            totalBytes += coverBytes.length;
          }
        } catch (e) {
          debugPrint('Optional cover download failed for $workId: $e');
        }
      }
      downloadProgress.value = {...downloadProgress.value, workId: 0.25};

      // 3. Download EPUB
      if (detail.hasEpub && mode != BookDownloadMode.audioOnly) {
        final epubBytes = await _apiClient.downloadEpub(workId);
        // Strict Validation: must be non-empty and start with ZIP magic bytes PK\x03\x04
        if (epubBytes.length < 512 || epubBytes[0] != 0x50 || epubBytes[1] != 0x4B) {
          throw FormatException('Downloaded EPUB for $workId is corrupt or invalid zip');
        }
        final epubFile = File('${workDir.path}/book.epub');
        await epubFile.writeAsBytes(epubBytes);
        savedFiles.add('book.epub');
        totalBytes += epubBytes.length;
      }
      downloadProgress.value = {...downloadProgress.value, workId: 0.60};

      // 4. Download Audiobook Tracks
      if (detail.hasAudiobook && mode != BookDownloadMode.epubOnly) {
        final audioEd = detail.audioEdition;
        if (audioEd != null && audioEd.assets.isNotEmpty) {
          final audioDir = Directory('${workDir.path}/audio');
          if (!await audioDir.exists()) await audioDir.create(recursive: true);

          final totalTracks = audioEd.assets.length;
          for (int i = 0; i < totalTracks; i++) {
            final asset = audioEd.assets[i];
            final tr = asset.trackNumber ?? (i + 1);
            final ext = asset.format?.toLowerCase().contains('flac') == true ? 'flac' : 'mp3';
            final trackBytes = await _apiClient.downloadAudioTrack(workId, tr);
            if (trackBytes.isEmpty) {
              throw FormatException('Downloaded audio track $tr for $workId was empty');
            }
            final trackFile = File('${audioDir.path}/track_$tr.$ext');
            await trackFile.writeAsBytes(trackBytes);
            savedFiles.add('audio/track_$tr.$ext');
            totalBytes += trackBytes.length;

            final prog = 0.60 + (0.35 * ((i + 1) / totalTracks));
            downloadProgress.value = {...downloadProgress.value, workId: prog};
          }
        }
      }

      // 5. Write download_manifest.json
      final manifest = BookDownloadManifest(
        workId: workId,
        downloadedAt: DateTime.now().millisecondsSinceEpoch / 1000.0,
        mode: mode.name,
        totalBytes: totalBytes,
        files: savedFiles,
      );
      final manifestFile = File('${workDir.path}/download_manifest.json');
      await manifestFile.writeAsString(jsonEncode(manifest.toJson()));

      final newIds = Set<String>.from(downloadedWorkIds.value)..add(workId);
      downloadedWorkIds.value = newIds;
    } catch (e) {
      // Clean up partially downloaded directory on failure to avoid leaving corrupted files
      if (await workDir.exists()) {
        try {
          await workDir.delete(recursive: true);
        } catch (_) {}
      }
      rethrow;
    } finally {
      final map = Map<String, double>.from(downloadProgress.value);
      map.remove(workId);
      downloadProgress.value = map;
    }
  }

  Future<void> deleteWork(String workId) async {
    try {
      final workDir = await _getWorkDir(workId);
      if (await workDir.exists()) {
        await workDir.delete(recursive: true);
      }
      // Also delete flat file if present
      final root = await _getStorageDir();
      final flat = File('${root.path}/$workId.epub');
      if (await flat.exists()) await flat.delete();

      final newIds = Set<String>.from(downloadedWorkIds.value)..remove(workId);
      downloadedWorkIds.value = newIds;
    } catch (e) {
      debugPrint('BooksDownloadService delete error: $e');
    }
  }
}
