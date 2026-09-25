#!/bin/sh

case "${1:-}" in
  -h|--help)
    printf 'Usage: sh %s [--interface can0|all] [--duration SECONDS] [--passive] [--lid N] [--cmd COMMAND] [--raw] [--ping LID [--count N]]\n' "${0##*/}"
    printf '%s\n' 'Default: read device identities and check for conflicts, then monitor live decoded traffic.'
    printf '%s\n' 'Options:'
    printf '%s\n' '  --duration SECONDS   Capture duration in seconds (default: 60).'
    printf '%s\n' '  --passive            Skip active identity discovery; show bus addresses only.'
    printf '%s\n' '  --lid LID            Filter live output to show only packets involving specified LID.'
    printf '%s\n' '  --cmd COMMAND        Filter live output by command name (e.g. SetVariable, Search).'
    printf '%s\n' '  --raw                Show raw CAN frame payload alongside decoded packet.'
    printf '%s\n' '  --ping LID           Ping a specific Bus77 device by LID and measure response RTT (ms).'
    printf '%s\n' '  --count N            Number of ping requests to send in --ping mode (default: 4).'
    exit 0
    ;;
esac

# Read device identities, detect conflicts, passively decode live CAN/Bus77 messages,
# calculate bus load, report top talkers, or ping specific devices.
# Interface settings are never changed.

# Setup logging directory & technical log file
CURRENT_DIR="$(pwd 2>/dev/null || printf '.')"
LOG_DIR="${IRIDI_DIAG_LOG_DIR:-$CURRENT_DIR}"
if [ ! -d "$LOG_DIR" ] || [ ! -w "$LOG_DIR" ]; then
  LOG_DIR="${TMPDIR:-/tmp}"
fi

HOST_LABEL="$(hostname 2>/dev/null || printf server)"
HOST_LABEL="$(printf '%s' "$HOST_LABEL" | tr -c 'A-Za-z0-9._-' '_')"
[ -n "$HOST_LABEL" ] || HOST_LABEL=server
TIMESTAMP="$(date '+%Y%m%d_%H%M%S' 2>/dev/null || printf unknown_time)"
LOG_FILE="$LOG_DIR/can_monitor_${HOST_LABEL}_${TIMESTAMP}_$$.log"

# Open File Descriptor 3 for technical log
if ! exec 3>>"$LOG_FILE" 2>/dev/null; then
  LOG_FILE="${TMPDIR:-/tmp}/can_monitor_${HOST_LABEL}_${TIMESTAMP}_$$.log"
  if ! exec 3>>"$LOG_FILE"; then
    printf '[NOT OK] Could not open log file for writing: %s\n' "$LOG_FILE" >&2
    exit 2
  fi
fi

# Terminal colors (screen only)
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
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

set +e
export LC_ALL=C

SCRIPT_VERSION=2.2
PASSIVE_ONLY=0
REQUESTED_INTERFACE=all
MONITOR_SECONDS=60
FILTER_LID=""
FILTER_CMD=""
SHOW_RAW=0
PING_MODE=0
PING_LID=""
PING_COUNT=4
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
  printf '%s\n' 'Usage: sh monitor_can_bus.sh [--interface can0|all] [--duration SECONDS] [--passive] [--lid N] [--cmd CMD] [--raw] [--ping LID [--count N]]'
  printf '%s\n' 'Defaults: read-only inventory, conflict check, then decoded passive monitor with top talkers and bus load.'
  printf '%s\n' 'Use --passive to skip identity requests and display addresses without model names.'
  printf '%s\n' 'Use --lid N or --cmd CMD to filter displayed live stream.'
  printf '%s\n' 'Use --ping LID to test responsiveness and round-trip latency of a specific Bus77 device.'
}

