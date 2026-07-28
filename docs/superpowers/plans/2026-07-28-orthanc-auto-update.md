# Orthanc Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Orthanc checks for a newer GitHub Release on launch, downloads and applies it silently via Sparkle (macOS) / WinSparkle (Windows), and shows a brief one-time note after the relaunch that actually picks up the new version.

**Architecture:** `auto_updater` (a Flutter wrapper around Sparkle/WinSparkle) owns the dangerous half of this feature — staged download, signature verification, and the atomic file-swap that installs the new build. Orthanc's own code only does two small things: kick off a silent check on launch (`AppRoot`), and detect + announce a version bump that already happened (`update_note.dart` + `UpdateNoteBanner`). Everything else is `auto_updater` configuration: an `appcast.xml` feed committed to the repo, and per-platform signing keys.

**Tech Stack:** Flutter desktop (macOS + Windows), `auto_updater` 1.0.0 (Sparkle/WinSparkle), `package_info_plus` 10.2.1, `shared_preferences` 2.5.5, `flutter_test`.

## Global Constraints

- Design spec: `docs/superpowers/specs/2026-07-28-orthanc-auto-update-design.md`. Every decision there is binding; this plan implements it and adds nothing.
- Distribution source is GitHub Releases, direct, on both platforms — no metis integration, no app store.
- Checks happen on launch only. No periodic/background timer, no manual "check for updates" UI.
- Updates download and apply silently — never a forced restart, never a dialog blocking input.
- The post-relaunch note is the only user-facing surface this plan builds; it must not block typing or steal focus from the terminal.
- Errors (network, missing feed) fail silent — no retry loop, no user-facing error state.
- Private signing keys (macOS EdDSA private half, Windows `dsa_priv.pem`) must never be committed. Public halves (the `SUPublicEDKey` string, `dsa_pub.pem`) are safe to commit.
- Deferred, do not build: manual update-check UI, skip-version/rollback UI, periodic checks, release-notes formatting beyond plain text, any metis integration.

## File Structure

| File | Responsibility |
|---|---|
| `lib/update_note.dart` | Pure logic: whether the running version differs from the last one seen (`checkForUpdateNote`), plus the read-compute-write orchestration over injected persistence functions (`updateNoteOnLaunch`). No Flutter import. |
| `lib/update_note_banner.dart` | The one-time banner widget: names the version, dismissible. |
| `lib/app_root.dart` | Wires `PackageInfo`, `SharedPreferences`, and `auto_updater` together on startup; owns banner-visibility state; forwards `Settings` into `WorkspaceView`. |
| `lib/main.dart` | Modified: `_OrthancAppState` hosts `AppRoot(settings: widget.settings)` instead of `WorkspaceView(settings: widget.settings)` directly. Its `Settings` loading, `PlatformMenuBar`, and everything else are untouched. |
| `pubspec.yaml` | Modified: adds `auto_updater`, `package_info_plus`, `shared_preferences`. |
| `appcast.xml` | Created: the Sparkle/WinSparkle feed, seeded empty (no `<item>`s) until the first release goes through the new signing step. |
| `macos/Runner/Info.plist` | Modified: adds `SUPublicEDKey`. |
| `macos/Runner/Release.entitlements`, `macos/Runner/DebugProfile.entitlements` | Modified: adds `com.apple.security.network.client`, required by Sparkle to reach the feed and download. |
| `windows/runner/Runner.rc` | Modified: embeds `dsa_pub.pem` as a `DSAPub` resource, required by WinSparkle to verify signatures. |
| `.gitignore` | Modified: excludes `dsa_priv.pem`. |
| `docs/releasing.md` | Created: the per-release signing + appcast-update step, layered onto the existing `scripts/publish_macos.sh` / `scripts/build_windows.ps1` + `scripts/release_github.ps1` flow. |
| `README.md` | Modified: one new paragraph in "Building a release" pointing at `docs/releasing.md`. |

---

## Task 1: Post-relaunch note — decision logic and persistence orchestration

**Files:**
- Create: `lib/update_note.dart`, `test/update_note_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class UpdateNoteState` with `final bool shouldShow` and `final String version`; `UpdateNoteState checkForUpdateNote({required String? lastSeenVersion, required String currentVersion})`; `Future<UpdateNoteState> updateNoteOnLaunch({required Future<String?> Function() readLastSeenVersion, required Future<void> Function(String version) writeLastSeenVersion, required String currentVersion})`. Task 2 and Task 3 both call these exact names.

