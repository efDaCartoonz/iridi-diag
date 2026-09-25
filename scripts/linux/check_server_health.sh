#!/bin/sh

case "${1:-}" in
  -h|--help)
    printf 'Usage: sh %s [options]\n' "${0##*/}"
    printf '\n'
    printf 'Options:\n'
    printf '  -h, --help    Show this help message and exit\n'
    printf '\n'
    printf 'Description:\n'
    printf '  Collects and reports comprehensive hardware identity, server firmware version,\n'
    printf '  runtime status, thermal indicators, eMMC wear level (SMART), memory, storage,\n'
    printf '  and network health for iRidi HSS, ProAV, UMC, and KNX Linux controllers.\n'
    exit 0
    ;;
esac

# Auto-logging wrapper (POSIX sh compatible)
if [ "${IRIDI_SERVER_HEALTH_LOG_ACTIVE:-0}" != "1" ]; then
  CURRENT_DIRECTORY="$(pwd 2>/dev/null || printf '.')"
  LOG_DIRECTORY="${IRIDI_DIAG_LOG_DIR:-$CURRENT_DIRECTORY}"
  if [ ! -d "$LOG_DIRECTORY" ] || [ ! -w "$LOG_DIRECTORY" ]; then
    LOG_DIRECTORY="/tmp"
  fi

  DEVICE_NAME="$(cat /sys/firmware/devicetree/base/serial-number 2>/dev/null | tr -d '\0')"
  if [ -z "$DEVICE_NAME" ]; then
    DEVICE_NAME="$(awk -F': *' '/Controller serial/{print $2}' /oem/hal/ccinfo 2>/dev/null | tr -d ' \r\t\n')"
  fi
  if [ -z "$DEVICE_NAME" ]; then
    DEVICE_NAME="$(uname -n 2>/dev/null | tr -cs 'A-Za-z0-9._-' '_')"
  fi
  DEVICE_NAME="${DEVICE_NAME:-unknown_device}"

  TIMESTAMP="$(date '+%Y%m%d_%H%M%S' 2>/dev/null || printf '00000000_000000')"
  LOG_FILE="${LOG_DIRECTORY}/server_health_${DEVICE_NAME}_${TIMESTAMP}_$$.log"

  export IRIDI_SERVER_HEALTH_LOG_ACTIVE=1
  export IRIDI_SERVER_HEALTH_LOG_FILE="$LOG_FILE"

  # Run diagnostic and stream through tee while stripping ANSI codes from log file
  sh "$0" "$@" 2>&1 | tee "$LOG_FILE.raw"
  SCRIPT_EXIT="${PIPESTATUS:-$?}"

  # Strip ANSI color codes from the permanent log file
  sed -e 's/\x1b\[[0-9;]*[mK]//g' "$LOG_FILE.raw" > "$LOG_FILE" 2>/dev/null
  rm -f "$LOG_FILE.raw" 2>/dev/null

  printf '\nLog saved: %s\n' "$LOG_FILE"

  if [ "$SCRIPT_EXIT" -ne 0 ]; then
    exit "$SCRIPT_EXIT"
  fi

  # Determine exit code from result
  if grep -E 'RESULT: FAIL' "$LOG_FILE" >/dev/null 2>&1; then
    exit 2
  fi
  if grep -E 'RESULT: WARN' "$LOG_FILE" >/dev/null 2>&1; then
    exit 1
  fi
  exit 0
fi

# Color formatting if connected to a terminal
if [ -t 1 ] && [ "${NO_COLOR:-0}" = "0" ]; then
  C_RESET="$(printf '\033[0m')"
  C_BOLD="$(printf '\033[1m')"
  C_GREEN="$(printf '\033[32m')"
  C_YELLOW="$(printf '\033[33m')"
  C_RED="$(printf '\033[31m')"
  C_CYAN="$(printf '\033[36m')"
else
  C_RESET=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi

TOOL_VERSION="1.0"
STARTED_AT="$(date 2>/dev/null || printf 'unknown')"
HOSTNAME_VAL="$(uname -n 2>/dev/null || printf 'unknown')"

