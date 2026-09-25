#!/bin/sh

# iRidi Cloud Diagnostics for macOS
# Standalone CLI and interactive diagnostic tool for all iRidi products.
#
# Usage:
#   sh check_iridi_cloud_macos.sh
#   sh check_iridi_cloud_macos.sh --product i3knx
#   sh check_iridi_cloud_macos.sh --product bus77-home
#   sh check_iridi_cloud_macos.sh --product bus77-lite
#   sh check_iridi_cloud_macos.sh --product iridi-pro --region RU
#   sh check_iridi_cloud_macos.sh --product iridi-pro --region EU
#   sh check_iridi_cloud_macos.sh --product iridi-pro --region CN

TOOL_VERSION="1.5"
PRODUCT=""
REGION="RU"
QUALITY_MODE=0

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --product|-p)
      [ "$#" -ge 2 ] || { printf '[NOT OK] --product requires a value.\n'; exit 2; }
      PRODUCT="$2"
      shift 2
      ;;
    --region|-r)
      [ "$#" -ge 2 ] || { printf '[NOT OK] --region requires a value.\n'; exit 2; }
      REGION="$2"
      shift 2
      ;;
    --quality|-q|--deep|--extended)
      QUALITY_MODE=1
      shift
      ;;
    --help|-h)
      printf 'Usage: sh %s [options]\n\n' "$0"
      printf 'Options:\n'
      printf '  -p, --product PRODUCT   Product to check: i3knx, bus77-home, bus77-lite, iridi-pro\n'
      printf '  -r, --region REGION     Region for iridi-pro: RU (default), EU, CN\n'
      printf '  -q, --quality           Run extended channel quality, latency, MTU, and throughput tests\n'
      printf '  -h, --help              Show this help message\n\n'
      printf 'Interactive mode is launched when no --product is provided.\n'
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1"
      exit 2
      ;;
  esac
done

# Interactive menu if product is not specified
if [ -z "$PRODUCT" ]; then
  while [ -z "$PRODUCT" ]; do
    printf '\033[2J\033[H' 2>/dev/null || clear 2>/dev/null || true
    printf '================================================================\n'
    printf '               iRidi Cloud Diagnostics (macOS)\n'
    printf '================================================================\n\n'
    printf 'Select product to diagnose:\n'
    printf '  1. i3 KNX\n'
    printf '  2. Bus77 Home\n'
    printf '  3. Bus77 Lite\n'
    printf '  4. iRidi Pro - RU region\n'
    printf '  5. iRidi Pro - EU region\n'
    printf '  6. iRidi Pro - CN region\n'
    printf '  0. Exit\n\n'
    printf 'Enter choice (0-6): '
    read -r CHOICE || exit 10
    case "$CHOICE" in
      1) PRODUCT="i3knx" ;;
      2) PRODUCT="bus77-home" ;;
      3) PRODUCT="bus77-lite" ;;
      4) PRODUCT="iridi-pro"; REGION="RU" ;;
      5) PRODUCT="iridi-pro"; REGION="EU" ;;
      6) PRODUCT="iridi-pro"; REGION="CN" ;;
      0) exit 0 ;;
      *)
        printf 'Invalid choice. Press Enter to continue...\n'
        read -r _ || exit 10
        continue
        ;;
    esac
    printf '\nRun extended quality & stability test (latency, loss, throughput, MTU)? [y/N]: '
    read -r QUALITY_ANSWER || exit 10
    case "$QUALITY_ANSWER" in
      [yY]*) QUALITY_MODE=1 ;;
      *) QUALITY_MODE=0 ;;
    esac
  done
fi

# Normalize product and region
PRODUCT="$(printf '%s' "$PRODUCT" | tr '[:upper:]' '[:lower:]')"
REGION="$(printf '%s' "$REGION" | tr '[:lower:]' '[:upper:]')"

case "$PRODUCT" in
  i3knx|bus77-home|bus77-lite|iridi-pro) ;;
  *)
    printf '[NOT OK] Unknown product: %s\n' "$PRODUCT"
    printf 'Allowed values: i3knx, bus77-home, bus77-lite, iridi-pro\n'
    exit 2
    ;;
esac

case "$REGION" in
  RU|EU|CN) ;;
  *)
    printf '[NOT OK] Unknown region: %s (allowed: RU, EU, CN)\n' "$REGION"
    exit 2
    ;;
esac

# Log directory and file setup
CURRENT_DIR="$(pwd 2>/dev/null || printf '.')"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd 2>/dev/null || printf '%s' "$CURRENT_DIR")"
LOG_DIR="${IRIDI_DIAG_LOG_DIR:-$SCRIPT_DIR/logs}"
mkdir -p "$LOG_DIR" 2>/dev/null || true
if ! touch "$LOG_DIR/.test_write_$$" 2>/dev/null; then
  LOG_DIR="${TMPDIR:-/tmp}/iridi_logs"
  mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="${TMPDIR:-/tmp}"
else
  rm -f "$LOG_DIR/.test_write_$$" 2>/dev/null || true
fi

LOG_PRODUCT="$(printf '%s' "$PRODUCT" | tr '-' '_')"
[ "$PRODUCT" = "iridi-pro" ] && LOG_PRODUCT="${LOG_PRODUCT}_$(printf '%s' "$REGION" | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S' 2>/dev/null || printf 'unknown_time')"
LOG_FILE="$LOG_DIR/${LOG_PRODUCT}_${TIMESTAMP}_$$.log"

