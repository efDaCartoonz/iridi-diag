#!/bin/sh

# POSIX sh; private bounded support bundle for Linux / BusyBox ash.
TOOL_NAME=support-bundle
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

# Discover runtime evidence without dumping command lines or credential-bearing XML.
discover_iridi_data_dir() (
  if [ -n "${IRIDI_DIAG_DATA_DIR:-}" ]; then
    [ ! -d "$IRIDI_DIAG_DATA_DIR" ] || printf '%s\n' "$IRIDI_DIAG_DATA_DIR"
    exit
  fi
  data_pid=$(pidof iridium 2>/dev/null | awk '{print $1}')
  if [ -n "$data_pid" ]; then
    for data_fd in /proc/"$data_pid"/fd/*; do
      data_target=$(readlink "$data_fd" 2>/dev/null)
      case "$data_target" in
        */DataBase/*) data_root=${data_target%/DataBase/*} ;;
        */Logs/*) data_root=${data_target%/Logs/*} ;;
        *) continue ;;
      esac
      if [ -d "$data_root" ]; then printf '%s\n' "$data_root"; exit; fi
    done
  fi
  for data_root in '/var/lib/iRidium Server' /userdata/iridi /opt/iridi; do
    if [ -d "$data_root" ]; then printf '%s\n' "$data_root"; exit; fi
  done
)

latest_iridi_log() (
  # Shell-expanded arguments preserve spaces and apostrophes in paths.
  ls -t "$1/Logs/"*.txt "$1/Logs/"*.log "$1/Documents/Logs/"*.txt "$1/Documents/Logs/"*.log 2>/dev/null | head -n 1
)

iridi_project_evidence() (
  evidence_root=$1
  for evidence_config in "$evidence_root/Documents/irconfig.xml" "$evidence_root/irconfig.xml" "$evidence_root/Documents/system.xml" "$evidence_root/system.xml"; do
    [ -f "$evidence_config" ] && [ -r "$evidence_config" ] || continue
    printf 'Configuration source: %s\n' "$evidence_config"
    # Only allowlisted attributes/tags are emitted; never dump the whole XML.
    head -c 262144 "$evidence_config" | awk '
      function attr(s,key, x) {
        if(match(s,"(^|[[:space:]])" key "=\"[^\"]*\"")) {
          x=substr(s,RSTART,RLENGTH);sub(/^[^=]*=\"/,"",x);sub(/\"$/,"",x);return x
        }
        return ""
      }
      BEGIN {RS="<"}
      /^Designs[[:space:]]/ {current=attr($0,"Current")}
      /^Design[[:space:]]/ {if(n<10){n++;names[n]=attr($0,"Name");files[n]=attr($0,"File")}}
      /^ActiveProject>/ {x=$0;sub(/^[^>]*>/,"",x);print "Configured project tag: " x}
      /^ProjectName>/ {x=$0;sub(/^[^>]*>/,"",x);print "Configured project name: " x}
      END {
        if(current!="")print "Configured current reference: " current
        for(i=1;i<=n;i++)print "Configured design candidate: " names[i] " | " files[i]
      }
    '
  done
  evidence_pid=$(pidof iridium 2>/dev/null | awk '{print $1}')
  if [ -n "$evidence_pid" ]; then
    for evidence_fd in /proc/"$evidence_pid"/fd/*; do
      evidence_target=$(readlink "$evidence_fd" 2>/dev/null)
      case "$evidence_target" in *.irp|*.sirp|*.sirpz|*.rpz|*.irpz) printf 'Process open project file: %s\n' "$evidence_target" ;; esac
    done
    if [ -r "/proc/$evidence_pid/cmdline" ]; then
      tr '\000' '\n' <"/proc/$evidence_pid/cmdline" | awk '/\.(irp|sirp|sirpz|rpz|irpz)$/ {print "Process project argument: " $0}'
    fi
  fi
  printf '%s\n' 'Configured references are not proof of a running project; correlate process evidence and successful-load log markers.'
)

DURATION=15
LOG_COUNT=3
LOG_KIB=128
MAX_MB=16
IRIDI_DIAG_DATA_DIR=${IRIDI_DIAG_DATA_DIR:-}
while [ "$#" -gt 0 ]; do
 case "$1" in
  --duration) need_value "$#" "$1"; uint_arg "$1" "$2" 1 300; DURATION=$NUMBER; shift 2 ;;
  --log-count) need_value "$#" "$1"; uint_arg "$1" "$2" 0 10; LOG_COUNT=$NUMBER; shift 2 ;;
  --log-kib) need_value "$#" "$1"; uint_arg "$1" "$2" 1 1024; LOG_KIB=$NUMBER; shift 2 ;;
  --max-mb) need_value "$#" "$1"; uint_arg "$1" "$2" 4 128; MAX_MB=$NUMBER; shift 2 ;;
  --data-dir) need_value "$#" "$1"; IRIDI_DIAG_DATA_DIR=$2; shift 2 ;;
  --output-dir) need_value "$#" "$1"; OUTPUT_BASE=$2; shift 2 ;;
  -h|--help) printf '%s\n' 'Usage: sh collect_support_bundle.sh [--duration SEC] [--data-dir DIR] [--log-count N] [--log-kib N] [--max-mb N] [--output-dir DIR]' 'Defaults: 15s concurrent runtime/Ethernet observation; last 128 KiB of 3 logs; 16 MiB staging budget. Creates private payload plus tar.gz. No packet capture, project contents, full configs or license files are collected. Credential-like log lines are masked heuristically; inspect before sharing.'; exit 0 ;;
  *) usage_error "Unknown option: $1" ;;
 esac
done
[ -z "$IRIDI_DIAG_DATA_DIR" ] || [ -d "$IRIDI_DIAG_DATA_DIR" ] || usage_error '--data-dir is not a directory'
init_run
PAYLOAD=$RUN_DIR/payload
mkdir "$PAYLOAD" || { fail 'Cannot create payload directory.'; finish; }
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
BUDGET_KIB=$((MAX_MB*1024))
CHILD_RUNTIME=
CHILD_ETHERNET=
stop_children() {
 for CHILD in "$CHILD_RUNTIME" "$CHILD_ETHERNET"; do
  [ -z "$CHILD" ] || kill -TERM "$CHILD" 2>/dev/null
 done
 for CHILD in "$CHILD_RUNTIME" "$CHILD_ETHERNET"; do [ -z "$CHILD" ] || wait "$CHILD" 2>/dev/null; done
 CHILD_RUNTIME=; CHILD_ETHERNET=
}
trap 'stop_children; warn "Interrupted; partial private payload retained"; finish' HUP INT TERM
redact_lines() {
 awk '{x=tolower($0); if(x ~ /password|passwd|authorization|cookie|secret|credential|token|private.key|passwordhash|<wmi|<smp/) print "[REDACTED credential-like line]"; else print}'
}
remaining_bytes() {
 USED=$(du -sk "$PAYLOAD" | awk '{print $1}')
 LEFT=$((BUDGET_KIB-USED-64)); [ "$LEFT" -ge 0 ] || LEFT=0
 printf '%s\n' "$((LEFT*1024))"
}
stage_text() {
 SOURCE=$1; DEST=$2; LIMIT=$3
 [ -f "$SOURCE" ] && [ -r "$SOURCE" ] || return 1
 REMAINING=$(remaining_bytes)
 [ "$LIMIT" -le "$REMAINING" ] || LIMIT=$REMAINING
 if [ "$LIMIT" -le 0 ]; then warn "Payload budget reached; skipped $SOURCE"; return 1; fi
 SIZE=$(wc -c <"$SOURCE" | tr -d ' ')
 if [ "$SIZE" -gt "$LIMIT" ]; then
  tail -c "$LIMIT" "$SOURCE" | sed '1d' | redact_lines | head -c "$LIMIT" >"$PAYLOAD/$DEST"
 else
  tail -c "$LIMIT" "$SOURCE" | redact_lines | head -c "$LIMIT" >"$PAYLOAD/$DEST"
 fi
 printf '%s | %s | tail_limit_bytes=%s\n' "$DEST" "$SOURCE" "$LIMIT" >>"$PAYLOAD/manifest.txt"
}
{
 printf 'tool=collect_support_bundle version=%s\n' "$TOOL_VERSION"
 printf 'created_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
 printf 'host=%s\nkernel=%s\nduration_s=%s\n' "$(uname -n)" "$(uname -srm)" "$DURATION"
 printf 'limits: payload=%sMiB log_count=%s tail_kib=%s\n' "$MAX_MB" "$LOG_COUNT" "$LOG_KIB"
 printf '%s\n' 'Logs are bounded tail excerpts with heuristic masking, not complete history or guaranteed secret-free data.'
 printf '%s\n' 'No archive/cleanup web API, service restart, database write, project modification or network reconfiguration is performed.'
} >"$PAYLOAD/manifest.txt"
for SOURCE in /oem/hal/ccinfo /timestamp /etc/os-release /proc/meminfo /proc/loadavg /proc/uptime; do
 case "$SOURCE" in /proc/*) DEST=proc-${SOURCE##*/}.txt ;; *) DEST=system-${SOURCE##*/}.txt ;; esac
 stage_text "$SOURCE" "$DEST" 16384 || :
done
# Capture small bounded command output; never source the result as shell code.
{
 date -u
 df -Pk / /userdata /oem 2>/dev/null
 if command -v ip >/dev/null 2>&1; then ip addr; ip route; ip -details link; fi
} 2>&3 | head -c 65536 >"$RUN_DIR/system-network.txt"
stage_text "$RUN_DIR/system-network.txt" system-network.txt 65536 || :
if dmesg >"$RUN_DIR/kernel.txt" 2>"$RUN_DIR/kernel.stderr"; then
 stage_text "$RUN_DIR/kernel.txt" kernel-tail.txt 131072 || :
else warn 'Kernel log could not be read; see collector audit log.'; cat "$RUN_DIR/kernel.stderr" >&3; fi
{
 for SOURCE in /sys/class/rtc/rtc*/name /sys/class/rtc/rtc*/date /sys/class/rtc/rtc*/time /sys/class/rtc/rtc*/since_epoch /sys/class/rtc/rtc*/device/battery_low; do
  [ -r "$SOURCE" ] || continue
  printf '%s: ' "$SOURCE"; head -c 1024 "$SOURCE"; printf '\n'
 done
 for DEVICE in /sys/bus/mmc/devices/*; do
  [ "$(cat "$DEVICE/type" 2>/dev/null)" = MMC ] || continue
  for FIELD in name manfid life_time pre_eol_info cid csd; do
   [ -r "$DEVICE/$FIELD" ] || continue
   printf '%s/%s: ' "$DEVICE" "$FIELD"; head -c 1024 "$DEVICE/$FIELD"; printf '\n'
  done
 done
 for SOURCE in /oem/hal/*_port; do
  if [ -L "$SOURCE" ]; then printf '%s -> %s\n' "$SOURCE" "$(readlink -f "$SOURCE" 2>/dev/null)"
  elif [ -f "$SOURCE" ] && [ -r "$SOURCE" ]; then printf '%s: ' "$SOURCE"; head -c 256 "$SOURCE"; printf '\n'; fi
 done
} >"$RUN_DIR/hardware.txt"
stage_text "$RUN_DIR/hardware.txt" hardware.txt 32768 || :
DATA_DIR=$(discover_iridi_data_dir)
if [ -n "$DATA_DIR" ]; then
 info "Data directory: $DATA_DIR"
 iridi_project_evidence "$DATA_DIR" >"$RUN_DIR/project-evidence.txt"
 stage_text "$RUN_DIR/project-evidence.txt" project-evidence.txt 32768 || :
 # Take a bounded beginning excerpt separately: successful startup may be absent from the tail.
 LATEST=$(latest_iridi_log "$DATA_DIR")
 if [ -n "$LATEST" ] && [ -f "$LATEST" ]; then
  head -c 65536 "$LATEST" | grep -iE 'project|loading|started to work' | redact_lines >"$RUN_DIR/project-startup-markers.txt" || :
  stage_text "$RUN_DIR/project-startup-markers.txt" project-startup-markers.txt 32768 || :
 fi
 ls -t "$DATA_DIR/Logs/"*.txt "$DATA_DIR/Logs/"*.log "$DATA_DIR/Documents/Logs/"*.txt "$DATA_DIR/Documents/Logs/"*.log 2>/dev/null >"$RUN_DIR/log-candidates.txt"
 TAKEN=0
 while IFS= read -r SOURCE; do
  [ "$TAKEN" -lt "$LOG_COUNT" ] || break
  [ -f "$SOURCE" ] || continue
  TAKEN=$((TAKEN+1))
  stage_text "$SOURCE" "server-log-$TAKEN.txt" "$((LOG_KIB*1024))" || :
 done <"$RUN_DIR/log-candidates.txt"
 [ "$TAKEN" -gt 0 ] || { [ "$LOG_COUNT" -eq 0 ] || warn 'No readable .txt/.log server logs found.'; }
else warn 'iRidi data directory not found; use --data-dir.'; fi
# Optional sibling tools run concurrently. They do not launch server_health's license dump or SQLite checks.
mkdir "$RUN_DIR/observations"
if [ -f "$SCRIPT_DIR/monitor_server_runtime.sh" ]; then
 sh "$SCRIPT_DIR/monitor_server_runtime.sh" --duration "$DURATION" --output-dir "$RUN_DIR/observations" >"$RUN_DIR/runtime.stdout" 2>"$RUN_DIR/runtime.stderr" &
 CHILD_RUNTIME=$!
else warn 'Runtime monitor sibling is missing; basic bundle remains available.'; fi
if [ -f "$SCRIPT_DIR/check_ethernet.sh" ]; then
 sh "$SCRIPT_DIR/check_ethernet.sh" --duration "$DURATION" --output-dir "$RUN_DIR/observations" >"$RUN_DIR/ethernet.stdout" 2>"$RUN_DIR/ethernet.stderr" &
 CHILD_ETHERNET=$!
else warn 'Ethernet check sibling is missing; basic bundle remains available.'; fi
for CHILD_KIND in runtime ethernet; do
 case "$CHILD_KIND" in runtime) CHILD=$CHILD_RUNTIME ;; ethernet) CHILD=$CHILD_ETHERNET ;; esac
 [ -n "$CHILD" ] || continue
 wait "$CHILD"; CHILD_RC=$?
 printf '%s_exit_code=%s\n' "$CHILD_KIND" "$CHILD_RC" >>"$PAYLOAD/manifest.txt"
 [ "$CHILD_RC" -eq 0 ] || warn "$CHILD_KIND observation returned $CHILD_RC; included results need review."
 stage_text "$RUN_DIR/$CHILD_KIND.stdout" "$CHILD_KIND-summary.txt" 32768 || :
 stage_text "$RUN_DIR/$CHILD_KIND.stderr" "$CHILD_KIND-stderr.txt" 8192 || :
 case "$CHILD_KIND" in runtime) CHILD_RUNTIME= ;; ethernet) CHILD_ETHERNET= ;; esac
done
INDEX=0
for OBS in "$RUN_DIR"/observations/*; do
 [ -d "$OBS" ] || continue
 for SOURCE in "$OBS/audit.log" "$OBS/runtime.csv" "$OBS/"*.deltas; do
  [ -f "$SOURCE" ] || continue
  INDEX=$((INDEX+1)); stage_text "$SOURCE" "observation-$INDEX-${SOURCE##*/}" 131072 || :
 done
done
stage_text "$LOG_FILE" collector-audit.txt 32768 || :
USED=$(du -sk "$PAYLOAD" | awk '{print $1}')
if [ "$USED" -gt "$BUDGET_KIB" ]; then fail 'Payload budget exceeded; archive not created.'; finish; fi
command -v tar >/dev/null 2>&1 && command -v gzip >/dev/null 2>&1 || { fail 'tar and gzip are required; private payload retained.'; finish; }
ARCHIVE=$RUN_DIR/support-bundle.tar.gz
TAR_FILE=$RUN_DIR/support-bundle.tar
# Some HSS BusyBox builds have tar without -z; keep compression as a separate step.
if tar -cf "$TAR_FILE" -C "$PAYLOAD" . 2>"$RUN_DIR/tar.stderr"; then
 if gzip -c "$TAR_FILE" >"$ARCHIVE" 2>"$RUN_DIR/gzip.stderr" && gzip -t "$ARCHIVE" 2>>"$RUN_DIR/gzip.stderr" && tar -tf "$TAR_FILE" >"$RUN_DIR/archive-members.txt" 2>>"$RUN_DIR/tar.stderr"; then
  ok "Archive created; gzip integrity and tar listing verified: $ARCHIVE"
  info "Payload: $USED KiB; logs: ${TAKEN:-0}; heuristic redaction applied."
 else fail 'Archive compression/integrity/listing verification failed.'; cat "$RUN_DIR/gzip.stderr" >&3; fi
else fail 'Archive creation failed; private payload retained.'; cat "$RUN_DIR/tar.stderr" >&3; fi
rm -f "$TAR_FILE"

finish
