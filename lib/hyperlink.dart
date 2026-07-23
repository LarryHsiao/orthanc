/// Whether the given key state means "open the hyperlink under the
/// pointer" — Ctrl on Windows/Linux, Cmd on macOS, matching every other
/// terminal emulator's own convention on each platform. A pure decision,
/// in the same shape as `paneAction()` in split_shortcuts.dart.
bool isHyperlinkModifierPressed({
  required bool isWindows,
  required bool isControlPressed,
  required bool isMetaPressed,
}) {
  return isWindows ? isControlPressed : isMetaPressed;
}

/// Whether [uri] is safe to launch — only http/https. OSC 8 lets a program
/// claim any scheme (file://, custom protocol handlers); launching those
/// from untrusted terminal output is a real risk, so anything else renders
/// underlined (it is still a real, detected link) but does nothing on
/// click.
bool isLaunchableHyperlink(String? uri) {
  if (uri == null) return false;
  final parsed = Uri.tryParse(uri);
  if (parsed == null) return false;
  return parsed.scheme == 'http' || parsed.scheme == 'https';
}