# Open File Descriptor 3 for technical log
if ! exec 3>>"$LOG_FILE" 2>/dev/null; then
  LOG_FILE="${TMPDIR:-/tmp}/${LOG_PRODUCT}_${TIMESTAMP}_$$.log"
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

# Logging helpers
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

MAX_ATTEMPTS=3
RETRY_DELAY=1
CONNECT_TIMEOUT=6
REQUEST_TIMEOUT=15
GATE_TIMEOUT=5
HTTP_TOTAL=0
HTTP_OK=0
HTTP_FAIL=0
WARN_COUNT=0
GATE_STATUS="not checked"

USER_AGENT="iridi-diag/macos-$PRODUCT/$TOOL_VERSION"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/iridi-cloud-mac.XXXXXX" 2>/dev/null)"
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ]; then
  WORK_DIR="${TMPDIR:-/tmp}/iridi-cloud-mac.$$"
  mkdir -p "$WORK_DIR" || exit 2
fi

cleanup() {
  rm -rf "$WORK_DIR" 2>/dev/null || true
  exec 3>&- 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

# Product configurations
case "$PRODUCT" in
  i3knx)
    PRODUCT_LABEL="i3 KNX"
    GATE_HOSTS="37.27.5.98 85.192.35.27"
    QUALITY_LATENCY_URL="https://auth.eu.iridi.com/"
    QUALITY_LATENCY_LABEL="Authorization EU"
    QUALITY_THROUGHPUT_URL="https://www.iridi.com/"
    QUALITY_THROUGHPUT_LABEL="iRidi portal (www.iridi.com)"
    QUALITY_MTU_HOST="auth.eu.iridi.com"
    ;;
  bus77-home)
    PRODUCT_LABEL="Bus77 Home"
    GATE_HOSTS="37.27.5.98 85.192.35.27"
    QUALITY_LATENCY_URL="https://auth.ru.iridi.com/"
    QUALITY_LATENCY_LABEL="Authorization RU"
    QUALITY_THROUGHPUT_URL="https://www.iridi.com/"
    QUALITY_THROUGHPUT_LABEL="iRidi portal (www.iridi.com)"
    QUALITY_MTU_HOST="auth.ru.iridi.com"
    ;;
  bus77-lite)
    PRODUCT_LABEL="Bus77 Lite"
    GATE_HOSTS="37.27.5.98 85.192.35.27"
    QUALITY_LATENCY_URL="https://auth.ru.iridi.com/"
    QUALITY_LATENCY_LABEL="Authorization RU"
    QUALITY_THROUGHPUT_URL="https://www.iridi.com/"
    QUALITY_THROUGHPUT_LABEL="iRidi portal (www.iridi.com)"
    QUALITY_MTU_HOST="auth.ru.iridi.com"
    ;;
  iridi-pro)
    PRODUCT_LABEL="iRidi Pro $REGION"
    case "$REGION" in
      EU)
        GATE_HOSTS="37.27.5.98"
        QUALITY_LATENCY_URL="https://auth.eu.iridi.com/"
        QUALITY_LATENCY_LABEL="Authorization EU"
        QUALITY_THROUGHPUT_URL="http://iridi.com/"
        QUALITY_THROUGHPUT_LABEL="Update service (iridi.com)"
        QUALITY_MTU_HOST="auth.eu.iridi.com"
        ;;
      RU)
        GATE_HOSTS="85.192.35.27"
        QUALITY_LATENCY_URL="https://auth.ru.iridi.com/"
        QUALITY_LATENCY_LABEL="Authorization RU"
        QUALITY_THROUGHPUT_URL="http://iridi.com/"
        QUALITY_THROUGHPUT_LABEL="Update service (iridi.com)"
        QUALITY_MTU_HOST="auth.ru.iridi.com"
        ;;
      CN)
        GATE_HOSTS="37.27.5.98"
        QUALITY_LATENCY_URL="https://auth.eu.iridi.com/"
        QUALITY_LATENCY_LABEL="Authorization CN (Global)"
        QUALITY_THROUGHPUT_URL="http://iridi.com/"
        QUALITY_THROUGHPUT_LABEL="Update service (iridi.com)"
        QUALITY_MTU_HOST="auth.eu.iridi.com"
        ;;
    esac
    ;;
esac

# Technical Log Initial Header
log_tech "================================================================================"
log_tech "iRidi Cloud Diagnostics (macOS) - Technical Log"
log_tech "Version: $TOOL_VERSION | Product: $PRODUCT_LABEL | Region: $REGION"
log_tech "Host: $(hostname 2>/dev/null) | OS: $(uname -srm 2>/dev/null) | User: $(whoami 2>/dev/null)"
log_tech "Start Time: $(date 2>/dev/null)"
log_tech "Quality Mode: $QUALITY_MODE"
log_tech "Log File: $LOG_FILE"
log_tech "================================================================================"

