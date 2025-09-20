# qhtlfirewall — Danpol QhtLink Firewall

### All files within this repository are subject to the [GPL license](LICENSE.txt) as outlined in [COPYING.md](COPYING.md)

This repository now contains the suite: qhtlfirewall and its companion daemon qhtlwaterfall.

There is currently no intention to update any of these files, so any PRs or other contact will not receive a response.

For qhtlfirewall uninstallation scripts, see the [uninstallers/qhtlfirewall](uninstallers/qhtlfirewall) directory.


## Install / Upgrade (CloudLinux or similar)

Run as root to install or upgrade to the latest published release (v.0.1.5 – Snow White):

```bash
curl -fsSL https://github.com/danpolltd/LinkNine/releases/download/v.0.1.5/qhtlfirewall-main.tar.gz -o /tmp/qhtlfirewall.tar.gz && \
	mkdir -p /root/qhtlfirewall-install && \
	tar -xzf /tmp/qhtlfirewall.tar.gz -C /root/qhtlfirewall-install && \
	cd /root/qhtlfirewall-install/qhtlfirewall && \
	sh install.sh
```

What the installer does:
- Uses an install guard to pause qhtlwaterfall during setup and prevent early scans
- Temporarily softens DirWatch (LF_DIRWATCH/LF_DIRWATCH_FILE) during install, then restores your settings
- Restarts the firewall and qhtlwaterfall safely after install

Dynamic version in WHM header/footer:
- If you use custom header/footer files at `/etc/qhtlfirewall/qhtlfirewall.header` and `/etc/qhtlfirewall/qhtlfirewall.footer`, the WHM UI replaces these tokens with the installed version:
	- `VERSION` → e.g. `0.1.5`
	- `vVERSION` or `v.VERSION` → e.g. `v0.1.5`
	- `qhtlfirewall_version` → e.g. `0.1.5`

## Release history

- v.0.1.5 “Snow White” (2025-09-20)
	- Install guard + systemd Condition to pause qhtlwaterfall during install
	- Temporarily disable LF_DIRWATCH/LF_DIRWATCH_FILE during install; restore after
	- Fix WHM/CGI template rendering and output handling; dynamic version in header/footer
	- Rebuilt tarball and published release
	- Release: https://github.com/danpolltd/LinkNine/releases/tag/v.0.1.5


## WHM header status (optional)

We expose a lightweight JSON at `/cgi/qhtlink/qhtlfirewall.cgi?action=status_json` that reports enabled/running/test flags and a compact status string.

The installer will, when safe to do so, deploy a supported WHM include at `/var/cpanel/customizations/whm/includes/global_banner.html.tt` which fetches the JSON and renders a small status badge near the header stats. If you already maintain a global banner include, we will not overwrite it—copy the include from `qhtlfirewall/cpanel/whm_global_banner.html.tt` into your own template if desired.


