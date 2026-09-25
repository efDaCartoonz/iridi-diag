#!/bin/sh

# iRidi CAN Bus & Bus77 Diagnostics
# Comprehensive SocketCAN health, active Bus77 device discovery,
# firmware profile verification, gateway configuration, and traffic sampling.
#
# Usage: sh check_can_bus.sh [--interface can0|all] [--duration SECONDS] [--passive] [--scan-only] [--json]

case "${1:-}" in
  -h|--help)
    printf 'Usage: sh %s [options]\n\n' "${0##*/}"
    printf 'Options:\n'
    printf '  --interface IFACE         SocketCAN interface (e.g. can0, can1, or all; default: all)\n'
    printf '  --duration SECONDS        Duration of passive traffic sampling in seconds (default: 15)\n'
    printf '  --passive                 Skip active discovery (only passive controller & traffic health)\n'
    printf '  --scan-only, --inventory  Discover Bus77 devices/profiles and exit without traffic sample\n'
    printf '  --json                    Output discovered devices in structured JSON format\n'
    printf '  -h, --help                Show this help message and exit\n\n'
    printf 'Description:\n'
    printf '  Performs non-disruptive diagnostics of SocketCAN interfaces and Bus77 network:\n'
    printf '  1. Controller & driver state, bitrates, error counters (bus-off, passive, arbit-lost)\n'
    printf '  2. Active read-only Bus77 device discovery (Search 0x03 & Device Info 0x04 requests)\n'
    printf '  3. Complete firmware profiles, hardware IDs, models, and channel configurations\n'
    printf '  4. iRidi CAN gateway process, data directory, JSON config, and UDP listener status\n'
    printf '  5. Passive traffic sampling with packet rate, error deltas, and bus activity analysis\n'
    exit 0
    ;;
esac

TOOL_VERSION="2.4"
PASSIVE_ONLY=0
SCAN_ONLY=0
JSON_OUTPUT=0
REQUESTED_INTERFACE="all"
SAMPLE_SECONDS=15
WARNINGS=0
FAILURES=0
WORK_DIR=""
CAPTURE_PID=""
SCANNER_CAN_ID=65534
SCANNER_LID=254

# Setup logging directory & technical log file
CURRENT_DIR="$(pwd 2>/dev/null || printf '.')"
LOG_DIR="${IRIDI_DIAG_LOG_DIR:-$CURRENT_DIR}"
if [ ! -d "$LOG_DIR" ] || [ ! -w "$LOG_DIR" ]; then
  LOG_DIR="${TMPDIR:-/tmp}"
fi

HOST_LABEL="$(hostname 2>/dev/null || printf server)"
HOST_LABEL="$(printf '%s' "$HOST_LABEL" | tr -c 'A-Za-z0-9._-' '_')"
[ -n "$HOST_LABEL" ] || HOST_LABEL="server"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S' 2>/dev/null || printf '00000000_000000')"
LOG_FILE="${LOG_DIR}/can_diagnostic_${HOST_LABEL}_${TIMESTAMP}_$$.log"

# Open File Descriptor 3 for technical log
if ! exec 3>>"$LOG_FILE" 2>/dev/null; then
  LOG_FILE="${TMPDIR:-/tmp}/can_diagnostic_${HOST_LABEL}_${TIMESTAMP}_$$.log"
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

ok() {
  printf '  %s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$1"
  log_tech "OK: $1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '  %s[ATTENTION]%s %s\n' "$C_YELLOW" "$C_RESET" "$1"
  log_tech "ATTENTION: $1"
}

fail() {
  FAILURES=$((FAILURES + 1))
  printf '  %s[NOT OK]%s %s\n' "$C_RED" "$C_RESET" "$1"
  log_tech "FAIL: $1"
}

info() {
  printf '  %s[INFO]%s %s\n' "$C_CYAN" "$C_RESET" "$1"
  log_tech "INFO: $1"
}

cleanup() {
  if [ -n "$CAPTURE_PID" ]; then
    kill -INT "$CAPTURE_PID" 2>/dev/null
    wait "$CAPTURE_PID" 2>/dev/null
  fi
  [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
  exec 3>&- 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

# Parse command-line arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --passive) PASSIVE_ONLY=1 ;;
    --scan-only|--inventory) SCAN_ONLY=1 ;;
    --json) JSON_OUTPUT=1 ;;
    --interface)
      [ "$#" -ge 2 ] || { printf 'RESULT: FAIL - missing interface argument.\n'; exit 2; }
      shift
      REQUESTED_INTERFACE="${1:-}"
      ;;
    --duration)
      [ "$#" -ge 2 ] || { printf 'RESULT: FAIL - missing duration argument.\n'; exit 2; }
      shift
      SAMPLE_SECONDS="${1:-}"
      ;;
    -h|--help)
      exit 0
      ;;
    *)
      printf '[NOT OK] Unknown argument: %s\n' "$1"
      printf 'RESULT: FAIL - NOT OK: invalid command-line arguments.\n'
      exit 2
      ;;
  esac
  shift
done

case "$SAMPLE_SECONDS" in
  ''|*[!0-9]*)
    printf '[NOT OK] Duration must be a whole number of seconds: %s\n' "$SAMPLE_SECONDS"
    printf 'RESULT: FAIL - NOT OK: invalid sample duration.\n'
    exit 2
    ;;
esac
if [ "$SAMPLE_SECONDS" -lt 1 ] || [ "$SAMPLE_SECONDS" -gt 3600 ]; then
  printf '[NOT OK] Duration must be between 1 and 3600 seconds.\n'
  printf 'RESULT: FAIL - NOT OK: invalid sample duration.\n'
  exit 2
