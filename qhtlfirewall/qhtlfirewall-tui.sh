#!/usr/bin/env bash
# qhtlfirewall-tui: Simple TUI wrapper around qhtlfirewall using dialog
# Requirements: dialog

set -euo pipefail

QHTL_BIN=${QHTL_BIN:-/usr/sbin/qhtlfirewall}
LOG_FILE=${LOG_FILE:-/var/log/qhtlwaterfall.log}
CONFIG_FILE=${CONFIG_FILE:-/etc/qhtlfirewall/qhtlfirewall.conf}
THEME_FILE=${THEME_FILE:-/etc/qhtlfirewall/ui/dialogrc}
LOG_LIST_FILE=${LOG_LIST_FILE:-/etc/qhtlfirewall/qhtlfirewall.logfiles}

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

# Add a wrapper so all dialogs share a consistent backtitle
BACKTITLE="QhtLink Firewall — TUI"
dialog() {
  command dialog --backtitle "$BACKTITLE" "$@"
}

# Simple animated gauge used as a spinner while commands run
spinner_start() {
  local title=${1:-Working} msg=${2:-Please wait...}
  { while :; do for p in 0 10 20 30 40 50 60 70 80 90 100; do echo $p; sleep 0.08; done; done; } \
    | command dialog --backtitle "$BACKTITLE" --title "$title" --gauge "$msg" 7 60 0 &
  SPINNER_PID=$!
}