# BEGIN GENERATED INVENTORY
run_bus77_inventory() (
  export IRIDI_BUS77_SCAN_LOG_ACTIVE=1

  case "${1:-}" in
    -h|--help)
      printf '%s\n' 'Usage: sh scan_bus77_devices.sh [--interface can0] [--timeout SECONDS]' 'Sends only read-only Bus77 Search and Device Info requests.'
      exit 0
      ;;
  esac

  CAN_INTERFACE=can0
  RESPONSE_TIMEOUT=5
  SCANNER_CAN_ID=65534
  SCANNER_LID=254
  INV_WARNINGS=0
  INV_FAILURES=0
  INV_CAPTURE_PID=""
  INV_WORK_DIR=""

  inv_cleanup() {
    if [ -n "$INV_CAPTURE_PID" ]; then
      kill -INT "$INV_CAPTURE_PID" 2>/dev/null
      wait "$INV_CAPTURE_PID" 2>/dev/null
    fi
    [ -n "$INV_WORK_DIR" ] && rm -rf "$INV_WORK_DIR"
  }
  trap inv_cleanup EXIT
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
    esac
    shift
  done

  case "$CAN_INTERFACE" in
    ''|*[!A-Za-z0-9_.:-]*)
      printf '[NOT OK] Invalid interface name: %s\n' "$CAN_INTERFACE"
      exit 2
      ;;
  esac

  INV_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/iridi-bus77-scan.XXXXXX" 2>/dev/null)"
  if [ -z "$INV_WORK_DIR" ] || [ ! -d "$INV_WORK_DIR" ]; then
    INV_WORK_DIR="${TMPDIR:-/tmp}/iridi-bus77-scan.$$"
    mkdir -m 700 "$INV_WORK_DIR" || exit 2
  fi
  SEARCH_CAPTURE="$INV_WORK_DIR/search.capture"
  SEARCH_RESULTS="$INV_WORK_DIR/search.results"
  INFO_CAPTURE="$INV_WORK_DIR/info.capture"
  INFO_RESULTS="$INV_WORK_DIR/info.results"
  : >"$SEARCH_RESULTS"
  : >"$INFO_RESULTS"

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
    INV_CAPTURE_PID=$!
    sleep 1
    kill -0 "$INV_CAPTURE_PID" 2>/dev/null || return 1
  }

  stop_capture() {
    sleep "$RESPONSE_TIMEOUT"
    kill -INT "$INV_CAPTURE_PID" 2>/dev/null
    wait "$INV_CAPTURE_PID" 2>/dev/null
    INV_CAPTURE_PID=""
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

  if ! start_capture "$SEARCH_CAPTURE"; then
    printf 'RESULT: FAIL - NOT OK: packet capture could not start; no requests sent.\n'
    exit 2
  fi
  send_search_request
  stop_capture
  parse_search_capture

  # Check for LID conflicts (multiple distinct HWIDs on same LID)
  CONFLICT_LIDS="$(awk -F'|' '{ lids[$1]++; hwids[$1] = (hwids[$1] ? hwids[$1] " " $3 : $3) } END { for (l in lids) if (lids[l] > 1) printf "LID_%d:%s\n", l, hwids[l] }' "$SEARCH_RESULTS")"
  if [ -n "$CONFLICT_LIDS" ]; then
    for CF in $CONFLICT_LIDS; do
      printf '  [NOT OK] LID Conflict Detected: %s (devices sharing same Logical ID)\n' "$CF"
      INV_FAILURES=$((INV_FAILURES + 1))
    done
  fi

  SEARCH_COUNT="$(wc -l <"$SEARCH_RESULTS" 2>/dev/null | tr -d ' ')"
  SEARCH_COUNT="${SEARCH_COUNT:-0}"

  if [ "$SEARCH_COUNT" -gt 0 ]; then
    if ! start_capture "$INFO_CAPTURE"; then
      exit 2
    fi
    while IFS='|' read -r LID CAN_ID HWID GROUP DEVICE_FLAGS EVENT; do
      [ "$LID" -eq 0 ] || [ "$LID" -ge 254 ] && continue
      send_device_info_request "$LID"
      sleep 1
    done <"$SEARCH_RESULTS"
    stop_capture
    parse_info_capture
  fi

  if [ -n "${IRIDI_BUS77_INVENTORY_FILE:-}" ]; then
    cat "$INFO_RESULTS" >"$IRIDI_BUS77_INVENTORY_FILE"
  fi
  if [ "$INV_FAILURES" -gt 0 ]; then
    exit 2
  fi
  exit 0
)
# END GENERATED INVENTORY

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

