import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xterm/xterm.dart';

/// A block name starts with a letter or digit and may then carry dots,
/// dashes and underscores — never a path separator, and never a leading dot,
/// so it cannot climb out of the folder it is resolved in.
const _namePattern = r'[A-Za-z0-9][A-Za-z0-9._-]*';

/// A marker line a program prints above a block it wants copyable:
/// `⧉ copy:<name>`. A name must end at whitespace or the end of the row, so
/// `a/b` is refused outright rather than read as `a`.
final _marker = RegExp('⧉ copy:($_namePattern)(?=\\s|\$)');

final _blockName = RegExp('^$_namePattern\$');

/// Windows device names (`CON`, `NUL`, `COM1`…, with or without an extension)
/// resolve to a device, not a file, and reading one can block. A name comes
/// from untrusted terminal output, so these are refused on every platform
/// rather than only where they bite.
final _deviceName = RegExp(
  r'^(con|prn|aux|nul|com\d|lpt\d)(\..*)?$',
  caseSensitive: false,
);

/// The highest code point a single UTF-16 unit holds; anything above it would
/// take two units and break the one-character-per-cell mapping.
const _highestBasicPlane = 0xFFFF;

/// The folder a marker's block file lives in, under the system temp folder.
String get copyBlockDirectory =>
    p.join(Directory.systemTemp.path, 'orthanc-copy');

/// The block name of the marker under [offset] in [buffer], or null. The row
/// is read together with the soft-wrapped rows around it, so a marker the
/// pane's own width split in two is still found from either half.
String? copyMarkerAtCell(Buffer buffer, CellOffset offset) {
  if (offset.y < 0 || offset.y >= buffer.height) return null;
  final line = _logicalLine(buffer, offset.y);
  var column = offset.x;
  for (var i = 0; i < offset.y - line.firstRow; i++) {
    column += line.rowLengths[i];
  }
  return copyMarkerNameAt(line.text, column);
}

/// One marker's cells on one buffer row: columns [startColumn] up to, but not
/// including, [endColumn]. A marker the pane's width split in two yields one
/// span per row.
class CopyMarkerSpan {
  const CopyMarkerSpan({
    required this.name,
    required this.row,
    required this.startColumn,
    required this.endColumn,
    this.markerOffset = 0,
  });

  final String name;
  final int row;
  final int startColumn;
  final int endColumn;

  /// How many characters of the marker lie before this span, so a marker
  /// split over two rows can show each row its own slice of the label.
  final int markerOffset;

  @override
  bool operator ==(Object other) =>
      other is CopyMarkerSpan &&
      other.name == name &&
      other.row == row &&
      other.startColumn == startColumn &&
      other.endColumn == endColumn &&
      other.markerOffset == markerOffset;

  @override
  int get hashCode =>
      Object.hash(name, row, startColumn, endColumn, markerOffset);

  @override
  String toString() =>
      'CopyMarkerSpan($name, row $row, $startColumn-$endColumn)';
}

/// Every marker cell run on buffer rows [firstRow] to [lastRow] inclusive,
/// top to bottom. A marker wrapped across the range's edge still yields the
/// half that lies inside it.
List<CopyMarkerSpan> copyMarkerSpans(Buffer buffer, int firstRow, int lastRow) {
  final spans = <CopyMarkerSpan>[];
  final last = lastRow < buffer.height ? lastRow : buffer.height - 1;
  var row = firstRow < 0 ? 0 : firstRow;
  while (row <= last) {
    final line = _logicalLine(buffer, row);
    for (final match in _marker.allMatches(line.text)) {
      spans.addAll(_rowSpans(line, match, firstRow, last));
    }
    row = line.firstRow + line.rowLengths.length;
  }
  return spans;
}

Iterable<CopyMarkerSpan> _rowSpans(
  _LogicalLine line,
  RegExpMatch match,
  int firstRow,
  int lastRow,
) sync* {
  var rowStart = 0;
  for (var i = 0; i < line.rowLengths.length; i++) {
    final rowEnd = rowStart + line.rowLengths[i];
    final start = match.start > rowStart ? match.start : rowStart;
    final end = match.end < rowEnd ? match.end : rowEnd;
    final row = line.firstRow + i;
    if (start < end && row >= firstRow && row <= lastRow) {
      yield CopyMarkerSpan(
        name: match.group(1)!,
        row: row,
        startColumn: start - rowStart,
        endColumn: end - rowStart,
        markerOffset: start - match.start,
      );
    }
    rowStart = rowEnd;
  }
}

/// A run of buffer rows joined by soft wraps: the text one cell per
/// character, and each row's length so a string index maps back to a row.
class _LogicalLine {
  const _LogicalLine(this.firstRow, this.text, this.rowLengths);

  final int firstRow;
  final String text;
  final List<int> rowLengths;
}

/// The logical line holding buffer [row]: walk up to where the wrap chain
/// begins, then down to where it ends.
_LogicalLine _logicalLine(Buffer buffer, int row) {
  var first = row;
  while (first > 0 && buffer.lines[first].isWrapped) {
    first--;
  }
  final text = StringBuffer();
  final lengths = <int>[];
  for (var y = first; y < buffer.height; y++) {
    if (y > first && !buffer.lines[y].isWrapped) break;
    final cells = _rowCells(buffer.lines[y]);
    lengths.add(cells.length);
    text.write(cells);
  }
  return _LogicalLine(first, text.toString(), lengths);
}

/// One character per cell: a never-written cell, the spacer half of a wide
/// glyph and a character outside the basic plane each stand as a single
/// character too, so a string index is a cell column.
String _rowCells(BufferLine line) {
  final cells = StringBuffer();
  for (var i = 0; i < line.length; i++) {
    final codePoint = line.getCodePoint(i);
    cells.write(
      codePoint == 0 || codePoint > _highestBasicPlane
          ? ' '
          : String.fromCharCode(codePoint),
    );
  }
  return cells.toString();
}

/// The text of block [name] in [directory] (default [copyBlockDirectory]), or
/// null when [name] is not a valid block name, is not a regular file, or
/// cannot be read as UTF-8 text. The name is checked here as well as at the
/// marker, so a caller that skips the marker still cannot read outside the
/// folder. A bad file copies nothing rather than throwing into the click.
String? readCopyBlock(String name, {String? directory}) {
  if (!_blockName.hasMatch(name) || _deviceName.hasMatch(name)) return null;
  final path = p.join(directory ?? copyBlockDirectory, name);
  if (!FileSystemEntity.isFileSync(path)) return null;
  try {
    return File(path).readAsStringSync();
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

/// The block name of the marker under [column] in [rowText], or null when the
/// column does not fall on a marker. [column] indexes [rowText] one character
/// per terminal cell, the way the caller lays a buffer row out.
String? copyMarkerNameAt(String rowText, int column) {
  for (final match in _marker.allMatches(rowText)) {
    if (column >= match.start && column < match.end) return match.group(1);
  }
  return null;
}
