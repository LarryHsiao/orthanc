# OSC 8 Terminal Hyperlinks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ctrl+click (Windows/Linux) or Cmd+click (macOS) on an OSC-8-emitted hyperlink in a terminal pane opens it in the system browser; link text is always underlined; the pointer becomes a hand only while hovering a link with the modifier held; only `http`/`https` schemes are launchable.

**Architecture:** The xterm.dart fork side is already implemented and pushed (commit `994d1e5ae5cb3be8efb2f6d96977006b763d9766` on branch `orthanc-osc8-hyperlinks` of `LarryHsiao/xterm.dart`, verified directly against the pushed source — see Global Constraints) — it exposes `Terminal.hyperlinkAt(CellOffset) -> String?` and renders an underline via a new `CellFlags.hyperlink` bit. This plan covers only the Orthanc-side consumption: two small pure decision functions (which modifier counts, which schemes launch), a pin bump plus `url_launcher`, and wiring `PaneView` to call them from hover and tap-up.

**Tech Stack:** Flutter/Dart, `flutter_test`, `url_launcher`, the pinned `xterm.dart` fork.

## Global Constraints

- The fork API is fixed and already verified against the real pushed commit — do not deviate from these exact names: `Terminal.hyperlinkAt(CellOffset offset) -> String?`, `CellFlags.hyperlink = 1 << 8`. Full ref: `994d1e5ae5cb3be8efb2f6d96977006b763d9766`.
- Modifier convention matches `lib/split_shortcuts.dart`'s existing `isWindows`-parameterized, pure-function style (see `paneAction()`) — no direct `Platform.isMacOS` branching scattered through UI code; one small pure function decides, callers pass in `Platform.isWindows` and `HardwareKeyboard.instance` values.
- Only `http`/`https` schemes may be launched. Every other scheme (including a valid-but-unparseable string) is treated as not launchable — no error surfaced, just inert.
- Test style: `group`/`test`, a named `expected` (or `expectedX`) constant declared before the call, then one assertion comparing against it — see `test/split_shortcuts_test.dart` for the exact pattern this plan follows.
- Widget/gesture-level behavior (`PaneView`'s hover cursor and click-to-open) has no test harness in this project and is verified **by eye, running the app** — same convention every prior spec in this repo has used (e.g. `docs/superpowers/plans/2026-07-23-orthanc-pane-collapse.md`'s Global Constraints). Do not introduce a new widget-testing pattern this codebase doesn't otherwise use.
- `xterm: ^4.0.0` in `dependencies` stays untouched — only `dependency_overrides.xterm.ref` changes.

---

### Task 1: Pure hyperlink decision helpers

**Files:**
- Create: `lib/hyperlink.dart`
- Test: `test/hyperlink_test.dart`

**Interfaces:**
- Produces: `bool isHyperlinkModifierPressed({required bool isWindows, required bool isControlPressed, required bool isMetaPressed})`, `bool isLaunchableHyperlink(String? uri)`.

- [ ] **Step 1: Write the failing tests**

Create `test/hyperlink_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/hyperlink.dart';

void main() {
  group('isHyperlinkModifierPressed', () {
    test('Windows: control held is the modifier', () {
      const expected = true;

      final result = isHyperlinkModifierPressed(
        isWindows: true,
        isControlPressed: true,
        isMetaPressed: false,
      );

      expect(result, expected);
    });

    test('Windows: meta held is not the modifier', () {
      const expected = false;

      final result = isHyperlinkModifierPressed(
        isWindows: true,
        isControlPressed: false,
        isMetaPressed: true,
      );

      expect(result, expected);
    });

    test('Windows: neither held is not the modifier', () {
      const expected = false;

      final result = isHyperlinkModifierPressed(
        isWindows: true,
        isControlPressed: false,
        isMetaPressed: false,
      );

      expect(result, expected);
    });

    test('macOS: meta held is the modifier', () {
      const expected = true;

      final result = isHyperlinkModifierPressed(
        isWindows: false,
        isControlPressed: false,
        isMetaPressed: true,
      );

      expect(result, expected);
    });

    test('macOS: control held is not the modifier', () {
      const expected = false;

      final result = isHyperlinkModifierPressed(
        isWindows: false,
        isControlPressed: true,
        isMetaPressed: false,
      );

      expect(result, expected);
    });
  });

  group('isLaunchableHyperlink', () {
    test('http scheme is launchable', () {
      const expected = true;

      final result = isLaunchableHyperlink('http://example.com');

      expect(result, expected);
    });

    test('https scheme is launchable', () {
      const expected = true;

      final result = isLaunchableHyperlink('https://example.com/path?x=1');

      expect(result, expected);
    });

    test('file scheme is not launchable', () {
      const expected = false;

      final result = isLaunchableHyperlink('file:///etc/passwd');

      expect(result, expected);
    });

    test('a custom scheme is not launchable', () {
      const expected = false;

      final result = isLaunchableHyperlink('vscode://file/foo.dart');

      expect(result, expected);
    });

    test('null is not launchable', () {
      const expected = false;

      final result = isLaunchableHyperlink(null);

      expect(result, expected);
    });

    test('an unparseable uri is not launchable', () {
      const expected = false;

      final result = isLaunchableHyperlink('%');

      expect(result, expected);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/hyperlink_test.dart`
