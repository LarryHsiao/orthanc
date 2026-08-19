/// Lines kept when a pane's scrollback crosses to another window, tail-first
/// — the default for [handoffScrollback]'s `maxLines`.
const handoffScrollbackLines = 2000;

/// Characters kept when a pane's scrollback crosses to another window,
/// tail-first — the default for [handoffScrollback]'s `maxChars`. Bounds a
/// long line's own length the line cap alone cannot.
const handoffScrollbackChars = 256 * 1024;

/// A terminal's plain-text scrollback (`Buffer.getText()`), made replayable
/// into a fresh terminal on the far side of a pane handoff.
///
/// Three things separate raw scrollback from something safe to [write] back
/// in:
///
/// * `Buffer.getText()` joins logical lines with a bare `'\n'`. A terminal's
///   `lineFeedMode` is off by default, so writing a bare `'\n'` back in moves
///   the cursor down a row without returning it to column 0 — every line
///   after the first stair-steps one column further than the last. Each
///   `'\n'` is rewritten to `'\r\n'` to fix that. A wrapped line's own
///   continuation carries no separator at all in `getText()`'s output (its
///   `isWrapped` flag suppresses one) — left untouched, since it is meant to
///   re-wrap at the *receiving* terminal's width, not repeat the sender's.
/// * `getText()`'s default range spans the whole viewport, including every
///   blank row below the cursor — replayed as-is, real content is pushed
///   off-screen and the pane opens on a screen of nothing. Trailing blank
///   lines (an unwritten cell has no character at all, so a wholly blank row
///   is an empty string) are dropped.
/// * A long-running pane's scrollback can run to megabytes, held in memory
///   while the moved pane's child process sits blocked on `write()` with
///   nobody reading — the whole point of pausing it for the handoff. The
///   result is capped to its tail: [maxLines] lines, then [maxChars]
///   characters, whichever binds first.
String handoffScrollback(
  String text, {
  int maxLines = handoffScrollbackLines,
  int maxChars = handoffScrollbackChars,
}) {
  final lines = text.split('\n');

  var end = lines.length;
  while (end > 0 && lines[end - 1].isEmpty) {
    end--;
  }
  final trimmed = lines.sublist(0, end);

  final capped = trimmed.length > maxLines
      ? trimmed.sublist(trimmed.length - maxLines)
      : trimmed;

  final replayable = capped.join('\r\n');
  return replayable.length > maxChars
      ? replayable.substring(replayable.length - maxChars)
      : replayable;
}
