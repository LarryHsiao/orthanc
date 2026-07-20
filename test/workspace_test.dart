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
}
