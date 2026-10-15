import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/features/book_viewport.dart';

void main() {
  test('single pages stop at the first and last page', () {
    final pages = BookPageController()..count = 3;
    addTearDown(pages.dispose);
    expect(pages.turn(-1), isFalse);
    expect(pages.turn(1), isTrue);
    expect(pages.page, 1);
    expect(pages.turn(1), isTrue);
    expect(pages.page, 2);
    expect(pages.turn(1), isFalse);
  });
  for (final count in [4, 5]) {
    test('two-page turns stop on the final spread for $count pages', () {
      final pages = BookPageController()
        ..count = count
        ..columns = 2;
      addTearDown(pages.dispose);
      while (pages.turn(1)) {
        expect(pages.page.isEven, isTrue);
      }
      expect(pages.page, count == 4 ? 2 : 4);
      expect(pages.turn(1), isFalse);
      expect(pages.turn(-1), isTrue);
      expect(pages.page, count == 4 ? 0 : 2);
    });
  }
}
