#!/usr/bin/env bash
set -euo pipefail
ver="0.1.65"
out="update_artifacts/qhtlfirewall-${ver}.tgz"
echo "Building $out"
tar -czf "$out" qhtlfirewall
sha=$(sha256sum "$out" | awk '{print $1}')
echo "sha256  $sha  qhtlfirewall.tgz (version $ver)" > update_artifacts/qhtlfirewall.sha256
echo "Wrote sha256 to update_artifacts/qhtlfirewall.sha256"