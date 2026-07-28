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
- **Apply**: silent. If a newer version is found, Sparkle/WinSparkle
  downloads and verifies it in the background and marks it ready. Nothing is
  shown to the user at this point. The update installs as a side effect of
  the next natural quit-and-relaunch — never a forced restart, so it can't
  interrupt a live Claude Code session running in a pane.
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

- Any UI to manually trigger a check, skip a version, or roll back.
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
