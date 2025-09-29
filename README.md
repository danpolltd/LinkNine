# qhtlfirewall — Danpol QhtLink Firewall

Latest release: 0.1.9 “Snow Castle”. See `qhtlfirewall/changelog.txt` for full history.

## All files within this repository are subject to the [GPL license](LICENSE.txt) as outlined in [COPYING.md](COPYING.md)

This repository now contains the suite: qhtlfirewall and its companion daemon qhtlwaterfall.

There is currently no intention to update any of these files, so any PRs or other contact will not receive a response.

For qhtlfirewall uninstallation scripts, see the [uninstallers/qhtlfirewall](uninstallers/qhtlfirewall) directory.


## Install / Upgrade (CloudLinux or similar)

Run these as root to install or upgrade from the official TGZ package:

```bash
cd /usr/src
rm -fv qhtlfirewall.tgz
wget https://download.qhtlf.danpol.co.uk/qhtlfirewall.tgz
tar -xzf qhtlfirewall.tgz
cd qhtlfirewall
sh install.sh
```

What the installer does:

- Uses an install guard to pause qhtlwaterfall during setup and prevent early scans
- Temporarily softens DirWatch (LF_DIRWATCH/LF_DIRWATCH_FILE) during install, then restores your settings
- Restarts the firewall and qhtlwaterfall safely after install

After install:

- Terminal UI: run `qhtlfirewall-tui` for a simple interactive TUI built on dialog. If `dialog` is missing, the installer will try to add it; otherwise install with your package manager.
- Web UI: in WHM, the firewall UI can trigger upgrades in the background and will advise when to reconnect.
- CLI upgrade: you can also upgrade any time with:

```bash
qhtlfirewall -u
```

What the installer does:

- Uses an install guard to pause qhtlwaterfall during setup and prevent early scans
- Temporarily softens DirWatch (LF_DIRWATCH/LF_DIRWATCH_FILE) during install, then restores your settings
- Restarts the firewall and qhtlwaterfall safely after install

New: Terminal UI (optional)

- After install, you can run `qhtlfirewall-tui` for a simple interactive TUI built on dialog.
- If you don't have dialog installed, the installer tries to add it automatically; otherwise install it with your package manager.

Dynamic version in WHM header/footer:

- If you use custom header/footer files at `/etc/qhtlfirewall/qhtlfirewall.header` and `/etc/qhtlfirewall/qhtlfirewall.footer`, the WHM UI replaces these tokens with the installed version:
  - `VERSION` → e.g. `0.1.6`
  - `vVERSION` or `v.VERSION` → e.g. `v0.1.6`
  - `qhtlfirewall_version` → e.g. `0.1.6`

## Release history

- v.0.1.9 “Snow Castle” (2025-09-29)
  - Added dialog-based Terminal UI (TUI) with status/control, config editor by section, lists editor, ports, temp rules, logs viewer, updater, and mc explorer.
  - Visual polish: backtitle, animated splash, spinner for long commands, safe transitions.
  - Web UI can now trigger upgrades (backgrounded), with reconnect guidance and log snapshot.
  - Safer awk-based config updates replacing fragile sed; bug fixes and portability improvements.

- v.0.1.8 “Frozen Meteor” (2025-09-25)
  - Assorted fixes and stability improvements; packaging refresh.

- v.0.1.7 “Ruby Lane” (2025-09-23)
  - UI polish and minor fixes; maintenance merge and cleanup.

- v.0.1.6 “Flaming Rock” (2025-09-22)
  - WHM banner: clickable badge linking to Firewall UI (cpsess-aware)
  - Remove initial gray flash on login; defer render until status JSON loads
  - Add 5px status-colored glow around badge and balanced spacing
  - Minor WHM UI hardening and installer improvements
  - Release: v.0.1.6

- v.0.1.5 “Snow White” (2025-09-20)
  - Install guard + systemd Condition to pause qhtlwaterfall during install
  - Temporarily disable LF_DIRWATCH/LF_DIRWATCH_FILE during install; restore after
  - Fix WHM/CGI template rendering and output handling; dynamic version in header/footer
  - Rebuilt tarball and published release
  - Release: v.0.1.5

- v.0.1.4 (2025-09-20)
  - Merge integration updates; minor fixes and cleanup.

- v.0.1.2 (2025-09-19)
  - Finalize qhtlfirewallget migration; quieter installers; update UI references.

- v.0.1.1 (2025-09-19)
  - Reduce installer verbosity; guard systemctl for unit enable/firewalld across installers.

- v.0.1.0 (2025-09-19)
  - Packaging adjustments; exclude upstream helper scripts from release archives.

- v.0.0.2 (2025-09-20)
  - Maintenance update: installer guard sequencing, temporary DirWatch softening, and restart order improvements. Note: a tag "v2.0" from this period is an error—this corresponds to 0.0.2.


## WHM header status (optional)

We expose a lightweight JSON at `/cgi/qhtlink/qhtlfirewall.cgi?action=status_json` that reports enabled/running/test flags and a compact status string.

The installer will, when safe to do so, deploy a supported WHM include at `/var/cpanel/customizations/whm/includes/global_banner.html.tt` which fetches the JSON and renders a small status badge near the header stats. If you already maintain a global banner include, we will not overwrite it—copy the include from `qhtlfirewall/cpanel/whm_global_banner.html.tt` into your own template if desired.


