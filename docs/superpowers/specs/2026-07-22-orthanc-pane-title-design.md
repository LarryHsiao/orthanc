# Orthanc — Pane Title: Name, Activity, and Idle pwd

## Goal

Each pane's title bar (`PaneBar`, added in Milestone 1) currently shows one
string: whatever the running program last set via OSC. In practice that string
gets overwritten in ways that lose information the user wants to keep seeing
at once — Claude Code renaming its session drops the activity that was
showing a moment before, and once Claude exits back to the shell, the stale
Claude-set title lingers instead of reflecting where the shell actually is.

This spec covers three related fixes, all touching how a pane's title state is
tracked and displayed:

1. Show the Claude session's name *and* its current activity together, not
   whichever one was set most recently.
2. When Claude exits back to the shell prompt, the pane bar reflects the
   shell's current working directory instead of a stale Claude title.
3. The OS window title bar is explicitly untouched — this is all in-app,
   inside `PaneBar`.

## Why this, and why in this shape

Milestone 1's design deliberately kept the title dumb: "the title comes from
the program, not from us" (`2026-07-21-orthanc-milestone-1-design.md`,
decision 6) — no parsing, no heuristics. That principle survives here. The fix
is not to sniff Claude's title strings for meaning; it's to notice that
terminals already expose **two independent title channels** — OSC 1 ("icon
name") and OSC 2 ("window title") — and that the xterm.dart fork Orthanc
pins already parses both separately (`Terminal.setTitle` /
`Terminal.setIconName`, `terminal.dart:893,898`), while `Session` today wires
up only one (`onTitleChange`). If Claude Code sends its session name on one
channel and its current-task activity on the other, Orthanc can track both
without inventing any string-content heuristics — the same "no parsing, no
guessing" discipline M1 already committed to.

The idle-pwd behavior follows the same discipline from a different angle.
Orthanc has no semantic signal for "the child process just exited" — a pty
exposes only raw bytes. The one channel-consistent, protocol-level signal
available is the shell redrawing its own prompt. Shell-integration tools
(VS Code, iTerm2, Starship) solve exactly this by injecting a small hook that
re-announces the title on every prompt. Doing the same here, and doing it on
OSC 2 specifically (never OSC 0, which would also stomp the OSC 1 name
channel), keeps the design self-consistent: OSC 2 is "current status" no
matter who's driving it — pwd when idle, Claude's activity when Claude runs.
OSC 1 stays Claude's alone, untouched by the shell.

## Open question, resolved by a verification step, not a guess

Whether Claude Code actually splits name and activity across OSC 1 and OSC 2
is unverified as of this spec. Rather than block design on a fact that can
only be checked by running Claude Code, implementation's first task is a
cheap, non-interactive check (capturing raw output bytes around a short
Claude Code invocation) to confirm which channel carries which. If Claude
Code turns out not to separate them — e.g. it only ever sets OSC 0, which sets
both channels to the same string — `name` simply never diverges from
`activity`, and the pane bar's combine logic (below) degrades to showing
`activity` alone: today's behavior, no regression, no special-casing needed to
achieve that fallback.

**Verified 2026-07-22:** No separation. Capturing `claude`'s raw output via
`script` shows it sets its title with `ESC ] 0 ; ✳ Claude Code BEL` — OSC 0,
confirmed byte-for-byte (`od -c` on the capture) — never OSC 1 or OSC 2 alone.
Per OSC 0's own semantics (and the xterm.dart parser Orthanc pins:
`parser.dart:1081-1084`), that sets the icon-name and window-title channels to
the *identical* string in one call. The consequence is more specific than
"`name` never populates": `name` and `activity` will always be equal
whenever Claude sets a title, since both notifiers fire from the same event
with the same value. `paneTitle()`'s combine rule (decision 2) must guard
against `name == activity`, not merely `name.isEmpty`, or the pane bar will
show a duplicated `"✳ Claude Code — ✳ Claude Code"` instead of falling back
to the single-field display this fallback was meant to produce.

## Decisions

1. **Two `ValueNotifier<String>` fields on `Session`, replacing the single
   `title`.** `activity` is driven by `onTitleChange` (OSC 2): Claude's
   current task while it runs, the shell's pwd while idle. `name` is driven by
   a new `onIconChange` wiring (OSC 1): Claude's session/conversation name,
   set only when Claude renames it, empty until then.

