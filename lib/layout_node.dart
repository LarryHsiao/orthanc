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

/// How close to a pane's own edge a drop must land to mean "insert here"
/// rather than "swap" — a fraction of that pane's own width or height.
const dropEdgeBand = 0.25;

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

  /// Which edge of this rect [x]/[y] (both fractions of the whole
  /// window, the same space [Workspace.paneRects] returns) sits closest
  /// to — or null when every edge is farther than [dropEdgeBand], the
  /// centre dead-zone where a drop means swap rather than insert.
  ///
  /// [x]/[y] are expected to already fall within this rect; a point
  /// exactly on the boundary is clamped rather than trusted, since the
  /// caller's own hit-test is what guarantees the point belongs here at
  /// all. A corner equidistant from two edges picks a fixed order —
  /// left, then right, then up, then down — arbitrary by design.
  Direction? zoneAt(double x, double y) {
    final localX = ((x - left) / width).clamp(0.0, 1.0);
    final localY = ((y - top) / height).clamp(0.0, 1.0);

    final distances = {
      Direction.left: localX,
      Direction.right: 1 - localX,
      Direction.up: localY,
      Direction.down: 1 - localY,
    };
    final nearest = distances.entries.reduce(
      (a, b) => a.value <= b.value ? a : b,
    );
    return nearest.value < dropEdgeBand ? nearest.key : null;
  }

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
