/// A path shaped like one Windows can resolve: a drive letter, or a UNC share.
final _windowsPath = RegExp(r'^([A-Za-z]:|\\\\)');

bool _namesWindowsPath(String? path) =>
    path != null && _windowsPath.hasMatch(path);

/// The directory a spawned session should start in, or null when the
/// environment names none.
///
/// `HOME` still comes first — someone who exports it means it, and their rc
/// files live there — but on Windows it is trusted only if it names a path
/// Windows can actually use, with `USERPROFILE` behind it.
///
/// Two things make that guard necessary. Windows never sets `HOME` itself, so
/// a double-clicked or Start-menu launch has none at all and must fall through
/// to `USERPROFILE`. And where `HOME` *is* present, an MSYS ancestor often put
/// it there — Git Bash hands its children `HOME=/c/Users/<name>`, which Win32
/// reads as the current drive's root and resolves to a `C:\c\Users\<name>`
/// that does not exist. flutter_pty does not fail on an unusable
/// `workingDirectory`; it silently leaves the child in the app's own cwd,
/// which is the very unpredictability a working directory is set to avoid.
///
/// A pure decision with no I/O, in the same shape as [ptyEnvironment] and
/// `shellCommand()`. It does not check that the directory exists — that is the
/// caller's to do, as `executableExists()` does for the configured shell.
String? homeDirectory({
  required bool isWindows,
  required Map<String, String> environment,
}) {
  if (!isWindows) return environment['HOME'];

  for (final candidate in [environment['HOME'], environment['USERPROFILE']]) {
    if (_namesWindowsPath(candidate)) return candidate;
  }
  return null;
}
