import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/terminal_clipboard_shortcuts.dart';

bool _isMetaV(ShortcutActivator activator) =>
    activator is SingleActivator &&
    activator.trigger == LogicalKeyboardKey.keyV &&
    activator.meta;

bool _isMetaC(ShortcutActivator activator) =>
    activator is SingleActivator &&
    activator.trigger == LogicalKeyboardKey.keyC &&
    activator.meta;

/// A fresh map on every call, its `SingleActivator` keys built without
/// `const` — deliberately, matching the real fork's own non-`const`
/// `_defaultAppleShortcuts`. A `const` map here would canonicalize its
/// `SingleActivator(keyV, meta: true)` key to the exact same instance
/// `terminal_clipboard_shortcuts.dart` constructs for its own replacement
/// entry, which would make even the naive, buggy `map[key] = value`
/// assignment appear to work in this test — silently defeating the one
/// regression this file exists to catch.
Map<ShortcutActivator, Intent> _buildDefaults() {
  return {
    SingleActivator(LogicalKeyboardKey.keyC, meta: true):
        CopySelectionTextIntent.copy,
    SingleActivator(LogicalKeyboardKey.keyV, meta: true): const PasteTextIntent(
      SelectionChangedCause.keyboard,
    ),
    SingleActivator(LogicalKeyboardKey.keyA, meta: true):
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
  };
}

void main() {
  group('terminalClipboardShortcuts', () {
    test('returns null off macOS', () {
      const expected = null;

      final result = terminalClipboardShortcuts(
        isMacOS: false,
        defaults: _buildDefaults(),
      );

      expect(result, expected);
    });

    test('binds exactly one activator to Cmd+V', () {
      // The regression this whole file exists for: a naive map assignment
      // against a freshly built SingleActivator adds a second entry rather
      // than replacing xterm's own, since SingleActivator has no
      // operator==. If that bug returns, this count silently becomes 2 and
      // xterm's own PasteTextIntent entry keeps winning.
      const expected = 1;

      final result = terminalClipboardShortcuts(
        isMacOS: true,
        defaults: _buildDefaults(),
      )!;

      expect(result.keys.where(_isMetaV).length, expected);
    });

    test('that entry asks for a pane paste', () {
      final expected = isA<PanePasteIntent>();

      final result = terminalClipboardShortcuts(
        isMacOS: true,
        defaults: _buildDefaults(),
      )!;
      final activator = result.keys.singleWhere(_isMetaV);

      expect(result[activator], expected);
    });

    test('binds exactly one activator to Cmd+C', () {
      // Same duplicate-key hazard as Cmd+V: xterm's own CopySelectionTextIntent
      // entry would keep winning if a second Cmd+C key were merely added.
      const expected = 1;

      final result = terminalClipboardShortcuts(
        isMacOS: true,
        defaults: _buildDefaults(),
      )!;

      expect(result.keys.where(_isMetaC).length, expected);
    });

    test('that entry asks for a pane copy', () {
      final expected = isA<PaneCopyIntent>();

      final result = terminalClipboardShortcuts(
        isMacOS: true,
        defaults: _buildDefaults(),
      )!;
      // Looked up by predicate, not by constructing a fresh SingleActivator
      // key — the map's own keys are non-const (see _buildDefaults), so a
      // freshly built lookup key would never be identical to the one
      // actually stored, and this lookup would wrongly read as null.
      final activator = result.keys.singleWhere(_isMetaC);

      expect(result[activator], expected);
    });

    test('leaves Cmd+A untouched', () {
      const expected = SelectAllTextIntent(SelectionChangedCause.keyboard);

      final result = terminalClipboardShortcuts(
        isMacOS: true,
        defaults: _buildDefaults(),
      )!;
      final activator = result.keys.singleWhere(
        (a) =>
            a is SingleActivator &&
            a.trigger == LogicalKeyboardKey.keyA &&
            a.meta,
      );

      expect(result[activator], expected);
    });

    test('does not mutate the map it was given', () {
      const expected = 3;
      final defaults = _buildDefaults();

      terminalClipboardShortcuts(isMacOS: true, defaults: defaults);

      expect(defaults.length, expected);
    });
  });
}