fi

case "$REQUESTED_INTERFACE" in
  all) : ;;
  ''|*[!A-Za-z0-9_.:-]*)
    printf '[NOT OK] Invalid interface name: %s\n' "$REQUESTED_INTERFACE"
    printf 'RESULT: FAIL - NOT OK: invalid CAN interface name.\n'
    exit 2
    ;;
esac

# Create temporary work directory
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/iridi-can-diag.XXXXXX" 2>/dev/null)"
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ]; then
  WORK_DIR="${TMPDIR:-/tmp}/iridi-can-diag.$$"
  mkdir -m 700 "$WORK_DIR" || { WORK_DIR=""; exit 2; }
fi

INVENTORY_FILE="$WORK_DIR/inventory.txt"
: >"$INVENTORY_FILE"

# Log Initial Header
log_tech "================================================================================"
log_tech "iRidi CAN Bus & Bus77 Diagnostic - Technical Log"
log_tech "Version: $TOOL_VERSION | Started: $STARTED_AT"
log_tech "Host: $HOSTNAME_VAL | Kernel: $(uname -srm 2>/dev/null)"
log_tech "Log File: $LOG_FILE"
log_tech "================================================================================"

# Helpers for discovery
detect_interfaces() {
  for CAN_PATH in /sys/class/net/*; do
    [ -e "$CAN_PATH" ] || continue
    [ "$(cat "$CAN_PATH/type" 2>/dev/null)" = "280" ] || continue
    printf '%s\n' "${CAN_PATH##*/}"
  done
}

crc16_hex() {
  awk '
    BEGIN {
      crc = 65535
      for (i = 1; i < ARGC; i++) {
        byte = ARGV[i] + 0
        crc = xor(crc, byte)
        for (bit = 0; bit < 8; bit++) {
          if (and(crc, 1)) crc = xor(rshift(crc, 1), 40961)
          else crc = rshift(crc, 1)
        }
      }
      printf "%02X%02X", and(crc, 255), and(rshift(crc, 8), 255)
      exit
    }
  ' "$@"
}

start_capture() {
  _IFACE="$1"
  _OUT="$2"
  candump -x -e "$_IFACE" >"$_OUT" 2>&1 &
  CAPTURE_PID=$!
  sleep 1
  kill -0 "$CAPTURE_PID" 2>/dev/null || return 1
}

stop_capture() {
  _WAIT_TIME="${1:-5}"
  sleep "$_WAIT_TIME"
  if [ -n "$CAPTURE_PID" ]; then
    kill -INT "$CAPTURE_PID" 2>/dev/null
    wait "$CAPTURE_PID" 2>/dev/null
    CAPTURE_PID=""
  fi
}

send_search_request() {
  _IFACE="$1"
  _SEARCH_CRC="$(crc16_hex 17 3 86 52 255)"
  cansend "$_IFACE" 1FFFDA00#750807FE11035634 || return 1
  cansend "$_IFACE" "1FFFDA01#FF$_SEARCH_CRC" || return 1
}

send_device_info_request() {
  _IFACE="$1"
  _TARGET_LID="$2"
  _TARGET_LID_HEX="$(awk -v value="$_TARGET_LID" 'BEGIN { printf "%02X", value }')"
  _REQ_TID_LOW="$_TARGET_LID"
  _REQ_TID_HIGH=80
  _REQ_CRC="$(crc16_hex 17 4 "$_REQ_TID_LOW" "$_REQ_TID_HIGH")"
  _REQ_CAN_ID="$(awk -v sender="$SCANNER_CAN_ID" -v address="$_TARGET_LID" '
    BEGIN { printf "%08X", lshift(sender, 13) + lshift(7, 10) + lshift(address, 1) }
  ')"
  _REQ_CAN_ID_END="$(awk -v value="$_REQ_CAN_ID" '
    function hex_digit(c) { return index("0123456789ABCDEF", c) - 1 }
    function hex_number(text, i, value) {
      value = 0
      for (i = 1; i <= length(text); i++) value = (value * 16) + hex_digit(substr(text, i, 1))
      return value
    }
    BEGIN { printf "%08X", hex_number(value) + 1 }
  ')"
  cansend "$_IFACE" "${_REQ_CAN_ID}#7D0806FE${_TARGET_LID_HEX}1104${_TARGET_LID_HEX}" || return 1
  cansend "$_IFACE" "${_REQ_CAN_ID_END}#50${_REQ_CRC}" || return 1
}