# Screen Header
printf '%s================================================================%s\n' "$C_CYAN" "$C_RESET"
printf '  %siRidi Cloud Diagnostics%s — %s%s%s (v%s)\n' "$C_BOLD" "$C_RESET" "$C_CYAN" "$PRODUCT_LABEL" "$C_RESET" "$TOOL_VERSION"
printf '%s================================================================%s\n' "$C_CYAN" "$C_RESET"
printf 'Host: %s | OS: %s\n' "$(hostname 2>/dev/null || printf unknown)" "$(uname -sm 2>/dev/null || printf macOS)"
[ "$QUALITY_MODE" -eq 1 ] && printf 'Mode: %sExtended Quality & Stability Analysis%s\n' "$C_BOLD" "$C_RESET"
printf '\n'

resolve_host() {
  RESOLVED_IP=""
  if command -v nslookup >/dev/null 2>&1; then
    RESOLVED_IP="$(nslookup "$1" 2>/dev/null | awk '
      /^Address [0-9]+: / {ip=$3}
      /^Address: / {ip=$2}
      END {sub(/#.*/, "", ip); print ip}
    ')"
  fi
  if [ -z "$RESOLVED_IP" ] && command -v getent >/dev/null 2>&1; then
    RESOLVED_IP="$(getent ahostsv4 "$1" 2>/dev/null | awk 'NR==1 {print $1; exit}')"
  fi
  if [ -z "$RESOLVED_IP" ] && command -v dscacheutil >/dev/null 2>&1; then
    RESOLVED_IP="$(dscacheutil -q host -a name "$1" 2>/dev/null | awk '/^ip_address: / {print $2; exit}')"
  fi
}

probe_resource() {
  RESOURCE_ID="$1"
  RESOURCE_LABEL="$2"
  RESOURCE_URL="$3"
  EXPECTED_IP="$4"
  FOLLOW_REDIRECTS="$5"
  HTTP_TOTAL=$((HTTP_TOTAL + 1))

  BODY_FILE="$WORK_DIR/$RESOURCE_ID.body"
  HEADER_FILE="$WORK_DIR/$RESOURCE_ID.headers"
  ERROR_FILE="$WORK_DIR/$RESOURCE_ID.error"
  RESOURCE_HOST="${RESOURCE_URL#*://}"
  RESOURCE_HOST="${RESOURCE_HOST%%/*}"
  RESOURCE_HOST="${RESOURCE_HOST%%:*}"
  resolve_host "$RESOURCE_HOST"

  log_tech "PROBE START: $RESOURCE_LABEL ($RESOURCE_URL)"
  log_tech "  Host: $RESOURCE_HOST -> Resolved IP: ${RESOLVED_IP:-unresolved} (Expected IP: $EXPECTED_IP)"

  ATTEMPT=1
  while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
    rm -f "$BODY_FILE" "$HEADER_FILE" "$ERROR_FILE"
    HTTP_CODE=0
    REMOTE_IP=""
    CONTENT_TYPE=""
    BODY_SIZE=0
    ELAPSED="n/a"
    CLIENT="none"
    CLIENT_RC=127
    HTTP_RECEIVED=no

    if command -v curl >/dev/null 2>&1; then
      CLIENT="curl"
      REDIRECT_ARGS="--max-redirs 0"
      [ "$FOLLOW_REDIRECTS" = "yes" ] && REDIRECT_ARGS="--location --max-redirs 3"
      META="$(curl --insecure $REDIRECT_ARGS --connect-timeout "$CONNECT_TIMEOUT" --max-time "$REQUEST_TIMEOUT" \
        --silent --show-error --dump-header "$HEADER_FILE" \
        --header 'Accept: application/json, text/plain, */*' \
        --user-agent "$USER_AGENT" --output "$BODY_FILE" \
        --write-out '%{http_code}|%{remote_ip}|%{content_type}|%{size_download}|%{time_total}' \
        "$RESOURCE_URL" 2>"$ERROR_FILE")"
      CLIENT_RC=$?
      OLD_IFS=$IFS
      set -f
      IFS='|'
      set -- $META
      IFS=$OLD_IFS
      set +f
      HTTP_CODE="${1:-0}"
      REMOTE_IP="${2:-}"
      CONTENT_TYPE="${3:-}"
      BODY_SIZE="${4:-0}"
      ELAPSED="${5:-n/a}"
    elif command -v wget >/dev/null 2>&1; then
      CLIENT="wget"
      WGET_REDIRECT="--max-redirect=0"
      [ "$FOLLOW_REDIRECTS" = "yes" ] && WGET_REDIRECT="--max-redirect=3"
      WGET_TLS=""
      wget --help 2>&1 | grep -q -e '--no-check-certificate' && WGET_TLS="--no-check-certificate"
      wget $WGET_TLS $WGET_REDIRECT -T "$REQUEST_TIMEOUT" -t 1 -S -O "$BODY_FILE" \
        --header='Accept: application/json, text/plain, */*' \
        --user-agent="$USER_AGENT" "$RESOURCE_URL" \
        2>"$HEADER_FILE"
      CLIENT_RC=$?
      HTTP_CODE="$(awk '/^[[:space:]]*HTTP\/[0-9.]+ [0-9][0-9][0-9]/{code=$2} END{print code+0}' "$HEADER_FILE")"
      CONTENT_TYPE="$(awk -F': ' 'tolower($1) ~ /content-type/{value=$2} END{gsub(/\r/, "", value); print value}' "$HEADER_FILE")"
      REMOTE_IP="$(sed -n 's/.*Connecting to [^ ]* (\([^):]*\).*/\1/p' "$HEADER_FILE" | head -n 1)"
      [ -f "$BODY_FILE" ] && BODY_SIZE="$(wc -c <"$BODY_FILE" | tr -d ' ')"
    else
      break
    fi

    log_tech "  Attempt $ATTEMPT/$MAX_ATTEMPTS: client=$CLIENT rc=$CLIENT_RC http_code=$HTTP_CODE ip=$REMOTE_IP elapsed=${ELAPSED}s size=${BODY_SIZE}B"
    [ -s "$HEADER_FILE" ] && log_tech_file "HTTP Headers ($RESOURCE_ID)" "$HEADER_FILE"
    [ -s "$ERROR_FILE" ] && log_tech_file "Client Errors ($RESOURCE_ID)" "$ERROR_FILE"

    case "$HTTP_CODE" in
      2??|3??|4??|5??) HTTP_RECEIVED=yes ;;
    esac
    [ "$HTTP_RECEIVED" = "yes" ] && break
    [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ] && break
    sleep "$RETRY_DELAY"
    ATTEMPT=$((ATTEMPT + 1))
  done

  case "$HTTP_CODE" in
    2??|3??|4??) AVAILABLE=yes ;;
    *) AVAILABLE=no ;;
  esac
  [ "$AVAILABLE" = "yes" ] && [ -z "$REMOTE_IP" ] && REMOTE_IP="$RESOLVED_IP"

  # Human-readable display formatting
  ELAPSED_MS="n/a"
  if [ "$ELAPSED" != "n/a" ]; then
    ELAPSED_MS="$(awk -v t="$ELAPSED" 'BEGIN { printf "%dms", (t * 1000) }' 2>/dev/null || printf '%ss' "$ELAPSED")"
  fi

  IP_INFO="${REMOTE_IP:-unresolved}"
  IP_WARN=""
  if [ "$EXPECTED_IP" != "dynamic" ] && [ -n "$REMOTE_IP" ] && [ "$REMOTE_IP" != "$EXPECTED_IP" ]; then
    IP_WARN=" (expected $EXPECTED_IP)"
  fi

  if [ "$AVAILABLE" = "yes" ]; then
    HTTP_OK=$((HTTP_OK + 1))
    if [ -n "$IP_WARN" ] || [ "$ATTEMPT" -gt 1 ]; then
      WARN_COUNT=$((WARN_COUNT + 1))
      printf '  %s[ATTENTION]%s %-26s %s (HTTP %s, %s, IP: %s%s)\n' \
        "$C_YELLOW" "$C_RESET" "$RESOURCE_LABEL" "$RESOURCE_HOST" "$HTTP_CODE" "$ELAPSED_MS" "$IP_INFO" "$IP_WARN"
      [ "$ATTEMPT" -gt 1 ] && printf '              %s! Succeeded on retry attempt %s of %s%s\n' "$C_DIM" "$ATTEMPT" "$MAX_ATTEMPTS" "$C_RESET"
      [ -n "$IP_WARN" ] && printf '              %s! Actual IP differs from documented IP (CDN/Proxy in use)%s\n' "$C_DIM" "$C_RESET"
      log_tech "PROBE RESULT: ATTENTION for $RESOURCE_LABEL"
    else
      printf '  %s[OK]%s        %-26s %s (HTTP %s, %s, IP: %s)\n' \
        "$C_GREEN" "$C_RESET" "$RESOURCE_LABEL" "$RESOURCE_HOST" "$HTTP_CODE" "$ELAPSED_MS" "$IP_INFO"
      log_tech "PROBE RESULT: OK for $RESOURCE_LABEL"
    fi
  else
    HTTP_FAIL=$((HTTP_FAIL + 1))
    printf '  %s[NOT OK]%s    %-26s %s (HTTP %s, %s)\n' \
      "$C_RED" "$C_RESET" "$RESOURCE_LABEL" "$RESOURCE_HOST" "${HTTP_CODE:-0}" "$IP_INFO"
    
    ERR_MSG=""
    if [ -s "$ERROR_FILE" ]; then
      ERR_MSG="$(tail -n 1 "$ERROR_FILE" | tr '\r\n' ' ')"
    elif [ -s "$HEADER_FILE" ]; then
      ERR_MSG="$(head -n 1 "$HEADER_FILE" | tr '\r\n' ' ')"
    fi
    [ -n "$ERR_MSG" ] && printf '              %s! Error: %s%s\n' "$C_RED" "$ERR_MSG" "$C_RESET"
    log_tech "PROBE RESULT: FAIL for $RESOURCE_LABEL (HTTP $HTTP_CODE, client_rc $CLIENT_RC)"
  fi
}

