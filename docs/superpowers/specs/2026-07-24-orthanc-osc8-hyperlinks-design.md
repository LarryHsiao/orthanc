# Orthanc — OSC 8 Terminal Hyperlinks

## Goal

Let the user open a hyperlink a running program emits via OSC 8 (`ls
--hyperlink=always`, `git log`, Claude Code's own links, and any other
OSC-8-aware tool) — Ctrl+click on Windows/Linux, Cmd+click on macOS. Link
text always renders underlined; the pointer cursor appears only while
hovering a link with the modifier held. Only `http`/`https` schemes are
launchable.

## Why this, and why now

Investigated via a handoff from a prior session: OSC 8 is not handled at
all today. The pinned `xterm.dart` fork's escape parser only special-cases
OSC 0/1/2 (title/icon); everything else, OSC 8 included, falls through to
`handler.unknownOSC()` and is dropped silently. No hyperlink bit exists on
the cell model, and no URL-launch wiring exists anywhere in the app. Both
hook points needed to build this (`Terminal.onPrivateOSC`,
`TerminalView.onTapUp`) already existed before this change, but neither is
wired to anything.

## Decisions

1. **Ctrl/Cmd+click, not plain click.** Today a plain click in the terminal
   does nothing (`onTapUp` was never wired, and a click alone doesn't start
   a selection without a drag), so a plain-click-opens design was viable —
   but the modifier matches the convention every other terminal on both
   target platforms already uses (iTerm2, Windows Terminal, VS Code's
   integrated terminal), leaving plain click free for the future should
   click-driven selection ever get built.

2. **Underline always shown for link cells; pointer cursor only on
   hover+modifier.** This pairs a static, cheap-to-render affordance
   (underline, driven by a per-cell flag exactly like SGR underline is)
   with a dynamic one (cursor swap) gated on the same modifier that
   actually triggers the click — so the cursor changing to a hand is a
   direct, honest preview of "this click will do something," not a
   decorative hover effect.

3. **Hyperlink underline is a distinct flag bit, not a reuse of the SGR
   underline bit.** Reusing the existing bit would have been simpler (zero
   painter changes) but risks clobbering a program's own explicit underline
   state if it happens to coincide with a link — e.g. link text closing
   would incorrectly also clear real SGR underline that started before the
   link opened. A dedicated bit costs one extra condition in the painter's
   existing underline-stroke check and avoids the correctness risk
   entirely.

4. **Only `http`/`https` schemes launch.** OSC 8 lets a program claim any
   URI — `file://`, custom protocol handlers, etc. A malicious or merely
   careless process piping untrusted output through the terminal (e.g.
   `cat`-ing an attacker-controlled file) could otherwise get a user to
   trigger a local-file open or protocol handler via what looks like a
   normal link. Other schemes still render underlined (they're real,
   detected links) but are inert on click — no error, no toast, just no
   action. This is a deliberate, narrow safety default, not a general
   sandboxing scheme.

5. **The xterm.dart fork change lives in a separate repo/session, forwarded
   by handoff.** This worktree's directory guard cannot reach outside
   itself, and the fork (`LarryHsiao/xterm.dart`) is a distinct git
   repository consumed via `dependency_overrides`, the same way the two
   prior fixes (SGR private-marker parsing, missing `viewId`) were done.
   The fork-side spec was hand-written and sent whole via
   `/handoff send xterm.dart`, then implemented and pushed independently —
   see Architecture below for what actually landed.

## Architecture

### Fork side (`xterm.dart`, already implemented — commit `994d1e5` on
`orthanc-osc8-hyperlinks`, branched from `orthanc-integration`)

- **Storage.** `BufferLine` gained a 5th per-cell field (link id, 0 = none)
  alongside foreground/background/attributes/content. Because the buffer's
  resize/copy/insert/remove paths already move cells generically, this
  survives scrollback, reflow, and resize without further changes.
  `CellData` and `CursorStyle` both carry the matching `linkId` field.
- **Flag bit.** `CellAttr.hyperlink` / `CellFlags.hyperlink` = `1 << 8` (the
  next free bit after `strikethrough`), set/cleared by
  `CursorStyle.openHyperlink(id)` / `closeHyperlink()`, mirroring the
  existing bold/underline pattern exactly.
- **Parsing.** `EscapeParser._escHandleOSC` gained a dedicated `case '8':`
  that parses the `params;URI` pair and calls the two new `EscapeHandler`
  methods, `openHyperlink(String uri)` / `closeHyperlink()` — implemented on
  `Terminal`, which registers each opened link in an internal
  `Map<int, String>` id→URI table and opens/closes the id on the cursor.
