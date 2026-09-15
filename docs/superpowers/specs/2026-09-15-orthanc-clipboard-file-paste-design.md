# Orthanc — Clipboard File Paste Design

## Goal

When the user copies a file in Finder or Explorer, then pastes into an
Orthanc pane — right-click "Paste", Windows' `Ctrl+Shift+V`, or macOS's
`Cmd+V` — write the file's real path into that pane's pty, in the exact
same form the already-shipped file-drop feature produces. Fall back to
ordinary text-paste when the clipboard holds no plausible file.

## Why this, and why now

The file-drop feature (`8ff2826`, `203d066`) taught Orthanc to hand Claude
Code a real file — `@/abs/path` when a program owns the pane, so an image
loads as image content, not a filename. Copy-and-paste is the other gesture
users reach for without thinking, and it was a silent no-op: copy a file,
press Paste, nothing happens.

The reason is architectural, not an oversight. `Clipboard.getData(Clipboard.kTextPlain)`
cannot see a copied file at all. On Windows, Explorer's file-copy never
populates `CF_UNICODETEXT`, only `CF_HDROP`. On macOS, Finder's file-copy
*does* put a text flavor on the pasteboard, but it holds the bare filename
(`"report.pdf"`), not the POSIX path — the full path is a separate
`Option+Cmd+C` gesture nobody is taking here. Reading the clipboard's real
file reference needed a new dependency.

## Decisions

1. **`pasteboard: ^0.5.0`** (mixin.dev, same verified publisher as
   `desktop_drop`). Reads real file paths on both platforms via
   `Pasteboard.files()`, no Rust, three pure-Dart transitive deps. Rejected:
   `super_clipboard`, which works but needs Rust or downloads precompiled
   binaries at build time — the same objection that ruled it out for the
   file-drop feature's own dependency choice.

2. **File wins over text.** `Pasteboard.files()` is checked first; only an
   empty or implausible result falls through to a text paste.

3. **The macOS false-positive guard.** `Pasteboard.files()`'s native call
   (`NSPasteboard.readObjects(forClasses: [NSURL.self], options: nil)`)
   omits `urlReadingFileURLsOnly`, so a copied *web link* can come back
   looking like a file path — `https://example.com/a/b` yields `/a/b`,
   absolute and plausible-looking. Guarded in `pastedFilePaths` by
   requiring the path to both look absolute (`looksLikePath`, reused from
   `session_path.dart`) and exist on disk (`File.existsSync`, injected for
   testability, matching `executableExists`'s own precedent in
   `settings_validation.dart`).

4. **macOS `Cmd+V` is intercepted, without a fifth `xterm` fork patch.**
   See *The mechanism* below.

5. **Windows plain `Ctrl+V` stays untouched.** The existing `Ctrl+Shift+V`
   workaround (`54a50b0`) is Orthanc's own chord ahead of the terminal —
   this feature rides that same path for free. Plain `Ctrl+V` remains
   exactly as unreliable as it always was; fixing it is out of scope.

6. **The Paste menu item's enablement is unchanged** — always offered,
   no-op on nothing to paste. Gating it on clipboard content would need
   async probing at synchronous menu-build time, for a cosmetic gain that
   doesn't justify the new infrastructure.

7. **`dropPathsInto` is not renamed**, even though paste now calls it too.
   Mechanically identical work — "write these paths into this session, in
   the right form" — regardless of which gesture produced them. Renaming
   shipped, tested code for naming purity alone would be pure churn against
   this repo's surgical-changes habit; a doc-comment names the second
   caller instead.

## The mechanism that makes `Cmd+V` interceptable — and the bug that nearly broke it

`TerminalView` (the pinned `xterm` fork) hard-codes `child = TerminalActions(...)`
in its own `build()`, with no override slot — `TerminalActions`'s `Actions`
widget handles exactly `PasteTextIntent`/`CopySelectionTextIntent`/`SelectAllTextIntent`,
each inline. It does expose a public `shortcuts:` constructor parameter
feeding its internal `ShortcutManager`, though.

`lib/terminal_paste_shortcuts.dart` gives `TerminalView` a `shortcuts:` map,
built only on macOS, rebinding `Cmd+V` to a private `PanePasteIntent`
instead of the stock `PasteTextIntent`. `PaneView` wraps its terminal
subtree in its own `Actions` widget handling `PanePasteIntent`. Because
`Actions.maybeFind` specializes on the Intent's runtime type and searches
*outward* from the focused node, and `TerminalActions` (nested inside
`TerminalView`, always nearer the focus than anything wrapping it) has no
handler for this unfamiliar type, resolution falls through past it to
`PaneView`'s own wrapper. No fork patch needed.

