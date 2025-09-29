#!/usr/bin/env bash
# qhtlfirewall-tui: Simple TUI wrapper around qhtlfirewall using dialog
# Requirements: dialog

set -euo pipefail

QHTL_BIN=${QHTL_BIN:-/usr/sbin/qhtlfirewall}
LOG_FILE=${LOG_FILE:-/var/log/qhtlwaterfall.log}

red() { printf "\033[31m%s\033[0m\n" "$*"; }

need_root() {
  if [[ $(id -u) -ne 0 ]]; then
    red "Please run as root (sudo qhtlfirewall-tui)"; exit 1
  fi
}

check_prereqs() {
  if ! command -v "$QHTL_BIN" >/dev/null 2>&1; then
    red "Cannot find $QHTL_BIN. Is qhtlfirewall installed?"; exit 1
  fi
  if ! command -v dialog >/dev/null 2>&1; then
    cat <<EOF
"dialog" is required for the TUI.

Install it and retry:
  - RHEL/CloudLinux:  sudo dnf -y install dialog || sudo yum -y install dialog
  - Debian/Ubuntu:    sudo apt-get update && sudo apt-get -y install dialog
  - SUSE:             sudo zypper -n install dialog
EOF
    exit 1
  fi
}

run_cmd() {
  local title=$1; shift
  local out
  if ! out=$("$@" 2>&1); then
    dialog --title "$title (failed)" --msgbox "$out" 20 80
    return 1
  fi
  dialog --title "$title" --msgbox "$out" 20 80
}

action_status() { run_cmd "Firewall Status" "$QHTL_BIN" -l; }
action_ports() { run_cmd "Open Ports" "$QHTL_BIN" -p; }
action_update() { run_cmd "Update" "$QHTL_BIN" -u; }

action_control() {
  local choice
  while true; do
    choice=$(dialog --clear --stdout --title "Control" --menu "Select action" 15 60 8 \
      start "Start" \
      restart "Restart" \
      stop "Stop" \
      enable "Enable" \
      disable "Disable" \
      restartall "Restart All (FW+WF)" \
      waterfall "Start qhtlwaterfall" \
      back "Back") || return
    case "$choice" in
      start) run_cmd "Start" "$QHTL_BIN" -s ;;
      restart) run_cmd "Restart" "$QHTL_BIN" -r ;;
      stop) run_cmd "Stop" "$QHTL_BIN" -f ;;
      enable) run_cmd "Enable" "$QHTL_BIN" -e ;;
      disable) run_cmd "Disable" "$QHTL_BIN" -x ;;
      restartall) run_cmd "Restart All" "$QHTL_BIN" -ra ;;
      waterfall) run_cmd "Start qhtlwaterfall" "$QHTL_BIN" -q ;;
      back) break ;;
    esac
  done
}

prompt_ip() {
  local title=$1; local ip
  ip=$(dialog --clear --stdout --title "$title" --inputbox "Enter IP or CIDR" 8 60) || return 1
  [[ -n $ip ]] || return 1
  printf '%s' "$ip"
}

action_allow_deny() {
  local choice ip
  while true; do
    choice=$(dialog --clear --stdout --title "Allow / Deny" --menu "Select action" 15 60 8 \
      allow "Add to Allow" \
      addrmp "Remove from Allow" \
      deny "Add to Deny" \
      denyrm "Remove from Deny" \
      back "Back") || return
    case "$choice" in
      allow)
        if ip=$(prompt_ip "Allow IP"); then run_cmd "Allow $ip" "$QHTL_BIN" -a "$ip"; fi ;;
      addrmp)
        if ip=$(prompt_ip "Remove Allowed IP"); then run_cmd "Allow Remove $ip" "$QHTL_BIN" -ar "$ip"; fi ;;
      deny)
        if ip=$(prompt_ip "Deny IP"); then run_cmd "Deny $ip" "$QHTL_BIN" -d "$ip"; fi ;;
      denyrm)
        if ip=$(prompt_ip "Remove Denied IP"); then run_cmd "Deny Remove $ip" "$QHTL_BIN" -dr "$ip"; fi ;;
      back) break ;;
    esac
  done
}

action_temp() {
  local choice ip minutes secs
  while true; do
    choice=$(dialog --clear --stdout --title "Temporary Rules" --menu "Select action" 15 60 8 \
      tempdeny "Temp Deny" \
      tempallow "Temp Allow" \
      temprm "Remove Temp by IP" \
      temprma "Remove All Temps" \
      back "Back") || return
    case "$choice" in
      tempdeny)
        if ip=$(prompt_ip "Temp Deny IP"); then
          minutes=$(dialog --clear --stdout --title "Duration" --inputbox "Minutes (default 60)" 8 40 "60") || continue
          [[ -z "$minutes" ]] && minutes=60
          secs=$((minutes*60))
          run_cmd "Temp Deny $ip for ${minutes}m" "$QHTL_BIN" -td "$ip" "$secs"
        fi ;;
      tempallow)
        if ip=$(prompt_ip "Temp Allow IP"); then
          minutes=$(dialog --clear --stdout --title "Duration" --inputbox "Minutes (default 60)" 8 40 "60") || continue
          [[ -z "$minutes" ]] && minutes=60
          secs=$((minutes*60))
          run_cmd "Temp Allow $ip for ${minutes}m" "$QHTL_BIN" -ta "$ip" "$secs"
        fi ;;
      temprm)
        if ip=$(prompt_ip "Remove Temp for IP"); then run_cmd "Temp Remove $ip" "$QHTL_BIN" -tr "$ip"; fi ;;
      temprma) run_cmd "Temp Remove All" "$QHTL_BIN" -tra ;;
      back) break ;;
    esac
  done
}

action_logs() {
  if [[ -r "$LOG_FILE" ]]; then
    dialog --title "qhtlwaterfall.log (last 300 lines)" --textbox <(tail -n 300 "$LOG_FILE") 25 100
  else
    dialog --title "Logs" --msgbox "Log file not readable: $LOG_FILE" 8 60
  fi
}

main_menu() {
  local choice
  while true; do
    choice=$(dialog --clear --stdout --title "QhtLink Firewall (TUI)" --menu "Choose a section" 18 70 10 \
      status "Status" \
      control "Start/Stop/Enable/Disable" \
      allowdeny "Allow / Deny" \
      temp "Temporary Rules" \
      ports "Open Ports" \
      update "Update" \
      logs "Logs" \
      quit "Quit") || break
    case "$choice" in
      status) action_status ;;
      control) action_control ;;
      allowdeny) action_allow_deny ;;
      temp) action_temp ;;
      ports) action_ports ;;
      update) action_update ;;
      logs) action_logs ;;
      quit) break ;;
    esac
  done
}

need_root
check_prereqs
main_menu
