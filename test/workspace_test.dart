import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/layout_node.dart';
import 'package:orthanc/workspace.dart';

void main() {
  group('Workspace.single', () {
    test('holds one pane, focused', () {
      const expectedId = 'a';

      final workspace = Workspace.single(expectedId);

      expect(workspace.root, isA<PaneNode>());
      expect((workspace.root as PaneNode).sessionId, expectedId);
      expect(workspace.focusedId, expectedId);
    });
  });

  group('Workspace.split', () {
    test('wraps a lone pane in a split holding both', () {
      final expected = ['a', 'b'];

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b');

      expect(workspace.root, isA<SplitNode>());
      final root = workspace.root as SplitNode;
      expect(root.axis, SplitAxis.row);
      expect(workspace.sessionIds, expected);
    });

    test('focuses the newly created pane', () {
      const expected = 'b';

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: expected);

      expect(workspace.focusedId, expected);
    });

    test('inserts as a sibling when the parent runs the same axis', () {
      final expected = ['a', 'c', 'b'];

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .focus('a')
          .split(axis: SplitAxis.row, newSessionId: 'c');

      expect(workspace.root, isA<SplitNode>());
      expect((workspace.root as SplitNode).children.length, 3);
      expect(workspace.sessionIds, expected);
    });

    test('wraps the focused pane when the parent runs the other axis', () {
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .focus('a')
          .split(axis: SplitAxis.column, newSessionId: 'c');

      final root = workspace.root as SplitNode;
      expect(root.axis, SplitAxis.row);
      expect(root.children.length, 2);
      expect(root.children.first, isA<SplitNode>());
      expect((root.children.first as SplitNode).axis, SplitAxis.column);
    });

    test('redistributes ratios evenly across the split', () {
      final expected = [1 / 3, 1 / 3, 1 / 3];

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.row, newSessionId: 'c');

      expect((workspace.root as SplitNode).ratios, expected);
    });
  });

  group('Workspace.close', () {
    test('returns null when the last pane closes', () {
      const expected = null;

      final actual = Workspace.single('a').close('a');

      expect(actual, expected);
    });

    test('removes the pane and leaves the others', () {
      final expected = ['a', 'c'];

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .close('b');

      expect(workspace!.sessionIds, expected);
    });

    test('dissolves a split left holding a single child', () {
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c')
          .close('c');

      // 'b' and 'c' shared a column inside the row; removing 'c' must leave
      // 'b' hoisted directly into the row, not wrapped in a one-child split.
      final root = workspace!.root as SplitNode;
      expect(root.children.length, 2);
      expect(root.children[1], isA<PaneNode>());
      expect((root.children[1] as PaneNode).sessionId, 'b');
    });

    test('collapses the tree to a bare pane when one session remains', () {
      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b').close('b');

      expect(workspace!.root, isA<PaneNode>());
      expect((workspace.root as PaneNode).sessionId, 'a');
    });

    test('moves focus off the closed pane', () {
      const expected = 'a';

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b').close('b');

      expect(workspace!.focusedId, expected);
    });

    test('leaves focus alone when another pane closes', () {
      const expected = 'c';

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .close('a');

      expect(workspace!.focusedId, expected);
    });
  });

  group('Workspace.paneRects', () {
    test('gives a lone pane the whole window', () {
      const expected = PaneRect(left: 0, top: 0, width: 1, height: 1);

      final rects = Workspace.single('a').paneRects();

      expect(rects['a'], expected);
    });

    test('halves the width for a row split', () {
      const expectedLeft = PaneRect(left: 0, top: 0, width: 0.5, height: 1);
      const expectedRight = PaneRect(left: 0.5, top: 0, width: 0.5, height: 1);

      final rects = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b').paneRects();

      expect(rects['a'], expectedLeft);
      expect(rects['b'], expectedRight);
    });

    test('halves the height for a column split', () {
      const expectedTop = PaneRect(left: 0, top: 0, width: 1, height: 0.5);
      const expectedBottom = PaneRect(left: 0, top: 0.5, width: 1, height: 0.5);

      final rects = Workspace.single(
        'a',
      ).split(axis: SplitAxis.column, newSessionId: 'b').paneRects();

      expect(rects['a'], expectedTop);
      expect(rects['b'], expectedBottom);
    });

    test('nests a column inside a row', () {
      const expected = PaneRect(left: 0.5, top: 0.5, width: 0.5, height: 0.5);

      final rects = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c')
          .paneRects();

      expect(rects['c'], expected);
    });
  });

  group('Workspace.neighbour', () {
    test('finds the pane to the right', () {
      const expected = 'b';

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b').focus('a');

      expect(workspace.neighbour(Direction.right), expected);
    });

    test('finds the pane to the left', () {
      const expected = 'a';

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b');

      expect(workspace.neighbour(Direction.left), expected);
    });

    test('finds the pane below', () {
      const expected = 'b';

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.column, newSessionId: 'b').focus('a');

      expect(workspace.neighbour(Direction.down), expected);
    });

    test('returns null at the edge', () {
      const expected = null;

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b').focus('a');

      expect(workspace.neighbour(Direction.left), expected);
    });

    test('returns null for a lone pane in every direction', () {
      final workspace = Workspace.single('a');

      expect(workspace.neighbour(Direction.left), null);
      expect(workspace.neighbour(Direction.right), null);
      expect(workspace.neighbour(Direction.up), null);
      expect(workspace.neighbour(Direction.down), null);
    });

    test('crosses into a nested split', () {
      const expected = 'b';

      // a | (b over c) — moving right from 'a' meets 'b', the upper of the two.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c')
          .focus('a');

      expect(workspace.neighbour(Direction.right), expected);
    });
  });

  group('Workspace.resizeSplit', () {
    test('moves share from one side of the divider to the other', () {
      final expected = [0.6, 0.4];

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b');
      final resized = workspace.resizeSplit(
        split: workspace.root,
        dividerIndex: 0,
        delta: 0.1,
      );

      expect((resized.root as SplitNode).ratios, expected);
    });

    test('refuses to shrink a pane past a minimum share', () {
      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b');
      final resized = workspace.resizeSplit(
        split: workspace.root,
        dividerIndex: 0,
        delta: 0.9,
      );

      final ratios = (resized.root as SplitNode).ratios;
      expect(ratios[1], greaterThanOrEqualTo(minPaneRatio));
      expect(ratios[0] + ratios[1], closeTo(1, 0.0001));
    });

    test('leaves other splits untouched', () {
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c');
      final nested = (workspace.root as SplitNode).children[1];

      final resized = workspace.resizeSplit(
        split: nested,
        dividerIndex: 0,
        delta: 0.1,
      );

      expect((resized.root as SplitNode).ratios, [0.5, 0.5]);
    });

    test('a dragged ratio survives closing an unrelated pane', () {
      final expected = [0.6, 0.4];

      // a | (b over c) — the root divider is dragged, then 'c' closes inside
      // the nested split. The root loses no child of its own, so its dragged
      // ratios must come through untouched rather than re-evened.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c');
      final resized = workspace.resizeSplit(
        split: workspace.root,
        dividerIndex: 0,
        delta: 0.1,
      );
      final closed = resized.close('c');

      expect((closed!.root as SplitNode).ratios, expected);
    });

    test(
      'when a split loses a child, the survivors keep their relative proportions',
      () {
        final expected = [8 / 13, 5 / 13];

        // a | b | c, dragged uneven, then 'b' (the middle child) closes. The
        // survivors 'a' and 'c' should share out the space in proportion to
        // the ratios they already held, not be re-evened.
        final workspace = Workspace.single('a')
            .split(axis: SplitAxis.row, newSessionId: 'b')
            .split(axis: SplitAxis.row, newSessionId: 'c');
        final resized = workspace.resizeSplit(
          split: workspace.root,
          dividerIndex: 0,
          delta: 0.2,
        );
        final closed = resized.close('b');

        final ratios = (closed!.root as SplitNode).ratios;
        expect(ratios[0], closeTo(expected[0], 0.0001));
        expect(ratios[1], closeTo(expected[1], 0.0001));
        expect(ratios[0] + ratios[1], closeTo(1, 0.0001));
      },
    );
  });
}
