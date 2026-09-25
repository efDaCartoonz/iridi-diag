#!/bin/sh

# iRidi Server Health & System Overview
# Comprehensive hardware identity, firmware version, runtime status,
# thermal indicators, eMMC wear level (SMART), memory, storage, and network health.
#
# Usage: sh check_server_health.sh

case "${1:-}" in
  -h|--help)
    printf 'Usage: sh %s [options]\n\n' "${0##*/}"
    printf 'Options:\n'
    printf '  -h, --help    Show this help message and exit\n\n'
    printf 'Description:\n'
    printf '  Collects and reports comprehensive hardware identity, server firmware version,\n'
    printf '  runtime status, thermal indicators, eMMC wear level (SMART), memory, storage,\n'
    printf '  and network health for iRidi HSS, ProAV, UMC, and KNX Linux controllers.\n'
    exit 0
    ;;
esac

TOOL_VERSION="1.1"

# Setup logging directory & technical log file
CURRENT_DIR="$(pwd 2>/dev/null || printf '.')"
LOG_DIR="${IRIDI_DIAG_LOG_DIR:-$CURRENT_DIR}"
if [ ! -d "$LOG_DIR" ] || [ ! -w "$LOG_DIR" ]; then
  LOG_DIR="${TMPDIR:-/tmp}"
fi

DEVICE_NAME="$(cat /sys/firmware/devicetree/base/serial-number 2>/dev/null | tr -d '\0')"
if [ -z "$DEVICE_NAME" ]; then
  DEVICE_NAME="$(awk -F': *' '/Controller serial/{print $2}' /oem/hal/ccinfo 2>/dev/null | tr -d ' \r\t\n')"
fi
if [ -z "$DEVICE_NAME" ]; then
  DEVICE_NAME="$(uname -n 2>/dev/null | tr -cs 'A-Za-z0-9._-' '_')"
fi
DEVICE_NAME="${DEVICE_NAME:-server}"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S' 2>/dev/null || printf '00000000_000000')"
LOG_FILE="${LOG_DIR}/server_health_${DEVICE_NAME}_${TIMESTAMP}_$$.log"

# Open File Descriptor 3 for technical log
if ! exec 3>>"$LOG_FILE" 2>/dev/null; then
  LOG_FILE="${TMPDIR:-/tmp}/server_health_${DEVICE_NAME}_${TIMESTAMP}_$$.log"
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
WARN_COUNT=0
FAIL_COUNT=0

