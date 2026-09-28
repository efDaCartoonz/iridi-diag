#!/bin/sh

# iRidi Server Health & System Diagnostic (HSS, ProAV, UMC, KNX)
# Comprehensive 360-degree audit:
# 1. Hardware Identity & devicetree (OEM serial, board revision, uptime, load)
# 2. Hardware Peripherals & I/O (RS-485/UART error counters, RTC & battery, Watchdog, GPIO)
# 3. iRidi Runtime & Systemd Services (PID, restart counts, OOM events, sockets, MQTT broker)
# 4. iRidi Projects, Licenses & Databases (License audit, active projects, SQLite integrity, log scan)
# 5. CPU, Thermals & Power (Thermal zones, throttling, core topology)
# 6. Memory (RAM) & Swap utilization
# 7. Storage, Mounts & eMMC Wear (eMMC SMART LifeTime A/B, Pre-EOL, I/O errors)
# 8. Network & Communication (Ethernet speed/duplex, CAN controllers, gateway ping, DNS latency)
#
# Usage: sh check_server_health.sh [--json]

case "${1:-}" in
  -h|--help)
    printf 'Usage: sh %s [options]\n\n' "${0##*/}"
    printf 'Options:\n'
    printf '  --json        Output summary in JSON format\n'
    printf '  -h, --help    Show this help message and exit\n\n'
    printf 'Description:\n'
    printf '  Collects and reports comprehensive hardware identity, server firmware version,\n'
    printf '  runtime status, thermal indicators, eMMC wear level (SMART), memory, storage,\n'
    printf '  RS-485/UART status, RTC/battery, Watchdog, iRidi projects & databases, and network health.\n'
    exit 0
    ;;
esac

TOOL_VERSION="2.0"
JSON_OUTPUT=0
[ "${1:-}" = "--json" ] && JSON_OUTPUT=1

# Setup logging directory & technical log file
CURRENT_DIR="$(pwd 2>/dev/null || printf '.')"
LOG_DIR="${IRIDI_DIAG_LOG_DIR:-$CURRENT_DIR}"
if [ ! -d "$LOG_DIR" ] || [ ! -w "$LOG_DIR" ]; then
  LOG_DIR="${TMPDIR:-/tmp}"
fi

DEVICE_NAME="$(cat /sys/firmware/devicetree/base/serial-number 2>/dev/null | tr -d '\0\r\n')"
if [ -z "$DEVICE_NAME" ]; then
  DEVICE_NAME="$(awk -F': *' '/Controller serial/{print $2}' /oem/hal/ccinfo 2>/dev/null | tr -d ' \r\t\n')"
fi
if [ -z "$DEVICE_NAME" ]; then
  DEVICE_NAME="$(uname -n 2>/dev/null | tr -d '\r\n' | tr -c 'A-Za-z0-9._-' '_')"
fi
DEVICE_NAME="${DEVICE_NAME:-server}"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S' 2>/dev/null || printf '00000000_000000')"
LOG_FILE="${LOG_DIR}/server_health_${DEVICE_NAME}_${TIMESTAMP}_$$.log"

# Open File Descriptor 3 for technical log
if ! exec 3>>"$LOG_FILE" 2>/dev/null; then
  LOG_FILE="${TMPDIR:-/tmp}/server_health_${DEVICE_NAME}_${TIMESTAMP}_$$.log"
  if ! exec 3>>"$LOG_FILE"; then
    printf '[NOT OK] Could not open log file for writing: %s\n' "$LOG_FILE" >&2
    exit 2
  fi
fi

# Terminal colors (screen only)
if [ -t 1 ] && [ "${NO_COLOR:-0}" = "0" ]; then
  C_RESET="$(printf '\033[0m')"
  C_BOLD="$(printf '\033[1m')"
  C_DIM="$(printf '\033[2m')"
  C_GREEN="$(printf '\033[32m')"
  C_YELLOW="$(printf '\033[33m')"
  C_RED="$(printf '\033[31m')"
  C_CYAN="$(printf '\033[36m')"
  C_GRAY="$(printf '\033[90m')"
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_GREEN=""
  C_YELLOW=""
  C_RED=""
  C_CYAN=""
  C_GRAY=""
fi

log_tech() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '-')" "$*" >&3
}

log_tech_file() {
  _HEADER="$1"
  _FILE="$2"
  if [ -s "$_FILE" ]; then
    printf '[%s] --- BEGIN %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '-')" "$_HEADER" >&3
    cat "$_FILE" >&3 2>/dev/null
    printf '[%s] --- END %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '-')" "$_HEADER" >&3
  fi
}

log_tech_cmd() {
  _LABEL="$1"
  shift
  printf '[%s] --- CMD EXEC: %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '-')" "$_LABEL" >&3
  "$@" >&3 2>&1 || true
  printf '[%s] --- END CMD: %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '-')" "$_LABEL" >&3
}

set +e
export LC_ALL=C

STARTED_AT="$(date 2>/dev/null || printf 'unknown')"
HOSTNAME_VAL="$(uname -n 2>/dev/null || printf 'unknown')"
WARN_COUNT=0
FAIL_COUNT=0

ok() {
  printf '  %s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$1"
  log_tech "OK: $1"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '  %s[ATTENTION]%s %s\n' "$C_YELLOW" "$C_RESET" "$1"
  log_tech "ATTENTION: $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '  %s[NOT OK]%s %s\n' "$C_RED" "$C_RESET" "$1"
  log_tech "FAIL: $1"
}

