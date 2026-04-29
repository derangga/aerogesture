#!/usr/bin/env bash
set -e

MAIN_SWIFT="Sources/aerogesture/main.swift"
FLAKE_NIX="flake.nix"

# Prompt
read -rp "What version do you want to release? (e.g. 1.0.0): " VERSION

if [[ -z "$VERSION" ]]; then
  echo "Error: version cannot be empty."
  exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be in semver format (e.g. 1.0.0)."
  exit 1
fi

TAG="v$VERSION"

# Update main.swift
sed -i '' "s/^let version = \".*\"/let version = \"$VERSION\"/" "$MAIN_SWIFT"

# Update flake.nix
sed -i '' "s/version = \"[0-9]*\.[0-9]*\.[0-9]*\";/version = \"$VERSION\";/" "$FLAKE_NIX"

# Commit
git add "$MAIN_SWIFT" "$FLAKE_NIX"
git commit -m "chore: bump version to $VERSION"

# Tag
git tag "$TAG"

echo ""
echo "version $VERSION already created, please double check before publish"
echo "  commit: $(git rev-parse --short HEAD)"
echo "  tag:    $TAG"
echo ""
echo "When ready, run:"
echo "  git push && git push origin $TAG"