cleanup() {
  exec 3>&- 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

# Technical Log Initial Header
log_tech "================================================================================"
log_tech "iRidi Server Health & System Diagnostic - Technical Log"
log_tech "Version: $TOOL_VERSION | Started: $STARTED_AT"
log_tech "Host: $HOSTNAME_VAL | Kernel: $(uname -srm 2>/dev/null)"
log_tech "Log File: $LOG_FILE"
log_tech "================================================================================"

# Log base system files
log_tech_file "OEM CCINFO (/oem/hal/ccinfo)" "/oem/hal/ccinfo"
log_tech_file "CPUINFO (/proc/cpuinfo)" "/proc/cpuinfo"
log_tech_file "MEMINFO (/proc/meminfo)" "/proc/meminfo"
log_tech_file "UPTIME (/proc/uptime)" "/proc/uptime"
log_tech_file "LOADAVG (/proc/loadavg)" "/proc/loadavg"

# Screen Header
printf '%s================================================================%s\n' "$C_CYAN" "$C_RESET"
printf '  %siRidi Server Health & System Overview%s (v%s)\n' "$C_BOLD" "$C_RESET" "$TOOL_VERSION"
printf '%s================================================================%s\n' "$C_CYAN" "$C_RESET"
printf 'Started: %s | Host: %s | Kernel: %s\n\n' "$STARTED_AT" "$HOSTNAME_VAL" "$(uname -srm 2>/dev/null || printf 'Linux')"

# --- SECTION 1: Hardware & System Identification ---
check_hardware_identity() {
  printf '%s1. Hardware & System Identity:%s\n' "$C_BOLD" "$C_RESET"

  MODEL=""
  SERIAL=""
  CPU_SERIAL=""
  SW_VERSION=""

  if [ -r /oem/hal/ccinfo ]; then
    SERIAL="$(awk -F': *' '/Controller serial/{print $2}' /oem/hal/ccinfo | sed 's/^[ \t]*//;s/[ \t]*$//')"
    CPU_SERIAL="$(awk -F': *' '/Processor serial/{print $2}' /oem/hal/ccinfo | sed 's/^[ \t]*//;s/[ \t]*$//')"
    MODEL="$(awk -F': *' '/Hardware version/{print $2}' /oem/hal/ccinfo | sed 's/^[ \t]*//;s/[ \t]*$//')"
    SW_VERSION="$(awk -F': *' '/Software version/{print $2}' /oem/hal/ccinfo | sed 's/^[ \t]*//;s/[ \t]*$//')"
  fi

  if [ -z "$MODEL" ] && [ -r /sys/firmware/devicetree/base/model ]; then
    MODEL="$(tr -d '\0' </sys/firmware/devicetree/base/model | sed 's/^[ \t]*//;s/[ \t]*$//')"
  fi
  if [ -z "$SERIAL" ] && [ -r /sys/firmware/devicetree/base/serial-number ]; then
    SERIAL="$(tr -d '\0' </sys/firmware/devicetree/base/serial-number | sed 's/^[ \t]*//;s/[ \t]*$//')"
  fi
  if [ -z "$CPU_SERIAL" ] && [ -r /proc/cpuinfo ]; then
    CPU_SERIAL="$(awk '/Serial/{print $3}' /proc/cpuinfo | head -n 1)"
  fi
  if [ -z "$SW_VERSION" ] && [ -r /usr/lib/os-release ]; then
    SW_VERSION="$(awk -F'=' '/PRETTY_NAME/{gsub(/"/, ""); print $2}' /usr/lib/os-release)"
  fi
  if [ -z "$SW_VERSION" ] && [ -r /etc/os-release ]; then
    SW_VERSION="$(awk -F'=' '/PRETTY_NAME/{gsub(/"/, ""); print $2}' /etc/os-release)"
  fi

  UPTIME_FMT="n/a"
  if [ -r /proc/uptime ]; then
    UPTIME_SECS="$(cut -d' ' -f1 /proc/uptime | cut -d'.' -f1)"
    DAYS=$((UPTIME_SECS / 86400))
    HOURS=$(((UPTIME_SECS % 86400) / 3600))
    MINS=$(((UPTIME_SECS % 3600) / 60))
    if [ "$DAYS" -gt 0 ]; then
      UPTIME_FMT="${DAYS}d ${HOURS}h ${MINS}m"
    elif [ "$HOURS" -gt 0 ]; then
      UPTIME_FMT="${HOURS}h ${MINS}m"
    else
      UPTIME_FMT="${MINS}m"
    fi
  fi

  LOAD_FMT="n/a"
  if [ -r /proc/loadavg ]; then
    LOAD_1="$(cut -d' ' -f1 /proc/loadavg)"
    LOAD_5="$(cut -d' ' -f2 /proc/loadavg)"
    LOAD_15="$(cut -d' ' -f3 /proc/loadavg)"
    LOAD_FMT="$LOAD_1, $LOAD_5, $LOAD_15"
  fi

  printf '  • Model:        %-24s Serial: %s\n' "${MODEL:-Unknown Model}" "${SERIAL:-n/a}"
  printf '  • Base OS:      %-24s Uptime: %s (Load: %s)\n' "${SW_VERSION:-Linux}" "$UPTIME_FMT" "$LOAD_FMT"
  log_tech "IDENTITY: model=$MODEL serial=$SERIAL cpu_serial=$CPU_SERIAL os=$SW_VERSION uptime=$UPTIME_FMT load=$LOAD_FMT"
}

