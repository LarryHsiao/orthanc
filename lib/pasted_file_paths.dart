import 'pane_title.dart';

/// Which of the clipboard's reported file paths are plausible enough to
/// write into a pty.
///
/// `Pasteboard.files()` is trusted on Windows, where it reads `CF_HDROP` and
/// can report nothing else. It is not trusted on macOS, where the plugin
/// calls `NSPasteboard.readObjects(forClasses: [NSURL.self], options: nil)`
/// without `urlReadingFileURLsOnly` — so a web link copied from Safari
/// (`public.url`) comes back as a "file" whose `.path` is the URL's path
/// component. `https://example.com/a/b` yields `/a/b`, which is absolute
/// and would otherwise sail through.
///
/// Two gates, both required: [looksLikePath] — the same POSIX-slash or
/// Windows-drive test `sessionPath()` and the pane title already lean on,
/// so there is one definition of "absolute path" in this repo — and
/// existence on disk, which is what actually rejects the Safari case.
///
/// [exists] is injected rather than calling `File().existsSync()` here,
/// matching `executableExists()` in `settings_validation.dart`: the caller
/// reads the filesystem once at the real I/O boundary, so this function
/// stays a pure decision testable on any host with no files to stage.
List<String> pastedFilePaths(
  List<String> candidates, {
  required bool Function(String) exists,
}) {
  return candidates
      .where((path) => path.isNotEmpty)
      .where(looksLikePath)
      .where(exists)
      .toList();
}
