#!/bin/sh

case "${1:-}" in
  -h|--help)
    printf 'Usage: sh %s [--interface can0|all] [--duration SECONDS] [--passive] [--scan-only] [--json]\n' "${0##*/}"
    printf '%s\n' 'Default: read device identities, then observe the bus. --passive skips all requests.'
    printf '%s\n' 'Use --scan-only (or --inventory) to discover devices and exit immediately without bus sampling.'
    exit 0
    ;;
esac

# Bus77 device inventory and CAN health diagnostics for HSS/ProAV.
# Only Search and Device Info requests are sent; interface settings stay unchanged.
# Usage: sh check_can_bus.sh [--interface can0|all] [--duration 15] [--scan-only] [--json]

if [ "${IRIDI_CAN_LOG_ACTIVE:-0}" != "1" ]; then
  CURRENT_DIRECTORY="$(pwd 2>/dev/null || printf '.')"
  LOG_DIRECTORY="${IRIDI_DIAG_LOG_DIR:-$CURRENT_DIRECTORY}"
  if [ ! -d "$LOG_DIRECTORY" ] || [ ! -w "$LOG_DIRECTORY" ]; then
    LOG_DIRECTORY="${TMPDIR:-/tmp}"
  fi
  HOST_LABEL="$(hostname 2>/dev/null || printf server)"
  HOST_LABEL="$(printf '%s' "$HOST_LABEL" | tr -c 'A-Za-z0-9._-' '_')"
  [ -n "$HOST_LABEL" ] || HOST_LABEL=server
  LOG_TIMESTAMP="$(date '+%Y%m%d_%H%M%S' 2>/dev/null || printf unknown_time)"
  LOG_FILE="$LOG_DIRECTORY/can_diagnostic_${HOST_LABEL}_${LOG_TIMESTAMP}_$$.log"
  export IRIDI_CAN_LOG_ACTIVE=1
  export IRIDI_CAN_LOG_FILE="$LOG_FILE"

  colorize_output() {
    awk '
      /\[OK\]|RESULT: PASS/ { printf "\033[32m%s\033[0m\n", $0; fflush(); next }
      /\[ATTENTION\]|RESULT: WARN/ { printf "\033[33m%s\033[0m\n", $0; fflush(); next }
      /\[NOT OK\]|RESULT: FAIL/ { printf "\033[31m%s\033[0m\n", $0; fflush(); next }
      { print; fflush() }
    '
  }

  if command -v tee >/dev/null 2>&1; then
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && command -v awk >/dev/null 2>&1; then
      sh "$0" "$@" 2>&1 | tee "$LOG_FILE" | colorize_output
    else
      sh "$0" "$@" 2>&1 | tee "$LOG_FILE"
    fi
    PIPELINE_RC=$?
    RESULT_LINE="$(grep '^RESULT:' "$LOG_FILE" 2>/dev/null | tail -n 1)"
    case "$RESULT_LINE" in
      *PASS*) FINAL_RC=0 ;;
      *WARN*) FINAL_RC=1 ;;
      *FAIL*) FINAL_RC=2 ;;
      *) FINAL_RC=2 ;;
    esac
    if [ "$PIPELINE_RC" -ne 0 ]; then
      FINAL_RC=2
      printf '[NOT OK] The log file could not be written completely.\n'
    fi
    printf '\nLog saved: %s\n' "$LOG_FILE" | tee -a "$LOG_FILE"
    exit "$FINAL_RC"
  fi

  sh "$0" "$@" >"$LOG_FILE" 2>&1
  FINAL_RC=$?
  cat "$LOG_FILE"
  printf '\nLog saved: %s\n' "$LOG_FILE"
  exit "$FINAL_RC"
fi

set +e
export LC_ALL=C

SCRIPT_VERSION=2.3
PASSIVE_ONLY=0
SCAN_ONLY=0
JSON_OUTPUT=0
REQUESTED_INTERFACE=all
SAMPLE_SECONDS=15
WARNINGS=0
FAILURES=0
WORK_DIR=""
CAPTURE_PID=""

separator() {
  printf '%s\n' '----------------------------------------------------------------'
}

ok() {
  printf '  [OK] %s\n' "$1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '  [ATTENTION] %s\n' "$1"
}

fail() {
  FAILURES=$((FAILURES + 1))
  printf '  [NOT OK] %s\n' "$1"
}

usage() {
  printf '%s\n' 'Usage: sh check_can_bus.sh [--interface can0|all] [--duration SECONDS] [--passive] [--scan-only] [--json]'
  printf '%s\n' 'Defaults: read-only inventory, then a 15-second health sample on all CAN interfaces.'
  printf '%s\n' 'Options:'
  printf '%s\n' '  --scan-only, --inventory  Discover connected Bus77 devices/profiles and exit without waiting for bus sample.'
  printf '%s\n' '  --passive                 Skip device identity requests (models and profiles will not be read).'
  printf '%s\n' '  --duration SECONDS        Duration of passive health sample in seconds (default: 15).'
  printf '%s\n' '  --interface IFACE         SocketCAN interface name (e.g. can0, or all).'
  printf '%s\n' '  --json                    Output discovered devices in structured JSON format.'
}

# BEGIN GENERATED INVENTORY
run_bus77_inventory() (
  export IRIDI_BUS77_SCAN_LOG_ACTIVE=1

# Active read-only Bus77 discovery for iRidi HSS and ProAV servers.
# Sends only System Search (0x03) and Device Info (0x04) requests.
# Usage: sh scan_bus77_devices.sh [--interface can0] [--timeout 5]

case "${1:-}" in
  -h|--help)
    printf '%s\n' 'Usage: sh scan_bus77_devices.sh [--interface can0] [--timeout SECONDS]' 'Sends only read-only Bus77 Search and Device Info requests.'
    exit 0
    ;;
esac

