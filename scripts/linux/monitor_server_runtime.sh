#!/bin/sh

# POSIX sh; Linux / BusyBox ash. Read-only observation.
TOOL_NAME=runtime
# Shared implementation is embedded so each tool remains standalone.
TOOL_VERSION=1.2
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

DURATION=60
INTERVAL=5
REQUESTED_PID=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --duration) need_value "$#" "$1"; uint_arg "$1" "$2" 1 3600; DURATION=$NUMBER; shift 2 ;;
    --interval) need_value "$#" "$1"; uint_arg "$1" "$2" 1 300; INTERVAL=$NUMBER; shift 2 ;;
    --pid) need_value "$#" "$1"; uint_arg "$1" "$2" 1 4194304; REQUESTED_PID=$NUMBER; shift 2 ;;
    --output-dir) need_value "$#" "$1"; OUTPUT_BASE=$2; shift 2 ;;
    -h|--help) printf '%s\n' 'Usage: sh monitor_server_runtime.sh [--pid PID] [--duration SEC] [--interval SEC] [--output-dir DIR]' 'Defaults: iridium process, duration 60s, interval 5s. Samples /proc; does not attach a debugger or restart services.'; exit 0 ;;
    *) usage_error "Unknown option: $1" ;;
  esac
done
init_run
trap 'cancel_pause; warn "Interrupted; partial CSV retained"; finish' HUP INT TERM
PID=$REQUESTED_PID
if [ -z "$PID" ]; then
  PIDS=$(pidof iridium 2>/dev/null)
  PID=$(printf '%s\n' "$PIDS" | awk '{print $1}')
  case "$PIDS" in *' '*) warn "Multiple iridium processes found ($PIDS); monitoring PID $PID. Use --pid to select." ;; esac