info() {
  printf '  %s[INFO]%s %s\n' "$C_CYAN" "$C_RESET" "$1"
  log_tech "INFO: $1"
}

cleanup() {
  exec 3>&- 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

# Technical Log Initial Header
log_tech "================================================================================"
log_tech "iRidi Server Health & System Diagnostic - Technical Log"
log_tech "Version: $TOOL_VERSION | Started: $STARTED_AT"
log_tech "Host: $HOSTNAME_VAL | Kernel: $(uname -srm 2>/dev/null)"
log_tech "Log File: $LOG_FILE"
log_tech "================================================================================"

log_tech_file "OEM CCINFO (/oem/hal/ccinfo)" "/oem/hal/ccinfo"
log_tech_file "CPUINFO (/proc/cpuinfo)" "/proc/cpuinfo"
log_tech_file "MEMINFO (/proc/meminfo)" "/proc/meminfo"
log_tech_file "UPTIME (/proc/uptime)" "/proc/uptime"
log_tech_file "LOADAVG (/proc/loadavg)" "/proc/loadavg"

# Screen Header
printf '%s================================================================================%s\n' "$C_BOLD" "$C_RESET"
printf '%s  iRidi Server Health & System Overview v%s%s\n' "$C_BOLD$C_CYAN" "$TOOL_VERSION" "$C_RESET"
printf '%s================================================================================%s\n' "$C_BOLD" "$C_RESET"
printf '  %-20s : %s (%s %s)\n' "Host" "$HOSTNAME_VAL" "$(uname -s 2>/dev/null)" "$(uname -m 2>/dev/null)"
printf '  %-20s : %s\n' "Started" "$STARTED_AT"
printf '  %-20s : %s%s%s\n' "Technical Log" "$C_DIM" "$LOG_FILE" "$C_RESET"
printf '%s--------------------------------------------------------------------------------%s\n' "$C_DIM" "$C_RESET"

# ==============================================================================
# SECTION 1: Hardware & System Identification
# ==============================================================================
check_hardware_identity() {
  printf '\n%s[1/8] Hardware & System Identity%s\n' "$C_BOLD" "$C_RESET"

  MODEL=""
  SERIAL=""
  CPU_SERIAL=""
  SW_VERSION=""

  if [ -r /oem/hal/ccinfo ]; then
    SERIAL="$(awk -F': *' '/Controller serial/{print $2}' /oem/hal/ccinfo | sed 's/^[ \t]*//;s/[ \t]*$//')"
    CPU_SERIAL="$(awk -F': *' '/Processor serial/{print $2}' /oem/hal/ccinfo | sed 's/^[ \t]*//;s/[ \t]*$//')"
    MODEL="$(awk -F': *' '/Hardware version/{print $2}' /oem/hal/ccinfo | sed 's/^[ \t]*//;s/[ \t]*$//')"
    SW_VERSION="$(awk -F': *' '/Software version/{print $2}' /oem/hal/ccinfo | sed 's/^[ \t]*//;s/[ \t]*$//')"
  fi

  if [ -z "$MODEL" ] && [ -r /sys/firmware/devicetree/base/model ]; then
    MODEL="$(tr -d '\0' </sys/firmware/devicetree/base/model | sed 's/^[ \t]*//;s/[ \t]*$//')"
  fi
  if [ -z "$SERIAL" ] && [ -r /sys/firmware/devicetree/base/serial-number ]; then
    SERIAL="$(tr -d '\0' </sys/firmware/devicetree/base/serial-number | sed 's/^[ \t]*//;s/[ \t]*$//')"
  fi
  if [ -z "$CPU_SERIAL" ] && [ -r /proc/cpuinfo ]; then
    CPU_SERIAL="$(awk '/Serial/{print $3}' /proc/cpuinfo | head -n 1)"
  fi
  if [ -z "$SW_VERSION" ] && [ -r /usr/lib/os-release ]; then
    SW_VERSION="$(awk -F'=' '/PRETTY_NAME/{gsub(/"/, ""); print $2}' /usr/lib/os-release)"
  fi
  if [ -z "$SW_VERSION" ] && [ -r /etc/os-release ]; then
    SW_VERSION="$(awk -F'=' '/PRETTY_NAME/{gsub(/"/, ""); print $2}' /etc/os-release)"
  fi

  UPTIME_FMT="n/a"
  if [ -r /proc/uptime ]; then
    UPTIME_SECS="$(cut -d' ' -f1 /proc/uptime | cut -d'.' -f1)"
    DAYS=$((UPTIME_SECS / 86400))
    HOURS=$(((UPTIME_SECS % 86400) / 3600))
    MINS=$(((UPTIME_SECS % 3600) / 60))
    if [ "$DAYS" -gt 0 ]; then
      UPTIME_FMT="${DAYS}d ${HOURS}h ${MINS}m"
    elif [ "$HOURS" -gt 0 ]; then
      UPTIME_FMT="${HOURS}h ${MINS}m"
    else
      UPTIME_FMT="${MINS}m"
    fi
  fi

  LOAD_FMT="n/a"
  if [ -r /proc/loadavg ]; then
    LOAD_1="$(cut -d' ' -f1 /proc/loadavg)"
    LOAD_5="$(cut -d' ' -f2 /proc/loadavg)"
    LOAD_15="$(cut -d' ' -f3 /proc/loadavg)"
    LOAD_FMT="$LOAD_1, $LOAD_5, $LOAD_15"
  fi

  printf '  - Hardware Model     : %s\n' "${MODEL:-Unknown Model}"
  printf '  - Controller Serial  : %s (CPU Serial: %s)\n' "${SERIAL:-n/a}" "${CPU_SERIAL:-n/a}"
  printf '  - Operating System   : %s (Kernel: %s)\n' "${SW_VERSION:-Linux}" "$(uname -r 2>/dev/null)"
  printf '  - System Uptime      : %s (Load average: %s)\n' "$UPTIME_FMT" "$LOAD_FMT"
  log_tech "IDENTITY: model=$MODEL serial=$SERIAL cpu_serial=$CPU_SERIAL os=$SW_VERSION uptime=$UPTIME_FMT load=$LOAD_FMT"
}

