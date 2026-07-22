/// Combines a session's name and current activity into one line for
/// [PaneBar] — both are shown together rather than one overwriting the
/// other, since a running program can set either independently. See
/// docs/superpowers/specs/2026-07-22-orthanc-pane-title-design.md.
///
/// Claude Code sets its title via OSC 0, which sets [name] and [activity]
/// to the identical string in one call (confirmed empirically — see the
/// spec's "Verified 2026-07-22" note) — so a [name] equal to [activity] is
/// treated the same as an empty one, or the pane bar would show the value
/// twice.
String paneTitle({required String name, required String activity}) {
  if (name.isEmpty || name == activity) return activity;
  return '$name — $activity';
}
