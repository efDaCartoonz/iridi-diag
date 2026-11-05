#!/bin/sh

# POSIX sh; bounded passive packet capture for Linux / BusyBox ash.
TOOL_NAME=network-capture
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

DURATION=30
MAX_MB=8
SNAPLEN=128
MAX_PACKETS=100000
IFACE=eth0
HOST=
PORT=
FILTER=
while [ "$#" -gt 0 ]; do
 case "$1" in
  --duration) need_value "$#" "$1"; uint_arg "$1" "$2" 1 3600; DURATION=$NUMBER; shift 2 ;;
  --max-mb) need_value "$#" "$1"; uint_arg "$1" "$2" 1 128; MAX_MB=$NUMBER; shift 2 ;;
  --snaplen) need_value "$#" "$1"; uint_arg "$1" "$2" 64 65535; SNAPLEN=$NUMBER; shift 2 ;;
  --count) need_value "$#" "$1"; uint_arg "$1" "$2" 1 1000000; MAX_PACKETS=$NUMBER; shift 2 ;;
  --interface) need_value "$#" "$1"; IFACE=$2; shift 2 ;;
  --host) need_value "$#" "$1"; HOST=$2; shift 2 ;;
  --port) need_value "$#" "$1"; uint_arg "$1" "$2" 1 65535; PORT=$NUMBER; shift 2 ;;
  --filter) need_value "$#" "$1"; FILTER=$2; shift 2 ;;
  --output-dir) need_value "$#" "$1"; OUTPUT_BASE=$2; shift 2 ;;
  -h|--help) printf '%s\n' 'Usage: sh capture_network.sh [--interface IFACE] [--duration SEC] [--max-mb N] [--snaplen N] [--count N] [--host IP] [--port N] [--filter BPF] [--output-dir DIR]' 'Defaults: eth0, 30s, 8 decimal MB ring, snaplen 128, 100000 packets; excludes SSH unless --filter is supplied. One rotating PCAP retains the latest traffic. It may exceed the size threshold by one packet. No promiscuous mode is enabled.'; exit 0 ;;
  *) usage_error "Unknown option: $1" ;;
 esac
done
case "$IFACE" in ''|*[!A-Za-z0-9_.:-]*) usage_error 'Invalid interface name' ;; esac
case "$HOST" in *[!0-9A-Fa-f:.]*) usage_error '--host requires a numeric IPv4/IPv6 address' ;; esac
if [ -n "$HOST" ]; then
 case "$HOST" in
  *:*) : ;; # libpcap validates IPv6 syntax, without interpreting the value as shell code.
  *)
   if ! printf '%s\n' "$HOST" | awk -F. 'NF!=4 {exit 1} {for(i=1;i<=4;i++)if($i!~/^[0-9]+$/ || $i>255 || length($i)>3)exit 1}'; then
    usage_error '--host requires a numeric IPv4/IPv6 address'
   fi ;;
 esac
fi
if [ -n "$FILTER" ] && { [ -n "$HOST" ] || [ -n "$PORT" ]; }; then usage_error 'Use either --filter or --host/--port, not both.'; fi
if [ -z "$FILTER" ]; then
 FILTER='not tcp port 22'
 [ -z "$HOST" ] || FILTER="($FILTER) and host $HOST"
 [ -z "$PORT" ] || FILTER="($FILTER) and port $PORT"
fi
init_run
command -v tcpdump >/dev/null 2>&1 || { fail 'tcpdump is required; no package was installed.'; finish; }
[ "$IFACE" = any ] || [ -d "/sys/class/net/$IFACE" ] || { fail "No such interface: $IFACE"; finish; }
PCAP=$RUN_DIR/capture.pcap
CAPTURE_PID=
capture_alive() {
 kill -0 "$CAPTURE_PID" 2>/dev/null || return 1
 if [ -r "/proc/$CAPTURE_PID/stat" ]; then
  CHILD_STATE=$(awk '{sub(/^.*\) /, "");print $1}' "/proc/$CAPTURE_PID/stat" 2>/dev/null)
  [ "$CHILD_STATE" != Z ] || return 1
 fi
 return 0
}
stop_capture() {
 if [ -n "$CAPTURE_PID" ]; then
  if capture_alive; then kill -INT "$CAPTURE_PID" 2>/dev/null; fi
  # Give the child time to flush, then terminate only this child if it ignores SIGINT.
  STOP_START=$(monotonic_seconds)
  while capture_alive; do
   STOP_NOW=$(monotonic_seconds)
   [ "$((STOP_NOW-STOP_START))" -lt 3 ] || break
   pause 1
  done
  if capture_alive; then
   log "tcpdump did not stop after SIGINT; sending TERM to child $CAPTURE_PID"
   kill -TERM "$CAPTURE_PID" 2>/dev/null; pause 1
   if capture_alive; then kill -KILL "$CAPTURE_PID" 2>/dev/null; fi
  fi
  wait "$CAPTURE_PID"; CAPTURE_RC=$?
  CAPTURE_PID=
 fi
}