`Actions`/`Shortcuts` register no `GestureRecognizer`, hit-test nothing, and
consume no layout — wrapping the terminal subtree in one does not violate
the file-drop plan's "no new gesture handling in the
`TerminalView`/`ClipRect`/`MouseRegion` region" constraint, whose actual
concern (contending in the gesture arena against xterm's own tap
recognizer) doesn't apply to keyboard-intent routing.

**The trap, verified directly against Flutter's own source before trusting
it:** `SingleActivator` declares no `operator==` — the only `operator==` in
`flutter/lib/src/widgets/shortcuts.dart` belongs to the unrelated `KeySet`.
The fork's own default shortcut map also builds its keys non-`const`. So
`map[SingleActivator(keyV, meta: true)] = ourIntent` does not replace the
existing Cmd+V entry — it silently adds a second one, using Dart's default
identity equality. `ShortcutManager` resolves the *first* accepting
activator in insertion order, so the stale entry would keep winning, Cmd+V
would keep doing exactly what it does today, and nothing would ever error.

`terminalPasteShortcuts` fixes this by removing the existing entry by
predicate (matching on trigger key and exact modifier set) before
inserting the replacement. Its own test — `binds exactly one activator to
Cmd+V` — exists precisely because this failure is invisible both to a
casual read and at runtime.

**A second, self-inflicted trap, caught only by deliberately trying to
break the test:** the regression test's own `defaults` fixture was first
written as a `const` map. Dart canonicalizes `const` values, so the
fixture's `SingleActivator(keyV, meta: true)` key was silently identical to
the implementation's own replacement key — which meant even the *naive,
buggy* implementation (assignment without the remove-by-predicate step)
passed the test. Verified by temporarily reverting to the naive
implementation and confirming the test still passed; the fixture was then
rebuilt non-`const`, exactly matching the real fork's own
`final _defaultAppleShortcuts = {...}` shape, and the same revert-and-check
cycle confirmed the corrected test now fails loudly against the naive code
and passes only against the real fix.

**A third trap, caught by the widget test suite failing outright:**
`debugDefaultTargetPlatformOverride` (needed so `defaultTerminalShortcuts`
resolves to the Apple map inside `flutter_test`, which defaults to Android)
cannot be reset via `tearDown()` or `addTearDown()` — both fire only after
Flutter's own end-of-test invariant check has already run, confirmed by
reading `testWidgets`'s own source. The reset must happen synchronously
inside the test body itself, via `try`/`finally`, wrapped in a
`testMacOSWidget` helper every test in `pane_view_paste_test.dart` uses in
place of `testWidgets` directly.

## Architecture

**`lib/pasted_file_paths.dart`** (new) — `pastedFilePaths(candidates, {required exists})`,
the pure plausibility filter: `looksLikePath` + injected existence check.

**`lib/terminal_paste_shortcuts.dart`** (new) — `PanePasteIntent` and
`terminalPasteShortcuts({required isMacOS, required defaults})`, the pure,
tested shortcut-map override with the remove-by-predicate fix.

**`lib/session_clipboard.dart`** — `pasteIntoSession` extended:

```dart
Future<void> pasteIntoSession(
  Session session, {
  required bool isWindows,
  Future<List<String>> Function()? readFiles,
  bool Function(String)? fileExists,
}) async {
  final files = pastedFilePaths(
    await (readFiles ?? Pasteboard.files)(),
    exists: fileExists ?? (path) => File(path).existsSync(),
  );
  if (files.isNotEmpty) {
    dropPathsInto(session, files, isWindows: isWindows);
    return;
  }
  // existing text-paste branch, unchanged
}
```

`readFiles`/`fileExists` are injected only for tests — real callers pass
neither, and `pane_view_paste_test.dart` is the one file that exercises the
real `pasteboard` channel and real filesystem end to end; every other test
covering `pasteIntoSession`'s precedence logic uses the injected seams,
keeping the channel-mocking surface small.