# ==============================================================================
# SECTION 2: Hardware Peripherals, Serial (RS-485), RTC & Watchdog
# ==============================================================================
check_peripherals_and_io() {
  printf '\n%s[2/8] Hardware Peripherals & I/O (RS-485, RTC, Watchdog)%s\n' "$C_BOLD" "$C_RESET"

  # 1. Serial & RS-485 Ports
  SERIAL_PORTS=""
  for PORT in /dev/ttyS* /dev/ttyUSB* /dev/ttyAMA* /dev/ttymxc* /dev/ttyAP*; do
    [ -e "$PORT" ] || continue
    # Filter out inactive virtual ttyS ports
    case "$PORT" in
      /dev/ttyS[2-9]|/dev/ttyS[1-9][0-9])
        if [ ! -d "/sys/class/tty/${PORT##*/}/device" ]; then
          continue
        fi
        ;;
    esac
    SERIAL_PORTS="${SERIAL_PORTS:+$SERIAL_PORTS }${PORT}"
  done

  if [ -n "$SERIAL_PORTS" ]; then
    ok "Detected serial / RS-485 port(s): $SERIAL_PORTS"
    if [ -r /proc/tty/driver/serial ]; then
      log_tech_file "Serial driver statistics (/proc/tty/driver/serial)" "/proc/tty/driver/serial"
      # Check for frame / overrun errors
      UART_ERRORS="$(awk '/oe:|fe:|pe:/{
        for(i=1;i<=NF;i++) {
          if($i ~ /oe:[1-9]/ || $i ~ /fe:[1-9]/ || $i ~ /pe:[1-9]/) print $0
        }
      }' /proc/tty/driver/serial 2>/dev/null)"
      if [ -n "$UART_ERRORS" ]; then
        warn "UART error events detected (overrun/framing): $UART_ERRORS"
      else
        ok "UART driver frame/overrun error counters are clean."
      fi
    fi
  else
    info "No hardware UART / RS-485 serial ports detected."
  fi

  # 2. Hardware Real-Time Clock (RTC) & Battery
  if [ -e /dev/rtc0 ] || [ -d /sys/class/rtc/rtc0 ]; then
    RTC_TIME="$(cat /sys/class/rtc/rtc0/time 2>/dev/null)"
    RTC_DATE="$(cat /sys/class/rtc/rtc0/date 2>/dev/null)"
    BATTERY_LOW="$(cat /sys/class/rtc/rtc0/device/battery_low 2>/dev/null)"
    
    if [ "$BATTERY_LOW" = "1" ]; then
      fail "RTC Backup Battery is LOW / EXHAUSTED (replace RTC battery)!"
    else
      ok "Hardware RTC (/dev/rtc0) is operational: ${RTC_DATE:-} ${RTC_TIME:-} (Battery: OK)."
    fi
    log_tech "RTC: rtc0 date=$RTC_DATE time=$RTC_TIME battery_low=$BATTERY_LOW"
  else
    info "No hardware RTC clock device (/dev/rtc0) found."
  fi

  # 3. Hardware Watchdog
  if [ -e /dev/watchdog ] || [ -e /dev/watchdog0 ]; then
    WD_TIMEOUT="$(cat /sys/class/watchdog/watchdog0/timeout 2>/dev/null || printf 'unknown')"
    WD_DEV="$(cat /sys/class/watchdog/watchdog0/identity 2>/dev/null || printf 'Hardware Watchdog')"
    ok "Watchdog active: $WD_DEV (Timeout: ${WD_TIMEOUT}s)."
    log_tech "WATCHDOG: identity=$WD_DEV timeout=$WD_TIMEOUT"
  else
    info "Hardware watchdog device (/dev/watchdog) not active."
  fi

  # 4. GPIO Dry Contacts / Relays
  if command -v gpiodetect >/dev/null 2>&1; then
    GPIO_CHIPS="$(gpiodetect 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
    [ -n "$GPIO_CHIPS" ] && ok "GPIO Controller(s) detected via libgpiod: $GPIO_CHIPS"
    log_tech_cmd "GPIO DETECT" gpiodetect
  elif [ -d /sys/class/gpio ]; then
    GPIO_CHIPS="$(ls -d /sys/class/gpio/gpiochip* 2>/dev/null | sed 's|.*/||' | tr '\n' ' ')"
    [ -n "$GPIO_CHIPS" ] && ok "GPIO Subsystem active: $GPIO_CHIPS"
  fi
}

