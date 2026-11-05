import 'package:finamp/components/navigation/apple_sidebar_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wide navigation uses the same four destinations as the compact bar', (tester) async {
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

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);

    await tester.tap(find.text('Books'));
    expect(tappedIndex, 2);

    await tester.tap(find.text('Settings'));
    expect(settingsTaps, 1);
  });
}