check_gate_tcp() {
  _HOST="$1"; _PORT="$2"
  if command -v nc >/dev/null 2>&1; then
    nc -G "$GATE_TIMEOUT" -z "$_HOST" "$_PORT" 2>/dev/null && return 0
  fi
  if command -v curl >/dev/null 2>&1; then
    curl --connect-timeout "$GATE_TIMEOUT" --max-time "$GATE_TIMEOUT" \
      --silent --show-error "http://$_HOST:$_PORT/" >/dev/null 2>&1
    _RC=$?
    case "$_RC" in 0|52|56) return 0 ;; esac
  fi
  return 1
}

check_gate() {
  printf '\n%s2. Cloud Gate TCP Connectivity (ports 9088/9089):%s\n' "$C_BOLD" "$C_RESET"
  log_tech "CLOUD GATE CHECK: hosts=$GATE_HOSTS"
  GATE_OK=0
  GATE_TOTAL=0
  for GH in $GATE_HOSTS; do
    for PORT in 9088 9089; do
      GATE_TOTAL=$((GATE_TOTAL + 1))
      if check_gate_tcp "$GH" "$PORT"; then
        printf '  %s[OK]%s        %s:%-5s (TCP port connected successfully)\n' "$C_GREEN" "$C_RESET" "$GH" "$PORT"
        GATE_OK=$((GATE_OK + 1))
        log_tech "  Gate TCP $GH:$PORT: OK"
      else
        printf '  %s[ATTENTION]%s %s:%-5s (connection timeout after %ss)\n' "$C_YELLOW" "$C_RESET" "$GH" "$PORT" "$GATE_TIMEOUT"
        WARN_COUNT=$((WARN_COUNT + 1))
        log_tech "  Gate TCP $GH:$PORT: TIMEOUT"
      fi
    done
  done

  if [ "$GATE_OK" -eq 0 ]; then
    GATE_STATUS="not reachable (0 of $GATE_TOTAL)"
    printf '  %s[NOT OK]%s    No Cloud Gate endpoints accepted a connection\n' "$C_RED" "$C_RESET"
    GATE_FAILED=1
    log_tech "GATE RESULT: FAIL (0/$GATE_TOTAL reachable)"
  else
    GATE_STATUS="reachable ($GATE_OK of $GATE_TOTAL)"
    GATE_FAILED=0
    log_tech "GATE RESULT: OK ($GATE_OK/$GATE_TOTAL reachable)"
  fi
}