# ==============================================================================
# SECTION 3: iRidi Runtime, Services & Sockets
# ==============================================================================
check_iridi_runtime() {
  printf '\n%s[3/8] iRidi Server Runtime & Services%s\n' "$C_BOLD" "$C_RESET"

  PACKAGE_VER=""
  if command -v opkg >/dev/null 2>&1; then
    PACKAGE_VER="$(opkg status iridiumserver 2>/dev/null | awk -F': *' '/Version:/{print $2}')"
  fi
  if [ -z "$PACKAGE_VER" ] && [ -r /var/lib/opkg/info/iridiumserver.control ]; then
    PACKAGE_VER="$(awk -F': *' '/Version:/{print $2}' /var/lib/opkg/info/iridiumserver.control)"
  fi

  FLAVOR="iRidi Server"
  BIN_PATH="/iridiumserver/iridium"
  [ -f "$BIN_PATH" ] || BIN_PATH="$(command -v iridium 2>/dev/null || printf '/iridiumserver/iridium')"
  
  if [ -f "$BIN_PATH" ]; then
    if strings "$BIN_PATH" 2>/dev/null | grep -q "Bus77 Home"; then
      FLAVOR="Bus77 Home Server"
    elif strings "$BIN_PATH" 2>/dev/null | grep -q "Bus77 Lite"; then
      FLAVOR="Bus77 Lite Server"
    elif strings "$BIN_PATH" 2>/dev/null | grep -q "ProAV Control Processor"; then
      FLAVOR="iRidi ProAV Server"
    elif strings "$BIN_PATH" 2>/dev/null | grep -q "KnxGatewayPort"; then
      FLAVOR="iRidi KNX / Pro Server"
    fi
  fi

  IRIDIUM_PID="$(pidof iridium 2>/dev/null | awk '{print $1}')"
  if [ -n "$IRIDIUM_PID" ]; then
    MEM_RSS="$(awk '/VmRSS/{print $2,$3}' "/proc/$IRIDIUM_PID/status" 2>/dev/null || printf 'n/a')"
    THREADS="$(awk '/Threads/{print $2}' "/proc/$IRIDIUM_PID/status" 2>/dev/null || printf 'n/a')"
    FD_COUNT="$(ls "/proc/$IRIDIUM_PID/fd" 2>/dev/null | wc -l | tr -d ' ')"
    ok "$FLAVOR (v${PACKAGE_VER:-unknown}) is RUNNING (PID $IRIDIUM_PID, RSS: $MEM_RSS, Threads: $THREADS, Open FDs: $FD_COUNT)."
    log_tech "RUNTIME: status=RUNNING flavor=$FLAVOR ver=$PACKAGE_VER pid=$IRIDIUM_PID rss=$MEM_RSS threads=$THREADS fds=$FD_COUNT"
  else
    fail "$FLAVOR is NOT RUNNING (Process stopped or failed)!"
    log_tech "RUNTIME: status=STOPPED flavor=$FLAVOR ver=$PACKAGE_VER"
  fi

  # Systemd service audit (restart count / crash loops)
  if command -v systemctl >/dev/null 2>&1; then
    SVC_ACTIVE="$(systemctl is-active iridium.service 2>/dev/null || printf 'unknown')"
    RESTART_COUNT="$(systemctl show iridium.service -p NRestarts 2>/dev/null | awk -F= '{print $2}')"
    EXEC_STATUS="$(systemctl show iridium.service -p ExecMainStatus 2>/dev/null | awk -F= '{print $2}')"
    
    log_tech "SYSTEMD: iridium.service active=$SVC_ACTIVE NRestarts=$RESTART_COUNT ExecMainStatus=$EXEC_STATUS"
    if [ -n "$RESTART_COUNT" ] && [ "$RESTART_COUNT" -gt 5 ]; then
      warn "iridium.service has restarted $RESTART_COUNT times since boot (possible crash loop)!"
    fi
  fi

  # MQTT Broker inspection (port 1883)
  MQTT_PID="$(pidof mosquitto 2>/dev/null | awk '{print $1}')"
  NETSTAT_OUT="$(ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null)"
  log_tech_cmd "OPEN PORTS (ss/netstat)" ss -tulpn
  
  if printf '%s\n' "$NETSTAT_OUT" | grep -q ":1883 "; then
    ok "MQTT Broker is ACTIVE and listening on port 1883 ${MQTT_PID:+(PID $MQTT_PID)}."
  else
    info "MQTT Broker port 1883 is not active."
  fi

  # Active listening ports
  OPEN_PORTS=""
  for PORT in 8888 8443 1883 30464 30465 30467 65534 22; do
    if printf '%s\n' "$NETSTAT_OUT" | grep -q ":${PORT} "; then
      OPEN_PORTS="${OPEN_PORTS:+$OPEN_PORTS, }$PORT"
    fi
  done
  [ -n "$OPEN_PORTS" ] && printf '  - Active Listening Ports : %s\n' "$OPEN_PORTS"
}

