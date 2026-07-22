import 'package:flutter/material.dart';

import 'layout_node.dart';
import 'pane_bar.dart';
import 'pane_view.dart';
import 'sessions.dart';

/// Draws a layout node, recursing into splits.
///
/// This walks the tree and nothing more — every decision about shape was
/// made in [Workspace], where it can be tested. A divider drag reports a
/// delta and lets the tree decide what it means. A column with one of its
/// direct children in [collapsedIds] renders that child at full size and
/// every other direct pane child as a bar-only strip — see
/// [_buildCollapsedSplitChildren].
class SplitView extends StatelessWidget {
  const SplitView({
    super.key,
    required this.node,
    required this.sessions,
    required this.focusedId,
    required this.collapsedIds,
    required this.collapsibleIds,
    required this.onFocus,
    required this.onResize,
    required this.onToggleCollapse,
    required this.onKeyEvent,
  });

  static const dividerThickness = 4.0;

  final LayoutNode node;
  final Sessions sessions;
  final String focusedId;
  final Set<String> collapsedIds;
  final Set<String> collapsibleIds;
  final void Function(String id) onFocus;
  final void Function(LayoutNode split, int dividerIndex, double delta)
  onResize;
  final void Function(String id) onToggleCollapse;
  final FocusOnKeyEventCallback onKeyEvent;

  @override
  Widget build(BuildContext context) {
    return switch (node) {
      PaneNode(:final sessionId) => _pane(sessionId),
      SplitNode split => _split(split),
    };
  }

  Widget _pane(String sessionId) => _shrinkablePane(sessionId, shrunk: false);

  Widget _shrinkablePane(String sessionId, {required bool shrunk}) {
    final session = sessions[sessionId];
    if (session == null) return const SizedBox.shrink();
    return PaneView(
      session: session,
      focused: sessionId == focusedId,
      onFocus: () => onFocus(sessionId),
      onKeyEvent: onKeyEvent,
      canCollapse: collapsibleIds.contains(sessionId),
      collapsed: collapsedIds.contains(sessionId),
      shrunk: shrunk,
      onToggleCollapse: () => onToggleCollapse(sessionId),
    );
  }

  /// The direct child of [split] currently expanded, or null if none of
  /// [split]'s direct pane children is in [collapsedIds] — including
  /// whenever [split] doesn't run the column axis at all.
  String? _expandedChildId(SplitNode split) {
    if (split.axis != SplitAxis.column) return null;
    for (final child in split.children) {
      if (child is PaneNode && collapsedIds.contains(child.sessionId)) {
        return child.sessionId;
      }
    }
    return null;
  }

  Widget _split(SplitNode split) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = split.axis == SplitAxis.row;
        final extent = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final dividers = split.children.length - 1;
        final free = extent - dividers * dividerThickness;
        final expandedId = _expandedChildId(split);

        final children = expandedId == null
            ? _buildEvenSplitChildren(split, context, horizontal, free)
            : _buildCollapsedSplitChildren(split, horizontal, free, expandedId);

        return horizontal
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              );
      },
    );
  }

  List<Widget> _buildEvenSplitChildren(
    SplitNode split,
    BuildContext context,
    bool horizontal,
    double free,
  ) {
    final children = <Widget>[];
    for (var i = 0; i < split.children.length; i++) {
      if (i > 0) {
        children.add(_divider(context, split, i - 1, horizontal, free));
      }
      children.add(_buildEvenSplitChild(split, i, horizontal, free));
    }
    return children;
  }

  Widget _buildEvenSplitChild(
    SplitNode split,
    int index,
    bool horizontal,
    double free,
  ) {
    return SizedBox(
      width: horizontal ? free * split.ratios[index] : null,
      height: horizontal ? null : free * split.ratios[index],
      child: _childSplitView(split.children[index]),
    );
  }

  /// Sizes a collapsed column's children: the expanded row absorbs every
  /// bit of space its shrunk pane-siblings gave up. A sibling that is
  /// itself a nested split (not a bare pane) has no single bar to shrink
  /// to, so it keeps its ordinary ratio-based share untouched — a known,
  /// accepted edge case rather than something this generalizes further.
  /// No dividers: a fixed-height shrunk row isn't draggable.
  List<Widget> _buildCollapsedSplitChildren(
    SplitNode split,
    bool horizontal,
    double free,
    String expandedId,
  ) {
    var fixedTotal = 0.0;
    var ratioTotal = 0.0;
    for (var i = 0; i < split.children.length; i++) {
      final child = split.children[i];
      if (child is PaneNode && child.sessionId != expandedId) {
        fixedTotal += PaneBar.height;
      } else if (child is SplitNode) {
        ratioTotal += free * split.ratios[i];
      }
    }
    final expandedSize = free - fixedTotal - ratioTotal;

    final children = <Widget>[];
    for (var i = 0; i < split.children.length; i++) {
      final child = split.children[i];
      if (child is PaneNode) {
        final isExpanded = child.sessionId == expandedId;
        final size = isExpanded ? expandedSize : PaneBar.height;
        children.add(
          SizedBox(
            width: horizontal ? size : null,
            height: horizontal ? null : size,
            child: _shrinkablePane(child.sessionId, shrunk: !isExpanded),
          ),
        );
      } else {
        final size = free * split.ratios[i];
        children.add(
          SizedBox(
            width: horizontal ? size : null,
            height: horizontal ? null : size,
            child: _childSplitView(child),
          ),
        );
      }
    }
    return children;
  }

  Widget _childSplitView(LayoutNode child) {
    return SplitView(
      node: child,
      sessions: sessions,
      focusedId: focusedId,
      collapsedIds: collapsedIds,
      collapsibleIds: collapsibleIds,
      onFocus: onFocus,
      onResize: onResize,
      onToggleCollapse: onToggleCollapse,
      onKeyEvent: onKeyEvent,
    );
  }

  Widget _divider(
    BuildContext context,
    SplitNode split,
    int index,
    bool horizontal,
    double free,
  ) {
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown,
      child: _dividerGestureDetector(context, split, index, horizontal, free),
    );
  }

  Widget _dividerGestureDetector(
    BuildContext context,
    SplitNode split,
    int index,
    bool horizontal,
    double free,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: horizontal
          ? (details) => onResize(split, index, details.delta.dx / free)
          : null,
      onVerticalDragUpdate: horizontal
          ? null
          : (details) => onResize(split, index, details.delta.dy / free),
      child: SizedBox(
        width: horizontal ? dividerThickness : null,
        height: horizontal ? null : dividerThickness,
        child: ColoredBox(color: Theme.of(context).dividerColor),
      ),
    );
  }
}