run_quality_latency() {
  _URL="$1"
  _LABEL="$2"
  printf '  • Latency & Loss (%s):\n' "$_LABEL"
  log_tech "QUALITY LATENCY: target=$_URL label=$_LABEL"
  _SUCCESS=0
  _TOTAL=10
  _SUM_MS=0
  _MIN_MS=999999
  _MAX_MS=0
  _DNS_SUM_MS=0

  i=1
  while [ "$i" -le "$_TOTAL" ]; do
    if command -v curl >/dev/null 2>&1; then
      _OUT="$(curl --insecure --silent --output /dev/null --connect-timeout 5 --max-time 8 \
        --user-agent "$USER_AGENT" \
        --write-out '%{http_code}|%{time_total}|%{time_namelookup}' \
        "$_URL" 2>/dev/null)"
      _CODE="$(printf '%s' "$_OUT" | cut -d'|' -f1)"
      _TIME_S="$(printf '%s' "$_OUT" | cut -d'|' -f2)"
      _DNS_S="$(printf '%s' "$_OUT" | cut -d'|' -f3)"
      _MS="$(awk -v t="${_TIME_S:-0}" 'BEGIN { printf "%d", (t * 1000) }' 2>/dev/null || echo 0)"
      _DNS_MS="$(awk -v t="${_DNS_S:-0}" 'BEGIN { printf "%d", (t * 1000) }' 2>/dev/null || echo 0)"

      log_tech "    Probe $i/$_TOTAL: code=$_CODE time=${_MS}ms dns=${_DNS_MS}ms"
      case "$_CODE" in
        2??|3??|4??)
          _SUCCESS=$((_SUCCESS + 1))
          _SUM_MS=$((_SUM_MS + _MS))
          _DNS_SUM_MS=$((_DNS_SUM_MS + _DNS_MS))
          [ "$_MS" -lt "$_MIN_MS" ] && _MIN_MS="$_MS"
          [ "$_MS" -gt "$_MAX_MS" ] && _MAX_MS="$_MS"
          ;;
      esac
    fi
    i=$((i + 1))
  done

  _LOSS=$(( ((_TOTAL - _SUCCESS) * 100) / _TOTAL ))
  if [ "$_SUCCESS" -gt 0 ]; then
    _AVG_MS=$((_SUM_MS / _SUCCESS))
    _AVG_DNS_MS=$((_DNS_SUM_MS / _SUCCESS))
    [ "$_MIN_MS" -eq 999999 ] && _MIN_MS=0
    
    if [ "$_LOSS" -eq 0 ]; then
      if [ "$_AVG_MS" -gt 1000 ]; then
        printf '    %s[ATTENTION]%s 0%% loss | min %sms, avg %sms, max %sms (high average latency)\n' "$C_YELLOW" "$C_RESET" "$_MIN_MS" "$_AVG_MS" "$_MAX_MS"
        WARN_COUNT=$((WARN_COUNT + 1))
      else
        printf '    %s[OK]%s        0%% loss (10/10) | min %sms, avg %sms, max %sms\n' "$C_GREEN" "$C_RESET" "$_MIN_MS" "$_AVG_MS" "$_MAX_MS"
      fi
    elif [ "$_LOSS" -le 20 ]; then
      printf '    %s[ATTENTION]%s %s%% packet loss (%s/%s) | min %sms, avg %sms, max %sms\n' "$C_YELLOW" "$C_RESET" "$_LOSS" "$_SUCCESS" "$_TOTAL" "$_MIN_MS" "$_AVG_MS" "$_MAX_MS"
      WARN_COUNT=$((WARN_COUNT + 1))
    else
      printf '    %s[NOT OK]%s    %s%% packet loss (%s/%s) | connection unstable\n' "$C_RED" "$C_RESET" "$_LOSS" "$_SUCCESS" "$_TOTAL"
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
  else
    printf '    %s[NOT OK]%s    100%% packet loss (0/%s probes succeeded)\n' "$C_RED" "$C_RESET" "$_TOTAL"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
}