parse_search_capture() {
  _CAP="$1"
  _OUT="$2"
  awk -v scanner_lid="$SCANNER_LID" '
    function hex_digit(c) { return index("0123456789ABCDEF", toupper(c)) - 1 }
    function hex_number(text, i, value) {
      value = 0
      for (i = 1; i <= length(text); i++) value = (value * 16) + hex_digit(substr(text, i, 1))
      return value
    }
    function crc_step(crc, byte, bit) {
      crc = xor(crc, byte)
      for (bit = 0; bit < 8; bit++) {
        if (and(crc, 1)) crc = xor(rshift(crc, 1), 40961)
        else crc = rshift(crc, 1)
      }
      return crc
    }
    $2 == "RX" {
      if (length($5) != 8 || toupper($5) !~ /^[0-9A-F]+$/) next
      ext_id = hex_number($5)
      if (ext_id > 536870911) next
      if (and(rshift(ext_id, 1), 255) != scanner_lid) next
      sender = and(rshift(ext_id, 13), 65535)
      stream = sprintf("%04X:%d", sender, and(rshift(ext_id, 10), 7))
      key = stream ":" generation[stream]
      for (field = 7; field <= NF; field++) {
        if (length($field) == 2 && toupper($field) ~ /^[0-9A-F]+$/) {
          data[key, length_by_key[key]++] = hex_number($field)
        }
      }
      if (and(ext_id, 1)) { complete[key] = 1; generation[stream]++ }
    }
    END {
      for (key in length_by_key) {
        if (!complete[key]) continue
        packet_length = length_by_key[key]
        if (packet_length < 12 || and(data[key, 0], 119) != 117) continue
        flags = data[key, 1]
        body_size = data[key, 2]
        cursor = 3
        if (and(flags, 128)) cursor++
        if (and(flags, 64)) cursor++
        source_lid = data[key, cursor++]
        if (and(flags, 32)) cursor++
        if (and(data[key, 0], 8)) cursor++
        body = cursor
        if (packet_length != body + body_size || body_size < 7) continue
        crc = 65535
        for (position = body; position < body + body_size - 2; position++) crc = crc_step(crc, data[key, position])
        expected_crc = data[key, body + body_size - 2] + (data[key, body + body_size - 1] * 256)
        if (crc != expected_crc) continue
        if (and(flags, 7) || data[key, body] != 145 || data[key, body + 1] != 3) continue
        if (data[key, body + 2] != 86 || data[key, body + 3] != 52) continue
        pointer = body + 4
        group = data[key, pointer++]
        hwid = ""
        while (pointer < body + body_size - 2 && data[key, pointer] != 0) {
          hwid = hwid sprintf("%c", data[key, pointer++])
        }
        if (pointer >= body + body_size - 2) continue
        pointer++
        if (pointer + 8 > body + body_size - 2) continue
        event = data[key, pointer++]
        device_flags = data[key, pointer++]
        gsub(/[|[:cntrl:]]/, "/", hwid)
        printf "%d|%s|%s|%d|%d|%d\n", source_lid, substr(key, 1, 4), hwid, group, device_flags, event
      }
    }
  ' "$_CAP" | sort -nu >"$_OUT"
}

parse_info_capture() {
  _INFO_CAP="$1"
  _SEARCH_RES="$2"
  _OUT="$3"
  awk -v scanner_lid="$SCANNER_LID" '
    function hex_digit(c) { return index("0123456789ABCDEF", toupper(c)) - 1 }
    function hex_number(text, i, value) {
      value = 0
      for (i = 1; i <= length(text); i++) value = (value * 16) + hex_digit(substr(text, i, 1))
      return value
    }
    function crc_step(crc, byte, bit) {
      crc = xor(crc, byte)
      for (bit = 0; bit < 8; bit++) {
        if (and(crc, 1)) crc = xor(rshift(crc, 1), 40961)
        else crc = rshift(crc, 1)
      }
      return crc
    }
    function u32(key, pointer) {
      return data[key, pointer] + data[key, pointer + 1] * 256 + data[key, pointer + 2] * 65536 + data[key, pointer + 3] * 16777216
    }
    $2 == "RX" {
      if (length($5) != 8 || toupper($5) !~ /^[0-9A-F]+$/) next
      ext_id = hex_number($5)
      if (ext_id > 536870911) next
      if (and(rshift(ext_id, 1), 255) != scanner_lid) next
      sender = and(rshift(ext_id, 13), 65535)
      stream = sprintf("%04X:%d", sender, and(rshift(ext_id, 10), 7))
      key = stream ":" generation[stream]
      for (field = 7; field <= NF; field++) {
        if (length($field) == 2 && toupper($field) ~ /^[0-9A-F]+$/) {
          data[key, length_by_key[key]++] = hex_number($field)
        }
      }
      if (and(ext_id, 1)) { complete[key] = 1; generation[stream]++ }
    }
    END {
      for (key in length_by_key) {
        if (!complete[key]) continue
        packet_length = length_by_key[key]
        if (packet_length < 20 || and(data[key, 0], 119) != 117) continue
        flags = data[key, 1]
        body_size = data[key, 2]
        cursor = 3
        if (and(flags, 128)) cursor++
        if (and(flags, 64)) cursor++
        source_lid = data[key, cursor++]
        if (and(flags, 32)) cursor++
        if (and(data[key, 0], 8)) cursor++
        body = cursor
        if (packet_length != body + body_size || body_size < 16) continue
        crc = 65535
        for (position = body; position < body + body_size - 2; position++) crc = crc_step(crc, data[key, position])
        expected_crc = data[key, body + body_size - 2] + (data[key, body + body_size - 1] * 256)
        if (crc != expected_crc) continue
        if (and(flags, 7) || and(data[key, body], 223) != 145 || data[key, body + 1] != 4) continue
        if (and(data[key, body], 32)) {
          pointer = body + 2
        } else {
          if (data[key, body + 2] != source_lid || data[key, body + 3] != 80) continue
          pointer = body + 4
        }
        group = data[key, pointer++]
        name = ""
        while (pointer < body + body_size - 2 && data[key, pointer] != 0) name = name sprintf("%c", data[key, pointer++])
        pointer++
        producer = ""
        while (pointer < body + body_size - 2 && data[key, pointer] != 0) producer = producer sprintf("%c", data[key, pointer++])
        pointer++
        model = ""
        while (pointer < body + body_size - 2 && data[key, pointer] != 0) model = model sprintf("%c", data[key, pointer++])
        pointer++
        hwid = ""
        while (pointer < body + body_size - 2 && data[key, pointer] != 0) hwid = hwid sprintf("%c", data[key, pointer++])
        pointer++
        if (pointer + 22 > body + body_size - 2) continue
        device_class = data[key, pointer++]
        processor = data[key, pointer++]
        operating_system = data[key, pointer++]
        device_flags = data[key, pointer++]
        firmware_id = data[key, pointer] + data[key, pointer + 1] * 256
        pointer += 2
        version_major = data[key, pointer++]
        version_minor = data[key, pointer++]
        channels = u32(key, pointer)
        pointer += 4
        tags = u32(key, pointer)
        pointer += 4
        user_id = u32(key, pointer)
        pointer += 4
        change = data[key, pointer] + data[key, pointer + 1] * 256
        gsub(/[|[:cntrl:]]/, "/", name)
        gsub(/[|[:cntrl:]]/, "/", producer)
        gsub(/[|[:cntrl:]]/, "/", model)
        gsub(/[|[:cntrl:]]/, "/", hwid)
        printf "%d|%s|%s|%s|%s|%s|%d|%d.%d|%d|%d|%d|%d|%d|%d|%d|%d\n", source_lid, substr(key, 1, 4), name, producer, model, hwid, firmware_id, version_major, version_minor, channels, tags, group, device_class, processor, operating_system, device_flags, user_id
      }
    }
  ' "$_INFO_CAP" | awk -F'|' 'NR == FNR {expected[$1 FS $2 FS $3]=1; next} expected[$1 FS $2 FS $6]' "$_SEARCH_RES" - | sort -nu >"$_OUT"
}

