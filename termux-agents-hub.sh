#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# termux-agents-hub — AI Agent Manager for Termux (Android)
# Supports: Hermes (Nous Research), Codex CLI (OpenAI), OpenClaw Gateway
# Features: Tools Menu, Health Monitor, Quick Connect, History, Backup/Restore
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Metadata ──────────────────────────────────────────────────────────────────
readonly VERSION="3.0.0"
readonly NAME="termux-agents-hub"
readonly HELP_URL="https://github.com/Ryuupyroxi/termux-agents-hub"

# ── Paths (XDG + Termux) ──────────────────────────────────────────────────────
: "${HOME:=/data/data/com.termux/files/home}"
: "${PREFIX:=/data/data/com.termux/files/usr}"

readonly XDG_CONFIG="${XDG_CONFIG_HOME:-${HOME}/.config}"
readonly XDG_DATA="${XDG_DATA_HOME:-${HOME}/.local/share}"
readonly XDG_STATE="${XDG_STATE_HOME:-${HOME}/.local/state}"
readonly XDG_CACHE="${XDG_CACHE_HOME:-${HOME}/.cache}"

CONFIG_DIR="${XDG_CONFIG}/${NAME}"
DATA_DIR="${XDG_DATA}/${NAME}"
STATE_DIR="${XDG_STATE}/${NAME}"
CACHE_DIR="${XDG_CACHE}/${NAME}"
LOG_DIR="${STATE_DIR}/logs"
RUN_DIR="${STATE_DIR}/run"
HISTORY_FILE="${STATE_DIR}/history.log"
BACKUP_DIR="/sdcard/Download/termux-agents-hub-backups"
BACKUP_FALLBACK="${DATA_DIR}/backups"

CONFIG_FILE="${CONFIG_DIR}/config.env"
KEYS_FILE="${CONFIG_DIR}/keys.env"
MIGRATION_DIR="${DATA_DIR}/migration"

HERMES_HOME="${HOME}/.hermes"
CODEX_HOME="${HOME}/.codex"
OPENCLAW_HOME="${HOME}/.openclaw"

# ── Defaults ──────────────────────────────────────────────────────────────────
HERMES_DASH_PORT="9119"
HERMES_API_PORT="9120"
CODEX_PORT_DEFAULT="8082"
OPENCLAW_PORT_DEFAULT="18789"

HERMES_HOST_DEFAULT="0.0.0.0"
MODEL_DEFAULT="openrouter/qwen/qwen3-coder:free"
PROVIDER_DEFAULT="openrouter"
HERMES_THEME_DEFAULT="default"
ENABLE_WAKE_LOCK_DEFAULT="true"
ENABLE_NOTIFICATIONS_DEFAULT="true"
ENABLE_AUTO_RESTART_DEFAULT="false"
HEALTH_POLL_INTERVAL_DEFAULT="5"
MIGRATION_SOURCE_DEFAULT="${DATA_DIR}/migration"
MAX_PORT_TRIES=20

# ── Colors ────────────────────────────────────────────────────────────────────
setup_colors() {
  if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    RST=$(tput sgr0)
    BOLD=$(tput bold)
    DIM=$(tput dim)
    BLACK=$(tput setaf 0)
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    WHITE=$(tput setaf 7)
  else
    RST=""; BOLD=""; DIM=""
    BLACK=""; RED=""; GREEN=""; YELLOW=""
    BLUE=""; MAGENTA=""; CYAN=""; WHITE=""
  fi
  readonly RST BOLD DIM BLACK RED GREEN YELLOW BLUE MAGENTA CYAN WHITE
}

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_FILE=""
setup_logging() {
  mkdir -p "${LOG_DIR}"
  LOG_FILE="${LOG_DIR}/$(date +%Y%m%d-%H%M%S).log"
}

log()   { printf '%b %s %b\n' "${DIM}$(date +%H:%M:%S)${RST}" "$*" | tee -a "${LOG_FILE}"; }
info()  { log "${BOLD}[INFO]${RST} $*"; }
warn()  { log "${YELLOW}[WARN]${RST} $*"; }
error() { log "${RED}[ERR]${RST} $*"; }
ok()    { log "${GREEN}[OK]${RST} $*"; }

# ── UI Primitives ─────────────────────────────────────────────────────────────
ui_header() {
  clear
  printf '\n'
  printf '  %s╔══════════════════════════════════════════════════╗%s\n' "${CYAN}" "${RST}"
  printf '  %s║%s  %s%-48s%s %s║%s\n' "${CYAN}" "${RST}" "${BOLD}" "$1" "${RST}" "${CYAN}" "${RST}"
  printf '  %s║%s  %s%-48s%s %s║%s\n' "${CYAN}" "${RST}" "${DIM}" "${NAME} v${VERSION} — AI Agent Manager" "${RST}" "${CYAN}" "${RST}"
  printf '  %s╚══════════════════════════════════════════════════╝%s\n' "${CYAN}" "${RST}"
}

status_bar() {
  local rc
  rc=$(running_count)
  local ip
  ip=$(get_ip)
  local model_short="${MODEL##*/}"
  local wl_status="OFF"
  [[ "${ENABLE_WAKE_LOCK}" == "true" ]] && wl_status="ON"
  printf '  %s🟢 %s/%s agents • %s • %s • wake:%s%s\n\n' "${DIM}" "${rc}" "4" "${ip}" "${model_short}" "${wl_status}" "${RST}"
}

footer() {
  local wl="OFF"; local nt="OFF"
  [[ "${ENABLE_WAKE_LOCK}" == "true" ]] && wl="ON"
  [[ "${ENABLE_NOTIFICATIONS}" == "true" ]] && nt="ON"
  printf '  %s────────────────────────────────────────────────%s\n' "${DIM}" "${RST}"
  printf '  %s%s v%s • wake:%s • notifications:%s • tools:56%s\n' "${DIM}" "${NAME}" "${VERSION}" "${wl}" "${nt}" "${RST}"
}

prompt_text() { printf '  %s> %s%s' "$1" "${BOLD}" "${RST}"; read -r REPLY; }
confirm()     { printf '  %s> %s [y/N]: %s' "$1" "${BOLD}" "${RST}"; read -r REPLY; [[ "${REPLY}" =~ ^[Yy]$ ]]; }
pause()       { printf '\n  %s> Press Enter to continue...%s' "${DIM}" "${RST}"; read -r _; }
keypress()    { printf '  %s> Press any key...%s' "${DIM}" "${RST}"; read -r -n1 _; }

separator() { printf '\n  %s────────────────────────────────────────────────%s\n' "${DIM}" "${RST}"; }

menu_item() {
  local n=$1 title=$2 status=${3:-} extra=${4:-}
  printf '  %s%2d)%s  %s%s%s %s%s%s\n' \
    "${BOLD}${CYAN}" "$n" "${RST}" \
    "${BOLD}${title}${RST}" \
    "${GREEN}${status:+ [$status]}${RST}" \
    "${DIM}${extra:+ ($extra)}${RST}"
}

# ── Session History ───────────────────────────────────────────────────────────
log_event() {
  local event=$1 agent=$2 details=${3:-}
  mkdir -p "${STATE_DIR}"
  printf '[%s] %-13s | %-15s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${event}" "${agent}" "${details}" >> "${HISTORY_FILE}"
  # Rotate: keep last 1000 lines
  if [[ -f "${HISTORY_FILE}" ]] && [[ $(wc -l < "${HISTORY_FILE}" 2>/dev/null || echo 0) -gt 1000 ]]; then
    tail -1000 "${HISTORY_FILE}" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "${HISTORY_FILE}"
  fi
}

show_history() {
  ui_header "SESSION HISTORY"
  if [[ ! -f "${HISTORY_FILE}" ]] || [[ ! -s "${HISTORY_FILE}" ]]; then
    printf '  %sNo history yet%s\n\n' "${DIM}" "${RST}"
    pause
    return
  fi
  local total
  total=$(wc -l < "${HISTORY_FILE}")
  printf '  %sLast 50 entries • %s total%s\n\n' "${DIM}" "${total}" "${RST}"
  tail -50 "${HISTORY_FILE}" | while IFS='|' read -r ts evt agent details; do
    local color="${DIM}"
    case "${evt}" in
      *START*) color="${GREEN}" ;;
      *STOP*|*CRASH*) color="${RED}" ;;
      *CONFIG*|*KEY*|*TOOL*) color="${YELLOW}" ;;
      *BACKUP*|*RESTORE*) color="${BLUE}" ;;
      *INSTALL*) color="${MAGENTA}" ;;
    esac
    printf '  %s%s%s%s%s%s%s\n' "${DIM}" "${ts}" "${RST}" "${color}" "${evt}" "${RST}" "${agent}${details}"
  done
  printf '\n  %s[c] Clear history  [q] Back%s\n' "${DIM}" "${RST}"
  printf '  > '; read -r hc
  [[ "${hc}" == "c" ]] && confirm "Clear all history?" && > "${HISTORY_FILE}" && ok "History cleared"
}

# ── Notification ──────────────────────────────────────────────────────────────
notify() {
  if [[ "${ENABLE_NOTIFICATIONS}" == "true" ]] && command -v termux-notification >/dev/null 2>&1; then
    local msg="$1"
    msg="${msg:0:80}"
    termux-notification -t "${NAME}" -c "${msg}" --priority high 2>/dev/null || true
  fi
}

tts() {
  if command -v termux-tts-speak >/dev/null 2>&1; then
    termux-tts-speak "$1" 2>/dev/null || true
  fi
}

# ── Wake Lock ─────────────────────────────────────────────────────────────────
acquire_wake_lock() {
  if [[ "${ENABLE_WAKE_LOCK}" == "true" ]] && command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock 2>/dev/null || true
    info "Wake lock acquired"
  fi
}

release_wake_lock() {
  if [[ "${ENABLE_WAKE_LOCK}" == "true" ]] && command -v termux-wake-unlock >/dev/null 2>&1; then
    termux-wake-unlock 2>/dev/null || true
    info "Wake lock released"
  fi
}