fi
case "$PID" in ''|*[!0-9]*) fail 'No iridium process found. Use --pid for a different process.'; finish ;; esac
[ -r "/proc/$PID/stat" ] || { fail "Cannot read /proc/$PID/stat"; finish; }
proc_identity() {
  # comm can contain spaces and parentheses; numeric fields start after the last ') '.
  awk '{sub(/^.*\) /, ""); printf "%.0f %.0f %s\n", $12+$13, $20, $1}' "/proc/$PID/stat" 2>/dev/null
}
fd_count() {
  if [ ! -r "/proc/$PID/fd" ] || [ ! -x "/proc/$PID/fd" ]; then printf 'n/a\n'; return; fi
  FD_COUNT=0
  for FD in /proc/"$PID"/fd/*; do [ ! -L "$FD" ] || FD_COUNT=$((FD_COUNT+1)); done
  printf '%s\n' "$FD_COUNT"
}
cpu_snapshot() {
  # guest/guest_nice are already included in user/nice. iowait is not busy CPU.
  awk '/^cpu([0-9]+)? / {
    total=0;for(i=2;i<=9 && i<=NF;i++)total+=$i
    printf "%s %.0f %.0f %.0f\n",$1,total,$5,$6
  }' /proc/stat
}
cpu_deltas() {
  awk -v labels="$CPU_LABELS" '
    NR==FNR {total[$1]=$2;idle[$1]=$3;io[$1]=$4;next}
    {current[$1]=$2;ci[$1]=$3;cw[$1]=$4}
    END {
      n=split(labels,a," ")
      for(i=1;i<=n;i++){
        key=a[i];value="n/a"
        if(key in total && key in current){
          dt=current[key]-total[key];di=ci[key]-idle[key];dw=cw[key]-io[key]
          if(dt>0 && di>=0 && dw>=0 && di+dw<=dt)value=sprintf("%.1f",100*(dt-di-dw)/dt)
        }
        print key,value
      }
    }
  ' "$1" "$2"
}
memory_percentages() {
  # RSS includes shared pages; system usage is based on available, not merely free, RAM.
  awk -v rss="$1" '
    $1=="MemTotal:" && $2~/^[0-9]+$/ {total=$2}
    $1=="MemAvailable:" && $2~/^[0-9]+$/ {available=$2;have_available=1}
    END {
      process="n/a";sys_used="n/a";t="n/a";a="n/a"
      if(total>0){
        t=sprintf("%.0f",total)
        if(rss~/^[0-9]+$/)process=sprintf("%.1f",100*rss/total)
        if(have_available && available<=total){
          a=sprintf("%.0f",available);sys_used=sprintf("%.1f",100*(total-available)/total)
        }
      }
      print process,sys_used,t,a
    }
  ' /proc/meminfo
}
INITIAL_ID=$(proc_identity)
START_TICKS=$(printf '%s\n' "$INITIAL_ID" | awk '{print $2}')
case "$START_TICKS" in ''|*[!0-9]*) fail 'Process identity could not be read.'; finish ;; esac
cpu_snapshot >"$RUN_DIR/cpu.previous"
CORE_LABELS=$(awk '$1!="cpu" {print $1}' "$RUN_DIR/cpu.previous")
CPU_LABELS="cpu $(printf '%s' "$CORE_LABELS" | tr '\n' ' ')"
CORES=$(printf '%s\n' "$CORE_LABELS" | awk 'NF {n++} END {print n+0}')
[ "$CORES" -gt 0 ] || CORES=1
CSV=$RUN_DIR/runtime.csv
printf '%s' 'utc,uptime_s,pid,state,cpu_percent_one_core,rss_kib,threads,open_fds,read_bytes,write_bytes,cpu_system_percent,cpu_process_capacity_percent,ram_process_percent,ram_system_used_percent,ram_total_kib,ram_available_kib' >"$CSV"
for CORE in $CORE_LABELS; do printf ',%s_percent' "$CORE" >>"$CSV"; done
printf '\n' >>"$CSV"
info "PID $PID; ${DURATION}s, interval ${INTERVAL}s; CPU ALL and PROC TOTAL are 0..100% of the controller; PROC 1C uses one core as 100%."
info 'Per-core busy CPU excludes idle and iowait. All CPU values are interval averages; the first sample is n/a.'
info 'RAM PROC is process RSS / total RAM (includes shared pages); RAM ALL uses available memory, accounting for reclaimable cache.'
log "PROCESS: pid=$PID start_ticks=$START_TICKS cores=$CORES"
printf '%-9s %-5s %-9s %-11s %-9s' 'ELAPSED' 'STATE' 'CPU ALL%' 'PROC TOTAL%' 'PROC 1C%'
for CORE in $CORE_LABELS; do printf ' %-7s' "CPU${CORE#cpu}%"; done
printf ' %-9s %-8s %-10s %-6s %s\n' 'RAM PROC%' 'RAM ALL%' 'RSS KiB' 'FDs' 'THREADS'
START=$(monotonic_seconds)
PREV_TOTAL=
PREV_TICKS=
SAMPLES=0
BLOCKED=0
while :; do
  NOW=$(monotonic_seconds); ELAPSED=$((NOW-START))
  ID=$(proc_identity)
  TICKS=$(printf '%s\n' "$ID" | awk '{print $1}')
  IDENTITY=$(printf '%s\n' "$ID" | awk '{print $2}')
  STATE=$(printf '%s\n' "$ID" | awk '{print $3}')
  if [ "$IDENTITY" != "$START_TICKS" ]; then
    fail "PID $PID exited or was reused; monitoring stopped without attaching to another process."
    break
  fi
  if [ "$STATE" = Z ]; then fail "PID $PID is a zombie."; break; fi
  cpu_snapshot >"$RUN_DIR/cpu.current"
  TOTAL=$(awk '$1=="cpu" {print $2}' "$RUN_DIR/cpu.current")
  CURRENT_CORES=$(awk '$1!="cpu" {print $1}' "$RUN_DIR/cpu.current")
  CORES=$(printf '%s\n' "$CURRENT_CORES" | awk 'NF {n++} END {print n+0}')
  [ "$CORES" -gt 0 ] || CORES=1
  CPU=n/a
  PROCESS_CAPACITY=n/a
  SYSTEM_CPU=n/a
  if [ -n "$PREV_TOTAL" ] && [ "$CURRENT_CORES" = "$PREV_CORES" ]; then
    CPU=$(awk -v p="$TICKS" -v pp="$PREV_TICKS" -v t="$TOTAL" -v pt="$PREV_TOTAL" -v c="$CORES" 'BEGIN {if(t>pt && p>=pp)printf "%.1f",100*c*(p-pp)/(t-pt);else print "n/a"}')
    PROCESS_CAPACITY=$(awk -v p="$TICKS" -v pp="$PREV_TICKS" -v t="$TOTAL" -v pt="$PREV_TOTAL" 'BEGIN {if(t>pt && p>=pp)printf "%.1f",100*(p-pp)/(t-pt);else print "n/a"}')
    if ! cpu_deltas "$RUN_DIR/cpu.previous" "$RUN_DIR/cpu.current" >"$RUN_DIR/cpu.percent" 2>&3; then
      fail 'CPU interval calculation failed; partial CSV retained.'
      break
    fi
    SYSTEM_CPU=$(awk '$1=="cpu" {print $2}' "$RUN_DIR/cpu.percent")
  else
    for CORE in $CPU_LABELS; do printf '%s n/a\n' "$CORE"; done >"$RUN_DIR/cpu.percent"
    if [ -n "$PREV_TOTAL" ]; then warn 'Online CPU set changed; aggregate/process CPU interval is unavailable. CSV core columns follow the initial CPU set.'; fi
  fi
  RSS=$(awk '/^VmRSS:/ {print $2}' "/proc/$PID/status" 2>/dev/null); RSS=${RSS:-n/a}
  if ! MEMORY=$(memory_percentages "$RSS" 2>&3); then
    warn 'Memory counters could not be read; RAM percentages are unavailable.'
    MEMORY='n/a n/a n/a n/a'
  fi
  PROCESS_RAM=$(printf '%s\n' "$MEMORY" | awk '{print $1}')
  SYSTEM_RAM=$(printf '%s\n' "$MEMORY" | awk '{print $2}')
  RAM_TOTAL=$(printf '%s\n' "$MEMORY" | awk '{print $3}')
  RAM_AVAILABLE=$(printf '%s\n' "$MEMORY" | awk '{print $4}')
  THREADS=$(awk '/^Threads:/ {print $2}' "/proc/$PID/status" 2>/dev/null); THREADS=${THREADS:-n/a}
  FDS=$(fd_count)
  READ_BYTES=$(awk '$1=="read_bytes:" {print $2}' "/proc/$PID/io" 2>/dev/null); READ_BYTES=${READ_BYTES:-n/a}
  WRITE_BYTES=$(awk '$1=="write_bytes:" {print $2}' "/proc/$PID/io" 2>/dev/null); WRITE_BYTES=${WRITE_BYTES:-n/a}
  if [ "$SAMPLES" -eq 0 ]; then FIRST_RSS=$RSS; FIRST_FDS=$FDS; fi
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$NOW" "$PID" "$STATE" "$CPU" "$RSS" "$THREADS" "$FDS" "$READ_BYTES" "$WRITE_BYTES" "$SYSTEM_CPU" "$PROCESS_CAPACITY" "$PROCESS_RAM" "$SYSTEM_RAM" "$RAM_TOTAL" "$RAM_AVAILABLE" >>"$CSV"
  printf '%-9s %-5s %-9s %-11s %-9s' "${ELAPSED}s" "$STATE" "$SYSTEM_CPU" "$PROCESS_CAPACITY" "$CPU"
  for CORE in $CORE_LABELS; do
    CORE_CPU=$(awk -v key="$CORE" '$1==key {print $2}' "$RUN_DIR/cpu.percent")
    printf ' %-7s' "${CORE_CPU:-n/a}"
    printf ',%s' "${CORE_CPU:-n/a}" >>"$CSV"
  done
  printf ' %-9s %-8s %-10s %-6s %s\n' "$PROCESS_RAM" "$SYSTEM_RAM" "$RSS" "$FDS" "$THREADS"
  printf '\n' >>"$CSV"
  log "SAMPLE: elapsed=$ELAPSED pid=$PID state=$STATE system_cpu=$SYSTEM_CPU process_capacity=$PROCESS_CAPACITY process_one_core=$CPU rss_kib=$RSS threads=$THREADS fds=$FDS read_bytes=$READ_BYTES write_bytes=$WRITE_BYTES"
  log "RAM: process_percent=$PROCESS_RAM system_used_percent=$SYSTEM_RAM total_kib=$RAM_TOTAL available_kib=$RAM_AVAILABLE"
  while read -r CORE CORE_CPU; do log "CPU BUSY: $CORE=$CORE_CPU%"; done <"$RUN_DIR/cpu.percent"
  if [ "$STATE" = D ]; then BLOCKED=$((BLOCKED+1)); else BLOCKED=0; fi
  [ "$BLOCKED" -ne 3 ] || warn "Process remained in uninterruptible sleep for three consecutive samples; inspect I/O and kernel logs."
  SAMPLES=$((SAMPLES+1)); PREV_TOTAL=$TOTAL; PREV_TICKS=$TICKS
  PREV_CORES=$CURRENT_CORES
  cp "$RUN_DIR/cpu.current" "$RUN_DIR/cpu.previous"
  [ "$ELAPSED" -lt "$DURATION" ] || break
  WAIT=$INTERVAL; LEFT=$((DURATION-ELAPSED)); [ "$WAIT" -le "$LEFT" ] || WAIT=$LEFT
  pause "$WAIT"
done
if [ "$SAMPLES" -gt 0 ]; then
  info "RSS KiB: $FIRST_RSS -> $RSS; open FDs: $FIRST_FDS -> $FDS. Growth alone does not prove a leak."
  if [ "$RSS" = n/a ] || [ "$FDS" = n/a ]; then warn 'Some process counters were unavailable; see CSV n/a fields.'; fi
fi
if dmesg >"$RUN_DIR/kernel.txt" 2>"$RUN_DIR/kernel.stderr"; then
  tail -n 200 "$RUN_DIR/kernel.txt" | grep -iE 'out of memory|oom|killed process|hung task|blocked for more than' >"$RUN_DIR/kernel-markers.txt" || :
  [ ! -s "$RUN_DIR/kernel-markers.txt" ] || info 'Kernel OOM/blocked-task markers saved; they may predate this observation.'
else
  rm -f "$RUN_DIR/kernel.txt"
  info 'Kernel log unavailable; no clean-kernel verdict was made.'
fi
info "CSV: $CSV ($SAMPLES samples)"
[ "$FAILURES" -ne 0 ] || ok 'Process monitoring completed; see sampled counters and their limits.'
finish
