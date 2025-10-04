#!/usr/bin/env bash
set -euo pipefail
ver="0.1.65"
out_versioned="update_artifacts/qhtlfirewall-${ver}.tgz"
out_canonical="update_artifacts/qhtlfirewall.tgz"
echo "Building $out_versioned"
tar -czf "$out_versioned" qhtlfirewall
cp -f "$out_versioned" "$out_canonical"
sha=$(sha256sum "$out_canonical" | awk '{print $1}')
echo "sha256  $sha  qhtlfirewall.tgz (version $ver)" > update_artifacts/qhtlfirewall.sha256
echo "Wrote sha256 for canonical tarball (copied from versioned) to update_artifacts/qhtlfirewall.sha256"