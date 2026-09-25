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

TOOL_VERSION="1.4"
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

# Automatic logging setup
if [ "${IRIDI_CLOUD_LOG_ACTIVE:-0}" != "1" ]; then
  CURRENT_DIR="$(pwd 2>/dev/null || printf '.')"
  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd 2>/dev/null || printf '%s' "$CURRENT_DIR")"
  LOG_DIR="$SCRIPT_DIR/logs"
  mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="${TMPDIR:-/tmp}/iridi_logs"
  mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="${TMPDIR:-/tmp}"

  LOG_PRODUCT="$(printf '%s' "$PRODUCT" | tr '-' '_')"
  [ "$PRODUCT" = "iridi-pro" ] && LOG_PRODUCT="${LOG_PRODUCT}_$(printf '%s' "$REGION" | tr '[:upper:]' '[:lower:]')"
  TIMESTAMP="$(date '+%Y%m%d_%H%M%S' 2>/dev/null || printf 'unknown_time')"
  LOG_FILE="$LOG_DIR/${LOG_PRODUCT}_${TIMESTAMP}_$$.log"

  export IRIDI_CLOUD_LOG_ACTIVE=1
  export IRIDI_CLOUD_LOG_FILE="$LOG_FILE"

  colorize_output() {
    awk '
      /\[OK\]|RESULT: PASS/ { printf "\033[32m%s\033[0m\n", $0; next }
      /\[ATTENTION\]|RESULT: WARN/ { printf "\033[33m%s\033[0m\n", $0; next }
      /\[NOT OK\]|RESULT: FAIL/ { printf "\033[31m%s\033[0m\n", $0; next }
      { print }
    '
  }

  EXTRA_ARGS=""
  [ "$QUALITY_MODE" -eq 1 ] && EXTRA_ARGS="--quality"

  if command -v tee >/dev/null 2>&1; then
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && command -v awk >/dev/null 2>&1; then
      sh "$0" --product "$PRODUCT" --region "$REGION" $EXTRA_ARGS 2>&1 | tee "$LOG_FILE" | colorize_output
    else
      sh "$0" --product "$PRODUCT" --region "$REGION" $EXTRA_ARGS 2>&1 | tee "$LOG_FILE"
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

  sh "$0" --product "$PRODUCT" --region "$REGION" >"$LOG_FILE" 2>&1
  FINAL_RC=$?
  cat "$LOG_FILE"
  printf '\nLog saved: %s\n' "$LOG_FILE"
  exit "$FINAL_RC"
fi

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
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