spinner_stop() {
  if [[ -n ${SPINNER_PID:-} ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    unset SPINNER_PID
  fi
}

# Optional splash screen on startup
splash_screen() {
  [[ ${TUI_NO_SPLASH:-0} -eq 1 ]] && return 0
  { for p in 0 20 40 60 80 100; do echo $p; sleep 0.12; done; } \
    | command dialog --backtitle "$BACKTITLE" --title "Starting…" --gauge "Loading QhtLink Firewall TUI…" 7 60 0
}

# Wrapper to run a command and show its output
run_cmd() {
  local title=$1; shift
  local tmp
  tmp=$(mktemp)
  spinner_start "$title" "Running: $*"
  if "$@" >"$tmp" 2>&1; then
    spinner_stop
    local out
    out=$(sed -n '1,400p' "$tmp")
    if [[ -z "$out" ]]; then out="(no output)"; fi
    dialog --title "$title" --msgbox "$out" 22 100
  else
    spinner_stop
    local out
    out=$(sed -n '1,400p' "$tmp")
    dialog --title "$title (error)" --msgbox "$out" 22 100
  fi
  rm -f "$tmp"
}

# Status view
action_status() {
  run_cmd "Status" "$QHTL_BIN" -l
}

# Parse section headers from config
get_sections() {
  # Output: lineNumber|Section Name
  awk 'BEGIN{FS=":"} /^# SECTION:/ {name=$0; sub(/^# SECTION:[[:space:]]*/,"",name); printf("%d|%s\n", NR, name)}' "$CONFIG_FILE"
}

# List editable keys between two line numbers (start inclusive, end exclusive)
list_keys_in_range() {
  local start=$1 end=$2
  awk -v s="$start" -v e="$end" 'NR>=s && NR<e && /^[A-Z0-9_]+[[:space:]]*=/{
    key=$1; sub(/[[:space:]]*=.*/,"",key);
    match($0,/\"([^\"]*)\"/,m); val=m[1];
    print key"|"val
  }' "$CONFIG_FILE"
}

# Edit single key in config safely
edit_key() {
  local key=$1 cur=$2
  local new
  new=$(dialog --clear --stdout --title "Edit $key" --inputbox "$key value" 9 70 "$cur") || return
  # Backup once per session
  if [[ -z ${__CFG_BK_DONE:-} ]]; then
    cp -a "$CONFIG_FILE" "${CONFIG_FILE}.tui.$(date +%Y%m%d%H%M%S).bak" 2>/dev/null || true
    __CFG_BK_DONE=1
  fi
  # Escape for AWK string concatenation
  local awkV
  awkV=$(printf '%s' "$new" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  awk -v K="$key" -v V="$awkV" 'BEGIN{done=0} {
    if (!done && $0 ~ ("^" K "[[:space:]]*=")) {
      sub(/\"[^\"]*\"/, "\"" V "\"")
      done=1
    }
    print
  }' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv -f "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  # Offer restart prompt after change
  if dialog --title "Apply change" --yesno "Restart qhtlfirewall now to apply changes?" 7 60; then
    "$QHTL_BIN" -r >/tmp/qhtl-tui-apply.$$ 2>&1 || true
    dialog --title "Restart" --msgbox "$(tail -n 200 /tmp/qhtl-tui-apply.$$)" 20 80
    rm -f /tmp/qhtl-tui-apply.$$ 2>/dev/null || true
  fi
}

# Edit list-like or arbitrary file via dialog editbox
edit_file_dialog() {
  local path=$1 title=$2
  if [[ ! -e "$path" ]]; then
    : > "$path" || { dialog --msgbox "Cannot create $path" 7 60; return 1; }
  fi
  local tmp
  tmp=$(mktemp)
  cp -a "$path" "$tmp" 2>/dev/null || true
  dialog --title "$title" --editbox "$tmp" 25 100 || { rm -f "$tmp"; return 1; }
  cp -f "$tmp" "$path" && dialog --msgbox "Saved $path" 6 60
  rm -f "$tmp"
}

# Configuration editor by section
action_config() {
  if [[ ! -r "$CONFIG_FILE" ]]; then
    dialog --title "Configuration" --msgbox "Cannot read $CONFIG_FILE" 8 70
    return
  fi
  while true; do
    # Build sections
    mapfile -t SEC_LINES < <(get_sections)
    if [[ ${#SEC_LINES[@]} -eq 0 ]]; then
      dialog --title "Configuration" --msgbox "No sections found in $CONFIG_FILE" 8 70
      return
    fi
    # Prepare menu items
    local items=()
    local s
    for s in "${SEC_LINES[@]}"; do
      local ln name
      ln=${s%%|*}; name=${s#*|}
      items+=("$ln" "$name")
    done
    items+=("search" "Search key by name")
    items+=("back" "Back")
    local secSel
    secSel=$(dialog --clear --stdout --title "Configuration Sections" --menu "Select a section to edit" 22 80 14 "${items[@]}") || return
    case "$secSel" in
      back) return ;;
      search)
        local q
        q=$(dialog --clear --stdout --title "Search" --inputbox "Enter KEY to edit (exact)" 8 60) || continue
        if [[ -n "$q" ]]; then
          local cur
          cur=$(awk -v k="$q" 'BEGIN{IGNORECASE=0} $0 ~ "^"k"[[:space:]]*=" {match($0,/\"([^\"]*)\"/,m); print m[1]; exit}' "$CONFIG_FILE")
          if [[ -z "$cur" ]]; then dialog --msgbox "Key not found: $q" 7 50; continue; fi
          edit_key "$q" "$cur" && dialog --msgbox "Saved $q" 6 40
        fi
        continue
        ;;
      *)
        # Determine range: secSel line to next section or EOF+1
        local start end
        start=$secSel
        end=$(awk -v s="$start" 'NR>s && /^# SECTION:/ {print NR; exit}' "$CONFIG_FILE")
        [[ -z "$end" ]] && end=$(( $(wc -l < "$CONFIG_FILE") + 1 ))
        while true; do
          # Build key menu for the section
          mapfile -t KV < <(list_keys_in_range "$start" "$end")
          if [[ ${#KV[@]} -eq 0 ]]; then dialog --msgbox "No editable keys in this section" 7 60; break; fi
          local kitems=()
          local kv
          for kv in "${KV[@]}"; do
            local k v
            k=${kv%%|*}; v=${kv#*|}
            # Truncate value preview
            [[ ${#v} -gt 60 ]] && v="${v:0:57}..."
            kitems+=("$k" "$v")
          done
          kitems+=("back" "Back to sections")
          local ksel
          ksel=$(dialog --clear --stdout --title "Edit Keys" --menu "Choose a key to edit" 22 100 14 "${kitems[@]}") || break
          [[ "$ksel" = "back" ]] && break
          # Find current value
          local cur
          cur=$(awk -v k="$ksel" 'BEGIN{IGNORECASE=0} $0 ~ "^"k"[[:space:]]*=" {match($0,/\"([^\"]*)\"/,m); print m[1]; exit}' "$CONFIG_FILE")
          edit_key "$ksel" "$cur" && dialog --msgbox "Saved $ksel" 6 40
        done
        ;;
    esac
  done
}

# Manage Lists
action_lists() {
  local base=/etc/qhtlfirewall
  while true; do
    local choice
    choice=$(dialog --clear --stdout --title "Lists" --menu "Choose a list to edit" 20 80 12 \
      allow "$base/qhtlfirewall.allow" \
      deny "$base/qhtlfirewall.deny" \
      ignore "$base/qhtlfirewall.ignore" \
      pignore "$base/qhtlfirewall.pignore" \
      rignore "$base/qhtlfirewall.rignore" \
      fignore "$base/qhtlfirewall.fignore" \
      sips "$base/qhtlfirewall.sips" \
      blocklists "$base/qhtlfirewall.blocklists" \
      cloudflare "$base/qhtlfirewall.cloudflare" \
      redirect "$base/qhtlfirewall.redirect" \
      other "Browse another file..." \
      back "Back") || return
    case "$choice" in
      allow) edit_file_dialog "$base/qhtlfirewall.allow" "Allow List" ;;
      deny) edit_file_dialog "$base/qhtlfirewall.deny" "Deny List" ;;
      ignore) edit_file_dialog "$base/qhtlfirewall.ignore" "Ignore List" ;;
      pignore) edit_file_dialog "$base/qhtlfirewall.pignore" "Process Ignore" ;;
      rignore) edit_file_dialog "$base/qhtlfirewall.rignore" "Recursive Ignore" ;;
      fignore) edit_file_dialog "$base/qhtlfirewall.fignore" "File Ignore" ;;
      sips) edit_file_dialog "$base/qhtlfirewall.sips" "Static IPs" ;;
      blocklists) edit_file_dialog "$base/qhtlfirewall.blocklists" "Blocklists" ;;
      cloudflare) edit_file_dialog "$base/qhtlfirewall.cloudflare" "Cloudflare" ;;
      redirect) edit_file_dialog "$base/qhtlfirewall.redirect" "Redirects" ;;
      other)
        local p
        p=$(dialog --clear --stdout --title "Open" --inputbox "Enter full path to edit" 8 70 "$base/") || continue
        [[ -z "$p" ]] && continue
        edit_file_dialog "$p" "Edit $p"
        ;;
      back) return ;;
    esac
  done
}

