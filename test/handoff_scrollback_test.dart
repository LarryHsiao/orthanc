import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/handoff_scrollback.dart';

void main() {
  group('handoffScrollback', () {
    test('rewrites a bare newline to carriage-return-newline', () {
      const expected = 'a\r\nb\r\nc';

      final result = handoffScrollback('a\nb\nc');

      expect(result, expected);
    });

    test('leaves a wrapped line\'s run-together text untouched', () {
      const expected = 'abcdef\r\nghi';

      // getText() never inserts '\n' inside a wrapped continuation — 'def'
      // ran on from 'abc' with no separator, as if it wrapped at the
      // sender's width. Only the real line boundary before 'ghi' gets a
      // '\r\n'; nothing splits 'abcdef' itself.
      final result = handoffScrollback('abcdef\nghi');

      expect(result, expected);
    });

    test('drops trailing blank rows', () {
      const expected = 'a\r\nb';

      // getText()'s default range spans the whole viewport, so several
      // blank rows below the cursor (each an empty string — an unwritten
      // cell has no character to return) commonly trail the real content.
      final result = handoffScrollback('a\nb\n\n\n');

      expect(result, expected);
    });

    test('leaves a blank line in the middle of real content alone', () {
      const expected = 'a\r\n\r\nb';

      final result = handoffScrollback('a\n\nb');

      expect(result, expected);
    });

    test('caps to the last maxLines lines', () {
      const expected = 'c\r\nd';

      final result = handoffScrollback('a\nb\nc\nd', maxLines: 2);

      expect(result, expected);
    });

    test('caps to the last maxChars characters', () {
      const expected = 'de';

      final result = handoffScrollback('abcde', maxChars: 2);

      expect(result, expected);
    });

    test('the line cap runs before the char cap, both taking the tail', () {
      const expected = '\r\nd';

      // 'a\nb\nc\nd' capped to 2 lines first ('c\r\nd', 4 characters), then
      // capped to the last 3 characters of THAT — not the last 3 characters
      // of the uncapped input.
      final result = handoffScrollback('a\nb\nc\nd', maxLines: 2, maxChars: 3);

      expect(result, expected);
    });

    test('empty input produces empty output', () {
      const expected = '';

      final result = handoffScrollback('');

      expect(result, expected);
    });

    test('uses the standing defaults when neither cap is passed', () {
      // The first 10 of 2,010 lines fall off the default 2,000-line cap.
      final expected = List.generate(
        handoffScrollbackLines,
        (i) => 'line${i + 10}',
      ).join('\r\n');

      final input = List.generate(
        handoffScrollbackLines + 10,
        (i) => 'line$i',
      ).join('\n');
      final result = handoffScrollback(input);

      expect(result, expected);
    });
  });
}
