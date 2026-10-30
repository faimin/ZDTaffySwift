#!/usr/bin/env bash
# Builds the Rust bridge for every Apple target and syncs the artifacts into the SwiftPM package:
#   Artifacts/ZDTaffy.xcframework   (git-ignored)  static library slices
#   Sources/ZDTaffyFFI/             C module shim (header + modulemap)
#   Sources/ZDTaffy/Generated/      Swift bindings produced by BoltFFI
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Homebrew's rustup keeps its proxies here; ~/.cargo/bin may hold stale links.
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"

command -v cargo >/dev/null || { echo "error: cargo not found" >&2; exit 1; }
command -v boltffi >/dev/null || { echo "error: boltffi not found (cargo install boltffi_cli --version 0.32.1)" >&2; exit 1; }

PROFILE_FLAG="--release"
[[ "${1:-}" == "--debug" ]] && PROFILE_FLAG=""

cd "$ROOT/rust"
boltffi pack apple $PROFILE_FLAG

DIST="$ROOT/rust/dist/apple"
rm -rf "$ROOT/Artifacts/ZDTaffy.xcframework" "$ROOT/Sources/ZDTaffyFFI" "$ROOT/Sources/ZDTaffy/Generated"
mkdir -p "$ROOT/Artifacts" "$ROOT/Sources/ZDTaffy/Generated"
cp -R "$DIST/ZDTaffy.xcframework" "$ROOT/Artifacts/ZDTaffy.xcframework"
cp -R "$DIST/FFI" "$ROOT/Sources/ZDTaffyFFI"
cp "$DIST"/Sources/BoltFFI/*.swift "$ROOT/Sources/ZDTaffy/Generated/"

echo "Done. Run 'swift test' from $ROOT."