# Identify interfaces
DETECTED_INTERFACES="$(detect_interfaces)"
if [ "$REQUESTED_INTERFACE" = "all" ]; then
  INTERFACES="$DETECTED_INTERFACES"
else
  INTERFACES="$REQUESTED_INTERFACE"
fi

# Screen Header
printf '%s================================================================================%s\n' "$C_BOLD" "$C_RESET"
printf '%s  iRidi CAN Bus & Bus77 Diagnostic v%s%s\n' "$C_BOLD$C_CYAN" "$TOOL_VERSION" "$C_RESET"
printf '%s================================================================================%s\n' "$C_BOLD" "$C_RESET"
printf '  %-18s : %s (%s %s)\n' "Host" "$HOSTNAME_VAL" "$(uname -s 2>/dev/null)" "$(uname -m 2>/dev/null)"
printf '  %-18s : %s\n' "Started" "$STARTED_AT"
if [ "$PASSIVE_ONLY" -eq 1 ]; then
  printf '  %-18s : %s\n' "Diagnostic Mode" "Passive Monitoring Only (no CAN transmissions)"
elif [ "$SCAN_ONLY" -eq 1 ]; then
  printf '  %-18s : %s\n' "Diagnostic Mode" "Active Device Discovery & Inventory (scan-only)"
else
  printf '  %-18s : %s\n' "Diagnostic Mode" "Active Discovery + Passive Traffic Sample (${SAMPLE_SECONDS}s)"
fi
printf '  %-18s : %s\n' "Target Interface(s)" "${INTERFACES:-none detected}"
printf '  %-18s : %s%s%s\n' "Log File" "$C_DIM" "$LOG_FILE" "$C_RESET"
printf '%s--------------------------------------------------------------------------------%s\n' "$C_DIM" "$C_RESET"

# SECTION 1: CAN CONTROLLER & INTERFACE PREFLIGHT
printf '\n%s[1/4] CAN Controller & Network Interfaces%s\n' "$C_BOLD" "$C_RESET"

if [ -z "$DETECTED_INTERFACES" ]; then
  fail "No SocketCAN interfaces detected in /sys/class/net."
elif [ -z "$INTERFACES" ]; then
  fail "Selected interface ($REQUESTED_INTERFACE) is not available."
else
  for CAN_IFACE in $INTERFACES; do
    if [ ! -d "/sys/class/net/$CAN_IFACE" ] || [ "$(cat "/sys/class/net/$CAN_IFACE/type" 2>/dev/null)" != "280" ]; then
      fail "$CAN_IFACE is not a valid SocketCAN interface."
      continue
    fi

    CAN_DETAILS="$(ip -details -statistics link show "$CAN_IFACE" 2>/dev/null)"
    log_tech_cmd "ip link details for $CAN_IFACE" ip -details -statistics link show "$CAN_IFACE"

    CAN_FLAGS="$(printf '%s\n' "$CAN_DETAILS" | awk 'NR==1 { sub(/^[^<]*</, ""); sub(/>.*/, ""); print; exit }')"
    CAN_STATE="$(printf '%s\n' "$CAN_DETAILS" | awk '/can .* state / { for(i=1;i<=NF;i++) if($i=="state") {print $(i+1); exit} }')"
    CAN_BITRATE="$(printf '%s\n' "$CAN_DETAILS" | awk '/ bitrate / { for(i=1;i<=NF;i++) if($i=="bitrate") {print $(i+1); exit} }')"
    CAN_DRIVER_LINK="$(readlink "/sys/class/net/$CAN_IFACE/device/driver" 2>/dev/null)"
    CAN_DRIVER="${CAN_DRIVER_LINK##*/}"
    
    # Error counters
    CAN_COUNTERS="$(printf '%s\n' "$CAN_DETAILS" | awk '/re-started[[:space:]]+bus-errors[[:space:]]+arbit-lost/ { getline; print $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6; exit }')"
    OLD_IFS=$IFS; IFS='|'; set -- $CAN_COUNTERS; IFS=$OLD_IFS
    CAN_RESTARTED="${1:-0}"; CAN_BUS_ERRORS="${2:-0}"; CAN_ARBIT_LOST="${3:-0}"
    CAN_ERR_WARN="${4:-0}"; CAN_ERR_PASS="${5:-0}"; CAN_BUS_OFF="${6:-0}"

    printf '  * Interface: %s%s%s (Driver: %s, Bitrate: %s bit/s)\n' "$C_BOLD" "$CAN_IFACE" "$C_RESET" "${CAN_DRIVER:-generic}" "${CAN_BITRATE:-unknown}"
    
    if [ "$CAN_STATE" = "ERROR-ACTIVE" ]; then
      ok "$CAN_IFACE state is ERROR-ACTIVE (healthy normal operation)."
    elif [ "$CAN_STATE" = "ERROR-WARNING" ] || [ "$CAN_STATE" = "ERROR-PASSIVE" ]; then
      warn "$CAN_IFACE state is $CAN_STATE (degraded CAN bus condition)."
    elif [ "$CAN_STATE" = "BUS-OFF" ] || [ "$CAN_STATE" = "STOPPED" ]; then
      fail "$CAN_IFACE state is $CAN_STATE (interface is offline or disconnected)."
    else
      warn "$CAN_IFACE state: ${CAN_STATE:-unknown}."
    fi

    case "$CAN_FLAGS" in
      *UP*) : ;;
      *) fail "$CAN_IFACE link is administratively DOWN." ;;
    esac

    if [ "$CAN_BUS_ERRORS" -gt 0 ] || [ "$CAN_ERR_WARN" -gt 0 ] || [ "$CAN_BUS_OFF" -gt 0 ]; then
      warn "$CAN_IFACE recorded past bus errors: BusErrors=$CAN_BUS_ERRORS, ArbLost=$CAN_ARBIT_LOST, Warn=$CAN_ERR_WARN, Pass=$CAN_ERR_PASS, BusOff=$CAN_BUS_OFF"
    else
      ok "$CAN_IFACE hardware error counters are clean (0 errors recorded)."
    fi
  done