run_quality_throughput() {
  _URL="$1"
  _LABEL="$2"
  printf '  • Download Throughput (%s):\n' "$_LABEL"
  log_tech "QUALITY THROUGHPUT: target=$_URL"
  if command -v curl >/dev/null 2>&1; then
    _OUT="$(curl --insecure --location --silent --output /dev/null --connect-timeout 6 --max-time 15 \
      --user-agent "$USER_AGENT" \
      --write-out '%{speed_download}|%{size_download}|%{time_total}' \
      "$_URL" 2>/dev/null)"
    _SPEED="$(printf '%s' "$_OUT" | cut -d'|' -f1)"
    _SIZE="$(printf '%s' "$_OUT" | cut -d'|' -f2)"
    _TIME="$(printf '%s' "$_OUT" | cut -d'|' -f3)"

    _BYTES_PER_SEC="$(awk -v s="${_SPEED:-0}" 'BEGIN { printf "%d", s }' 2>/dev/null || echo 0)"
    _KB_PER_SEC=$(( _BYTES_PER_SEC / 1024 ))
    _DOWNLOADED_KB=$(( ${_SIZE:-0} / 1024 ))

    log_tech "    Throughput result: ${_KB_PER_SEC} KB/s, transferred ${_DOWNLOADED_KB} KB in ${_TIME}s"

    if [ "$_BYTES_PER_SEC" -gt 0 ]; then
      if [ "$_KB_PER_SEC" -ge 1024 ]; then
        _MB_FMT="$(awk -v k="$_KB_PER_SEC" 'BEGIN { printf "%.2f MB/s", (k / 1024) }' 2>/dev/null || echo "${_KB_PER_SEC} KB/s")"
        _SPEED_STR="$_MB_FMT"
      else
        _SPEED_STR="${_KB_PER_SEC} KB/s"
      fi

      if [ "$_KB_PER_SEC" -lt 128 ]; then
        printf '    %s[ATTENTION]%s %s (%s KB in %ss) — low speed for large projects\n' "$C_YELLOW" "$C_RESET" "$_SPEED_STR" "$_DOWNLOADED_KB" "${_TIME:-n/a}"
        WARN_COUNT=$((WARN_COUNT + 1))
      else
        printf '    %s[OK]%s        %s (%s KB in %ss)\n' "$C_GREEN" "$C_RESET" "$_SPEED_STR" "$_DOWNLOADED_KB" "${_TIME:-n/a}"
      fi
    else
      printf '    %s[INFO]%s      Throughput test skipped or endpoint redirected\n' "$C_GRAY" "$C_RESET"
    fi
  fi
}

run_quality_gate() {
  _HOSTS="$1"
  printf '  • Gate Burst Stability:\n'
  log_tech "QUALITY GATE BURST: hosts=$_HOSTS"
  for _GH in $_HOSTS; do
    for _PORT in 9088 9089; do
      _G_OK=0
      _G_TIME_SUM=0
      for _TRY in 1 2 3; do
        if command -v curl >/dev/null 2>&1; then
          _C_OUT="$(curl --connect-timeout 5 --max-time 6 --silent \
            --write-out '%{time_connect}' \
            "http://$_GH:$_PORT/" </dev/null 2>/dev/null)"
          _RC=$?
          case "$_RC" in
            0|52|56)
              _G_OK=$((_G_OK + 1))
              _C_MS="$(awk -v t="${_C_OUT:-0}" 'BEGIN { printf "%d", (t * 1000) }' 2>/dev/null || echo 0)"
              _G_TIME_SUM=$((_G_TIME_SUM + _C_MS))
              ;;
          esac
        elif command -v nc >/dev/null 2>&1; then
          if nc -w 5 "$_GH" "$_PORT" </dev/null >/dev/null 2>&1; then
            _G_OK=$((_G_OK + 1))
          fi
        fi
      done
      log_tech "    Gate $_GH:$_PORT: $_G_OK/3 connected"
      if [ "$_G_OK" -eq 3 ]; then
        _G_AVG=$((_G_TIME_SUM / 3))
        [ "$_G_AVG" -gt 0 ] && _AVG_STR=" (avg handshake: ${_G_AVG}ms)" || _AVG_STR=""
        printf '    %s[OK]%s        %s:%-5s 3/3 connections%s\n' "$C_GREEN" "$C_RESET" "$_GH" "$_PORT" "$_AVG_STR"
      elif [ "$_G_OK" -gt 0 ]; then
        printf '    %s[ATTENTION]%s %s:%-5s %s/3 connections (intermittent resets)\n' "$C_YELLOW" "$C_RESET" "$_GH" "$_PORT" "$_G_OK"
        WARN_COUNT=$((WARN_COUNT + 1))
      else
        printf '    %s[NOT OK]%s    %s:%-5s 0/3 connections failed\n' "$C_RED" "$C_RESET" "$_GH" "$_PORT"
        WARN_COUNT=$((WARN_COUNT + 1))
      fi
    done
  done
}