# BEGIN GENERATED DECODER
decode_bus77_traffic() {
  awk -v inventory="$INVENTORY_FILE" -v status="$WORK_DIR/decoder.status" \
      -v top_talkers_file="$WORK_DIR/top_talkers.txt" \
      -v filter_lid="$FILTER_LID" -v filter_cmd="$FILTER_CMD" -v show_raw="$SHOW_RAW" '
function hx(s, i,n) { n=0; for(i=1;i<=length(s);i++) n=n*16+index("0123456789ABCDEF",toupper(substr(s,i,1)))-1; return n }
function pow2(n, i,r) { if(n in powers)return powers[n];r=1;for(i=0;i<n;i++)r*=2;for(i=0;i>n;i--)r/=2;powers[n]=r;return r }
function bit(n,p) { return int(n/pow2(p))%2 }
function bxor(a,b, n,p) { n=0;p=1;while(a||b){if(a%2!=b%2)n+=p;a=int(a/2);b=int(b/2);p*=2}return n }
function crcstep(c,b,i) { c=bxor(c,b);for(i=0;i<8;i++)c=bxor(int(c/2),c%2?40961:0);return c }
function uint(p,size, i,n) { n=0;for(i=0;i<size;i++)n+=bytes[p+i]*pow2(8*i);return n }
function raw(p,end, i,s) { s="";for(i=p;i<end;i++)s=s sprintf("%02X",bytes[i]) (i+1<end?" ":"");return s }
function clean(s) { gsub(/[[:cntrl:]|]/,"?",s);return s }
function label(dev,addr,can,local, k,s) {
    s=(addr>=256?"S" int(addr/256) ":":"") "LID " addr%256
    if(local || servers[dev SUBSEP addr]) return "SERVER/GW(" s ")"
    k=dev SUBSEP addr
    if(addr<256 && names[k]!="" && names[k]!="AMBIGUOUS" && (can=="" || identities[k]==can)) s=s " " names[k]
    if(can!="") s=s " [" can "]"
    return s
}
function value(p,end, t,present,size,n,exponent,mantissa,i,s) {
    value_end=p; value_ok=0
    if(p>=end)return "<missing value>"
    t=bytes[p]%128;present=bit(bytes[p++],7);value_end=p
    if(t==0){value_ok=1;return "NONE"}
    if(t==1){value_ok=1;return present?"true":"false"}
    if(t==2||t==3)size=1
    else if(t==4||t==5)size=2
    else if(t==6||t==7||t==8)size=4
    else if(t==9||t==10||t==11)size=8
    else if(t==12||t==15){
        if(!present){value_ok=1;return t==12?"\"\"":"[]"}
        if(p+2>end)return "<truncated length>"
        size=uint(p,2);p+=2
        if(p+size>end)return "<truncated string/array>"
        value_end=p+size;value_ok=1
        if(t==15)return "bytes[" raw(p,p+size) "]"
        s="";for(i=p;i<p+size;i++)if(bytes[i])s=s sprintf("%c",bytes[i])
        return "\"" clean(s) "\""
    } else return "<unsupported type " t ">"
    if(!present){value_ok=1;return "0"}
    if(p+size>end)return "<truncated value>"
    value_end=p+size;value_ok=1
    if(t==9||t==10||t==11)return "type=" t " LE-hex=" raw(p,p+size)
    n=uint(p,size)
    if(t==2||t==4||t==6){if(n>=pow2(size*8-1))n-=pow2(size*8);return sprintf("%.0f",n)}
    if(t!=8)return sprintf("%.0f",n)
    exponent=int(n/8388608)%256;mantissa=n%8388608
    if(exponent==255)return mantissa?"NaN":(bit(n,31)?"-Inf":"+Inf")
    n=(exponent?1+mantissa/8388608:mantissa/8388608)*pow2((exponent?exponent:1)-127)
    return sprintf("%.7g",n*(bit(bytes[p+3],7)?-1:1))
}
function details(cmd,response,p,end, s,id,v) {
    if(cmd==8||cmd==5||cmd==80||cmd==81||cmd==82)return "payload hidden (sensitive/control data)"
    if(p==end)return response?"acknowledgement":"no payload"
    if(cmd==16&&!response){
        v=value(p,end);p=value_end
        if(value_ok&&p+2<=end)return "variable=" uint(p,2) " value=" v
        return "unparsed variable payload"
    }
    if(cmd==17&&p+2<=end){
        s="variable=" uint(p,2);p+=2
        if(response)s=s " value=" value(p,end)
        return s
    }
    if((cmd==38||cmd==39||cmd==51||cmd==54)&&p+4<=end){
        s=(cmd==38||cmd==39?"tag=":"channel=") uint(p,4);p+=4
        if((!response&&(cmd==38||cmd==51))||(response&&(cmd==39||cmd==54)))s=s " value=" value(p,end)
        return s
    }
    if((cmd==37||cmd==53)&&p+4<=end)return "id=" uint(p,4) " data=" raw(p+4,end)
    if(cmd==3&&!response)return sprintf("capability mask=0x%02X",bytes[p])
    return "data=" raw(p,end)
}
function report_bad(reason) {
    bad++;printf "%s %-5s %-2s [ATTENTION] CAN %s: %s\n",strftime("%H:%M:%S"),dev,direction,can,reason;fflush()
}
function packet(n, i,flags,p,srcseg,src,dstseg,dst,body,end,c,cmd,mflags,response,tid,from,to,what,route,k,cmd_name,pass_filter) {
    if(n<8 || bytes[0]%128!=117 && bytes[0]%128!=125){report_bad("not a complete supported Bus77 packet");return}
    flags=bytes[1];p=3
    if(bit(flags,7))p++
    srcseg=0;if(bit(flags,6))srcseg=bytes[p++]
    src=srcseg*256+bytes[p++]
    dstseg=0;if(bit(flags,5))dstseg=bytes[p++]
    dst=bit(bytes[0],3)?dstseg*256+bytes[p++]:-1
    body=p;end=body+bytes[2]-2
    if(int(flags/8)%4>1 || n!=end+2 || end<body+2){report_bad("unsupported header or incomplete packet");return}
    c=65535;for(i=body;i<end;i++)c=crcstep(c,bytes[i])
    if(c!=uint(end,2)){report_bad("CRC mismatch; payload not decoded");return}
    if(direction=="TX")servers[dev SUBSEP src]=1
    from=label(dev,src,can,direction=="TX")
    to=dst<0?"ALL (broadcast)":label(dev,dst,"",0)
    cmd_name="UNKNOWN"
    if(flags%8){what="ENCRYPTED (not decoded)"; cmd_name="ENCRYPTED"}
    else {
        mflags=bytes[p++];cmd=bytes[p++];response=bit(mflags,7)
        if(mflags%16!=1){report_bad("unsupported message version");return}
        tid="none";if(!bit(mflags,5)){if(p+2>end){report_bad("missing transaction ID");return};tid=uint(p,2);p+=2}
        cmd_name=(commands[cmd]!=""?commands[cmd]:sprintf("UNKNOWN_0x%02X",cmd))
        what=(response?"RESPONSE ":"REQUEST ") cmd_name " tid=" tid
        if(cmd==8||cmd==5||cmd==80||cmd==81||cmd==82)what=what " | payload hidden (sensitive/control data)"
        else if(bit(mflags,6))what=what " ERROR data=" raw(p,end)
        else if(!bit(mflags,4))what=what " MORE (message fragment) data=" raw(p,end)
        else what=what " | " details(cmd,response,p,end)
    }

    # Record Top Talkers stats
    dev_name = (names[dev SUBSEP src]!=""?names[dev SUBSEP src]:"Bus77 Module")
    talker_key = (direction=="TX" ? "LOCAL_SERVER" : sprintf("LID_%d|%s|%s", src, dev_name, can))
    talker_counts[talker_key]++

    # Filter checks
    pass_filter = 1
    if(filter_lid != "" && filter_lid != sprintf("%d", src) && (dst < 0 || filter_lid != sprintf("%d", dst))) pass_filter = 0
    if(filter_cmd != "" && toupper(cmd_name) !~ toupper(filter_cmd)) pass_filter = 0

    if(pass_filter) {
        if(show_raw && last_raw_frame[dev] != "") {
            printf "[RAW: %s] ", last_raw_frame[dev]
        }
        printf "%s %-5s %-2s %s -> %s | %s\n",strftime("%H:%M:%S"),dev,direction,from,to,what
        fflush()
    }
    good++;route=dev SUBSEP from SUBSEP to;routes[route]++
}
BEGIN {
    commands[2]="Ping";commands[3]="Search";commands[4]="DeviceInfo";commands[5]="SetLID";commands[8]="SessionToken";commands[10]="SmartAPI";commands[11]="Blink"
    commands[16]="SetVariable";commands[17]="GetVariable";commands[18]="DeleteVariables"
    commands[32]="GetTags";commands[36]="LinkTagVariable";commands[37]="GetTagDescription";commands[38]="SetTagValue";commands[39]="GetTagValue"
    commands[48]="GetChannels";commands[51]="SetChannelValue";commands[52]="LinkChannelVariable";commands[53]="GetChannelDescription";commands[54]="GetChannelValue"
    commands[80]="StreamOpen";commands[81]="StreamBlock";commands[82]="StreamClose";commands[96]="GetScenarios";commands[97]="GetScenario";commands[98]="SetScenario"
    if(inventory!="")while((getline line < inventory)>0){
        split(line,f,"|");k=f[1] SUBSEP f[2]
        if(names[k]!=""&&identities[k]!=f[3])names[k]="AMBIGUOUS"
        else if(names[k]!="AMBIGUOUS"){names[k]=clean(f[6]);identities[k]=f[3]}
    }
    close(inventory)
}
$2=="RX" || $2=="TX" {
    dev=$1;direction=$2;id=toupper($5);can=id
    if(length(id)!=8||id!~/^[01][0-9A-F]+$/){report_bad("CAN error or non-extended frame (not decoded)");next}
    number=hx(id);can=sprintf("%04X",int(number/8192)%65536)
    key=dev SUBSEP direction SUBSEP int(number/2)
    last_raw_frame[dev]=$0
    for(i=7;i<=NF;i++)if(length($i)==2&&toupper($i)~/^[0-9A-F]+$/){
        if(count[key]<264)data[key,count[key]++]=hx($i);else overflow[key]=1
    }
    if(number%2){
        if(overflow[key])report_bad("oversized/reassembly gap")
        else{for(i=0;i<count[key];i++)bytes[i]=data[key,i];packet(count[key])}
        for(i=0;i<count[key];i++)delete data[key,i]
        delete count[key];delete overflow[key]
    }
    next
}
{ if($0!="") {bad++;print "[ATTENTION] Capture: " clean($0);fflush()} }
END {
    for(k in count)if(count[k])incomplete++
    printf "\nDecoded traffic routes (Bus77 packets, not CAN frames):\n"
    for(k in routes){split(k,f,SUBSEP);printf "  %s %s -> %s : %d packets\n",f[1],f[2],f[3],routes[k]}
    printf "Decoder: %d valid packets, %d undecoded/corrupt frames or packets, %d unfinished packets.\n",good,bad,incomplete
    if(status!=""){printf "%d\n",bad+incomplete > status;close(status)}
    if(top_talkers_file!=""){
        for(t in talker_counts) printf "%s|%d\n", t, talker_counts[t] > top_talkers_file
        close(top_talkers_file)
    }
    fflush()
}
'
}
# END GENERATED DECODER

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