fi

# SECTION 2: IRIDI RUNTIME & CAN GATEWAY CONFIGURATION
printf '\n%s[2/4] iRidi Runtime & Gateway Configuration%s\n' "$C_BOLD" "$C_RESET"

IRIDI_PID="$(pidof iridium 2>/dev/null | awk '{print $1; exit}')"
ACTIVE_DATA_DIR=""
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
  ok "iRidi Server daemon is running (PID $IRIDI_PID, Data: ${ACTIVE_DATA_DIR:-/opt/iridi})."
else
  warn "No running 'iridium' process detected on this host."
fi

GATEWAY_JSON=""
if [ -n "$ACTIVE_DATA_DIR" ] && [ -r "$ACTIVE_DATA_DIR/Documents/can_gateway.json" ]; then
  GATEWAY_JSON="$ACTIVE_DATA_DIR/Documents/can_gateway.json"
elif [ -r "/opt/iridi/Documents/can_gateway.json" ]; then
  GATEWAY_JSON="/opt/iridi/Documents/can_gateway.json"
fi

if [ -n "$GATEWAY_JSON" ]; then
  log_tech_file "can_gateway.json" "$GATEWAY_JSON"
  GATE_CAN0_ACT="$(sed -n 's/.*"Can0GateWayActive":[[:space:]]*\([^,}]*\).*/\1/p' "$GATEWAY_JSON")"
  GATE_CAN0_LID="$(sed -n 's/.*"DeviceLid":[[:space:]]*\([^,}]*\).*/\1/p' "$GATEWAY_JSON")"
  GATE_CAN0_UDP="$(sed -n 's/.*"UdpCan0":[[:space:]]*\([^,}]*\).*/\1/p' "$GATEWAY_JSON")"
  GATE_CAN1_ACT="$(sed -n 's/.*"Can1GateWayActive":[[:space:]]*\([^,}]*\).*/\1/p' "$GATEWAY_JSON")"
  GATE_CAN1_LID="$(sed -n 's/.*"DeviceLidCan1":[[:space:]]*\([^,}]*\).*/\1/p' "$GATEWAY_JSON")"
  GATE_CAN1_UDP="$(sed -n 's/.*"UdpCan1":[[:space:]]*\([^,}]*\).*/\1/p' "$GATEWAY_JSON")"
  
  ok "Gateway config loaded from $GATEWAY_JSON:"
  printf '     - can0 gateway: %s (Local LID: %s, UDP Port: %s)\n' "${GATE_CAN0_ACT:-false}" "${GATE_CAN0_LID:-1}" "${GATE_CAN0_UDP:-30467}"
  printf '     - can1 gateway: %s (Local LID: %s, UDP Port: %s)\n' "${GATE_CAN1_ACT:-false}" "${GATE_CAN1_LID:-2}" "${GATE_CAN1_UDP:-30468}"
else
  info "CAN gateway configuration file (can_gateway.json) not found in standard paths."
fi

# Check gateway listener ports
if command -v ss >/dev/null 2>&1; then
  SS_OUT="$(ss -lunp 2>/dev/null | grep -E ':(30467|30468|65534)[[:space:]]')"
  if [ -n "$SS_OUT" ]; then
    ok "Active UDP CAN gateway socket listener(s) detected:"
    printf '%s\n' "$SS_OUT" | awk '{printf "     - %s (%s)\n", $5, $NF}'
  else
    info "No active UDP gateway sockets on default ports (30467/30468/65534)."
  fi
  log_tech_cmd "Socket statistics" ss -lunp
fi

# SECTION 3: BUS77 ACTIVE DEVICE DISCOVERY & INVENTORY
printf '\n%s[3/4] Bus77 Device Discovery & Inventory%s\n' "$C_BOLD" "$C_RESET"

TOTAL_DISCOVERED=0
TOTAL_PROFILES=0