run_quality_mtu() {
  _TARGET_HOST="$1"
  printf '  • Path MTU & Packet Fragmentation:\n'
  log_tech "QUALITY MTU: host=$_TARGET_HOST"
  if ! command -v ping >/dev/null 2>&1; then
    printf '    %s[INFO]%s      ping utility not available; MTU test skipped\n' "$C_GRAY" "$C_RESET"
    return 0
  fi

  if ! ping -c 1 -W 2 "$_TARGET_HOST" >/dev/null 2>&1 && ! ping -c 1 "$_TARGET_HOST" >/dev/null 2>&1; then
    printf '    %s[INFO]%s      ICMP ping filtered; MTU test skipped\n' "$C_GRAY" "$C_RESET"
    return 0
  fi

  _MTU_1500=0
  if ping -c 2 -W 2 -D -s 1472 "$_TARGET_HOST" >/dev/null 2>&1; then
    _MTU_1500=1
  elif ping -c 2 -W 2 -s 1472 "$_TARGET_HOST" >/dev/null 2>&1; then
    _MTU_1500=1
  fi

  if [ "$_MTU_1500" -eq 1 ]; then
    printf '    %s[OK]%s        Standard 1500-byte MTU supported without fragmentation\n' "$C_GREEN" "$C_RESET"
    log_tech "    MTU 1500: OK"
  else
    _MTU_1400=0
    if ping -c 2 -W 2 -D -s 1372 "$_TARGET_HOST" >/dev/null 2>&1; then
      _MTU_1400=1
    elif ping -c 2 -W 2 -s 1372 "$_TARGET_HOST" >/dev/null 2>&1; then
      _MTU_1400=1
    fi

    if [ "$_MTU_1400" -eq 1 ]; then
      printf '    %s[ATTENTION]%s 1500-byte dropped, 1400-byte passed (MSS clamping/VPN active)\n' "$C_YELLOW" "$C_RESET"
      WARN_COUNT=$((WARN_COUNT + 1))
      log_tech "    MTU 1500: FAILED, MTU 1400: OK"
    else
      printf '    %s[ATTENTION]%s Large ICMP frames dropped (network restricted)\n' "$C_YELLOW" "$C_RESET"
      WARN_COUNT=$((WARN_COUNT + 1))
      log_tech "    MTU Large: FAILED"
    fi
  fi
}

printf '%s1. Cloud HTTP/HTTPS Services:%s\n' "$C_BOLD" "$C_RESET"

# Execute checks for selected product
case "$PRODUCT" in
  i3knx)
    probe_resource www "Website & Downloads" "https://www.iridi.com/" "89.169.183.139" yes
    probe_resource auth-eu "Authorization EU" "https://auth.eu.iridi.com/" "95.216.162.71" yes
    probe_resource proxy-auth-eu "Auth Proxy EU" "https://proxy.auth.eu.iridi.com/" "72.56.78.171" yes
    probe_resource proxy-auth-cloud "Auth Proxy Cloud" "https://proxy.auth.eu.iridi.cloud/" "94.131.83.102" yes
    probe_resource i3knx-eu "i3 KNX Cloud EU" "https://i3knx.eu.iridi.com/" "95.216.162.71" yes
    probe_resource proxy-i3knx-eu "i3 KNX Proxy EU" "https://proxy.i3knx.eu.iridi.com/" "147.45.238.146" yes
    probe_resource proxy-knx-cloud "KNX Proxy Cloud" "https://proxy.knx.eu.iridi.cloud/" "94.131.87.121" yes
    probe_resource proxy-s3-eu "Storage Proxy EU" "https://proxy.s3.eu.iridi.com/" "72.56.68.146" yes
    probe_resource ping "Control Endpoint" "https://ping.iridiummobile.net/" "52.222.136.36" yes
    probe_resource s3-eu "Project Storage EU" "https://s3.eu.iridi.com/" "95.217.164.135" yes
    ;;
  bus77-home)
    probe_resource www "Website & Downloads" "https://www.iridi.com/" "89.169.183.139" yes
    probe_resource auth-ru "Authorization RU" "https://auth.ru.iridi.com/" "84.201.152.245" yes
    probe_resource endpoint "Cloud Endpoint" "https://endpoint.iridi.com/" "95.181.182.182" yes
    probe_resource bus77-home "Bus77 Home Cloud" "https://bus77home.ru.iridi.com/" "84.201.152.245" yes
    probe_resource iphub-home "IP-Hub Home Cloud" "https://iphubhome.ru.iridi.com/" "37.139.42.137" yes
    probe_resource commercial "Commercial Offers API" "https://api.commercial-offer.iridi.com/" "213.219.212.191" yes
    probe_resource voice-cws "Voice Assistants (CWS)" "https://cws.iridi.com:7972/" "185.32.84.60" no
    ;;
  bus77-lite)
    probe_resource www "Website & Downloads" "https://www.iridi.com/" "89.169.183.139" yes
    probe_resource auth-ru "Authorization RU" "https://auth.ru.iridi.com/" "84.201.152.245" yes
    probe_resource endpoint "Cloud Endpoint" "https://endpoint.iridi.com/" "95.181.182.182" yes
    probe_resource bus77-lite "Bus77 Lite Cloud" "https://bus77lite.ru.iridi.com/" "84.201.152.245" yes
    probe_resource iphub-lite "IP-Hub Lite Cloud" "https://iphub.ru.iridi.com/" "51.250.30.171" yes
    probe_resource commercial "Commercial Offers API" "https://api.commercial-offer.iridi.com/" "213.219.212.191" yes
    probe_resource voice-cws "Voice Assistants (CWS)" "https://cws.iridi.com:7972/" "185.32.84.60" no
    ;;
  iridi-pro)
    case "$REGION" in
      EU)
        probe_resource auth-eu "Authorization EU" "https://auth.eu.iridi.com/" "95.216.162.71" yes
        probe_resource i3pro-eu "i3 Pro Cloud EU" "https://i3pro.eu.iridi.com/" "95.216.162.71" yes
        probe_resource storage-eu "AWS Storage EU" "https://s3.us-east-1.amazonaws.com/" "dynamic" yes
        probe_resource projects-eu "i3 Pro Projects EU" "https://iridium-cloud-files.s3.amazonaws.com/" "dynamic" yes
        probe_resource updates-site "Update Service" "http://iridi.com/" "89.169.183.139" no
        probe_resource updates-s3 "Update Files" "http://iridium3download.s3.amazonaws.com/" "dynamic" no
        ;;
      RU)
        probe_resource auth-ru "Authorization RU" "https://auth.ru.iridi.com/" "84.201.152.245" yes
        probe_resource i3pro-ru "i3 Pro Cloud RU" "https://i3pro.ru.iridi.com/" "84.201.152.245" yes
        probe_resource storage-ru "RU Storage" "https://storage.yandexcloud.net/" "213.180.193.243" yes
        probe_resource projects-ru "i3 Pro Projects RU" "https://i3pro.storage.yandexcloud.net/" "213.180.193.243" yes
        probe_resource updates-site "Update Service" "http://iridi.com/" "89.169.183.139" no
        probe_resource updates-s3 "Update Files" "http://iridium3download.s3.amazonaws.com/" "dynamic" no
        ;;
      CN)
        probe_resource auth-cn "Authorization CN" "https://auth.eu.iridi.com/" "95.216.162.71" yes
        probe_resource i3pro-cn "i3 Pro Cloud CN" "https://i3pro.eu.iridi.com/" "95.216.162.71" yes
        probe_resource storage-cn "CN Object Storage" "https://ir-endpoint.oss-cn-shanghai.aliyuncs.com/" "106.14.228.182" yes
        probe_resource projects-cn "i3 Pro Projects CN" "https://ir-proj-sh.oss-cn-shanghai.aliyuncs.com/" "106.14.228.182" yes
        probe_resource updates-site "Update Service" "http://iridi.com/" "89.169.183.139" no
        probe_resource updates-cn "CN Update Files" "http://iridium3download.oss-cn-hangzhou.aliyuncs.com/" "118.178.60.104" no
        ;;
    esac
    ;;