# ── Network Helpers ───────────────────────────────────────────────────────────
get_ip() {
  local ip=""
  if command -v ifconfig >/dev/null 2>&1; then
    ip=$(ifconfig 2>/dev/null | grep -oE 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
  else
    ip=$(ip addr 2>/dev/null | grep -oE 'inet ([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
  fi
  echo "${ip:-${LOCAL_IP:-$(hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')}}"
}

is_port_free() {
  local port=$1
  ! ss -tlnp 2>/dev/null | grep -q ":${port} " && \
  ! lsof -i ":${port}" >/dev/null 2>&1
}

find_free_port() {
  local preferred=$1
  local port=$preferred
  local tries=0
  while ! is_port_free "${port}" && (( tries < MAX_PORT_TRIES )); do
    port=$((port + 1))
    tries=$((tries + 1))
  done
  if (( tries >= MAX_PORT_TRIES )); then
    warn "Could not find free port near ${preferred}"
    echo "${preferred}"
  else
    echo "${port}"
  fi
}

snapshot_ports() {
  ss -tlnp 2>/dev/null > "${RUN_DIR}/ports.snapshot" || true
}

# ── Config Persistence ────────────────────────────────────────────────────────
load_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
  fi
  if [[ -f "${KEYS_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${KEYS_FILE}"
  fi

  HERMES_HOST="${HERMES_HOST:-${HERMES_HOST_DEFAULT}}"
  HERMES_DASH_PORT="${HERMES_DASH_PORT:-${HERMES_DASH_PORT}}"
  HERMES_API_PORT="${HERMES_API_PORT:-${HERMES_API_PORT}}"
  CODEX_PORT="${CODEX_PORT:-${CODEX_PORT_DEFAULT}}"
  OPENCLAW_PORT="${OPENCLAW_PORT:-${OPENCLAW_PORT_DEFAULT}}"
  MODEL="${MODEL:-${MODEL_DEFAULT}}"
  PROVIDER="${PROVIDER:-${PROVIDER_DEFAULT}}"
  HERMES_THEME="${HERMES_THEME:-${HERMES_THEME_DEFAULT}}"
  ENABLE_WAKE_LOCK="${ENABLE_WAKE_LOCK:-${ENABLE_WAKE_LOCK_DEFAULT}}"
  ENABLE_NOTIFICATIONS="${ENABLE_NOTIFICATIONS:-${ENABLE_NOTIFICATIONS_DEFAULT}}"
  ENABLE_AUTO_RESTART="${ENABLE_AUTO_RESTART:-${ENABLE_AUTO_RESTART_DEFAULT}}"
  HEALTH_POLL_INTERVAL="${HEALTH_POLL_INTERVAL:-${HEALTH_POLL_INTERVAL_DEFAULT}}"
  MIGRATION_SOURCE="${MIGRATION_SOURCE:-${MIGRATION_SOURCE_DEFAULT}}"
  OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"

  # Tool category defaults
  TOOL_CAT_TERMUX="${TOOL_CAT_TERMUX:-on}"
  TOOL_CAT_SHIZUKU="${TOOL_CAT_SHIZUKU:-on}"
  TOOL_CAT_INTENT="${TOOL_CAT_INTENT:-on}"
  TOOL_CAT_DEV="${TOOL_CAT_DEV:-on}"
}

save_config() {
  mkdir -p "${CONFIG_DIR}"
  cat > "${CONFIG_FILE}" << CONFIGEOF
# ${NAME} configuration
# Generated $(date)

# Network
HERMES_HOST="${HERMES_HOST}"
HERMES_DASH_PORT="${HERMES_DASH_PORT}"
HERMES_API_PORT="${HERMES_API_PORT}"
CODEX_PORT="${CODEX_PORT}"
OPENCLAW_PORT="${OPENCLAW_PORT}"

# Model & Provider
MODEL="${MODEL}"
PROVIDER="${PROVIDER}"

# Hermes
HERMES_THEME="${HERMES_THEME}"

# Features
ENABLE_WAKE_LOCK="${ENABLE_WAKE_LOCK}"
ENABLE_NOTIFICATIONS="${ENABLE_NOTIFICATIONS}"
ENABLE_AUTO_RESTART="${ENABLE_AUTO_RESTART}"
HEALTH_POLL_INTERVAL="${HEALTH_POLL_INTERVAL}"

# Migration
MIGRATION_SOURCE="${MIGRATION_SOURCE}"

# Tool Categories
TOOL_CAT_TERMUX="${TOOL_CAT_TERMUX}"
TOOL_CAT_SHIZUKU="${TOOL_CAT_SHIZUKU}"
TOOL_CAT_INTENT="${TOOL_CAT_INTENT}"
TOOL_CAT_DEV="${TOOL_CAT_DEV}"
CONFIGEOF
}

save_keys() {
  mkdir -p "${CONFIG_DIR}"
  cat > "${KEYS_FILE}" << KEYSEOF
# ${NAME} API keys
# Generated $(date)
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
KEYSEOF
  chmod 600 "${KEYS_FILE}"
}

# ── Agent Status Helpers ──────────────────────────────────────────────────────
agent_running() {
  local pattern=$1
  pgrep -f "${pattern}" >/dev/null 2>&1
}

running_count() {
  local count=0
  agent_running "hermes.*dashboard" && count=$((count + 1))
  agent_running "hermes.*serve" && count=$((count + 1))
  agent_running "codex" && count=$((count + 1))
  agent_running "openclaw" && count=$((count + 1))
  echo "${count}"
}

agent_status() {
  local pattern=$1
  if agent_running "${pattern}"; then
    echo "${GREEN}● Running${RST}"
  else
    echo "${RED}○ Stopped${RST}"
  fi
}

agent_pid() {
  local pattern=$1
  pgrep -f "${pattern}" 2>/dev/null | head -1
}

agent_uptime() {
  local pattern=$1
  local pid
  pid=$(agent_pid "${pattern}")
  if [[ -n "${pid}" ]]; then
    ps -o etime= -p "${pid}" 2>/dev/null | tr -d ' ' || echo "unknown"
  else
    echo "-"
  fi
}

# ── Quick Connect ─────────────────────────────────────────────────────────────
copy_to_clipboard() {
  local text=$1
  if command -v termux-clipboard-set >/dev/null 2>&1; then
    termux-clipboard-set "${text}" 2>/dev/null
    if command -v termux-toast >/dev/null 2>&1; then
      termux-toast "URL copied to clipboard" 2>/dev/null || true
    fi
    ok "Copied: ${text}"
  else
    warn "termux-clipboard-set not found. Install: pkg install termux-api"
    printf '  %sURL: %s%s\n' "${BOLD}" "${text}" "${RST}"
  fi
}

open_in_browser() {
  local url=$1
  if command -v termux-open-url >/dev/null 2>&1; then
    termux-open-url "${url}" 2>/dev/null
    ok "Opened: ${url}"
  else
    warn "termux-open-url not found. Install: pkg install termux-api"
    printf '  %sURL: %s%s\n' "${BOLD}" "${url}" "${RST}"
  fi
}

quick_connect() {
  local agent=$1
  local ip
  ip=$(get_ip)
  local port=""
  local url=""

  case "${agent}" in
    dashboard) port="${HERMES_DASH_PORT}" ;;
    api)       port="${HERMES_API_PORT}" ;;
    openclaw)  port="${OPENCLAW_PORT}" ;;
    *)         return ;;
  esac

  url="http://${ip}:${port}"
  printf '\n  %s[c]opy URL  [o]pen browser  [b]ack%s\n' "${BOLD}" "${RST}"
  printf '  > '; read -r qc
  case "${qc}" in
    c|C) copy_to_clipboard "${url}" ;;
    o|O) open_in_browser "${url}" ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# TOOLS & SKILLS MENU
# ═══════════════════════════════════════════════════════════════════════════════

# Tool format: TOOL_CMD|TOOL_NAME|TOOL_ICON|TOOL_DESC|TOOL_CMD_FULL
declare -a TOOLS_TERMUX=(
  "clipboard-get|Clipboard Get|📋|Read clipboard contents|termux-clipboard-get"
  "clipboard-set|Clipboard Set|📋|Set clipboard text|termux-clipboard-set \"text\""
  "notification|Notification|🔔|Send rich notification|termux-notification -t \"Title\" -c \"Content\""
  "toast|Toast|💬|Brief on-screen message|termux-toast \"Hello world\""
  "tts-speak|Text-to-Speech|🔊|Speak text aloud|termux-tts-speak \"Hello world\""
  "battery-status|Battery|🔋|Battery status & level|termux-battery-status"
  "device-info|Device Info|📱|Model, SDK, manufacturer|termux-device-info"
  "brightness|Brightness|🔆|Set screen brightness|termux-brightness 128"
  "screenshot|Screenshot|📸|Capture screen to file|termux-screenshot"
  "camera-photo|Camera|📷|Take a photo|termux-camera-photo /sdcard/Download/photo.jpg"
  "torch|Torch|🔦|Toggle flashlight|termux-torch on"
  "microphone-record|Microphone|🎙|Record audio|termux-microphone-record -l 10"
  "media-player|Media Player|🎵|Play media file|termux-media-player play"
  "media-scan|Media Scan|📂|Scan media files|termux-media-scan"
  "wifi-connectioninfo|WiFi Info|📶|WiFi SSID, IP, signal|termux-wifi-connectioninfo"
  "wifi-scaninfo|WiFi Scan|🔍|Scan available networks|termux-wifi-scaninfo"
  "contact-list|Contacts|👥|List contacts|termux-contact-list"
  "sms-list|SMS List|💬|List SMS messages|termux-sms-list"
  "sms-send|SMS Send|📤|Send SMS message|termux-sms-send -n NUMBER -m \"text\""
  "telephony-deviceinfo|Telephony|📞|Phone network info|termux-telephony-deviceinfo"
  "telephony-cellinfo|Cell Info|📡|Cell tower info|termux-telephony-cellinfo"
  "location|Location|📍|Get GPS coordinates|termux-location"
  "calendar-list|Calendar List|📅|List calendar events|termux-calendar-list"
  "calendar-insert|Calendar Insert|📅|Insert calendar event|termux-calendar-insert -t \"Title\" -d \"Desc\""
  "vibrate|Vibrate|📳|Haptic feedback|termux-vibrate -d 300"
  "fingerprint|Fingerprint|🔐|Fingerprint scan|termux-fingerprint"
  "volume|Volume|🔉|Get/set media volume|termux-volume media 8"
  "setup-storage|Setup Storage|💾|Grant storage access|termux-setup-storage"
  "storages|Storages|📁|List storage paths|termux-storages"
  "download|Download|⬇️ |Download a URL|termux-download URL"
  "wake-lock|Wake Lock|🔋|Acquire wake lock|termux-wake-lock"
  "wake-unlock|Wake Unlock|🔋|Release wake lock|termux-wake-unlock"
  "open|Open File|📂|Open file with app|termux-open /path/to/file"
)

declare -a TOOLS_SHIZUKU=(
  "pm|Package Manager|📦|Install/uninstall/list apps|shizuku pm list packages"
  "am|App Manager|🎮|Start/stop apps & services|shizuku am start -n com.example/.MainActivity"
  "settings|System Settings|⚙️ |Read/write Android settings|shizuku settings get global airplane_mode_on"
  "dumpsys|Diagnostics|📊|System diagnostics|shizuku dumpsys battery"
  "cmd|System Cmd|🖥|Run system commands|shizuku cmd package list packages"
  "input|UI Input|👆|Tap, swipe, type, keys|shizuku input tap 500 800"
  "uiautomator|UI Dump|🔎|Dump UI hierarchy|shizuku uiautomator dump /sdcard/ui.xml"
  "screencap|Screen Capture|📸|Screenshot via shell|shizuku screencap -p /sdcard/screen.png"
  "content|Content Query|📋|Query contacts/SMS|shizuku content query --uri content://com.android.contacts/contacts"
  "ls|List Files|📂|List directory contents|shizuku ls /sdcard/Download/"
  "cat|Read File|📄|Read file contents|shizuku cat /sdcard/file.txt"
  "cp|Copy File|📋|Copy files|shizuku cp /src/file /dst/file"
  "appops|Permissions|🔑|Manage app permissions|shizuku appops set com.example MANAGE_EXTERNAL_STORAGE allow"
  "sh|Shell|💻|Arbitrary shell commands|shizuku sh -c \"whoami\""
)

declare -a TOOLS_INTENT=(
  "intent|Intent Bridge|⚡|Launch apps, services, broadcasts|intent '{\"start\":\"activity\",\"action\":\"android.intent.action.VIEW\",\"data\":\"https://example.com\"}'"
)

declare -a TOOLS_DEV=(
  "system-health|System Health|📈|CPU, memory, disk monitor|system-health"
  "log-tools|Log Tools|📋|Tail, grep, analyze logs|log-tools"
  "git-intel|Git Intel|📊|Analyze git history|git-intel"
  "file-finder|File Finder|🔍|Locate files by name/type|file-finder"
  "dep-scan|Dependency Scan|🔧|Check outdated/vuln deps|dependency-scan"
  "security-review|Security Review|🔒|Best-practice code audit|security-best-practices"
  "json-query|JSON Query|🔎|Extract & transform JSON|json-query"
  "cron-helper|Cron Helper|⏰|Schedule recurring tasks|cron-helper"
)

