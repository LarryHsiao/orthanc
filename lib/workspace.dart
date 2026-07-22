import 'layout_node.dart';

/// The arrangement of panes and which one has focus.
///
/// Immutable: every operation returns a new [Workspace], so a test is three
/// lines with no setup and no teardown. It holds session ids, never sessions,
/// which is why it needs neither a Flutter engine nor a live process.
class Workspace {
  const Workspace({
    required this.root,
    required this.focusedId,
    this.collapsedIds = const {},
  });

  /// The window holding a single session — how the app starts.
  factory Workspace.single(String sessionId) =>
      Workspace(root: PaneNode(sessionId), focusedId: sessionId);

  final LayoutNode root;
  final String focusedId;

  /// Session ids currently the sole expanded row within their own
  /// direct-parent column. Scoped per column: two entries can coexist
  /// freely as long as they belong to different columns, since a
  /// column's own other rows are never independently reachable while one
  /// of their siblings is the expanded one.
  final Set<String> collapsedIds;

  /// Every session in the tree, left to right, top to bottom.
  List<String> get sessionIds => _idsOf(root);

  static List<String> _idsOf(LayoutNode node) => switch (node) {
    PaneNode(:final sessionId) => [sessionId],
    SplitNode(:final children) => [
      for (final child in children) ..._idsOf(child),
    ],
  };

  Workspace focus(String sessionId) =>
      Workspace(root: root, focusedId: sessionId, collapsedIds: collapsedIds);

  /// Sets [sessionId] as the sole expanded row within its own direct-parent
  /// column, or restores that column to even shares if [sessionId] was
  /// already the expanded one. No-ops when [sessionId]'s direct parent
  /// isn't a column split with 2+ children — the one gate every caller
  /// (a bar click, a hotkey) gets for free by going through here.
  Workspace toggleCollapse(String sessionId) {
    final parent = _directParent(root, sessionId);
    if (parent == null ||
        parent.axis != SplitAxis.column ||
        parent.children.length < 2) {
      return this;
    }

    final siblingIds = _paneChildIds(parent);
    final updated = {...collapsedIds}..removeAll(siblingIds);
    if (!collapsedIds.contains(sessionId)) updated.add(sessionId);

    return Workspace(root: root, focusedId: sessionId, collapsedIds: updated);
  }

  /// Clears whichever collapse entry (if any) is currently hiding
  /// [sessionId] behind a different sibling in the same column, so
  /// [sessionId] becomes visible. A no-op if [sessionId] isn't hidden.
  Workspace reveal(String sessionId) {
    final parent = _directParent(root, sessionId);
    if (parent == null || parent.axis != SplitAxis.column) return this;

    final siblingIds = _paneChildIds(parent);
    final hiding = collapsedIds.intersection(siblingIds)..remove(sessionId);
    if (hiding.isEmpty) return this;

    return Workspace(
      root: root,
      focusedId: focusedId,
      collapsedIds: collapsedIds.difference(hiding),
    );
  }

  /// Every session whose direct parent is a column split with 2+ children —
  /// the panes a bar's collapse affordance should appear on.
  Set<String> get collapsibleIds {
    final ids = <String>{};
    _collectCollapsible(root, ids);
    return ids;
  }

  static void _collectCollapsible(LayoutNode node, Set<String> into) {
    if (node is PaneNode) return;
    final split = node as SplitNode;
    if (split.axis == SplitAxis.column && split.children.length >= 2) {
      into.addAll(_paneChildIds(split));
    }
    for (final child in split.children) {
      _collectCollapsible(child, into);
    }
  }

  /// The session ids of [split]'s own direct pane children — excludes any
  /// child that is itself a nested split.
  static Set<String> _paneChildIds(SplitNode split) => {
    for (final child in split.children)
      if (child is PaneNode) child.sessionId,
  };