# --- SECTION 2: iRidi Server Runtime & Firmware ---
check_iridi_runtime() {
  printf '\n%s2. iRidi Server Runtime & Services:%s\n' "$C_BOLD" "$C_RESET"

  PACKAGE_VER=""
  PACKAGE_TIME=""
  if command -v opkg >/dev/null 2>&1; then
    PACKAGE_VER="$(opkg status iridiumserver 2>/dev/null | awk -F': *' '/Version:/{print $2}')"
    PACKAGE_TIME="$(opkg status iridiumserver 2>/dev/null | awk -F': *' '/Installed-Time:/{print $2}')"
  fi
  if [ -z "$PACKAGE_VER" ] && [ -r /var/lib/opkg/info/iridiumserver.control ]; then
    PACKAGE_VER="$(awk -F': *' '/Version:/{print $2}' /var/lib/opkg/info/iridiumserver.control)"
  fi

  FLAVOR="iRidi Server"
  BIN_PATH="/iridiumserver/iridium"
  if [ -f "$BIN_PATH" ]; then
    if strings "$BIN_PATH" 2>/dev/null | grep -q "Bus77 Home"; then
      FLAVOR="Bus77 Home Server"
    elif strings "$BIN_PATH" 2>/dev/null | grep -q "Bus77 Lite"; then
      FLAVOR="Bus77 Lite Server"
    elif strings "$BIN_PATH" 2>/dev/null | grep -q "ProAV Control Processor"; then
      FLAVOR="iRidi ProAV Server"
    elif strings "$BIN_PATH" 2>/dev/null | grep -q "KnxGatewayPort"; then
      FLAVOR="iRidi KNX / Pro Server"
    fi
  fi

  IRIDIUM_PID="$(pidof iridium 2>/dev/null | awk '{print $1}')"
  if [ -n "$IRIDIUM_PID" ]; then
    MEM_RSS="$(awk '/VmRSS/{print $2,$3}' "/proc/$IRIDIUM_PID/status" 2>/dev/null || printf 'n/a')"
    THREADS="$(awk '/Threads/{print $2}' "/proc/$IRIDIUM_PID/status" 2>/dev/null || printf 'n/a')"
    printf '  %s[OK]%s        %s (v%s) — RUNNING (PID %s, RAM: %s, %s threads)\n' \
      "$C_GREEN" "$C_RESET" "$FLAVOR" "${PACKAGE_VER:-unknown}" "$IRIDIUM_PID" "$MEM_RSS" "$THREADS"
    log_tech "RUNTIME: status=RUNNING flavor=$FLAVOR ver=$PACKAGE_VER pid=$IRIDIUM_PID rss=$MEM_RSS threads=$THREADS"
  else
    printf '  %s[NOT OK]%s    %s — NOT RUNNING (Process stopped or failed!)\n' "$C_RED" "$C_RESET" "$FLAVOR"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log_tech "RUNTIME: status=STOPPED flavor=$FLAVOR ver=$PACKAGE_VER"
  fi

  # Log socket connections
  NETSTAT_OUT="$(ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null)"
  log_tech_cmd "OPEN PORTS (ss/netstat)" ss -tulpn
  
  OPEN_PORTS=""
  for PORT in 8888 8443 30464 30465 30467 65534 8883 2812 22; do
    if printf '%s\n' "$NETSTAT_OUT" | grep -q ":${PORT} "; then
      OPEN_PORTS="${OPEN_PORTS:+$OPEN_PORTS, }$PORT"
    fi
  done
  [ -n "$OPEN_PORTS" ] && printf '  • Active Listening Ports: %s\n' "$OPEN_PORTS"
}