tool_is_available() {
  local cmd=$1
  case "${cmd}" in
    clipboard-get|clipboard-set|notification|toast|tts-speak|battery-status|device-info|brightness|screenshot|camera-photo|torch|microphone-record|media-player|media-scan|wifi-connectioninfo|wifi-scaninfo|contact-list|sms-list|sms-send|telephony-deviceinfo|telephony-cellinfo|location|calendar-list|calendar-insert|vibrate|fingerprint|volume|setup-storage|storages|download|wake-lock|wake-unlock|open)
      command -v "termux-${cmd}" >/dev/null 2>&1 ;;
    pm|am|settings|dumpsys|cmd|input|uiautomator|screencap|content|ls|cat|cp|appops|sh)
      command -v shizuku >/dev/null 2>&1 ;;
    intent)
      command -v intent >/dev/null 2>&1 ;;
    system-health|log-tools|git-intel|file-finder|dep-scan|security-review|json-query|cron-helper)
      true ;; # Dev tools are always "available" as skill references
    *)
      false ;;
  esac
}

tool_category_status() {
  local cat=$1
  local var="TOOL_CAT_${cat}"
  echo "${!var:-on}"
}

toggle_tool_category() {
  local cat=$1
  local var="TOOL_CAT_${cat}"
  if [[ "${!var}" == "on" ]]; then
    eval "${var}=\"off\""
  else
    eval "${var}=\"on\""
  fi
  save_config
}

show_tools_menu() {
  while true; do
    ui_header "TOOLS & SKILLS"
    printf '  %s56 tools available • Press number to view command%s\n\n' "${DIM}" "${RST}"

    local tc
    tc=$(tool_category_status "TERMUX")
    local ts
    ts=$(tool_category_status "SHIZUKU")
    local ti
    ti=$(tool_category_status "INTENT")
    local td
    td=$(tool_category_status "DEV")

    # Termux API section
    printf '  %s▸ 📱 TERMUX API [%s]%s  %s[a]%s toggle\n' "${BOLD}" "${tc}" "${RST}" "${DIM}" "${RST}"
    if [[ "${tc}" == "on" ]]; then
      local idx=1
      for tool_entry in "${TOOLS_TERMUX[@]}"; do
        IFS='|' read -r cmd name icon desc full_cmd <<< "${tool_entry}"
        local avail="✓"
        local avail_color="${GREEN}"
        if ! tool_is_available "${cmd}"; then
          avail="✗"
          avail_color="${RED}"
        fi
        printf '  %s%2d)%s %s %-20s %s%s%s %s%s%s\n' \
          "${BOLD}${CYAN}" "${idx}" "${RST}" "${icon}" "${name}" "${avail_color}" "${avail}" "${RST}" "${DIM}" "${desc}" "${RST}"
        idx=$((idx + 1))
      done
    else
      printf '  %s  (category disabled)%s\n' "${DIM}" "${RST}"
    fi

    printf '\n'

    # Shizuku section
    printf '  %s▸ 🔶 SHIZUKU [%s]%s  %s[b]%s toggle\n' "${BOLD}" "${ts}" "${RST}" "${DIM}" "${RST}"
    if [[ "${ts}" == "on" ]]; then
      local idx=1
      for tool_entry in "${TOOLS_SHIZUKU[@]}"; do
        IFS='|' read -r cmd name icon desc full_cmd <<< "${tool_entry}"
        local avail="✓"
        local avail_color="${GREEN}"
        if ! tool_is_available "${cmd}"; then
          avail="✗"
          avail_color="${RED}"
        fi
        printf '  %s%2d)%s %s %-20s %s%s%s %s%s%s\n' \
          "${BOLD}${CYAN}" "$((idx + 33))" "${RST}" "${icon}" "${name}" "${avail_color}" "${avail}" "${RST}" "${DIM}" "${desc}" "${RST}"
        idx=$((idx + 1))
      done
    else
      printf '  %s  (category disabled)%s\n' "${DIM}" "${RST}"
    fi

    printf '\n'

    # Intent section
    printf '  %s▸ ⚡ INTENT BRIDGE [%s]%s  %s[c]%s toggle\n' "${BOLD}" "${ti}" "${RST}" "${DIM}" "${RST}"
    if [[ "${ti}" == "on" ]]; then
      printf '  %s%2d)%s ⚡ %-20s %s✓%s %s%s%s\n' \
        "${BOLD}${CYAN}" "48" "${RST}" "Intent Bridge" "${GREEN}" "${RST}" "${DIM}" "Launch apps, services, broadcasts" "${RST}"
    else
      printf '  %s  (category disabled)%s\n' "${DIM}" "${RST}"
    fi

    printf '\n'

    # Dev tools section
    printf '  %s▸ 🛠 DEV TOOLS [%s]%s  %s[d]%s toggle\n' "${BOLD}" "${td}" "${RST}" "${DIM}" "${RST}"
    if [[ "${td}" == "on" ]]; then
      local idx=1
      for tool_entry in "${TOOLS_DEV[@]}"; do
        IFS='|' read -r cmd name icon desc full_cmd <<< "${tool_entry}"
        printf '  %s%2d)%s %s %-20s %s%s%s\n' \
          "${BOLD}${CYAN}" "$((idx + 48))" "${RST}" "${icon}" "${name}" "${DIM}" "${desc}" "${RST}"
        idx=$((idx + 1))
      done
    else
      printf '  %s  (category disabled)%s\n' "${DIM}" "${RST}"
    fi

    printf '\n  %s[q] Back to menu%s\n' "${DIM}" "${RST}"
    footer

    printf '  > '; read -r choice

    case "${choice}" in
      a|A) toggle_tool_category "TERMUX" ;;
      b|B) toggle_tool_category "SHIZUKU" ;;
      c|C) toggle_tool_category "INTENT" ;;
      d|D) toggle_tool_category "DEV" ;;
      q|Q) return ;;
      [0-9]|[0-9][0-9])
        show_tool_detail "${choice}" ;;
      *) ;;
    esac
  done
}

show_tool_detail() {
  local num=$1
  local tool_entry=""
  local category=""

  if (( num >= 1 && num <= 33 )); then
    tool_entry="${TOOLS_TERMUX[$((num - 1))]}"
    category="TERMUX"
  elif (( num >= 34 && num <= 47 )); then
    tool_entry="${TOOLS_SHIZUKU[$((num - 34))]}"
    category="SHIZUKU"
  elif (( num == 48 )); then
    tool_entry="${TOOLS_INTENT[0]}"
    category="INTENT"
  elif (( num >= 49 && num <= 56 )); then
    tool_entry="${TOOLS_DEV[$((num - 49))]}"
    category="DEV"
  else
    return
  fi

  IFS='|' read -r cmd name icon desc full_cmd <<< "${tool_entry}"

  ui_header "TOOL: ${name}"
  printf '  %sCategory:%s %s\n' "${BOLD}" "${RST}" "${category}"
  printf '  %sDescription:%s %s\n\n' "${BOLD}" "${RST}" "${desc}"

  local avail="✓ installed"
  local avail_color="${GREEN}"
  if ! tool_is_available "${cmd}"; then
    avail="✗ not installed"
    avail_color="${RED}"
  fi
  printf '  %sStatus:%s %s%s%s\n\n' "${BOLD}" "${RST}" "${avail_color}" "${avail}" "${RST}"

  printf '  %sCommand:%s\n' "${BOLD}" "${RST}"
  printf '    %s%s%s\n\n' "${DIM}" "${full_cmd}" "${RST}"

  printf '  %s[a] Copy command  [b] Back%s\n' "${BOLD}" "${RST}"
  printf '  > '; read -r td
  case "${td}" in
    a|A) copy_to_clipboard "${full_cmd}" ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# STOP AGENT
# ═══════════════════════════════════════════════════════════════════════════════

stop_agent() {
  local name=$1
  local pattern=$2
  local pid
  pid=$(agent_pid "${pattern}")
  if [[ -n "${pid}" ]]; then
    info "Stopping ${name} (PID ${pid})..."
    kill "${pid}" 2>/dev/null || true
    local waited=0
    while kill -0 "${pid}" 2>/dev/null && (( waited < 5 )); do
      sleep 1
      waited=$((waited + 1))
    done
    if kill -0 "${pid}" 2>/dev/null; then
      warn "Force killing ${name} (PID ${pid})"
      kill -9 "${pid}" 2>/dev/null || true
    fi
    ok "${name} stopped"
    log_event "STOP" "${name}" "PID ${pid}"
  else
    warn "${name} is not running"
  fi
}

stop_all_agents() {
  local agents=("hermes-dashboard:hermes.*dashboard" "hermes-serve:hermes.*serve" "codex:codex" "openclaw:openclaw")
  for entry in "${agents[@]}"; do
    local name="${entry%%:*}"
    local pattern="${entry##*:}"
    agent_running "${pattern}" && stop_agent "${name}" "${pattern}"
  done
}

# ═══════════════════════════════════════════════════════════════════════════════
# PORT RESOLUTION
# ═══════════════════════════════════════════════════════════════════════════════

resolve_ports() {
  snapshot_ports
  info "Resolving available ports..."
  local old_dash="${HERMES_DASH_PORT}"
  local old_api="${HERMES_API_PORT}"
  local old_codex="${CODEX_PORT}"
  local old_openclaw="${OPENCLAW_PORT}"
  HERMES_DASH_PORT=$(find_free_port "${HERMES_DASH_PORT}")
  HERMES_API_PORT=$(find_free_port "${HERMES_API_PORT}")
  CODEX_PORT=$(find_free_port "${CODEX_PORT}")
  OPENCLAW_PORT=$(find_free_port "${OPENCLAW_PORT}")
  [[ "${old_dash}" != "${HERMES_DASH_PORT}" ]] && warn "Hermes Dashboard: ${old_dash} busy → ${HERMES_DASH_PORT}"
  [[ "${old_api}" != "${HERMES_API_PORT}" ]] && warn "Hermes API: ${old_api} busy → ${HERMES_API_PORT}"
  [[ "${old_codex}" != "${CODEX_PORT}" ]] && warn "Codex: ${old_codex} busy → ${CODEX_PORT}"
  [[ "${old_openclaw}" != "${OPENCLAW_PORT}" ]] && warn "OpenClaw: ${old_openclaw} busy → ${OPENCLAW_PORT}"
  save_config
}

# ═══════════════════════════════════════════════════════════════════════════════
# INSTALLATION SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

install_base_deps() {
  info "Installing base dependencies..."
  pkg update -y 2>/dev/null || apt update -y 2>/dev/null || true
  for pkg in nodejs python git curl; do
    if ! command -v "${pkg}" >/dev/null 2>&1 && ! pkg list-installed 2>/dev/null | grep -q "^${pkg}/"; then
      info "  Installing ${pkg}..."
      pkg install -y "${pkg}" 2>/dev/null || apt install -y "${pkg}" 2>/dev/null || warn "Failed to install ${pkg}"
    else
      info "  ${pkg}: already installed"
    fi
  done
}

install_hermes() {
  info "Installing Hermes..."
  if command -v hermes >/dev/null 2>&1; then
    info "  Hermes already installed: $(hermes --version 2>/dev/null | head -1 || echo 'unknown version')"
    return 0
  fi
  pip install hermes-agent 2>/dev/null || pip3 install hermes-agent 2>/dev/null || {
    error "Failed to install Hermes via pip"
    return 1
  }
  if command -v hermes >/dev/null 2>&1; then
    ok "Hermes installed: $(hermes --version 2>/dev/null | head -1 || echo 'installed')"
    log_event "INSTALL" "hermes" "pip install"
    return 0
  else
    error "Hermes installed but not found in PATH"
    return 1
  fi
}

