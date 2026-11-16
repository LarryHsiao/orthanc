import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/link_preview_card.dart';

void main() {
  test('a card that fits sits at the anchor', () {
    const expected = 10.0;

    final result = clampCardLeft(anchorX: 10, cardWidth: 300, paneWidth: 800);

    expect(result, expected);
  });

  test('a card near the right edge is pulled back to fit', () {
    const expected = 500.0;

    final result = clampCardLeft(anchorX: 700, cardWidth: 300, paneWidth: 800);

    expect(result, expected);
  });

  test('a card in a pane narrower than itself sits at the left edge', () {
    const expected = 0.0;

    final result = clampCardLeft(anchorX: 50, cardWidth: 300, paneWidth: 200);

    expect(result, expected);
  });

  test('a negative anchor is held at the left edge', () {
    const expected = 0.0;

    final result = clampCardLeft(anchorX: -20, cardWidth: 300, paneWidth: 800);

    expect(result, expected);
  });

  group('cardOrigin', () {
    const card = Size(300, 100);
    const pane = Size(800, 600);

    test('with room below, the card sits under the link cell', () {
      const expected = Offset(40, 120);

      final result = cardOrigin(
        cell: const Rect.fromLTWH(40, 100, 10, 20),
        card: card,
        pane: pane,
      );

      expect(result, expected);
    });

    test('with no room below, the card flips above the link cell', () {
      const expected = Offset(40, 480);

      final result = cardOrigin(
        cell: const Rect.fromLTWH(40, 580, 10, 20),
        card: card,
        pane: pane,
      );

      expect(result, expected);
    });

    test('a card that just fits below stays below', () {
      const expected = Offset(40, 500);

      final result = cardOrigin(
        cell: const Rect.fromLTWH(40, 480, 10, 20),
        card: card,
        pane: pane,
      );

      expect(result, expected);
    });

    test(
      'with room neither below nor above, the card is held inside the pane',
      () {
        const expected = Offset(40, 0);

        final result = cardOrigin(
          cell: const Rect.fromLTWH(40, 40, 10, 20),
          card: const Size(300, 200),
          pane: const Size(800, 150),
        );

        expect(result, expected);
      },
    );

    test('the card is pulled back from the right edge as well', () {
      const expected = Offset(500, 120);

      final result = cardOrigin(
        cell: const Rect.fromLTWH(700, 100, 10, 20),
        card: card,
        pane: pane,
      );

      expect(result, expected);
    });
  });
}
