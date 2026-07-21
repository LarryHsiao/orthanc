import 'package:flutter/material.dart';

import 'layout_node.dart';
import 'pane_view.dart';
import 'sessions.dart';

/// Draws a layout node, recursing into splits.
///
/// This walks the tree and nothing more — every decision about shape was made
/// in [Workspace], where it can be tested. A divider drag reports a delta and
/// lets the tree decide what it means.
class SplitView extends StatelessWidget {
  const SplitView({
    super.key,
    required this.node,
    required this.sessions,
    required this.focusedId,
    required this.onFocus,
    required this.onResize,
  });

  static const dividerThickness = 4.0;

  final LayoutNode node;
  final Sessions sessions;
  final String focusedId;
  final void Function(String id) onFocus;
  final void Function(LayoutNode split, int dividerIndex, double delta)
  onResize;

  @override
  Widget build(BuildContext context) {
    return switch (node) {
      PaneNode(:final sessionId) => _pane(sessionId),
      SplitNode split => _split(split),
    };
  }

  Widget _pane(String sessionId) {
    final session = sessions[sessionId];
    if (session == null) return const SizedBox.shrink();
    return PaneView(
      session: session,
      focused: sessionId == focusedId,
      onFocus: () => onFocus(sessionId),
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
        final free = extent - dividers * dividerThickness;

        final children = _buildSplitChildren(split, context, horizontal, free);

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

  List<Widget> _buildSplitChildren(
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
      children.add(_buildSplitChild(split, i, horizontal, free));
    }
    return children;
  }

  Widget _buildSplitChild(
    SplitNode split,
    int index,
    bool horizontal,
    double free,
  ) {
    return SizedBox(
      width: horizontal ? free * split.ratios[index] : null,
      height: horizontal ? null : free * split.ratios[index],
      child: SplitView(
        node: split.children[index],
        sessions: sessions,
        focusedId: focusedId,
        onFocus: onFocus,
        onResize: onResize,
      ),
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