if [ "${IRIDI_BUS77_SCAN_LOG_ACTIVE:-0}" != "1" ]; then
  CURRENT_DIRECTORY="$(pwd 2>/dev/null || printf '.')"
  LOG_DIRECTORY="${IRIDI_DIAG_LOG_DIR:-$CURRENT_DIRECTORY}"
  if [ ! -d "$LOG_DIRECTORY" ] || [ ! -w "$LOG_DIRECTORY" ]; then
    LOG_DIRECTORY="${TMPDIR:-/tmp}"
  fi
  HOST_LABEL="$(hostname 2>/dev/null || printf server)"
  HOST_LABEL="$(printf '%s' "$HOST_LABEL" | tr -c 'A-Za-z0-9._-' '_')"
  [ -n "$HOST_LABEL" ] || HOST_LABEL=server
  LOG_TIMESTAMP="$(date '+%Y%m%d_%H%M%S' 2>/dev/null || printf unknown_time)"
  LOG_FILE="$LOG_DIRECTORY/bus77_device_scan_${HOST_LABEL}_${LOG_TIMESTAMP}_$$.log"
  export IRIDI_BUS77_SCAN_LOG_ACTIVE=1
  export IRIDI_BUS77_SCAN_LOG_FILE="$LOG_FILE"

  colorize_output() {
    awk '
      /\[OK\]|RESULT: PASS/ { printf "\033[32m%s\033[0m\n", $0; fflush(); next }
      /\[ATTENTION\]|RESULT: WARN/ { printf "\033[33m%s\033[0m\n", $0; fflush(); next }
      /\[NOT OK\]|RESULT: FAIL/ { printf "\033[31m%s\033[0m\n", $0; fflush(); next }
      { print; fflush() }
    '
  }

  if command -v tee >/dev/null 2>&1; then
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && command -v awk >/dev/null 2>&1; then
      sh "$0" "$@" 2>&1 | tee "$LOG_FILE" | colorize_output
    else
      sh "$0" "$@" 2>&1 | tee "$LOG_FILE"
    fi
    PIPELINE_RC=$?
    RESULT_LINE="$(grep '^RESULT:' "$LOG_FILE" 2>/dev/null | tail -n 1)"
    case "$RESULT_LINE" in
      *PASS*) FINAL_RC=0 ;;
      *WARN*) FINAL_RC=1 ;;
      *) FINAL_RC=2 ;;
    esac
    if [ "$PIPELINE_RC" -ne 0 ]; then
      FINAL_RC=2
      printf '[NOT OK] The log file could not be written completely.\n'
    fi
    printf '\nLog saved: %s\n' "$LOG_FILE" | tee -a "$LOG_FILE"
    exit "$FINAL_RC"
  fi

  sh "$0" "$@" >"$LOG_FILE" 2>&1
  FINAL_RC=$?
  cat "$LOG_FILE"
  printf '\nLog saved: %s\n' "$LOG_FILE"
  exit "$FINAL_RC"
fi

set +e
export LC_ALL=C

SCRIPT_VERSION=1.1
CAN_INTERFACE=can0
RESPONSE_TIMEOUT=5
SCANNER_CAN_ID=65534
SCANNER_LID=254
WARNINGS=0
FAILURES=0
CAPTURE_PID=""
WORK_DIR=""

separator() {
  printf '%s\n' '----------------------------------------------------------------'
}

ok() {
  printf '  [OK] %s\n' "$1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '  [ATTENTION] %s\n' "$1"
}

fail() {
  FAILURES=$((FAILURES + 1))
  printf '  [NOT OK] %s\n' "$1"
}

usage() {
  printf '%s\n' 'Usage: sh scan_bus77_devices.sh [--interface can0] [--timeout SECONDS]'
  printf '%s\n' 'Sends only read-only Bus77 Search and Device Info requests.'
}

cleanup() {
  if [ -n "$CAPTURE_PID" ]; then
    kill -INT "$CAPTURE_PID" 2>/dev/null
    wait "$CAPTURE_PID" 2>/dev/null
  fi
  [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --interface)
      shift
      CAN_INTERFACE="${1:-}"
      ;;
    --timeout)
      shift
      RESPONSE_TIMEOUT="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[NOT OK] Unknown argument: %s\n' "$1"
      usage
      printf 'RESULT: FAIL - NOT OK: invalid command-line arguments.\n'
      exit 2
      ;;
  esac
  shift
done

case "$CAN_INTERFACE" in
  ''|*[!A-Za-z0-9_.:-]*)
    printf '[NOT OK] Invalid interface name: %s\n' "$CAN_INTERFACE"
    printf 'RESULT: FAIL - NOT OK: invalid CAN interface name.\n'
    exit 2
    ;;
esac
case "$RESPONSE_TIMEOUT" in
  ''|*[!0-9]*)
    printf '[NOT OK] Timeout must be a whole number of seconds.\n'
    printf 'RESULT: FAIL - NOT OK: invalid timeout.\n'
    exit 2
    ;;
esac
if [ "$RESPONSE_TIMEOUT" -lt 2 ] || [ "$RESPONSE_TIMEOUT" -gt 30 ]; then
  printf '[NOT OK] Timeout must be between 2 and 30 seconds.\n'
  printf 'RESULT: FAIL - NOT OK: invalid timeout.\n'
  exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/iridi-bus77-scan.XXXXXX" 2>/dev/null)"
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ]; then
  WORK_DIR="${TMPDIR:-/tmp}/iridi-bus77-scan.$$"
  mkdir -m 700 "$WORK_DIR" || { WORK_DIR=""; exit 2; }
fi
SEARCH_CAPTURE="$WORK_DIR/search.capture"
SEARCH_RESULTS="$WORK_DIR/search.results"
INFO_CAPTURE="$WORK_DIR/info.capture"
INFO_RESULTS="$WORK_DIR/info.results"
: >"$SEARCH_RESULTS"
: >"$INFO_RESULTS"