WARN_COUNT=0
FAIL_COUNT=0

separator() {
  printf '%s\n' '----------------------------------------------------------------'
}

print_header() {
  printf '%s%siRidi Server Health & System Overview%s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
  printf 'Script version: %s\n' "$TOOL_VERSION"
  printf 'Started: %s\n' "$STARTED_AT"
  printf 'Host: %s | Kernel: %s\n' "$HOSTNAME_VAL" "$(uname -srm 2>/dev/null || printf 'Linux')"
}

# --- SECTION 1: Hardware & System Identification ---
check_hardware_identity() {
  separator
  printf '%s1. Hardware & System Identity%s\n' "$C_BOLD" "$C_RESET"

  MODEL=""
  SERIAL=""
  CPU_SERIAL=""
  SW_VERSION=""

  # Try /oem/hal/ccinfo first
  if [ -r /oem/hal/ccinfo ]; then
    SERIAL="$(awk -F': *' '/Controller serial/{print $2}' /oem/hal/ccinfo | sed 's/^[ \t]*//;s/[ \t]*$//')"
    CPU_SERIAL="$(awk -F': *' '/Processor serial/{print $2}' /oem/hal/ccinfo | sed 's/^[ \t]*//;s/[ \t]*$//')"
    MODEL="$(awk -F': *' '/Hardware version/{print $2}' /oem/hal/ccinfo | sed 's/^[ \t]*//;s/[ \t]*$//')"
    SW_VERSION="$(awk -F': *' '/Software version/{print $2}' /oem/hal/ccinfo | sed 's/^[ \t]*//;s/[ \t]*$//')"
  fi

  # Fallback to devicetree & proc
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

  printf '  Device Model:         %s%s%s\n' "$C_BOLD" "${MODEL:-Unknown Model}" "$C_RESET"
  printf '  Controller Serial:    %s%s%s\n' "$C_BOLD" "${SERIAL:-n/a}" "$C_RESET"
  printf '  Processor Serial:     %s\n' "${CPU_SERIAL:-n/a}"
  printf '  Base OS:              %s\n' "${SW_VERSION:-Buildroot}"
  
  # System Uptime & Load
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
    printf '  System Uptime:        %s\n' "$UPTIME_FMT"
  fi

  if [ -r /proc/loadavg ]; then
    LOAD_1="$(cut -d' ' -f1 /proc/loadavg)"
    LOAD_5="$(cut -d' ' -f2 /proc/loadavg)"
    LOAD_15="$(cut -d' ' -f3 /proc/loadavg)"
    printf '  Load Average:         %s, %s, %s (1m, 5m, 15m)\n' "$LOAD_1" "$LOAD_5" "$LOAD_15"
  fi
}

