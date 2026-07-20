import 'layout_node.dart';

/// The arrangement of panes and which one has focus.
///
/// Immutable: every operation returns a new [Workspace], so a test is three
/// lines with no setup and no teardown. It holds session ids, never sessions,
/// which is why it needs neither a Flutter engine nor a live process.
class Workspace {
  const Workspace({required this.root, required this.focusedId});

  /// The window holding a single session — how the app starts.
  factory Workspace.single(String sessionId) =>
      Workspace(root: PaneNode(sessionId), focusedId: sessionId);

  final LayoutNode root;
  final String focusedId;

  /// Every session in the tree, left to right, top to bottom.
  List<String> get sessionIds => _idsOf(root);

  static List<String> _idsOf(LayoutNode node) => switch (node) {
    PaneNode(:final sessionId) => [sessionId],
    SplitNode(:final children) => [
      for (final child in children) ..._idsOf(child),
    ],
  };

  Workspace focus(String sessionId) =>
      Workspace(root: root, focusedId: sessionId);

  /// Divides the focused pane, putting [newSessionId] beside or below it.
  ///
  /// Two rules, chosen by one comparison — does the focused pane's parent split
  /// already run along [axis]? If it does, the new pane joins that split as the
  /// next sibling and the tree stays flat. If it does not (or the focused pane
  /// is the root), the focused pane is replaced by a new split holding both and
  /// the tree deepens by one level. Either way the new pane ends up adjacent to
  /// the focused one; only the shape differs.
  Workspace split({required SplitAxis axis, required String newSessionId}) {
    final wrapped = _wrapIfFocused(root, axis, newSessionId);
    return Workspace(
      root: wrapped ?? _insertBeside(root, axis, newSessionId),
      focusedId: newSessionId,
    );
  }

  /// Handles the case where the focused pane is the whole tree.
  LayoutNode? _wrapIfFocused(
    LayoutNode node,
    SplitAxis axis,
    String newSessionId,
  ) {
    if (node is PaneNode && node.sessionId == focusedId) {
      return SplitNode(
        axis: axis,
        children: [node, PaneNode(newSessionId)],
        ratios: evenRatios(2),
      );
    }
    return null;
  }

  LayoutNode _insertBeside(
    LayoutNode node,
    SplitAxis axis,
    String newSessionId,
  ) {
    if (node is PaneNode) return node;

    final split = node as SplitNode;
    final at = split.children.indexWhere(
      (child) => child is PaneNode && child.sessionId == focusedId,
    );

    if (at != -1 && split.axis == axis) {
      final children = [...split.children]
        ..insert(at + 1, PaneNode(newSessionId));
      return SplitNode(
        axis: axis,
        children: children,
        ratios: evenRatios(children.length),
      );
    }

    if (at != -1) {
      final children = [...split.children];
      children[at] = SplitNode(
        axis: axis,
        children: [children[at], PaneNode(newSessionId)],
        ratios: evenRatios(2),
      );
      return SplitNode(
        axis: split.axis,
        children: children,
        ratios: split.ratios,
      );
    }

    return SplitNode(
      axis: split.axis,
      children: [
        for (final child in split.children)
          _insertBeside(child, axis, newSessionId),
      ],
      ratios: split.ratios,
    );
  }
}

/// [count] equal shares, summing to 1.
List<double> evenRatios(int count) =>
    List<double>.filled(count, 1 / count, growable: false);