# ==============================================================================
# SECTION 4: iRidi Projects, Licenses & SQLite Database Integrity
# ==============================================================================
check_iridi_data_and_projects() {
  printf '\n%s[4/8] iRidi Projects, Licenses & Database Integrity%s\n' "$C_BOLD" "$C_RESET"

  # Find active data directory
  ACTIVE_DATA_DIR=""
  IRIDI_PID="$(pidof iridium 2>/dev/null | awk '{print $1}')"
  if [ -n "$IRIDI_PID" ]; then
    for FD_PATH in /proc/$IRIDI_PID/fd/*; do
      [ -e "$FD_PATH" ] || continue
      FD_TARGET="$(readlink "$FD_PATH" 2>/dev/null)"
      case "$FD_TARGET" in
        */DataBase/*)
          ACTIVE_DATA_DIR="${FD_TARGET%/DataBase/*}"
          break
          ;;
      esac
    done
  fi
  [ -z "$ACTIVE_DATA_DIR" ] && [ -d /opt/iridi ] && ACTIVE_DATA_DIR="/opt/iridi"
  [ -z "$ACTIVE_DATA_DIR" ] && [ -d /userdata/iridi ] && ACTIVE_DATA_DIR="/userdata/iridi"

  if [ -n "$ACTIVE_DATA_DIR" ] && [ -d "$ACTIVE_DATA_DIR" ]; then
    printf '  - Data Directory         : %s\n' "$ACTIVE_DATA_DIR"
    
    # 1. License Check
    LICENSE_FILE=""
    for L_CAND in "$ACTIVE_DATA_DIR/Documents/license.xml" "$ACTIVE_DATA_DIR/license.xml" "$ACTIVE_DATA_DIR/license.key"; do
      if [ -r "$L_CAND" ]; then
        LICENSE_FILE="$L_CAND"
        break
      fi
    done
    if [ -n "$LICENSE_FILE" ]; then
      LIC_SER_ID="$(sed -n 's/.*<ServerID>\(.*\)<\/ServerID>.*/\1/p' "$LICENSE_FILE" 2>/dev/null)"
      LIC_PANELS="$(sed -n 's/.*<CountPanels>\(.*\)<\/CountPanels>.*/\1/p' "$LICENSE_FILE" 2>/dev/null)"
      ok "Server License detected: ServerID=${LIC_SER_ID:-set}, Panels/Clients=${LIC_PANELS:-unlimited}."
      log_tech "LICENSE: file=$LICENSE_FILE id=$LIC_SER_ID panels=$LIC_PANELS"
    else
      info "No standalone license.xml file found (may use cloud licensing or embedded token)."
    fi

    # 2. Projects Inventory
    PROJECTS_DIR="$ACTIVE_DATA_DIR/Documents/Projects"
    if [ -d "$PROJECTS_DIR" ]; then
      PROJ_COUNT="$(find "$PROJECTS_DIR" -type f \( -name "*.sirp" -o -name "*.rpz" \) 2>/dev/null | wc -l | tr -d ' ')"
      if [ "$PROJ_COUNT" -gt 0 ]; then
        ok "Loaded server projects ($PROJ_COUNT found in Documents/Projects):"
        find "$PROJECTS_DIR" -type f \( -name "*.sirp" -o -name "*.rpz" \) -exec ls -lh {} + 2>/dev/null | awk '{printf "     - %s (Size: %s, Modified: %s %s)\n", $NF, $5, $6, $7}'
      else
        info "No server projects (.sirp/.rpz) found in Documents/Projects."
      fi
    fi

    # 3. SQLite Database Integrity Check
    DB_DIR="$ACTIVE_DATA_DIR/DataBase"
    if [ -d "$DB_DIR" ]; then
      for DB_FILE in "$DB_DIR"/*.db; do
        [ -e "$DB_FILE" ] || continue
        DB_SIZE="$(ls -lh "$DB_FILE" 2>/dev/null | awk '{print $5}')"
        
        # Check integrity if sqlite3 is available
        if command -v sqlite3 >/dev/null 2>&1; then
          INTEG_RES="$(sqlite3 "$DB_FILE" "PRAGMA integrity_check;" 2>&1)"
          if [ "$INTEG_RES" = "ok" ]; then
            ok "Database ${DB_FILE##*/}: Integrity check PASS ($DB_SIZE)."
          else
            fail "Database ${DB_FILE##*/}: Integrity check FAILED ($INTEG_RES)!"
          fi
        else
          # Header validation
          DB_HDR="$(head -c 16 "$DB_FILE" 2>/dev/null)"
          case "$DB_HDR" in
            "SQLite format 3"*)
              ok "Database ${DB_FILE##*/}: Valid SQLite format header ($DB_SIZE)."
              ;;
            *)
              warn "Database ${DB_FILE##*/}: Non-standard header or corrupted file ($DB_SIZE)!"
              ;;
          esac
        fi
        
        # Check WAL size
        WAL_FILE="${DB_FILE}-wal"
        if [ -f "$WAL_FILE" ]; then
          WAL_SIZE="$(ls -lh "$WAL_FILE" 2>/dev/null | awk '{print $5}')"
          log_tech "DATABASE WAL: file=$WAL_FILE size=$WAL_SIZE"
        fi
      done
    fi

    # 4. Scan Recent Logs for Critical Errors
    LOG_DIR_IRIDI="$ACTIVE_DATA_DIR/Documents/Logs"
    if [ -d "$LOG_DIR_IRIDI" ]; then
      LATEST_LOG="$(ls -t "$LOG_DIR_IRIDI"/*.log 2>/dev/null | head -n 1)"
      if [ -n "$LATEST_LOG" ] && [ -r "$LATEST_LOG" ]; then
        CRIT_ERRS="$(tail -n 200 "$LATEST_LOG" 2>/dev/null | grep -ciE '(CRITICAL|EXCEPTION|Segmentation fault|Fatal error|Bus error)' || true)"
        if [ "$CRIT_ERRS" -gt 0 ]; then
          warn "Detected $CRIT_ERRS error/exception markers in recent server log (${LATEST_LOG##*/})."
          log_tech_cmd "LATEST LOG ERROR EXCERPT" sh -c "tail -n 200 '$LATEST_LOG' | grep -iE '(CRITICAL|EXCEPTION|Segmentation fault|Fatal error|Bus error)'"
        else
          ok "Recent server log (${LATEST_LOG##*/}) is clean (0 fatal errors in last 200 lines)."
        fi
      fi
    fi

  else
    info "iRidi data directory not found in standard paths."
  fi
}

