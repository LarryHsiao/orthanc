import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/layout_node.dart';
import 'package:orthanc/workspace.dart';
import 'package:orthanc/workspace_view.dart';

void main() {
  group('dropTargetAt', () {
    test('finds the pane containing the given fraction', () {
      const expected = 'b';

      // row[a, b] — 'b' occupies the right half.
      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b');

      final result = dropTargetAt(workspace, 0.75, 0.5);

      expect(result?.id, expected);
    });

    test('returns null for a point off the whole tree', () {
      const expected = null;

      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b');

      final result = dropTargetAt(workspace, 1.5, 0.5);

      expect(result, expected);
    });

    test('pairs the pane with its own zoneAt at the same point', () {
      const expected = Direction.left;

      // row[a, b] — near b's own left edge, inside the drop-edge band.
      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b');

      final result = dropTargetAt(workspace, 0.55, 0.5);

      expect(result?.id, 'b');
      expect(result?.side, expected);
    });

    test('the centre dead-zone pairs the pane with a null side', () {
      const expected = null;

      // row[a, b] — dead centre of 'b's own half, away from every edge.
      final workspace = Workspace.single(
        'a',
      ).split(axis: SplitAxis.row, newSessionId: 'b');

      final result = dropTargetAt(workspace, 0.75, 0.5);

      expect(result?.side, expected);
    });

    test('a lone pane fills the whole window', () {
      const expected = 'a';

      final workspace = Workspace.single('a');

      final result = dropTargetAt(workspace, 0.1, 0.9);

      expect(result?.id, expected);
    });
  });
}