configure_hermes() {
  info "Configuring Hermes..."
  mkdir -p "${HERMES_HOME}"
  local env_file="${HERMES_HOME}/.env"
  if [[ -n "${OPENROUTER_API_KEY}" ]]; then
    cat > "${env_file}" << HERMESEOF
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
HERMES_MODEL=${MODEL}
HERMES_PROVIDER=${PROVIDER}
HERMES_THEME=${HERMES_THEME}
HERMESEOF
    ok "Hermes configured"
  else
    cat > "${env_file}" << HERMESEOF
HERMES_MODEL=${MODEL}
HERMES_PROVIDER=${PROVIDER}
HERMES_THEME=${HERMES_THEME}
HERMESEOF
    warn "Hermes configured (no API key — add via Settings)"
  fi
}

install_codex() {
  info "Installing Codex CLI..."
  if command -v codex >/dev/null 2>&1; then
    info "  Codex already installed"
    return 0
  fi
  npm install -g @openai/codex 2>/dev/null || { error "Failed to install Codex"; return 1; }
  if command -v codex >/dev/null 2>&1; then
    ok "Codex installed"
    log_event "INSTALL" "codex" "npm install"
    return 0
  fi
  return 1
}

install_openclaw() {
  info "Installing OpenClaw Gateway..."
  if command -v openclaw >/dev/null 2>&1; then
    info "  OpenClaw already installed"
    return 0
  fi
  npm install -g openclaw 2>/dev/null || pip install openclaw 2>/dev/null || pip3 install openclaw 2>/dev/null || {
    error "Failed to install OpenClaw"
    return 1
  }
  if command -v openclaw >/dev/null 2>&1; then
    ok "OpenClaw installed"
    log_event "INSTALL" "openclaw" "npm/pip install"
    return 0
  fi
  return 1
}

setup_storage() {
  if command -v termux-setup-storage >/dev/null 2>&1; then
    if [[ ! -d "/sdcard/Download" ]]; then
      info "Requesting storage access..."
      termux-setup-storage 2>/dev/null || warn "Storage access denied"
    else
      info "Storage access already granted"
    fi
  fi
}

verify_install() {
  local tool=$1
  local version_cmd=$2
  if command -v "${tool}" >/dev/null 2>&1; then
    local ver
    ver=$(${version_cmd} 2>/dev/null | head -1 || echo "installed")
    printf '    %s✓%s  %-12s %s%s%s\n' "${GREEN}" "${RST}" "${tool}" "${DIM}" "${ver}" "${RST}"
    return 0
  else
    printf '    %s✗%s  %-12s %snot installed%s\n' "${RED}" "${RST}" "${tool}" "${DIM}" "${RST}"
    return 1
  fi
}

install_menu() {
  ui_header "INSTALL AGENTS"
  printf '  %sCurrent Status:%s\n\n' "${BOLD}" "${RST}"
  verify_install "hermes" "hermes --version" || true
  verify_install "codex" "codex --version" || true
  verify_install "openclaw" "openclaw --version" || true
  separator
  printf '  %s1)%s  Install All\n' "${BOLD}${CYAN}" "${RST}"
  printf '  %s2)%s  Install Base Dependencies Only\n' "${BOLD}${CYAN}" "${RST}"
  printf '  %s3)%s  Install Hermes\n' "${BOLD}${CYAN}" "${RST}"
  printf '  %s4)%s  Install Codex CLI\n' "${BOLD}${CYAN}" "${RST}"
  printf '  %s5)%s  Install OpenClaw Gateway\n' "${BOLD}${CYAN}" "${RST}"
  printf '  %s6)%s  Setup Storage Access\n' "${BOLD}${CYAN}" "${RST}"
  printf '  %s0)%s  Back\n\n' "${BOLD}${CYAN}" "${RST}"
  printf '  > '; read -r choice
  case "${choice}" in
    1)
      acquire_wake_lock
      setup_storage
      install_base_deps
      install_hermes && configure_hermes
      install_codex
      install_openclaw
      release_wake_lock
      ok "Installation complete"
      notify "Installation complete"
      ;;
    2) install_base_deps ;;
    3) install_hermes && configure_hermes ;;
    4) install_codex ;;
    5) install_openclaw ;;
    6) setup_storage ;;
    0) return ;;
    *) warn "Invalid choice" ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# LAUNCH SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

ensure_key_env() {
  export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
  if [[ -n "${OPENROUTER_API_KEY}" ]]; then
    export OPENAI_API_KEY="${OPENROUTER_API_KEY}"
  fi
}

launch_background() {
  local name=$1
  shift
  local cmd="$*"
  info "Launching ${name}..."
  ensure_key_env
  mkdir -p "${RUN_DIR}"
  nohup bash -c "
    export HOME='${HOME}'
    export PATH='${PREFIX}/bin:\${PATH}'
    export OPENROUTER_API_KEY='${OPENROUTER_API_KEY:-}'
    export OPENAI_API_KEY='${OPENROUTER_API_KEY:-}'
    ${cmd}
  " > "${RUN_DIR}/${name}.log" 2>&1 &
  local pid=$!
  echo "${pid}" > "${RUN_DIR}/${name}.pid"
  disown "${pid}" 2>/dev/null || true
  sleep 1
  if kill -0 "${pid}" 2>/dev/null; then
    ok "${name} launched (PID ${pid})"
    log_event "START" "${name}" "PID ${pid}"
    return 0
  else
    error "${name} failed to start. Check logs: ${RUN_DIR}/${name}.log"
    log_event "CRASH" "${name}" "Failed to start"
    tts "Agent failed to start"
    return 1
  fi
}

launch_hermes_dashboard() {
  if ! command -v hermes >/dev/null 2>&1; then
    error "Hermes is not installed. Run Install first."; pause; return
  fi
  if agent_running "hermes.*dashboard"; then
    warn "Hermes Dashboard is already running"; pause; return
  fi
  HERMES_DASH_PORT=$(find_free_port "${HERMES_DASH_PORT}")
  launch_background "hermes-dashboard" \
    "hermes dashboard --host ${HERMES_HOST} --port ${HERMES_DASH_PORT} --no-open"
  save_config
  local ip; ip=$(get_ip)
  ok "Hermes Dashboard: ${BOLD}http://${ip}:${HERMES_DASH_PORT}${RST}"
  notify "Hermes Dashboard running on port ${HERMES_DASH_PORT}"
}

launch_hermes_serve() {
  if ! command -v hermes >/dev/null 2>&1; then
    error "Hermes is not installed. Run Install first."; pause; return
  fi
  if agent_running "hermes.*serve"; then
    warn "Hermes API Server is already running"; pause; return
  fi
  HERMES_API_PORT=$(find_free_port "${HERMES_API_PORT}")
  launch_background "hermes-serve" \
    "hermes chat --host ${HERMES_HOST} --port ${HERMES_API_PORT}"
  save_config
  local ip; ip=$(get_ip)
  ok "Hermes API Server: ${BOLD}http://${ip}:${HERMES_API_PORT}${RST}"
  notify "Hermes API running on port ${HERMES_API_PORT}"
}

launch_hermes_chat() {
  if ! command -v hermes >/dev/null 2>&1; then
    error "Hermes is not installed. Run Install first."; pause; return
  fi
  info "Launching Hermes Chat TUI (foreground)..."
  ensure_key_env
  hermes chat
}

launch_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    error "Codex CLI is not installed. Run Install first."; pause; return
  fi
  if agent_running "codex"; then
    warn "Codex is already running"; pause; return
  fi
  info "Launching Codex CLI (foreground)..."
  ensure_key_env
  codex
}

