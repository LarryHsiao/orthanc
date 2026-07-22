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
& gh release create $tag --title $tag --generate-notes --repo LarryHsiao/orthanc 2>&1 | Out-Null

Write-Host "==> Uploading $($installer.Name) and $($zip.Name)"
& gh release upload $tag $installer.FullName $zip.FullName --clobber --repo LarryHsiao/orthanc
if ($LASTEXITCODE -ne 0) { throw "gh release upload exited $LASTEXITCODE" }
