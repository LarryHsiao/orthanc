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
  var first = offset.y;
  while (first > 0 && buffer.lines[first].isWrapped) {
    first--;
  }
  final text = StringBuffer();
  var column = offset.x;
  for (var y = first; y < buffer.height; y++) {
    if (y > first && !buffer.lines[y].isWrapped) break;
    final cells = _rowCells(buffer.lines[y]);
    if (y < offset.y) column += cells.length;
    text.write(cells);
  }
  return copyMarkerNameAt(text.toString(), column);
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
