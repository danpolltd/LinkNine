#!/usr/bin/env bash
set -euo pipefail
ver=$(tr -d '\n' < update_artifacts/version.txt)
echo "Detected version: $ver"
# Sync internal tree version.txt if present and different
if [ -f qhtlfirewall/version.txt ]; then
	cur=$(tr -d '\n' < qhtlfirewall/version.txt || true)
	if [ "$cur" != "$ver" ]; then
		echo "Syncing internal qhtlfirewall/version.txt ($cur -> $ver)";
		printf '%s\n' "$ver" > qhtlfirewall/version.txt;
	fi
fi
out_versioned="update_artifacts/qhtlfirewall-${ver}.tgz"
out_canonical="update_artifacts/qhtlfirewall.tgz"
echo "Building $out_versioned"
tar -czf "$out_versioned" qhtlfirewall
cp -f "$out_versioned" "$out_canonical"
sha=$(sha256sum "$out_canonical" | awk '{print $1}')
echo "sha256  $sha  qhtlfirewall.tgz (version $ver)" > update_artifacts/qhtlfirewall.sha256
echo "Wrote sha256 for canonical tarball (copied from versioned) to update_artifacts/qhtlfirewall.sha256"