separator() {
  printf '%s\n' '----------------------------------------------------------------'
}

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
        --silent --show-error --header 'Accept: application/json, text/plain, */*' \
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
      ELAPSED="${5:-n/a} s"
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

  separator
  printf '%s\n' "$RESOURCE_LABEL"
  printf '  URL:              %s\n' "$RESOURCE_URL"
  printf '  DNS:              %s -> %s\n' "$RESOURCE_HOST" "${RESOLVED_IP:-not resolved}"
  printf '  Documented IP:    %s\n' "$EXPECTED_IP"
  printf '  Actual IP:        %s\n' "${REMOTE_IP:-not detected}"
  printf '  HTTP client:      %s\n' "$CLIENT"
  printf '  Attempt:          %s of %s\n' "$ATTEMPT" "$MAX_ATTEMPTS"
  printf '  HTTP response:    %s\n' "${HTTP_CODE:-0}"
  printf '  Content-Type:     %s\n' "${CONTENT_TYPE:-not provided}"
  printf '  Payload:          %s bytes\n' "${BODY_SIZE:-0}"
  [ "$ELAPSED" != "n/a" ] && printf '  Request time:     %s\n' "$ELAPSED"

  if [ "$EXPECTED_IP" != "dynamic" ] && [ -n "$REMOTE_IP" ] && [ "$REMOTE_IP" != "$EXPECTED_IP" ]; then
    printf '  [ATTENTION] The actual IP differs from the documented IP (a CDN, proxy, or gateway may be in use).\n'
    WARN_COUNT=$((WARN_COUNT + 1))
  fi

  if [ "$AVAILABLE" = "yes" ]; then
    if [ "$ATTEMPT" -gt 1 ]; then
      printf '  [ATTENTION] A response was received after a retry; the connection may be unstable.\n'
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
    printf '  [OK] The resource is reachable and returned an application-level HTTP response.\n'
    HTTP_OK=$((HTTP_OK + 1))
  else
    case "$HTTP_CODE" in
      5??) printf '  [NOT OK] The resource returned HTTP %s.\n' "$HTTP_CODE" ;;
      *) printf '  [NOT OK] No application-level HTTP response was received after %s attempts (client exit code %s).\n' "$ATTEMPT" "$CLIENT_RC" ;;
    esac
    if [ -s "$ERROR_FILE" ]; then
      printf '  Error: '
      tail -n 2 "$ERROR_FILE" | tr '\n' ' '
      printf '\n'
    elif [ -s "$HEADER_FILE" ]; then
      printf '  Error: '
      tail -n 2 "$HEADER_FILE" | tr '\n' ' '
      printf '\n'
    fi
    HTTP_FAIL=$((HTTP_FAIL + 1))
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
  separator
  printf 'Cloud Gate TCP connectivity: %s, ports 9088/9089\n' "$GATE_HOSTS"
  GATE_OK=0
  GATE_TOTAL=0
  for GH in $GATE_HOSTS; do
    for PORT in 9088 9089; do
      GATE_TOTAL=$((GATE_TOTAL + 1))
      printf '  %s:%s ... ' "$GH" "$PORT"
      if check_gate_tcp "$GH" "$PORT"; then
        printf '[OK] TCP port accepts connections.\n'
        GATE_OK=$((GATE_OK + 1))
      else
        printf '[ATTENTION] TCP port did not accept a connection within %s s.\n' "$GATE_TIMEOUT"
        WARN_COUNT=$((WARN_COUNT + 1))
      fi
    done
  done
  if [ "$GATE_OK" -eq 0 ]; then
    GATE_STATUS="not reachable (0 of $GATE_TOTAL)"
    printf '  [NOT OK] No Cloud Gate endpoint accepted a TCP connection.\n'
    GATE_FAILED=1
  else
    GATE_STATUS="reachable ($GATE_OK of $GATE_TOTAL)"
    printf '  [OK] Cloud Gate is reachable through %s of %s tested endpoints.\n' "$GATE_OK" "$GATE_TOTAL"
    GATE_FAILED=0
  fi
}

# Configure Product Title & Gate Hosts
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

