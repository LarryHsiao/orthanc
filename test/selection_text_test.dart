import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/selection_text.dart';
import 'package:xterm/xterm.dart';

String _copy(Terminal terminal, CellOffset begin, CellOffset end) =>
    selectionText(terminal.buffer, BufferRangeLine(begin, end));

void main() {
  test('cells skipped by cursor-forward copy as spaces', () {
    final terminal = Terminal();
    terminal.write('\$\x1b[4Ccmd');

    final expected = '\$    cmd';

    final actual = _copy(terminal, CellOffset(0, 0), CellOffset(79, 0));
    expect(actual, expected);
  });

  test('never-written cells after the last written cell are trimmed', () {
    final terminal = Terminal();
    terminal.write('ab');

    final expected = 'ab';

    final actual = _copy(terminal, CellOffset(0, 0), CellOffset(79, 0));
    expect(actual, expected);
  });

  test('leading skipped cells inside the selection copy as spaces', () {
    final terminal = Terminal();
    terminal.write('\x1b[2Cx');

    final expected = '  x';

    final actual = _copy(terminal, CellOffset(0, 0), CellOffset(79, 0));
    expect(actual, expected);
  });

  test('the spacer half of a wide character is not a space', () {
    final terminal = Terminal();
    terminal.write('日本');

    final expected = '日本';

    final actual = _copy(terminal, CellOffset(0, 0), CellOffset(79, 0));
    expect(actual, expected);
  });

  test('a selection starting on a spacer half adds no leading space', () {
    final terminal = Terminal();
    terminal.write('日本');

    final expected = '本';

    final actual = _copy(terminal, CellOffset(1, 0), CellOffset(79, 0));
    expect(actual, expected);
  });

  test('separate rows are joined by a newline', () {
    final terminal = Terminal();
    terminal.write('one\r\n\x1b[2Ctwo');

    final expected = 'one\n  two';

    final actual = _copy(terminal, CellOffset(0, 0), CellOffset(79, 1));
    expect(actual, expected);
  });

  test('a soft-wrapped row joins without a newline', () {
    final terminal = Terminal();
    terminal.resize(5, 3);
    terminal.write('abcdefgh');

    final expected = 'abcdefgh';

    final actual = _copy(terminal, CellOffset(0, 0), CellOffset(4, 1));
    expect(actual, expected);
  });
}
