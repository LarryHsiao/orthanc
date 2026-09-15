/// A single dropped path, quoted for a bare shell command line.
///
/// POSIX shells (`bash`, `zsh`) get single quotes with an embedded `'`
/// escaped as `'\''` — not double quotes: a double-quoted string still lets
/// the shell expand `$`, backtick, backslash and (interactively) `!`, so a
/// file literally named `$HOME (1).txt` or `hi!.txt` would be mangled.
/// Single quotes protect everything else too, non-ASCII bytes included,
/// since the shell never looks inside them.
///
/// `cmd.exe` gets double quotes with no escaping at all — NTFS forbids a
/// literal `"` in a filename, so there is nothing to escape, and writing
/// dead escaping code for a case that cannot occur would only mislead the
/// next reader.
String _quotedPath({required String path, required bool isCmd}) {
  if (isCmd) return '"$path"';
  return "'${path.replaceAll("'", "'\\''")}'";
}

/// A single dropped path as Claude Code's `@`-reference syntax — no quotes
/// at all, since `@` is Claude Code's own mini-syntax rather than shell
/// syntax: `@'…'` would put the quote character inside the filename token,
/// and only whitespace marks where the token ends.
///
/// On a POSIX-style path, a space is backslash-escaped — the form macOS
/// Terminal and iTerm already emit on an ordinary file drag, so it is the
/// form Claude Code's `@`-parser has been most exposed to in the wild. On a
/// Windows path, the path is left verbatim: backslash is already that
/// path's own separator, so escaping a space with one more would be
/// ambiguous, and there is no established convention to lean on instead.
String _atPath({required String path, required bool isWindows}) {
  if (isWindows) return '@$path';
  return '@${path.replaceAll(' ', r'\ ')}';
}

/// The bracketed-paste text a file drop should write into a pane's pty —
/// one path per line, except under `cmd.exe`, which has no bracketed
/// paste of its own: at a bare `cmd` prompt a newline in the pasted text
/// runs as a pressed Enter, so a multi-file drop there would execute each
/// line rather than sit in the buffer. Space-joining sidesteps the hazard
/// for both of `cmd`'s branches — `@a.txt @b.txt` reads as one Claude Code
/// input, so the narrower fix costs nothing to widen.
///
/// [atReferenced] chooses the `@`-reference form (for a pane a running
/// program owns) over the bare quoted form (for a pane idle at its shell
/// prompt) — see [sessionPath] and `session_drop.dart` for the inference
/// that decides it. [isWindows] governs only the `@`-form's escaping,
/// since a dropped path's own separator syntax comes from the platform,
/// not from which shell happens to be running inside it — Git Bash on
/// Windows still receives a `C:\` path from the OS, not a POSIX one.
/// [isCmd] governs only the bare form's quoting and the join character,
/// since those are cmd's own syntax rather than the platform's.
///
/// An empty [paths] returns `''` — nothing to write.
String droppedPathsText({
  required List<String> paths,
  required bool atReferenced,
  required bool isWindows,
  required bool isCmd,
}) {
  if (paths.isEmpty) return '';
  final separator = isCmd ? ' ' : '\n';
  return paths
      .map(
        (path) => atReferenced
            ? _atPath(path: path, isWindows: isWindows)
            : _quotedPath(path: path, isCmd: isCmd),
      )
      .join(separator);
}