# Dedicated Bus77 Device Ping & Latency RTT Test
run_bus77_ping() {
  TARGET_LID="$1"
  COUNT="${2:-4}"
  INTERFACE="${3:-can0}"

  printf 'Bus77 Device Ping & Latency Diagnostic\n'
  printf 'Script version: %s\n' "$SCRIPT_VERSION"
  printf 'Target LID: %s\n' "$TARGET_LID"
  printf 'Interface: %s\n' "$INTERFACE"
  printf 'Probes to send: %s\n' "$COUNT"
  separator

  if [ ! -d "/sys/class/net/$INTERFACE" ]; then
    fail "Interface $INTERFACE not found."
    exit 2
  fi
  CUR_STATE="$(can_state "$INTERFACE")"
  if [ "$CUR_STATE" != "ERROR-ACTIVE" ]; then
    warn "Interface $INTERFACE is currently in state $CUR_STATE."
  fi

  SCANNER_CAN_ID=65534
  TARGET_LID_HEX="$(awk -v value="$TARGET_LID" 'BEGIN { printf "%02X", value }')"
  REQUEST_TID_LOW="$TARGET_LID"
  REQUEST_TID_HIGH=80
  REQUEST_CRC="$(awk '
    BEGIN {
      crc = 65535
      bytes[1]=17; bytes[2]=4; bytes[3]='"$REQUEST_TID_LOW"'; bytes[4]='"$REQUEST_TID_HIGH"'
      for (i = 1; i <= 4; i++) {
        crc = xor(crc, bytes[i])
        for (bit = 0; bit < 8; bit++) {
          if (and(crc, 1)) crc = xor(rshift(crc, 1), 40961)
          else crc = rshift(crc, 1)
        }
      }
      printf "%02X%02X", and(crc, 255), and(rshift(crc, 8), 255)
      exit
    }
  ')"
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

  SENT=0
  RECEIVED=0
  LATENCIES=""
  PING_LOG="$WORK_DIR/ping_raw.log"

  for SEQ in $(awk -v n="$COUNT" 'BEGIN { for (i=1;i<=n;i++) print i }'); do
    SENT=$((SENT + 1))
    : >"$PING_LOG"
    
    candump -t a -x "$INTERFACE" >"$PING_LOG" 2>&1 &
    DUMP_PID=$!
    sleep 0.1
    
    START_NS="$(date +%s%N 2>/dev/null)"
    cansend "$INTERFACE" "${REQUEST_CAN_ID}#7D0806FE${TARGET_LID_HEX}1104${TARGET_LID_HEX}" >/dev/null 2>&1
    cansend "$INTERFACE" "${REQUEST_CAN_ID_END}#50${REQUEST_CRC}" >/dev/null 2>&1
    
    REPLY_FOUND=0
    ELAPSED_MS=0
    for TICK in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
      sleep 0.1
      if grep -q "RX.*${TARGET_LID_HEX}" "$PING_LOG" 2>/dev/null; then
        END_NS="$(date +%s%N 2>/dev/null)"
        if [ -n "$START_NS" ] && [ -n "$END_NS" ] && [ "$END_NS" -ge "$START_NS" ]; then
          ELAPSED_MS="$(awk -v s="$START_NS" -v e="$END_NS" 'BEGIN { printf "%.1f", (e - s)/1000000 }')"
        else
          ELAPSED_MS="$(awk -v t="$TICK" 'BEGIN { printf "%.1f", t * 100 }')"
        fi
        REPLY_FOUND=1
        break
      fi
    done
    
    kill -INT "$DUMP_PID" 2>/dev/null
    wait "$DUMP_PID" 2>/dev/null
    
    if [ "$REPLY_FOUND" -eq 1 ]; then
      RECEIVED=$((RECEIVED + 1))
      LATENCIES="${LATENCIES}${ELAPSED_MS} "
      printf '  Probe %d: Reply from LID %s in %s ms [OK]\n' "$SEQ" "$TARGET_LID" "$ELAPSED_MS"
    else
      printf '  Probe %d: Request timed out (no response from LID %s within 1500 ms) [FAIL]\n' "$SEQ" "$TARGET_LID"
    fi
    sleep 0.5
  done

  separator
  printf 'PING STATISTICS for LID %s\n' "$TARGET_LID"
  LOSS_PERCENT="$(awk -v s="$SENT" -v r="$RECEIVED" 'BEGIN { if (s>0) printf "%.0f", ((s-r)/s)*100; else print 100 }')"
  printf '  Packets: Sent = %d, Received = %d, Lost = %d (%s%% loss)\n' "$SENT" "$RECEIVED" "$((SENT - RECEIVED))" "$LOSS_PERCENT"

  if [ "$RECEIVED" -gt 0 ]; then
    STATS="$(awk -v vals="$LATENCIES" '
      BEGIN {
        split(vals, a, " ")
        n = 0; min = 999999; max = 0; sum = 0
        for (i in a) {
          v = a[i] + 0
          if (v <= 0) continue
          n++
          if (v < min) min = v
          if (v > max) max = v
          sum += v
        }
        if (n > 0) {
          avg = sum / n
          diff_sum = 0
          for (i = 2; i <= n; i++) {
            d = a[i] - a[i-1]
            if (d < 0) d = -d
            diff_sum += d
          }
          jitter = (n > 1) ? diff_sum / (n - 1) : 0
          printf "min=%.1f ms, avg=%.1f ms, max=%.1f ms, jitter=%.1f ms", min, avg, max, jitter
        }
      }
    ')"
    printf '  Round trip times: %s\n' "$STATS"
    if [ "$RECEIVED" -eq "$SENT" ]; then
      printf 'RESULT: PASS - LID %s is highly responsive with 0%% packet loss.\n' "$TARGET_LID"
      exit 0
    else
      printf 'RESULT: WARN - LID %s responded with partial packet loss (%s%% loss).\n' "$TARGET_LID" "$LOSS_PERCENT"
      exit 1
    fi
  else
    printf 'RESULT: FAIL - LID %s did not respond to any ping requests (100%% loss).\n' "$TARGET_LID"
    exit 2
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --passive) PASSIVE_ONLY=1 ;;
    --raw) SHOW_RAW=1 ;;
    --interface)
      [ "$#" -ge 2 ] || { printf 'RESULT: FAIL - missing interface.\n'; exit 2; }
      shift
      REQUESTED_INTERFACE="${1:-}"
      ;;
    --duration)
      [ "$#" -ge 2 ] || { printf 'RESULT: FAIL - missing duration.\n'; exit 2; }
      shift
      MONITOR_SECONDS="${1:-}"
      ;;
    --lid)
      [ "$#" -ge 2 ] || { printf 'RESULT: FAIL - missing LID.\n'; exit 2; }
      shift
      FILTER_LID="${1:-}"
      ;;
    --cmd)
      [ "$#" -ge 2 ] || { printf 'RESULT: FAIL - missing command name.\n'; exit 2; }
      shift
      FILTER_CMD="${1:-}"
      ;;
    --ping)
      [ "$#" -ge 2 ] || { printf 'RESULT: FAIL - missing LID for ping.\n'; exit 2; }
      shift
      PING_MODE=1
      PING_LID="${1:-}"
      ;;
    --count)
      [ "$#" -ge 2 ] || { printf 'RESULT: FAIL - missing ping count.\n'; exit 2; }
      shift
      PING_COUNT="${1:-}"
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

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/iridi-can-monitor.XXXXXX" 2>/dev/null)"
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ]; then
  WORK_DIR="${TMPDIR:-/tmp}/iridi-can-monitor.$$"
  mkdir -m 700 "$WORK_DIR" || { WORK_DIR=""; exit 2; }
