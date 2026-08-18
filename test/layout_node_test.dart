import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/layout_node.dart';

void main() {
  test('a pane node carries its session id', () {
    const expected = 'a';

    const node = PaneNode(expected);

    expect(node.sessionId, expected);
  });

  test('a split node carries its axis, children and ratios', () {
    const expectedAxis = SplitAxis.row;
    const expectedChildren = [PaneNode('a'), PaneNode('b')];
    const expectedRatios = [0.5, 0.5];

    const node = SplitNode(
      axis: expectedAxis,
      children: expectedChildren,
      ratios: expectedRatios,
    );

    expect(node.axis, expectedAxis);
    expect(node.children, expectedChildren);
    expect(node.ratios, expectedRatios);
  });

  test('pane rects of the same numbers are equal', () {
    const expected = PaneRect(left: 0, top: 0, width: 0.5, height: 1);

    const actual = PaneRect(left: 0, top: 0, width: 0.5, height: 1);

    expect(actual, expected);
  });

  group('PaneRect.zoneAt', () {
    const rect = PaneRect(left: 0.25, top: 0.25, width: 0.5, height: 0.5);

    test('the centre is the dead zone', () {
      const expected = null;

      final zone = rect.zoneAt(0.5, 0.5);

      expect(zone, expected);
    });

    test('a point near the left edge picks left', () {
      const expected = Direction.left;

      final zone = rect.zoneAt(0.26, 0.5);

      expect(zone, expected);
    });

    test('a point near the right edge picks right', () {
      const expected = Direction.right;

      final zone = rect.zoneAt(0.74, 0.5);

      expect(zone, expected);
    });

    test('a point near the top edge picks up', () {
      const expected = Direction.up;

      final zone = rect.zoneAt(0.5, 0.26);

      expect(zone, expected);
    });

    test('a point near the bottom edge picks down', () {
      const expected = Direction.down;

      final zone = rect.zoneAt(0.5, 0.74);

      expect(zone, expected);
    });

    test('exactly at the band boundary still counts as the centre', () {
      const expected = null;

      // Local x = (0.375 - 0.25) / 0.5 = 0.25, exactly dropEdgeBand from
      // the left edge — the comparison is strict, so the boundary itself
      // belongs to the centre, not the edge.
      final zone = rect.zoneAt(0.375, 0.5);

      expect(zone, expected);
    });

    test('a corner picks a deterministic edge, not the centre', () {
      const expected = Direction.left;

      // Local (0, 0) — equidistant from left and up. left wins the tie.
      final zone = rect.zoneAt(0.25, 0.25);

      expect(zone, expected);
    });
  });
}
