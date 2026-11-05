import 'package:finamp/services/catalog_recent_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('new installations do not show hardcoded demo search results', () async {
    expect(await CatalogRecentHistory.load(), isEmpty);
  });

  test('persists real catalog navigation and preserves same-name artists', () async {
    const indie = CatalogRecentItem(
      id: 'b29020d6-5dbf-4c99-b16f-c009f8a712ff',
      title: 'Steve Lacy',
      subtitle: 'Artist',
      kind: 'artist',
    );
    const jazz = CatalogRecentItem(
      id: 'ca9766a0-1c30-43e6-a213-bac1334efc4a',
      title: 'Steve Lacy',
      subtitle: 'Artist',
      kind: 'artist',
    );

    await CatalogRecentHistory.save([indie, jazz]);
    final items = await CatalogRecentHistory.load();
    expect(items.map((item) => item.id), [indie.id, jazz.id]);
    expect(items.map((item) => item.title), ['Steve Lacy', 'Steve Lacy']);
  });

  test('clear permanently removes navigation history', () async {
    await CatalogRecentHistory.save([
      const CatalogRecentItem(id: 'artist-id', title: 'Artist', subtitle: 'Artist', kind: 'artist'),
    ]);
    await CatalogRecentHistory.clear();
    expect(await CatalogRecentHistory.load(), isEmpty);
  });

  test('corrupt persisted entries are ignored', () async {
    SharedPreferences.setMockInitialValues({
      'catalog_recent_items_v1': <String>['not-json', '{"kind":"artist"}'],
    });
    expect(await CatalogRecentHistory.load(), isEmpty);
  });
}
