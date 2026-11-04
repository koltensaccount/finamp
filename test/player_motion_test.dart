import 'package:finamp/components/navigation/player_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mini-player moves continuously between root and detail anchors', (tester) async {
    const barKey = ValueKey('bar');
    Widget bar() => const SizedBox(key: barKey, height: 54, child: Text('Song · Artist'));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(bottomNavigationBar: MiniPlayerAnchor(child: bar())),
                ),
              ),
              child: const Text('Open'),
            ),
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiniPlayerAnchor(includeBottomSafeArea: false, child: bar()),
                const SizedBox(height: 90),
              ],
            ),
          ),
        ),
      ),
    );
    final start = tester.getTopLeft(find.byKey(barKey)).dy;
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The flying bar is the only painted copy; the route placeholders are offstage.
    final middle = tester.getTopLeft(find.byKey(barKey).last).dy;
    expect(middle, greaterThan(start));
    expect(middle, lessThan(start + 90));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(barKey)).dy, closeTo(start + 90, 0.1));
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(barKey)).dy, closeTo(start, 0.1));
  });

  testWidgets('sheet uses the same geometry forward and backward and respects reduced motion', (tester) async {
    final progress = AnimationController(vsync: tester, value: 0.5);
    addTearDown(progress.dispose);
    Widget app({bool reduced = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: PlayerSheetTransition(animation: progress, child: const SizedBox.expand()),
      ),
    );
    await tester.pumpWidget(app());
    final slide = find.descendant(of: find.byType(PlayerSheetTransition), matching: find.byType(SlideTransition));
    final offset = tester.widget<SlideTransition>(slide).position.value;
    expect(offset.dx, 0);
    expect(offset.dy, inExclusiveRange(0.0, 1.0));
    progress.value = 1;
    await tester.pump();
    progress.value = 0.5;
    await tester.pump();
    expect(tester.widget<SlideTransition>(slide).position.value, offset);
    await tester.pumpWidget(app(reduced: true));
    expect(slide, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
