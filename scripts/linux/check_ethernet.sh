#!/bin/sh

# POSIX sh; Linux / BusyBox ash. Read-only observation.
TOOL_NAME=ethernet
# Shared implementation is embedded so each tool remains standalone.
TOOL_VERSION=1.0
WARNINGS=0
FAILURES=0
OUTPUT_BASE=${IRIDI_DIAG_LOG_DIR:-${TMPDIR:-/tmp}}
RUN_DIR=
LOG_FILE=

usage_error() { printf '[NOT OK] %s\n' "$*" >&2; exit 2; }
need_value() { [ "$1" -ge 2 ] || usage_error "Missing value for $2"; }
uint_arg() {
  case "$2" in ''|*[!0-9]*) usage_error "$1 must be an integer in $3..$4" ;; esac
  NUMBER=$(printf '%s' "$2" | sed 's/^0*//'); NUMBER=${NUMBER:-0}
  [ "$NUMBER" -ge "$3" ] 2>/dev/null && [ "$NUMBER" -le "$4" ] 2>/dev/null || usage_error "$1 must be in $3..$4"
}
init_run() {
  umask 077
  [ -d "$OUTPUT_BASE" ] && [ -w "$OUTPUT_BASE" ] || usage_error "Output directory is unavailable: $OUTPUT_BASE"
  OUTPUT_BASE=$(cd "$OUTPUT_BASE" && pwd -P) || exit 2
  RUN_DIR=$(mktemp -d "$OUTPUT_BASE/iridi-$TOOL_NAME.XXXXXX") || exit 2
  LOG_FILE=$RUN_DIR/audit.log
  exec 3>"$LOG_FILE" || exit 2
  log "START: tool=$TOOL_NAME version=$TOOL_VERSION host=$(uname -n) kernel=$(uname -srm)"
  printf 'iRidi %s v%s\nArtifacts: %s\n' "$TOOL_NAME" "$TOOL_VERSION" "$RUN_DIR"
}
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$*" >&3; }
info() { printf '  [INFO] %s\n' "$*"; log "INFO: $*"; }
ok() { printf '  [OK] %s\n' "$*"; log "OK: $*"; }
warn() { WARNINGS=$((WARNINGS+1)); printf '  [ATTENTION] %s\n' "$*"; log "WARN: $*"; }
fail() { FAILURES=$((FAILURES+1)); printf '  [NOT OK] %s\n' "$*"; log "FAIL: $*"; }
finish() {
  RESULT=PASS; RC=0
  if [ "$FAILURES" -gt 0 ]; then RESULT=FAIL; RC=2
  elif [ "$WARNINGS" -gt 0 ]; then RESULT=WARN; RC=1; fi
  log "RESULT: $RESULT exit=$RC failures=$FAILURES warnings=$WARNINGS"
  printf '%s\n' "$RC" >"$RUN_DIR/exit_code"
  printf 'RESULT: %s (failures=%s, warnings=%s)\nTechnical log: %s\n' "$RESULT" "$FAILURES" "$WARNINGS" "$LOG_FILE"
  exit "$RC"
}
monotonic_seconds() { awk '{print int($1)}' /proc/uptime; }
read_number() {
  READ_VALUE=$(cat "$1" 2>/dev/null)
  case "$READ_VALUE" in ''|*[!0-9]*) printf 'n/a\n' ;; *) printf '%s\n' "$READ_VALUE" ;; esac
}
# No color escapes are emitted, including under NO_COLOR=1 or redirected stdout.

PAUSE_PID=
pause() {
  sleep "$1" >/dev/null 2>&1 3>&- & PAUSE_PID=$!
  wait "$PAUSE_PID"
  PAUSE_PID=
}
cancel_pause() {
  # A signal can arrive between spawning sleep and assigning $!. Verify ownership
  # before recovering that child PID; never signal an unrelated last-background PID.
  if [ -z "$PAUSE_PID" ] && [ -n "$!" ] && [ -r "/proc/$!/stat" ]; then
    PAUSE_LAST=$!
    PAUSE_COMM=$(cat "/proc/$PAUSE_LAST/comm" 2>/dev/null)
    PAUSE_PARENT=$(awk '{sub(/^.*\) /, "");print $2}' "/proc/$PAUSE_LAST/stat" 2>/dev/null)
    if [ "$PAUSE_COMM" = sleep ] && [ "$PAUSE_PARENT" = "$$" ]; then PAUSE_PID=$PAUSE_LAST; fi
  fi
  if [ -n "$PAUSE_PID" ]; then
    kill -TERM "$PAUSE_PID" 2>/dev/null
    wait "$PAUSE_PID" 2>/dev/null
    PAUSE_PID=
  fi
}

DURATION=10
REQUESTED_INTERFACE=all
while [ "$#" -gt 0 ]; do
 case "$1" in
  --duration) need_value "$#" "$1"; uint_arg "$1" "$2" 1 300; DURATION=$NUMBER; shift 2 ;;
  --interface) need_value "$#" "$1"; REQUESTED_INTERFACE=$2; shift 2 ;;
  --output-dir) need_value "$#" "$1"; OUTPUT_BASE=$2; shift 2 ;;
  -h|--help) printf '%s\n' 'Usage: sh check_ethernet.sh [--interface IFACE|all] [--duration SEC] [--output-dir DIR]' 'Defaults: physical wired Ethernet interfaces, 10 seconds. Reads link and counter deltas; does not change interface settings.'; exit 0 ;;
  *) usage_error "Unknown option: $1" ;;
 esac
