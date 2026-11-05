import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

import '../models/jellyfin_models.dart';
import 'favorite_provider.dart';
import 'finamp_settings_helper.dart';
import 'jellyfin_api_helper.dart';

class LikedSongsService extends ChangeNotifier {
  LikedSongsService({JellyfinApiHelper? apiHelper})
    : _jellyfinApiHelper = apiHelper ?? GetIt.instance<JellyfinApiHelper>();

  final JellyfinApiHelper _jellyfinApiHelper;

  List<BaseItemDto> _tracks = [];
  bool _loading = false;
  String? _error;
  DateTime? _lastSynced;

  List<BaseItemDto> get tracks => List.unmodifiable(_tracks);
  int get count => _tracks.length;
  bool get isLoading => _loading;
  String? get error => _error;
  DateTime? get lastSynced => _lastSynced;

  /// Pulls favorite audio tracks directly from the Jellyfin server.
  Future<void> syncWithJellyfin({bool force = false}) async {
    if (_loading && !force) return;

    if (FinampSettingsHelper.finampSettings.isOffline) {
      // Offline mode: keep current cached tracks
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Query Jellyfin server for all favorite audio tracks
      final items = await _jellyfinApiHelper.getItems(
        includeItemTypes: 'Audio',
        recursive: true,
        filters: 'IsFavorite',
        isFavorite: true,
        sortBy: 'DateCreated,SortName',
        sortOrder: 'Descending',
      );

      final resultList = items ?? <BaseItemDto>[];
      for (final item in resultList) {
        item.userData ??= UserItemDataDto(playbackPositionTicks: 0, playCount: 0, isFavorite: true, played: false);
        item.userData!.isFavorite = true;
      }
      _tracks = resultList;
      _lastSynced = DateTime.now();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Called whenever an item's favorite status changes anywhere in Finamp.
  void onFavoriteChanged(BaseItemDto item, bool isFavorite) {
    if (isFavorite) {
      final existingIndex = _tracks.indexWhere((t) => t.id == item.id);
      item.userData ??= UserItemDataDto(playbackPositionTicks: 0, playCount: 0, isFavorite: true, played: false);
      item.userData!.isFavorite = true;

      if (existingIndex >= 0) {
        _tracks[existingIndex] = item;
      } else {
        _tracks.insert(0, item);
      }
    } else {
      _tracks.removeWhere((t) => t.id == item.id);
    }
    notifyListeners();
  }

  /// Toggles favorite status on Jellyfin and updates local list.
  Future<void> toggleLike(BaseItemDto item) async {
    final currentlyLiked = _tracks.any((t) => t.id == item.id) || (item.userData?.isFavorite ?? false);
    final targetFavorite = !currentlyLiked;

    // Optimistic local update
    onFavoriteChanged(item, targetFavorite);

    try {
      if (targetFavorite) {
        await _jellyfinApiHelper.addFavorite(item.id);
      } else {
        await _jellyfinApiHelper.removeFavorite(item.id);
      }
      if (GetIt.instance.isRegistered<ProviderContainer>()) {
        final container = GetIt.instance<ProviderContainer>();
        container.read(isFavoriteProvider(item).notifier).updateState(targetFavorite);
      }
    } catch (e) {
      // Rollback on failure
      onFavoriteChanged(item, currentlyLiked);
      rethrow;
    }
  }
}

final likedSongsProvider = ChangeNotifierProvider<LikedSongsService>((ref) {
  final service = GetIt.instance<LikedSongsService>();
  return service;
});
