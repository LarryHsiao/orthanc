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
/// show the value twice.
String paneTitle({
  required String name,
  required String activity,
  String manualName = '',
}) {
  final base = (name.isEmpty || name == activity)
      ? activity
      : '$name — $activity';
  if (manualName.isEmpty) return base;
  return '$manualName — $base';
}
