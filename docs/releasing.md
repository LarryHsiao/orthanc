# Releasing

Orthanc checks for updates on launch and downloads them automatically via
Sparkle (macOS) / WinSparkle (Windows); Sparkle shows its own one-time
"install now?" consent alert before applying. The existing build-and-publish
flow, documented in the README's "Building a release" section, is
unchanged; each publish script also signs its artifact for Sparkle/WinSparkle
and updates the `appcast.xml` feed automatically — nothing manual to do
after the build.

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

## 1. Build and publish

- **macOS**: `scripts/publish_macos.sh --publish` — builds, signs,
  notarizes, and uploads `build/publish/orthanc.dmg` to a GitHub Release
  tagged `v<VERSION>` (created if it doesn't exist yet). Once the upload
  succeeds, the same script signs the DMG for Sparkle
  (`dart run auto_updater:sign_update`), adds/replaces its `<item>` in
  `appcast.xml` via `scripts/update_appcast.py`, and commits and pushes
  the feed.
- **Windows**: `scripts/build_windows.ps1` produces
  `build\publish\orthanc-setup-<VERSION>.exe` (signed installer) and
  `build\publish\orthanc-<VERSION>-windows.zip`. `scripts/release_github.ps1`
  then uploads both to the same `v<VERSION>` GitHub Release, signs the
  installer for WinSparkle, and updates/pushes `appcast.xml` the same way.

Running either script without its publish step (`publish_macos.sh` with no
`--publish`) skips the appcast update too — nothing touches the feed until
the artifact is actually uploaded and its real download URL is known.

## How the appcast update works

Both scripts call the same `scripts/update_appcast.py`, which adds or
replaces one platform's `<item>` in `appcast.xml` — replaces, not
duplicates: re-running a publish for a platform overwrites that platform's
entry, leaving the other platform's entry untouched. `sparkle:os` is what
lets one shared feed serve both platforms — each client only installs the
item matching its own OS.

To debug a bad feed entry by hand, the script can be invoked directly:

```bash
python3 scripts/update_appcast.py \
  --appcast appcast.xml --os macos \
  --version <VERSION> --build <BUILD_NUMBER> \
  --pub-date "<RFC_2822_DATE>" \
  --url "https://github.com/LarryHsiao/orthanc/releases/download/v<VERSION>/orthanc.dmg" \
  --length <BYTES> --ed-signature "<FROM sign_update>"
```

(`--dsa-signature --full-version <VERSION>+<BUILD>` in place of
`--build`/`--ed-signature` for `--os windows` — `--full-version` must match
the built exe's `ProductVersion` string exactly, since that's what
WinSparkle compares against; a bare `<VERSION>` without the build suffix
makes it think every install is out of date.)
Always `xmllint --noout appcast.xml` after a manual edit before committing.