# --- SECTION 2: iRidi Server Runtime & Firmware ---
check_iridi_runtime() {
  separator
  printf '%s2. iRidi Server Firmware & Runtime%s\n' "$C_BOLD" "$C_RESET"

  PACKAGE_VER=""
  PACKAGE_TIME=""
  if command -v opkg >/dev/null 2>&1; then
    PACKAGE_VER="$(opkg status iridiumserver 2>/dev/null | awk -F': *' '/Version:/{print $2}')"
    PACKAGE_TIME="$(opkg status iridiumserver 2>/dev/null | awk -F': *' '/Installed-Time:/{print $2}')"
  fi
  if [ -z "$PACKAGE_VER" ] && [ -r /var/lib/opkg/info/iridiumserver.control ]; then
    PACKAGE_VER="$(awk -F': *' '/Version:/{print $2}' /var/lib/opkg/info/iridiumserver.control)"
  fi

  # Determine server flavor (Bus77 Home, iRidi Pro, ProAV, i3 KNX, Lite)
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

  printf '  Server Edition:       %s%s%s\n' "$C_BOLD" "$FLAVOR" "$C_RESET"
  if [ -n "$PACKAGE_VER" ]; then
    printf '  Package Version:      %s%s%s\n' "$C_GREEN" "$PACKAGE_VER" "$C_RESET"
  else
    printf '  Package Version:      unknown\n'
  fi

  if [ -n "$PACKAGE_TIME" ] && [ "$PACKAGE_TIME" -gt 0 ] 2>/dev/null; then
    INSTALLED_DATE="$(date -d "@$PACKAGE_TIME" 2>/dev/null || date -r "$PACKAGE_TIME" 2>/dev/null || printf '')"
    if [ -n "$INSTALLED_DATE" ]; then
      printf '  Installed Date:       %s\n' "$INSTALLED_DATE"
    fi
  fi

  # Check process status
  IRIDIUM_PID="$(pidof iridium 2>/dev/null | awk '{print $1}')"
  if [ -n "$IRIDIUM_PID" ]; then
    # Memory and CPU stats
    MEM_RSS="$(awk '/VmRSS/{print $2,$3}' "/proc/$IRIDIUM_PID/status" 2>/dev/null || printf 'n/a')"
    THREADS="$(awk '/Threads/{print $2}' "/proc/$IRIDIUM_PID/status" 2>/dev/null || printf 'n/a')"
    printf '  Service Process:      %sRUNNING%s (PID %s, Memory: %s, Threads: %s)\n' "$C_GREEN" "$C_RESET" "$IRIDIUM_PID" "$MEM_RSS" "$THREADS"
    printf '  [%sOK%s] iRidi Server service is actively running.\n' "$C_GREEN" "$C_RESET"
  else
    printf '  Service Process:      %sNOT RUNNING%s\n' "$C_RED" "$C_RESET"
    printf '  [%sNOT OK%s] iRidi Server executable is not running!\n' "$C_RED" "$C_RESET"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

  # Check active ports
  printf '  Active Server Ports:\n'
  NETSTAT_OUT="$(ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null)"
  for PORT in 8888 8443 30464 30465 30467 65534 8883 2812 22; do
    DESC=""
    case "$PORT" in
      8888) DESC="Web Interface (HTTP)" ;;
      8443) DESC="Web Interface (HTTPS)" ;;
      30464) DESC="Client Discovery & App Link" ;;
      30465) DESC="Client Connection Port" ;;
      30467) DESC="Internal Gateway Port" ;;
      65534) DESC="CAN/Bus77 UDP Gateway" ;;
      8883) DESC="Mosquitto MQTT (TLS)" ;;
      2812) DESC="Monit Process Supervisor" ;;
      22)   DESC="SSH Management" ;;
    esac
    if printf '%s\n' "$NETSTAT_OUT" | grep -q ":${PORT} "; then
      printf '    - Port %-5s [%sOPEN%s]  - %s\n' "$PORT" "$C_GREEN" "$C_RESET" "$DESC"
    fi
  done
}

