# Clipboard File Paste Implementation Plan

**Goal:** Copying a file in Finder or Explorer, then pasting into an
Orthanc pane, writes the file's real path into that pane's pty — the same
`@`-vs-bare-path form the file-drop feature already produces. See the
paired design doc, `2026-09-15-orthanc-clipboard-file-paste-design.md`,
for the full reasoning, including the two subtle bugs caught during
implementation and how each was verified as actually fixed.

**Architecture:** A new `pasteboard` dependency reads real file paths off
the clipboard on both platforms. A pure plausibility filter
(`pasted_file_paths.dart`) rejects anything that isn't both an absolute
path and real on disk, closing a macOS-specific false-positive where a
copied web link can look like a file. `session_clipboard.dart`'s
`pasteIntoSession` checks that filter first and falls back to ordinary
text-paste otherwise, reusing the file-drop feature's own
`dropPathsInto` to write whatever it finds. macOS's `Cmd+V` — which never
reached Orthanc's own code before this feature, intercepted a layer down
inside the pinned `xterm` fork — is rerouted through a custom `Intent` type
and an `Actions` wrapper, without a fifth fork patch.

**Tech Stack:** Flutter/Dart, `flutter_test`, `pasteboard: ^0.5.0`.

## Global Constraints

- Match existing test style exactly: `group`/`test`, a named `expected`
  constant declared before the call, one assertion comparing against it.
- Pure decisions live in their own top-level-function file with their own
  test — `pasted_file_paths.dart` and `terminal_paste_shortcuts.dart`
  follow `dropped_paths_text.dart`'s shape.
- `Platform.isWindows`/`Platform.isMacOS` are read once, at the real I/O
  boundary, and threaded through as explicit parameters — never read
  inline inside code meant to stay testable.
- No new gesture handling in the `TerminalView`/`ClipRect`/`MouseRegion`
  region — an `Actions`/`Shortcuts` wrapper is not a gesture handler and
  does not violate this, but nothing pointer-related may be added there.
- A `SingleActivator` map entry must never be replaced by direct
  assignment against a freshly constructed key — `SingleActivator` has no
  `operator==`, so this silently adds a duplicate rather than replacing.
  Always remove by predicate first.
- Any test fixture standing in for a shortcut map that must faithfully
  reproduce identity-based lookup behavior (i.e. anything meant to catch
  the trap above) must be built non-`const` — a `const` fixture
  canonicalizes its keys and silently hides this exact class of bug.

## Tasks

- [x] **Step 1 — the dependency and the filter, wired to nothing.**
  Added `pasteboard: ^0.5.0` to `pubspec.yaml`. New
  `lib/pasted_file_paths.dart` and its test (7 cases). Verified the
  channel/method names (`'pasteboard'`, `'files'`) against the actually
  resolved package source, not just its GitHub `main` branch.

- [x] **Step 2 — the core: right-click Paste and Windows `Ctrl+Shift+V`
  pick up a copied file.** Extended `pasteIntoSession` in
  `lib/session_clipboard.dart` with the file-first branch and injected
  test seams. Updated all three then-existing call sites
  (`pane_view.dart`, `workspace_view.dart`, and the pre-existing tests) to
  pass `isWindows`. Added precedence tests to `test/session_clipboard_test.dart`
  and a `pasteboard` channel mock to `test/pane_view_test.dart`'s existing
  clipboard group so its Paste tests keep proving the menu's text path is
  explicitly unchanged.

- [x] **Step 3 — the macOS `Cmd+V` interception.** New
  `lib/terminal_paste_shortcuts.dart` (`PanePasteIntent` +
  `terminalPasteShortcuts`, remove-by-predicate) and its test — caught,
  by deliberately reverting to the naive implementation and re-running,
  that the test's own fixture was flawed (a `const` map hid the exact bug
  the test was meant to catch); fixed the fixture, re-confirmed the naive
  code now fails and the real fix passes. Wired `_shortcuts` and an
  `Actions` wrapper into `lib/pane_view.dart`. New
  `test/pane_view_paste_test.dart` — 9 cases, including the three
  regressions (Cmd+C, Cmd+A, an unrelated key) this whole file exists to
  prove. Caught and fixed a second bug along the way:
  `debugDefaultTargetPlatformOverride` cannot be reset via `tearDown()`/
  `addTearDown()` (both fire after Flutter's own end-of-test invariant
  check), so every test in the file runs through a `testMacOSWidget`
  wrapper that resets it synchronously in a `finally` clause instead.

- [x] **Step 4 — documentation.** This plan; the paired design doc;
  `CHANGELOG.md`; `README.md`.

## Verification

`flutter analyze` clean and the full `flutter test` suite green at the
close of every step (548 tests at the close of Step 3, up from 521 at the
start). `flutter build macos --debug` succeeds at the close of Steps 1 and
3. Two implementation-time bugs were caught not by inspection but by
deliberately reverting to the broken version and confirming the test
suite actually failed against it — see the design doc's *The mechanism*
section for both. Physical checks — the `.png`-on-Claude-Code claim, the
web-link guard against a real Safari copy, ordinary Cmd+C/Cmd+A/Cmd+V,
multi-file paste, and the whole feature on Windows — are the operator's to
run by hand; see the design doc's *Unverified* section.
