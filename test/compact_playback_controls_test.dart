import 'package:finamp/components/compact_playback_controls.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact player exposes previous, toggle, next in order at touch size', (tester) async {
    final actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 132,
            child: CompactPlaybackControls(
              isPlaying: false,
              onPrevious: () => actions.add('previous'),
              onTogglePlayback: () => actions.add('toggle'),
              onNext: () => actions.add('next'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final previous = find.byIcon(Icons.skip_previous_rounded);
    final play = find.byIcon(Icons.play_arrow_rounded);
    final next = find.byIcon(Icons.skip_next_rounded);
    expect(tester.getCenter(previous).dx, lessThan(tester.getCenter(play).dx));
    expect(tester.getCenter(play).dx, lessThan(tester.getCenter(next).dx));
    for (final button in find.byType(IconButton).evaluate()) {
      expect(tester.getSize(find.byWidget(button.widget)), const Size(44, 44));
      expect((button.widget as IconButton).tooltip, isNotEmpty);
    }
    await tester.tap(previous);
    await tester.tap(play);
    await tester.tap(next);
    expect(actions, ['previous', 'toggle', 'next']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('playing state exposes pause rather than a second play action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CompactPlaybackControls(isPlaying: true, onPrevious: () {}, onTogglePlayback: () {}, onNext: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
  });
}
