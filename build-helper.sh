#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
BUILD_ROOT="$SCRIPT_DIR/.build"
CODEX_SOURCE="$BUILD_ROOT/codex"
CODEX_COMMIT="$(<"$SCRIPT_DIR/UPSTREAM_COMMIT")"
OUTPUT_ROOT="$SCRIPT_DIR/dist"
APP_ROOT="$OUTPUT_ROOT/Codex Dual Auth.app"

command -v cargo >/dev/null || { print -u2 "Rust is required: https://rustup.rs"; exit 1; }
command -v swiftc >/dev/null || { print -u2 "Install Xcode Command Line Tools first."; exit 1; }

mkdir -p "$BUILD_ROOT" "$OUTPUT_ROOT"
if [[ ! -d "$CODEX_SOURCE/.git" ]]; then
  git clone --filter=blob:none https://github.com/openai/codex.git "$CODEX_SOURCE"
fi

git -C "$CODEX_SOURCE" fetch --depth=1 origin "$CODEX_COMMIT"
git -C "$CODEX_SOURCE" checkout --detach --force "$CODEX_COMMIT"
git -C "$CODEX_SOURCE" apply "$SCRIPT_DIR/patches/codex-dual-auth.patch"

cd "$CODEX_SOURCE/codex-rs"
cargo build --release -p codex-cli --bin codex

rm -rf "$APP_ROOT"
mkdir -p "$APP_ROOT/Contents/MacOS" "$APP_ROOT/Contents/Resources"
swiftc \
  -parse-as-library \
  -O \
  -target arm64-apple-macosx14.0 \
  -framework SwiftUI \
  -framework AppKit \
  "$SCRIPT_DIR/Sources/CodexDualAuthLauncher.swift" \
  -o "$APP_ROOT/Contents/MacOS/CodexDualAuthLauncher"
cp "$SCRIPT_DIR/Info.plist" "$APP_ROOT/Contents/Info.plist"
cp "$CODEX_SOURCE/codex-rs/target/release/codex" "$APP_ROOT/Contents/Resources/codex-dual-auth"
chmod 755 "$APP_ROOT/Contents/MacOS/CodexDualAuthLauncher" "$APP_ROOT/Contents/Resources/codex-dual-auth"
strip -S -x "$APP_ROOT/Contents/Resources/codex-dual-auth"
codesign --force --deep --sign - "$APP_ROOT"
"$SCRIPT_DIR/scripts/verify-bundle.sh" "$APP_ROOT"

rm -f "$OUTPUT_ROOT/Codex-Dual-Auth-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_ROOT" "$OUTPUT_ROOT/Codex-Dual-Auth-macOS-arm64.zip"
shasum -a 256 "$OUTPUT_ROOT/Codex-Dual-Auth-macOS-arm64.zip"