# --- SECTION 3: CPU & Thermal Health ---
check_thermal_and_cpu() {
  separator
  printf '%s3. CPU & Thermal Sensors (Hardware Health)%s\n' "$C_BOLD" "$C_RESET"

  THERMAL_FOUND=0
  for TZ_DIR in /sys/class/thermal/thermal_zone*; do
    if [ -d "$TZ_DIR" ]; then
      THERMAL_FOUND=1
      TZ_TYPE="$(cat "$TZ_DIR/type" 2>/dev/null || printf 'zone')"
      TZ_RAW="$(cat "$TZ_DIR/temp" 2>/dev/null || printf '0')"
      TZ_C=$(( TZ_RAW / 1000 ))
      
      if [ "$TZ_C" -lt 75 ]; then
        printf '  %-18s: %s%d°C%s [%sOK%s]\n' "$TZ_TYPE" "$C_GREEN" "$TZ_C" "$C_RESET" "$C_GREEN" "$C_RESET"
      elif [ "$TZ_C" -lt 85 ]; then
        printf '  %-18s: %s%d°C%s [%sATTENTION%s - elevated temperature]\n' "$TZ_TYPE" "$C_YELLOW" "$TZ_C" "$C_RESET" "$C_YELLOW" "$C_RESET"
        WARN_COUNT=$((WARN_COUNT + 1))
      else
        printf '  %-18s: %s%d°C%s [%sCRITICAL%s - overheating!]\n' "$TZ_TYPE" "$C_RED" "$TZ_C" "$C_RESET" "$C_RED" "$C_RESET"
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
    fi
  done

  if [ "$THERMAL_FOUND" -eq 0 ]; then
    printf '  [INFO] No hardware thermal sensors detected under /sys/class/thermal.\n'
  fi

  # CPU Cores & Current Frequency
  CPU_CORES="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || printf '1')"
  CPU_FREQ_RAW="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq 2>/dev/null)"
  if [ -n "$CPU_FREQ_RAW" ] && [ "$CPU_FREQ_RAW" -gt 0 ] 2>/dev/null; then
    CPU_MHZ=$(( CPU_FREQ_RAW / 1000 ))
    printf '  CPU Configuration : %s cores @ %d MHz\n' "$CPU_CORES" "$CPU_MHZ"
  else
    printf '  CPU Configuration : %s cores\n' "$CPU_CORES"
  fi
}

# --- SECTION 4: Memory (RAM) Health ---
check_memory_health() {
  separator
  printf '%s4. Memory (RAM) Utilization%s\n' "$C_BOLD" "$C_RESET"

  if [ -r /proc/meminfo ]; then
    MEM_TOTAL_KB="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
    MEM_FREE_KB="$(awk '/MemFree/{print $2}' /proc/meminfo)"
    MEM_AVAIL_KB="$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
    MEM_BUFFERS_KB="$(awk '/Buffers/{print $2}' /proc/meminfo)"
    MEM_CACHED_KB="$(awk '/^Cached/{print $2}' /proc/meminfo)"

    MEM_AVAIL_KB="${MEM_AVAIL_KB:-$MEM_FREE_KB}"
    MEM_TOTAL_MB=$(( MEM_TOTAL_KB / 1024 ))
    MEM_AVAIL_MB=$(( MEM_AVAIL_KB / 1024 ))
    MEM_USED_MB=$(( MEM_TOTAL_MB - MEM_AVAIL_MB ))

    MEM_PERCENT=0
    if [ "$MEM_TOTAL_MB" -gt 0 ]; then
      MEM_PERCENT=$(( (MEM_USED_MB * 100) / MEM_TOTAL_MB ))
    fi

    printf '  Total Memory      : %s MB\n' "$MEM_TOTAL_MB"
    printf '  Used Memory       : %s MB (%d%%)\n' "$MEM_USED_MB" "$MEM_PERCENT"
    printf '  Available Memory  : %s MB\n' "$MEM_AVAIL_MB"

    if [ "$MEM_PERCENT" -lt 85 ]; then
      printf '  [%sOK%s] Memory utilization is normal.\n' "$C_GREEN" "$C_RESET"
    elif [ "$MEM_PERCENT" -lt 95 ]; then
      printf '  [%sATTENTION%s] Memory usage is high (%d%% used).\n' "$C_YELLOW" "$C_RESET" "$MEM_PERCENT"
      WARN_COUNT=$((WARN_COUNT + 1))
    else
      printf '  [%sNOT OK%s] Memory exhaustion risk (%d%% used, only %s MB free).\n' "$C_RED" "$C_RESET" "$MEM_PERCENT" "$MEM_AVAIL_MB"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  fi
}

