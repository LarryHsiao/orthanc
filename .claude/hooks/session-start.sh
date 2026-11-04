#!/bin/bash
# Installs the Flutter SDK and this package's dependencies so `flutter test`
# and `flutter analyze` work in Claude Code cloud sessions.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}"

FLUTTER_HOME="${FLUTTER_HOME:-$HOME/flutter}"
# The version README.md says the app is built and tested against. A newer
# SDK re-resolves pubspec.lock and rewrites analysis_options.yaml on first
# use, so keep this in step with that line rather than tracking `stable`.
FLUTTER_VERSION=3.38.7

# Global tool: the Flutter SDK, outside the repository, at the pinned version.
if [ "$(cat "$FLUTTER_HOME/version" 2>/dev/null)" != "$FLUTTER_VERSION" ] &&
   ! grep -qs "\"frameworkVersion\": \"$FLUTTER_VERSION\"" "$FLUTTER_HOME/bin/cache/flutter.version.json"; then
  rm -rf "$FLUTTER_HOME"
  git clone --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi
export PATH="$FLUTTER_HOME/bin:$PATH"
export FLUTTER_SUPPRESS_ANALYTICS=true
flutter config --no-analytics >/dev/null 2>&1 || true
# First run downloads the Dart SDK and engine artifacts; later runs are no-ops.
flutter --version >/dev/null

# Package dependencies: rerun only when what decides them has changed.
hashes=.dart_tool/.session-start.sha256
if ! sha256sum --check --status "$hashes" 2>/dev/null; then
  rm -f "$hashes"
  flutter pub get
  sha256sum .claude/hooks/session-start.sh pubspec.yaml pubspec.lock > "$hashes" || rm -f "$hashes"
fi

# Every session needs flutter on PATH.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$FLUTTER_HOME/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
  echo "export FLUTTER_SUPPRESS_ANALYTICS=true" >> "$CLAUDE_ENV_FILE"
fi