if [ "$PASSIVE_ONLY" -eq 1 ]; then
  info "Active device discovery skipped (--passive mode enabled)."
elif [ -z "$INTERFACES" ]; then
  fail "Cannot perform device discovery: no CAN interfaces available."
else
  for CAN_IFACE in $INTERFACES; do
    printf '  * Interface %s%s%s: running active discovery...\n' "$C_BOLD" "$CAN_IFACE" "$C_RESET"
    
    SEARCH_CAP="$WORK_DIR/search_${CAN_IFACE}.cap"
    SEARCH_RES="$WORK_DIR/search_${CAN_IFACE}.res"
    INFO_CAP="$WORK_DIR/info_${CAN_IFACE}.cap"
    INFO_RES="$WORK_DIR/info_${CAN_IFACE}.res"
    : >"$SEARCH_RES"
    : >"$INFO_RES"

    # 1. System Search (0x03)
    if ! start_capture "$CAN_IFACE" "$SEARCH_CAP"; then
      fail "Could not start packet capture on $CAN_IFACE."
      continue
    fi
    
    if ! send_search_request "$CAN_IFACE"; then
      fail "Failed to transmit Bus77 Search request on $CAN_IFACE."
      stop_capture 1
      continue
    fi
    stop_capture 3
    
    log_tech_file "Raw Search candump on $CAN_IFACE" "$SEARCH_CAP"
    parse_search_capture "$SEARCH_CAP" "$SEARCH_RES"
    
    IFACE_SEARCH_COUNT="$(wc -l <"$SEARCH_RES" 2>/dev/null | tr -d ' ')"
    IFACE_SEARCH_COUNT="${IFACE_SEARCH_COUNT:-0}"
    
    if [ "$IFACE_SEARCH_COUNT" -eq 0 ]; then
      warn "No Bus77 devices replied to Search broadcast on $CAN_IFACE."
      continue
    fi
    
    ok "$CAN_IFACE: $IFACE_SEARCH_COUNT device(s) responded to Search broadcast."
    TOTAL_DISCOVERED=$((TOTAL_DISCOVERED + IFACE_SEARCH_COUNT))

    # 2. Device Info (0x04)
    if ! start_capture "$CAN_IFACE" "$INFO_CAP"; then
      fail "Could not start packet capture for Device Info on $CAN_IFACE."
      continue
    fi
    
    while IFS='|' read -r DEV_LID DEV_CAN_ID DEV_HWID DEV_GRP DEV_FLAGS DEV_EVT; do
      [ -n "$DEV_LID" ] || continue
      send_device_info_request "$CAN_IFACE" "$DEV_LID" 2>/dev/null || true
      sleep 1
    done <"$SEARCH_RES"
    stop_capture 3
    
    log_tech_file "Raw Device Info candump on $CAN_IFACE" "$INFO_CAP"
    parse_info_capture "$INFO_CAP" "$SEARCH_RES" "$INFO_RES"
    
    IFACE_INFO_COUNT="$(wc -l <"$INFO_RES" 2>/dev/null | tr -d ' ')"
    IFACE_INFO_COUNT="${IFACE_INFO_COUNT:-0}"
    TOTAL_PROFILES=$((TOTAL_PROFILES + IFACE_INFO_COUNT))
    
    if [ "$IFACE_INFO_COUNT" -gt 0 ]; then
      ok "$CAN_IFACE: Decoded complete firmware profiles for $IFACE_INFO_COUNT device(s)."
      # Append to master inventory file
      awk -v dev="$CAN_IFACE" '{print dev "|" $0}' "$INFO_RES" >>"$INVENTORY_FILE"
    else
      warn "$CAN_IFACE: Discovered $IFACE_SEARCH_COUNT devices, but Device Info profiles could not be decoded."
      # Fallback to search results in master inventory
      while IFS='|' read -r DEV_LID DEV_CAN_ID DEV_HWID DEV_GRP DEV_FLAGS DEV_EVT; do
        printf '%s|%s|%s||||%s|||||%s||||%s|\n' "$CAN_IFACE" "$DEV_LID" "$DEV_CAN_ID" "$DEV_HWID" "$DEV_GRP" "$DEV_FLAGS" >>"$INVENTORY_FILE"
      done <"$SEARCH_RES"
    fi
  done
fi

# Present Discovered Devices
INV_COUNT="$(wc -l <"$INVENTORY_FILE" 2>/dev/null | tr -d ' ')"
INV_COUNT="${INV_COUNT:-0}"

