#!/usr/bin/env bash
set -euo pipefail

# Parity diff: Upstream ConfigServer/*.pm vs local QhtLink/*.pm
# Normalizes common rebrand tokens before diffing to highlight logic drifts.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UP_DIR="$ROOT_DIR/_upstream_scripts/scripts/csf/ConfigServer"
LOC_DIR="$ROOT_DIR/qhtlfirewall/QhtLink"

if [[ ! -d "$UP_DIR" ]]; then
  echo "Upstream directory not found: $UP_DIR" >&2
  exit 1
fi

if [[ ! -d "$LOC_DIR" ]]; then
  echo "Local directory not found: $LOC_DIR" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Comparing upstream -> local (normalized for rebrand):"
echo "  Upstream: $UP_DIR"
echo "  Local   : $LOC_DIR"

DIFFS=0
MISSING=0

for up in "$UP_DIR"/*.pm; do
  bn="$(basename "$up")"
  norm="$TMP_DIR/$bn"
  # Normalize common rename tokens (best-effort; diff is advisory)
  sed -e 's/\bConfigServer\b/QhtLink/g' \
      -e 's/\bcsf\b/qhtlfirewall/g' \
      -e 's/\blfd\b/qhtlwaterfall/g' \
      -e 's/CSF/QHTLFIREWALL/g' \
      "$up" > "$norm"

  loc="$LOC_DIR/$bn"
  if [[ ! -f "$loc" ]]; then
    echo "-- Missing local file: $bn" >&2
    ((MISSING++))
    continue
  fi

  if ! diff -u "$norm" "$loc" > "$TMP_DIR/$bn.diff"; then
    echo "== Diff: $bn =="
    cat "$TMP_DIR/$bn.diff"
    echo
    ((DIFFS++))
  fi
done

echo "Summary: $DIFFS file(s) with diffs, $MISSING missing locally."
[[ $DIFFS -eq 0 && $MISSING -eq 0 ]] && echo "Parity looks good (modulo rebrand token normalization)."