done
case "$REQUESTED_INTERFACE" in ''|*[!A-Za-z0-9_.:-]*) usage_error 'Invalid interface name' ;; esac
init_run
trap 'cancel_pause; warn "Interrupted; partial counters retained"; finish' HUP INT TERM
INTERFACES=$REQUESTED_INTERFACE
if [ "$REQUESTED_INTERFACE" = all ]; then
 INTERFACES=$(for path in /sys/class/net/*; do
  [ -d "$path/device" ] && [ ! -d "$path/wireless" ] || continue
  [ "$(cat "$path/type" 2>/dev/null)" = 1 ] || continue
  printf '%s\n' "${path##*/}"
 done)
fi
[ -n "$INTERFACES" ] || { warn 'No physical wired Ethernet interfaces found.'; finish; }
FIELDS='rx_bytes tx_bytes rx_packets tx_packets rx_errors tx_errors rx_dropped tx_dropped rx_crc_errors rx_frame_errors rx_length_errors rx_over_errors rx_missed_errors tx_carrier_errors'
snapshot_link() {
 SNAP_IF=$1; SNAP_FILE=$2
 : >"$SNAP_FILE"
 for FIELD in $FIELDS; do printf '%s %s\n' "$FIELD" "$(read_number "/sys/class/net/$SNAP_IF/statistics/$FIELD")" >>"$SNAP_FILE"; done
 printf 'carrier_changes %s\n' "$(read_number "/sys/class/net/$SNAP_IF/carrier_changes")" >>"$SNAP_FILE"
}
for IFACE in $INTERFACES; do
 if [ ! -d "/sys/class/net/$IFACE" ] || [ "$(cat "/sys/class/net/$IFACE/type" 2>/dev/null)" != 1 ]; then fail "$IFACE is not an available Ethernet interface."; continue; fi
 snapshot_link "$IFACE" "$RUN_DIR/$IFACE.before"
 OPER=$(cat "/sys/class/net/$IFACE/operstate" 2>/dev/null)
 SPEED=$(cat "/sys/class/net/$IFACE/speed" 2>/dev/null); SPEED=${SPEED:-n/a}
 DUPLEX=$(cat "/sys/class/net/$IFACE/duplex" 2>/dev/null); DUPLEX=${DUPLEX:-n/a}
 info "$IFACE: state=${OPER:-unknown}, speed=$SPEED Mbps, duplex=$DUPLEX"
 printf '%s\n' "$OPER" >"$RUN_DIR/$IFACE.initial-state"
 [ "$OPER" = up ] || warn "$IFACE link is ${OPER:-unknown}; this can be expected for an unused port."
 [ "$DUPLEX" != half ] || warn "$IFACE reports half duplex."
 if command -v ethtool >/dev/null 2>&1; then
  log "ETHTOOL: $IFACE"
  ethtool "$IFACE" >&3 2>&1 || info "$IFACE: ethtool link details unavailable."
  log "ETHTOOL DRIVER COUNTERS: $IFACE"
  ethtool -S "$IFACE" >&3 2>&1 || info "$IFACE: driver-specific counters unavailable."
 else info 'ethtool is unavailable; using kernel link state and counters.'; fi
 if command -v ip >/dev/null 2>&1; then log "IP LINK: $IFACE"; ip -details -statistics link show "$IFACE" >&3 2>&1; fi
done
[ "$FAILURES" -eq 0 ] || finish
info "Sampling counter deltas for ${DURATION}s."
pause "$DURATION"
for IFACE in $INTERFACES; do
 snapshot_link "$IFACE" "$RUN_DIR/$IFACE.after"
 awk 'NR==FNR {before[$1]=$2; next} {d="n/a";if(before[$1]~/^[0-9]+$/ && $2~/^[0-9]+$/) {if($2>=before[$1]) d=$2-before[$1];else d="reset"} print $1,before[$1],$2,d}' "$RUN_DIR/$IFACE.before" "$RUN_DIR/$IFACE.after" >"$RUN_DIR/$IFACE.deltas"
 while read -r FIELD BEFORE AFTER DELTA; do
  log "$IFACE $FIELD: before=$BEFORE after=$AFTER delta=$DELTA"
  case "$DELTA" in
   reset) warn "$IFACE: $FIELD counter decreased; interval is not comparable (reset or wrap)." ;;
   n/a) case "$FIELD" in rx_packets|tx_packets|rx_errors|tx_errors) warn "$IFACE: $FIELD unavailable." ;; esac ;;
   *) case "$FIELD" in
    rx_bytes|tx_bytes|rx_packets|tx_packets) info "$IFACE: $FIELD +$DELTA" ;;
    *) [ "$DELTA" -eq 0 ] || warn "$IFACE: $FIELD increased by $DELTA." ;;
   esac ;;
  esac
 done <"$RUN_DIR/$IFACE.deltas"
 OPER=$(cat "/sys/class/net/$IFACE/operstate" 2>/dev/null)
 INITIAL=$(cat "$RUN_DIR/$IFACE.initial-state")
 [ "$OPER" = "$INITIAL" ] || warn "$IFACE state changed: $INITIAL -> ${OPER:-unavailable}."
done
if dmesg >"$RUN_DIR/kernel.txt" 2>"$RUN_DIR/kernel.stderr"; then
 grep -iE 'stmmac|ethernet|link is (up|down)|NETDEV WATCHDOG|tx timeout' "$RUN_DIR/kernel.txt" >"$RUN_DIR/ethernet-kernel.txt" || :
else info 'Kernel log unavailable.'; fi
[ "$WARNINGS" -ne 0 ] || ok 'No Ethernet faults detected in the sampled counters; end-to-end connectivity was not tested.'
finish
