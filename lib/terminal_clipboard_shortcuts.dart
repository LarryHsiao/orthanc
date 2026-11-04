import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Asks the pane to paste — a file path when the clipboard holds one, the
/// clipboard's text otherwise. A distinct `Intent` type from Flutter's own
/// `PasteTextIntent` on purpose: xterm's own `TerminalActions` (nested
/// inside `TerminalView`, and therefore always nearer the focused node than
/// anything `PaneView` can wrap around it) handles `PasteTextIntent`
/// unconditionally and cannot be shadowed by an outer `Actions` widget for
/// the same Intent type. `Actions.maybeFind` specialises on the Intent's
/// runtime type, so an Intent `TerminalActions` has never heard of walks
/// straight past it to `PaneView`'s own `Actions` wrapper instead.
class PanePasteIntent extends Intent {
  const PanePasteIntent();
}

/// Asks the pane to copy its selection through `copySelection`, which trims
/// the blanks xterm's own copy would carry onto the clipboard. A distinct
/// `Intent` type from Flutter's `CopySelectionTextIntent` for the same
/// reason [PanePasteIntent] is distinct from `PasteTextIntent`: xterm's own
/// `TerminalActions` handles the stock type and cannot be shadowed.
class PaneCopyIntent extends Intent {
  const PaneCopyIntent();
}

/// [defaults] with macOS's `Cmd+C` rebound to [PaneCopyIntent] and `Cmd+V`
/// to [PanePasteIntent], or `null` on every other platform — `null` is what
/// `TerminalView` already treats as "use your own defaults," so Windows and
/// Linux stay byte-identical to before this feature.
///
/// Each entry is *removed by predicate, then re-inserted* — never
/// assigned over a freshly built key. `SingleActivator` declares no
/// `operator==` (Flutter's own `shortcuts.dart` defines exactly one
/// `operator==` in the whole file, and it belongs to the unrelated
/// `KeySet`), and xterm's own default map builds its keys non-`const`, so
/// `map[SingleActivator(keyV, meta: true)] = ourIntent` would use Dart's
/// default identity equality and *add a second entry* rather than replace
/// the first. `ShortcutManager` resolves the *first* accepting activator in
/// insertion order, so the stale entry — xterm's own — would keep winning,
/// the key would keep doing exactly what it does today, and nothing would
/// ever error. This is why this function's own test asserts the resulting
/// map holds exactly one entry per key, not merely that it holds one mapping
/// to our intent.
Map<ShortcutActivator, Intent>? terminalClipboardShortcuts({
  required bool isMacOS,
  required Map<ShortcutActivator, Intent> defaults,
}) {
  if (!isMacOS) return null;
  return Map.of(defaults)
    ..removeWhere(_isPlainMeta(LogicalKeyboardKey.keyC))
    ..removeWhere(_isPlainMeta(LogicalKeyboardKey.keyV))
    ..[const SingleActivator(LogicalKeyboardKey.keyC, meta: true)] =
        const PaneCopyIntent()
    ..[const SingleActivator(LogicalKeyboardKey.keyV, meta: true)] =
        const PanePasteIntent();
}

bool Function(ShortcutActivator, Intent) _isPlainMeta(LogicalKeyboardKey key) {
  return (activator, _) =>
      activator is SingleActivator &&
      activator.trigger == key &&
      activator.meta &&
      !activator.control &&
      !activator.alt &&
      !activator.shift;
}
