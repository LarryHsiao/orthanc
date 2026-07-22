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

    test('recurses past a split holding neither the focused pane nor a '
        'matching axis, to insert beside it deep in the tree', () {
      final expected = ['a', 'b', 'c', 'd'];

      // a | (b over c), then splitting 'c' along the column axis — the
      // same axis its own parent split already runs. The row root holds
      // neither 'c' as a direct child nor a matching axis, so the split
      // must recurse into the root's children to find where 'c' actually
      // lives, then land 'd' as its sibling inside that nested split.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.row, newSessionId: 'b')
          .focus('b')
          .split(axis: SplitAxis.column, newSessionId: 'c')
          .split(axis: SplitAxis.column, newSessionId: 'd');

      expect(workspace.sessionIds, expected);
      final root = workspace.root as SplitNode;
      expect(root.axis, SplitAxis.row);
      final nested = root.children[1] as SplitNode;
      expect(nested.axis, SplitAxis.column);
      expect(nested.children.length, 3);
      expect((nested.children[1] as PaneNode).sessionId, 'c');
      expect((nested.children[2] as PaneNode).sessionId, 'd');
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

    test(
      'clears its own column\'s collapse entry when the collapsed pane closes',
      () {
        final expected = <String>{};

        final workspace = Workspace.single('a')
            .split(axis: SplitAxis.column, newSessionId: 'b')
            .split(axis: SplitAxis.column, newSessionId: 'c')
            .toggleCollapse('b')
            .close('b');

        expect(workspace!.collapsedIds, expected);
      },
    );

    test('leaves an unrelated column\'s collapse entry alone', () {
      final expected = {'d'};

      // (a over b) | (c over d) — collapse the right column to 'd', then
      // close a pane entirely inside the left column.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .focus('a')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .split(axis: SplitAxis.column, newSessionId: 'd')
          .toggleCollapse('d')
          .close('b');

      expect(workspace!.collapsedIds, expected);
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

  group('Workspace.toggleCollapse', () {
    test('collapses a pane whose direct parent is a 2-row column', () {
      final expected = {'b'};

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.column, newSessionId: 'b').toggleCollapse('b');

      expect(workspace.collapsedIds, expected);
    });

    test('toggling the already-collapsed pane restores even shares', () {
      final expected = <String>{};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('b')
          .toggleCollapse('b');

      expect(workspace.collapsedIds, expected);
    });

    test('collapsing a different sibling replaces the column\'s entry', () {
      final expected = {'c'};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .split(axis: SplitAxis.column, newSessionId: 'c')
          .toggleCollapse('b')
          .toggleCollapse('c');

      expect(workspace.collapsedIds, expected);
    });

    test('focuses the pane it collapses', () {
      const expected = 'b';

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.column, newSessionId: 'b').toggleCollapse('b');

      expect(workspace.focusedId, expected);
    });

    test('no-ops on a pane inside a row split (side by side)', () {
      final expected = <String>{};

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b').toggleCollapse('b');

      expect(workspace.collapsedIds, expected);
    });

    test('no-ops on a lone pane with no split at all', () {
      final expected = <String>{};

      final workspace = Workspace.single('a').toggleCollapse('a');

      expect(workspace.collapsedIds, expected);
    });

    test('two different columns collapse independently', () {
      final expected = {'b', 'd'};

      // (a over b) | (c over d) — a row split holding two columns.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .focus('a')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .split(axis: SplitAxis.column, newSessionId: 'd')
          .toggleCollapse('b')
          .toggleCollapse('d');

      expect(workspace.collapsedIds, expected);
    });
  });

  group('Workspace.collapsibleIds', () {
    test('is empty for a lone pane', () {
      final expected = <String>{};

      final ids = Workspace.single('a').collapsibleIds;

      expect(ids, expected);
    });

    test('excludes panes in a row split', () {
      final expected = <String>{};

      final ids = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b').collapsibleIds;

      expect(ids, expected);
    });

    test('includes every direct child of a 2+-row column', () {
      final expected = {'a', 'b'};

      final ids = Workspace.single(
        'a',
      ).split(axis: SplitAxis.column, newSessionId: 'b').collapsibleIds;

      expect(ids, expected);
    });
  });

  group('Workspace.split clearing collapse', () {
    test('splitting into an already-collapsed column reveals the new pane', () {
      final expected = <String>{};

      // Column of (a over b), collapsed to 'a'. Focusing 'a' and splitting
      // it along the column axis inserts 'c' as a new sibling row in the
      // same column — which must reveal the whole column again.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('a')
          .split(axis: SplitAxis.column, newSessionId: 'c');

      expect(workspace.collapsedIds, expected);
    });

    test('splitting a different, uncollapsed column leaves collapse alone', () {
      final expected = {'b'};

      // (a over b), collapsed to 'b'. A fresh row split off the whole tree
      // wraps the root in a new row — 'b' stays exactly where it was, in
      // the same column, so its collapse survives untouched.
      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('b')
          .split(axis: SplitAxis.row, newSessionId: 'c');

      expect(workspace.collapsedIds, expected);
    });
  });

  group('Workspace.reveal', () {
    test('clears the entry hiding a sibling in the same column', () {
      final expected = <String>{};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .toggleCollapse('a')
          .reveal('b');

      expect(workspace.collapsedIds, expected);
    });

    test('is a no-op when the target is not hidden by any collapse', () {
      final expected = <String>{};

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.column, newSessionId: 'b').reveal('b');

      expect(workspace.collapsedIds, expected);
    });

    test('leaves a different column\'s collapse untouched', () {
      final expected = {'d'};

      final workspace = Workspace.single('a')
          .split(axis: SplitAxis.column, newSessionId: 'b')
          .focus('a')
          .split(axis: SplitAxis.row, newSessionId: 'c')
          .split(axis: SplitAxis.column, newSessionId: 'd')
          .toggleCollapse('d')
          .reveal('b');

      expect(workspace.collapsedIds, expected);
    });
  });
}
