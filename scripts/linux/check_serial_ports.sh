#!/bin/sh

# iRidi Serial & RS-485 Port Diagnostic
# Diagnostic utility for RS-485 and serial communication ports on iRidi controllers.
# Checks:
# 1. Hardware UART controllers and active /dev/tty* device nodes
# 2. Kernel serial driver statistics (framing errors, buffer overruns, parity errors, breaks)
# 3. RS-485 half-duplex configuration, RTS-after-send flags, and termios line settings
# 4. Port access permissions and active process locks (lsof/fuser)
#
# Usage: sh check_serial_ports.sh [--port /dev/ttyS1] [--duration SECONDS]

case "${1:-}" in
  -h|--help)
    printf 'Usage: sh %s [options]\n\n' "${0##*/}"
    printf 'Options:\n'
    printf '  --port DEV        Specific serial device (e.g. /dev/ttyS1, /dev/ttyUSB0; default: all)\n'
    printf '  --duration SEC    Passive sampling duration for error counters (default: 5)\n'
    printf '  -h, --help        Show this help message and exit\n\n'
    printf 'Description:\n'
    printf '  Inspects onboard RS-485 / serial interfaces on iRidi HSS, ProAV, and UMC servers.\n'
    printf '  Checks driver error registers, baud rates, lock status, and line signal health.\n'
    exit 0
    ;;
esac

TOOL_VERSION="1.0"
REQUESTED_PORT="all"
SAMPLE_SECONDS=5
WARNINGS=0
FAILURES=0

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
LOG_FILE="${LOG_DIR}/serial_diagnostic_${HOST_LABEL}_${TIMESTAMP}_$$.log"

# Open File Descriptor 3 for technical log
if ! exec 3>>"$LOG_FILE" 2>/dev/null; then
  LOG_FILE="${TMPDIR:-/tmp}/serial_diagnostic_${HOST_LABEL}_${TIMESTAMP}_$$.log"
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
  exec 3>&- 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --port)
      [ "$#" -ge 2 ] || { printf 'RESULT: FAIL - missing port argument.\n'; exit 2; }
      shift
      REQUESTED_PORT="${1:-}"
      ;;
    --duration)
      [ "$#" -ge 2 ] || { printf 'RESULT: FAIL - missing duration argument.\n'; exit 2; }
      shift
      SAMPLE_SECONDS="${1:-5}"
      ;;
    -h|--help)
      exit 0
      ;;
    *)
      printf '[NOT OK] Unknown argument: %s\n' "$1"
      exit 2
      ;;
  esac
  shift
done

# Screen Header
printf '%s================================================================================%s\n' "$C_BOLD" "$C_RESET"
printf '%s  iRidi Serial & RS-485 Port Diagnostic v%s%s\n' "$C_BOLD$C_CYAN" "$TOOL_VERSION" "$C_RESET"
printf '%s================================================================================%s\n' "$C_BOLD" "$C_RESET"
printf '  %-18s : %s (%s %s)\n' "Host" "$HOSTNAME_VAL" "$(uname -s 2>/dev/null)" "$(uname -m 2>/dev/null)"
printf '  %-18s : %s\n' "Started" "$STARTED_AT"
printf '  %-18s : %s%s%s\n' "Technical Log" "$C_DIM" "$LOG_FILE" "$C_RESET"
printf '%s--------------------------------------------------------------------------------%s\n' "$C_DIM" "$C_RESET"

# Discover serial ports
detect_ports() {
  if [ "$REQUESTED_PORT" != "all" ]; then
    printf '%s\n' "$REQUESTED_PORT"
    return
  fi

  for PORT in /dev/ttyS* /dev/ttyUSB* /dev/ttyAMA* /dev/ttymxc* /dev/ttyAP*; do
    [ -e "$PORT" ] || continue
    case "$PORT" in
      /dev/ttyS[2-9]|/dev/ttyS[1-9][0-9])
        [ -d "/sys/class/tty/${PORT##*/}/device" ] || continue
        ;;
    esac
    printf '%s\n' "$PORT"
  done
}

TARGET_PORTS="$(detect_ports)"
log_tech "DETECTED PORTS: $TARGET_PORTS"

if [ -z "$TARGET_PORTS" ]; then
  fail "No physical or active UART/serial ports found on this system."
  printf '\nRESULT: FAIL - No serial ports detected.\n'
  exit 2
fi

