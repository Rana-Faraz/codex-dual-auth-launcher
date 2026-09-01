#!/bin/zsh
set -euo pipefail

APP_ROOT="${1:?usage: verify-bundle.sh /path/to/Codex Dual Auth.app}"
EXECUTABLE="$APP_ROOT/Contents/MacOS/CodexDualAuthLauncher"
EXPECTED_TARGET="14.0"

plutil -lint "$APP_ROOT/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP_ROOT"

ACTUAL_TARGET="$({ vtool -show-build "$EXECUTABLE" | awk '$1 == "minos" { print $2; exit }'; })"
if [[ "$ACTUAL_TARGET" != "$EXPECTED_TARGET" ]]; then
  print -u2 "Unexpected launcher deployment target: $ACTUAL_TARGET (expected $EXPECTED_TARGET)"
  exit 1
fi

if [[ "$(file "$EXECUTABLE")" != *"arm64"* ]]; then
  print -u2 "The launcher does not contain an arm64 executable."
  exit 1
fi

print "Verified arm64 launcher with macOS $EXPECTED_TARGET deployment target."
