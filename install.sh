#!/usr/bin/env bash

# QHTL Firewall umbrella installer
# Auto-detects your hosting panel and runs the matching installer from this repo.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/danpolltd/LinkNine/feat/cpanel-theming/install.sh | bash
#   
# Options:
#   --branch <name>    Branch to install from (default: $QHTL_BRANCH or 'main')
#   --repo <owner/repo>GitHub repo slug (default: $QHTL_REPO_SLUG or 'danpolltd/LinkNine')
#   --dry-run          Print detected panel and installer URL, then exit
#   -h, --help         Show help

set -euo pipefail

BRANCH="${QHTL_BRANCH:-main}"
REPO_SLUG="${QHTL_REPO_SLUG:-danpolltd/LinkNine}"
DRY_RUN=0

print_help() {
  cat <<EOF
QHTL Firewall umbrella installer

Auto-detects your hosting panel and runs the matching installer from GitHub.

Options:
  --branch <name>      Branch to install from (default: \"${BRANCH}\")
  --repo <owner/repo>  GitHub repo slug (default: \"${REPO_SLUG}\")
  --dry-run            Print detected panel and installer URL, then exit
  -h, --help           Show this help and exit

Examples:
  curl -fsSL https://raw.githubusercontent.com/${REPO_SLUG}/${BRANCH}/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/${REPO_SLUG}/${BRANCH}/install.sh | bash -s -- --branch feat/cpanel-theming
EOF
}

# Parse args
ARGS=( "$@" )
i=0
while [ $i -lt ${#ARGS[@]} ]; do
  case "${ARGS[$i]}" in
    --branch)
      i=$((i+1)); BRANCH="${ARGS[$i]:-"$BRANCH"}" ;;
    --branch=*)
      BRANCH="${ARGS[$i]#*=}" ;;
    --repo)
      i=$((i+1)); REPO_SLUG="${ARGS[$i]:-"$REPO_SLUG"}" ;;
    --repo=*)
      REPO_SLUG="${ARGS[$i]#*=}" ;;
    --dry-run)
      DRY_RUN=1 ;;
    -h|--help)
      print_help; exit 0 ;;
    --)
      # stop parsing
      shift $((i+1)); break ;;
    *)
      # ignore unknown args here; forward them to inner installer if any
      ;;
  esac
  i=$((i+1))
done

if [ "${EUID}" -ne 0 ]; then
  echo "[!] Please run as root (required to install panel integrations)." >&2
  exit 1
fi

detect_panel() {
  if [ -f /usr/local/cpanel/version ]; then echo cpanel; return; fi
  if [ -d /usr/local/directadmin ]; then echo directadmin; return; fi
  if [ -d /usr/local/CyberCP ]; then echo cyberpanel; return; fi
  if [ -d /usr/local/cwpsrv ]; then echo cwp; return; fi
  if [ -d /usr/local/interworx ]; then echo interworx; return; fi
  if [ -d /usr/local/vesta ]; then echo vesta; return; fi
  echo generic
}

PANEL="$(detect_panel)"

case "$PANEL" in
  cpanel)      INSTALLER="install.cpanel.sh" ;;
  directadmin) INSTALLER="install.directadmin.sh" ;;
  cyberpanel)  INSTALLER="install.cyberpanel.sh" ;;
  cwp)         INSTALLER="install.cwp.sh" ;;
  interworx)   INSTALLER="install.interworx.sh" ;;
  vesta)       INSTALLER="install.vesta.sh" ;;
  *)           INSTALLER="install.generic.sh" ;;
esac

RAW_URL="https://raw.githubusercontent.com/${REPO_SLUG}/${BRANCH}/qhtlfirewall/${INSTALLER}"

echo "[i] Detected panel: ${PANEL}"
echo "[i] Using installer: ${INSTALLER}"
echo "[i] From: ${REPO_SLUG}@${BRANCH}"

if [ "${DRY_RUN}" -eq 1 ]; then
  echo "[dry-run] Would fetch: ${RAW_URL}"
  exit 0
fi

TMP="$(mktemp -t qhtlf-install-XXXXXX)"
cleanup() { rm -f "$TMP" || true; }
trap cleanup EXIT

echo "[i] Downloading installer..."
if ! curl -fsSL "$RAW_URL" -o "$TMP"; then
  echo "[!] Failed to download: $RAW_URL" >&2
  exit 1
fi

chmod +x "$TMP"
echo "[i] Running ${INSTALLER}..."
"$TMP" "$@"

echo "[✓] QHTL Firewall install finished"
