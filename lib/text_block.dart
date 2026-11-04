import 'package:xterm/xterm.dart';

import 'selection_text.dart';

/// A run of non-blank rows around a clicked row — what a Cmd/Ctrl+click on
/// plain text copies. See [textBlockAt].
class TextBlock {
  const TextBlock({
    required this.firstRow,
    required this.lastRow,
    required this.text,
  });

  /// Buffer row index of the block's first row.
  final int firstRow;

  /// Buffer row index of the block's last row, inclusive.
  final int lastRow;

  /// The block's text, ready for the clipboard — see [textBlockAt].
  final String text;
}

/// The block of text around [row] in [buffer], or null when [row] is blank
/// or outside the buffer.
///
/// A block is every row reachable from [row] without crossing a blank one —
/// the shape a command block takes in Claude Code's output, which sets each
/// code block off from the prose around it with an empty line. Content-blind
/// by design: nothing here guesses whether the text "looks like" a command;
/// it only reads where the blank rows fall.
///
/// The text is cleaned for pasting into a shell: trailing blanks on each
/// line are dropped, and the indentation every line shares is removed — the
/// two columns Claude Code indents its whole reply by would otherwise ride
/// along into the clipboard. Indentation *within* the block (a nested line
/// of a script) survives, since only the common part is removed. Rows are
/// read with [selectionText], so cursor-skipped cells count as spaces and a
/// soft-wrapped row continues its line, exactly as a drag-selection copy
/// does.
TextBlock? textBlockAt(Buffer buffer, int row) {
  if (row < 0 || row >= buffer.height) return null;
  if (_isBlank(buffer, row)) return null;

  var first = row;
  while (first > 0 && !_isBlank(buffer, first - 1)) {
    first--;
  }
  var last = row;
  while (last < buffer.height - 1 && !_isBlank(buffer, last + 1)) {
    last++;
  }

  final raw = selectionText(
    buffer,
    BufferRangeLine(
      CellOffset(0, first),
      CellOffset(buffer.lines[last].length, last),
    ),
  );
  return TextBlock(firstRow: first, lastRow: last, text: dedent(raw));
}

/// [text] with trailing blanks dropped from every line and the leading
/// spaces all non-empty lines share removed. Exposed for tests.
String dedent(String text) {
  final lines = text.split('\n').map((l) => l.trimRight()).toList();
  int? common;
  for (final line in lines) {
    if (line.isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    if (common == null || indent < common) common = indent;
  }
  final cut = common ?? 0;
  return lines
      .map((l) => l.length >= cut ? l.substring(cut) : '')
      .join('\n');
}

bool _isBlank(Buffer buffer, int row) {
  final line = buffer.lines[row];
  final text = selectionText(
    buffer,
    BufferRangeLine(CellOffset(0, row), CellOffset(line.length, row)),
  );
  return text.trim().isEmpty;
}