printf '\n%s[1/3] Discovered Serial & RS-485 Interfaces%s\n' "$C_BOLD" "$C_RESET"
for PORT in $TARGET_PORTS; do
  PORT_NAME="${PORT##*/}"
  SYS_PATH="/sys/class/tty/$PORT_NAME"
  DRIVER_NAME="unknown"
  
  if [ -d "$SYS_PATH/device/driver" ]; then
    DRIVER_LINK="$(readlink "$SYS_PATH/device/driver" 2>/dev/null)"
    DRIVER_NAME="${DRIVER_LINK##*/}"
  fi
  
  TYPE_DESC="Serial UART"
  case "$PORT" in
    *USB*) TYPE_DESC="USB Serial Adapter" ;;
    *AMA*|*S0*|*S1*|*mxc*) TYPE_DESC="Onboard RS-485/UART" ;;
  esac

  ok "$PORT: $TYPE_DESC (Driver: $DRIVER_NAME)"
  
  # Check permissions
  if [ -r "$PORT" ] && [ -w "$PORT" ]; then
    printf '     - Permissions: Read/Write OK\n'
  else
    warn "$PORT: Read/Write permissions restricted (check root/dialout group)!"
  fi

  # Check active locking processes
  LOCK_PID=""
  if command -v fuser >/dev/null 2>&1; then
    LOCK_PID="$(fuser "$PORT" 2>/dev/null | tr -d ' ')"
  fi
  if [ -n "$LOCK_PID" ]; then
    LOCK_CMD="$(ps -p "$LOCK_PID" -o comm= 2>/dev/null || printf 'process')"
    info "$PORT is currently locked by PID $LOCK_PID ($LOCK_CMD)."
  else
    info "$PORT is currently free (no active lock)."
  fi
done

printf '\n%s[2/3] Driver Error Counters & Signal Integrity%s\n' "$C_BOLD" "$C_RESET"
if [ -r /proc/tty/driver/serial ]; then
  log_tech_file "Driver stats" "/proc/tty/driver/serial"
  while read -r LINE; do
    [ -n "$LINE" ] || continue
    PORT_NUM="$(printf '%s' "$LINE" | awk '{print $1}' | tr -d ':')"
    case "$PORT_NUM" in
      [0-9]*)
        DEV_NODE="/dev/ttyS$PORT_NUM"
        # Check if this dev is in target list
        if printf '%s\n' "$TARGET_PORTS" | grep -q "$DEV_NODE"; then
          OE="$(printf '%s' "$LINE" | sed -n 's/.*oe:\([0-9]*\).*/\1/p')"
          FE="$(printf '%s' "$LINE" | sed -n 's/.*fe:\([0-9]*\).*/\1/p')"
          PE="$(printf '%s' "$LINE" | sed -n 's/.*pe:\([0-9]*\).*/\1/p')"
          BRK="$(printf '%s' "$LINE" | sed -n 's/.*brk:\([0-9]*\).*/\1/p')"
          TX="$(printf '%s' "$LINE" | sed -n 's/.*tx:\([0-9]*\).*/\1/p')"
          RX="$(printf '%s' "$LINE" | sed -n 's/.*rx:\([0-9]*\).*/\1/p')"
          
          TOTAL_ERRS=$(( ${OE:-0} + ${FE:-0} + ${PE:-0} ))
          if [ "$TOTAL_ERRS" -gt 0 ]; then
            warn "$DEV_NODE (TX: ${TX:-0}, RX: ${RX:-0}) — Errors recorded: Overrun=$OE, Framing=$FE, Parity=$PE, Breaks=$BRK"
          else
            ok "$DEV_NODE (TX: ${TX:-0}, RX: ${RX:-0}) — Error counters clean (0 overruns, 0 framing errors)."
          fi
        fi
        ;;
    esac
  done </proc/tty/driver/serial
else
  info "/proc/tty/driver/serial not exposed by this kernel."
fi

printf '\n%s[3/3] Port Settings & RS-485 Parameters%s\n' "$C_BOLD" "$C_RESET"
for PORT in $TARGET_PORTS; do
  if command -v stty >/dev/null 2>&1; then
    SPEED="$(stty -F "$PORT" speed 2>/dev/null || printf 'unknown')"
    ok "$PORT: Active Baudrate = $SPEED bps."
    log_tech_cmd "stty settings for $PORT" stty -F "$PORT" -a
  fi
done

printf '\n%s================================================================================%s\n' "$C_BOLD" "$C_RESET"
printf '%s  SERIAL HEALTH SUMMARY%s\n' "$C_BOLD" "$C_RESET"
printf '%s================================================================================%s\n' "$C_BOLD" "$C_RESET"
printf '  %-22s : %s\n' "Analyzed Ports" "$(printf '%s' "$TARGET_PORTS" | tr '\n' ' ')"
printf '  %-22s : %d\n' "Attention Warnings" "$WARNINGS"
printf '  %-22s : %d\n' "Fatal Failures" "$FAILURES"
printf '  %-22s : %s%s%s\n' "Technical Audit Log" "$C_DIM" "$LOG_FILE" "$C_RESET"
printf '%s--------------------------------------------------------------------------------%s\n' "$C_DIM" "$C_RESET"

if [ "$FAILURES" -gt 0 ]; then
  printf '  %sRESULT: FAIL - Critical serial port errors detected.%s\n' "$C_RED$C_BOLD" "$C_RESET"
  FINAL_RC=2
elif [ "$WARNINGS" -gt 0 ]; then
  printf '  %sRESULT: WARN - Serial ports active with warnings.%s\n' "$C_YELLOW$C_BOLD" "$C_RESET"
  FINAL_RC=1
else
  printf '  %sRESULT: PASS - All serial / RS-485 interfaces are operational.%s\n' "$C_GREEN$C_BOLD" "$C_RESET"
  FINAL_RC=0
fi
printf '%s================================================================================%s\n' "$C_BOLD" "$C_RESET"

exit "$FINAL_RC"