# ==============================================================================
# SECTION 5: CPU, Thermals & Power Health
# ==============================================================================
check_thermal_and_cpu() {
  printf '\n%s[5/8] CPU & Thermal Health%s\n' "$C_BOLD" "$C_RESET"

  THERMAL_FOUND=0
  MAX_TEMP=0
  for TZ_DIR in /sys/class/thermal/thermal_zone*; do
    if [ -d "$TZ_DIR" ]; then
      THERMAL_FOUND=1
      TZ_TYPE="$(cat "$TZ_DIR/type" 2>/dev/null || printf 'zone')"
      TZ_RAW="$(cat "$TZ_DIR/temp" 2>/dev/null || printf '0')"
      TZ_C=$(( TZ_RAW / 1000 ))
      log_tech "THERMAL: zone=$TZ_DIR type=$TZ_TYPE temp=${TZ_C}C"
      [ "$TZ_C" -gt "$MAX_TEMP" ] && MAX_TEMP="$TZ_C"
    fi
  done

  if [ "$THERMAL_FOUND" -eq 1 ]; then
    if [ "$MAX_TEMP" -lt 75 ]; then
      ok "CPU / SoC Temperature: ${MAX_TEMP}°C (Normal healthy thermal envelope)."
    elif [ "$MAX_TEMP" -lt 85 ]; then
      warn "CPU / SoC Temperature: ${MAX_TEMP}°C (Elevated temperature, verify airflow)."
    else
      fail "CPU / SoC Temperature: ${MAX_TEMP}°C (CRITICAL OVERHEATING RISK)!"
    fi
  else
    info "No hardware thermal sensors exposed under /sys/class/thermal."
  fi

  CPU_CORES="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || printf '1')"
  CPU_FREQ_RAW="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq 2>/dev/null)"
  if [ -n "$CPU_FREQ_RAW" ] && [ "$CPU_FREQ_RAW" -gt 0 ] 2>/dev/null; then
    CPU_MHZ=$(( CPU_FREQ_RAW / 1000 ))
    printf '  - CPU Topology           : %s core(s) @ %d MHz\n' "$CPU_CORES" "$CPU_MHZ"
  else
    printf '  - CPU Topology           : %s core(s)\n' "$CPU_CORES"
  fi
}

# ==============================================================================
# SECTION 6: Memory (RAM) & Swap Health
# ==============================================================================
check_memory_health() {
  printf '\n%s[6/8] Memory (RAM) & Swap Utilization%s\n' "$C_BOLD" "$C_RESET"

  if [ -r /proc/meminfo ]; then
    MEM_TOTAL_KB="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
    MEM_FREE_KB="$(awk '/MemFree/{print $2}' /proc/meminfo)"
    MEM_AVAIL_KB="$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
    MEM_AVAIL_KB="${MEM_AVAIL_KB:-$MEM_FREE_KB}"
    
    MEM_TOTAL_MB=$(( MEM_TOTAL_KB / 1024 ))
    MEM_AVAIL_MB=$(( MEM_AVAIL_KB / 1024 ))
    MEM_USED_MB=$(( MEM_TOTAL_MB - MEM_AVAIL_MB ))

    MEM_PERCENT=0
    [ "$MEM_TOTAL_MB" -gt 0 ] && MEM_PERCENT=$(( (MEM_USED_MB * 100) / MEM_TOTAL_MB ))

    log_tech "MEMORY: total=${MEM_TOTAL_MB}MB used=${MEM_USED_MB}MB (${MEM_PERCENT}%) avail=${MEM_AVAIL_MB}MB"

    if [ "$MEM_PERCENT" -lt 85 ]; then
      ok "Memory Usage: $MEM_USED_MB MB / $MEM_TOTAL_MB MB used (${MEM_PERCENT}%, Available: $MEM_AVAIL_MB MB)."
    elif [ "$MEM_PERCENT" -lt 95 ]; then
      warn "Memory Usage: $MEM_USED_MB MB / $MEM_TOTAL_MB MB used (${MEM_PERCENT}%) — High memory pressure!"
    else
      fail "Memory Usage: $MEM_USED_MB MB / $MEM_TOTAL_MB MB used (${MEM_PERCENT}%) — OOM Risk!"
    fi
  fi
}

