# qhtlfirewall — Danpol QhtLink Firewall

### All files within this repository are subject to the [GPL license](LICENSE.txt) as outlined in [COPYING.md](COPYING.md)

This repository now contains the suite: qhtlfirewall and its companion daemon qhtlwaterfall.

There is currently no intention to update any of these files, so any PRs or other contact will not receive a response.

For qhtlfirewall uninstallation scripts, see the [uninstallers/qhtlfirewall](uninstallers/qhtlfirewall) directory.


## Update from main (one-liner)

Use this cache-proof one-liner on a target server to install the latest core modules directly from the main branch. It stops the service, fetches via GitHub API raw (bypassing CDN caches), compile-checks modules, backs up existing files, installs, restarts, and tails logs.

```bash
sh -lc 'set -e -o pipefail; R=danpolltd/LinkNine; API=https://api.github.com/repos/$R/contents; TMP=$(mktemp -d); MODDIR=/usr/local/qhtlfirewall/lib/QhtLink; F=(RegexMain.pm qhtlmanagerUI.pm CloudFlare.pm); systemctl stop qhtlwaterfall || true; for f in "${F[@]}"; do curl -fsSL -H "Accept: application/vnd.github.raw" "$API/qhtlfirewall/QhtLink/$f?ref=main" -o "$TMP/$f"; perl -c "$TMP/$f"; done; TS=$(date +%F-%H%M%S); BAK=/var/lib/qhtlfirewall/backup/$TS; mkdir -p "$BAK/QhtLink" "$MODDIR"; for f in "${F[@]}"; do [ -f "$MODDIR/$f" ] && cp -a "$MODDIR/$f" "$BAK/QhtLink/"; install -m 0644 "$TMP/$f" "$MODDIR/$f"; done; systemctl restart qhtlwaterfall; sleep 1; journalctl -u qhtlwaterfall -n 60 -f'
```

Notes:
- If you want Cloudflare API actions enabled, install libwww-perl (Debian/Ubuntu) or perl-libwww-perl (RHEL/CloudLinux), and set `URLGET=1` in `qhtlfirewall.conf`. Without it, we log and skip Cloudflare calls safely.
- The above updates only module files; for a full reinstall, use the provided installer scripts under `qhtlfirewall/install.*.sh`.

## Dev tools

For local maintenance and parity checks:

- `tools/parity_diff.sh` — Normalized diff against upstream to focus on logic differences and ignore rebrand tokens.
- `tools/PARITY_REPORT.md` — Notes and decisions from parity sweeps.
- `tools/verify_modules.sh` — Compile-check all `QhtLink/*.pm` modules with proper include path.


