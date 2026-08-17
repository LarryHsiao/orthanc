# Changelog

All notable changes to Orthanc are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

Releases before 1.1.18 are not recorded here; their notes are generated from
commit messages on each [GitHub Release](https://github.com/LarryHsiao/orthanc/releases).

## [1.1.18] - 2026-08-17

### Fixed

- A column holding a collapsed pane no longer leaves an empty strip along its
  bottom edge. The collapsed layout draws no dividers, yet was still reserving
  their space — four logical pixels per divider, so the gap grew with every
  split in that column.
- A column can no longer be reduced to nothing but pane bars over dead space.
  The last expanded pane in a column refuses to collapse, and closing a pane
  releases the collapse of any column it would have emptied.

[1.1.18]: https://github.com/LarryHsiao/orthanc/releases/tag/v1.1.18