printf 'iRidi Bus77 Device Scanner\n'
printf 'Script version: %s\n' "$SCRIPT_VERSION"
printf 'Started: %s\n' "$(date 2>/dev/null || echo unknown)"
printf 'Device: %s | %s | %s\n' "$(hostname 2>/dev/null || echo unknown)" "$(uname -s 2>/dev/null)" "$(uname -m 2>/dev/null)"
printf 'Log file: %s\n' "${IRIDI_BUS77_SCAN_LOG_FILE:-not set}"
printf 'CAN interface: %s\n' "$CAN_INTERFACE"
printf 'Mode: active read-only discovery\n'
printf 'Allowed requests: System Search (0x03), Device Info (0x04)\n'
printf 'Scanner identity: CAN ID=0xFFFE, LID=254\n'

separator
printf '1. Safety and interface preflight\n'
if [ ! -d "/sys/class/net/$CAN_INTERFACE" ] || [ "$(cat "/sys/class/net/$CAN_INTERFACE/type" 2>/dev/null)" != "280" ]; then
  fail "$CAN_INTERFACE is not an available SocketCAN interface."
fi
for REQUIRED_COMMAND in ip awk candump cansend; do
  if ! command -v "$REQUIRED_COMMAND" >/dev/null 2>&1; then
    fail "$REQUIRED_COMMAND is required."
  fi
done
AWK_BITWISE="$(awk 'BEGIN { print xor(1, 2) ":" and(7, 3) ":" lshift(1, 4) ":" rshift(16, 2) }' 2>/dev/null)"
if [ "$AWK_BITWISE" != "3:3:16:4" ]; then
  fail 'The installed awk does not provide the required bitwise functions.'
fi

CAN_DETAILS="$(ip -details -statistics link show "$CAN_INTERFACE" 2>/dev/null)"
CAN_STATE="$(printf '%s\n' "$CAN_DETAILS" | awk '/can .* state / { for(i=1;i<=NF;i++) if($i=="state") {print $(i+1); exit} }')"
CAN_BITRATE="$(printf '%s\n' "$CAN_DETAILS" | awk '/ bitrate / { for(i=1;i<=NF;i++) if($i=="bitrate") {print $(i+1); exit} }')"
printf '  Controller state: %s\n' "${CAN_STATE:-not determined}"
printf '  Bitrate: %s bit/s\n' "${CAN_BITRATE:-not determined}"
case "$CAN_STATE" in
  ERROR-ACTIVE) ok "$CAN_INTERFACE is ready for discovery." ;;
  ERROR-WARNING|ERROR-PASSIVE) warn "$CAN_INTERFACE is $CAN_STATE; discovery will continue cautiously." ;;
  *) fail "$CAN_INTERFACE is not in an operational CAN state." ;;
esac

if [ "$FAILURES" -gt 0 ]; then
  separator
  printf 'RESULT: FAIL - NOT OK: safety preflight failed; no CAN frames were sent.\n'
  exit 2
fi

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
  CAPTURE_FILE="$1"
  candump -x -e "$CAN_INTERFACE" >"$CAPTURE_FILE" 2>&1 &
  CAPTURE_PID=$!
  sleep 1
  kill -0 "$CAPTURE_PID" 2>/dev/null || return 1
}

stop_capture() {
  sleep "$RESPONSE_TIMEOUT"
  kill -INT "$CAPTURE_PID" 2>/dev/null
  wait "$CAPTURE_PID" 2>/dev/null
  CAPTURE_PID=""
}

send_search_request() {
  SEARCH_CRC="$(crc16_hex 17 3 86 52 255)"
  cansend "$CAN_INTERFACE" 1FFFDA00#750807FE11035634 || return 1
  cansend "$CAN_INTERFACE" "1FFFDA01#FF$SEARCH_CRC" || return 1
}

send_device_info_request() {
  TARGET_LID="$1"
  TARGET_LID_HEX="$(awk -v value="$TARGET_LID" 'BEGIN { printf "%02X", value }')"
  REQUEST_TID_LOW="$TARGET_LID"
  REQUEST_TID_HIGH=80
  REQUEST_CRC="$(crc16_hex 17 4 "$REQUEST_TID_LOW" "$REQUEST_TID_HIGH")"
  REQUEST_CAN_ID="$(awk -v sender="$SCANNER_CAN_ID" -v address="$TARGET_LID" '
    BEGIN { printf "%08X", lshift(sender, 13) + lshift(7, 10) + lshift(address, 1) }
  ')"
  REQUEST_CAN_ID_END="$(awk -v value="$REQUEST_CAN_ID" '
    function hex_digit(c) { return index("0123456789ABCDEF", c) - 1 }
    function hex_number(text, i, value) {
      value = 0
      for (i = 1; i <= length(text); i++) value = (value * 16) + hex_digit(substr(text, i, 1))
      return value
    }
    BEGIN { printf "%08X", hex_number(value) + 1 }
  ')"
  cansend "$CAN_INTERFACE" "${REQUEST_CAN_ID}#7D0806FE${TARGET_LID_HEX}1104${TARGET_LID_HEX}" || return 1
  cansend "$CAN_INTERFACE" "${REQUEST_CAN_ID_END}#50${REQUEST_CRC}" || return 1
}

parse_search_capture() {
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
  ' "$SEARCH_CAPTURE" | sort -nu >"$SEARCH_RESULTS"
}

parse_info_capture() {
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
  ' "$INFO_CAPTURE" | awk -F'|' 'NR == FNR {expected[$1 FS $2 FS $3]=1; next} expected[$1 FS $2 FS $6]' "$SEARCH_RESULTS" - | sort -nu >"$INFO_RESULTS"
}

separator
printf '2. Bus77 Search discovery\n'
printf '  Sending one broadcast System Search request.\n'
if ! start_capture "$SEARCH_CAPTURE"; then
  printf 'RESULT: FAIL - NOT OK: packet capture could not start; no requests sent.\n'
  exit 2