launch_openclaw() {
  if ! command -v openclaw >/dev/null 2>&1; then
    error "OpenClaw is not installed. Run Install first."; pause; return
  fi
  if agent_running "openclaw"; then
    warn "OpenClaw Gateway is already running"; pause; return
  fi
  OPENCLAW_PORT=$(find_free_port "${OPENCLAW_PORT}")
  launch_background "openclaw" \
    "openclaw gateway --host ${HERMES_HOST} --port ${OPENCLAW_PORT}"
  save_config
  local ip; ip=$(get_ip)
  ok "OpenClaw Gateway: ${BOLD}http://${ip}:${OPENCLAW_PORT}${RST}"
  notify "OpenClaw Gateway running on port ${OPENCLAW_PORT}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# LAUNCH MENU
# ═══════════════════════════════════════════════════════════════════════════════

launch_menu() {
  while true; do
    ui_header "LAUNCH AGENTS"
    status_bar

    local ip; ip=$(get_ip)
    local dash_status api_status codex_status openclaw_status
    dash_status=$(agent_status "hermes.*dashboard")
    api_status=$(agent_status "hermes.*serve")
    codex_status=$(agent_status "codex")
    openclaw_status=$(agent_status "openclaw")

    # ── Agents panel ──────────────────────────────────────────────
    printf '  %s┌──────────────────────────────────────────────┐%s\n' "${DIM}" "${RST}"
    printf '  %s│%s  %s◆ AGENTS%s                                   %s│%s\n' "${DIM}" "${RST}" "${BOLD}" "${RST}" "${DIM}" "${RST}"

    printf '  %s│%b  1)%b  Hermes Dashboard   %s         %s│%s\n' \
      "${DIM}" "${RST}" "${BOLD}${CYAN}" "${RST}" "${dash_status}" "${DIM}"
    if agent_running "hermes.*dashboard"; then
      printf '  %s│%b       %shttp://%s:%s%s%s%s                       %s│%s\n' \
        "${DIM}" "${RST}" "${DIM}" "${ip}" "${HERMES_DASH_PORT}" "${RST}" "${GREEN}" "${RST}" "${DIM}" "${RST}"
    else
      printf '  %s│%b       %sPort: %s%s%s                                   %s│%s\n' \
        "${DIM}" "${RST}" "${DIM}" "${HERMES_DASH_PORT}" "${RST}" "${DIM}" "${RST}" "${DIM}"
    fi

    printf '  %s│%b  2)%b  Hermes API Server  %s         %s│%s\n' \
      "${DIM}" "${RST}" "${BOLD}${CYAN}" "${RST}" "${api_status}" "${DIM}"
    if agent_running "hermes.*serve"; then
      printf '  %s│%b       %shttp://%s:%s%s%s%s                       %s│%s\n' \
        "${DIM}" "${RST}" "${DIM}" "${ip}" "${HERMES_API_PORT}" "${RST}" "${GREEN}" "${RST}" "${DIM}" "${RST}"
    else
      printf '  %s│%b       %sPort: %s%s%s                                   %s│%s\n' \
        "${DIM}" "${RST}" "${DIM}" "${HERMES_API_PORT}" "${RST}" "${DIM}" "${RST}" "${DIM}"
    fi

    printf '  %s│%b  3)%b  Hermes Chat TUI     %s                       %s│%s\n' \
      "${DIM}" "${RST}" "${BOLD}${CYAN}" "${RST}" "${DIM}" "${RST}"

    printf '  %s├──────────────────────────────────────────────┤%s\n' "${DIM}" "${RST}"

    printf '  %s│%s  %s◆ AGENTS (cont.)%s                          %s│%s\n' "${DIM}" "${RST}" "${BOLD}" "${RST}" "${DIM}" "${RST}"
    printf '  %s│%b  4)%b  Codex CLI            %s         %s│%s\n' \
      "${DIM}" "${RST}" "${BOLD}${CYAN}" "${RST}" "${codex_status}" "${DIM}"

    printf '  %s├──────────────────────────────────────────────┤%s\n' "${DIM}" "${RST}"

    printf '  %s│%b  5)%b  OpenClaw Gateway     %s         %s│%s\n' \
      "${DIM}" "${RST}" "${BOLD}${CYAN}" "${RST}" "${openclaw_status}" "${DIM}"
    if agent_running "openclaw"; then
      printf '  %s│%b       %shttp://%s:%s%s%s%s                       %s│%s\n' \
        "${DIM}" "${RST}" "${DIM}" "${ip}" "${OPENCLAW_PORT}" "${RST}" "${GREEN}" "${RST}" "${DIM}" "${RST}"
    else
      printf '  %s│%b       %sPort: %s%s%s                                   %s│%s\n' \
        "${DIM}" "${RST}" "${DIM}" "${OPENCLAW_PORT}" "${RST}" "${DIM}" "${RST}" "${DIM}"
    fi

    printf '  %s├──────────────────────────────────────────────┤%s\n' "${DIM}" "${RST}"
    printf '  %s│%s  %s◆ MANAGEMENT%s                              %s│%s\n' "${DIM}" "${RST}" "${BOLD}" "${RST}" "${DIM}" "${RST}"
    printf '  %s│%b  6)%b  Stop Agent     %s 9)%b Health Monitor%s  %s│%s\n' \
      "${DIM}" "${RST}" "${BOLD}${CYAN}" "${RST}" "${CYAN}" "${RST}" "${DIM}" "${RST}"
    printf '  %s│%b  7)%b  Migration      %s10)%b Session History%s %s│%s\n' \
      "${DIM}" "${RST}" "${BOLD}${CYAN}" "${RST}" "${CYAN}" "${RST}" "${DIM}" "${RST}"
    printf '  %s│%b  8)%b  Diagnostics    %s11)%b Backup / Restore%s %s│%s\n' \
      "${DIM}" "${RST}" "${BOLD}${CYAN}" "${RST}" "${CYAN}" "${RST}" "${DIM}" "${RST}"

    printf '  %s├──────────────────────────────────────────────┤%s\n' "${DIM}" "${RST}"
    printf '  %s│%s  %s◆ TOOLS & SKILLS%s                          %s│%s\n' "${DIM}" "${RST}" "${BOLD}" "${RST}" "${DIM}" "${RST}"
    printf '  %s│%b 12)%b  Browse All Tools %s(56)%s                  %s│%s\n' \
      "${DIM}" "${RST}" "${BOLD}${CYAN}" "${RST}" "${DIM}" "${RST}" "${DIM}" "${RST}"
    printf '  %s│%b 13)%b  Settings                               %s│%s\n' \
      "${DIM}" "${RST}" "${BOLD}${CYAN}" "${RST}" "${DIM}" "${RST}"
    printf '  %s└──────────────────────────────────────────────┘%s\n' "${DIM}" "${RST}"

    printf '\n  %s▸ q:%s Quit  %s▸ 1-13:%s Select\n' "${DIM}" "${RST}" "${DIM}" "${RST}"
    footer

    printf '  > '; read -r choice

    case "${choice}" in
      1)
        launch_hermes_dashboard
        quick_connect "dashboard"
        ;;
      2)
        launch_hermes_serve
        quick_connect "api"
        ;;
      3) launch_hermes_chat ;;
      4) launch_codex ;;
      5)
        launch_openclaw
        quick_connect "openclaw"
        ;;
      6)
        ui_header "STOP AGENT"
        printf '  %sRunning agents:%s\n\n' "${BOLD}" "${RST}"
        local has_any=false
        agent_running "hermes.*dashboard" && { printf '    1) Hermes Dashboard (PID %s, uptime %s)\n' "$(agent_pid 'hermes.*dashboard')" "$(agent_uptime 'hermes.*dashboard')"; has_any=true; }
        agent_running "hermes.*serve" && { printf '    2) Hermes API Server (PID %s, uptime %s)\n' "$(agent_pid 'hermes.*serve')" "$(agent_uptime 'hermes.*serve')"; has_any=true; }
        agent_running "openclaw" && { printf '    3) OpenClaw Gateway (PID %s, uptime %s)\n' "$(agent_pid 'openclaw')" "$(agent_uptime 'openclaw')"; has_any=true; }
        agent_running "codex" && { printf '    4) Codex CLI (PID %s, uptime %s)\n' "$(agent_pid 'codex')" "$(agent_uptime 'codex')"; has_any=true; }
        if [[ "${has_any}" == "false" ]]; then
          warn "No agents currently running"
          pause
          continue
        fi
        printf '    0) Back\n\n'
        printf '  > '; read -r sc
        case "${sc}" in
          1) stop_agent "Hermes Dashboard" "hermes.*dashboard" ;;
          2) stop_agent "Hermes API Server" "hermes.*serve" ;;
          3) stop_agent "OpenClaw Gateway" "openclaw" ;;
          4) stop_agent "Codex CLI" "codex" ;;
          *) ;;
        esac
        pause
        ;;
      7) run_migration ;;
      8) diagnostics ;;
      9) health_monitor ;;
      10) show_history ;;
      11) backup_restore_menu ;;
      12) show_tools_menu ;;
      13) settings ;;
      q|Q) exit 0 ;;
      *) ;;
    esac
  done
}

# ═══════════════════════════════════════════════════════════════════════════════
# HEALTH MONITOR
# ═══════════════════════════════════════════════════════════════════════════════

health_monitor() {
  local prev_running=("")

  while true; do
    ui_header "HEALTH MONITOR"
    printf '  %sPolling every %ss • Press q to quit%s\n\n' "${DIM}" "${HEALTH_POLL_INTERVAL}" "${RST}"

    printf '  %s┌──────────────────────────────────────────────┐%s\n' "${DIM}" "${RST}"

    local agents=("hermes-dashboard:hermes.*dashboard" "hermes-api:hermes.*serve" "codex:codex" "openclaw:openclaw")
    local any_running=false

    for entry in "${agents[@]}"; do
      local name="${entry%%:*}"
      local pattern="${entry##*:}"
      local display_name="${name}"

      if agent_running "${pattern}"; then
        any_running=true
        local pid uptime_val
        pid=$(agent_pid "${pattern}")
        uptime_val=$(agent_uptime "${pattern}")
        printf '  %s│%s  %s♥ %s%s%s                     %s│%s\n' \
          "${DIM}" "${RST}" "${GREEN}" "${BOLD}" "${display_name}" "${RST}" "${GREEN}" "${RST}" "${DIM}"
        printf '  %s│%s     PID: %s  Uptime: %s                      %s│%s\n' \
          "${DIM}" "${RST}" "${pid}" "${uptime_val}" "${GREEN}" "${RST}" "${DIM}"
        printf '  %s│%s     %s♥ heartbeat OK  Last check: %ss ago%s    %s│%s\n' \
          "${DIM}" "${RST}" "${GREEN}" "${RST}" "${HEALTH_POLL_INTERVAL}" "${DIM}" "${RST}" "${DIM}"
        printf '  %s├──────────────────────────────────────────────┤%s\n' "${DIM}" "${RST}"
      fi
    done

    # Show crashed agents (were running before but not now)
    for entry in "${agents[@]}"; do
      local name="${entry%%:*}"
      local pattern="${entry##*:}"
      local was_running=false
      for prev in "${prev_running[@]}"; do
        [[ "${prev}" == "${pattern}" ]] && was_running=true
      done
      if [[ "${was_running}" == "true" ]] && ! agent_running "${pattern}"; then
        printf '  %s│%s  %s✖ %s%s%s %s(CRASHED)%s               %s│%s\n' \
          "${DIM}" "${RST}" "${RED}" "${BOLD}" "${name}" "${RST}" "${RED}" "${RST}" "${RED}" "${DIM}"
        local crash_time
        crash_time=$(date +%H:%M:%S)
        printf '  %s│%s     %s✖ Process died at %s%s             %s│%s\n' \
          "${DIM}" "${RST}" "${RED}" "${crash_time}" "${RST}" "${RED}" "${DIM}"
        notify "${name} crashed!"
        tts "Warning: ${name} crashed"
        log_event "CRASH" "${name}" "Process died"
        if [[ "${ENABLE_AUTO_RESTART}" == "true" ]]; then
          info "Auto-restarting ${name}..."
          case "${pattern}" in
            "hermes.*dashboard") launch_hermes_dashboard ;;
            "hermes.*serve") launch_hermes_serve ;;
            "codex") launch_codex ;;
            "openclaw") launch_openclaw ;;
          esac
          log_event "START" "${name}" "Auto-restart after crash"
        fi
        printf '  %s├──────────────────────────────────────────────┤%s\n' "${DIM}" "${RST}"
      fi
    done

    if [[ "${any_running}" == "false" ]]; then
      printf '  %s│%s  %sNo agents running%s                            %s│%s\n' \
        "${DIM}" "${RST}" "${DIM}" "${RST}" "${DIM}" "${RST}"
      printf '  %s└──────────────────────────────────────────────┘%s\n' "${DIM}" "${RST}"
      printf '\n  %sStart an agent from the launch menu first.%s\n\n' "${DIM}" "${RST}"
      pause
      return
    fi

    printf '  %s└──────────────────────────────────────────────┘%s\n' "${DIM}" "${RST}"

    # Update prev_running for next iteration
    prev_running=()
    for entry in "${agents[@]}"; do
      local pattern="${entry##*:}"
      agent_running "${pattern}" && prev_running+=("${pattern}")
    done

    printf '\n  %sAuto-restart: %s%s%s  %s[a]%s toggle  %sq:%s quit\n' \
      "${DIM}" "${BOLD}" "${ENABLE_AUTO_RESTART}" "${RST}" "${BOLD}" "${RST}" "${DIM}" "${RST}"

    # Non-blocking read with timeout
    local choice=""
    read -t "${HEALTH_POLL_INTERVAL}" -r choice 2>/dev/null || true
    case "${choice}" in
      q|Q) return ;;
      a|A)
        if [[ "${ENABLE_AUTO_RESTART}" == "true" ]]; then
          ENABLE_AUTO_RESTART="false"
        else
          ENABLE_AUTO_RESTART="true"
        fi
        save_config
        log_event "CONFIG_CHANGE" "auto-restart" "Set to ${ENABLE_AUTO_RESTART}"
        ;;
    esac
  done
}

# ═══════════════════════════════════════════════════════════════════════════════
# BACKUP / RESTORE
# ═══════════════════════════════════════════════════════════════════════════════

backup_restore_menu() {
  while true; do
    ui_header "BACKUP / RESTORE"
    printf '  %sFollows standard migration structure%s\n\n' "${DIM}" "${RST}"

    printf '  1)  💾 Backup All Agents\n'
    printf '      %s→ Creates termux-agents-hub-backup-*.tar.gz%s\n' "${DIM}" "${RST}"
    printf '      %s→ Destination: /sdcard/Download/termux-agents-hub-backups/%s\n' "${DIM}" "${RST}"
    printf '\n'
    printf '  2)  📂 Available Backups\n'

    # List existing backups
    local backup_path="${BACKUP_DIR}"
    if [[ ! -d "${backup_path}" ]]; then
      backup_path="${BACKUP_FALLBACK}"
    fi
    if [[ -d "${backup_path}" ]]; then
      local count=0
      for f in "${backup_path}"/termux-agents-hub-backup-*.tar.gz; do
        [[ -f "${f}" ]] && count=$((count + 1))
      done
      printf '      %s→ %s backup(s) found%s\n' "${DIM}" "${count}" "${RST}"
    else
      printf '      %s→ No backups found%s\n' "${DIM}" "${RST}"
    fi

    printf '\n'
    printf '  3)  ↩️  Restore from Backup\n'
    printf '      %s→ Select backup → validate → restore → hermes doctor%s\n' "${DIM}" "${RST}"
    printf '\n'
    printf '  0)  Back\n\n'
    printf '  > '; read -r choice

    case "${choice}" in
      1) backup_agents ;;
      2) list_backups ;;
      3) restore_agents ;;
      0) return ;;
      *) ;;
    esac
  done
}

