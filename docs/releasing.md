# Releasing

Orthanc checks for updates on launch and downloads them automatically via
Sparkle (macOS) / WinSparkle (Windows); Sparkle shows its own one-time
"install now?" consent alert before applying. The existing build-and-publish
flow, documented in the README's "Building a release" section, is
unchanged; this adds one step at the end so the `auto_updater` feed
(`appcast.xml`) picks up the new build.

## 0. One-time setup: signing keys

Both platforms need a signing keypair before the first release goes out,
generated via `dart run auto_updater:generate_keys` — run once per platform,
not once per release:

- **macOS**: writes an EdDSA keypair to the signer's local keychain; the
  public half is already committed in `macos/Runner/Info.plist` (done as
  part of Task 4 — nothing further to generate here).
- **Windows**: writes `dsa_priv.pem` / `dsa_pub.pem` to the working
  directory. The private half must never be committed — it's excluded via
  `.gitignore` — and instead lives only on the machine that runs the
  release build.

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