Expected: FAIL — `Error: Error when reading 'lib/hyperlink.dart': No such file or directory` (or equivalent "package:orthanc/hyperlink.dart" not found compile error).

- [ ] **Step 3: Write the minimal implementation**

Create `lib/hyperlink.dart`:

```dart
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/hyperlink_test.dart`
Expected: PASS — all 11 tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/hyperlink.dart test/hyperlink_test.dart
git commit -m "feat: pure decision helpers for hyperlink modifier and scheme"
```

---

### Task 2: Pin the xterm fork commit and add `url_launcher`

**Files:**
- Modify: `pubspec.yaml`
- Test: `test/hyperlink_test.dart` (new group, same file as Task 1)

**Interfaces:**
- Consumes: nothing new from Task 1.
- Produces: confirms `Terminal.hyperlinkAt(CellOffset)` is resolvable from `package:xterm/xterm.dart` at the pinned commit — Task 3 depends on this being real, not assumed.

- [ ] **Step 1: Write the failing test**

Add to `test/hyperlink_test.dart` (new import at the top, new group at the end of `main()`):

```dart
import 'package:xterm/xterm.dart';
```

```dart
  group('Terminal.hyperlinkAt (xterm fork integration)', () {
    test('resolves the URI for a cell inside an OSC 8 span', () {
      const expected = 'https://example.com';

      final terminal = Terminal(maxLines: 100);
      terminal.write('\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\');
      final result = terminal.hyperlinkAt(const CellOffset(0, 0));

      expect(result, expected);
    });

    test('returns null for a cell outside any hyperlink span', () {
      const expected = null;

      final terminal = Terminal(maxLines: 100);
      terminal.write(
        '\x1b]8;;https://example.com\x1b\\link\x1b]8;;\x1b\\ plain',
      );
      final result = terminal.hyperlinkAt(const CellOffset(5, 0));

      expect(result, expected);
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/hyperlink_test.dart`
Expected: FAIL — `The method 'hyperlinkAt' isn't defined for the type 'Terminal'` (the currently-pinned commit `a766197d21a516d7e949bb095acbea2b0b707e09` predates the OSC 8 work).

- [ ] **Step 3: Bump the pin and add `url_launcher`**

In `pubspec.yaml`, change the `dependency_overrides` block's `ref`:

```yaml
dependency_overrides:
  xterm:
    git:
      url: https://github.com/LarryHsiao/xterm.dart.git
      ref: 994d1e5ae5cb3be8efb2f6d96977006b763d9766
```

Extend the comment block directly above `dependency_overrides` (currently describing fixes 1 and 2) with a third entry, keeping the existing two untouched:

```yaml
# 3. OSC 8 (terminal hyperlinks) was unhandled entirely — the escape parser
#    only special-cased OSC 0/1/2 (title/icon); everything else, OSC 8
#    included, fell through to unknownOSC() and was dropped silently.
#    Adds Terminal.hyperlinkAt(CellOffset) -> String? and a dedicated
#    CellFlags.hyperlink underline bit. See
#    docs/superpowers/specs/2026-07-24-orthanc-osc8-hyperlinks-design.md.
#    Fork branch: orthanc-osc8-hyperlinks
#    Upstream PR: not filed
```

Add `url_launcher` to `dependencies` (alongside `flutter_pty` and `xterm`):

```yaml
  url_launcher: ^6.3.2
```

Run: `flutter pub get`
Expected: resolves cleanly, fetching the new commit.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/hyperlink_test.dart`
Expected: PASS — all 13 tests green (11 from Task 1, 2 new).

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock test/hyperlink_test.dart
git commit -m "feat: pin xterm fork's OSC 8 commit, add url_launcher"
```

---

### Task 3: Wire click-to-open and hover cursor into `PaneView`

**Files:**
- Modify: `lib/pane_view.dart`

**Interfaces:**
- Consumes: `isHyperlinkModifierPressed(...)`, `isLaunchableHyperlink(String?)` (Task 1); `Terminal.hyperlinkAt(CellOffset)` (Task 2, via `session.terminal`); `TerminalView`'s existing `onTapUp`, `mouseCursor` constructor parameters and its `TerminalViewState.renderTerminal.getCellOffset(Offset) -> CellOffset` (all pre-existing xterm API, unchanged by the fork patch).
- Produces: no new public interface — this is the leaf consumer.

No automated test for this task — see Global Constraints. Verification is the manual procedure in Step 3.

- [ ] **Step 1: Convert `PaneView` to a `StatefulWidget` and wire the two callbacks**

Replace the full contents of `lib/pane_view.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart';

import 'hyperlink.dart';
import 'pane_bar.dart';
import 'session.dart';

/// One pane: its bar, and the terminal beneath — unless [collapsed], in
/// which case only the bar renders, at its own fixed height, and the
/// terminal is skipped entirely. A pane's [Session] outlives this widget
/// either way.
class PaneView extends StatefulWidget {
  const PaneView({
    super.key,
    required this.session,
    required this.focused,
    required this.onFocus,
    required this.onKeyEvent,
    required this.canCollapse,
    required this.collapsed,
    required this.onToggleCollapse,
  });

  final Session session;
  final bool focused;
  final VoidCallback onFocus;
  final FocusOnKeyEventCallback onKeyEvent;
  final bool canCollapse;
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  @override
  State<PaneView> createState() => _PaneViewState();
}

class _PaneViewState extends State<PaneView> {
  final _terminalKey = GlobalKey<TerminalViewState>();
  MouseCursor _cursor = SystemMouseCursors.text;

  @override
  Widget build(BuildContext context) {
    // Listener sees every pointer down regardless of the gesture arena; a
    // GestureDetector here would compete with xterm's own tap recognizer and
    // routinely lose it on a brisk click.
    return Listener(
      onPointerDown: (_) => widget.onFocus(),
      child: Column(
        children: [
          GestureDetector(
            onTap: widget.canCollapse ? widget.onToggleCollapse : null,
            child: PaneBar(
              session: widget.session,
              focused: widget.focused,
              canCollapse: widget.canCollapse,
              collapsed: widget.collapsed,
            ),
          ),
          if (!widget.collapsed)
            Expanded(
              // xterm's RenderTerminal never clips its own paint, so a scroll
              // can draw rows past its box and into PaneBar above it. Clip
              // explicitly rather than rely on that render object doing it.
              child: ClipRect(
                child: MouseRegion(
                  onHover: _onHover,
                  onExit: (_) => _setCursor(SystemMouseCursors.text),
                  child: TerminalView(
                    key: _terminalKey,
                    widget.session.terminal,
                    focusNode: widget.session.focusNode,
                    onKeyEvent: widget.onKeyEvent,
                    onTapUp: _onTapUp,
                    mouseCursor: _cursor,
                    // xterm's built-in fallback list is Linux/Android-flavored
                    // and omits Hack Nerd Font Mono, so the Private-Use-Area
                    // glyphs shell tools (lsd, oh-my-posh, ...) use for icons
                    // render as tofu unless named explicitly here — a no-op
                    // fallback entry on a machine that lacks it.
                    //
                    // Apple Color Emoji / Segoe UI Emoji are deliberately absent:
                    // both claim dingbat codepoints that also have a plain-text
                    // glyph (Claude Code's spinner frames — ✢ ✳ ✻ ✽ — and its
                    // ⏺ paragraph bullet included), and being first in the list
                    // would win the match and render them in color instead of
                    // the monochrome glyph a native terminal shows.
                    //
                    // The trailing entries below are copied verbatim from the
                    // fork's private _kDefaultFontFamilyFallback (unexported,
                    // so not importable) — lib/src/ui/terminal_text_style.dart
                    // at the pinned pubspec.yaml ref. Re-sync if that list
                    // changes upstream.
                    textStyle: const TerminalStyle(
                      fontFamilyFallback: [
                        'Hack Nerd Font Mono',
                        'Menlo',
                        'Monaco',
                        'Consolas',
                        'Liberation Mono',
                        'Courier New',
                        'Noto Sans Mono CJK SC',
                        'Noto Sans Mono CJK TC',
                        'Noto Sans Mono CJK KR',
                        'Noto Sans Mono CJK JP',
                        'Noto Sans Mono CJK HK',
                        'Noto Color Emoji',
                        'Noto Sans Symbols',
                        'monospace',
                        'sans-serif',
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onHover(PointerHoverEvent event) {
    final state = _terminalKey.currentState;
    if (state == null) return;
    final offset = state.renderTerminal.getCellOffset(event.localPosition);
    final launchable =
        _isLinkModifierHeld() && _launchableHyperlinkAt(offset) != null;
    _setCursor(launchable ? SystemMouseCursors.click : SystemMouseCursors.text);
  }

  void _onTapUp(TapUpDetails details, CellOffset offset) {
    if (!_isLinkModifierHeld()) return;
    final uri = _launchableHyperlinkAt(offset);
    if (uri == null) return;
    launchUrl(Uri.parse(uri));
  }

  void _setCursor(MouseCursor cursor) {
    if (cursor == _cursor) return;
    setState(() => _cursor = cursor);
  }

  bool _isLinkModifierHeld() {
    final keys = HardwareKeyboard.instance;
    return isHyperlinkModifierPressed(
      isWindows: Platform.isWindows,
      isControlPressed: keys.isControlPressed,
      isMetaPressed: keys.isMetaPressed,
    );
  }

  String? _launchableHyperlinkAt(CellOffset offset) {
    final uri = widget.session.terminal.hyperlinkAt(offset);
    return isLaunchableHyperlink(uri) ? uri : null;
  }
}
```

- [ ] **Step 2: Run the full test suite to confirm nothing regressed**

Run: `flutter test`
Expected: PASS — every existing test still green (this task changes no tested surface; `PaneView` has no test file), plus the 13 hyperlink tests from Tasks 1-2.

Run: `flutter analyze`
Expected: no new issues.

- [ ] **Step 3: Manual verification (no automated test covers gesture/rendering wiring)**

Run: `flutter run -d windows` (and again on macOS if available).

1. In the spawned shell, run a command that emits a real OSC 8 link, e.g.:
   - PowerShell/cmd on Windows: `printf` isn't built in, so use `[Console]::Write("$([char]27)]8;;https://example.com$([char]7)click me$([char]27)]8;;$([char]7)`)` in PowerShell, or run `claude` and ask it to print a markdown link (Claude Code emits OSC 8 for links in its own output).
   - macOS/Linux shell: `printf '\e]8;;https://example.com\e\\click me\e]8;;\e\\\n'`
2. Confirm "click me" renders underlined immediately (no hover or modifier needed).
3. Hover over "click me" without any modifier held — cursor stays the normal text-beam cursor.
4. Hold Ctrl (Windows) / Cmd (macOS) and hover over "click me" — cursor becomes a pointing hand **precisely over the underlined glyphs**, not merely somewhere in the pane (the click path and the hover path compute the cell position two different ways — see the design doc's Watch out section — so this is the one thing static review couldn't confirm).
5. Ctrl/Cmd+click "click me" — the system default browser opens `https://example.com`.
6. Plain click (no modifier) on "click me" — nothing opens; existing focus behavior (pane gains focus) still works.
7. Emit a `file://` link the same way and confirm it renders underlined but Ctrl/Cmd+click does nothing.
8. Click and hover on ordinary, non-link terminal text — behaves exactly as before this change (text cursor, no accidental launches).
9. Scroll a link up into scrollback (e.g. print enough lines after it), scroll back up, and repeat step 4 against the scrolled link — confirm the hand still lands on the right glyphs.
10. Hover a link with the modifier held so the hand cursor appears, then release the modifier **without moving the mouse** — the hand persists until the next pointer move. This is a known, accepted gap (see design doc Watch out), not a regression to chase.

If any of 2-9 fails, the bug is in this task's wiring, not the fork (already covered by 18 passing tests there) — re-check the coordinate math in `_onHover` and the modifier/scheme gating before suspecting the pinned dependency.

- [ ] **Step 4: Commit**

```bash
git add lib/pane_view.dart
git commit -m "feat: Ctrl/Cmd+click opens OSC 8 hyperlinks, hover shows pointer cursor"
```
