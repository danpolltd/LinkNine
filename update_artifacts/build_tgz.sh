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

# Preflight: verify critical Perl modules compile before packaging (fail fast)
if command -v perl >/dev/null 2>&1; then
  if ! perl -c "$TMP_DIR/$PKG_NAME/QhtLink/DisplayUI.pm" >/dev/null 2>&1; then
    echo "ERROR: Perl syntax check failed for QhtLink/DisplayUI.pm. Aborting build." >&2
    perl -c "$TMP_DIR/$PKG_NAME/QhtLink/DisplayUI.pm" || true
    exit 1
  fi
fi

# Emit version for traceability
if [ -f "$TMP_DIR/$PKG_NAME/version.txt" ]; then
  echo "Packaging qhtlfirewall version: $(head -n1 "$TMP_DIR/$PKG_NAME/version.txt")"
fi

# Ensure version.txt and changelog.txt exist
if [[ -f "$ROOT_DIR/qhtlfirewall/version.txt" ]]; then
  cp "$ROOT_DIR/qhtlfirewall/version.txt" "$OUT_DIR/version.txt"
fi
if [[ -f "$ROOT_DIR/qhtlfirewall/changelog.txt" ]]; then
  cp "$ROOT_DIR/qhtlfirewall/changelog.txt" "$OUT_DIR/changelog.txt"
fi

# Determine version for versioned artifact
VERSION="unknown"
if [ -f "$TMP_DIR/$PKG_NAME/version.txt" ]; then
  VERSION=$(head -n1 "$TMP_DIR/$PKG_NAME/version.txt" | tr -d '\r')
fi

# Create tarballs at output path (unversioned and versioned)
cd "$TMP_DIR"
TARBALL_UNVERSIONED="$OUT_DIR/qhtlfirewall.tgz"
TARBALL_VERSIONED="$OUT_DIR/qhtlfirewall-${VERSION}.tgz"
rm -f "$TARBALL_UNVERSIONED" "$TARBALL_VERSIONED"
tar -czf "$TARBALL_UNVERSIONED" "$PKG_NAME"
cp -f "$TARBALL_UNVERSIONED" "$TARBALL_VERSIONED"

# Compute checksums for traceability
SHA256=$(sha256sum "$TARBALL_UNVERSIONED" | awk '{print $1}')
echo "sha256  $SHA256  qhtlfirewall.tgz (version $VERSION)" > "$OUT_DIR/qhtlfirewall.sha256"
echo "Built: $TARBALL_UNVERSIONED (checksum $SHA256)"
echo "Built: $TARBALL_VERSIONED"