fi
if awk '
  function hex(s, i, n) { n=0; for(i=1;i<=length(s);i++) n=n*16+index("0123456789ABCDEF",toupper(substr(s,i,1)))-1; return n }
  $2 == "RX" && length($5) == 8 {
    if (and(rshift(hex($5),13),65535) == 65534) collision=1
    if ($7 == "75" || $7 == "7D") {
      flags=hex($8); pos=10
      if(and(flags,128)) pos++
      if(and(flags,64)) pos++
      if(hex($pos)==254) collision=1
    }
  }
  END { exit !collision }
' "$SEARCH_CAPTURE"; then
  printf 'RESULT: FAIL - NOT OK: scanner identity already observed on the bus; no requests sent.\n'
  exit 2
fi
printf '  Identity was not observed in the preflight sample; silent conflicts cannot be excluded.\n'
if send_search_request; then
  ok 'Search request sent successfully (2 CAN frames).'
else
  fail 'Search request could not be sent.'
fi
stop_capture

if [ "$FAILURES" -eq 0 ]; then
  parse_search_capture
fi
SEARCH_COUNT="$(wc -l <"$SEARCH_RESULTS" 2>/dev/null | tr -d ' ')"
SEARCH_COUNT="${SEARCH_COUNT:-0}"
if [ "$SEARCH_COUNT" -eq 0 ]; then
  fail 'No valid Bus77 Search responses were received.'
else
  ok "$SEARCH_COUNT devices responded with valid CRC-protected Search data."
  printf '\n  %-4s %-8s %-34s %-5s %-5s\n' 'LID' 'CAN ID' 'HWID' 'Group' 'Flags'
  while IFS='|' read -r LID CAN_ID HWID GROUP DEVICE_FLAGS EVENT; do
    printf '  %-4s 0x%-6s %-34s %-5s 0x%02X\n' "$LID" "$CAN_ID" "$HWID" "$GROUP" "$DEVICE_FLAGS"
  done <"$SEARCH_RESULTS"
fi

separator
printf '3. Device information\n'
if [ "$SEARCH_COUNT" -gt 0 ]; then
  printf '  Requesting Device Info from every discovered LID.\n'
  if ! start_capture "$INFO_CAPTURE"; then
    printf 'RESULT: FAIL - NOT OK: packet capture could not start for Device Info.\n'
    exit 2
  fi
  REQUESTED_COUNT=0
  while IFS='|' read -r LID CAN_ID HWID GROUP DEVICE_FLAGS EVENT; do
    if [ "$LID" -eq 0 ] || [ "$LID" -ge 254 ] || [ "$(awk -F'|' -v lid="$LID" '$1 == lid {n++} END {print n+0}' "$SEARCH_RESULTS")" -ne 1 ]; then
      warn "Skipping ambiguous or reserved LID $LID; profile requires individual addressing."
      continue
    fi
    if send_device_info_request "$LID"; then
      REQUESTED_COUNT=$((REQUESTED_COUNT + 1))
    else
      warn "Device Info request to LID $LID could not be sent."
    fi
    sleep 1
  done <"$SEARCH_RESULTS"
  stop_capture
  parse_info_capture
else
  REQUESTED_COUNT=0
  : >"$INFO_RESULTS"
fi

INFO_COUNT="$(wc -l <"$INFO_RESULTS" 2>/dev/null | tr -d ' ')"
INFO_COUNT="${INFO_COUNT:-0}"
if [ "$SEARCH_COUNT" -eq 0 ]; then
  :
elif [ "$INFO_COUNT" -eq 0 ]; then
  fail 'No valid Device Info responses were decoded.'
elif [ "$INFO_COUNT" -lt "$SEARCH_COUNT" ]; then
  warn "Decoded Device Info for $INFO_COUNT of $SEARCH_COUNT discovered devices."
else
  ok "Decoded Device Info for all $INFO_COUNT discovered devices."
fi

if [ -n "${IRIDI_BUS77_INVENTORY_FILE:-}" ]; then
  cat "$INFO_RESULTS" >"$IRIDI_BUS77_INVENTORY_FILE" || warn 'Could not export inventory for the traffic decoder.'
fi
if [ "$INFO_COUNT" -gt 0 ]; then
  printf '\n  %-4s %-24s %-10s %-8s %s\n' 'LID' 'MODEL' 'FIRMWARE' 'PROFILE' 'CAN ID'
  awk -F'|' '{printf "  %-4s %-24s %-10s %-8s 0x%s\n", $1, $5, $8, $7, $2}' "$INFO_RESULTS"
  while IFS='|' read -r LID CAN_ID NAME PRODUCER MODEL HWID FIRMWARE_ID VERSION CHANNELS TAGS GROUP DEVICE_CLASS PROCESSOR OPERATING_SYSTEM DEVICE_FLAGS USER_ID; do
    printf '\n  LID %s | %s\n' "$LID" "${MODEL:-unknown model}"
    printf '    Name:             %s\n' "${NAME:-not set}"
    printf '    Producer:         %s\n' "${PRODUCER:-not set}"
    printf '    HWID:             %s\n' "${HWID:-not set}"
    printf '    CAN device ID:    0x%s\n' "$CAN_ID"
    printf '    Firmware version: %s\n' "$VERSION"
    printf '    Firmware profile: %s (Firmware ID)\n' "$FIRMWARE_ID"
    printf '    Channels / tags:  %s / %s\n' "$CHANNELS" "$TAGS"
    printf '    Group/class:      %s / %s\n' "$GROUP" "$DEVICE_CLASS"
    printf '    Processor / OS:   %s / %s\n' "$PROCESSOR" "$OPERATING_SYSTEM"
    printf '    User ID:          %s\n' "$USER_ID"
  done <"$INFO_RESULTS"
fi

