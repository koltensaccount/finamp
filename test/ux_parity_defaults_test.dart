import 'package:finamp/models/finamp_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shared music gesture contract', () {
    test('new installs offer swipe-to-favorite and add-to-Next-Up', () {
      expect(DefaultSettings.itemSwipeActionLeftToRight, ItemSwipeActions.toggleFavorite);
      expect(DefaultSettings.itemSwipeActionRightToLeft, ItemSwipeActions.addToNextUp);
    });

    test('new swipe enum value is appended without renumbering existing actions', () {
      expect(
        ItemSwipeActions.values,
        [
          ItemSwipeActions.nothing,
          ItemSwipeActions.addToQueue,
          ItemSwipeActions.addToNextUp,
          ItemSwipeActions.playNext,
          ItemSwipeActions.toggleFavorite,
        ],
      );
    });
  });
}
