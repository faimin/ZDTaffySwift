#!/usr/bin/env bash
# Builds the XCFramework and prepares a release whose Package.swift points at the zip attached to the GitHub release.
#
#   scripts/release.sh 0.2.0              dry run: build, zip, checksum, and write build/release/Package.swift
#   scripts/release.sh 0.2.0 --publish    also commit the release manifest, tag v0.2.0, push the tag and create the
#                                         GitHub release with the zip attached (needs `gh`, logged in)
#
# `main` keeps a manifest that points at the locally built Artifacts/ZDTaffy.xcframework. The release commit
# differs from it only in the binaryTarget, is tagged, and is deliberately NOT merged back into `main`.
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version> [--publish]}"
PUBLISH="${2:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPO_URL="$(git config --get remote.origin.url | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
TAG="v$VERSION"
OUT="$ROOT/build/release"
ZIP="$OUT/ZDTaffy.xcframework.zip"
ASSET_URL="https://github.com/$REPO_URL/releases/download/$TAG/ZDTaffy.xcframework.zip"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]] || { echo "error: '$VERSION' is not a semantic version" >&2; exit 1; }
if [[ "$PUBLISH" == "--publish" ]]; then
  [[ -z "$(git status --porcelain)" ]] || { echo "error: the working tree must be clean to publish" >&2; exit 1; }
  git rev-parse "$TAG" >/dev/null 2>&1 && { echo "error: tag $TAG already exists" >&2; exit 1; }
  command -v gh >/dev/null || { echo "error: gh is required to publish" >&2; exit 1; }
fi

echo "==> Building the XCFramework"
"$ROOT/scripts/build-xcframework.sh"

echo "==> Zipping"
rm -rf "$OUT" && mkdir -p "$OUT"
# SwiftPM expects the .xcframework directory at the root of the archive.
ditto -c -k --sequesterRsrc --keepParent "$ROOT/Artifacts/ZDTaffy.xcframework" "$ZIP"
CHECKSUM="$(swift package compute-checksum "$ZIP")"
echo "    $(du -h "$ZIP" | cut -f1)  checksum $CHECKSUM"

echo "==> Writing the release manifest"
python3 -I - "$ROOT/Package.swift" "$OUT/Package.swift" "$ASSET_URL" "$CHECKSUM" <<'PY'
import re, sys
source, target, url, checksum = sys.argv[1:5]
text = open(source).read()
pattern = r'\.binaryTarget\(name: "ZDTaffyFFIBinary", path: "[^"]*"\)'
assert re.search(pattern, text), "binaryTarget line not found in Package.swift"
text = re.sub(pattern, f'.binaryTarget(name: "ZDTaffyFFIBinary", url: "{url}", checksum: "{checksum}")', text)
text = text.replace("// Produced by scripts/build-xcframework.sh.", "// The XCFramework attached to this release.")
open(target, "w").write(text)
PY
# The manifest must still parse (this does not touch the network).
mkdir -p "$OUT/check" && cp "$OUT/Package.swift" "$OUT/check/Package.swift"
( cd "$OUT/check" && swift package dump-package >/dev/null ) || { echo "error: the release manifest does not parse" >&2; exit 1; }
rm -rf "$OUT/check"
echo "    $OUT/Package.swift  ->  $ASSET_URL"

if [[ "$PUBLISH" != "--publish" ]]; then
  echo
  echo "Dry run. To publish: scripts/release.sh $VERSION --publish"
  exit 0
fi

echo "==> Publishing $TAG"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git checkout --detach
cp "$OUT/Package.swift" Package.swift
git add Package.swift
git commit -m "release: $TAG" -m "Points the binary target at the release asset. Not part of $BRANCH."
git tag "$TAG"
git push origin "$TAG"
git checkout "$BRANCH"
gh release create "$TAG" "$ZIP" --title "$TAG" --generate-notes --verify-tag
echo "Released $TAG"