separator
printf 'SUMMARY\n'
printf '  Discovered devices: %s\n' "$SEARCH_COUNT"
printf '  Complete profiles:  %s\n' "$INFO_COUNT"
printf '  Read-only requests: 1 Search, %s Device Info\n' "$REQUESTED_COUNT"
printf '  Write operations:   none\n'
printf '  Failures:           %s\n' "$FAILURES"
printf '  Attention items:    %s\n' "$WARNINGS"
if [ "$FAILURES" -gt 0 ]; then
  printf 'RESULT: FAIL - NOT OK: Bus77 discovery could not be completed.\n'
  exit 2
fi
if [ "$WARNINGS" -gt 0 ]; then
  printf 'RESULT: WARN - ATTENTION REQUIRED: discovery completed with incomplete or questionable data.\n'
  exit 1
fi
printf 'RESULT: PASS - OK: all discovered Bus77 devices returned complete valid profiles.\n'
exit 0

)
# END GENERATED INVENTORY

# BEGIN GENERATED CARDS
show_bus_devices() {
  awk '
BEGIN { FS="|"; print "BUS DEVICES - verified identity data from this run" }
NF >= 9 {
    printf "\n  DEVICE %d | %s | LID %s\n", ++count, $1, $2
    print "  ------------------------------------------------------------"
    printf "  Model             : %s\n", ($6!=""?$6:"not reported")
    printf "  Device name       : %s\n", ($4!=""?$4:"not reported")
    printf "  HWID              : %s\n", ($7!=""?$7:"not reported")
    printf "  Firmware version  : %s\n", ($9!=""?$9:"not reported")
    printf "  Firmware profile  : %s (Firmware ID)\n", ($8!=""?$8:"not reported")
    printf "  CAN device ID     : 0x%s\n", $3
}
END {
    printf "\n  Devices with verified details: %d\n", count
    if(!count) print "  [ATTENTION] Device details are unavailable, not an empty-bus diagnosis.\n  Check the discovery messages above; --passive does not request identities."
    print "  Only devices that replied with valid identity data are included."
}
' "$INVENTORY_FILE"
}
# END GENERATED CARDS

cleanup() {
  if [ -n "$CAPTURE_PID" ]; then
    kill -INT "$CAPTURE_PID" 2>/dev/null
    wait "$CAPTURE_PID" 2>/dev/null
  fi
  [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --passive) PASSIVE_ONLY=1 ;;
    --scan-only|--inventory) SCAN_ONLY=1 ;;
    --json) JSON_OUTPUT=1 ;;
    --interface)
      [ "$#" -ge 2 ] || { printf 'RESULT: FAIL - missing interface.\n'; exit 2; }
      shift
      REQUESTED_INTERFACE="${1:-}"
      ;;
    --duration)
      [ "$#" -ge 2 ] || { printf 'RESULT: FAIL - missing duration.\n'; exit 2; }
      shift
      SAMPLE_SECONDS="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[NOT OK] Unknown argument: %s\n' "$1"
      usage
      printf 'RESULT: FAIL - NOT OK: invalid command-line arguments.\n'
      exit 2
      ;;
  esac
  shift
done

case "$SAMPLE_SECONDS" in
  ''|*[!0-9]*)
    printf '[NOT OK] Duration must be a whole number of seconds.\n'
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/iridi-can-check.XXXXXX" 2>/dev/null)"
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ]; then
  WORK_DIR="${TMPDIR:-/tmp}/iridi-can-check.$$"
  mkdir -m 700 "$WORK_DIR" || { WORK_DIR=""; exit 2; }
fi
CAPTURE_FILE="$WORK_DIR/capture.txt"
INVENTORY_FILE="$WORK_DIR/inventory.txt"
: >"$INVENTORY_FILE"

detect_interfaces() {
  for CAN_PATH in /sys/class/net/*; do
    [ -e "$CAN_PATH" ] || continue
    [ "$(cat "$CAN_PATH/type" 2>/dev/null)" = "280" ] || continue
    printf '%s\n' "${CAN_PATH##*/}"
  done
}

DETECTED_INTERFACES="$(detect_interfaces)"
if [ "$REQUESTED_INTERFACE" = "all" ]; then
  INTERFACES="$DETECTED_INTERFACES"
else
  INTERFACES="$REQUESTED_INTERFACE"
fi

printf 'iRidi CAN/Bus77 Diagnostic\n'
printf 'Script version: %s\n' "$SCRIPT_VERSION"
printf 'Started: %s\n' "$(date 2>/dev/null || echo unknown)"
printf 'Device: %s | %s | %s\n' "$(hostname 2>/dev/null || echo unknown)" "$(uname -s 2>/dev/null)" "$(uname -m 2>/dev/null)"
printf 'Log file: %s\n' "${IRIDI_CAN_LOG_FILE:-not set}"
if [ "$PASSIVE_ONLY" -eq 1 ]; then
  printf 'Mode: passive only; no CAN frames are transmitted\n'
else
  printf 'Mode: read-only device discovery, followed by passive bus health checks\n'
fi
printf 'Sample duration: %s seconds\n' "$SAMPLE_SECONDS"

separator
printf 'BUS77 DEVICE INVENTORY\n'
if [ "$PASSIVE_ONLY" -eq 1 ]; then
  warn 'Device inventory skipped in passive mode; model, HWID and profile are not requested.'
else
  for INVENTORY_INTERFACE in $INTERFACES; do
    printf '  %s: reading device identities and firmware profiles...\n' "$INVENTORY_INTERFACE"
    : >"$WORK_DIR/device.rows"
    IRIDI_BUS77_INVENTORY_FILE="$WORK_DIR/device.rows" run_bus77_inventory --interface "$INVENTORY_INTERFACE" >"$WORK_DIR/inventory.report" 2>&1
    INVENTORY_RC=$?
    if [ -s "$WORK_DIR/device.rows" ]; then
      awk -v dev="$INVENTORY_INTERFACE" '{print dev "|" $0}' "$WORK_DIR/device.rows" >>"$INVENTORY_FILE"
    fi
    awk '/\[NOT OK\]/ || /\[ATTENTION\]/ {print} /^RESULT:/ {sub(/^RESULT:/,"Inventory result:");print}' "$WORK_DIR/inventory.report"
    if [ "$INVENTORY_RC" -ne 0 ]; then
      printf '  Search identities (some detailed profiles may be missing):\n'
      awk '/LID.*CAN ID.*HWID/ {show=1} /^---/ {show=0} show {print}' "$WORK_DIR/inventory.report"
    fi
    case "$INVENTORY_RC" in
      0) ok "$INVENTORY_INTERFACE device inventory is complete for all responding devices." ;;
      1) warn "$INVENTORY_INTERFACE inventory is incomplete; see the inventory result above." ;;
      *) fail "$INVENTORY_INTERFACE inventory failed; bus health checks will still run." ;;
    esac
  done
