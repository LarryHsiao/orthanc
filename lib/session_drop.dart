import 'dropped_paths_text.dart';
import 'session.dart';
import 'session_path.dart';
import 'shell_prompt_hook.dart';

/// Writes [paths], dropped onto [session]'s pane, into its terminal as a
/// bracketed paste — and clears its selection, matching [pasteIntoSession]'s
/// own shape. A no-op with nothing dropped.
///
/// Also called by `pasteIntoSession` itself, once it has found a file on
/// the clipboard rather than one dropped: the gesture that produced [paths]
/// is the caller's business, not this function's — a path is a path either
/// way, and the pane decides its form the same way regardless of how it
/// arrived.
///
/// Which form each path takes is inferred from the pane, not asked of the
/// user: [sessionPath] returning null means a running program (most likely
/// Claude Code) currently owns the pane's title, so the path becomes an
/// `@`-reference Claude Code will read the file through — an image so
/// referenced loads as image content, not as a filename. A non-null
/// [sessionPath] means the shell itself just announced its own prompt, so
/// the path is written bare and quoted instead.
///
/// This inference is wrong, on purpose and documented rather than fixed,
/// for three cases: an unhooked shell (PowerShell, fish) never announces a
/// path, so every drop there reads as "program running"; a program other
/// than Claude Code (`vim`, `less`, a REPL) looks identical to it and
/// receives the same `@`-reference; and a freshly spawned pane, before its
/// first prompt draws, has an empty name and also reads as "program
/// running". See the file-drop design doc for why a per-drop escape hatch
/// was deferred rather than added to fix these.
///
/// [isWindows] is taken as a parameter rather than read from `Platform`
/// directly, matching every other platform-dependent pure decision in this
/// codebase (see `shell_prompt_hook.dart`) — the caller reads
/// `Platform.isWindows` once, at the real I/O boundary, so this function
/// stays testable on any host.
void dropPathsInto(
  Session session,
  List<String> paths, {
  required bool isWindows,
}) {
  final text = droppedPathsText(
    paths: paths,
    atReferenced: sessionPath(session.name.value) == null,
    isWindows: isWindows,
    // Windows-gated, matching shellPromptHook's own use of this check —
    // isCmdShell is a bare basename match, so leaving it ungated would let
    // a POSIX binary a user names literally `cmd` be mistaken for cmd.exe.
    isCmd: isWindows && isCmdShell(session.executable),
  );
  if (text.isEmpty) return;
  session.terminal.paste(text);
  session.terminalController.clearSelection();
}
