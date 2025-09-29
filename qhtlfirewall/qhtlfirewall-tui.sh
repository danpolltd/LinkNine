#!/usr/bin/env bash
# qhtlfirewall-tui: Simple TUI wrapper around qhtlfirewall using dialog
# Requirements: dialog

set -euo pipefail

QHTL_BIN=${QHTL_BIN:-/usr/sbin/qhtlfirewall}
LOG_FILE=${LOG_FILE:-/var/log/qhtlwaterfall.log}
CONFIG_FILE=${CONFIG_FILE:-/etc/qhtlfirewall/qhtlfirewall.conf}

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

escape_sed() {
  sed 's/[&\\/]/\\&/g'
}

get_sections() {
  # Output: lineNumber|Section Name
  awk 'BEGIN{FS=":"}
       /^# SECTION:/ { name=$0; sub(/^# SECTION:[ ]*/,"",name); print NR"|"name }' "$CONFIG_FILE"
}

list_keys_in_range() {
  local start=$1 end=$2
  awk -v s="$start" -v e="$end" 'NR>=s && NR<e && /^[A-Z0-9_]+[[:space:]]*=/ {
    key=$1; sub(/[[:space:]]*=.*/,"",key);
    match($0,/"(.*)"/,m); val=m[1];
    print key"|"val
  }' "$CONFIG_FILE"
}

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
}

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
      about "About / Version" \
      quit "Quit") || break
    case "$choice" in
      status) action_status ;;
      control) action_control ;;
      config) action_config ;;
      lists) action_lists ;;
      allowdeny) action_allow_deny ;;
      temp) action_temp ;;
      ports) action_ports ;;
      update) action_update ;;
      logs) action_logs ;;
      about) run_cmd "Version" "$QHTL_BIN" -v ;;
      quit) break ;;
    esac
  done
}

need_root
check_prereqs
main_menu