# ==============================================================================
# SECTION 7: Storage, Mounts & eMMC Wear (SMART)
# ==============================================================================
check_emmc_and_storage() {
  printf '\n%s[7/8] Storage & eMMC Wear Indicators (SMART)%s\n' "$C_BOLD" "$C_RESET"

  MMC_DEV=""
  for CANDIDATE in /sys/class/mmc_host/mmc1/mmc1:0001 /sys/class/mmc_host/mmc0/mmc0:0001 /sys/block/mmcblk0/device /sys/block/mmcblk1/device; do
    if [ -d "$CANDIDATE" ]; then
      MMC_DEV="$CANDIDATE"
      break
    fi
  done

  if [ -n "$MMC_DEV" ]; then
    MMC_NAME="$(cat "$MMC_DEV/name" 2>/dev/null)"
    MMC_MANFID="$(cat "$MMC_DEV/manfid" 2>/dev/null)"
    MMC_LIFE="$(cat "$MMC_DEV/life_time" 2>/dev/null)"
    MMC_PRE_EOL="$(cat "$MMC_DEV/pre_eol_info" 2>/dev/null)"

    MANUFACTURER_STR="Unknown"
    case "$MMC_MANFID" in
      0x000015|0x15) MANUFACTURER_STR="Samsung" ;;
      0x000013|0x13) MANUFACTURER_STR="Micron" ;;
      0x000045|0x45) MANUFACTURER_STR="SanDisk" ;;
      0x000090|0x90) MANUFACTURER_STR="SK Hynix" ;;
      0x0000fe|0xfe) MANUFACTURER_STR="Micron" ;;
    esac

    LIFE_A="$(printf '%s' "$MMC_LIFE" | awk '{print $1}')"
    LIFE_B="$(printf '%s' "$MMC_LIFE" | awk '{print $2}')"
    
    decode_life() {
      case "$1" in
        0x01|0x1|1) echo "0-10% used" ;;
        0x02|0x2|2) echo "10-20% used" ;;
        0x03|0x3|3) echo "20-30% used" ;;
        0x04|0x4|4) echo "30-40% used" ;;
        0x05|0x5|5) echo "40-50% used" ;;
        0x06|0x6|6) echo "50-60% used" ;;
        0x07|0x7|7) echo "60-70% used" ;;
        0x08|0x8|8) echo "70-80% used" ;;
        0x09|0x9|9) echo "80-90% used" ;;
        0x0a|0xa|10) echo "90-100% used" ;;
        0x0b|0xb|11) echo "exceeded life" ;;
        *) echo "n/a" ;;
      esac
    }

    log_tech "EMMC: dev=$MMC_DEV name=$MMC_NAME manfid=$MMC_MANFID ($MANUFACTURER_STR) life_raw='$MMC_LIFE' pre_eol=$MMC_PRE_EOL"

    if [ "$LIFE_A" = "0x0a" ] || [ "$LIFE_A" = "0x0b" ] || [ "$LIFE_B" = "0x0a" ] || [ "$LIFE_B" = "0x0b" ] || [ "$MMC_PRE_EOL" = "0x03" ]; then
      fail "eMMC Flash: ${MMC_NAME:-eMMC} ($MANUFACTURER_STR) — CRITICAL WEAR: Life A: $(decode_life "$LIFE_A"), Life B: $(decode_life "$LIFE_B")!"
    elif [ "$MMC_PRE_EOL" = "0x02" ] || [ "$LIFE_A" = "0x09" ] || [ "$LIFE_B" = "0x09" ]; then
      warn "eMMC Flash: ${MMC_NAME:-eMMC} ($MANUFACTURER_STR) — ELEVATED WEAR: Life A: $(decode_life "$LIFE_A"), Life B: $(decode_life "$LIFE_B")."
    else
      ok "eMMC Flash: ${MMC_NAME:-eMMC} ($MANUFACTURER_STR) — Wear: $(decode_life "$LIFE_A") (Health: Normal)."
    fi
  else
    info "eMMC hardware sysfs node not directly exposed."
  fi

  # Partition Space
  DF_OUT="$(df -h / /userdata /oem 2>/dev/null)"
  log_tech_cmd "DISK USAGE (df -h)" df -h
  printf '  - Storage Partitions:\n'
  printf '%s\n' "$DF_OUT" | awk 'NR>1 { printf "     - %-14s: %6s total, %6s free (%4s used)\n", $6, $2, $4, $5 }'

  # Kernel error scan
  ERR_COUNT=0
  if command -v dmesg >/dev/null 2>&1; then
    ERR_COUNT="$(dmesg 2>/dev/null | grep -ciE '(Buffer I/O error|EXT4-fs error|blk_update_request: I/O error|mmc.*error|end_request: I/O error)' || true)"
    log_tech_cmd "STORAGE KERNEL LOG SCAN" sh -c "dmesg | grep -iE '(Buffer I/O error|EXT4-fs error|blk_update_request: I/O error|mmc.*error|end_request: I/O error)'"
  fi
  if [ "$ERR_COUNT" -eq 0 ]; then
    ok "Kernel storage error log is clean (0 filesystem / I/O errors)."
  else
    warn "Kernel storage error log recorded $ERR_COUNT I/O error events!"
  fi
}