backup_agents() {
  info "Creating backup..."
  mkdir -p "${BACKUP_DIR}" 2>/dev/null || mkdir -p "${BACKUP_FALLBACK}" || {
    error "Cannot create backup directory"
    return
  }
  local backup_path="${BACKUP_DIR}"
  [[ ! -d "${backup_path}" ]] && backup_path="${BACKUP_FALLBACK}"
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  local archive="${backup_path}/termux-agents-hub-backup-${ts}.tar.gz"
  local tmpdir
  tmpdir=$(mktemp -d)

  # Create manifest
  cat > "${tmpdir}/backup-manifest.json" << MANIFEST
{"version":"${VERSION}","timestamp":"$(date -Iseconds)","agents":["hermes","codex","openclaw"],"model":"${MODEL}","provider":"${PROVIDER}"}
MANIFEST

  # Copy configs
  [[ -d "${HERMES_HOME}" ]] && cp -r "${HERMES_HOME}" "${tmpdir}/hermes" 2>/dev/null || true
  [[ -d "${CODEX_HOME}" ]] && cp -r "${CODEX_HOME}" "${tmpdir}/codex" 2>/dev/null || true
  [[ -d "${OPENCLAW_HOME}" ]] && cp -r "${OPENCLAW_HOME}" "${tmpdir}/openclaw" 2>/dev/null || true
  mkdir -p "${tmpdir}/hub"
  [[ -f "${CONFIG_FILE}" ]] && cp "${CONFIG_FILE}" "${tmpdir}/hub/" 2>/dev/null || true
  [[ -f "${KEYS_FILE}" ]] && cp "${KEYS_FILE}" "${tmpdir}/hub/" 2>/dev/null || true

  # Create archive
  if tar -czf "${archive}" -C "${tmpdir}" . 2>/dev/null; then
    local size
    size=$(du -h "${archive}" | cut -f1)
    ok "Backup created: ${archive} (${size})"
    log_event "BACKUP" "all" "${archive}"
    notify "Backup complete: ${size}"
  else
    error "Backup failed"
  fi

  rm -rf "${tmpdir}"
}

list_backups() {
  local backup_path="${BACKUP_DIR}"
  [[ ! -d "${backup_path}" ]] && backup_path="${BACKUP_FALLBACK}"

  ui_header "AVAILABLE BACKUPS"
  if [[ ! -d "${backup_path}" ]]; then
    printf '  %sNo backups found%s\n\n' "${DIM}" "${RST}"
    pause
    return
  fi

  local idx=1
  for f in $(ls -t "${backup_path}"/termux-agents-hub-backup-*.tar.gz 2>/dev/null); do
    [[ -f "${f}" ]] || continue
    local size
    size=$(du -h "${f}" | cut -f1)
    local name
    name=$(basename "${f}")
    printf '  %s%d)%s  %s (%s)\n' "${BOLD}${CYAN}" "${idx}" "${RST}" "${name}" "${size}"
    idx=$((idx + 1))
  done

  if (( idx == 1 )); then
    printf '  %sNo backups found%s\n' "${DIM}" "${RST}"
  fi
  pause
}

restore_agents() {
  local backup_path="${BACKUP_DIR}"
  [[ ! -d "${backup_path}" ]] && backup_path="${BACKUP_FALLBACK}"

  ui_header "RESTORE FROM BACKUP"
  if [[ ! -d "${backup_path}" ]]; then
    printf '  %sNo backups found%s\n\n' "${DIM}" "${RST}"
    pause
    return
  fi

  # List backups
  local backups=()
  for f in $(ls -t "${backup_path}"/termux-agents-hub-backup-*.tar.gz 2>/dev/null); do
    [[ -f "${f}" ]] && backups+=("${f}")
  done

  if (( ${#backups[@]} == 0 )); then
    printf '  %sNo backups found%s\n\n' "${DIM}" "${RST}"
    pause
    return
  fi

  printf '  Select backup to restore:\n\n'
  local idx=1
  for f in "${backups[@]}"; do
    local name; name=$(basename "${f}")
    local size; size=$(du -h "${f}" | cut -f1)
    printf '  %s%d)%s  %s (%s)\n' "${BOLD}${CYAN}" "${idx}" "${RST}" "${name}" "${size}"
    idx=$((idx + 1))
  done
  printf '  0)  Back\n\n'
  printf '  > '; read -r sel

  if [[ "${sel}" == "0" ]] || (( sel < 1 || sel > ${#backups[@]} )); then
    return
  fi

  local archive="${backups[$((sel - 1))]}"
  if ! confirm "Restore from $(basename "${archive}")?"; then
    return
  fi

  info "Restoring from backup..."
  local tmpdir
  tmpdir=$(mktemp -d)

  if tar -xzf "${archive}" -C "${tmpdir}" 2>/dev/null; then
    # Validate manifest
    if [[ -f "${tmpdir}/backup-manifest.json" ]]; then
      ok "Manifest validated"
    fi

    # Restore each agent
    [[ -d "${tmpdir}/hermes" ]] && cp -r "${tmpdir}/hermes/"* "${HERMES_HOME}/" 2>/dev/null && ok "Hermes restored"
    [[ -d "${tmpdir}/codex" ]] && cp -r "${tmpdir}/codex/"* "${CODEX_HOME}/" 2>/dev/null && ok "Codex restored"
    [[ -d "${tmpdir}/openclaw" ]] && cp -r "${tmpdir}/openclaw/"* "${OPENCLAW_HOME}/" 2>/dev/null && ok "OpenClaw restored"
    [[ -d "${tmpdir}/hub" ]] && {
      [[ -f "${tmpdir}/hub/config.env" ]] && cp "${tmpdir}/hub/config.env" "${CONFIG_FILE}"
      [[ -f "${tmpdir}/hub/keys.env" ]] && cp "${tmpdir}/hub/keys.env" "${KEYS_FILE}"
      ok "Hub config restored"
    }

    # Post-restore
    if command -v hermes >/dev/null 2>&1; then
      info "Running hermes doctor..."
      hermes doctor 2>/dev/null || warn "hermes doctor check failed"
    fi

    log_event "RESTORE" "all" "$(basename "${archive}")"
    ok "Restore complete!"
    notify "Restore complete"
    load_config
  else
    error "Failed to extract backup"
  fi

  rm -rf "${tmpdir}"
  pause
}

# ═══════════════════════════════════════════════════════════════════════════════
# MIGRATION SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

run_migration() {
  ui_header "MIGRATION"
  local sdcard_src="/sdcard/Download/sid-os-migration"
  local data_src="${MIGRATION_SOURCE}"
  local source=""

  if [[ -d "${sdcard_src}" ]]; then
    source="${sdcard_src}"
    info "Found migration source: ${sdcard_src}"
  elif [[ -d "${data_src}" ]]; then
    source="${data_src}"
    info "Found migration source: ${data_src}"
  else
    warn "No migration source found"
    printf '  Expected paths:\n    %s\n    %s\n\n' "${sdcard_src}" "${data_src}"
    printf '  Custom path? (Enter path or empty to cancel): '
    read -r custom
    if [[ -n "${custom}" ]] && [[ -d "${custom}" ]]; then
      source="${custom}"
    else
      pause
      return
    fi
  fi

  separator
  info "Validating migration source..."
  for subdir in hermes codex openclaw; do
    [[ -d "${source}/${subdir}" ]] && ok "  ${subdir}/ found" || warn "  ${subdir}/ not found (skipping)"
  done

  separator
  if ! confirm "Run migration from ${source}?"; then
    return
  fi

  acquire_wake_lock
  local backup_dir="${STATE_DIR}/backups/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "${backup_dir}"
  info "Creating backups in ${backup_dir}..."

  if [[ -d "${source}/hermes" ]]; then
    info "Migrating Hermes..."
    [[ -d "${HERMES_HOME}" ]] && cp -r "${HERMES_HOME}" "${backup_dir}/hermes" 2>/dev/null || true
    cp -r "${source}/hermes/"* "${HERMES_HOME}/" 2>/dev/null || true
    ok "Hermes migrated"
  fi
  if [[ -d "${source}/codex" ]]; then
    info "Migrating Codex..."
    [[ -d "${CODEX_HOME}" ]] && cp -r "${CODEX_HOME}" "${backup_dir}/codex" 2>/dev/null || true
    cp -r "${source}/codex/"* "${CODEX_HOME}/" 2>/dev/null || true
    ok "Codex migrated"
  fi
  if [[ -d "${source}/openclaw" ]]; then
    info "Migrating OpenClaw..."
    [[ -d "${OPENCLAW_HOME}" ]] && cp -r "${OPENCLAW_HOME}" "${backup_dir}/openclaw" 2>/dev/null || true
    cp -r "${source}/openclaw/"* "${OPENCLAW_HOME}/" 2>/dev/null || true
    ok "OpenClaw migrated"
  fi

  if command -v hermes >/dev/null 2>&1; then
    info "Running Hermes doctor..."
    hermes doctor 2>/dev/null || warn "Hermes doctor check failed"
  fi

  release_wake_lock
  log_event "MIGRATION" "all" "from ${source}"
  ok "Migration complete! Backups at: ${backup_dir}"
  notify "Migration complete"
  pause
}

# ═══════════════════════════════════════════════════════════════════════════════
# SETTINGS
# ═══════════════════════════════════════════════════════════════════════════════

settings() {
  while true; do
    ui_header "SETTINGS"
    printf '  %s1)%s  Network & Ports\n' "${BOLD}${CYAN}" "${RST}"
    printf '  %s2)%s  Model & Provider\n' "${BOLD}${CYAN}" "${RST}"
    printf '  %s3)%s  API Key Setup\n' "${BOLD}${CYAN}" "${RST}"
    printf '  %s4)%s  Theme\n' "${BOLD}${CYAN}" "${RST}"
    printf '  %s5)%s  Features (Wake Lock, Notifications, Auto-restart)\n' "${BOLD}${CYAN}" "${RST}"
    printf '  %s6)%s  Migration Source\n' "${BOLD}${CYAN}" "${RST}"
    printf '  %s7)%s  View Current Config\n' "${BOLD}${CYAN}" "${RST}"
    printf '  %s8)%s  Health Monitor Settings\n' "${BOLD}${CYAN}" "${RST}"
    printf '  %s0)%s  Back to Launch Menu\n\n' "${BOLD}${CYAN}" "${RST}"
    printf '  > '; read -r choice

    case "${choice}" in
      1) settings_network ;;
      2) settings_model ;;
      3) settings_api_key ;;
      4) settings_theme ;;
      5) settings_features ;;
      6) settings_migration_source ;;
      7) settings_view_config ;;
      8) settings_health ;;
      0) return ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

settings_network() {
  ui_header "NETWORK & PORTS"
  printf '  %sCurrent settings:%s\n' "${BOLD}" "${RST}"
  printf '    Host:      %s\n' "${HERMES_HOST}"
  printf '    Dashboard: %s (auto-resolves conflicts)\n' "${HERMES_DASH_PORT}"
  printf '    API:       %s (auto-resolves conflicts)\n' "${HERMES_API_PORT}"
  printf '    Codex:     %s (auto-resolves conflicts)\n' "${CODEX_PORT}"
  printf '    OpenClaw:  %s (auto-resolves conflicts)\n' "${OPENCLAW_PORT}"
  separator
  printf '  1) Change host (current: %s)\n' "${HERMES_HOST}"
  printf '  2) Auto-resolve port conflicts now\n'
  printf '  3) Set Hermes Dashboard port (current: %s)\n' "${HERMES_DASH_PORT}"
  printf '  4) Set Hermes API port (current: %s)\n' "${HERMES_API_PORT}"
  printf '  5) Set Codex port (current: %s)\n' "${CODEX_PORT}"
  printf '  6) Set OpenClaw port (current: %s)\n' "${OPENCLAW_PORT}"
  printf '  0) Back\n\n'
  printf '  > '; read -r choice

  case "${choice}" in
    1) printf '  New host [0.0.0.0]: '; read -r val; HERMES_HOST="${val:-0.0.0.0}" ;;
    2) resolve_ports ;;
    3) printf '  New port [9119]: '; read -r val; HERMES_DASH_PORT="${val:-9119}" ;;
    4) printf '  New port [9120]: '; read -r val; HERMES_API_PORT="${val:-9120}" ;;
    5) printf '  New port [8082]: '; read -r val; CODEX_PORT="${val:-8082}" ;;
    6) printf '  New port [18789]: '; read -r val; OPENCLAW_PORT="${val:-18789}" ;;
    *) return ;;
  esac
  save_config
  log_event "CONFIG_CHANGE" "network" "${choice}"
  ok "Settings saved"
}

