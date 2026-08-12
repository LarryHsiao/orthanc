/// One row of the Keyboard Shortcuts reference: what an action does, and the
/// key combination that triggers it on the current platform.
class ShortcutEntry {
  const ShortcutEntry(this.label, this.keys);

  final String label;
  final String keys;
}

/// Every pane shortcut bound in `paneAction` (split_shortcuts.dart) and the
/// app menu's New Window item, labelled for display. Branches by platform the
/// same way `paneAction` itself does — mac symbols vs Windows chord text.
List<ShortcutEntry> paneShortcuts({required bool isWindows}) {
  if (isWindows) {
    return const [
      ShortcutEntry('New window', 'Ctrl+N'),
      ShortcutEntry('Split right', 'Shift+Alt+='),
      ShortcutEntry('Split down', 'Shift+Alt+-'),
      ShortcutEntry('Close pane', 'Ctrl+Shift+W'),
      ShortcutEntry('Move focus left', 'Alt+Left'),
      ShortcutEntry('Move focus right', 'Alt+Right'),
      ShortcutEntry('Move focus up', 'Alt+Up'),
      ShortcutEntry('Move focus down', 'Alt+Down'),
      ShortcutEntry('Collapse/expand pane', 'Shift+Alt+Z'),
    ];
  }
  return const [
    ShortcutEntry('New window', '⌘N'),
    ShortcutEntry('Split right', '⌘D'),
    ShortcutEntry('Split down', '⌘⇧D'),
    ShortcutEntry('Close pane', '⌘W'),
    ShortcutEntry('Move focus left', '⌘⌥←'),
    ShortcutEntry('Move focus right', '⌘⌥→'),
    ShortcutEntry('Move focus up', '⌘⌥↑'),
    ShortcutEntry('Move focus down', '⌘⌥↓'),
    ShortcutEntry('Collapse/expand pane', '⌘⇧⏎'),
  ];
}