# Control submenu
action_control() {
  local choice
  while true; do
    choice=$(dialog --clear --stdout --title "Control" --menu "Select action" 15 70 10 \
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

# Prompt for IP helper
prompt_ip() {
  local title=$1; local ip
  ip=$(dialog --clear --stdout --title "$title" --inputbox "Enter IP or CIDR" 8 60) || return 1
  [[ -n $ip ]] || return 1
  printf '%s' "$ip"
}

# Quick allow/deny
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

# Temporary rules
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

# Open ports helper
action_ports() {
  local ports
  ports=$(dialog --clear --stdout --title "Open Ports" --inputbox "Enter ports (comma separated)" 8 60) || return
  [[ -z "$ports" ]] && return
  run_cmd "Open Ports" "$QHTL_BIN" -o "$ports"
}

# Update helper
action_update() {
  run_cmd "Update" "$QHTL_BIN" -u
}

# Logs viewer
action_logs() {
  # Gather candidates from configured list and common defaults
  local -a candidates items
  candidates=("$LOG_FILE" /var/log/messages /var/log/kern.log /var/log/syslog)
  if [[ -r "$LOG_LIST_FILE" ]]; then
    while IFS= read -r line; do
      line=${line%%$'\r'}
      # strip leading/trailing whitespace
      line=${line##+([[:space:]])}
      line=${line%%+([[:space:]])}
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      [[ "$line" == /* ]] || continue
      candidates+=("$line")
    done < <(sed -e 's/\t/ /g' "$LOG_LIST_FILE")
  fi
  # Build menu items with readability check and de-dup
  items=()
  local f i exists
  for f in "${candidates[@]}"; do
    [[ -r "$f" ]] || continue
    exists=0
    for ((i=0; i<${#items[@]}; i+=2)); do
      if [[ "${items[i]}" == "$f" ]]; then exists=1; break; fi
    done
    if [[ $exists -eq 0 ]]; then
      items+=("$f" "view")
    fi
  done
  # Provide Back option only (no browsing from here)
  items+=("back" "Back")
  local pick
  pick=$(dialog --clear --stdout --title "Logs" --menu "Choose a log to view (live)" 22 100 16 "${items[@]}") || return
  case "$pick" in
    back|"") return ;;
  esac
  # small transition hint
  command dialog --backtitle "$BACKTITLE" --infobox "Opening $(basename "$pick")…" 5 60; sleep 0.15
  if [[ -r "$pick" ]]; then
    if [[ ! -s "$pick" ]]; then
      dialog --title "Logs" --msgbox "The file $(basename "$pick") is currently empty." 8 70
    else
      dialog --title "$(basename "$pick") (live)" --tailbox "$pick" 25 100
    fi
  else
    dialog --title "Logs" --msgbox "Log file not readable: $pick" 8 60
  fi
}

# Ensure Midnight Commander is available, optionally offer to install
ensure_mc() {
  if command -v mc >/dev/null 2>&1; then return 0; fi
  if dialog --title "File Explorer" --yesno "Midnight Commander (mc) is not installed. Install it now?" 8 70; then
    # Try common package managers
    run_cmd "Install Midnight Commander" /bin/sh -c '
      if command -v dnf >/dev/null 2>&1; then dnf -y install mc;
      elif command -v yum >/dev/null 2>&1; then yum -y install mc;
      elif command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get -y install mc;
      elif command -v zypper >/dev/null 2>&1; then zypper -n install mc;
      else echo "No supported package manager found."; exit 1; fi'
  fi
  command -v mc >/dev/null 2>&1
}

# Launch file explorer (mc)
action_explorer() {
  if ! ensure_mc; then
    dialog --title "File Explorer" --msgbox "Midnight Commander (mc) is not available." 7 60
    return
  fi
  # Clear dialog screen and launch mc; resume TUI when it exits
  command dialog --clear
  clear
  mc || true
  # Small notice on return
  command dialog --backtitle "$BACKTITLE" --infobox "Returned from File Explorer" 5 50; sleep 0.2
}

# Main menu
main_menu() {
  local choice
  while true; do
    # subtle fade-in effect between menu refreshes
    command dialog --backtitle "$BACKTITLE" --infobox "" 1 1; sleep 0.05
    choice=$(dialog --clear --stdout --title "QhtLink Firewall (TUI)" --menu "Choose a section" 22 80 14 \
      status "Status" \
      control "Start/Stop/Enable/Disable" \
      config "Configuration (edit qhtlfirewall.conf by section)" \
      lists "Lists (allow/deny/ignore/etc.)" \
      allowdeny "Quick Allow / Deny" \
      temp "Temporary Rules" \
      ports "Open Ports" \
      update "Update" \
      logs "Logs" \
      explorer "File Explorer (mc)" \
      about "About / Version" \
      quit "Quit") || break
    case "${choice:-}" in
      status) action_status ;;
      control) action_control ;;
      config) action_config ;;
      lists) action_lists ;;
      allowdeny) action_allow_deny ;;
      temp) action_temp ;;
      ports) action_ports ;;
      update) action_update ;;
      logs) action_logs ;;
  explorer) action_explorer ;;
      about) run_cmd "Version" "$QHTL_BIN" -v ;;
      ""|cancel) : ;; # if user presses ESC or cancels, redisplay menu
      quit) break ;;
    esac
  done
}

need_root
check_prereqs
# Optional theme
if [[ -r "$THEME_FILE" ]]; then export DIALOGRC="$THEME_FILE"; fi
splash_screen
main_menu