fi

separator
show_bus_devices

if [ "$JSON_OUTPUT" -eq 1 ]; then
  separator
  printf 'JSON INVENTORY EXPORT:\n'
  awk -F'|' '
    BEGIN {
      printf "[\n"
    }
    NF >= 9 {
      if (count++) printf ",\n"
      printf "  {\n"
      printf "    \"interface\": \"%s\",\n", $1
      printf "    \"lid\": %d,\n", $2
      printf "    \"can_id\": \"0x%s\",\n", $3
      printf "    \"name\": \"%s\",\n", $4
      printf "    \"producer\": \"%s\",\n", $5
      printf "    \"model\": \"%s\",\n", $6
      printf "    \"hwid\": \"%s\",\n", $7
      printf "    \"firmware_profile\": %s,\n", ($8!=""?$8:"null")
      printf "    \"firmware_version\": \"%s\",\n", $9
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
    END {
      printf "\n]\n"
    }
  ' "$INVENTORY_FILE"
fi

if [ "$SCAN_ONLY" -eq 1 ]; then
  separator
  printf 'SUMMARY\n'
  DEV_COUNT="$(wc -l <"$INVENTORY_FILE" 2>/dev/null | tr -d ' ')"
  printf '  Interfaces: %s\n' "$(printf '%s' "$INTERFACES" | tr '\n' ' ')"
  printf '  Mode: scan only (health observation skipped)\n'
  printf '  Discovered devices: %s\n' "${DEV_COUNT:-0}"
  printf '  Failures: %s\n' "$FAILURES"
  printf '  Attention items: %s\n' "$WARNINGS"
  if [ "$FAILURES" -gt 0 ]; then
    printf 'RESULT: FAIL - NOT OK: device discovery failed.\n'
    exit 2
  elif [ "$WARNINGS" -gt 0 ]; then
    printf 'RESULT: WARN - ATTENTION REQUIRED: discovery completed with warnings.\n'
    exit 1
  else
    printf 'RESULT: PASS - OK: all discovered Bus77 devices returned complete valid profiles.\n'
    exit 0
  fi
fi

separator
printf 'BUS HEALTH\n'
printf '1. CAN interface discovery\n'
if [ -z "$DETECTED_INTERFACES" ]; then
  fail 'No SocketCAN interfaces were detected.'
fi
if [ -z "$INTERFACES" ]; then
  fail 'No CAN interface is available for diagnostics.'
else
  printf '  Selected interfaces: %s\n' "$(printf '%s' "$INTERFACES" | tr '\n' ' ')"
fi

if [ "$REQUESTED_INTERFACE" != "all" ]; then
  if [ ! -d "/sys/class/net/$REQUESTED_INTERFACE" ] || [ "$(cat "/sys/class/net/$REQUESTED_INTERFACE/type" 2>/dev/null)" != "280" ]; then
    fail "Interface $REQUESTED_INTERFACE is not an available SocketCAN interface."
    INTERFACES=""
  fi
fi

if ! command -v ip >/dev/null 2>&1; then
  fail 'The ip utility is required to read detailed CAN controller state.'
fi

snapshot_stats() {
  SNAPSHOT_INTERFACE="$1"
  SNAPSHOT_FILE="$2"
  : >"$SNAPSHOT_FILE"
  for SNAPSHOT_FIELD in rx_packets rx_bytes rx_errors rx_dropped tx_packets tx_bytes tx_errors tx_dropped; do
    SNAPSHOT_VALUE="$(cat "/sys/class/net/$SNAPSHOT_INTERFACE/statistics/$SNAPSHOT_FIELD" 2>/dev/null)"
    printf '%s=%s\n' "$SNAPSHOT_FIELD" "${SNAPSHOT_VALUE:-0}" >>"$SNAPSHOT_FILE"
  done
}

read_snapshot() {
  awk -F= -v key="$2" '$1 == key { print $2; exit }' "$1" 2>/dev/null
}

can_state() {
  ip -details link show "$1" 2>/dev/null | awk '
    /can .* state / {
      for (i = 1; i <= NF; i++) if ($i == "state") { print $(i + 1); exit }
    }
  '
}

can_bitrate() {
  ip -details link show "$1" 2>/dev/null | awk '
    / bitrate / {
      for (i = 1; i <= NF; i++) if ($i == "bitrate") { print $(i + 1); exit }
    }
  '
}

can_health_counters() {
  ip -details -statistics link show "$1" 2>/dev/null | awk '
    /re-started[[:space:]]+bus-errors[[:space:]]+arbit-lost/ {
      getline
      print $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6
      exit
    }
  '
}

for CAN_INTERFACE in $INTERFACES; do
  snapshot_stats "$CAN_INTERFACE" "$WORK_DIR/$CAN_INTERFACE.before"
  CAN_DETAILS="$(ip -details -statistics link show "$CAN_INTERFACE" 2>/dev/null)"
  CAN_STATE="$(can_state "$CAN_INTERFACE")"
  CAN_BITRATE="$(can_bitrate "$CAN_INTERFACE")"
  CAN_OPERSTATE="$(cat "/sys/class/net/$CAN_INTERFACE/operstate" 2>/dev/null)"
  CAN_CARRIER="$(cat "/sys/class/net/$CAN_INTERFACE/carrier" 2>/dev/null)"
  CAN_DRIVER_LINK="$(readlink "/sys/class/net/$CAN_INTERFACE/device/driver" 2>/dev/null)"
  CAN_DRIVER="${CAN_DRIVER_LINK##*/}"
  CAN_FLAGS="$(printf '%s\n' "$CAN_DETAILS" | awk '
    NR == 1 {
      line = $0
      sub(/^[^<]*</, "", line)
      sub(/>.*/, "", line)
      print line
      exit
    }
  ')"
  CAN_HEALTH="$(can_health_counters "$CAN_INTERFACE")"
  OLD_IFS=$IFS
  IFS='|'
  set -- $CAN_HEALTH
  IFS=$OLD_IFS
  CAN_RESTARTED="${1:-unknown}"
  CAN_BUS_ERRORS="${2:-unknown}"
  CAN_ARBIT_LOST="${3:-unknown}"
  CAN_ERROR_WARN="${4:-unknown}"
  CAN_ERROR_PASS="${5:-unknown}"
  CAN_BUS_OFF="${6:-unknown}"

  printf '\n  Interface: %s\n' "$CAN_INTERFACE"
  printf '    Driver:               %s\n' "${CAN_DRIVER:-not determined}"
  printf '    Link flags:           %s\n' "${CAN_FLAGS:-not determined}"
  printf '    Operational state:    %s\n' "${CAN_OPERSTATE:-not determined}"
  printf '    Carrier:              %s\n' "${CAN_CARRIER:-not determined}"
  printf '    CAN controller state: %s\n' "${CAN_STATE:-not determined}"
  printf '    Bitrate:              %s bit/s\n' "${CAN_BITRATE:-not determined}"
  printf '    Restarted:            %s\n' "$CAN_RESTARTED"
  printf '    Bus errors:           %s\n' "$CAN_BUS_ERRORS"
  printf '    Arbitration lost:     %s\n' "$CAN_ARBIT_LOST"
  printf '    Error-warning events: %s\n' "$CAN_ERROR_WARN"
  printf '    Error-passive events: %s\n' "$CAN_ERROR_PASS"
  printf '    Bus-off events:       %s\n' "$CAN_BUS_OFF"

  case "$CAN_FLAGS" in
    *UP*) : ;;
    *) fail "$CAN_INTERFACE is not administratively UP." ;;
  esac
  case "$CAN_STATE" in
    ERROR-ACTIVE) ok "$CAN_INTERFACE is currently ERROR-ACTIVE." ;;
    ERROR-WARNING|ERROR-PASSIVE) warn "$CAN_INTERFACE is currently $CAN_STATE." ;;
    BUS-OFF|STOPPED) fail "$CAN_INTERFACE is currently $CAN_STATE." ;;
    *) warn "The current CAN controller state of $CAN_INTERFACE could not be determined." ;;
  esac
  case "$CAN_ERROR_WARN:$CAN_ERROR_PASS:$CAN_BUS_OFF" in
    0:0:0|unknown:unknown:unknown) : ;;
    *) warn "$CAN_INTERFACE has recorded CAN state transitions since boot; compare repeated reports for growth." ;;
  esac
