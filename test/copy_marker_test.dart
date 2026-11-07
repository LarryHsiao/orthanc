import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/copy_marker.dart';
import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart';

void main() {
  group('readCopyBlock', () {
    late Directory root;
    late Directory blocks;

    setUp(() {
      root = Directory.systemTemp.createTempSync('orthanc-copy-test');
      blocks = Directory(p.join(root.path, 'blocks'))..createSync();
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('an existing block file returns its text exactly', () {
      const expected = '#!/usr/bin/env bash\n  echo "hi"\n';
      File(p.join(blocks.path, 'block-1.sh')).writeAsStringSync(expected);

      final result = readCopyBlock('block-1.sh', directory: blocks.path);

      expect(result, expected);
    });

    test('a missing block file returns null', () {
      final result = readCopyBlock('absent.sh', directory: blocks.path);

      expect(result, isNull);
    });

    test('a name climbing out of the folder returns null', () {
      File(p.join(root.path, 'secret.txt')).writeAsStringSync('secret');

      final result = readCopyBlock('../secret.txt', directory: blocks.path);

      expect(result, isNull);
    });

    test('a file that is not valid UTF-8 returns null', () {
      File(
        p.join(blocks.path, 'bin.dat'),
      ).writeAsBytesSync([0xFF, 0xFE, 0xC0, 0x80]);

      final result = readCopyBlock('bin.dat', directory: blocks.path);

      expect(result, isNull);
    });

    test('a name that is a folder returns null', () {
      Directory(p.join(blocks.path, 'adir')).createSync();

      final result = readCopyBlock('adir', directory: blocks.path);

      expect(result, isNull);
    });

    test('a Windows device name returns null', () {
      final results = [
        readCopyBlock('CON', directory: blocks.path),
        readCopyBlock('nul.txt', directory: blocks.path),
        readCopyBlock('Com1', directory: blocks.path),
      ];

      expect(results, [null, null, null]);
    });

    test('a name with a backslash or a bare dot-dot returns null', () {
      final results = [
        readCopyBlock(r'a\b', directory: blocks.path),
        readCopyBlock('..', directory: blocks.path),
      ];

      expect(results, [null, null]);
    });

    test('a name carrying a separator returns null', () {
      Directory(p.join(blocks.path, 'sub')).createSync();
      File(p.join(blocks.path, 'sub', 'x.sh')).writeAsStringSync('x');

      final result = readCopyBlock('sub/x.sh', directory: blocks.path);

      expect(result, isNull);
    });
  });

  group('copyMarkerAtCell', () {
    test('a cell on a marker row names the block', () {
      final terminal = Terminal()..write('⧉ copy:block-1');
      const expected = 'block-1';

      final result = copyMarkerAtCell(terminal.buffer, CellOffset(10, 0));

      expect(result, expected);
    });

    test('a cell past the marker names nothing', () {
      final terminal = Terminal()..write('⧉ copy:block-1');

      final result = copyMarkerAtCell(terminal.buffer, CellOffset(40, 0));

      expect(result, isNull);
    });

    test('a marker wrapped over two rows is found from either row', () {
      final terminal = Terminal()
        ..resize(12, 5)
        ..write('⧉ copy:block-1');
      const expected = 'block-1';

      final onFirstRow = copyMarkerAtCell(terminal.buffer, CellOffset(3, 0));
      final onSecondRow = copyMarkerAtCell(terminal.buffer, CellOffset(1, 1));

      expect([onFirstRow, onSecondRow], [expected, expected]);
    });

    test('a marker after a wide glyph is found at its own cells', () {
      final terminal = Terminal()..write('漢字 ⧉ copy:block-1');
      const expected = 'block-1';
      // two wide glyphs take four cells, then a space: the marker starts at 5.
      const markerCell = 5;

      final result = copyMarkerAtCell(
        terminal.buffer,
        CellOffset(markerCell, 0),
      );

      expect(result, expected);
    });

    test('a row below the buffer names nothing', () {
      final terminal = Terminal()..write('⧉ copy:block-1');

      final result = copyMarkerAtCell(terminal.buffer, CellOffset(0, 9999));

      expect(result, isNull);
    });
  });

  group('copyMarkerNameAt', () {
    const row = 'see ⧉ copy:block-1 below';
    final start = row.indexOf('⧉');
    final end = row.indexOf('block-1') + 'block-1'.length - 1;

    test('a column on the marker glyph names the block', () {
      const expected = 'block-1';

      final result = copyMarkerNameAt(row, start);

      expect(result, expected);
    });

    test('a column on the last character of the name names the block', () {
      const expected = 'block-1';

      final result = copyMarkerNameAt(row, end);

      expect(result, expected);
    });

    test('a column before the marker names nothing', () {
      final result = copyMarkerNameAt(row, start - 1);

      expect(result, isNull);
    });

    test('a column after the marker names nothing', () {
      final result = copyMarkerNameAt(row, end + 1);

      expect(result, isNull);
    });

    test('a row with no marker names nothing', () {
      final result = copyMarkerNameAt('echo hello', 3);

      expect(result, isNull);
    });

    test('a name that starts with a dot is refused', () {
      final result = copyMarkerNameAt('⧉ copy:..', 0);

      expect(result, isNull);
    });

    test('a name carrying a path separator is refused', () {
      final result = copyMarkerNameAt('⧉ copy:a/b', 0);

      expect(result, isNull);
    });

    test('a name ending the row is accepted', () {
      const expected = 'x.sh';

      final result = copyMarkerNameAt('⧉ copy:x.sh', 0);

      expect(result, expected);
    });
  });
}
