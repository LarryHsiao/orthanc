import 'package:flutter/services.dart';

import 'layout_node.dart';

/// Something a key press asks of the layout, rather than of the terminal.
sealed class PaneAction {
  const PaneAction();
}

class SplitPane extends PaneAction {
  const SplitPane(this.axis);

  final SplitAxis axis;
}

class ClosePane extends PaneAction {
  const ClosePane();
}

class MoveFocus extends PaneAction {
  const MoveFocus(this.direction);

  final Direction direction;
}

/// What a key press means to the layout, or null to let the terminal have it.
///
/// Each platform wears the scheme of the terminal already in use there — iTerm2
/// on macOS, Windows Terminal on Windows. Ctrl+D is bound on neither: it is
/// EOF, and would kill a session rather than split it. A pure decision with no
/// I/O, in the same shape as shellCommand() and ptyEnvironment().
PaneAction? paneAction({
  required bool isWindows,
  required LogicalKeyboardKey key,
  required bool isControlPressed,
  required bool isShiftPressed,
  required bool isAltPressed,
  required bool isMetaPressed,
}) {
  if (isWindows) {
    if (isAltPressed && isShiftPressed && key == LogicalKeyboardKey.equal) {
      return const SplitPane(SplitAxis.row);
    }
    if (isAltPressed && isShiftPressed && key == LogicalKeyboardKey.minus) {
      return const SplitPane(SplitAxis.column);
    }
    if (isControlPressed && isShiftPressed && key == LogicalKeyboardKey.keyW) {
      return const ClosePane();
    }
    if (isAltPressed && !isShiftPressed) {
      final direction = _arrow(key);
      if (direction != null) return MoveFocus(direction);
    }
    return null;
  }

  if (isMetaPressed && key == LogicalKeyboardKey.keyD) {
    return SplitPane(isShiftPressed ? SplitAxis.column : SplitAxis.row);
  }
  if (isMetaPressed && key == LogicalKeyboardKey.keyW) {
    return const ClosePane();
  }
  if (isMetaPressed && isAltPressed) {
    final direction = _arrow(key);
    if (direction != null) return MoveFocus(direction);
  }
  return null;
}

Direction? _arrow(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.arrowLeft => Direction.left,
  LogicalKeyboardKey.arrowRight => Direction.right,
  LogicalKeyboardKey.arrowUp => Direction.up,
  LogicalKeyboardKey.arrowDown => Direction.down,
  _ => null,
};
