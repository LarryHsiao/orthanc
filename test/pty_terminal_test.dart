import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/pty_terminal.dart';

void main() {
  test('stores the executable and arguments it is given', () {
    final expectedExecutable = 'claude';
    final expectedArguments = ['--foo'];

    final widget = PtyTerminal(
      executable: expectedExecutable,
      arguments: expectedArguments,
    );

    expect(widget.executable, expectedExecutable);
    expect(widget.arguments, expectedArguments);
  });

  test('defaults arguments to an empty list', () {
    final expected = <String>[];

    final widget = PtyTerminal(executable: 'claude');

    expect(widget.arguments, expected);
  });
}
