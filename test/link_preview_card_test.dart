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
}
