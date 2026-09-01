#!/bin/zsh
set -euo pipefail

REPOSITORY="${CODEX_DUAL_AUTH_REPO:-Rana-Faraz/codex-dual-auth-launcher}"
VERSION="${CODEX_DUAL_AUTH_VERSION:-v0.1.3}"
ASSET="Codex-Dual-Auth-macOS-arm64.zip"
EXPECTED_SHA256="5d6def17c654fd813da1c293f840416b7ee73b5692cc8249d4a94d511b6d932f"
INSTALL_DIR="${CODEX_DUAL_AUTH_INSTALL_DIR:-$HOME/Applications}"
DESTINATION="$INSTALL_DIR/Codex Dual Auth.app"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  print -u2 "Codex Dual Auth $VERSION supports Apple-silicon macOS only."
  exit 1
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/codex-dual-auth.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
ARCHIVE="$TEMP_ROOT/$ASSET"
DOWNLOAD_URL="https://github.com/$REPOSITORY/releases/download/$VERSION/$ASSET"

print "Downloading $REPOSITORY $VERSION…"
curl --fail --location --proto '=https' --tlsv1.2 "$DOWNLOAD_URL" --output "$ARCHIVE"

ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  print -u2 "Checksum verification failed."
  print -u2 "Expected: $EXPECTED_SHA256"
  print -u2 "Actual:   $ACTUAL_SHA256"
  exit 1
fi

ditto -x -k "$ARCHIVE" "$TEMP_ROOT/unpacked"
SOURCE_APP="$TEMP_ROOT/unpacked/Codex Dual Auth.app"
if [[ ! -d "$SOURCE_APP" ]]; then
  print -u2 "The release archive did not contain Codex Dual Auth.app."
  exit 1
fi

mkdir -p "$INSTALL_DIR"
BACKUP_APP="$TEMP_ROOT/previous.app"
if [[ -e "$DESTINATION" ]]; then
  mv "$DESTINATION" "$BACKUP_APP"
fi

restore_previous() {
  rm -rf "$DESTINATION"
  if [[ -e "$BACKUP_APP" ]]; then
    mv "$BACKUP_APP" "$DESTINATION"
  fi
}

if ! ditto "$SOURCE_APP" "$DESTINATION"; then
  restore_previous
  print -u2 "Installation failed; the previous copy was restored."
  exit 1
fi

if ! codesign --verify --deep --strict "$DESTINATION"; then
  restore_previous
  print -u2 "Code-signature verification failed; the previous copy was restored."
  exit 1
fi

print "Installed: $DESTINATION"
if [[ "${CODEX_DUAL_AUTH_NO_OPEN:-0}" != "1" ]]; then
  open "$DESTINATION"
fi