run_quality_latency() {
  _URL="$1"
  _LABEL="$2"
  printf '1. Latency & Packet Loss test (10 probes to %s):\n' "$_LABEL"
  _SUCCESS=0
  _TOTAL=10
  _SUM_MS=0
  _MIN_MS=999999
  _MAX_MS=0
  _DNS_SUM_MS=0

  i=1
  printf '  Probing: '
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

      case "$_CODE" in
        2??|3??|4??)
          _SUCCESS=$((_SUCCESS + 1))
          _SUM_MS=$((_SUM_MS + _MS))
          _DNS_SUM_MS=$((_DNS_SUM_MS + _DNS_MS))
          [ "$_MS" -lt "$_MIN_MS" ] && _MIN_MS="$_MS"
          [ "$_MS" -gt "$_MAX_MS" ] && _MAX_MS="$_MS"
          printf '.'
          ;;
        *)
          printf 'x'
          ;;
      esac
    else
      if wget -q -O /dev/null --no-check-certificate --timeout=5 -t 1 "$_URL" 2>/dev/null; then
        _SUCCESS=$((_SUCCESS + 1))
        printf '.'
      else
        printf 'x'
      fi
    fi
    i=$((i + 1))
  done
  printf '\n'

  _LOSS=$(( ((_TOTAL - _SUCCESS) * 100) / _TOTAL ))
  if [ "$_SUCCESS" -gt 0 ]; then
    _AVG_MS=$((_SUM_MS / _SUCCESS))
    _AVG_DNS_MS=$((_DNS_SUM_MS / _SUCCESS))
    [ "$_MIN_MS" -eq 999999 ] && _MIN_MS=0
    printf '  Requests succeeded: %s of %s (%s%% loss)\n' "$_SUCCESS" "$_TOTAL" "$_LOSS"
    printf '  Latency (RTT):      min %sms | avg %sms | max %sms\n' "$_MIN_MS" "$_AVG_MS" "$_MAX_MS"
    [ "$_AVG_DNS_MS" -gt 0 ] && printf '  DNS lookup time:    avg %sms\n' "$_AVG_DNS_MS"
  else
    printf '  Requests succeeded: 0 of %s (100%% loss)\n' "$_TOTAL"
  fi

  if [ "$_LOSS" -eq 0 ]; then
    if [ "$_SUCCESS" -gt 0 ] && [ "$_AVG_MS" -gt 1000 ]; then
      printf '  [ATTENTION] All requests succeeded, but average latency is high (> 1000 ms).\n'
      WARN_COUNT=$((WARN_COUNT + 1))
    else
      printf '  [OK] Connection latency is stable with 0%% packet loss.\n'
    fi
  elif [ "$_LOSS" -le 20 ]; then
    printf '  [ATTENTION] Minor packet/request loss detected (%s%%). Connection may experience intermittent drops.\n' "$_LOSS"
    WARN_COUNT=$((WARN_COUNT + 1))
  else
    printf '  [NOT OK] High packet/request loss detected (%s%%). Connection is unstable.\n' "$_LOSS"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
}

run_quality_throughput() {
  _URL="$1"
  _LABEL="$2"
  printf '2. Bandwidth & Download Throughput (%s):\n' "$_LABEL"
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

    if [ "$_BYTES_PER_SEC" -gt 0 ]; then
      if [ "$_KB_PER_SEC" -ge 1024 ]; then
        _MB_FMT="$(awk -v k="$_KB_PER_SEC" 'BEGIN { printf "%.2f MB/s", (k / 1024) }' 2>/dev/null || echo "${_KB_PER_SEC} KB/s")"
        printf '  Download speed:     %s (%s KB transferred in %ss)\n' "$_MB_FMT" "$_DOWNLOADED_KB" "${_TIME:-n/a}"
      else
        printf '  Download speed:     %s KB/s (%s KB transferred in %ss)\n' "$_KB_PER_SEC" "$_DOWNLOADED_KB" "${_TIME:-n/a}"
      fi
      if [ "$_KB_PER_SEC" -lt 128 ]; then
        printf '  [ATTENTION] Download speed is low (< 128 KB/s). Large project uploads or downloads may be slow.\n'
        WARN_COUNT=$((WARN_COUNT + 1))
      else
        printf '  [OK] Download throughput is sufficient for project transfers and asset syncing.\n'
      fi
    else
      printf '  [INFO] Throughput benchmark returned 0 bytes (endpoint may be redirecting or protected).\n'
    fi
  else
    printf '  [INFO] curl is not available; throughput benchmark skipped.\n'
  fi
}

