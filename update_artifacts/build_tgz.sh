#!/usr/bin/env bash
set -euo pipefail
# Build a clean qhtlfirewall.tgz from repo contents
# Output: update_artifacts/qhtlfirewall.tgz

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/update_artifacts"
PKG_NAME="qhtlfirewall"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Create staging folder layout: <TMP>/qhtlfirewall/
mkdir -p "$TMP_DIR/$PKG_NAME"

# Copy the package contents: everything under repo/qhtlfirewall into staging/qhtlfirewall
rsync -a --exclude '.git' --exclude 'update_artifacts' --exclude 'qhtlfirewall-main.tar.gz' \
  "$ROOT_DIR/qhtlfirewall/" "$TMP_DIR/$PKG_NAME/"

# Ensure version.txt and changelog.txt exist
if [[ -f "$ROOT_DIR/qhtlfirewall/version.txt" ]]; then
  cp "$ROOT_DIR/qhtlfirewall/version.txt" "$OUT_DIR/version.txt"
fi
if [[ -f "$ROOT_DIR/qhtlfirewall/changelog.txt" ]]; then
  cp "$ROOT_DIR/qhtlfirewall/changelog.txt" "$OUT_DIR/changelog.txt"
fi

# Create tarball at output path (qhtlfirewall.tgz containing folder qhtlfirewall/)
cd "$TMP_DIR"
TARBALL_PATH="$OUT_DIR/qhtlfirewall.tgz"
rm -f "$TARBALL_PATH"
tar -czf "$TARBALL_PATH" "$PKG_NAME"

echo "Built: $TARBALL_PATH"