# --- SECTION 3: CPU & Thermal Health ---
check_thermal_and_cpu() {
  printf '\n%s3. CPU & Thermal Health:%s\n' "$C_BOLD" "$C_RESET"

  THERMAL_FOUND=0
  MAX_TEMP=0
  for TZ_DIR in /sys/class/thermal/thermal_zone*; do
    if [ -d "$TZ_DIR" ]; then
      THERMAL_FOUND=1
      TZ_TYPE="$(cat "$TZ_DIR/type" 2>/dev/null || printf 'zone')"
      TZ_RAW="$(cat "$TZ_DIR/temp" 2>/dev/null || printf '0')"
      TZ_C=$(( TZ_RAW / 1000 ))
      log_tech "THERMAL: zone=$TZ_DIR type=$TZ_TYPE temp=${TZ_C}C"
      [ "$TZ_C" -gt "$MAX_TEMP" ] && MAX_TEMP="$TZ_C"
    fi
  done

  if [ "$THERMAL_FOUND" -eq 1 ]; then
    if [ "$MAX_TEMP" -lt 75 ]; then
      printf '  %s[OK]%s        CPU / SoC Temperature: %d°C (Normal)\n' "$C_GREEN" "$C_RESET" "$MAX_TEMP"
    elif [ "$MAX_TEMP" -lt 85 ]; then
      printf '  %s[ATTENTION]%s CPU / SoC Temperature: %d°C (Elevated temperature)\n' "$C_YELLOW" "$C_RESET" "$MAX_TEMP"
      WARN_COUNT=$((WARN_COUNT + 1))
    else
      printf '  %s[NOT OK]%s    CPU / SoC Temperature: %d°C (CRITICAL OVERHEATING)\n' "$C_RED" "$C_RESET" "$MAX_TEMP"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  else
    printf '  %s[INFO]%s      No hardware thermal sensors exposed under /sys/class/thermal\n' "$C_GRAY" "$C_RESET"
  fi

  CPU_CORES="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || printf '1')"
  CPU_FREQ_RAW="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq 2>/dev/null)"
  if [ -n "$CPU_FREQ_RAW" ] && [ "$CPU_FREQ_RAW" -gt 0 ] 2>/dev/null; then
    CPU_MHZ=$(( CPU_FREQ_RAW / 1000 ))
    printf '  • CPU Topology: %s cores @ %d MHz\n' "$CPU_CORES" "$CPU_MHZ"
  else
    printf '  • CPU Topology: %s cores\n' "$CPU_CORES"
  fi
}

# --- SECTION 4: Memory (RAM) Health ---
check_memory_health() {
  printf '\n%s4. Memory (RAM) Utilization:%s\n' "$C_BOLD" "$C_RESET"

  if [ -r /proc/meminfo ]; then
    MEM_TOTAL_KB="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
    MEM_FREE_KB="$(awk '/MemFree/{print $2}' /proc/meminfo)"
    MEM_AVAIL_KB="$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
    MEM_AVAIL_KB="${MEM_AVAIL_KB:-$MEM_FREE_KB}"
    
    MEM_TOTAL_MB=$(( MEM_TOTAL_KB / 1024 ))
    MEM_AVAIL_MB=$(( MEM_AVAIL_KB / 1024 ))
    MEM_USED_MB=$(( MEM_TOTAL_MB - MEM_AVAIL_MB ))

    MEM_PERCENT=0
    [ "$MEM_TOTAL_MB" -gt 0 ] && MEM_PERCENT=$(( (MEM_USED_MB * 100) / MEM_TOTAL_MB ))

    log_tech "MEMORY: total=${MEM_TOTAL_MB}MB used=${MEM_USED_MB}MB (${MEM_PERCENT}%) avail=${MEM_AVAIL_MB}MB"

    if [ "$MEM_PERCENT" -lt 85 ]; then
      printf '  %s[OK]%s        Memory Usage: %s MB / %s MB used (%d%%)\n' "$C_GREEN" "$C_RESET" "$MEM_USED_MB" "$MEM_TOTAL_MB" "$MEM_PERCENT"
    elif [ "$MEM_PERCENT" -lt 95 ]; then
      printf '  %s[ATTENTION]%s Memory Usage: %s MB / %s MB used (%d%%) — High memory load\n' "$C_YELLOW" "$C_RESET" "$MEM_USED_MB" "$MEM_TOTAL_MB" "$MEM_PERCENT"
      WARN_COUNT=$((WARN_COUNT + 1))
    else
      printf '  %s[NOT OK]%s    Memory Usage: %s MB / %s MB used (%d%%) — Exhaustion risk (only %s MB free)\n' "$C_RED" "$C_RESET" "$MEM_USED_MB" "$MEM_TOTAL_MB" "$MEM_PERCENT" "$MEM_AVAIL_MB"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  fi
}