2. **`PaneBar` combines them as `"$name — $activity"` when a name is set and
   differs from `activity`, or `activity` alone otherwise.** An empty `name`
   is simply omitted rather than shown as a dash or placeholder; a `name`
   equal to `activity` — the confirmed OSC 0 case, where both notifiers fire
   from the same event with the same string — collapses to the same
   activity-only display, rather than showing the value twice.

3. **A shell prompt hook resets `activity` to the pwd on every prompt
   redraw.** The pane's shell is launched with a small init script — sourcing
   the user's real rc file first, then adding a precmd/PROMPT_COMMAND hook —
   that emits an OSC 2 update on each prompt. Scoped to what
   `shellCommand()` (`lib/shell_command.dart`) actually spawns today: bash/zsh
   on macOS, `cmd.exe` on Windows. Other shells (fish, PowerShell, etc.) are
   not handled — see Deferred.

4. **The OS window title bar is untouched.** Confirmed explicitly during
   design discussion: "the title" the user meant throughout was always
   `PaneBar`'s in-app strip, never the native window chrome, which stays a
   fixed string as it is today.

5. **No manual rename UI.** Both `name` and `activity` are program-set only,
   consistent with M1 decision 6 ("the title comes from the program, not from
   us"). A user-facing rename control is explicitly out of scope here.

## Architecture

Changes are confined to the same four units M1 already established
(`Session`, `Sessions`, the pane widgets) plus the shell-spawn path:

- **`Session`** (`lib/session.dart`) — `title` becomes `activity`; a new
  `name` notifier is added; `_wire()` gains a `terminal.onIconChange`
  assignment alongside the existing `onTitleChange`. `dispose()` disposes
  both notifiers, mirroring today's single `title.dispose()`.

- **`PaneBar`** (`lib/pane_bar.dart`) — `_title()` reads both notifiers and
  combines them per decision 2. Two `ValueListenableBuilder`s (or one nested
  in the other) replace the single one there today.

- **`shellCommand()` / `Sessions.spawn()`** (`lib/shell_command.dart`,
  `lib/sessions.dart`) — gains the platform-specific init-script injection
  for the prompt hook. The exact mechanism (temp rc file, `--rcfile`,
  `ZDOTDIR` override for zsh, a `cmd.exe` `PROMPT` value using `$e]2;$p$e\`)
  is an implementation-plan concern, not a design one; the constraint that
  matters here is OSC 2 only, never OSC 0.

## Testing

| Unit | Tested by |
|---|---|
| `Session` wiring `onIconChange`/`onTitleChange` to `name`/`activity` independently | unit tests |
| `PaneBar` combine logic — name+activity, activity-only, empty-name | unit tests |
| Whether Claude Code actually separates OSC 1/OSC 2 | one-time manual verification, first implementation step |
| Shell prompt hook actually firing on prompt redraw, on both platforms | by eye, running the app — same category M1 already carves out for pty/terminal wiring |

## Definition of done

A pane running Claude Code shows its session name and current activity
together once both are known; renaming the session no longer erases the
activity text. Exiting Claude back to a shell prompt shows the shell's pwd
instead of a stale Claude title, on both bash/zsh (macOS) and `cmd.exe`
(Windows) — confirmed by hand on both platforms, as M0 and M1 were.

## Deferred — not in this change

- Shells other than bash/zsh (macOS) and `cmd.exe` (Windows) — fish,
  PowerShell, and anything else the user's `$SHELL` might name.
- Manual rename UI for either `name` or `activity`.
- Persisting `name`/`activity` across app restarts.
- Native OS window title bar changes.

## Watch out

- If the OSC 1/OSC 2 verification step finds Claude Code does *not* separate
  name from activity, do not invent a heuristic to fake the split — fall back
  to `activity`-only display, matching today's behavior, and note it plainly
  rather than silently shipping a `name` field that never populates.
- The shell hook must use OSC 2 specifically. Using OSC 0 for the pwd reset
  would also overwrite `name` (OSC 1) every time the shell redraws its
  prompt, silently breaking decision 1 the moment it's exercised.
- The init-script injection must not mutate the user's actual `.bashrc` /
  `.zshrc` on disk — it sources the user's real rc file and layers the hook
  on top, in a temp file or override directory, exactly as VS Code's shell
  integration does.