settings_model() {
  ui_header "MODEL & PROVIDER"
  printf '  %sCurrent:%s Model=%s  Provider=%s\n\n' "${BOLD}" "${RST}" "${MODEL}" "${PROVIDER}"
  printf '  1) Set Model\n'
  printf '  2) Set Provider\n'
  printf '  3) Quick select free model\n'
  printf '  0) Back\n\n'
  printf '  > '; read -r choice

  case "${choice}" in
    1) printf '  Model [openrouter/qwen/qwen3-coder:free]: '; read -r val; MODEL="${val:-openrouter/qwen/qwen3-coder:free}" ;;
    2) printf '  Provider [openrouter]: '; read -r val; PROVIDER="${val:-openrouter}" ;;
    3)
      printf '\n  Free models:\n'
      printf '    1) openrouter/qwen/qwen3-coder:free\n'
      printf '    2) openrouter/nvidia/nemotron-3-ultra:free\n'
      printf '    3) openrouter/meta-llama/llama-4-maverick:free\n'
      printf '    4) Custom...\n\n'
      printf '  > '; read -r mc
      case "${mc}" in
        1) MODEL="openrouter/qwen/qwen3-coder:free" ;;
        2) MODEL="openrouter/nvidia/nemotron-3-ultra:free" ;;
        3) MODEL="openrouter/meta-llama/llama-4-maverick:free" ;;
        4) printf '  Model: '; read -r MODEL ;;
        *) return ;;
      esac
      ;;
    *) return ;;
  esac
  save_config
  log_event "CONFIG_CHANGE" "model" "${MODEL}"
  if [[ -f "${HERMES_HOME}/.env" ]]; then
    sed -i "s|^HERMES_MODEL=.*|HERMES_MODEL=${MODEL}|" "${HERMES_HOME}/.env" 2>/dev/null || true
    sed -i "s|^HERMES_PROVIDER=.*|HERMES_PROVIDER=${PROVIDER}|" "${HERMES_HOME}/.env" 2>/dev/null || true
  fi
  ok "Model updated: ${MODEL}"
  check_restart_agents "model"
}

settings_api_key() {
  ui_header "API KEY SETUP"
  if [[ -n "${OPENROUTER_API_KEY}" ]]; then
    local masked="${OPENROUTER_API_KEY:0:12}...${OPENROUTER_API_KEY: -4}"
    printf '  %sCurrent key:%s %s\n\n' "${BOLD}" "${RST}" "${masked}"
  else
    printf '  %sNo API key configured%s\n\n' "${YELLOW}" "${RST}"
  fi
  printf '  1) Set new API key\n'
  printf '  2) Clear API key\n'
  printf '  0) Back\n\n'
  printf '  > '; read -r choice

  case "${choice}" in
    1)
      printf '  Enter OpenRouter API key (sk-or-v1-...): '
      read -r -s new_key; printf '\n'
      if [[ -n "${new_key}" ]]; then
        OPENROUTER_API_KEY="${new_key}"
        save_keys
        if [[ -d "${HERMES_HOME}" ]]; then
          if [[ -f "${HERMES_HOME}/.env" ]]; then
            sed -i "s|^OPENROUTER_API_KEY=.*|OPENROUTER_API_KEY=${new_key}|" "${HERMES_HOME}/.env" 2>/dev/null || \
            echo "OPENROUTER_API_KEY=${new_key}" >> "${HERMES_HOME}/.env"
          else
            echo "OPENROUTER_API_KEY=${new_key}" > "${HERMES_HOME}/.env"
          fi
        fi
        log_event "KEY_CHANGE" "api-key" "Updated"
        ok "API key saved"
        check_restart_agents "API key"
      else
        warn "No key entered"
      fi
      ;;
    2)
      OPENROUTER_API_KEY=""
      save_keys
      [[ -f "${HERMES_HOME}/.env" ]] && sed -i "s|^OPENROUTER_API_KEY=.*|OPENROUTER_API_KEY=|" "${HERMES_HOME}/.env" 2>/dev/null || true
      log_event "KEY_CHANGE" "api-key" "Cleared"
      ok "API key cleared"
      check_restart_agents "API key"
      ;;
    *) return ;;
  esac
}

settings_theme() {
  ui_header "HERMES THEME"
  printf '  %sCurrent:%s %s\n\n' "${BOLD}" "${RST}" "${HERMES_THEME}"
  printf '  1) default\n  2) midnight\n  3) ember\n  4) mono\n  5) cyberpunk\n  6) rose\n  0) Back\n\n'
  printf '  > '; read -r choice
  case "${choice}" in
    1) HERMES_THEME="default" ;; 2) HERMES_THEME="midnight" ;; 3) HERMES_THEME="ember" ;;
    4) HERMES_THEME="mono" ;; 5) HERMES_THEME="cyberpunk" ;; 6) HERMES_THEME="rose" ;;
    *) return ;;
  esac
  save_config
  [[ -f "${HERMES_HOME}/.env" ]] && sed -i "s|^HERMES_THEME=.*|HERMES_THEME=${HERMES_THEME}|" "${HERMES_HOME}/.env" 2>/dev/null || true
  log_event "CONFIG_CHANGE" "theme" "${HERMES_THEME}"
  ok "Theme set to: ${HERMES_THEME}"
}

settings_features() {
  ui_header "FEATURES"
  printf '  1) Wake Lock:             %s%s%s\n' "${BOLD}" "${ENABLE_WAKE_LOCK}" "${RST}"
  printf '  2) Notifications:         %s%s%s\n' "${BOLD}" "${ENABLE_NOTIFICATIONS}" "${RST}"
  printf '  3) Auto-restart on crash: %s%s%s\n' "${BOLD}" "${ENABLE_AUTO_RESTART}" "${RST}"
  printf '  0) Back\n\n'
  printf '  > '; read -r choice

  case "${choice}" in
    1)
      if [[ "${ENABLE_WAKE_LOCK}" == "true" ]]; then ENABLE_WAKE_LOCK="false"; release_wake_lock
      else ENABLE_WAKE_LOCK="true"; acquire_wake_lock; fi ;;
    2)
      if [[ "${ENABLE_NOTIFICATIONS}" == "true" ]]; then ENABLE_NOTIFICATIONS="false"
      else ENABLE_NOTIFICATIONS="true"; fi ;;
    3)
      if [[ "${ENABLE_AUTO_RESTART}" == "true" ]]; then ENABLE_AUTO_RESTART="false"
      else ENABLE_AUTO_RESTART="true"; fi ;;
    *) return ;;
  esac
  save_config
  log_event "CONFIG_CHANGE" "features" "${choice}"
  ok "Feature updated"
}

settings_health() {
  ui_header "HEALTH MONITOR SETTINGS"
  printf '  %sCurrent:%s Poll interval: %ss  Auto-restart: %s\n\n' "${BOLD}" "${RST}" "${HEALTH_POLL_INTERVAL}" "${ENABLE_AUTO_RESTART}"
  printf '  1) Set poll interval (current: %ss)\n' "${HEALTH_POLL_INTERVAL}"
  printf '  2) Toggle auto-restart (current: %s)\n' "${ENABLE_AUTO_RESTART}"
  printf '  0) Back\n\n'
  printf '  > '; read -r choice

  case "${choice}" in
    1)
      printf '  Poll interval in seconds [5]: '; read -r val
      HEALTH_POLL_INTERVAL="${val:-5}"
      ;;
    2)
      if [[ "${ENABLE_AUTO_RESTART}" == "true" ]]; then ENABLE_AUTO_RESTART="false"
      else ENABLE_AUTO_RESTART="true"; fi
      ;;
    *) return ;;
  esac
  save_config
  log_event "CONFIG_CHANGE" "health" "${choice}"
  ok "Health settings updated"
}

settings_migration_source() {
  ui_header "MIGRATION SOURCE"
  printf '  %sCurrent:%s %s\n\n' "${BOLD}" "${RST}" "${MIGRATION_SOURCE}"
  printf '  Enter new path (empty to keep current): '
  read -r new_path
  if [[ -n "${new_path}" ]]; then
    MIGRATION_SOURCE="${new_path}"
    save_config
    ok "Migration source updated"
  fi
}

settings_view_config() {
  ui_header "CURRENT CONFIGURATION"
  printf '  %sNetwork:%s\n' "${BOLD}" "${RST}"
  printf '    Host:          %s\n' "${HERMES_HOST}"
  printf '    Dashboard:     %s\n' "${HERMES_DASH_PORT}"
  printf '    API:           %s\n' "${HERMES_API_PORT}"
  printf '    Codex:         %s\n' "${CODEX_PORT}"
  printf '    OpenClaw:      %s\n' "${OPENCLAW_PORT}"
  separator
  printf '  %sModel & Provider:%s\n' "${BOLD}" "${RST}"
  printf '    Model:         %s\n' "${MODEL}"
  printf '    Provider:      %s\n' "${PROVIDER}"
  separator
  printf '  %sHermes:%s\n' "${BOLD}" "${RST}"
  printf '    Theme:         %s\n' "${HERMES_THEME}"
  separator
  printf '  %sFeatures:%s\n' "${BOLD}" "${RST}"
  printf '    Wake Lock:     %s\n' "${ENABLE_WAKE_LOCK}"
  printf '    Notifications: %s\n' "${ENABLE_NOTIFICATIONS}"
  printf '    Auto-restart:  %s\n' "${ENABLE_AUTO_RESTART}"
  printf '    Health poll:   %ss\n' "${HEALTH_POLL_INTERVAL}"
  separator
  printf '  %sPaths:%s\n' "${BOLD}" "${RST}"
  printf '    Config:        %s\n' "${CONFIG_FILE}"
  printf '    Keys:          %s\n' "${KEYS_FILE}"
  printf '    Logs:          %s\n' "${LOG_DIR}"
  printf '    History:       %s\n' "${HISTORY_FILE}"
  printf '    Backup:        %s\n' "${BACKUP_DIR}"
  separator
  printf '  %sTool Categories:%s\n' "${BOLD}" "${RST}"
  printf '    Termux API:    %s\n' "${TOOL_CAT_TERMUX}"
  printf '    Shizuku:       %s\n' "${TOOL_CAT_SHIZUKU}"
  printf '    Intent:        %s\n' "${TOOL_CAT_INTENT}"
  printf '    Dev Tools:     %s\n' "${TOOL_CAT_DEV}"
  separator
  printf '  %sAPI Key:%s\n' "${BOLD}" "${RST}"
  if [[ -n "${OPENROUTER_API_KEY}" ]]; then
    printf '    %sconfigured%s (%s...%s)\n' "${GREEN}" "${RST}" "${OPENROUTER_API_KEY:0:12}" "${OPENROUTER_API_KEY: -4}"
  else
    printf '    %snot configured%s\n' "${YELLOW}" "${RST}"
  fi
  pause
}