# --- SECTION 5: Storage & eMMC Wear Indicators (SMART) ---
check_emmc_and_storage() {
  printf '\n%s5. Storage & eMMC Wear Indicators (SMART):%s\n' "$C_BOLD" "$C_RESET"

  MMC_DEV=""
  for CANDIDATE in /sys/class/mmc_host/mmc1/mmc1:0001 /sys/class/mmc_host/mmc0/mmc0:0001 /sys/block/mmcblk0/device /sys/block/mmcblk1/device; do
    if [ -d "$CANDIDATE" ]; then
      MMC_DEV="$CANDIDATE"
      break
    fi
  done

  if [ -n "$MMC_DEV" ]; then
    MMC_NAME="$(cat "$MMC_DEV/name" 2>/dev/null)"
    MMC_MANFID="$(cat "$MMC_DEV/manfid" 2>/dev/null)"
    MMC_LIFE="$(cat "$MMC_DEV/life_time" 2>/dev/null)"
    MMC_PRE_EOL="$(cat "$MMC_DEV/pre_eol_info" 2>/dev/null)"

    MANUFACTURER_STR="Unknown"
    case "$MMC_MANFID" in
      0x000015|0x15) MANUFACTURER_STR="Samsung" ;;
      0x000013|0x13) MANUFACTURER_STR="Micron" ;;
      0x000045|0x45) MANUFACTURER_STR="SanDisk" ;;
      0x000090|0x90) MANUFACTURER_STR="SK Hynix" ;;
      0x0000fe|0xfe) MANUFACTURER_STR="Micron" ;;
    esac

    LIFE_A="$(printf '%s' "$MMC_LIFE" | awk '{print $1}')"
    LIFE_B="$(printf '%s' "$MMC_LIFE" | awk '{print $2}')"
    
    decode_life() {
      case "$1" in
        0x01|0x1|1) echo "0-10% used" ;;
        0x02|0x2|2) echo "10-20% used" ;;
        0x03|0x3|3) echo "20-30% used" ;;
        0x04|0x4|4) echo "30-40% used" ;;
        0x05|0x5|5) echo "40-50% used" ;;
        0x06|0x6|6) echo "50-60% used" ;;
        0x07|0x7|7) echo "60-70% used" ;;
        0x08|0x8|8) echo "70-80% used" ;;
        0x09|0x9|9) echo "80-90% used" ;;
        0x0a|0xa|10) echo "90-100% used" ;;
        0x0b|0xb|11) echo "exceeded life" ;;
        *) echo "n/a" ;;
      esac
    }

    log_tech "EMMC: dev=$MMC_DEV name=$MMC_NAME manfid=$MMC_MANFID ($MANUFACTURER_STR) life_raw='$MMC_LIFE' pre_eol=$MMC_PRE_EOL"

    if [ "$LIFE_A" = "0x0a" ] || [ "$LIFE_A" = "0x0b" ] || [ "$LIFE_B" = "0x0a" ] || [ "$LIFE_B" = "0x0b" ] || [ "$MMC_PRE_EOL" = "0x03" ]; then
      printf '  %s[NOT OK]%s    eMMC Flash: %s (%s) — CRITICAL WEAR: Life A: %s, Life B: %s\n' \
        "$C_RED" "$C_RESET" "${MMC_NAME:-eMMC}" "$MANUFACTURER_STR" "$(decode_life "$LIFE_A")" "$(decode_life "$LIFE_B")"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    elif [ "$MMC_PRE_EOL" = "0x02" ] || [ "$LIFE_A" = "0x09" ] || [ "$LIFE_B" = "0x09" ]; then
      printf '  %s[ATTENTION]%s eMMC Flash: %s (%s) — ELEVATED WEAR: Life A: %s, Life B: %s\n' \
        "$C_YELLOW" "$C_RESET" "${MMC_NAME:-eMMC}" "$MANUFACTURER_STR" "$(decode_life "$LIFE_A")" "$(decode_life "$LIFE_B")"
      WARN_COUNT=$((WARN_COUNT + 1))
    else
      printf '  %s[OK]%s        eMMC Flash: %s (%s) — Wear: %s (Health: Normal)\n' \
        "$C_GREEN" "$C_RESET" "${MMC_NAME:-eMMC}" "$MANUFACTURER_STR" "$(decode_life "$LIFE_A")"
    fi
  else
    printf '  %s[INFO]%s      eMMC sysfs node not directly accessible\n' "$C_GRAY" "$C_RESET"
  fi

  # Partition Space
  DF_OUT="$(df -h / /userdata /oem 2>/dev/null)"
  log_tech_cmd "DISK USAGE (df -h)" df -h
  printf '  • Storage Partitions:\n'
  printf '%s\n' "$DF_OUT" | awk 'NR>1 { printf "    - %-14s: %6s total, %6s free (%4s used)\n", $6, $2, $4, $5 }'

  # Kernel error scan
  ERR_COUNT=0
  if command -v dmesg >/dev/null 2>&1; then
    ERR_COUNT="$(dmesg 2>/dev/null | grep -ciE '(Buffer I/O error|EXT4-fs error|blk_update_request: I/O error|mmc.*error|end_request: I/O error)' || true)"
    log_tech_cmd "STORAGE KERNEL LOG SCAN" sh -c "dmesg | grep -iE '(Buffer I/O error|EXT4-fs error|blk_update_request: I/O error|mmc.*error|end_request: I/O error)'"
  fi
  if [ "$ERR_COUNT" -eq 0 ]; then
    printf '  %s[OK]%s        Kernel Storage Ring Buffer: Clean (0 filesystem / I/O errors)\n' "$C_GREEN" "$C_RESET"
  else
    printf '  %s[ATTENTION]%s Kernel Storage Ring Buffer: %d filesystem/storage error events detected!\n' "$C_YELLOW" "$C_RESET" "$ERR_COUNT"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
}

