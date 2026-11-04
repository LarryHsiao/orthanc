import 'package:xterm/xterm.dart';

/// The text of [range] in [buffer], as it should land on the clipboard.
///
/// xterm's own `Buffer.getText` drops every never-written cell (code point
/// 0). A program that moves the cursor with `ESC [ n C` instead of printing
/// spaces — Ink, the renderer behind Claude Code, does — leaves such cells
/// between its glyphs, so indentation vanishes on copy. Here a never-written
/// cell *between* a row's glyphs copies as a space; blanks after a row's last
/// glyph stay trimmed, written or not, so a `\` followed by spaces cannot
/// reach a shell and break its line continuation. The one exception is a row
/// a soft-wrapped row continues within the selection: its written spaces are
/// the word gap at the wrap point and are kept. Row joining follows `Buffer.getText`: a
/// soft-wrapped row continues the previous one with no newline.
String selectionText(Buffer buffer, BufferRange range) {
  final normalized = range.normalized;
  final builder = StringBuffer();
  for (final segment in normalized.toSegments()) {
    if (segment.line < 0 || segment.line >= buffer.height) continue;
    final line = buffer.lines[segment.line];
    final joinsPrevious =
        segment.line == normalized.begin.y ||
        segment.line == 0 ||
        line.isWrapped;
    if (!joinsPrevious) builder.write('\n');
    final joinsNext =
        segment.line < normalized.end.y &&
        segment.line + 1 < buffer.height &&
        buffer.lines[segment.line + 1].isWrapped;
    builder.write(
      _rowText(line, segment.start, segment.end, keepWrittenSpaces: joinsNext),
    );
  }
  return builder.toString();
}

const _space = 0x20;

/// A row's text between [start] and [end]. Blanks — never-written cells and
/// written spaces alike — are held back until a glyph follows, so a row's
/// trailing blanks do not reach the clipboard. With [keepWrittenSpaces], the
/// written spaces among the trailing blanks are emitted too (never-written
/// cells after the last written space still are not).
String _rowText(
  BufferLine line,
  int? start,
  int? end, {
  required bool keepWrittenSpaces,
}) {
  final from = (start == null || start < 0) ? 0 : start;
  final to = (end == null || end > line.length) ? line.length : end;
  final builder = StringBuffer();
  var pendingBlanks = 0;
  var blanksThroughLastSpace = 0;
  // A selection may begin on the right half of a wide character.
  var spacerCells = from > 0 && line.getWidth(from - 1) == 2 ? 1 : 0;
  for (var i = from; i < to; i++) {
    if (spacerCells > 0) {
      spacerCells--;
      continue;
    }
    final codePoint = line.getCodePoint(i);
    if (codePoint == 0 || codePoint == _space) {
      pendingBlanks++;
      if (codePoint == _space) blanksThroughLastSpace = pendingBlanks;
      continue;
    }
    builder.write(' ' * pendingBlanks);
    pendingBlanks = 0;
    blanksThroughLastSpace = 0;
    builder.writeCharCode(codePoint);
    spacerCells = line.getWidth(i) - 1;
  }
  if (keepWrittenSpaces) builder.write(' ' * blanksThroughLastSpace);
  return builder.toString();
}