trap 'cancel_pause; stop_capture; warn "Interrupted; partial capture retained"; finish' HUP INT TERM
info "Interface=$IFACE; duration=${DURATION}s; ring=${MAX_MB}MB; snaplen=$SNAPLEN; packet limit=$MAX_PACKETS"
info "BPF: $FILTER"
info 'PCAP can contain payload fragments and identifiers; automatic log redaction does not apply to packet bytes.'
log "TCPDUMP: interface=$IFACE duration=$DURATION max_mb=$MAX_MB snaplen=$SNAPLEN count=$MAX_PACKETS filter=$FILTER"
# Validate BPF before starting capture; no shell evaluation of filter text.
if ! tcpdump -i "$IFACE" -p -nn -s "$SNAPLEN" -d -- "$FILTER" >"$RUN_DIR/filter.txt" 2>"$RUN_DIR/filter.stderr"; then
 cat "$RUN_DIR/filter.stderr" >&3; fail 'tcpdump rejected the interface/filter or access permissions.'; finish
fi
tcpdump -i "$IFACE" -p -nn -U -s "$SNAPLEN" -c "$MAX_PACKETS" -C "$MAX_MB" -W 1 -Z "$(id -un)" -w "$PCAP" -- "$FILTER" >"$RUN_DIR/tcpdump.stdout" 2>"$RUN_DIR/tcpdump.stderr" &
CAPTURE_PID=$!
START=$(monotonic_seconds)
while kill -0 "$CAPTURE_PID" 2>/dev/null; do
 NOW=$(monotonic_seconds)
 [ "$((NOW-START))" -lt "$DURATION" ] || break
 pause 1
done
stop_capture
cat "$RUN_DIR/tcpdump.stderr" >&3
if [ "${CAPTURE_RC:-1}" -ne 0 ]; then fail "tcpdump exited with code ${CAPTURE_RC:-unknown}; inspect tcpdump.stderr."; finish; fi
FOUND=0
PACKETS=0
for FILE in "$RUN_DIR"/capture.pcap*; do
 [ -f "$FILE" ] || continue
 FOUND=$((FOUND+1)); SIZE=$(wc -c <"$FILE" | tr -d ' ')
 # Reading the file validates PCAP structure without printing packet contents.
 (tcpdump -nn -q -r "$FILE" 2>"$RUN_DIR/pcap-check.stderr"; printf '%s\n' "$?" >"$RUN_DIR/pcap-check.exit") | awk 'END {print NR+0}' >"$RUN_DIR/packet-count.txt"
 if [ "$(cat "$RUN_DIR/pcap-check.exit")" -eq 0 ]; then
  COUNT=$(cat "$RUN_DIR/packet-count.txt"); PACKETS=$((PACKETS+COUNT))
  info "PCAP: $FILE ($SIZE bytes, $COUNT packets retained)"
 else fail "PCAP could not be decoded: $FILE"; cat "$RUN_DIR/pcap-check.stderr" >&3; fi
 # Packet summaries are counted in a pipe, never materialized as a large text file.
done
[ "$FOUND" -gt 0 ] || fail 'No PCAP file was produced.'
[ "$PACKETS" -ne 0 ] || warn 'No matching packets retained during this observation; this is not proof of a network fault.'
DROPPED=$(sed -n 's/^\([0-9][0-9]*\) packets dropped by kernel.*/\1/p' "$RUN_DIR/tcpdump.stderr")
case "$DROPPED" in ''|0) : ;; *) warn "tcpdump reports $DROPPED packets dropped by kernel." ;; esac
[ "$FAILURES" -ne 0 ] || ok 'Bounded packet capture completed; no interface configuration was changed.'
finish