run_quality_gate() {
  _HOSTS="$1"
  printf '3. Cloud Gate Connection Stability (burst connect & timing):\n'
  for _GH in $_HOSTS; do
    for _PORT in 9088 9089; do
      printf '  Testing %s:%s (3 attempts) ... ' "$_GH" "$_PORT"
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
      if [ "$_G_OK" -eq 3 ]; then
        if [ "$_G_TIME_SUM" -gt 0 ]; then
          _G_AVG=$((_G_TIME_SUM / 3))
          printf '[OK] 3/3 connected (avg handshake: %sms)\n' "$_G_AVG"
        else
          printf '[OK] 3/3 connected successfully\n'
        fi
      elif [ "$_G_OK" -gt 0 ]; then
        printf '[ATTENTION] %s of 3 connected (intermittent TCP resets or packet loss)\n' "$_G_OK"
        WARN_COUNT=$((WARN_COUNT + 1))
      else
        printf '[NOT OK] 0 of 3 connected\n'
        WARN_COUNT=$((WARN_COUNT + 1))
      fi
    done
  done
}

run_quality_mtu() {
  _TARGET_HOST="$1"
  printf '4. Path MTU & Packet Size test (target: %s):\n' "$_TARGET_HOST"
  if ! command -v ping >/dev/null 2>&1; then
    printf '  [INFO] ping utility not available; MTU test skipped.\n'
    return 0
  fi

  if ! ping -c 1 -W 2 "$_TARGET_HOST" >/dev/null 2>&1 && ! ping -c 1 "$_TARGET_HOST" >/dev/null 2>&1; then
    printf '  [INFO] ICMP ping is filtered or unacknowledged by target host; MTU test skipped.\n'
    return 0
  fi

  _MTU_1500=0
  if ping -c 2 -W 2 -M do -s 1472 "$_TARGET_HOST" >/dev/null 2>&1; then
    _MTU_1500=1
  elif ping -c 2 -W 2 -s 1472 "$_TARGET_HOST" >/dev/null 2>&1; then
    _MTU_1500=1
  fi

  if [ "$_MTU_1500" -eq 1 ]; then
    printf '  [OK] Standard 1500-byte MTU packets pass without fragmentation drops.\n'
  else
    _MTU_1400=0
    if ping -c 2 -W 2 -M do -s 1372 "$_TARGET_HOST" >/dev/null 2>&1; then
      _MTU_1400=1
    elif ping -c 2 -W 2 -s 1372 "$_TARGET_HOST" >/dev/null 2>&1; then
      _MTU_1400=1
    fi

    if [ "$_MTU_1400" -eq 1 ]; then
      printf '  [ATTENTION] 1500-byte packets were dropped, but 1400-byte packets passed (possible VPN/PPPoE MSS clamping issue).\n'
      WARN_COUNT=$((WARN_COUNT + 1))
    else
      printf '  [ATTENTION] Large ICMP packets were dropped (network may restrict packet size or disallow large frames).\n'
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
  fi
}

# Banner
printf 'iRidi Cloud Check - %s\n' "$PRODUCT_LABEL"
printf 'Target: macOS / POSIX sh\n'
printf 'Tool version: %s\n' "$TOOL_VERSION"
if [ "$QUALITY_MODE" -eq 1 ]; then
  printf 'Mode: Extended quality, latency, MTU, and stability analysis\n'
else
  printf 'Mode: Standard reachability pre-flight (run with --quality for extended tests)\n'
fi
printf 'Started: %s\n' "$(date 2>/dev/null || echo unknown)"
printf 'Computer: %s | %s | %s\n' "$(hostname 2>/dev/null || echo unknown)" "$(uname -s 2>/dev/null)" "$(uname -m 2>/dev/null)"
printf 'Log file: %s\n' "${IRIDI_CLOUD_LOG_FILE:-not set}"
printf 'Method: DNS + real HTTP(S) GET + response and payload analysis + Cloud Gate TCP\n'
printf 'Note: TLS certificate validation is intentionally bypassed for reachability diagnostics.\n'

