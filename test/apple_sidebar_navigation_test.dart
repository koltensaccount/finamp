import 'package:finamp/components/navigation/apple_sidebar_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppleSidebarNavigation Component Tests', () {
    testWidgets('wide navigation displays all four destinations and settings', (tester) async {
      int? tappedIndex;
      var settingsTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppleSidebarNavigation(
              selectedIndex: 1,
              onDestinationSelected: (index) => tappedIndex = index,
              onSettingsTap: () => settingsTaps++,
            ),
          ),
        ),
      );

      expect(find.text('Music'), findsOneWidget);
      expect(find.text('EXPLORE'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Books'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.text('Home'));
      expect(tappedIndex, 0);

      await tester.tap(find.text('Library'));
      expect(tappedIndex, 1);

      await tester.tap(find.text('Books'));
      expect(tappedIndex, 2);

      await tester.tap(find.text('Search'));
      expect(tappedIndex, 3);

      await tester.tap(find.text('Settings'));
      expect(settingsTaps, 1);
    });

    testWidgets('renders properly in dark mode and light mode', (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: AppleSidebarNavigation(selectedIndex: 0, onDestinationSelected: (_) {}, onSettingsTap: () {}),
            ),
          ),
        );

        expect(find.text('Music'), findsOneWidget);
        expect(find.byType(AppleSidebarNavigation), findsOneWidget);
      }
    });

    testWidgets('selected destination has correct semantic state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppleSidebarNavigation(selectedIndex: 2, onDestinationSelected: (_) {}, onSettingsTap: () {}),
          ),
        ),
      );

      final booksSelected = tester.widget<Semantics>(
        find.ancestor(
          of: find.text('Books'),
          matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true),
        ),
      );
      expect(booksSelected.properties.selected, isTrue);

      final homeSelected = tester.widget<Semantics>(
        find.ancestor(
          of: find.text('Home'),
          matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true),
        ),
      );
      expect(homeSelected.properties.selected, isFalse);
    });
  });
}
