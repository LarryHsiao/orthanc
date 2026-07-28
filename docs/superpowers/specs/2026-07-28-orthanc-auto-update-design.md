# Orthanc — Auto-Update Design

## Goal

Orthanc checks for a newer release on launch and, when one exists, downloads
and applies it silently — no prompt, no forced restart — so that the next
time the user naturally quits and reopens the app, they're already on the
new version. A brief note names the version change after that relaunch, so
the update is never invisible, only unintrusive.

## Scope

Independent of Milestone 1; does not touch pane/layout code. Distribution is
GitHub Releases, direct, on both macOS and Windows — no app store on either
platform, so no store-provided auto-update to lean on instead.

## Stack

- `auto_updater` — wraps native Sparkle (macOS) and WinSparkle (Windows)
  behind one Flutter API. Handles the two genuinely dangerous parts of a
  desktop self-updater: staged download + signature verification, and an
  atomic swap of the running app's files (`.app` bundle on macOS, `.exe` on
  Windows) that keeps the code signature intact and works around Windows
  refusing to overwrite a running executable. Published by verified
  publisher `leanflutter`, last released ~21 months ago — same vintage as
  `flutter_pty`/`xterm`, which this project already accepted; the API
  surface this design relies on (`setFeedURL`, `checkForUpdates`) is narrow
  and stable enough that the staleness isn't a blocker here.

## Feed

`appcast.xml`, committed to the orthanc repo root, served via its raw GitHub
URL. No separate hosting — GitHub already serves the file, the same way it
serves the release assets the feed points at.

## Signing keys

Generated once via `dart run auto_updater:generate_keys`:

- **macOS**: EdDSA keypair. Private key stays in the signer's keychain,
  never committed.
- **Windows**: DSA keypair. Private `.pem` kept out of the repo — this
  project has no CI (`/publish-macos` builds and signs locally), so it lives
  only on the machine that runs the release build, the same way macOS
  notarization credentials already do; public `.pem` bundled into the
  Windows build.

## Release pipeline change

One new step after the existing "build and upload platform binaries to a
GitHub Release": sign each artifact with `dart run auto_updater:sign_update`
and regenerate/commit `appcast.xml`. Nothing upstream of that step changes.

## Runtime behavior

- **Check**: on launch only, fire-and-forget. `main()` calls
  `autoUpdater.setFeedURL(...)` then `autoUpdater.checkForUpdates()`
  non-blocking — the terminal opens immediately regardless of outcome.
- **Apply**: mostly silent, with one unavoidable exception found by the
  Task 7 manual walk. `auto_updater_macos` hardcodes Sparkle's
  `SPUStandardUserDriver` — there is no code path in the plugin for a fully
  silent driver. `checkForUpdates(inBackground: true)` suppresses only the
  "checking…" indicator; once a valid update is found, Sparkle's standard
  one-time "an update is available, install?" alert still shows. Accepted
  as-is rather than forking `auto_updater_macos` for a custom silent
  `SPUUserDriver` or dropping Sparkle for a hand-rolled updater — this is
  how virtually every Sparkle-based Mac app behaves, and it's a single
  consent gate, not a recurring interruption. If the user accepts, Sparkle
  downloads, verifies, and installs — either immediately (if the user
  clicks through right away) or on the next natural quit-and-relaunch — but
  never a forced restart Orthanc itself initiates, so a live Claude Code
  session in a pane is never killed out from under the user without their
  own action.
- **Post-relaunch note**: on every launch, compare the running version
  against a "last-seen version" value in local prefs. If they differ, show a
  small one-time banner naming the new version (and release notes, if
  `auto_updater` surfaces the appcast's description field), then update the
  stored value. This is the only custom logic Orthanc owns — everything else
  is native Sparkle/WinSparkle behavior.

## Error handling

Network failure or an unreachable feed: the check silently no-ops. Nothing
surfaces to the user, no retry loop. The next natural launch tries again.
No other error state is designed — "fail silent, try again next time" is
the whole policy.

## Testing

The version-mismatch/banner logic (stored version vs. running version) is a
pure function and gets a unit test. The download/verify/self-replace path is
native Sparkle/WinSparkle code outside Flutter's reach — like the pty layer
in Milestone 0, it can only be judged by a manual walk on both platforms
(bump the appcast, relaunch, confirm the update lands and the banner shows),
not by `flutter test`.

## Definition of done

A running Orthanc build detects a newer GitHub Release on launch, downloads
and applies it silently, and shows the post-relaunch note — confirmed by
hand on both macOS and Windows, the same way Milestone 0's pty layer was.

## Deferred

- Any UI to manually trigger a check, skip a version, or roll back —
  Orthanc builds none of this itself. Sparkle's own standard alert (see
  Runtime behavior's Apply note) happens to offer "Skip This Version" and
  "Remind Me Later" regardless, as part of the UI this design accepted
  rather than suppressed; that's Sparkle's behavior, not a feature Orthanc
  implemented.
- Periodic/background checks while the app stays open — launch-time only.
- Release notes formatting beyond whatever plain text the appcast carries.
- Any integration with metis's update-serving backend — considered and
  rejected: that system is built for licensed/private apps (per-device auth
  keys, private release bucket) and Orthanc's builds are already public on
  GitHub, so it would add machinery without buying anything Orthanc needs.

## Watch out

- Don't let the post-relaunch note block input or steal focus from the
  terminal — it's informational, not a dialog the user must dismiss before
  typing.
- The private signing keys must never land in the repo — Windows' DSA
  private key in particular needs to live outside the working tree
  entirely (there's no CI to hold it as a secret), not a local file that
  could get committed by accident.
- Sparkle/WinSparkle's actual download-and-swap behavior cannot be
  meaningfully unit tested; don't let that gap get papered over with a
  mocked-out "integration test" that doesn't exercise the real engine.

## What the macOS walk found (2026-07-28)

The original "Apply: silent" line assumed `checkForUpdates(inBackground:
true)` produced a fully invisible check-and-install. It doesn't:
`auto_updater_macos`'s `AutoUpdater.swift` always constructs Sparkle with
`SPUStandardUserDriver`, and `inBackground` (per
`AutoUpdaterMacosPlugin.swift`) only routes to `checkForUpdatesInBackground()`,
which suppresses Sparkle's "checking…" indicator but not its "an update is
available, install?" alert once a valid item is found. Confirmed by cutting
a real signed `v1.1.3` release and watching a running `v1.1.2` build's
launch-time check surface that alert. No amount of unit or widget testing
would have caught this — only running the real engine did, which is exactly
why this task exists. Resolved by accepting Sparkle's one-time consent
alert rather than forking the plugin or dropping Sparkle; see Runtime
behavior's Apply note, above, for the corrected description.