# ── Auto-Restart on Settings Change ──────────────────────────────────────────
check_restart_agents() {
  local changed=$1
  local restarted=false

  if agent_running "hermes.*dashboard"; then
    if confirm "Hermes Dashboard is running. Restart for ${changed}?"; then
      stop_agent "Hermes Dashboard" "hermes.*dashboard"
      sleep 1
      launch_background "hermes-dashboard" \
        "hermes dashboard --host ${HERMES_HOST} --port ${HERMES_DASH_PORT} --no-open"
      restarted=true
    fi
  fi

  if agent_running "hermes.*serve"; then
    if confirm "Hermes API Server is running. Restart for ${changed}?"; then
      stop_agent "Hermes API Server" "hermes.*serve"
      sleep 1
      launch_background "hermes-serve" \
        "hermes chat --host ${HERMES_HOST} --port ${HERMES_API_PORT}"
      restarted=true
    fi
  fi

  if agent_running "openclaw"; then
    if confirm "OpenClaw is running. Restart for ${changed}?"; then
      stop_agent "OpenClaw Gateway" "openclaw"
      sleep 1
      launch_background "openclaw" \
        "openclaw gateway --host ${HERMES_HOST} --port ${OPENCLAW_PORT}"
      restarted=true
    fi
  fi

  [[ "${restarted}" == "true" ]] && notify "Agents restarted after ${changed} update"
}

# ═══════════════════════════════════════════════════════════════════════════════
# DIAGNOSTICS
# ═══════════════════════════════════════════════════════════════════════════════

diagnostics() {
  ui_header "DIAGNOSTICS"
  printf '  %sInstalled Versions:%s\n' "${BOLD}" "${RST}"
  for tool in hermes codex openclaw; do
    if command -v "${tool}" >/dev/null 2>&1; then
      local ver; ver=$(${tool} --version 2>/dev/null | head -1 || echo "installed")
      printf '    %s✓%s  %-12s %s%s%s\n' "${GREEN}" "${RST}" "${tool}" "${DIM}" "${ver}" "${RST}"
    else
      printf '    %s✗%s  %-12s %snot installed%s\n' "${RED}" "${RST}" "${tool}" "${DIM}" "${RST}"
    fi
  done
  separator
  printf '  %sRunning Agents:%s\n' "${BOLD}" "${RST}"
  local ip; ip=$(get_ip)
  agent_running "hermes.*dashboard" && printf '    %s●%s Hermes Dashboard   %shttp://%s:%s%s\n' "${GREEN}" "${RST}" "${DIM}" "${ip}" "${HERMES_DASH_PORT}" "${RST}"
  agent_running "hermes.*serve" && printf '    %s●%s Hermes API Server  %shttp://%s:%s/api%s\n' "${GREEN}" "${RST}" "${DIM}" "${ip}" "${HERMES_API_PORT}" "${RST}"
  agent_running "openclaw" && printf '    %s●%s OpenClaw Gateway   %shttp://%s:%s%s\n' "${GREEN}" "${RST}" "${DIM}" "${ip}" "${OPENCLAW_PORT}" "${RST}"
  agent_running "codex" && printf '    %s●%s Codex CLI          %srunning%s\n' "${GREEN}" "${RST}" "${DIM}" "${RST}"
  local rc; rc=$(running_count)
  [[ "${rc}" -eq 0 ]] && printf '    %s(none running)%s\n' "${DIM}" "${RST}"
  separator
  printf '  %sConfiguration:%s\n' "${BOLD}" "${RST}"
  printf '    Config:    %s\n' "${CONFIG_FILE}"
  printf '    Model:     %s\n' "${MODEL}"
  printf '    Provider:  %s\n' "${PROVIDER}"
  printf '    Theme:     %s\n' "${HERMES_THEME}"
  separator
  printf '  %sNetwork:%s\n' "${BOLD}" "${RST}"
  printf '    Local IP:  %s\n' "${ip}"
  printf '    Host:      %s\n' "${HERMES_HOST}"
  separator
  printf '  %sConnectivity:%s\n' "${BOLD}" "${RST}"
  if curl -s --max-time 5 "https://openrouter.ai/api/v1/models" >/dev/null 2>&1; then
    printf '    %s✓%s  OpenRouter reachable\n' "${GREEN}" "${RST}"
  else
    printf '    %s✗%s  OpenRouter unreachable\n' "${RED}" "${RST}"
  fi
  pause
}

# ═══════════════════════════════════════════════════════════════════════════════
# SELF-UPDATE
# ═══════════════════════════════════════════════════════════════════════════════

self_update() {
  info "Checking for updates..."
  local remote_version
  remote_version=$(curl -s --max-time 10 "https://raw.githubusercontent.com/your-org/termux-agents-hub/main/VERSION" 2>/dev/null | tr -d '[:space:]')
  if [[ -z "${remote_version}" ]]; then
    warn "Could not check for updates"
    return
  fi
  if [[ "${remote_version}" == "${VERSION}" ]]; then
    ok "Already up to date (v${VERSION})"
  else
    info "New version available: v${remote_version}"
    if confirm "Update to v${remote_version}?"; then
      local script_path="${0}"
      if curl -s --max-time 30 -o "${script_path}" \
        "https://raw.githubusercontent.com/your-org/termux-agents-hub/main/termux-agents-hub.sh" 2>/dev/null; then
        chmod +x "${script_path}"
        ok "Updated to v${remote_version}. Restart the script."
        exit 0
      else
        error "Update failed"
      fi
    fi
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CLEANUP / TRAP
# ═══════════════════════════════════════════════════════════════════════════════

cleanup() {
  :
}

trap cleanup EXIT

# ═══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

main() {
  # Verify critical functions loaded (catches silent parse failures on some bash versions)
  for _fn in install_menu launch_menu health_monitor show_tools_menu settings              backup_restore_menu run_migration diagnostics show_history              resolve_ports load_config save_config find_free_port; do
    if ! declare -f "${_fn}" >/dev/null 2>&1; then
      echo "FATAL: Function ${_fn}() not loaded. Your bash may not support all syntax used."
      echo "Try: bash -n $(basename "$0") to check, or reinstall from GitHub."
      exit 1
    fi
  done

  setup_colors
  setup_logging
  mkdir -p "${CONFIG_DIR}" "${DATA_DIR}" "${STATE_DIR}" "${CACHE_DIR}" "${RUN_DIR}" "${LOG_DIR}"

  load_config
  resolve_ports
  acquire_wake_lock

  case "${1:-}" in
    --update|-u) self_update ;;
    --install|i) install_menu ;;
    --settings|s) settings ;;
    --migrate|m) run_migration ;;
    --diagnostics|d) diagnostics ;;
    --tools|t) show_tools_menu ;;
    --health) health_monitor ;;
    --history) show_history ;;
    --backup) backup_restore_menu ;;
    --doctor)
      ui_header "DOCTOR"
      printf '  %sEnvironment:%s\n' "${BOLD}" "${RST}"
      printf '    Home:      %s\n' "${HOME}"
      printf '    Prefix:    %s\n' "${PREFIX}"
      printf '    Config:    %s\n' "${CONFIG_FILE}"
      printf '    Migration: %s\n' "${MIGRATION_SOURCE}"
      separator
      printf '  %sInstalled Agents:%s\n' "${BOLD}" "${RST}"
      for bin in hermes codex openclaw; do
        if command -v "${bin}" >/dev/null 2>&1; then
          local ver; ver=$(${bin} --version 2>/dev/null | head -1 || echo "installed")
          printf '    %s✓%s  %s: %s\n' "${GREEN}" "${RST}" "${bin}" "${ver}"
        else
          printf '    %s✗%s  %s: not installed\n' "${RED}" "${RST}" "${bin}"
        fi
      done
      separator
      printf '  %sRunning:%s %s agent(s)\n' "${BOLD}" "${RST}" "$(running_count)"
      local ip; ip=$(get_ip)
      agent_running "hermes.*dashboard" && printf '    Dashboard: http://%s:%s\n' "${ip}" "${HERMES_DASH_PORT}"
      agent_running "hermes.*serve" && printf '    API:       http://%s:%s/api\n' "${ip}" "${HERMES_API_PORT}"
      agent_running "openclaw" && printf '    OpenClaw:  http://%s:%s\n' "${ip}" "${OPENCLAW_PORT}"
      ;;
    --stop-all) stop_all_agents ;;
    --stop)
      local agent="${2:-}"
      case "${agent}" in
        hermes-dashboard|dashboard) stop_agent "Hermes Dashboard" "hermes.*dashboard" ;;
        hermes-api|api) stop_agent "Hermes API Server" "hermes.*serve" ;;
        codex) stop_agent "Codex CLI" "codex" ;;
        openclaw) stop_agent "OpenClaw Gateway" "openclaw" ;;
        *) warn "Usage: $0 --stop <agent-name>" ;;
      esac
      ;;
    --launch-dashboard) launch_hermes_dashboard ;;
    --launch-api) launch_hermes_serve ;;
    --launch-chat) launch_hermes_chat ;;
    --launch-codex) launch_codex ;;
    --launch-openclaw) launch_openclaw ;;
    --copy-url)
      local agent="${2:-}"
      case "${agent}" in
        dashboard) copy_to_clipboard "http://$(get_ip):${HERMES_DASH_PORT}" ;;
        api) copy_to_clipboard "http://$(get_ip):${HERMES_API_PORT}" ;;
        openclaw) copy_to_clipboard "http://$(get_ip):${OPENCLAW_PORT}" ;;
        *) warn "Usage: $0 --copy-url <dashboard|api|openclaw>" ;;
      esac
      ;;
    --open-url)
      local agent="${2:-}"
      case "${agent}" in
        dashboard) open_in_browser "http://$(get_ip):${HERMES_DASH_PORT}" ;;
        api) open_in_browser "http://$(get_ip):${HERMES_API_PORT}" ;;
        openclaw) open_in_browser "http://$(get_ip):${OPENCLAW_PORT}" ;;
        *) warn "Usage: $0 --open-url <dashboard|api|openclaw>" ;;
      esac
      ;;
    --help|-h)
      cat << EOF
${NAME} v${VERSION}

Usage: $(basename "$0") [command]

Commands:
  (no args)           Launch interactive menu
  --install, -i       Open install menu
  --settings, -s      Open settings
  --tools, -t         Browse tools & skills
  --health            Launch health monitor
  --history           View session history
  --backup            Backup / restore agents
  --migrate, -m       Run migration
  --diagnostics, -d   Show diagnostics
  --doctor            System health check
  --update, -u        Check for script updates

Launch:
  --launch-dashboard  Start Hermes Dashboard (web UI)
  --launch-api        Start Hermes API Server (headless)
  --launch-chat       Start Hermes Chat TUI (foreground)
  --launch-codex      Start Codex CLI (foreground)
  --launch-openclaw   Start OpenClaw Gateway (web UI)

Quick Connect:
  --copy-url <agent>  Copy agent URL to clipboard
  --open-url <agent>  Open agent URL in browser

Stop:
  --stop <agent>      Stop a specific agent
  --stop-all          Stop all running agents

Tools & Skills:
  Browse 56 tools (Termux API, Shizuku, Intent Bridge, Dev)
  Toggle categories on/off in settings

Environment:
  OPENROUTER_API_KEY    API key for OpenRouter (all agents)
  MODEL                 Default model
  PROVIDER              Default provider

Config:    ${CONFIG_FILE}
Keys:      ${KEYS_FILE}
Logs:      ${LOG_DIR}
History:   ${HISTORY_FILE}
Backup:    ${BACKUP_DIR}
EOF
      ;;
    *) launch_menu ;;
  esac
}

main "$@"