done

separator
printf '2. Active iRidi runtime and CAN gateway configuration\n'
IRIDI_PID="$(pidof iridium 2>/dev/null | awk '{print $1; exit}')"
ACTIVE_DATA_DIR=""
if [ -n "$IRIDI_PID" ]; then
  printf '  iRidi Server PID: %s\n' "$IRIDI_PID"
  printf '  Executable: %s\n' "$(readlink "/proc/$IRIDI_PID/exe" 2>/dev/null)"
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
  printf '  Active data directory: %s\n' "${ACTIVE_DATA_DIR:-not determined}"
else
  warn 'No running iridium process was detected.'
fi

GATEWAY_JSON=""
if [ -n "$ACTIVE_DATA_DIR" ] && [ -r "$ACTIVE_DATA_DIR/Documents/can_gateway.json" ]; then
  GATEWAY_JSON="$ACTIVE_DATA_DIR/Documents/can_gateway.json"
fi
if [ -n "$GATEWAY_JSON" ]; then
  printf '  Gateway configuration: %s\n' "$GATEWAY_JSON"
  for CAN_INTERFACE in $INTERFACES; do
    case "$CAN_INTERFACE" in
      can0)
        GATE_ACTIVE="$(sed -n 's/.*"Can0GateWayActive":\([^,}]*\).*/\1/p' "$GATEWAY_JSON")"
        GATE_LID="$(sed -n 's/.*"DeviceLid":\([^,}]*\).*/\1/p' "$GATEWAY_JSON")"
        GATE_UDP="$(sed -n 's/.*"UdpCan0":\([^,}]*\).*/\1/p' "$GATEWAY_JSON")"
        ;;
      can1)
        GATE_ACTIVE="$(sed -n 's/.*"Can1GateWayActive":\([^,}]*\).*/\1/p' "$GATEWAY_JSON")"
        GATE_LID="$(sed -n 's/.*"DeviceLidCan1":\([^,}]*\).*/\1/p' "$GATEWAY_JSON")"
        GATE_UDP="$(sed -n 's/.*"UdpCan1":\([^,}]*\).*/\1/p' "$GATEWAY_JSON")"
        ;;
      *) GATE_ACTIVE=unknown; GATE_LID=unknown; GATE_UDP=unknown ;;
    esac
    printf '    %s: gateway=%s, local LID=%s, UDP port=%s\n' "$CAN_INTERFACE" "${GATE_ACTIVE:-unknown}" "${GATE_LID:-unknown}" "${GATE_UDP:-unknown}"
  done
else
  warn 'The active CAN gateway configuration file was not found.'
fi

printf '  CAN gateway listeners:\n'
if command -v ss >/dev/null 2>&1; then
  ss -lntup 2>/dev/null | grep -E ':(30467|30468|65534)([[:space:]]|$)' | sed 's/^/    /' || printf '    none detected\n'