**`lib/pane_view.dart`** — a `late final _shortcuts` field (not rebuilt per
frame: `TerminalView.didUpdateWidget` reassigns its `ShortcutManager` on
every rebuild, and fresh `SingleActivator` instances every frame would
defeat that setter's own equality-based no-op guard), passed as
`shortcuts:` to `TerminalView`; an `Actions` widget wrapping the `ClipRect`
supplying `CallbackAction<PanePasteIntent>` that calls
`pasteIntoSession(widget.session, isWindows: Platform.isWindows)` — the
same call the right-click menu already makes, just from a third caller.

**Three call sites total**: the right-click menu (`pane_view.dart`),
Windows `Ctrl+Shift+V` (`workspace_view.dart`'s `_pasteIntoFocused`), and
the new macOS `Cmd+V` handler — all pass `isWindows: Platform.isWindows`
explicitly, matching `dropPathsInto`'s own established convention of
reading `Platform` once at the real I/O boundary rather than inside
testable code.

## Testing

| Unit | Tested by |
|---|---|
| `pastedFilePaths` — absolute+exists kept, relative dropped, absolute+missing dropped (the Safari case), empty string dropped, Windows drive path kept, order preserved, empty input → empty output | unit tests, no engine |
| `terminalPasteShortcuts` — null off macOS, exactly one Cmd+V entry (the duplicate-key regression), that entry is `PanePasteIntent`, Cmd+C/Cmd+A untouched, the input map is not mutated | unit tests, no engine — the fixture is deliberately non-`const`, matching the real fork |
| `pasteIntoSession` — file-vs-text precedence, fallback on no plausible file, selection cleared on a file paste too, cmd.exe space-joining | widget tests via the injected seams, no channel mock |
| Right-click menu's existing Paste tests | widget tests, `pasteboard` channel mocked to return `[]`, proving the text path is explicitly unchanged rather than relying on an unmocked channel's null-safe fallback |
| macOS Cmd+V — file with a program-owned pane, file with an idle shell, no file falls back to text, file wins when both present, nothing to paste writes nothing, the web-link guard rejects a non-existent path; **Cmd+C still copies, Cmd+A still selects all, an unrelated key still reaches the terminal** | widget tests, the one file that mocks the `pasteboard` channel and exercises real key-press simulation and real `File.existsSync` |
| Copy a `.png` on a live Claude Code pane and see it loaded as image content; the web-link guard against a real Safari copy; ordinary Cmd+V/Cmd+C/Cmd+A; multi-file copy-paste; right-click Paste and Windows `Ctrl+Shift+V` both picking up a copied file; focus targeting with two split panes | by hand, both platforms |

## Definition of done

Copying a file and pasting — by any of the three gestures — writes its
path into the target pane's pty, quoted correctly for the pane's shell and
prefixed with `@` when a program owns the pane; copying text still pastes
as text, unchanged; a copied web link is never mistaken for a file; Cmd+C
and Cmd+A on macOS are unaffected by the Cmd+V rewiring; and — the claim
that earns the feature — copying an image in Finder and pasting it into a
running Claude Code pane makes Claude describe the image, not recite its
filename.

## Deferred, with reasoning recorded

- **Conditionally enabling the Paste menu item** based on clipboard
  content — needs async probing at synchronous menu-build time; not worth
  new infrastructure for a cosmetic gain.
- **A fix for the plain-text/file-path ambiguity** named in *Unverified*
  below, if the hand check finds it real.

## Watch out

- `pasteIntoSession`'s real call sites pass no `fileExists` override, so
  the macOS false-positive guard depends on the actual filesystem at paste
  time — a path that exists at the moment of paste but is deleted a moment
  later races harmlessly (the paste already captured the text), but a
  network-mounted or slow filesystem could make `existsSync` itself slow
  enough to notice on a very large clipboard payload. Not measured.
- The replacement Cmd+V entry inherits `SingleActivator`'s default
  `includeRepeats: true`, so a held Cmd+V costs a platform round-trip plus
  a filesystem check per repeat — unchanged in kind from before this
  feature (which also round-tripped per repeat), but now with an added
  filesystem check. Kept deliberately; revisit if felt in practice.
- `Session.executable`'s staleness (a user running another shell inside a
  pane) affects `isCmdShell` here exactly as it already does for file-drop
  — inherited, not introduced.

## Verified by hand

**2026-09-15, macOS:** both `Cmd+V` and the right-click "Paste" menu item
were confirmed working by hand.

## Unverified — to be settled during implementation

1. **Whether `NSPasteboard.readObjects(forClasses: [NSURL.self])` also
   reads plain-string pasteboard entries** — if it does, copying the
   *literal text* `/etc/hosts` and pasting could produce `@/etc/hosts`
   instead of plain text, since both plausibility gates would pass. The
   macOS pass above did not specifically exercise this case. Settled by
   hand: copy the literal text `/etc/hosts`, paste, see which form lands.
   If it fires, the narrow fix: prefer text whenever `Clipboard.getData`'s
   string equals the single candidate path exactly, since a genuine
   Finder file-copy's text flavor is the *basename*, never the full POSIX
   path.
2. **The whole feature on Windows** — this development machine is
   macOS-only, the same limitation the file-drop design already carries.