# --- SECTION 6: Network & CAN Bus Status ---
check_network_and_can() {
  printf '\n%s6. Network & Communication Interfaces:%s\n' "$C_BOLD" "$C_RESET"

  # Ethernet (eth0)
  if [ -d /sys/class/net/eth0 ]; then
    ETH_IP="$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}' | head -n 1)"
    ETH_OPER="$(cat /sys/class/net/eth0/operstate 2>/dev/null)"
    ETH_SPEED="$(cat /sys/class/net/eth0/speed 2>/dev/null || printf 'n/a')"
    
    log_tech "NET eth0: oper=$ETH_OPER ip=$ETH_IP speed=$ETH_SPEED"

    if [ "$ETH_OPER" = "up" ]; then
      printf '  %s[OK]%s        eth0: Link UP (%s Mbps) | IP: %s\n' "$C_GREEN" "$C_RESET" "${ETH_SPEED:-1000}" "${ETH_IP:-no IPv4}"
    else
      printf '  %s[ATTENTION]%s eth0: Link is %s\n' "$C_YELLOW" "$C_RESET" "${ETH_OPER:-DOWN}"
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
  fi

  # CAN Bus (can0)
  if [ -d /sys/class/net/can0 ]; then
    CAN_STATE="UNKNOWN"
    CAN_BITRATE="125000"
    if command -v ip >/dev/null 2>&1; then
      CAN_DETAIL="$(ip -details link show can0 2>/dev/null)"
      CAN_STATE="$(echo "$CAN_DETAIL" | awk '/can .* state/ {for(i=1;i<=NF;i++) if($i=="state") print $(i+1)}' | head -n 1)"
      CAN_BITRATE="$(echo "$CAN_DETAIL" | awk '/bitrate/ {for(i=1;i<=NF;i++) if($i=="bitrate") print $(i+1)}' | head -n 1)"
      log_tech_file "CAN0 DETAILS (ip -details link show can0)" "$CAN_DETAIL"
    fi
    CAN_STATE="${CAN_STATE:-UP}"
    log_tech "CAN can0: state=$CAN_STATE bitrate=$CAN_BITRATE"

    if [ "$CAN_STATE" = "ERROR-ACTIVE" ] || [ "$CAN_STATE" = "UP" ]; then
      printf '  %s[OK]%s        can0: State %s | Bitrate: %s bit/s (Bus connected)\n' "$C_GREEN" "$C_RESET" "$CAN_STATE" "${CAN_BITRATE:-125000}"
    elif [ "$CAN_STATE" = "ERROR-PASSIVE" ]; then
      printf '  %s[INFO]%s      can0: State ERROR-PASSIVE | %s bit/s (Normal if no modules connected)\n' "$C_GRAY" "$C_RESET" "${CAN_BITRATE:-125000}"
    elif [ "$CAN_STATE" = "BUS-OFF" ]; then
      printf '  %s[ATTENTION]%s can0: State BUS-OFF (Bus failure / heavy collision detected)\n' "$C_YELLOW" "$C_RESET"
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
  else
    printf '  • can0: not present (controller has no hardware CAN bus)\n'
  fi

  # Default Gateway & DNS
  DEF_GW="$(ip route show default 2>/dev/null | awk '/default via/{print $3}' | head -n 1)"
  DNS_SERVERS="$(awk '/nameserver/{printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)"
  printf '  • Default Gateway: %-18s DNS: %s\n' "${DEF_GW:-n/a}" "${DNS_SERVERS:-n/a}"
  log_tech "NET CONFIG: gateway=$DEF_GW dns='$DNS_SERVERS'"
}