# --- SECTION 5: eMMC Storage Wear & SMART Health ---
check_emmc_and_storage() {
  separator
  printf '%s5. Storage & eMMC Wear Indicators (SMART)%s\n' "$C_BOLD" "$C_RESET"

  # Detect eMMC device path
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
    MMC_DATE="$(cat "$MMC_DEV/date" 2>/dev/null)"
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

    printf '  eMMC Model        : %s (%s, date: %s)\n' "${MMC_NAME:-eMMC}" "$MANUFACTURER_STR" "${MMC_DATE:-n/a}"
    
    # Life Time Indicators
    LIFE_A="$(printf '%s' "$MMC_LIFE" | awk '{print $1}')"
    LIFE_B="$(printf '%s' "$MMC_LIFE" | awk '{print $2}')"
    
    decode_life() {
      case "$1" in
        0x01|0x1|1) echo "0-10% life used" ;;
        0x02|0x2|2) echo "10-20% life used" ;;
        0x03|0x3|3) echo "20-30% life used" ;;
        0x04|0x4|4) echo "30-40% life used" ;;
        0x05|0x5|5) echo "40-50% life used" ;;
        0x06|0x6|6) echo "50-60% life used" ;;
        0x07|0x7|7) echo "60-70% life used" ;;
        0x08|0x8|8) echo "70-80% life used" ;;
        0x09|0x9|9) echo "80-90% life used" ;;
        0x0a|0xa|10) echo "90-100% life used (critical)" ;;
        0x0b|0xb|11) echo "exceeded maximum estimated life" ;;
        *) echo "not reported ($1)" ;;
      esac
    }

    if [ -n "$LIFE_A" ]; then
      printf '  Wear Indicator A  : %s (%s)\n' "$LIFE_A" "$(decode_life "$LIFE_A")"
      printf '  Wear Indicator B  : %s (%s)\n' "$LIFE_B" "$(decode_life "$LIFE_B")"
      if [ "$LIFE_A" = "0x0a" ] || [ "$LIFE_A" = "0x0b" ] || [ "$LIFE_B" = "0x0a" ] || [ "$LIFE_B" = "0x0b" ]; then
        printf '  [%sCRITICAL%s] eMMC flash storage has reached end of rated endurance!\n' "$C_RED" "$C_RESET"
        FAIL_COUNT=$((FAIL_COUNT + 1))
      else
        printf '  [%sOK%s] eMMC endurance level is healthy.\n' "$C_GREEN" "$C_RESET"
      fi
    fi

    # Pre-EOL State
    case "$MMC_PRE_EOL" in
      0x01|0x1|1)
        printf '  Pre-EOL State     : 0x01 Normal [%sOK%s]\n' "$C_GREEN" "$C_RESET"
        ;;
      0x02|0x2|2)
        printf '  Pre-EOL State     : 0x02 Warning (consumed 80%% of reserved blocks) [%sATTENTION%s]\n' "$C_YELLOW" "$C_RESET"
        WARN_COUNT=$((WARN_COUNT + 1))
        ;;
      0x03|0x3|3)
        printf '  Pre-EOL State     : 0x03 Urgent (consumed reserved blocks) [%sCRITICAL%s]\n' "$C_RED" "$C_RESET"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        ;;
      *)
        printf '  Pre-EOL State     : %s\n' "${MMC_PRE_EOL:-n/a}"
        ;;
    esac
  else
    printf '  [INFO] eMMC sysfs node not directly accessible.\n'
  fi

  # Partition usage
  printf '  Partition Space Status:\n'
  df -h / /userdata /oem 2>/dev/null | awk 'NR>1 { printf "    - %-14s: %6s total, %6s free (%4s used)\n", $6, $2, $4, $5 }'

  # Kernel error scan
  ERR_COUNT=0
  if command -v dmesg >/dev/null 2>&1; then
    ERR_COUNT="$(dmesg 2>/dev/null | grep -ciE '(Buffer I/O error|EXT4-fs error|blk_update_request: I/O error|mmc.*error|end_request: I/O error)' || true)"
  fi
  if [ "$ERR_COUNT" -eq 0 ]; then
    printf '  [%sOK%s] No storage I/O or EXT4 filesystem errors detected in kernel log.\n' "$C_GREEN" "$C_RESET"
  else
    printf '  [%sATTENTION%s] %d storage/filesystem errors found in kernel log!\n' "$C_YELLOW" "$C_RESET" "$ERR_COUNT"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
}

