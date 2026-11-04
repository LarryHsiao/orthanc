import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/text_block.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('copies the run of rows between blank lines, indentation removed', () {
    final terminal = Terminal();
    terminal.write(
      '⏺ Run these:\r\n'
      '\r\n'
      '  cd orthanc\r\n'
      '  flutter test\r\n'
      '\r\n'
      '  That is all.\r\n',
    );

    final block = textBlockAt(terminal.buffer, 3)!;

    expect(block.text, 'cd orthanc\nflutter test');
    expect(block.firstRow, 2);
    expect(block.lastRow, 3);
  });

  test('a blank row copies nothing', () {
    final terminal = Terminal();
    terminal.write('one\r\n\r\ntwo\r\n');

    expect(textBlockAt(terminal.buffer, 1), isNull);
  });

  test('a row outside the buffer copies nothing', () {
    final terminal = Terminal();
    terminal.write('one');

    expect(textBlockAt(terminal.buffer, -1), isNull);
    expect(textBlockAt(terminal.buffer, 10000), isNull);
  });

  test('cursor-skipped indentation is removed like printed spaces', () {
    final terminal = Terminal();
    terminal.write('\x1b[2Cls -la\r\n\x1b[2Cpwd\r\n');

    expect(textBlockAt(terminal.buffer, 0)!.text, 'ls -la\npwd');
  });

  test('a soft-wrapped command stays one line', () {
    final terminal = Terminal();
    terminal.resize(10, 5);
    terminal.write('echo abcdefghij');

    expect(textBlockAt(terminal.buffer, 1)!.text, 'echo abcdefghij');
  });

  test('dedent keeps nesting deeper than the shared indent', () {
    expect(
      dedent('    if true; then\n      echo hi   \n    fi'),
      'if true; then\n  echo hi\nfi',
    );
  });
}