fi
CAPTURE_FILE="$WORK_DIR/capture.txt"
INVENTORY_FILE="$WORK_DIR/inventory.txt"
: >"$INVENTORY_FILE"

cleanup() {
  if [ -n "$CAPTURE_PID" ]; then
    kill -INT "$CAPTURE_PID" 2>/dev/null
    wait "$CAPTURE_PID" 2>/dev/null
  fi
  [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

if [ "$PING_MODE" -eq 1 ]; then
  IFACE="${REQUESTED_INTERFACE:-can0}"
  [ "$IFACE" = "all" ] && IFACE=can0
  run_bus77_ping "$PING_LID" "$PING_COUNT" "$IFACE"
  exit $?
fi

case "$MONITOR_SECONDS" in
  ''|*[!0-9]*)
    printf '[NOT OK] Duration must be a whole number of seconds.\n'
    printf 'RESULT: FAIL - NOT OK: invalid monitor duration.\n'
    exit 2
    ;;
esac
if [ "$MONITOR_SECONDS" -lt 1 ] || [ "$MONITOR_SECONDS" -gt 86400 ]; then
  printf '[NOT OK] Duration must be between 1 and 86400 seconds.\n'
  printf 'RESULT: FAIL - NOT OK: invalid monitor duration.\n'
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

printf 'iRidi CAN/Bus77 Live Monitor & Bus Analyzer\n'
printf 'Script version: %s\n' "$SCRIPT_VERSION"
printf 'Started: %s\n' "$(date 2>/dev/null || echo unknown)"
printf 'Device: %s | %s | %s\n' "$(hostname 2>/dev/null || echo unknown)" "$(uname -s 2>/dev/null)" "$(uname -m 2>/dev/null)"
printf 'Log file: %s\n' "${IRIDI_CAN_MONITOR_LOG_FILE:-not set}"
if [ "$PASSIVE_ONLY" -eq 1 ]; then
  printf 'Mode: passive only; no CAN frames are transmitted\n'
else
  printf 'Mode: read-only identity & conflict check, then passive decoded monitoring\n'
fi
printf 'Monitor duration: %s seconds\n' "$MONITOR_SECONDS"
[ -n "$FILTER_LID" ] && printf 'Filter LID: %s\n' "$FILTER_LID"
[ -n "$FILTER_CMD" ] && printf 'Filter Command: %s\n' "$FILTER_CMD"
[ "$SHOW_RAW" -eq 1 ] && printf 'Raw frame display: enabled\n'

if [ -z "$INTERFACES" ]; then
  fail 'No SocketCAN interfaces were detected.'
fi
if [ "$REQUESTED_INTERFACE" != "all" ]; then
  if [ ! -d "/sys/class/net/$REQUESTED_INTERFACE" ] || [ "$(cat "/sys/class/net/$REQUESTED_INTERFACE/type" 2>/dev/null)" != "280" ]; then
    fail "Interface $REQUESTED_INTERFACE is not an available SocketCAN interface."
    INTERFACES=""
  fi
fi
if ! command -v candump >/dev/null 2>&1; then
  fail 'candump is required for live packet monitoring.'
fi
if ! command -v ip >/dev/null 2>&1; then
  fail 'ip is required to inspect the CAN controller.'
fi
if ! awk 'BEGIN {print strftime("%H:%M:%S"); fflush()}' >/dev/null 2>&1; then
  fail 'awk with strftime and fflush is required (available in the supported BusyBox firmware).'
fi

separator
printf 'Selected interfaces and initial state\n'
PRIMARY_BITRATE=125000
for CAN_INTERFACE in $INTERFACES; do
  snapshot_stats "$CAN_INTERFACE" "$WORK_DIR/$CAN_INTERFACE.before"
  INITIAL_STATE="$(can_state "$CAN_INTERFACE")"
  INITIAL_BITRATE="$(ip -details link show "$CAN_INTERFACE" 2>/dev/null | awk '/ bitrate / { for (i=1;i<=NF;i++) if ($i=="bitrate") {print $(i+1); exit} }')"
  [ -n "$INITIAL_BITRATE" ] && PRIMARY_BITRATE="$INITIAL_BITRATE"
  printf '  %s: state=%s, bitrate=%s bit/s\n' "$CAN_INTERFACE" "${INITIAL_STATE:-not determined}" "${INITIAL_BITRATE:-not determined}"
  case "$INITIAL_STATE" in
    BUS-OFF|STOPPED) fail "$CAN_INTERFACE is currently $INITIAL_STATE." ;;
    ERROR-WARNING|ERROR-PASSIVE) warn "$CAN_INTERFACE is currently $INITIAL_STATE." ;;
  esac