  /// The nearest ancestor split holding [sessionId] as a direct child, or
  /// null if [sessionId] is the whole tree (no parent at all).
  static SplitNode? _directParent(LayoutNode node, String sessionId) {
    if (node is PaneNode) return null;
    final split = node as SplitNode;
    for (final child in split.children) {
      if (child is PaneNode && child.sessionId == sessionId) return split;
    }
    for (final child in split.children) {
      final found = _directParent(child, sessionId);
      if (found != null) return found;
    }
    return null;
  }

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
      collapsedIds: collapsedIds,
    ).reveal(newSessionId);
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
      collapsedIds: collapsedIds.where((id) => id != sessionId).toSet(),
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

  static bool _liesBeyond(PaneRect to, PaneRect from, Direction direction) {
    return switch (direction) {
      Direction.left => to.right <= from.left,
      Direction.right => to.left >= from.right,
      Direction.up => to.bottom <= from.top,
      Direction.down => to.top >= from.bottom,
    };
  }

  static double _offsetAcross(PaneRect to, PaneRect from, Direction direction) {
    return switch (direction) {
      Direction.left || Direction.right => (to.centerY - from.centerY).abs(),
      Direction.up || Direction.down => (to.centerX - from.centerX).abs(),
    };
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

      if (!_liesBeyond(to, from, direction)) continue;

      final offset = _offsetAcross(to, from, direction);
      if (offset < bestOffset) {
        bestOffset = offset;
        best = entry.key;
      }
    }

    return best;
  }

  /// Moves one divider of one split, taking share from one side and giving it
  /// to the other. [delta] is a fraction of that split's own extent.
  ///
  /// Identity is by reference: [split] is the node the dragged divider belongs
  /// to, which the widget already holds. Only that node's ratios change.
  Workspace resizeSplit({
    required LayoutNode split,
    required int dividerIndex,
    required double delta,
  }) {
    return Workspace(
      root: _resized(root, split, dividerIndex, delta),
      focusedId: focusedId,
      collapsedIds: collapsedIds,
    );
  }

  static LayoutNode _resized(
    LayoutNode node,
    LayoutNode target,
    int dividerIndex,
    double delta,
  ) {
    if (node is PaneNode) return node;
    final split = node as SplitNode;
    if (identical(split, target)) {
      return SplitNode(
        axis: split.axis,
        children: split.children,
        ratios: _tradeRatios(split.ratios, dividerIndex, delta),
      );
    }
    return SplitNode(
      axis: split.axis,
      children: [
        for (final child in split.children)
          _resized(child, target, dividerIndex, delta),
      ],
      ratios: split.ratios,
    );
  }

  /// Moves [delta] of share from the ratio at [dividerIndex] to the one just
  /// after it, clamping both sides so neither drops below [minPaneRatio].
  static List<double> _tradeRatios(
    List<double> ratios,
    int dividerIndex,
    double delta,
  ) {
    final traded = [...ratios];
    final before = traded[dividerIndex];
    final after = traded[dividerIndex + 1];
    final room = before + after;
    final moved = (before + delta).clamp(minPaneRatio, room - minPaneRatio);
    traded[dividerIndex] = moved;
    traded[dividerIndex + 1] = room - moved;
    return traded;
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
    final keptRatios = <double>[];
    for (var i = 0; i < split.children.length; i++) {
      final survivor = _without(split.children[i], sessionId);
      if (survivor != null) {
        kept.add(survivor);
        keptRatios.add(split.ratios[i]);
      }
    }

    if (kept.isEmpty) return null;
    if (kept.length == 1) return kept.single;
    return SplitNode(
      axis: split.axis,
      children: kept,
      ratios: _renormalized(keptRatios),
    );
  }

  /// The kept ratios, scaled so they sum to 1 again.
  ///
  /// Each survivor keeps its original share relative to the others — when
  /// nothing was removed the ratios already sum to 1, so this is a no-op;
  /// when a sibling was removed, the survivors share out its space in
  /// proportion to the sizes they already held.
  static List<double> _renormalized(List<double> ratios) {
    final sum = ratios.fold(0.0, (total, ratio) => total + ratio);
    return [for (final ratio in ratios) ratio / sum];
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

/// The least share a pane may be dragged down to, so it can never vanish
/// behind its own divider.
const minPaneRatio = 0.05;
