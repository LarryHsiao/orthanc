/// Whether [value] looks like a filesystem path — a POSIX path starting
/// with `/`, or a Windows path starting with a drive letter (`C:\` or
/// `C:/`). Used to tell the shell's own idle-prompt directory announcement
/// (see shell_prompt_hook.dart) apart from a running program's own OSC
/// title, which never looks like a path — [Session.terminal]'s
/// `onIconChange` leans on this to keep the last real directory in [name]
/// once a program like Claude Code starts overwriting [activity] with its
/// own message.
bool looksLikePath(String value) {
  return value.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
}

/// [path]'s last path segment — `orthanc` for `/Users/larry/orthanc` — for
/// display, falling back to [path] itself when there is no segment (the
/// filesystem root, `/`).
String _lastPathSegment(String path) {
  final segments = path
      .split(RegExp(r'[\\/]'))
      .where((segment) => segment.isNotEmpty);
  return segments.isEmpty ? path : segments.last;
}

/// Combines a session's manual name, program-set name, and current
/// activity into one line for [PaneBar]. [manualName] — set by the user via
/// [PaneBar]'s rename control, never by the running program — prefixes
/// whatever [name] and [activity] already combine to, when set. See
/// docs/superpowers/specs/2026-07-23-orthanc-pane-rename-design.md and
/// docs/superpowers/specs/2026-07-22-orthanc-pane-title-design.md.
///
/// Claude Code sets its title via OSC 0, which sets [name] and [activity]
/// to the identical string in one call (confirmed empirically — see the
/// pane-title spec's "Verified 2026-07-22" note) — so a [name] equal to
/// [activity] is treated the same as an empty one, or the pane bar would
/// show the value twice. Once they differ because [name] still holds the
/// last real directory while [activity] has moved on to Claude's own
/// message, only [name]'s last path segment is shown — the combined line
/// reads `orthanc — Compacting…`, not the whole absolute path glued to a
/// program's message.
String paneTitle({
  required String name,
  required String activity,
  String manualName = '',
}) {
  final displayName = looksLikePath(name) ? _lastPathSegment(name) : name;
  final base = (name.isEmpty || name == activity)
      ? activity
      : '$displayName — $activity';
  if (manualName.isEmpty) return base;
  return '$manualName — $base';
}