if [ "$INV_COUNT" -gt 0 ]; then
  printf '\n  %sDiscovered Bus77 Device Inventory (%d devices):%s\n\n' "$C_BOLD" "$INV_COUNT" "$C_RESET"
  printf '  %-6s %-4s %-20s %-10s %-9s %-8s %-16s\n' "IFACE" "LID" "MODEL" "FIRMWARE" "PROFILE" "CAN ID" "HWID"
  printf '  %s\n' "-------------------------------------------------------------------------------"
  
  while IFS='|' read -r DEV_IFACE DEV_LID DEV_CAN_ID DEV_NAME DEV_PROD DEV_MODEL DEV_HWID DEV_FW_ID DEV_VER DEV_CH DEV_TAGS DEV_GRP DEV_CLS DEV_CPU DEV_OS DEV_FLG DEV_UID; do
    printf '  %-6s %-4s %-20s %-10s %-9s 0x%-6s %-16s\n' \
      "$DEV_IFACE" "$DEV_LID" "${DEV_MODEL:-unknown}" "${DEV_VER:--}" "${DEV_FW_ID:--}" "$DEV_CAN_ID" "${DEV_HWID:--}"
  done <"$INVENTORY_FILE"
  
  printf '\n  %sDevice Identity Details:%s\n' "$C_BOLD" "$C_RESET"
  DEV_IDX=0
  while IFS='|' read -r DEV_IFACE DEV_LID DEV_CAN_ID DEV_NAME DEV_PROD DEV_MODEL DEV_HWID DEV_FW_ID DEV_VER DEV_CH DEV_TAGS DEV_GRP DEV_CLS DEV_CPU DEV_OS DEV_FLG DEV_UID; do
    DEV_IDX=$((DEV_IDX + 1))
    printf '  + [%d] %s (LID %s on %s)\n' "$DEV_IDX" "${DEV_MODEL:-Bus77 Device}" "$DEV_LID" "$DEV_IFACE"
    [ -n "$DEV_NAME" ] && printf '      Name / Producer  : %s (%s)\n' "$DEV_NAME" "${DEV_PROD:-iRidi}"
    printf '      HWID             : %s\n' "${DEV_HWID:-not set}"
    printf '      CAN Device ID    : 0x%s\n' "$DEV_CAN_ID"
    [ -n "$DEV_VER" ] && printf '      Firmware Version : %s (Profile ID: %s)\n' "$DEV_VER" "${DEV_FW_ID:-unknown}"
    [ -n "$DEV_CH" ] && [ "$DEV_CH" != "0" ] && printf '      Channels / Tags  : %s / %s\n' "$DEV_CH" "$DEV_TAGS"
  done <"$INVENTORY_FILE"
fi

# Optional JSON Export
if [ "$JSON_OUTPUT" -eq 1 ]; then
  printf '\n%sJSON INVENTORY EXPORT:%s\n' "$C_BOLD" "$C_RESET"
  awk -F'|' '
    BEGIN { printf "[\n" }
    NF >= 3 {
      if (count++) printf ",\n"
      printf "  {\n"
      printf "    \"interface\": \"%s\",\n", $1
      printf "    \"lid\": %d,\n", $2
      printf "    \"can_id\": \"0x%s\",\n", $3
      printf "    \"name\": \"%s\",\n", ($4!=""?$4:"")
      printf "    \"producer\": \"%s\",\n", ($5!=""?$5:"")
      printf "    \"model\": \"%s\",\n", ($6!=""?$6:"")
      printf "    \"hwid\": \"%s\",\n", ($7!=""?$7:"")
      printf "    \"firmware_profile\": %s,\n", ($8!=""?$8:"null")
      printf "    \"firmware_version\": \"%s\",\n", ($9!=""?$9:"")
      printf "    \"channels\": %s,\n", ($10!=""?$10:"null")
      printf "    \"tags\": %s,\n", ($11!=""?$11:"null")
      printf "    \"group\": %s,\n", ($12!=""?$12:"null")
      printf "    \"device_class\": %s,\n", ($13!=""?$13:"null")
      printf "    \"processor\": %s,\n", ($14!=""?$14:"null")
      printf "    \"operating_system\": %s,\n", ($15!=""?$15:"null")
      printf "    \"device_flags\": %s,\n", ($16!=""?$16:"null")
      printf "    \"user_id\": %s\n", ($17!=""?$17:"null")
      printf "  }"
    }
    END { printf "\n]\n" }
  ' "$INVENTORY_FILE"
fi

