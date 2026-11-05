import 'package:finamp/services/catalog_recent_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CatalogRecentHistory.resetGenerationForTesting();
  });

  group('Catalog Recent History Persistence & Integrity Tests', () {
    test('1. new installations have empty history with no fabricated demo items', () async {
      final items = await CatalogRecentHistory.load();
      expect(items, isEmpty);
    });

    test('2. opening an artist or album records it to history with metadata', () async {
      await CatalogRecentHistory.record(
        const CatalogRecentItem(
          id: 'artist-1',
          title: 'Steve Lacy',
          subtitle: 'Artist',
          kind: 'artist',
          imageUrl: 'https://example.com/steve.jpg',
        ),
      );
      await CatalogRecentHistory.record(
        const CatalogRecentItem(
          id: 'album-1',
          title: 'Gemini Rights',
          subtitle: 'Steve Lacy',
          kind: 'album',
          imageUrl: 'https://example.com/gemini.jpg',
        ),
      );

      final items = await CatalogRecentHistory.load();
      expect(items.length, 2);
      expect(items[0].id, 'album-1');
      expect(items[0].kind, 'album');
      expect(items[0].imageUrl, 'https://example.com/gemini.jpg');
      expect(items[1].id, 'artist-1');
      expect(items[1].kind, 'artist');
    });

    test('3. history survives restarting the application (persists to SharedPreferences)', () async {
      await CatalogRecentHistory.save([
        const CatalogRecentItem(id: 'artist-persisted', title: 'Kendrick Lamar', subtitle: 'Artist', kind: 'artist'),
      ]);

      // Re-load as if the app was restarted fresh
      final loaded = await CatalogRecentHistory.load();
      expect(loaded.length, 1);
      expect(loaded.first.id, 'artist-persisted');
      expect(loaded.first.title, 'Kendrick Lamar');
    });

    test('4. history is capped strictly at maxItems (12)', () async {
      for (var i = 0; i < 20; i++) {
        await CatalogRecentHistory.record(
          CatalogRecentItem(id: 'item-$i', title: 'Title $i', subtitle: 'Subtitle $i', kind: 'album'),
        );
      }

      final items = await CatalogRecentHistory.load();
      expect(items.length, CatalogRecentHistory.maxItems);
      expect(items.first.id, 'item-19');
      expect(items.last.id, 'item-8');
    });

    test('5. reopening an existing item moves it to the top without duplicating', () async {
      const item1 = CatalogRecentItem(id: '1', title: 'First', subtitle: 'A', kind: 'artist');
      const item2 = CatalogRecentItem(id: '2', title: 'Second', subtitle: 'B', kind: 'artist');
      const item3 = CatalogRecentItem(id: '3', title: 'Third', subtitle: 'C', kind: 'artist');

      await CatalogRecentHistory.record(item1);
      await CatalogRecentHistory.record(item2);
      await CatalogRecentHistory.record(item3);

      var items = await CatalogRecentHistory.load();
      expect(items.map((e) => e.id), ['3', '2', '1']);

      // Reopen item1
      await CatalogRecentHistory.record(item1);
      items = await CatalogRecentHistory.load();
      expect(items.map((e) => e.id), ['1', '3', '2']);
      expect(items.length, 3);
    });

    test('6. clearing history permanently removes persisted entries', () async {
      await CatalogRecentHistory.save([const CatalogRecentItem(id: 'a', title: 'A', subtitle: 'A', kind: 'artist')]);
      expect(await CatalogRecentHistory.load(), isNotEmpty);

      await CatalogRecentHistory.clear();
      expect(await CatalogRecentHistory.load(), isEmpty);
    });

    test('7. corrupt and invalid entries are ignored and do not crash load', () async {
      SharedPreferences.setMockInitialValues({
        'catalog_recent_items_v1': <String>[
          'not valid json',
          '{"kind":"artist"}', // missing id and title
          '{"id":"","title":"No ID","subtitle":"sub","kind":"artist"}', // empty id
          '{"id":"123","title":"","subtitle":"sub","kind":"artist"}', // empty title
          '{"id":"valid-1","title":"Valid","subtitle":"Sub","kind":"artist"}',
        ],
      });

      final items = await CatalogRecentHistory.load();
      expect(items.length, 1);
      expect(items.first.id, 'valid-1');
    });

    test('8. two artists with identical names remain distinct using canonical IDs', () async {
      const rbSteve = CatalogRecentItem(
        id: 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
        title: 'Steve Lacy',
        subtitle: 'R&B Musician',
        kind: 'artist',
      );
      const jazzSteve = CatalogRecentItem(
        id: 'ca9766a0-1c30-43e6-a213-bac1334efc4a',
        title: 'Steve Lacy',
        subtitle: 'Jazz Saxophonist',
        kind: 'artist',
      );

      await CatalogRecentHistory.record(rbSteve);
      await CatalogRecentHistory.record(jazzSteve);

      final items = await CatalogRecentHistory.load();
      expect(items.length, 2);
      expect(items[0].id, jazzSteve.id);
      expect(items[1].id, rbSteve.id);
      expect(items[0].title, equals(items[1].title));
    });

    test('9. asynchronous clear invalidates in-flight older saves', () async {
      // Simulate race condition where clear is invoked while a save was queued
      final saveFuture = CatalogRecentHistory.save([
        const CatalogRecentItem(id: 'stale', title: 'Stale', subtitle: 'Stale', kind: 'artist'),
      ]);
      final clearFuture = CatalogRecentHistory.clear();

      await Future.wait([saveFuture, clearFuture]);
      final items = await CatalogRecentHistory.load();
      expect(items, isEmpty);
    });
  });
}
