import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/shortcuts_reference.dart';

void main() {
  void expectContains(List<ShortcutEntry> entries, ShortcutEntry expected) {
    expect(
      entries,
      contains(
        predicate<ShortcutEntry>((e) {
          return e.label == expected.label && e.keys == expected.keys;
        }),
      ),
    );
  }

  test('mac labels use the shortcuts bound in _macAction', () {
    final entries = paneShortcuts(isWindows: false);

    // SplitAxis.row lays children out side by side (Workspace._fill varies
    // `left`), so the row split is "right"; SplitAxis.column stacks them
    // (varies `top`), so the column split is "down". _macAction binds row to
    // plain ⌘D and column to ⌘⇧D.
    expectContains(entries, const ShortcutEntry('Split right', '⌘D'));
    expectContains(entries, const ShortcutEntry('Split down', '⌘⇧D'));
    expectContains(entries, const ShortcutEntry('Move focus left', '⌘⌥←'));
  });

  test('windows labels use the shortcuts bound in _windowsAction', () {
    final entries = paneShortcuts(isWindows: true);

    expectContains(entries, const ShortcutEntry('Split right', 'Shift+Alt+='));
    expectContains(entries, const ShortcutEntry('Split down', 'Shift+Alt+-'));
    expectContains(entries, const ShortcutEntry('Move focus left', 'Alt+Left'));
  });

  test('the quake toggle chord differs by platform', () {
    expectContains(
      paneShortcuts(isWindows: true),
      const ShortcutEntry('Toggle quake window', 'Ctrl+`'),
    );
    expectContains(
      paneShortcuts(isWindows: false),
      const ShortcutEntry('Toggle quake window', '⌘`'),
    );
  });

  test('every entry has a non-empty label and key combination', () {
    for (final isWindows in [true, false]) {
      for (final entry in paneShortcuts(isWindows: isWindows)) {
        expect(entry.label, isNotEmpty);
        expect(entry.keys, isNotEmpty);
      }
    }
  });
}