- **Lookup.** `Terminal.hyperlinkAt(CellOffset offset)` resolves a buffer
  position to its URI (`null` if none). `TerminalView.onTapUp`'s
  `CellOffset` is already absolute-buffer-indexed via
  `RenderTerminal.getCellOffset`, matching `terminal.buffer.lines` directly
  — no coordinate translation needed on the Orthanc side.
- **Rendering.** `painter.dart`'s existing underline-stroke condition now
  triggers on `CellFlags.underline | CellFlags.hyperlink`, reusing the
  existing stroke-drawing code path unchanged.
- **Known deviation from the original spec:** `EscapeHandler` has a third
  implementer beyond `Terminal` — `lib/src/utils/debugger.dart`, an
  internal debug logger — which needed matching (no-op) `openHyperlink`/
  `closeHyperlink` overrides to keep compiling. Mechanical, no behavior
  implications.
- **Tests.** 18 new tests (parser open/close + flag/id correctness, buffer
  survival across resize/reflow/scrollback, `hyperlinkAt` resolution
  including the closed-link and outside-span cases, painter underline on
  the new bit alone). Full suite: 130 tests green; the 2 pre-existing
  golden pixel-diff failures are unrelated and present on the
  `orthanc-integration` baseline already.

### Orthanc side (this repo — to build)

- **`pubspec.yaml`**: bump `dependency_overrides.xterm.ref` to `994d1e5`;
  add `url_launcher`.
- **Click-to-open.** `PaneView` wires `TerminalView.onTapUp`. On tap-up,
  when the platform modifier (`HardwareKeyboard.instance.isControlPressed`
  on Windows/Linux, `isMetaPressed` on macOS) is held and
  `session.terminal.hyperlinkAt(offset)` resolves to an `http`/`https` URI,
  launch it via `url_launcher`. Otherwise a no-op — today's tap-up behavior
  (none; the callback was never wired) is unaffected for every other case.
- **Hover cursor.** `PaneView` holds a `GlobalKey<TerminalViewState>` per
  session to reach `renderTerminal.getCellOffset()`, the same conversion
  `onTapUp` already uses internally. A `MouseRegion.onHover` wrapping the
  `TerminalView` recomputes, on each pointer move, whether the modifier is
  held and the pointer sits over a live link, and swaps a
  `ValueNotifier<MouseCursor>` between `SystemMouseCursors.text` (today's
  default) and `SystemMouseCursors.click`.

## Testing

| Unit | Tested by |
|---|---|
| Fork: OSC 8 parse open/close, buffer survival, `hyperlinkAt` resolution, painter underline | done — 18 tests, fork repo |
| Modifier check (`isHyperlinkModifierPressed`) and scheme allow-list (`isLaunchableHyperlink`) — the pure decisions the wiring below is built from | unit test, no engine |
| `Terminal.hyperlinkAt` resolves correctly against the pinned fork commit (integration smoke test, not a re-test of the fork's own 18) | unit test, no engine |
| Modifier-gated tap-to-open, hover cursor swap, underline rendering, actual browser opening, both platforms | by eye, running the app — this codebase has no widget-test harness for gesture/rendering wiring (`PaneBar`, `PaneView`, `SplitView` all follow this precedent already; see `docs/superpowers/plans/2026-07-23-orthanc-pane-collapse.md`'s Global Constraints), and retrofitting one just for this feature's tap/hover callbacks would add an injection seam (a fake `launchUrl`) the rest of the codebase doesn't use |

## Definition of done

Ctrl+click (Windows) / Cmd+click (macOS) on `http`/`https` link text opens
it in the system browser; the same click on a non-http(s) link or non-link
text does nothing; link text is always underlined; the pointer becomes a
hand only while hovering a link with the modifier held — confirmed by hand
on both platforms.

## Deferred — not in this change

- Non-`http`/`https` scheme handling (e.g. offering to reveal a `file://`
  path in Explorer/Finder instead of launching it).
- Link-id deduplication (OSC 8's optional `id=` parameter) — every open
  allocates a fresh id; harmless, just not maximally memory-efficient.
- Eviction of scrolled-off links from `Terminal._hyperlinks` — accepted as
  a known, bounded-impact limitation (a few KB even over a long session).
- Upstreaming the fork's change to `TerminalStudio/xterm.dart` — optional,
  not required to unblock Orthanc, left to whoever wants to pursue it.

## Watch out

- The hover-cursor's modifier check only re-evaluates on pointer movement,
  not on modifier keydown/keyup while the mouse is stationary — a small,
  accepted UX gap, not a bug to chase.
- `HardwareKeyboard.instance.isMetaPressed` vs `isControlPressed` must be
  chosen per-platform correctly, or macOS users get no working modifier at
  all — worth a specific by-hand check on macOS during the walk, since this
  worktree's own dev loop is Windows-first.
