import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/terminal_paste_shortcuts.dart';

bool _isMetaV(ShortcutActivator activator) =>
    activator is SingleActivator &&
    activator.trigger == LogicalKeyboardKey.keyV &&
    activator.meta;

/// A fresh map on every call, its `SingleActivator` keys built without
/// `const` — deliberately, matching the real fork's own non-`const`
/// `_defaultAppleShortcuts`. A `const` map here would canonicalize its
/// `SingleActivator(keyV, meta: true)` key to the exact same instance
/// `terminal_paste_shortcuts.dart` constructs for its own replacement
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
  group('terminalPasteShortcuts', () {
    test('returns null off macOS', () {
      const expected = null;

      final result = terminalPasteShortcuts(
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

      final result = terminalPasteShortcuts(
        isMacOS: true,
        defaults: _buildDefaults(),
      )!;

      expect(result.keys.where(_isMetaV).length, expected);
    });

    test('that entry asks for a pane paste', () {
      final expected = isA<PanePasteIntent>();

      final result = terminalPasteShortcuts(
        isMacOS: true,
        defaults: _buildDefaults(),
      )!;
      final activator = result.keys.singleWhere(_isMetaV);

      expect(result[activator], expected);
    });

    test('leaves Cmd+C untouched', () {
      const expected = CopySelectionTextIntent.copy;

      final result = terminalPasteShortcuts(
        isMacOS: true,
        defaults: _buildDefaults(),
      )!;
      // Looked up by predicate, not by constructing a fresh SingleActivator
      // key — the map's own keys are non-const (see _buildDefaults), so a
      // freshly built lookup key would never be identical to the one
      // actually stored, and this assertion would wrongly read as null
      // rather than proving the entry survived untouched.
      final activator = result.keys.singleWhere(
        (a) =>
            a is SingleActivator &&
            a.trigger == LogicalKeyboardKey.keyC &&
            a.meta,
      );

      expect(result[activator], expected);
    });

    test('leaves Cmd+A untouched', () {
      const expected = SelectAllTextIntent(SelectionChangedCause.keyboard);

      final result = terminalPasteShortcuts(
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

      terminalPasteShortcuts(isMacOS: true, defaults: defaults);

      expect(defaults.length, expected);
    });
  });
}
