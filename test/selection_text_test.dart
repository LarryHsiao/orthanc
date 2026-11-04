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

  test('written spaces after the last glyph are trimmed', () {
    final terminal = Terminal();
    terminal.write('curl \\      \r\nnext');

    final expected = 'curl \\\nnext';

    final actual = _copy(terminal, CellOffset(0, 0), CellOffset(79, 1));
    expect(actual, expected);
  });

  test('a written space at a soft-wrap point survives the join', () {
    final terminal = Terminal();
    terminal.resize(6, 3);
    terminal.write('hello world');

    final expected = 'hello world';

    final actual = _copy(terminal, CellOffset(0, 0), CellOffset(5, 1));
    expect(actual, expected);
  });

  test('a selection ending before the wrapped row trims the gap space', () {
    final terminal = Terminal();
    terminal.resize(6, 3);
    terminal.write('hello world');

    final expected = 'hello';

    final actual = _copy(terminal, CellOffset(0, 0), CellOffset(5, 0));
    expect(actual, expected);
  });

  test('leading written spaces are kept', () {
    final terminal = Terminal();
    terminal.write('  x');

    final expected = '  x';

    final actual = _copy(terminal, CellOffset(0, 0), CellOffset(79, 0));
    expect(actual, expected);
  });

  test('a selection ending mid-row drops its trailing spaces', () {
    final terminal = Terminal();
    terminal.write('foo   bar');

    final expected = 'foo';

    final actual = _copy(terminal, CellOffset(0, 0), CellOffset(5, 0));
    expect(actual, expected);
  });

  test('a row holding only spaces copies as an empty line', () {
    final terminal = Terminal();
    terminal.write('a\r\n   \r\nb');

    final expected = 'a\n\nb';

    final actual = _copy(terminal, CellOffset(0, 0), CellOffset(79, 2));
    expect(actual, expected);
  });

  test('written spaces between glyphs are kept', () {
    final terminal = Terminal();
    terminal.write('a  b');

    final expected = 'a  b';

    final actual = _copy(terminal, CellOffset(0, 0), CellOffset(79, 0));
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