done

separator
printf 'DEVICE DIRECTORY & ADDRESS CONFLICT CHECK\n'
if [ "$PASSIVE_ONLY" -eq 1 ]; then
  printf '  Passive mode: devices are identified by their bus addresses.\n'
elif [ "$FAILURES" -eq 0 ]; then
  for INVENTORY_INTERFACE in $INTERFACES; do
    printf '  %s: reading device identities and checking for conflicts...\n' "$INVENTORY_INTERFACE"
    IRIDI_BUS77_INVENTORY_FILE="$WORK_DIR/device.rows" run_bus77_inventory --interface "$INVENTORY_INTERFACE" >"$WORK_DIR/inventory.report" 2>&1
    INVENTORY_RC=$?
    if [ -s "$WORK_DIR/device.rows" ]; then
      awk -F'|' -v dev="$INVENTORY_INTERFACE" '{print dev "|" $0}' "$WORK_DIR/device.rows" >>"$INVENTORY_FILE"
    fi
    if grep -q "LID Conflict Detected" "$WORK_DIR/inventory.report" 2>/dev/null; then
      grep "LID Conflict Detected" "$WORK_DIR/inventory.report" | while read -r LINE; do
        fail "$LINE"
      done
    fi
    if [ "$INVENTORY_RC" -ne 0 ] && ! grep -q "LID Conflict" "$WORK_DIR/inventory.report" 2>/dev/null; then
      warn "$INVENTORY_INTERFACE directory is incomplete; unknown devices will retain their bus addresses."
      awk '/\[NOT OK\]/ || /\[ATTENTION\]/ {print}' "$WORK_DIR/inventory.report"
    fi
    : >"$WORK_DIR/device.rows"
  done
