import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A real recently-viewed catalog item. Keeping the catalog ID (rather than
/// deduplicating by title) preserves distinct artists with identical names.
class CatalogRecentItem {
  const CatalogRecentItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String subtitle;
  final String kind;
  final String? imageUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'kind': kind,
    if (imageUrl != null) 'imageUrl': imageUrl,
  };

  static CatalogRecentItem? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = value['title'];
    final subtitle = value['subtitle'];
    final kind = value['kind'];
    if (id is! String ||
        id.trim().isEmpty ||
        title is! String ||
        title.trim().isEmpty ||
        subtitle is! String ||
        kind is! String) {
      return null;
    }
    if (kind != 'artist' && kind != 'album' && kind != 'track') return null;
    return CatalogRecentItem(
      id: id,
      title: title,
      subtitle: subtitle,
      kind: kind,
      imageUrl: value['imageUrl'] is String ? value['imageUrl'] as String : null,
    );
  }
}

/// Local-only catalog navigation history; no server writes or account syncing.
class CatalogRecentHistory {
  static const _key = 'catalog_recent_items_v1';
  static const maxItems = 12;
  static int _operationGeneration = 0;

  @visibleForTesting
  static void resetGenerationForTesting() {
    _operationGeneration = 0;
  }

  static Future<List<CatalogRecentItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key) ?? const <String>[];
    final result = <CatalogRecentItem>[];
    for (final raw in stored) {
      try {
        final decoded = jsonDecode(raw);
        final item = CatalogRecentItem.fromJson(decoded);
        if (item != null) result.add(item);
      } catch (_) {
        // A corrupt legacy entry should not break the search screen.
      }
    }
    return result.take(maxItems).toList();
  }

  static Future<void> save(List<CatalogRecentItem> items) async {
    final gen = ++_operationGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (gen != _operationGeneration) return;
    await prefs.setStringList(_key, items.take(maxItems).map((item) => jsonEncode(item.toJson())).toList());
  }

  static Future<void> clear() async {
    final gen = ++_operationGeneration;
    final prefs = await SharedPreferences.getInstance();
    if (gen != _operationGeneration) return;
    await prefs.remove(_key);
  }

  /// Convenience helper to record any viewed catalog entity across screens.
  static Future<void> record(CatalogRecentItem item) async {
    final items = await load();
    items.removeWhere((x) => x.id == item.id && x.kind == item.kind);
    items.insert(0, item);
    await save(items);
  }
}