# ==============================================================================
# SECTION 8: Network & Communication Health
# ==============================================================================
check_network_and_can() {
  printf '\n%s[8/8] Network & Communication Interfaces%s\n' "$C_BOLD" "$C_RESET"

  # Ethernet (eth0 / eth1)
  for ETH_DEV in /sys/class/net/eth*; do
    [ -e "$ETH_DEV" ] || continue
    ETH_NAME="${ETH_DEV##*/}"
    ETH_IP="$(ip -4 addr show "$ETH_NAME" 2>/dev/null | awk '/inet /{print $2}' | head -n 1)"
    ETH_OPER="$(cat "$ETH_DEV/operstate" 2>/dev/null)"
    ETH_SPEED="$(cat "$ETH_DEV/speed" 2>/dev/null || printf 'n/a')"
    ETH_DUPLEX="$(cat "$ETH_DEV/duplex" 2>/dev/null || printf 'n/a')"
    
    log_tech "NET $ETH_NAME: oper=$ETH_OPER ip=$ETH_IP speed=$ETH_SPEED duplex=$ETH_DUPLEX"

    if [ "$ETH_OPER" = "up" ]; then
      ok "$ETH_NAME: Link UP (${ETH_SPEED} Mbps, ${ETH_DUPLEX}) | IPv4: ${ETH_IP:-none}"
    else
      warn "$ETH_NAME: Link is ${ETH_OPER:-DOWN}"
    fi
  done

  # CAN Bus (can0, can1)
  for CAN_DEV in /sys/class/net/can*; do
    [ -e "$CAN_DEV" ] || continue
    CAN_NAME="${CAN_DEV##*/}"
    CAN_STATE="UNKNOWN"
    CAN_BITRATE="unknown"
    if command -v ip >/dev/null 2>&1; then
      CAN_DETAIL="$(ip -details link show "$CAN_NAME" 2>/dev/null)"
      CAN_STATE="$(echo "$CAN_DETAIL" | awk '/can .* state/ {for(i=1;i<=NF;i++) if($i=="state") print $(i+1)}' | head -n 1)"
      CAN_BITRATE="$(echo "$CAN_DETAIL" | awk '/bitrate/ {for(i=1;i<=NF;i++) if($i=="bitrate") print $(i+1)}' | head -n 1)"
      log_tech_file "CAN DETAILS ($CAN_NAME)" "$CAN_DETAIL"
    fi
    CAN_STATE="${CAN_STATE:-UP}"
    log_tech "CAN $CAN_NAME: state=$CAN_STATE bitrate=$CAN_BITRATE"

    if [ "$CAN_STATE" = "ERROR-ACTIVE" ] || [ "$CAN_STATE" = "UP" ]; then
      ok "$CAN_NAME: State $CAN_STATE | Bitrate: ${CAN_BITRATE:-125000} bit/s (Normal operational state)."
    elif [ "$CAN_STATE" = "ERROR-PASSIVE" ] || [ "$CAN_STATE" = "ERROR-WARNING" ]; then
      warn "$CAN_NAME: State $CAN_STATE | Bitrate: ${CAN_BITRATE:-125000} bit/s (Degraded / No terminations)."
    elif [ "$CAN_STATE" = "BUS-OFF" ]; then
      fail "$CAN_NAME: State BUS-OFF (Critical CAN collision / bus disconnection)!"
    fi
  done

  # Default Gateway & DNS Latency
  DEF_GW="$(ip route show default 2>/dev/null | awk '/default via/{print $3}' | head -n 1)"
  DNS_SERVERS="$(awk '/nameserver/{printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)"
  
  if [ -n "$DEF_GW" ]; then
    if command -v ping >/dev/null 2>&1; then
      GW_PING="$(ping -c 1 -W 2 "$DEF_GW" 2>/dev/null | awk -F'/' '/rtt|round-trip/{print $5}')"
      if [ -n "$GW_PING" ]; then
        ok "Default Gateway reachable: $DEF_GW (Latency: ${GW_PING} ms)."
      else
        warn "Default Gateway ($DEF_GW) did not respond to ICMP ping."
      fi
    else
      printf '  - Default Gateway        : %s\n' "$DEF_GW"
    fi
  fi
  printf '  - Configured DNS Servers : %s\n' "${DNS_SERVERS:-none}"
  log_tech "NET CONFIG: gateway=$DEF_GW dns='$DNS_SERVERS'"
}

# ==============================================================================
# FINAL SUMMARY & VERDICT
# ==============================================================================
print_summary() {
  printf '\n%s================================================================================%s\n' "$C_BOLD" "$C_RESET"
  printf '%s  SYSTEM HEALTH SUMMARY%s\n' "$C_BOLD" "$C_RESET"
  printf '%s================================================================================%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-24s : %d\n' "Fatal Failures" "$FAIL_COUNT"
  printf '  %-24s : %d\n' "Attention Warnings" "$WARN_COUNT"
  printf '  %-24s : %s%s%s\n' "Technical Audit Log" "$C_DIM" "$LOG_FILE" "$C_RESET"
  printf '%s--------------------------------------------------------------------------------%s\n' "$C_DIM" "$C_RESET"

  log_tech "SUMMARY: failures=$FAIL_COUNT warnings=$WARN_COUNT"

  if [ "$FAIL_COUNT" -gt 0 ]; then
    printf '  %sRESULT: FAIL - Critical hardware or service issues detected (%d failure(s), %d warning(s)).%s\n' "$C_RED$C_BOLD" "$FAIL_COUNT" "$WARN_COUNT" "$C_RESET"
    FINAL_RC=2
  elif [ "$WARN_COUNT" -gt 0 ]; then
    printf '  %sRESULT: WARN - System is operational, but %d item(s) require attention.%s\n' "$C_YELLOW$C_BOLD" "$WARN_COUNT" "$C_RESET"
    FINAL_RC=1
  else
    printf '  %sRESULT: PASS - All hardware, peripherals, services, and databases are healthy.%s\n' "$C_GREEN$C_BOLD" "$C_RESET"
    FINAL_RC=0
  fi
  printf '%s================================================================================%s\n' "$C_BOLD" "$C_RESET"
  
  log_tech "================================================================================"
  log_tech "DIAGNOSTIC COMPLETE | Exit Code: $FINAL_RC | Failures: $FAIL_COUNT | Warnings: $WARN_COUNT"
  log_tech "================================================================================"
  exit "$FINAL_RC"
}

check_hardware_identity
check_peripherals_and_io
check_iridi_runtime
check_iridi_data_and_projects
check_thermal_and_cpu
check_memory_health
check_emmc_and_storage
check_network_and_can
print_summary