esac

check_gate

if [ "$QUALITY_MODE" -eq 1 ]; then
  printf '\n%s3. Extended Channel Quality & Stability Analysis:%s\n' "$C_BOLD" "$C_RESET"
  run_quality_latency "$QUALITY_LATENCY_URL" "$QUALITY_LATENCY_LABEL"
  run_quality_throughput "$QUALITY_THROUGHPUT_URL" "$QUALITY_THROUGHPUT_LABEL"
  run_quality_gate "$GATE_HOSTS"
  run_quality_mtu "$QUALITY_MTU_HOST"
fi

# Summary
printf '\n%s================================================================%s\n' "$C_CYAN" "$C_RESET"
printf '  %sDIAGNOSTIC SUMMARY%s\n' "$C_BOLD" "$C_RESET"
printf '%s================================================================%s\n' "$C_CYAN" "$C_RESET"
printf 'HTTP Services: %s of %s available (%s failed)\n' "$HTTP_OK" "$HTTP_TOTAL" "$HTTP_FAIL"
printf 'Cloud Gate:    %s\n' "$GATE_STATUS"
printf 'Warnings:      %s\n' "$WARN_COUNT"

log_tech "SUMMARY: total=$HTTP_TOTAL ok=$HTTP_OK fail=$HTTP_FAIL warn=$WARN_COUNT gate_status=$GATE_STATUS"

if [ "$HTTP_FAIL" -gt 0 ] || [ "${GATE_FAILED:-0}" -eq 1 ]; then
  printf '\n%sRESULT: FAIL — One or more critical cloud resources are unavailable.%s\n' "$C_RED" "$C_RESET"
  printf 'Detailed technical log: %s\n\n' "$LOG_FILE"
  log_tech "RESULT: FAIL"
  exit 2
fi

if [ "$WARN_COUNT" -gt 0 ]; then
  printf '\n%sRESULT: WARN — Cloud services are reachable, but warnings were detected.%s\n' "$C_YELLOW" "$C_RESET"
  printf 'Detailed technical log: %s\n\n' "$LOG_FILE"
  log_tech "RESULT: WARN"
  exit 1
fi

printf '\n%sRESULT: PASS — All required cloud resources and Cloud Gate are reachable.%s\n' "$C_GREEN" "$C_RESET"
if [ "$QUALITY_MODE" -eq 0 ]; then
  printf 'Tip: For deeper channel quality and latency benchmarks, run: %ssh %s --quality%s\n' "$C_DIM" "$0" "$C_RESET"
fi
printf 'Detailed technical log: %s\n\n' "$LOG_FILE"
log_tech "RESULT: PASS"
exit 0