- [ ] **Step 1: Write the failing test for `checkForUpdateNote`**

Create `test/update_note_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/update_note.dart';

void main() {
  group('checkForUpdateNote', () {
    test('shows no note on the very first launch (nothing seen yet)', () {
      const expected = false;

      final result = checkForUpdateNote(
        lastSeenVersion: null,
        currentVersion: '1.2.0',
      );

      expect(result.shouldShow, expected);
    });

    test('shows no note when the version is unchanged', () {
      const expected = false;

      final result = checkForUpdateNote(
        lastSeenVersion: '1.2.0',
        currentVersion: '1.2.0',
      );

      expect(result.shouldShow, expected);
    });

    test('shows a note naming the new version when it changed', () {
      const expectedShouldShow = true;
      const expectedVersion = '1.2.0';

      final result = checkForUpdateNote(
        lastSeenVersion: '1.1.0',
        currentVersion: '1.2.0',
      );

      expect(result.shouldShow, expectedShouldShow);
      expect(result.version, expectedVersion);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/update_note_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orthanc/update_note.dart'`.

- [ ] **Step 3: Implement `UpdateNoteState` and `checkForUpdateNote`**

Create `lib/update_note.dart`:

```dart
/// Whether a newer version landed since the user last saw this app running,
/// derived by comparing the running version against the last one recorded
/// in local prefs. `shouldShow` is false on the very first launch, when
/// there is nothing to compare against.
class UpdateNoteState {
  const UpdateNoteState({required this.shouldShow, required this.version});

  final bool shouldShow;
  final String version;
}

UpdateNoteState checkForUpdateNote({
  required String? lastSeenVersion,
  required String currentVersion,
}) {
  final shouldShow =
      lastSeenVersion != null && lastSeenVersion != currentVersion;
  return UpdateNoteState(shouldShow: shouldShow, version: currentVersion);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `fvm flutter test test/update_note_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Write the failing test for `updateNoteOnLaunch`**

Append to `test/update_note_test.dart`, inside `main()` after the `checkForUpdateNote` group:

```dart
  group('updateNoteOnLaunch', () {
    test('reads the last-seen version, computes the note, and persists the running version', () async {
      const expectedShouldShow = true;
      const expectedVersion = '1.2.0';
      String? written;

      final result = await updateNoteOnLaunch(
        readLastSeenVersion: () async => '1.1.0',
        writeLastSeenVersion: (version) async => written = version,
        currentVersion: '1.2.0',
      );

      expect(result.shouldShow, expectedShouldShow);
      expect(result.version, expectedVersion);
      expect(written, expectedVersion);
    });

    test('persists the running version even on the first launch, so the next launch has something to compare against', () async {
      const expectedWritten = '1.2.0';
      String? written;

      final result = await updateNoteOnLaunch(
        readLastSeenVersion: () async => null,
        writeLastSeenVersion: (version) async => written = version,
        currentVersion: '1.2.0',
      );

      expect(result.shouldShow, false);
      expect(written, expectedWritten);
    });
  });
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `fvm flutter test test/update_note_test.dart`
Expected: FAIL — `The function 'updateNoteOnLaunch' isn't defined`.

- [ ] **Step 7: Implement `updateNoteOnLaunch`**

Append to `lib/update_note.dart`:

```dart

/// Reads the last-seen version, computes [checkForUpdateNote] against it,
/// then unconditionally persists the running version — so a launch that
/// shows no note still leaves the next launch something to compare against.
Future<UpdateNoteState> updateNoteOnLaunch({
  required Future<String?> Function() readLastSeenVersion,
  required Future<void> Function(String version) writeLastSeenVersion,
  required String currentVersion,
}) async {
  final lastSeen = await readLastSeenVersion();
  final state = checkForUpdateNote(
    lastSeenVersion: lastSeen,
    currentVersion: currentVersion,
  );
  await writeLastSeenVersion(currentVersion);
  return state;
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `fvm flutter test test/update_note_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 9: Commit**

```bash
rtk git add lib/update_note.dart test/update_note_test.dart
rtk git commit -m "feat: add post-relaunch update-note decision logic"
```

---

## Task 2: Post-relaunch note banner widget

