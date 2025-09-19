#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$ROOT_DIR/qhtlfirewall"

echo "Verifying Perl modules under: $LIB_DIR/QhtLink"
ok=0; fail=0
while IFS= read -r -d '' f; do
  rel="${f#$ROOT_DIR/}"
  if PERL5LIB="$LIB_DIR" perl -c "$f" >/dev/null 2>&1; then
    printf "[OK]   %s\n" "$rel"; ((ok++))
  else
    printf "[FAIL] %s\n" "$rel"; ((fail++))
    PERL5LIB="$LIB_DIR" perl -c "$f" || true
  fi
done < <(find "$LIB_DIR/QhtLink" -maxdepth 1 -type f -name '*.pm' -print0 | sort -z)

echo "---"
echo "Modules OK: $ok, failed: $fail"
exit $(( fail>0 ? 1 : 0 ))
