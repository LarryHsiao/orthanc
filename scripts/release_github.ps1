<#
.SYNOPSIS
  Orthanc — publish built artifacts to a GitHub Release. Idempotent.

.DESCRIPTION
  Ported from Heimdall's scripts/release_github.ps1. Creates the release if
  missing, then uploads with --clobber. Skips silently when the build is
  not on a tag matching v*.

  Requires:
    - gh CLI on PATH
    - GH_TOKEN env var with repo scope
    - Built artifacts at build\installer\orthanc-setup-*.exe and
      build\publish\orthanc-*-windows.zip
    - FVM on PATH (to reach the pinned Dart SDK for auto_updater:sign_update)
    - bash on PATH and Vaultwarden reachable via
      ~/.claude/hooks/secret.sh, item "orthanc-winsparkle-dsa" (password
      field = base64 of dsa_priv.pem, the WinSparkle signing key)

  Argument:
    -Branch — TeamCity's %teamcity.build.branch% (e.g. refs/tags/v1.0.1)
#>
param([Parameter(Mandatory=$true)][string]$Branch)
$ErrorActionPreference = 'Stop'

if ($Branch -notmatch '^(refs/tags/)?v\d') {
  Write-Host "Not a tag build (branch=$Branch); skipping release"
  exit 0
}
$tag = $Branch -replace '^refs/tags/', ''

$installer = Get-ChildItem 'build\installer\orthanc-setup-*.exe' -ErrorAction Stop | Select-Object -First 1
$zip       = Get-ChildItem 'build\publish\orthanc-*-windows.zip' -ErrorAction Stop | Select-Object -First 1

Write-Host "==> Ensuring release exists for $tag"
# gh writes "already exists" to stderr on repeat runs; don't capture it with 2>&1 —
# under EAP='Stop' that wraps it into a terminating NativeCommandError.
& gh release create $tag --title $tag --generate-notes --repo LarryHsiao/orthanc | Out-Null

Write-Host "==> Uploading $($installer.Name) and $($zip.Name)"
& gh release upload $tag $installer.FullName $zip.FullName --clobber --repo LarryHsiao/orthanc
if ($LASTEXITCODE -ne 0) { throw "gh release upload exited $LASTEXITCODE" }

$version = $tag -replace '^v', ''
$versionLine = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $versionLine) { throw "could not read version from pubspec.yaml" }
$fullVersion = $versionLine.Matches.Groups[1].Value

Write-Host "==> Resolving WinSparkle signing key from Vaultwarden"
$dsaKeyB64 = & bash "$env:USERPROFILE\.claude\hooks\secret.sh" orthanc-winsparkle-dsa password
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($dsaKeyB64)) {
  throw "could not resolve WinSparkle signing key from Vaultwarden (item: orthanc-winsparkle-dsa)"
}
$dsaKeyPath = Join-Path (Get-Location) 'dsa_priv.pem'
[IO.File]::WriteAllBytes($dsaKeyPath, [Convert]::FromBase64String($dsaKeyB64))

Write-Host "==> Signing update for WinSparkle"
try {
  $signOutput = & fvm dart run auto_updater:sign_update $installer.FullName
  if ($LASTEXITCODE -ne 0) { throw "auto_updater:sign_update exited $LASTEXITCODE" }
  if ($signOutput -notmatch 'sparkle:dsaSignature="([^"]+)"' -or $signOutput -notmatch 'length="([0-9]+)"') {
    throw "could not parse sign_update output: $signOutput"
  }
} finally {
  Remove-Item -Force $dsaKeyPath -ErrorAction SilentlyContinue
}
$dsaSignature = ($signOutput | Select-String -Pattern 'sparkle:dsaSignature="([^"]+)"').Matches.Groups[1].Value
$length = ($signOutput | Select-String -Pattern 'length="([0-9]+)"').Matches.Groups[1].Value

Write-Host "==> Updating appcast.xml"
$pubDate = (Get-Date).ToUniversalTime().ToString("ddd, dd MMM yyyy HH:mm:ss +0000")

& git fetch origin master
if ($LASTEXITCODE -ne 0) { throw "git fetch origin master exited $LASTEXITCODE" }

# The macOS deploy pipeline updates the same file and can win the push race.
# update_appcast.py replaces only this OS's <item>, so on a lost race we
# reset to the winner's commit and regenerate on top of it rather than
# rebasing a stale edit into a conflict.
$maxAttempts = 5
$pushed = $false
for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
  & git reset --hard origin/master
  if ($LASTEXITCODE -ne 0) { throw "git reset to origin/master exited $LASTEXITCODE" }

  & python3 scripts/update_appcast.py `
    --appcast appcast.xml `
    --os windows `
    --version $version `
    --full-version $fullVersion `
    --pub-date $pubDate `
    --url "https://github.com/LarryHsiao/orthanc/releases/download/$tag/$($installer.Name)" `
    --length $length `
    --dsa-signature $dsaSignature
  if ($LASTEXITCODE -ne 0) { throw "update_appcast.py exited $LASTEXITCODE" }

  & xmllint --noout appcast.xml
  if ($LASTEXITCODE -ne 0) { throw "appcast.xml is not valid XML after update" }
  & git add appcast.xml
  & git commit -m "chore: publish $tag to the update feed"
  if ($LASTEXITCODE -ne 0) { throw "git commit exited $LASTEXITCODE" }

  & git push origin HEAD:master
  if ($LASTEXITCODE -eq 0) { $pushed = $true; break }

  Write-Host "==> push race on attempt $attempt/$maxAttempts - refetching origin/master and retrying"
  Start-Sleep -Seconds 5
  & git fetch origin master
  if ($LASTEXITCODE -ne 0) { throw "git fetch origin master exited $LASTEXITCODE" }
}
if (-not $pushed) { throw "git push to master failed after $maxAttempts attempts - appcast.xml needs manual reconciliation" }
Write-Host "==> appcast.xml published for $tag"