**Files:**
- Create: `lib/update_note_banner.dart`, `test/update_note_banner_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1 directly (takes a plain `version` string and callback — `AppRoot` in Task 3 is what connects it to `UpdateNoteState`).
- Produces: `class UpdateNoteBanner extends StatelessWidget` with constructor `UpdateNoteBanner({required String version, required VoidCallback onDismiss})`. Task 3 depends on this exact constructor.

- [ ] **Step 1: Write the failing test**

Create `test/update_note_banner_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthanc/update_note_banner.dart';

void main() {
  testWidgets('names the version that was updated to', (tester) async {
    const expected = 'Updated to v1.2.0';

    await tester.pumpWidget(
      MaterialApp(
        home: UpdateNoteBanner(version: '1.2.0', onDismiss: () {}),
      ),
    );

    expect(find.text(expected), findsOneWidget);
  });

  testWidgets('calls onDismiss when the close button is tapped', (tester) async {
    const expected = true;
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: UpdateNoteBanner(
          version: '1.2.0',
          onDismiss: () => dismissed = true,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(dismissed, expected);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `fvm flutter test test/update_note_banner_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orthanc/update_note_banner.dart'`.

- [ ] **Step 3: Implement the widget**

Create `lib/update_note_banner.dart`:

```dart
import 'package:flutter/material.dart';

/// A one-time, non-blocking note that Orthanc updated itself since the last
/// launch. Purely informational — it never intercepts keyboard input, so it
/// must not sit in the focus chain the terminal panes rely on.
class UpdateNoteBanner extends StatelessWidget {
  const UpdateNoteBanner({
    super.key,
    required this.version,
    required this.onDismiss,
  });

  final String version;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.blueGrey.shade800,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Updated to v$version',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 16),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `fvm flutter test test/update_note_banner_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
rtk git add lib/update_note_banner.dart test/update_note_banner_test.dart
rtk git commit -m "feat: add the post-relaunch update-note banner"
```

---

## Task 3: Wire the update engine and the note into app startup

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/app_root.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `checkForUpdateNote`/`updateNoteOnLaunch`/`UpdateNoteState` from `lib/update_note.dart` (Task 1); `UpdateNoteBanner` from `lib/update_note_banner.dart` (Task 2); `WorkspaceView` (existing, `lib/workspace_view.dart`, constructor `WorkspaceView({required ValueNotifier<Settings> settings})`); `Settings` (existing, `lib/settings.dart`).
- Produces: `class AppRoot extends StatefulWidget` with constructor `AppRoot({required ValueNotifier<Settings> settings})`, hosted by `main.dart`'s `_OrthancAppState` in place of its current direct `WorkspaceView(settings: widget.settings)`.

Note on drift: this plan was authored against an older snapshot of `main.dart` (a bare `StatelessWidget` hosting `WorkspaceView()` directly). The current `main.dart` has since grown a `Settings` system — `main()` is now `async`, loads `Settings` from disk, and `OrthancApp` is a `StatefulWidget` holding a `ValueNotifier<Settings>`, a `PlatformMenuBar`, and a `Scaffold` whose body is `SafeArea(child: WorkspaceView(settings: widget.settings))`. `AppRoot` now takes that same `settings` notifier and forwards it to `WorkspaceView` — it does not touch settings loading, the menu bar, or anything else `OrthancApp` already owns.

- [ ] **Step 1: Add the three dependencies**

Edit `pubspec.yaml`, in the `dependencies:` block, after `xterm: ^4.0.0`:

```yaml
  auto_updater: ^1.0.0
  package_info_plus: ^10.2.1
  shared_preferences: ^2.5.5
```

Run: `fvm flutter pub get`
Expected: resolves cleanly, `pubspec.lock` updated.

- [ ] **Step 2: Implement `AppRoot`**

Create `lib/app_root.dart`:

```dart
import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';
import 'update_note.dart';
import 'update_note_banner.dart';
import 'workspace_view.dart';

const _lastSeenVersionKey = 'last_seen_version';
const _appcastFeedUrl =
    'https://raw.githubusercontent.com/LarryHsiao/orthanc/master/appcast.xml';

/// Hosts the workspace, and around it: a silent launch-time update check
/// (Sparkle/WinSparkle, via [autoUpdater]) and a one-time note if the last
/// check already landed one. Both are best-effort — neither may ever block
/// the terminal from opening or stand between the user and their keyboard.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.settings});

  final ValueNotifier<Settings> settings;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  UpdateNoteState? _note;

  @override
  void initState() {
    super.initState();
    _showUpdateNoteIfAny();
    _checkForUpdate();
  }

  Future<void> _showUpdateNoteIfAny() async {
    final info = await PackageInfo.fromPlatform();
    final prefs = await SharedPreferences.getInstance();
    final state = await updateNoteOnLaunch(
      readLastSeenVersion: () async => prefs.getString(_lastSeenVersionKey),
      writeLastSeenVersion: (version) =>
          prefs.setString(_lastSeenVersionKey, version),
      currentVersion: info.version,
    );
    if (state.shouldShow && mounted) {
      setState(() => _note = state);
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      await autoUpdater.setFeedURL(_appcastFeedUrl);
      await autoUpdater.checkForUpdates(inBackground: true);
    } catch (_) {
      // Fail silent by design — see the design spec's Error handling
      // section. A missing feed or a network hiccup is not worth
      // surfacing at launch; the next launch tries again.
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    return Column(
      children: [
        if (note != null)
          UpdateNoteBanner(
            version: note.version,
            onDismiss: () => setState(() => _note = null),
          ),
        Expanded(child: WorkspaceView(settings: widget.settings)),
      ],
    );
  }
}
```

- [ ] **Step 3: Host `AppRoot` from `main.dart`**

`main.dart` currently ends with `_OrthancAppState`, whose `build()` returns a
`PlatformMenuBar` wrapping a `MaterialApp` whose `home` is
`Scaffold(body: SafeArea(child: WorkspaceView(settings: widget.settings)))`.
Two edits, both inside the existing file — nothing else in it changes.

Edit `lib/main.dart`'s import block:

```diff
 import 'dart:io';

 import 'package:flutter/material.dart';
 import 'package:flutter/services.dart';
 import 'package:path_provider/path_provider.dart';

+import 'app_root.dart';
 import 'settings.dart';
 import 'settings_dialog.dart';
 import 'settings_store.dart';
 import 'shell_command.dart';
-import 'workspace_view.dart';
```

Edit `_OrthancAppState.build()`'s `home:`:

```diff
       child: MaterialApp(
         navigatorKey: _navigatorKey,
         title: 'Orthanc',
         debugShowCheckedModeBanner: false,
-        home: Scaffold(
-          body: SafeArea(child: WorkspaceView(settings: widget.settings)),
-        ),
+        home: Scaffold(
+          body: SafeArea(child: AppRoot(settings: widget.settings)),
+        ),
       ),
```

- [ ] **Step 4: Verify the whole suite still analyzes and passes**

Run: `fvm flutter analyze`
Expected: no issues.

Run: `fvm flutter test`
Expected: all tests pass (the pre-existing suite plus Tasks 1–2's new tests). `auto_updater`'s native download/verify/swap path is not exercised here — like the pty layer, it can only be judged by hand, which Task 7 does.

- [ ] **Step 5: Commit**

```bash
rtk git add pubspec.yaml pubspec.lock lib/app_root.dart lib/main.dart
rtk git commit -m "feat: check for updates on launch and wire the update note"
```

---

## Task 4: macOS signing setup, entitlements, and the seed feed

**Files:**
- Modify: `macos/Runner/Info.plist`, `macos/Runner/Release.entitlements`, `macos/Runner/DebugProfile.entitlements`
- Create: `appcast.xml`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `appcast.xml` at the repo root, matching the URL `AppRoot` already points at; the macOS build now links Sparkle and can reach the network to check it.

- [ ] **Step 1: Generate the macOS EdDSA signing key**

Run: `dart run auto_updater:generate_keys`

This writes the private key into the local keychain (never touches the repo) and prints a `SUPublicEDKey` value, e.g.:

```
<key>SUPublicEDKey</key>
<string>bHaXClrRGMmKoKP/3HJnr/jn2ODTRPAM3VZhhkI9ZvY=</string>
```

- [ ] **Step 2: Add the public key to `Info.plist`**

Edit `macos/Runner/Info.plist`, inside the top-level `<dict>`, after the `NSPrincipalClass` entry:

```diff
 	<key>NSPrincipalClass</key>
 	<string>NSApplication</string>
+	<key>SUPublicEDKey</key>
+	<string>PASTE_THE_KEY_PRINTED_BY_STEP_1_HERE</string>
 </dict>
```

- [ ] **Step 3: Grant Sparkle network access**

Edit `macos/Runner/Release.entitlements`:

```diff
 <?xml version="1.0" encoding="UTF-8"?>
 <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
 <plist version="1.0">
 <dict>
+	<key>com.apple.security.network.client</key>
+	<true/>
 </dict>
 </plist>
```

Edit `macos/Runner/DebugProfile.entitlements`:

```diff
 	<key>com.apple.security.cs.allow-jit</key>
 	<true/>
 	<key>com.apple.security.network.server</key>
 	<true/>
+	<key>com.apple.security.network.client</key>
+	<true/>
```

- [ ] **Step 4: Create the seed feed**

Create `appcast.xml` at the repo root:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Orthanc</title>
        <description>Orthanc release feed</description>
        <language>en</language>
    </channel>
</rss>
```

No `<item>` yet — the first real entry is added by `docs/releasing.md`'s process (Task 6), the first time a signed release goes out. `checkForUpdates` against an empty channel simply finds nothing newer.

- [ ] **Step 5: Verify the feed is valid XML**

Run: `xmllint --noout appcast.xml`
Expected: no output, exit code 0.

- [ ] **Step 6: Verify the macOS build still launches**

Run: `fvm flutter run -d macos`
Expected: the app builds (CocoaPods pulls in Sparkle via the `auto_updater_macos` plugin automatically) and launches exactly as before — no visible change, since the seed feed carries no update. Quit the app once confirmed.

- [ ] **Step 7: Commit**

```bash
rtk git add macos/Runner/Info.plist macos/Runner/Release.entitlements macos/Runner/DebugProfile.entitlements appcast.xml
rtk git commit -m "feat(macos): wire Sparkle signing key, entitlements, and the seed feed"
```

---

## Task 5: Windows signing setup

**Files:**
- Modify: `windows/runner/Runner.rc`, `.gitignore`
- Create (locally, not committed): `dsa_priv.pem`
- Create (committed): `dsa_pub.pem`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `dsa_pub.pem` at the repo root, embedded into the Windows build as a resource; the Windows build can now verify signed updates.

This task can only be run on Windows — WinSparkle's key generation needs OpenSSL and the Windows resource compiler. Budget real time here the way Milestone 0/1 did for their Windows passes; don't treat it as a formality.

- [ ] **Step 1: Install OpenSSL**

Run (PowerShell, as admin): `choco install openssl`

- [ ] **Step 2: Generate the Windows DSA signing key**

Run: `dart run auto_updater:generate_keys`

This writes two files to the current directory: `dsa_priv.pem` (private — never commit) and `dsa_pub.pem` (public — safe to commit). Move both to the repo root if they land elsewhere.

- [ ] **Step 3: Keep the private key out of git**

Edit `.gitignore`, in the "Flutter/Dart/Pub related" section:

```diff
 /build/
 /coverage/
+
+# WinSparkle signing — never commit the private half
+dsa_priv.pem
```

- [ ] **Step 4: Embed the public key as a Windows resource**

Edit `windows/runner/Runner.rc`, appending at the end of the file:

```rc

/////////////////////////////////////////////////////////////////////////////
//
// WinSparkle
//
// Verify update signatures using this DSA public key:
DSAPub      DSAPEM      "../../dsa_pub.pem"
```

- [ ] **Step 5: Verify the Windows build still launches**

Run: `fvm flutter run -d windows`
Expected: the app builds and launches exactly as before — no visible change, since the seed feed (Task 4) carries no update. Quit once confirmed.

- [ ] **Step 6: Commit**

```bash
rtk git add windows/runner/Runner.rc .gitignore dsa_pub.pem
rtk git commit -m "feat(windows): wire WinSparkle signing key"
```

---

## Task 6: Document the release pipeline step

**Files:**
- Create: `docs/releasing.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: the exact commands verified in Tasks 4 and 5, and the real build scripts already in the repo (`scripts/publish_macos.sh`, `scripts/build_windows.ps1`, `scripts/release_github.ps1`).
- Produces: nothing consumed by other tasks — this is the human-facing process doc that Task 7 exercises for real.

Note on drift: this plan was authored against an older snapshot of the repo, before `scripts/publish_macos.sh`, `scripts/build_windows.ps1`, and `scripts/release_github.ps1` existed and before README grew its own "Building a release" section. The steps below name those real scripts and their real artifact filenames instead of the placeholder flow originally assumed.

- [ ] **Step 1: Write the release doc**

Create `docs/releasing.md`:

```markdown
# Releasing

Orthanc checks for updates on launch and applies them silently via
Sparkle (macOS) / WinSparkle (Windows). The existing build-and-publish
flow, documented in the README's "Building a release" section, is
unchanged; this adds one step at the end so the `auto_updater` feed
(`appcast.xml`) picks up the new build.

## 1. Build and publish the platform artifacts (existing flow)

- **macOS**: `scripts/publish_macos.sh --publish` — builds, signs,
  notarizes, and uploads `build/publish/orthanc.dmg` to a GitHub Release
  tagged `v<VERSION>` (created if it doesn't exist yet).
- **Windows**: `scripts/build_windows.ps1` produces
  `build\publish\orthanc-setup-<VERSION>.exe` (signed installer) and
  `build\publish\orthanc-<VERSION>-windows.zip`; `scripts/release_github.ps1`
  then uploads both to the same `v<VERSION>` GitHub Release.

Both artifacts stay on disk after their script runs — step 2 signs them
in place, order doesn't matter relative to the upload.

## 2. Sign each artifact for Sparkle/WinSparkle

macOS:

```bash
dart run auto_updater:sign_update build/publish/orthanc.dmg
```

Windows (run on a Windows machine, against the installer — that's the
artifact WinSparkle actually runs to apply the update):

```bash
dart run auto_updater:sign_update build\publish\orthanc-setup-<VERSION>.exe
```

Each command prints a signature attribute — `sparkle:edSignature="..."
length="..."` on macOS, `sparkle:dsaSignature="..." length="..."` on
Windows. Keep both outputs for step 3.

## 3. Add an `<item>` to `appcast.xml`

Append one `<item>` per platform inside `<channel>`, using the signatures
from step 2 and the real GitHub Release download URLs (both scripts
publish to `https://github.com/LarryHsiao/orthanc/releases/download/v<VERSION>/...`):

```xml
        <item>
            <title>Version <VERSION></title>
            <sparkle:version><BUILD_NUMBER></sparkle:version>
            <sparkle:shortVersionString><VERSION></sparkle:shortVersionString>
            <pubDate><RFC_2822_DATE></pubDate>
            <enclosure url="https://github.com/LarryHsiao/orthanc/releases/download/v<VERSION>/orthanc.dmg"
                       sparkle:edSignature="<FROM_STEP_2>"
                       sparkle:os="macos"
                       length="<FROM_STEP_2>"
                       type="application/octet-stream" />
        </item>
        <item>
            <title>Version <VERSION></title>
            <pubDate><RFC_2822_DATE></pubDate>
            <enclosure url="https://github.com/LarryHsiao/orthanc/releases/download/v<VERSION>/orthanc-setup-<VERSION>.exe"
                       sparkle:dsaSignature="<FROM_STEP_2>"
                       sparkle:version="<VERSION>"
                       sparkle:os="windows"
                       length="<FROM_STEP_2>"
                       type="application/octet-stream" />
        </item>
```

`sparkle:os` is what lets one shared feed serve both platforms — each
client only installs the item matching its own OS.

## 4. Commit and push the feed

```bash
xmllint --noout appcast.xml   # validate before committing
rtk git add appcast.xml
rtk git commit -m "chore: publish v<VERSION> to the update feed"
rtk git push
```

Step 1 already created and uploaded the GitHub Release itself — this is
the only remaining step once step 3's signatures are in place.
```

- [ ] **Step 2: Link it from the README**

Edit `README.md`'s "Building a release" section — add one paragraph right
after its introductory two paragraphs (before the "**Windows**" bullet):

```diff
 Each script fails on the first missing tool rather than part-way through, so
 check its prerequisites before the first run.

+Orthanc also checks for updates on launch and applies them silently via
+Sparkle/WinSparkle — see [`docs/releasing.md`](docs/releasing.md) for the
+one extra step this adds to the flow below: signing each artifact and
+publishing it to the `appcast.xml` feed.
+
 - **Windows** — `scripts/build_windows.ps1` builds a signed installer (via
```

- [ ] **Step 3: Commit**

```bash
rtk git add docs/releasing.md README.md
rtk git commit -m "docs: write the auto-update release process"
```

---

## Task 7: Cross-platform manual walk

**Files:** none in advance — any fix lands in whichever file the fault is actually in, decided once observed.

**Interfaces:**
- Consumes: the whole feature.
- Produces: this plan's definition of done.

This mirrors Milestone 0/1's own closing task: the native download/verify/
install path cannot be exercised by `flutter test`, so it is judged by
actually cutting a release and watching an old build pick it up.

- [ ] **Step 1: Cut a real, signed test release**

Bump `pubspec.yaml`'s `version:` by one patch (e.g. `1.1.2+6` →
`1.1.3+7`), then follow `docs/releasing.md` end to end for both platforms:
build/publish (creates the GitHub Release), sign, add feed items, commit
and push `appcast.xml`.

- [ ] **Step 2: Walk the macOS path**

- Install the *previous* version's build (the one still on disk before
  this task's bump) and launch it.
- Confirm no dialog or prompt appears; the terminal opens immediately.
- Wait for the background download to finish (check Console.app or the
  app's own logs if `auto_updater` emits any).
- Quit the app normally, then relaunch it.
- **Confirm**: the app is now running the new version (check the About
  panel or `defaults read` the bundle's `CFBundleShortVersionString`), and
  the update-note banner appears once, naming the new version, without
  stealing keyboard focus from the terminal.
- Relaunch once more.
- **Confirm**: the banner does not reappear.

- [ ] **Step 3: Walk the Windows path**

Same sequence as Step 2, on Windows, with the previous build's `.exe`.

- [ ] **Step 4: Fix what the walk found**

Fix in whichever file the fault is actually in. Repeat Steps 2–3 until both
platforms pass clean.

- [ ] **Step 5: Update the records and commit**

Mark this plan's tasks complete and commit:

```bash
rtk git add -A
rtk git commit -m "Confirm auto-update on macOS and Windows"
```

---

## Self-Review

**Spec coverage.** Goal (silent check-on-launch, silent apply, post-relaunch note) → Task 3's `AppRoot`. Scope (GitHub Releases direct, no metis) → Global Constraints, and no metis code appears anywhere in this plan. Stack (`auto_updater`) → Task 3's dependency + Tasks 4–5's platform setup. Feed (in-repo `appcast.xml`, raw GitHub URL) → Task 4 Step 4, referenced by `AppRoot`'s `_appcastFeedUrl`. Signing keys → Tasks 4–5. Release pipeline change → Task 6. Runtime behavior (check/apply/note) → Tasks 1–3. Error handling (fail silent) → Task 3's `try`/`catch` in `_checkForUpdate`. Testing (pure logic unit-tested, native path manually walked) → Tasks 1–2's unit/widget tests and Task 7. Definition of done → Task 7.

**Placeholder scan.** No TBD/TODO in any step. `docs/releasing.md`'s `<VERSION>`/`<FROM_STEP_2>` tokens are template placeholders *within a document a human fills in per release* — not a gap in this plan's own instructions, which give every surrounding command verbatim.

**Type consistency.** `UpdateNoteState`, `checkForUpdateNote`, `updateNoteOnLaunch` (Task 1) match their use in Task 3 exactly. `UpdateNoteBanner(version:, onDismiss:)` (Task 2) matches its construction in Task 3 exactly. `AppRoot(settings:)` matches its construction in Task 3's `main.dart` edit exactly.

**Drift reconciliation (added before execution).** This plan was originally written against master at `af18799`; the implementation worktree branched from `origin/master` at `937a114`, 34 commits ahead (a Settings system, OSC 8 hyperlinks, real release scripts, a rewritten README). Reconciled before any task was dispatched: Task 3's `AppRoot`/`main.dart` now thread the existing `ValueNotifier<Settings>` through instead of assuming a bare `WorkspaceView()`; Task 6's release doc and README edit now name the real `scripts/publish_macos.sh` / `scripts/build_windows.ps1` / `scripts/release_github.ps1` and their real artifact filenames instead of a placeholder flow; Task 7's version-bump example uses the current `1.1.2+6`. Tasks 1, 2, 4, and 5 were checked against the current tree and needed no changes — Info.plist and both entitlements files, in particular, are byte-identical to what those tasks already assumed.
