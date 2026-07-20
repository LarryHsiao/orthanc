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

  /// Removes a pane, returning null when it was the last one.
  ///
  /// Removal runs the splitting rules backwards: take the pane out, and if its
  /// parent split is left holding a single child, dissolve that split and hoist
  /// the child into its place. Without that collapse the tree accumulates
  /// one-child splits that draw nothing yet still hold ratios — invisible on
  /// screen, and how a layout rots over a long session.
  Workspace? close(String sessionId) {
    final remaining = _without(root, sessionId);
    if (remaining == null) return null;

    final ids = _idsOf(remaining);
    return Workspace(
      root: remaining,
      focusedId: ids.contains(focusedId) ? focusedId : ids.first,
    );
  }

  /// Every pane's share of the window, in fractions of the whole.
  ///
  /// The same numbers the widgets lay out by, which is what lets a directional
  /// focus move be decided here rather than guessed at from the screen.
  Map<String, PaneRect> paneRects() {
    final rects = <String, PaneRect>{};
    _fill(root, const PaneRect(left: 0, top: 0, width: 1, height: 1), rects);
    return rects;
  }

  /// The nearest pane in [direction], or null at the edge of the window.
  ///
  /// Decided from the same rectangles the widgets lay out by: keep only panes
  /// genuinely on that side, then take the one whose centre lies closest to the
  /// focused pane's own centre along the perpendicular axis — so moving right
  /// from a tall pane meets whichever neighbour sits level with it.
  String? neighbour(Direction direction) {
    final rects = paneRects();
    final from = rects[focusedId];
    if (from == null) return null;

    String? best;
    var bestOffset = double.infinity;

    for (final entry in rects.entries) {
      if (entry.key == focusedId) continue;
      final to = entry.value;

      final beyond = switch (direction) {
        Direction.left => to.right <= from.left,
        Direction.right => to.left >= from.right,
        Direction.up => to.bottom <= from.top,
        Direction.down => to.top >= from.bottom,
      };
      if (!beyond) continue;

      final offset = switch (direction) {
        Direction.left || Direction.right => (to.centerY - from.centerY).abs(),
        Direction.up || Direction.down => (to.centerX - from.centerX).abs(),
      };
      if (offset < bestOffset) {
        bestOffset = offset;
        best = entry.key;
      }
    }

    return best;
  }

  static void _fill(
    LayoutNode node,
    PaneRect within,
    Map<String, PaneRect> into,
  ) {
    if (node is PaneNode) {
      into[node.sessionId] = within;
      return;
    }

    final split = node as SplitNode;
    var offset = 0.0;
    for (var i = 0; i < split.children.length; i++) {
      final share = split.ratios[i];
      final child = switch (split.axis) {
        SplitAxis.row => PaneRect(
          left: within.left + offset * within.width,
          top: within.top,
          width: within.width * share,
          height: within.height,
        ),
        SplitAxis.column => PaneRect(
          left: within.left,
          top: within.top + offset * within.height,
          width: within.width,
          height: within.height * share,
        ),
      };
      _fill(split.children[i], child, into);
      offset += share;
    }
  }

  static LayoutNode? _without(LayoutNode node, String sessionId) {
    if (node is PaneNode) {
      return node.sessionId == sessionId ? null : node;
    }

    final split = node as SplitNode;
    final kept = <LayoutNode>[];
    for (final child in split.children) {
      final survivor = _without(child, sessionId);
      if (survivor != null) kept.add(survivor);
    }

    if (kept.isEmpty) return null;
    if (kept.length == 1) return kept.single;
    return SplitNode(
      axis: split.axis,
      children: kept,
      ratios: evenRatios(kept.length),
    );
  }

  /// Handles the case where the focused pane is the whole tree.
  LayoutNode? _wrapIfFocused(
    LayoutNode node,
    SplitAxis axis,
    String newSessionId,
  ) {
    if (node is PaneNode && node.sessionId == focusedId) {
      return _wrapInSplit(node, axis, newSessionId);
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
      return _insertSibling(split, at, axis, newSessionId);
    }

    if (at != -1) {
      return _wrapFocusedChild(split, at, axis, newSessionId);
    }

    return _recurseBesideInChildren(split, axis, newSessionId);
  }

  LayoutNode _insertSibling(
    SplitNode split,
    int at,
    SplitAxis axis,
    String newSessionId,
  ) {
    final children = [...split.children]
      ..insert(at + 1, PaneNode(newSessionId));
    return SplitNode(
      axis: axis,
      children: children,
      ratios: evenRatios(children.length),
    );
  }

  LayoutNode _wrapFocusedChild(
    SplitNode split,
    int at,
    SplitAxis axis,
    String newSessionId,
  ) {
    final children = [...split.children];
    children[at] = _wrapInSplit(children[at], axis, newSessionId);
    return SplitNode(
      axis: split.axis,
      children: children,
      ratios: split.ratios,
    );
  }

  LayoutNode _recurseBesideInChildren(
    SplitNode split,
    SplitAxis axis,
    String newSessionId,
  ) {
    return SplitNode(
      axis: split.axis,
      children: [
        for (final child in split.children)
          _insertBeside(child, axis, newSessionId),
      ],
      ratios: split.ratios,
    );
  }

  LayoutNode _wrapInSplit(
    LayoutNode node,
    SplitAxis axis,
    String newSessionId,
  ) {
    return SplitNode(
      axis: axis,
      children: [node, PaneNode(newSessionId)],
      ratios: evenRatios(2),
    );
  }
}

/// [count] equal shares, summing to 1.
List<double> evenRatios(int count) =>
    List<double>.filled(count, 1 / count, growable: false);