# SECTION 4: PASSIVE TRAFFIC SAMPLING & HEALTH
if [ "$SCAN_ONLY" -eq 0 ]; then
  printf '\n%s[4/4] Passive Bus Traffic Sample (%ds)%s\n' "$C_BOLD" "$SAMPLE_SECONDS" "$C_RESET"
  
  if [ -z "$INTERFACES" ]; then
    fail "Traffic sampling skipped: no CAN interfaces available."
  else
    # Take initial snapshots
    snapshot_stats() {
      _IFACE="$1"
      _OUT="$2"
      : >"$_OUT"
      for STAT_KEY in rx_packets rx_bytes rx_errors rx_dropped tx_packets tx_bytes tx_errors tx_dropped; do
        STAT_VAL="$(cat "/sys/class/net/$_IFACE/statistics/$STAT_KEY" 2>/dev/null)"
        printf '%s=%s\n' "$STAT_KEY" "${STAT_VAL:-0}" >>"$_OUT"
      done
    }
    
    read_snapshot_val() {
      awk -F= -v key="$2" '$1 == key { print $2; exit }' "$1" 2>/dev/null
    }

    for CAN_IFACE in $INTERFACES; do
      snapshot_stats "$CAN_IFACE" "$WORK_DIR/${CAN_IFACE}.before"
    done

    TRAFFIC_CAP="$WORK_DIR/traffic_sample.cap"
    printf '  * Listening on %s (%d seconds)...\n' "$(printf '%s' "$INTERFACES" | tr '\n' ' ')" "$SAMPLE_SECONDS"
    
    if command -v candump >/dev/null 2>&1; then
      if command -v timeout >/dev/null 2>&1; then
        timeout "$SAMPLE_SECONDS" candump -x -e $INTERFACES >"$TRAFFIC_CAP" 2>&1 || true
      else
        candump -x -e $INTERFACES >"$TRAFFIC_CAP" 2>&1 &
        CAPTURE_PID=$!
        sleep "$SAMPLE_SECONDS"
        kill -INT "$CAPTURE_PID" 2>/dev/null
        wait "$CAPTURE_PID" 2>/dev/null
        CAPTURE_PID=""
      fi
      log_tech_file "Passive candump traffic sample" "$TRAFFIC_CAP"
    else
      warn "candump utility not available; evaluating kernel network counters only."
      sleep "$SAMPLE_SECONDS"
    fi

    # Read post-sample stats and compute deltas
    for CAN_IFACE in $INTERFACES; do
      snapshot_stats "$CAN_IFACE" "$WORK_DIR/${CAN_IFACE}.after"
      BEFORE_F="$WORK_DIR/${CAN_IFACE}.before"
      AFTER_F="$WORK_DIR/${CAN_IFACE}.after"
      
      RX_BEF="$(read_snapshot_val "$BEFORE_F" rx_packets)"
      TX_BEF="$(read_snapshot_val "$BEFORE_F" tx_packets)"
      RX_ERR_BEF="$(read_snapshot_val "$BEFORE_F" rx_errors)"
      TX_ERR_BEF="$(read_snapshot_val "$BEFORE_F" tx_errors)"
      RX_DRP_BEF="$(read_snapshot_val "$BEFORE_F" rx_dropped)"
      TX_DRP_BEF="$(read_snapshot_val "$BEFORE_F" tx_dropped)"
      
      RX_AFT="$(read_snapshot_val "$AFTER_F" rx_packets)"
      TX_AFT="$(read_snapshot_val "$AFTER_F" tx_packets)"
      RX_ERR_AFT="$(read_snapshot_val "$AFTER_F" rx_errors)"
      TX_ERR_AFT="$(read_snapshot_val "$AFTER_F" tx_errors)"
      RX_DRP_AFT="$(read_snapshot_val "$AFTER_F" rx_dropped)"
      TX_DRP_AFT="$(read_snapshot_val "$AFTER_F" tx_dropped)"
      
      DELTA_RX=$((RX_AFT - RX_BEF))
      DELTA_TX=$((TX_AFT - TX_BEF))
      DELTA_RX_ERR=$((RX_ERR_AFT - RX_ERR_BEF))
      DELTA_TX_ERR=$((TX_ERR_AFT - TX_ERR_BEF))
      DELTA_RX_DRP=$((RX_DRP_AFT - RX_DRP_BEF))
      DELTA_TX_DRP=$((TX_DRP_AFT - TX_DRP_BEF))

      printf '\n  * Interface %s%s%s traffic statistics:\n' "$C_BOLD" "$CAN_IFACE" "$C_RESET"
      printf '    - RX Frames received : %d\n' "$DELTA_RX"
      printf '    - TX Frames sent     : %d\n' "$DELTA_TX"
      printf '    - New RX/TX Errors   : %d / %d\n' "$DELTA_RX_ERR" "$DELTA_TX_ERR"
      printf '    - New RX/TX Drops    : %d / %d\n' "$DELTA_RX_DRP" "$DELTA_TX_DRP"

      if [ "$DELTA_RX" -gt 0 ]; then
        ok "$CAN_IFACE actively exchanged physical bus traffic during observation."
      elif [ "$DELTA_TX" -gt 0 ]; then
        warn "$CAN_IFACE transmitted packets but received no responses (isolated bus or no devices)."
      else
        warn "$CAN_IFACE was idle during observation (0 frames captured in ${SAMPLE_SECONDS}s)."
      fi

      if [ "$DELTA_RX_ERR" -gt 0 ] || [ "$DELTA_TX_ERR" -gt 0 ] || [ "$DELTA_RX_DRP" -gt 0 ] || [ "$DELTA_TX_DRP" -gt 0 ]; then
        fail "$CAN_IFACE encountered new errors or packet drops during the observation window."
      else
        ok "$CAN_IFACE frame integrity is 100% clean (zero errors or drops during sample)."
      fi
    done
  fi
fi

# SUMMARY & FINAL VERDICT
printf '\n%s================================================================================%s\n' "$C_BOLD" "$C_RESET"
printf '%s  DIAGNOSTIC SUMMARY%s\n' "$C_BOLD" "$C_RESET"
printf '%s================================================================================%s\n' "$C_BOLD" "$C_RESET"
printf '  %-22s : %s\n' "CAN Interfaces" "$(printf '%s' "$INTERFACES" | tr '\n' ' ')"
printf '  %-22s : %d discovered (%d full profiles verified)\n' "Bus77 Devices" "$TOTAL_DISCOVERED" "$TOTAL_PROFILES"
printf '  %-22s : %s\n' "Attention Warnings" "$WARNINGS"
printf '  %-22s : %s\n' "Fatal Failures" "$FAILURES"
printf '  %-22s : %s%s%s\n' "Detailed Tech Log" "$C_DIM" "$LOG_FILE" "$C_RESET"
printf '%s--------------------------------------------------------------------------------%s\n' "$C_DIM" "$C_RESET"

if [ "$FAILURES" -gt 0 ]; then
  printf '  %sRESULT: FAIL - NOT OK: Critical CAN bus or controller errors detected.%s\n' "$C_RED$C_BOLD" "$C_RESET"
  FINAL_RC=2
elif [ "$WARNINGS" -gt 0 ]; then
  printf '  %sRESULT: WARN - ATTENTION REQUIRED: CAN bus is operational with warnings.%s\n' "$C_YELLOW$C_BOLD" "$C_RESET"
  FINAL_RC=1
else
  printf '  %sRESULT: PASS - OK: CAN controller and Bus77 network are healthy.%s\n' "$C_GREEN$C_BOLD" "$C_RESET"
  FINAL_RC=0
fi
printf '%s================================================================================%s\n' "$C_BOLD" "$C_RESET"

log_tech "================================================================================"
log_tech "DIAGNOSTIC COMPLETE | Exit Code: $FINAL_RC | Failures: $FAILURES | Warnings: $WARNINGS"
log_tech "================================================================================"

exit "$FINAL_RC"