# Execute checks for selected product
case "$PRODUCT" in
  i3knx)
    probe_resource www "Website and downloads" "https://www.iridi.com/" "89.169.183.139" yes
    probe_resource auth-eu "Authorization EU" "https://auth.eu.iridi.com/" "95.216.162.71" yes
    probe_resource proxy-auth-eu "Authorization proxy EU" "https://proxy.auth.eu.iridi.com/" "72.56.78.171" yes
    probe_resource proxy-auth-cloud "Authorization proxy Cloud" "https://proxy.auth.eu.iridi.cloud/" "94.131.83.102" yes
    probe_resource i3knx-eu "i3 KNX cloud EU" "https://i3knx.eu.iridi.com/" "95.216.162.71" yes
    probe_resource proxy-i3knx-eu "i3 KNX proxy EU" "https://proxy.i3knx.eu.iridi.com/" "147.45.238.146" yes
    probe_resource proxy-knx-cloud "KNX proxy Cloud" "https://proxy.knx.eu.iridi.cloud/" "94.131.87.121" yes
    probe_resource proxy-s3-eu "Storage proxy EU" "https://proxy.s3.eu.iridi.com/" "72.56.68.146" yes
    probe_resource ping "Control endpoint" "https://ping.iridiummobile.net/" "52.222.136.36" yes
    probe_resource s3-eu "Project storage EU" "https://s3.eu.iridi.com/" "95.217.164.135" yes
    ;;
  bus77-home)
    probe_resource www "Website and downloads" "https://www.iridi.com/" "89.169.183.139" yes
    probe_resource auth-ru "Authorization RU" "https://auth.ru.iridi.com/" "84.201.152.245" yes
    probe_resource endpoint "Cloud endpoint" "https://endpoint.iridi.com/" "95.181.182.182" yes
    probe_resource bus77-home "Bus77 Home cloud" "https://bus77home.ru.iridi.com/" "84.201.152.245" yes
    probe_resource iphub-home "IP-Hub Home cloud" "https://iphubhome.ru.iridi.com/" "37.139.42.137" yes
    probe_resource commercial "Commercial offers API" "https://api.commercial-offer.iridi.com/" "213.219.212.191" yes
    probe_resource voice-cws "Voice assistants (CWS)" "https://cws.iridi.com:7972/" "185.32.84.60" no
    ;;
  bus77-lite)
    probe_resource www "Website and downloads" "https://www.iridi.com/" "89.169.183.139" yes
    probe_resource auth-ru "Authorization RU" "https://auth.ru.iridi.com/" "84.201.152.245" yes
    probe_resource endpoint "Cloud endpoint" "https://endpoint.iridi.com/" "95.181.182.182" yes
    probe_resource bus77-lite "Bus77 Lite cloud" "https://bus77lite.ru.iridi.com/" "84.201.152.245" yes
    probe_resource iphub-lite "IP-Hub Lite cloud" "https://iphub.ru.iridi.com/" "51.250.30.171" yes
    probe_resource commercial "Commercial offers API" "https://api.commercial-offer.iridi.com/" "213.219.212.191" yes
    probe_resource voice-cws "Voice assistants (CWS)" "https://cws.iridi.com:7972/" "185.32.84.60" no
    ;;
  iridi-pro)
    case "$REGION" in
      EU)
        probe_resource auth-eu "Authorization EU" "https://auth.eu.iridi.com/" "95.216.162.71" yes
        probe_resource i3pro-eu "i3 Pro cloud EU" "https://i3pro.eu.iridi.com/" "95.216.162.71" yes
        probe_resource storage-eu "AWS storage EU" "https://s3.us-east-1.amazonaws.com/" "dynamic" yes
        probe_resource projects-eu "i3 Pro projects EU" "https://iridium-cloud-files.s3.amazonaws.com/" "dynamic" yes
        probe_resource updates-site "Update service" "http://iridi.com/" "89.169.183.139" no
        probe_resource updates-s3 "Update files" "http://iridium3download.s3.amazonaws.com/" "dynamic" no
        ;;
      RU)
        probe_resource auth-ru "Authorization RU" "https://auth.ru.iridi.com/" "84.201.152.245" yes
        probe_resource i3pro-ru "i3 Pro cloud RU" "https://i3pro.ru.iridi.com/" "84.201.152.245" yes
        probe_resource storage-ru "RU storage" "https://storage.yandexcloud.net/" "213.180.193.243" yes
        probe_resource projects-ru "i3 Pro projects RU" "https://i3pro.storage.yandexcloud.net/" "213.180.193.243" yes
        probe_resource updates-site "Update service" "http://iridi.com/" "89.169.183.139" no
        probe_resource updates-s3 "Update files" "http://iridium3download.s3.amazonaws.com/" "dynamic" no
        ;;
      CN)
        probe_resource auth-cn "Authorization CN" "https://auth.eu.iridi.com/" "95.216.162.71" yes
        probe_resource i3pro-cn "i3 Pro cloud CN" "https://i3pro.eu.iridi.com/" "95.216.162.71" yes
        probe_resource storage-cn "CN object storage" "https://ir-endpoint.oss-cn-shanghai.aliyuncs.com/" "106.14.228.182" yes
        probe_resource projects-cn "i3 Pro projects CN" "https://ir-proj-sh.oss-cn-shanghai.aliyuncs.com/" "106.14.228.182" yes
        probe_resource updates-site "Update service" "http://iridi.com/" "89.169.183.139" no
        probe_resource updates-cn "CN update files" "http://iridium3download.oss-cn-hangzhou.aliyuncs.com/" "118.178.60.104" no
        ;;
    esac
    ;;
