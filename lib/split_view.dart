import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'layout_node.dart';
import 'pane_bar.dart';
import 'pane_view.dart';
import 'sessions.dart';

/// Draws a layout node, recursing into splits.
///
/// This walks the tree and nothing more — every decision about shape was
/// made in [Workspace], where it can be tested. A divider drag reports a
/// delta and lets the tree decide what it means. Each pane's collapse
/// state is independent: a column with at least one direct pane child in
/// [collapsedIds] shrinks every collapsed child to bar height and splits
/// the reclaimed space evenly among whatever remains expanded — see
/// [_buildCollapsedSplitChildren]. A column with nothing collapsed renders
/// by its stored ratios exactly as before, dividers and all.
class SplitView extends StatelessWidget {
  const SplitView({
    super.key,
    required this.node,
    required this.sessions,
    required this.focusedId,
    required this.highlightFocus,
    required this.collapsedIds,
    required this.collapsibleIds,
    required this.theme,
    required this.fontFamily,
    required this.fontSize,
    required this.onFocus,
    required this.onResize,
    required this.onToggleCollapse,
    required this.onExpand,
    required this.onKeyEvent,
    required this.canDrag,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.dragSourceId,
    required this.dragHoverId,
  });

  static const dividerThickness = 4.0;

  final LayoutNode node;
  final Sessions sessions;
  final String focusedId;

  /// Whether a focused pane should be marked at all. False when the window
  /// holds a single pane: that pane is always the focused one, so a mark
  /// there distinguishes it from nothing. Threaded verbatim through the
  /// recursion, exactly as [focusedId] is — the whole tree answers this, not
  /// the subtree any one [SplitView] happens to hold.
  final bool highlightFocus;
  final Set<String> collapsedIds;
  final Set<String> collapsibleIds;
  final TerminalTheme theme;
  final String fontFamily;
  final double fontSize;
  final void Function(String id) onFocus;
  final void Function(LayoutNode split, int dividerIndex, double delta)
  onResize;
  final void Function(String id) onToggleCollapse;
  final void Function(String id) onExpand;
  final FocusOnKeyEventCallback onKeyEvent;

  final bool canDrag;
  final void Function(String id) onDragStart;
  final void Function(String id, Offset globalPosition) onDragUpdate;
  final void Function(String id) onDragEnd;

  /// The pane currently being dragged, or null when no drag is in
  /// progress.
  final String? dragSourceId;

  /// The pane currently under the dragged pointer, or null.
  final String? dragHoverId;

  @override
  Widget build(BuildContext context) {
    return switch (node) {
      PaneNode(:final sessionId) => _pane(sessionId),
      SplitNode split => _split(split),
    };
  }

  Widget _pane(String sessionId) => _shrinkablePane(sessionId);

  Widget _shrinkablePane(String sessionId) {
    final session = sessions[sessionId];
    if (session == null) return const SizedBox.shrink();
    return PaneView(
      session: session,
      focused: highlightFocus && sessionId == focusedId,
      onFocus: () => onFocus(sessionId),
      onKeyEvent: onKeyEvent,
      canCollapse: collapsibleIds.contains(sessionId),
      collapsed: collapsedIds.contains(sessionId),
      theme: theme,
      fontFamily: fontFamily,
      fontSize: fontSize,
      onToggleCollapse: () => onToggleCollapse(sessionId),
      onExpand: () => onExpand(sessionId),
      canDrag: canDrag,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      isBeingDragged: sessionId == dragSourceId,
      isDropTarget: sessionId == dragHoverId,
    );
  }

  /// Whether any direct pane child of [split] is currently collapsed —
  /// always false whenever [split] isn't a column at all.
  bool _hasCollapsedChild(SplitNode split) {
    if (split.axis != SplitAxis.column) return false;
    return split.children.any(
      (child) => child is PaneNode && collapsedIds.contains(child.sessionId),
    );
  }

  Widget _split(SplitNode split) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = split.axis == SplitAxis.row;
        final extent = horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final dividers = split.children.length - 1;

        // Only the ratio branch draws dividers, so only it sets aside their
        // space. The collapsed branch shares out the whole extent — reserving
        // room there for dividers it never lays out leaves that strip empty at
        // the far end of the column.
        final children = _hasCollapsedChild(split)
            ? _buildCollapsedSplitChildren(split, extent)
            : _buildRatioSplitChildren(
                split,
                context,
                horizontal,
                extent - dividers * dividerThickness,
              );

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

  List<Widget> _buildRatioSplitChildren(
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
      children.add(_buildRatioSplitChild(split, i, horizontal, free));
    }
    return children;
  }

  Widget _buildRatioSplitChild(
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

  /// Sizes a column with at least one collapsed pane: every collapsed
  /// direct pane child shrinks to [PaneBar.height]; everything else — an
  /// expanded pane, or a nested split child, which is never itself
  /// collapsible — shares the reclaimed space evenly. Ratios are ignored
  /// entirely in this state. Only ever called for a column split, so
  /// height is the only dimension that matters here — no [horizontal]
  /// branch needed. No dividers: a fixed-height collapsed row isn't
  /// draggable, and an evenly-split expanded row isn't either — which is why
  /// [extent] is the column's whole height here, undiminished by the divider
  /// reservation the ratio branch makes.
  List<Widget> _buildCollapsedSplitChildren(SplitNode split, double extent) {
    final collapsedCount = split.children
        .whereType<PaneNode>()
        .where((pane) => collapsedIds.contains(pane.sessionId))
        .length;
    final expandedCount = split.children.length - collapsedCount;
    final fixedTotal = collapsedCount * PaneBar.height;
    final evenSize = expandedCount == 0
        ? 0.0
        : ((extent - fixedTotal) / expandedCount).clamp(0.0, extent);

    final children = <Widget>[];
    for (final child in split.children) {
      if (child is PaneNode && collapsedIds.contains(child.sessionId)) {
        children.add(
          SizedBox(
            height: PaneBar.height,
            child: _shrinkablePane(child.sessionId),
          ),
        );
      } else if (child is PaneNode) {
        children.add(
          SizedBox(height: evenSize, child: _shrinkablePane(child.sessionId)),
        );
      } else {
        children.add(SizedBox(height: evenSize, child: _childSplitView(child)));
      }
    }
    return children;
  }

  Widget _childSplitView(LayoutNode child) {
    return SplitView(
      node: child,
      sessions: sessions,
      focusedId: focusedId,
      highlightFocus: highlightFocus,
      collapsedIds: collapsedIds,
      collapsibleIds: collapsibleIds,
      theme: theme,
      fontFamily: fontFamily,
      fontSize: fontSize,
      onFocus: onFocus,
      onResize: onResize,
      onToggleCollapse: onToggleCollapse,
      onExpand: onExpand,
      onKeyEvent: onKeyEvent,
      canDrag: canDrag,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      dragSourceId: dragSourceId,
      dragHoverId: dragHoverId,
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