# --- SECTION 6: Network & CAN Bus Status ---
check_network_and_can() {
  separator
  printf '%s6. Network & Communication Interfaces%s\n' "$C_BOLD" "$C_RESET"

  # Ethernet (eth0)
  if [ -d /sys/class/net/eth0 ]; then
    ETH_IP="$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}' | head -n 1)"
    ETH_MAC="$(cat /sys/class/net/eth0/address 2>/dev/null)"
    ETH_OPER="$(cat /sys/class/net/eth0/operstate 2>/dev/null)"
    ETH_SPEED="$(cat /sys/class/net/eth0/speed 2>/dev/null || printf 'n/a')"
    
    printf '  Interface eth0    : %s (%s, %s Mbps)\n' "${ETH_IP:-no IPv4}" "${ETH_OPER:-unknown}" "${ETH_SPEED:-n/a}"
    printf '  MAC Address       : %s\n' "${ETH_MAC:-unknown}"
    
    if [ "$ETH_OPER" = "up" ]; then
      printf '  [%sOK%s] Ethernet link is UP.\n' "$C_GREEN" "$C_RESET"
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
    fi
    CAN_STATE="${CAN_STATE:-UP}"
    printf '  Interface can0    : %s (State: %s, Bitrate: %s bit/s)\n' "Bus77 CAN Bus" "$CAN_STATE" "${CAN_BITRATE:-125000}"
    if [ "$CAN_STATE" = "ERROR-ACTIVE" ]; then
      printf '  [%sOK%s] CAN controller is ERROR-ACTIVE (bus connected and active).\n' "$C_GREEN" "$C_RESET"
    elif [ "$CAN_STATE" = "ERROR-PASSIVE" ]; then
      printf '  [%sINFO%s] CAN controller is in ERROR-PASSIVE state (normal if no devices or cable connected).\n' "$C_CYAN" "$C_RESET"
    elif [ "$CAN_STATE" = "BUS-OFF" ]; then
      printf '  [%sATTENTION%s] CAN controller is in BUS-OFF state (bus failure / heavy collision).\n' "$C_YELLOW" "$C_RESET"
      WARN_COUNT=$((WARN_COUNT + 1))
    else
      printf '  [%sOK%s] CAN interface is ready.\n' "$C_GREEN" "$C_RESET"
    fi
  else
    printf '  Interface can0    : not present (device operates without hardware CAN bus)\n'
  fi

  # Default Gateway & DNS
  DEF_GW="$(ip route show default 2>/dev/null | awk '/default via/{print $3}' | head -n 1)"
  DNS_SERVERS="$(awk '/nameserver/{printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)"
  printf '  Default Gateway   : %s\n' "${DEF_GW:-n/a}"
  printf '  DNS Resolvers     : %s\n' "${DNS_SERVERS:-n/a}"
}

# --- SECTION 7: Summary & Verdict ---
print_summary() {
  separator
  printf '%sSUMMARY%s\n' "$C_BOLD" "$C_RESET"
  printf '  Failures:        %d\n' "$FAIL_COUNT"
  printf '  Attention items: %d\n' "$WARN_COUNT"

  if [ "$FAIL_COUNT" -gt 0 ]; then
    printf '%sRESULT: FAIL - CRITICAL ISSUES DETECTED (%d failure(s), %d warning(s))%s\n' "$C_RED" "$FAIL_COUNT" "$WARN_COUNT" "$C_RESET"
  elif [ "$WARN_COUNT" -gt 0 ]; then
    printf '%sRESULT: WARN - ATTENTION REQUIRED (%d warning(s), 0 failures)%s\n' "$C_YELLOW" "$WARN_COUNT" "$C_RESET"
  else
    printf '%sRESULT: PASS - SYSTEM HEALTH IS NORMAL (0 failures, 0 warnings)%s\n' "$C_GREEN" "$C_RESET"
  fi
}

# Main execution flow
print_header
check_hardware_identity
check_iridi_runtime
check_thermal_and_cpu
check_memory_health
check_emmc_and_storage
check_network_and_can
print_summary