esac

check_gate

if [ "$QUALITY_MODE" -eq 1 ]; then
  separator
  printf 'EXTENDED QUALITY & STABILITY ANALYSIS\n'
  run_quality_latency "$QUALITY_LATENCY_URL" "$QUALITY_LATENCY_LABEL"
  run_quality_throughput "$QUALITY_THROUGHPUT_URL" "$QUALITY_THROUGHPUT_LABEL"
  run_quality_gate "$GATE_HOSTS"
  run_quality_mtu "$QUALITY_MTU_HOST"
fi

separator
printf 'SUMMARY\n'
printf '  Profile: %s\n' "$PRODUCT_LABEL"
printf '  Mode: %s\n' "$( [ "$QUALITY_MODE" -eq 1 ] && echo "extended quality & stability" || echo "standard reachability" )"
printf '  HTTP resources: %s of %s available, %s failed\n' "$HTTP_OK" "$HTTP_TOTAL" "$HTTP_FAIL"
printf '  Cloud Gate: %s\n' "$GATE_STATUS"
printf '  Warnings: %s\n' "$WARN_COUNT"

if [ "$HTTP_FAIL" -gt 0 ] || [ "${GATE_FAILED:-0}" -eq 1 ]; then
  printf '  Conclusion: one or more required cloud resources are unavailable.\n'
elif [ "$WARN_COUNT" -gt 0 ]; then
  printf '  Conclusion: required cloud resources are available, but some items require attention.\n'
else
  printf '  Conclusion: required cloud resources are available with no warnings.\n'
fi

separator
printf 'SUMMARY %s: checked %s, available %s, failed %s, warnings %s\n' "$PRODUCT_LABEL" "$HTTP_TOTAL" "$HTTP_OK" "$HTTP_FAIL" "$WARN_COUNT"

if [ "$HTTP_FAIL" -gt 0 ] || [ "${GATE_FAILED:-0}" -eq 1 ]; then
  printf 'RESULT: FAIL - NOT OK: one or more required cloud resources are unavailable.\n'
  exit 2
fi

if [ "$WARN_COUNT" -gt 0 ]; then
  printf 'RESULT: WARN - ATTENTION REQUIRED: required services are reachable, but warnings were found.\n'
  exit 1
fi

printf 'RESULT: PASS - OK: required cloud resources and Cloud Gate are reachable.\n'
if [ "$QUALITY_MODE" -eq 0 ]; then
  printf '\nTip: For deeper channel quality, latency, MTU, and throughput tests, re-run with: sh %s --quality\n' "$0"
fi
exit 0