fi

separator
show_bus_devices
separator
printf 'Live packet exchange\n'
printf '  TIME | CAN | RX/TX | SENDER -> RECEIVER | COMMAND | CHANNEL/VARIABLE/VALUE\n'
printf '  RX/TX is relative to this server; ALL means a broadcast, not an acknowledgement.\n'
printf '  S3:LID 0 means segment 3, local address 0; SERVER/GW may forward upstream clients.\n'
printf '  Monitoring starts now and stops automatically after %s seconds.\n' "$MONITOR_SECONDS"
separator
for CAN_INTERFACE in $INTERFACES; do
  snapshot_stats "$CAN_INTERFACE" "$WORK_DIR/$CAN_INTERFACE.before"
done

if [ "$FAILURES" -eq 0 ]; then
  if command -v timeout >/dev/null 2>&1 && command -v tee >/dev/null 2>&1; then
    timeout "$MONITOR_SECONDS" candump -x -e $INTERFACES 2>&1 | tee "$CAPTURE_FILE" | decode_bus77_traffic
  else
    warn 'Live streaming support is limited because timeout or tee is unavailable; output will be shown after capture.'
    candump -x -e $INTERFACES >"$CAPTURE_FILE" 2>&1 &
    CAPTURE_PID=$!
    sleep "$MONITOR_SECONDS"
    kill -INT "$CAPTURE_PID" 2>/dev/null
    wait "$CAPTURE_PID" 2>/dev/null
    CAPTURE_PID=""
    decode_bus77_traffic <"$CAPTURE_FILE"
  fi
fi

separator
printf 'Traffic, Bus Load & Top Talkers Analysis\n'
if [ ! -s "$WORK_DIR/decoder.status" ]; then
  fail 'The Bus77 decoder did not complete successfully.'
elif [ "$(cat "$WORK_DIR/decoder.status")" -gt 0 ]; then
  warn 'Some traffic could not be decoded completely; see decoder notices above.'
fi
TOTAL_CAPTURED="$(awk '$2 == "RX" || $2 == "TX" { count++ } END { print count + 0 }' "$CAPTURE_FILE" 2>/dev/null)"
TOTAL_RX_CAPTURED="$(awk '$2 == "RX" { count++ } END { print count + 0 }' "$CAPTURE_FILE" 2>/dev/null)"
TOTAL_TX_CAPTURED="$(awk '$2 == "TX" { count++ } END { print count + 0 }' "$CAPTURE_FILE" 2>/dev/null)"
TOTAL_ERROR_CAPTURED="$(awk '($2 == "RX" || $2 == "TX") && toupper($5) ~ /^2/ { count++ } END { print count + 0 }' "$CAPTURE_FILE" 2>/dev/null)"

# Calculate FPS and Bus Load %
FPS="$(awk -v total="$TOTAL_CAPTURED" -v sec="$MONITOR_SECONDS" 'BEGIN { if (sec>0) printf "%.1f", total/sec; else print 0 }')"
BUS_LOAD_PERCENT="$(awk -v total="$TOTAL_CAPTURED" -v sec="$MONITOR_SECONDS" -v baud="$PRIMARY_BITRATE" '
  BEGIN {
    if (sec > 0 && baud > 0) {
      bits_transferred = total * 135
      total_capacity = baud * sec
      load = (bits_transferred / total_capacity) * 100
      printf "%.1f", load
    } else print 0.0
  }
')"

printf '  Captured frames     : %s total, %s RX, %s TX, %s CAN error frames\n' "$TOTAL_CAPTURED" "$TOTAL_RX_CAPTURED" "$TOTAL_TX_CAPTURED" "$TOTAL_ERROR_CAPTURED"
printf '  Average Traffic Rate: %s frames/sec (Bus Load: %s%% of %s bit/s)\n' "$FPS" "$BUS_LOAD_PERCENT" "$PRIMARY_BITRATE"

if [ "$(awk -v load="$BUS_LOAD_PERCENT" 'BEGIN { print (load > 60.0) ? 1 : 0 }')" -eq 1 ]; then
  warn "High CAN bus load ($BUS_LOAD_PERCENT%). Check for packet storms or flapping dry contacts."
else
  ok "CAN bus load is normal ($BUS_LOAD_PERCENT% at $FPS fps)."
fi