elif command -v netstat >/dev/null 2>&1; then
  netstat -lntup 2>/dev/null | grep -E ':(30467|30468|65534)([[:space:]]|$)' | sed 's/^/    /' || printf '    none detected\n'
else
  printf '    listener information unavailable\n'
fi

separator
printf '3. Passive traffic sample\n'
if [ -z "$INTERFACES" ]; then
  fail 'Traffic sampling cannot start without a CAN interface.'
elif ! command -v candump >/dev/null 2>&1; then
  warn 'candump is unavailable; only kernel counters can be evaluated.'
  sleep "$SAMPLE_SECONDS"
else
  printf '  Listening for %s seconds on: %s\n' "$SAMPLE_SECONDS" "$(printf '%s' "$INTERFACES" | tr '\n' ' ')"
  if command -v timeout >/dev/null 2>&1; then
    timeout "$SAMPLE_SECONDS" candump -x -e $INTERFACES >"$CAPTURE_FILE" 2>&1
    CAPTURE_RC=$?
    case "$CAPTURE_RC" in 0|124|137|143) : ;; *) warn "candump exited with status $CAPTURE_RC." ;; esac
  else
    candump -x -e $INTERFACES >"$CAPTURE_FILE" 2>&1 &
    CAPTURE_PID=$!
    sleep "$SAMPLE_SECONDS"
    kill -INT "$CAPTURE_PID" 2>/dev/null
    wait "$CAPTURE_PID" 2>/dev/null
    CAPTURE_PID=""
  fi
fi

for CAN_INTERFACE in $INTERFACES; do
  snapshot_stats "$CAN_INTERFACE" "$WORK_DIR/$CAN_INTERFACE.after"
  BEFORE_FILE="$WORK_DIR/$CAN_INTERFACE.before"
  AFTER_FILE="$WORK_DIR/$CAN_INTERFACE.after"
  RX_BEFORE="$(read_snapshot "$BEFORE_FILE" rx_packets)"
  TX_BEFORE="$(read_snapshot "$BEFORE_FILE" tx_packets)"
  RX_ERRORS_BEFORE="$(read_snapshot "$BEFORE_FILE" rx_errors)"
  TX_ERRORS_BEFORE="$(read_snapshot "$BEFORE_FILE" tx_errors)"
  RX_DROPPED_BEFORE="$(read_snapshot "$BEFORE_FILE" rx_dropped)"
  TX_DROPPED_BEFORE="$(read_snapshot "$BEFORE_FILE" tx_dropped)"
  RX_AFTER="$(read_snapshot "$AFTER_FILE" rx_packets)"
  TX_AFTER="$(read_snapshot "$AFTER_FILE" tx_packets)"
  RX_ERRORS_AFTER="$(read_snapshot "$AFTER_FILE" rx_errors)"
  TX_ERRORS_AFTER="$(read_snapshot "$AFTER_FILE" tx_errors)"
  RX_DROPPED_AFTER="$(read_snapshot "$AFTER_FILE" rx_dropped)"
  TX_DROPPED_AFTER="$(read_snapshot "$AFTER_FILE" tx_dropped)"
  RX_DELTA=$((RX_AFTER - RX_BEFORE))
  TX_DELTA=$((TX_AFTER - TX_BEFORE))
  RX_ERRORS_DELTA=$((RX_ERRORS_AFTER - RX_ERRORS_BEFORE))
  TX_ERRORS_DELTA=$((TX_ERRORS_AFTER - TX_ERRORS_BEFORE))
  RX_DROPPED_DELTA=$((RX_DROPPED_AFTER - RX_DROPPED_BEFORE))
  TX_DROPPED_DELTA=$((TX_DROPPED_AFTER - TX_DROPPED_BEFORE))

  printf '\n  Interface: %s\n' "$CAN_INTERFACE"
  printf '    RX frames during sample: %s\n' "$RX_DELTA"
  printf '    TX frames during sample: %s\n' "$TX_DELTA"
  printf '    New RX/TX errors:        %s / %s\n' "$RX_ERRORS_DELTA" "$TX_ERRORS_DELTA"
  printf '    New RX/TX drops:         %s / %s\n' "$RX_DROPPED_DELTA" "$TX_DROPPED_DELTA"
  if [ "$RX_DELTA" -gt 0 ]; then
    ok "$CAN_INTERFACE received physical bus traffic during the sample."
  elif [ "$TX_DELTA" -gt 0 ]; then
    warn "$CAN_INTERFACE transmitted frames but received no frames during the sample."
  else
    warn "$CAN_INTERFACE was silent during the sample; this does not prove that the port is faulty."
  fi
  if [ "$RX_ERRORS_DELTA" -gt 0 ] || [ "$TX_ERRORS_DELTA" -gt 0 ] || [ "$RX_DROPPED_DELTA" -gt 0 ] || [ "$TX_DROPPED_DELTA" -gt 0 ]; then
    warn "$CAN_INTERFACE recorded new errors or dropped frames during the sample."
  fi
done

separator
printf 'SUMMARY\n'
printf '  Interfaces: %s\n' "$(printf '%s' "$INTERFACES" | tr '\n' ' ')"
printf '  Passive sample: %s seconds\n' "$SAMPLE_SECONDS"
printf '  Failures: %s\n' "$FAILURES"
printf '  Attention items: %s\n' "$WARNINGS"
if [ "$FAILURES" -gt 0 ]; then
  printf 'RESULT: FAIL - NOT OK: the CAN subsystem has a critical problem or could not be checked.\n'
  exit 2
fi
if [ "$WARNINGS" -gt 0 ]; then
  printf 'RESULT: WARN - ATTENTION REQUIRED: CAN is available, but one or more findings need review.\n'
  exit 1
fi
printf 'RESULT: PASS - OK: CAN is operational and traffic was observed without new errors.\n'
exit 0