# --- SECTION 7: Summary & Verdict ---
print_summary() {
  printf '\n%s================================================================%s\n' "$C_CYAN" "$C_RESET"
  printf '  %sSYSTEM HEALTH SUMMARY%s\n' "$C_BOLD" "$C_RESET"
  printf '%s================================================================%s\n' "$C_CYAN" "$C_RESET"
  printf 'Failures:        %d\n' "$FAIL_COUNT"
  printf 'Attention items: %d\n' "$WARN_COUNT"

  log_tech "SUMMARY: failures=$FAIL_COUNT warnings=$WARN_COUNT"

  if [ "$FAIL_COUNT" -gt 0 ]; then
    printf '\n%sRESULT: FAIL — Critical hardware or service issues detected (%d failures, %d warnings)%s\n' "$C_RED" "$FAIL_COUNT" "$WARN_COUNT" "$C_RESET"
    printf 'Detailed technical log: %s\n\n' "$LOG_FILE"
    log_tech "RESULT: FAIL"
    exit 2
  elif [ "$WARN_COUNT" -gt 0 ]; then
    printf '\n%sRESULT: WARN — System is operational, but %d item(s) require attention%s\n' "$C_YELLOW" "$WARN_COUNT" "$C_RESET"
    printf 'Detailed technical log: %s\n\n' "$LOG_FILE"
    log_tech "RESULT: WARN"
    exit 1
  else
    printf '\n%sRESULT: PASS — All hardware and system components are healthy (0 failures, 0 warnings)%s\n' "$C_GREEN" "$C_RESET"
    printf 'Detailed technical log: %s\n\n' "$LOG_FILE"
    log_tech "RESULT: PASS"
    exit 0
  fi
}

check_hardware_identity
check_iridi_runtime
check_thermal_and_cpu
check_memory_health
check_emmc_and_storage
check_network_and_can
print_summary
