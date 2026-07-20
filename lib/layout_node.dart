/// The arrangement of panes, as plain data.
///
/// Nothing here imports Flutter, and nothing here holds a [Session] — only its
/// id. That is what lets every layout operation be exercised by a unit test
/// with no engine and no live process, which the pty wiring itself can never be.
///
/// Which way a split lays its children out.
///
/// Named [SplitAxis] rather than `Axis` because widget files import Flutter's
/// `Axis` alongside this.
enum SplitAxis { row, column }

/// A direction to look in for a neighbouring pane.
enum Direction { left, right, up, down }

/// A pane's share of the window, in fractions of the whole.
class PaneRect {
  const PaneRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  @override
  bool operator ==(Object other) =>
      other is PaneRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'PaneRect($left, $top, $width, $height)';
}

/// One node of the layout: either a pane, or a split holding more nodes.
sealed class LayoutNode {
  const LayoutNode();
}

/// A leaf — one session's place in the window.
class PaneNode extends LayoutNode {
  const PaneNode(this.sessionId);

  final String sessionId;
}

/// A division. [ratios] runs parallel to [children] and sums to 1.
class SplitNode extends LayoutNode {
  const SplitNode({
    required this.axis,
    required this.children,
    required this.ratios,
  });

  final SplitAxis axis;
  final List<LayoutNode> children;
  final List<double> ratios;
}
