import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'books_api_client.dart';

class BooksDownloadService {
  BooksDownloadService({required BooksApiClient apiClient}) : _apiClient = apiClient;

  final BooksApiClient _apiClient;
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
      final files = dir.listSync();
      final ids = <String>{};
      for (final entity in files) {
        if (entity is File && entity.path.endsWith('.epub')) {
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
    final baseDir = Platform.isIOS
        ? await getApplicationDocumentsDirectory()
        : await getApplicationSupportDirectory();
    final booksDir = Directory('${baseDir.path}/books');
    if (!await booksDir.exists()) {
      await booksDir.create(recursive: true);
    }
    return booksDir;
  }

  bool isDownloaded(String workId) {
    return downloadedWorkIds.value.contains(workId);
  }

  bool isDownloading(String workId) {
    return downloadProgress.value.containsKey(workId);
  }

  Future<File?> getLocalEpubFile(String workId) async {
    final dir = await _getStorageDir();
    final file = File('${dir.path}/$workId.epub');
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  Future<Uint8List?> getLocalEpubBytes(String workId) async {
    final file = await getLocalEpubFile(workId);
    if (file != null) {
      return await file.readAsBytes();
    }
    return null;
  }

  Future<void> downloadWork(String workId) async {
    if (isDownloaded(workId)) return;
    downloadProgress.value = {...downloadProgress.value, workId: 0.1};
    try {
      final bytes = await _apiClient.downloadEpub(workId);
      downloadProgress.value = {...downloadProgress.value, workId: 0.8};

      final dir = await _getStorageDir();
      final file = File('${dir.path}/$workId.epub');
      await file.writeAsBytes(bytes);

      final newIds = Set<String>.from(downloadedWorkIds.value)..add(workId);
      downloadedWorkIds.value = newIds;
    } finally {
      final map = Map<String, double>.from(downloadProgress.value);
      map.remove(workId);
      downloadProgress.value = map;
    }
  }

  Future<void> deleteWork(String workId) async {
    try {
      final file = await getLocalEpubFile(workId);
      if (file != null && await file.exists()) {
        await file.delete();
      }
      final newIds = Set<String>.from(downloadedWorkIds.value)..remove(workId);
      downloadedWorkIds.value = newIds;
    } catch (e) {
      debugPrint('BooksDownloadService delete error: $e');
    }
  }
}
