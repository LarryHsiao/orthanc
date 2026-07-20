import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/layout_node.dart';
import 'package:orthanc/split_shortcuts.dart';

PaneAction? macAction(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool meta = false,
  bool alt = false,
}) => paneAction(
  isWindows: false,
  key: key,
  isControlPressed: false,
  isShiftPressed: shift,
  isAltPressed: alt,
  isMetaPressed: meta,
);

PaneAction? windowsAction(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool control = false,
  bool alt = false,
}) => paneAction(
  isWindows: true,
  key: key,
  isControlPressed: control,
  isShiftPressed: shift,
  isAltPressed: alt,
  isMetaPressed: false,
);

void main() {
  group('macOS', () {
    test('Cmd+D splits into a row', () {
      const expected = SplitAxis.row;

      final action = macAction(LogicalKeyboardKey.keyD, meta: true);

      expect((action as SplitPane).axis, expected);
    });

    test('Cmd+Shift+D splits into a column', () {
      const expected = SplitAxis.column;

      final action = macAction(
        LogicalKeyboardKey.keyD,
        meta: true,
        shift: true,
      );

      expect((action as SplitPane).axis, expected);
    });

    test('Cmd+W closes the pane', () {
      final action = macAction(LogicalKeyboardKey.keyW, meta: true);

      expect(action, isA<ClosePane>());
    });

    test('Cmd+Opt+Left moves focus left', () {
      const expected = Direction.left;

      final action = macAction(
        LogicalKeyboardKey.arrowLeft,
        meta: true,
        alt: true,
      );

      expect((action as MoveFocus).direction, expected);
    });

    test('a bare D is left for the terminal', () {
      const expected = null;

      final action = macAction(LogicalKeyboardKey.keyD);

      expect(action, expected);
    });
  });

  group('Windows', () {
    test('Alt+Shift+Equal splits into a row', () {
      const expected = SplitAxis.row;

      final action = windowsAction(
        LogicalKeyboardKey.equal,
        alt: true,
        shift: true,
      );

      expect((action as SplitPane).axis, expected);
    });

    test('Alt+Shift+Minus splits into a column', () {
      const expected = SplitAxis.column;

      final action = windowsAction(
        LogicalKeyboardKey.minus,
        alt: true,
        shift: true,
      );

      expect((action as SplitPane).axis, expected);
    });

    test('Ctrl+Shift+W closes the pane', () {
      final action = windowsAction(
        LogicalKeyboardKey.keyW,
        control: true,
        shift: true,
      );

      expect(action, isA<ClosePane>());
    });

    test('Alt+Down moves focus down', () {
      const expected = Direction.down;

      final action = windowsAction(LogicalKeyboardKey.arrowDown, alt: true);

      expect((action as MoveFocus).direction, expected);
    });

    test('Ctrl+D is never bound — it is EOF', () {
      const expected = null;

      final action = windowsAction(LogicalKeyboardKey.keyD, control: true);

      expect(action, expected);
    });
  });

  test('the mac scheme does not fire on Windows', () {
    const expected = null;

    final action = windowsAction(LogicalKeyboardKey.keyD, control: true);

    expect(action, expected);
  });
}
