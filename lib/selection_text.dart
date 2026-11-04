import 'package:xterm/xterm.dart';

/// The text of [range] in [buffer], as it should land on the clipboard.
///
/// xterm's own `Buffer.getText` drops every never-written cell (code point
/// 0). A program that moves the cursor with `ESC [ n C` instead of printing
/// spaces — Ink, the renderer behind Claude Code, does — leaves such cells
/// between its glyphs, so indentation vanishes on copy. Here a never-written
/// cell *between* a row's written cells copies as a space; blanks after the
/// last written cell stay trimmed. Row joining follows `Buffer.getText`: a
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
    builder.write(_rowText(line, segment.start, segment.end));
  }
  return builder.toString();
}

String _rowText(BufferLine line, int? start, int? end) {
  final from = (start == null || start < 0) ? 0 : start;
  final to = (end == null || end > line.length) ? line.length : end;
  final builder = StringBuffer();
  var pendingBlanks = 0;
  // A selection may begin on the right half of a wide character.
  var spacerCells = from > 0 && line.getWidth(from - 1) == 2 ? 1 : 0;
  for (var i = from; i < to; i++) {
    if (spacerCells > 0) {
      spacerCells--;
      continue;
    }
    final codePoint = line.getCodePoint(i);
    if (codePoint == 0) {
      pendingBlanks++;
      continue;
    }
    builder.write(' ' * pendingBlanks);
    pendingBlanks = 0;
    builder.writeCharCode(codePoint);
    spacerCells = line.getWidth(i) - 1;
  }
  return builder.toString();
}
