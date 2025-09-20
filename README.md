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