# Top Talkers Breakdown Table
if [ -s "$WORK_DIR/top_talkers.txt" ] && [ "$TOTAL_CAPTURED" -gt 0 ]; then
  printf '\n  TOP TALKERS (Device Activity Ranking):\n'
  printf '  %-4s %-12s %-24s %-8s %-10s %s\n' 'RANK' 'SENDER' 'MODEL / NAME' 'FRAMES' '%% TRAFFIC' 'AVG RATE'
  awk -F'|' -v total="$TOTAL_CAPTURED" -v sec="$MONITOR_SECONDS" '
    {
      if ($1 == "LOCAL_SERVER") {
        sender = "SERVER/GW"
        model = "iRidi Server Gateway"
        frames = $2 + 0
      } else {
        sender = $1
        model = ($2 != "" ? $2 : "Bus77 Module")
        frames = $4 + 0
        if (frames == 0) frames = $2 + 0
      }
      talkers[sender SUBSEP model] += frames
    }
    END {
      for (k in talkers) {
        split(k, f, SUBSEP)
        pct = (total > 0) ? (talkers[k] / total) * 100 : 0
        rate = (sec > 0) ? talkers[k] / sec : 0
        printf "%08d|%s|%s|%d|%.1f%%|%.1f fps\n", talkers[k], f[1], f[2], talkers[k], pct, rate
      }
    }
  ' "$WORK_DIR/top_talkers.txt" | sort -rn | awk -F'|' '
    {
      rank++
      printf "  %-4d %-12s %-24s %-8d %-10s %s\n", rank, $2, substr($3, 1, 24), $4, $5, $6
      if ($5 + 0 > 50.0 && rank == 1 && $4 > 100) {
        high_talker = $2 " (" $3 ")"
      }
    }
    END {
      if (high_talker != "") {
        print "  [ATTENTION] Top talker " high_talker " is generating over 50% of all bus traffic."
      }
    }
  '
fi

for CAN_INTERFACE in $INTERFACES; do
  snapshot_stats "$CAN_INTERFACE" "$WORK_DIR/$CAN_INTERFACE.after"
  BEFORE_FILE="$WORK_DIR/$CAN_INTERFACE.before"
  AFTER_FILE="$WORK_DIR/$CAN_INTERFACE.after"
  RX_DELTA=$(($(read_snapshot "$AFTER_FILE" rx_packets) - $(read_snapshot "$BEFORE_FILE" rx_packets)))
  TX_DELTA=$(($(read_snapshot "$AFTER_FILE" tx_packets) - $(read_snapshot "$BEFORE_FILE" tx_packets)))
  RX_ERRORS_DELTA=$(($(read_snapshot "$AFTER_FILE" rx_errors) - $(read_snapshot "$BEFORE_FILE" rx_errors)))
  TX_ERRORS_DELTA=$(($(read_snapshot "$AFTER_FILE" tx_errors) - $(read_snapshot "$BEFORE_FILE" tx_errors)))
  RX_DROPPED_DELTA=$(($(read_snapshot "$AFTER_FILE" rx_dropped) - $(read_snapshot "$BEFORE_FILE" rx_dropped)))
  TX_DROPPED_DELTA=$(($(read_snapshot "$AFTER_FILE" tx_dropped) - $(read_snapshot "$BEFORE_FILE" tx_dropped)))
  FINAL_STATE="$(can_state "$CAN_INTERFACE")"
  printf '  %s: kernel RX=%s, TX=%s, new errors RX/TX=%s/%s, new drops RX/TX=%s/%s, state=%s\n' \
    "$CAN_INTERFACE" "$RX_DELTA" "$TX_DELTA" "$RX_ERRORS_DELTA" "$TX_ERRORS_DELTA" \
    "$RX_DROPPED_DELTA" "$TX_DROPPED_DELTA" "${FINAL_STATE:-not determined}"
  case "$FINAL_STATE" in
    BUS-OFF|STOPPED) fail "$CAN_INTERFACE ended in state $FINAL_STATE." ;;
    ERROR-WARNING|ERROR-PASSIVE) warn "$CAN_INTERFACE ended in state $FINAL_STATE." ;;
  esac
  if [ "$RX_ERRORS_DELTA" -gt 0 ] || [ "$TX_ERRORS_DELTA" -gt 0 ] || [ "$RX_DROPPED_DELTA" -gt 0 ] || [ "$TX_DROPPED_DELTA" -gt 0 ]; then
    warn "$CAN_INTERFACE recorded new errors or dropped frames during monitoring."
  fi
done

if [ "$TOTAL_CAPTURED" -eq 0 ] && [ "$FAILURES" -eq 0 ]; then
  warn 'No CAN frames were captured during the monitoring interval.'
elif [ "$TOTAL_RX_CAPTURED" -eq 0 ] && [ "$TOTAL_TX_CAPTURED" -gt 0 ]; then
  warn 'Only transmitted frames were observed; no physical bus responses were received.'
elif [ "$TOTAL_TX_CAPTURED" -eq 0 ] && [ "$TOTAL_RX_CAPTURED" -gt 0 ]; then
  warn 'Only received frames were observed; no local server transmissions were captured.'
else
  ok 'Bidirectional CAN packet exchange was observed.'
fi
if [ "$TOTAL_ERROR_CAPTURED" -gt 0 ]; then
  warn 'One or more CAN error frames were captured.'
fi

separator
printf 'SUMMARY\n'
printf '  Interfaces: %s\n' "$(printf '%s' "$INTERFACES" | tr '\n' ' ')"
printf '  Duration: %s seconds\n' "$MONITOR_SECONDS"
printf '  Captured: %s RX, %s TX, %s error frames\n' "$TOTAL_RX_CAPTURED" "$TOTAL_TX_CAPTURED" "$TOTAL_ERROR_CAPTURED"
printf '  Bus Load: %s%% (%s fps)\n' "$BUS_LOAD_PERCENT" "$FPS"
printf '  Failures: %s\n' "$FAILURES"
printf '  Attention items: %s\n' "$WARNINGS"
if [ "$FAILURES" -gt 0 ]; then
  printf 'RESULT: FAIL - NOT OK: the CAN monitor found a critical problem or could not run.\n'
  exit 2
fi
if [ "$WARNINGS" -gt 0 ]; then
  printf 'RESULT: WARN - ATTENTION REQUIRED: traffic was monitored, but one or more findings need review.\n'
  exit 1
fi
printf 'RESULT: PASS - OK: bidirectional CAN traffic was observed without new errors.\n'
exit 0
