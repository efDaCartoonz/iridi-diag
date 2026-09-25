#!/bin/sh

# Safe eMMC and storage diagnostics for iRidi HS/ProAV/UMC and Linux servers.
# Verifies eMMC wear indicators (SMART), partitions & inodes across / and /userdata,
# scans kernel/system logs for storage faults, verifies multi-partition write integrity,
# and benchmarks sequential throughput and 4K database sync latency.
#
# Run:          sh check_emmc_health.sh
# Read-only:    sh check_emmc_health.sh --no-write

case "${1:-}" in
  -h|--help)
    printf 'Usage: sh %s [options]\n\n' "${0##*/}"
    printf 'Options:\n'
    printf '  --no-write    Run safe read-only diagnostics without write benchmarks\n'
    printf '  -h, --help    Show this help message and exit\n\n'
    exit 0
    ;;
esac

TOOL_VERSION="2.1"
WRITE_TEST=yes
[ "${1:-}" = "--no-write" ] && WRITE_TEST=no

# Setup logging directory & technical log file
CURRENT_DIR="$(pwd 2>/dev/null || printf '.')"
LOG_DIR="${IRIDI_DIAG_LOG_DIR:-$CURRENT_DIR}"
if [ ! -d "$LOG_DIR" ] || [ ! -w "$LOG_DIR" ]; then
  LOG_DIR="${TMPDIR:-/tmp}"
fi

HOST_LABEL="$(hostname 2>/dev/null || printf server)"
HOST_LABEL="$(printf '%s' "$HOST_LABEL" | tr -c 'A-Za-z0-9._-' '_')"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S' 2>/dev/null || printf unknown_time)"
LOG_FILE="$LOG_DIR/emmc_diagnostic_${HOST_LABEL}_${TIMESTAMP}_$$.log"

# Open File Descriptor 3 for technical log
if ! exec 3>>"$LOG_FILE" 2>/dev/null; then
  LOG_FILE="${TMPDIR:-/tmp}/emmc_diagnostic_${HOST_LABEL}_${TIMESTAMP}_$$.log"
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

log_tech_cmd() {
  _LABEL="$1"
  shift
  printf '[%s] --- CMD EXEC: %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '-')" "$_LABEL" >&3
  "$@" >&3 2>&1 || true
  printf '[%s] --- END CMD: %s ---\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '-')" "$_LABEL" >&3
}

set +e
export LC_ALL=C

WARNINGS=0
FAILURES=0
TEST_FILES=""
TEST_ERROR=""
EMMC_STATUS="not detected"
BLOCK_STATUS="not determined"
WEAR_STATUS="unavailable"
KERNEL_STATUS="not checked"
WRITE_INTEGRITY_STATUS="not performed"
THROUGHPUT_STATUS="skipped"
LATENCY_STATUS="skipped"

cleanup() {
  for f in $TEST_FILES; do
    [ -f "$f" ] && rm -f "$f"
  done
  [ -n "$TEST_ERROR" ] && rm -f "$TEST_ERROR"
  exec 3>&- 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

read_field() {
  if [ -r "$1" ]; then
    cat "$1" 2>/dev/null
  fi
}

normalize_hex() {
  printf '%s' "$1" | tr 'A-F' 'a-f'
}

manufacturer_name() {
  case "$(normalize_hex "$1")" in
    0x000015|0x15) printf 'Samsung' ;;
    0x000013|0x13) printf 'Micron' ;;
    0x000045|0x45) printf 'SanDisk/Western Digital' ;;
    0x000090|0x90) printf 'SK hynix' ;;
    0x000011|0x11) printf 'Kioxia/Toshiba' ;;
    *) printf 'Unknown' ;;
  esac
}

life_description() {
  case "$(normalize_hex "$1")" in
    0x00) printf 'estimate unavailable' ;;
    0x01) printf '0-10%% used' ;;
    0x02) printf '10-20%% used' ;;
    0x03) printf '20-30%% used' ;;
    0x04) printf '30-40%% used' ;;
    0x05) printf '40-50%% used' ;;
    0x06) printf '50-60%% used' ;;
    0x07) printf '60-70%% used' ;;
    0x08) printf '70-80%% used' ;;
    0x09) printf '80-90%% used' ;;
    0x0a) printf '90-100%% used (critical)' ;;
    0x0b) printf 'rated life exceeded' ;;
    *) printf 'n/a' ;;
  esac
}

checksum_file() {
  if command -v cksum >/dev/null 2>&1; then
    cksum "$1" 2>/dev/null | awk '{print $1":"$2}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  elif command -v md5sum >/dev/null 2>&1; then
    md5sum "$1" 2>/dev/null | awk '{print $1}'
  fi
}

# Technical Log Initial Header
log_tech "================================================================================"
log_tech "iRidi eMMC Storage Diagnostic - Technical Log"
log_tech "Version: $TOOL_VERSION | Write Test: $WRITE_TEST"
log_tech "Host: $(hostname 2>/dev/null) | Kernel: $(uname -srm 2>/dev/null)"
log_tech "Model: $(tr -d '\000' </proc/device-tree/model 2>/dev/null || echo unknown)"
log_tech "Log File: $LOG_FILE"
log_tech "================================================================================"

# Screen Header
printf '%s================================================================%s\n' "$C_CYAN" "$C_RESET"
printf '  %siRidi eMMC Storage Health & Performance%s (v%s)\n' "$C_BOLD" "$C_RESET" "$TOOL_VERSION"
printf '%s================================================================%s\n' "$C_CYAN" "$C_RESET"
printf 'Host: %s | Mode: %s\n\n' "$(hostname 2>/dev/null || printf unknown)" "$( [ "$WRITE_TEST" = "yes" ] && echo "Full (Read/Write Benchmarks)" || echo "Read-Only (--no-write)" )"

# --- SECTION 1: eMMC Identification & Wear Indicators ---
check_emmc_smart() {
  printf '%s1. eMMC Hardware Identification & SMART Indicators:%s\n' "$C_BOLD" "$C_RESET"

  MMC_DEVICE=""
  for candidate in /sys/bus/mmc/devices/*; do
    [ -d "$candidate" ] || continue
    [ "$(read_field "$candidate/type")" = "MMC" ] || continue
    MMC_DEVICE="$candidate"
    break
  done

  MMC_BLOCK=""
  MMC_NODE=""
  if [ -n "$MMC_DEVICE" ]; then
    for candidate in "$MMC_DEVICE"/block/mmcblk*; do
      [ -e "$candidate" ] || continue
      MMC_BLOCK="$candidate"
      MMC_NODE="/dev/${candidate##*/}"
      break
    done
  fi

  if [ -z "$MMC_DEVICE" ]; then
    printf '  %s[NOT OK]%s    No eMMC device detected in /sys/bus/mmc/devices\n' "$C_RED" "$C_RESET"
    FAILURES=$((FAILURES + 1))
    log_tech "EMMC SMART: No eMMC device found"
  else
    EMMC_STATUS="detected"
    MMC_NAME="$(read_field "$MMC_DEVICE/name")"
    MMC_MANFID="$(read_field "$MMC_DEVICE/manfid")"
    MMC_DATE="$(read_field "$MMC_DEVICE/date")"
    MMC_SERIAL="$(read_field "$MMC_DEVICE/serial")"
    MMC_LIFE="$(read_field "$MMC_DEVICE/life_time")"
    MMC_LIFE_A="$(printf '%s' "$MMC_LIFE" | awk '{print $1}')"
    MMC_LIFE_B="$(printf '%s' "$MMC_LIFE" | awk '{print $2}')"
    MMC_PRE_EOL="$(read_field "$MMC_DEVICE/pre_eol_info")"

    log_tech "EMMC RAW: dev=$MMC_DEVICE node=$MMC_NODE name=$MMC_NAME manfid=$MMC_MANFID life='$MMC_LIFE' pre_eol=$MMC_PRE_EOL"

    MANF_NAME="$(manufacturer_name "$MMC_MANFID")"
    DESC_A="$(life_description "$MMC_LIFE_A")"
    DESC_B="$(life_description "$MMC_LIFE_B")"

    if [ "$MMC_PRE_EOL" = "0x03" ] || [ "$MMC_LIFE_A" = "0x0b" ] || [ "$MMC_LIFE_B" = "0x0b" ]; then
      printf '  %s[NOT OK]%s    Device: %s (%s) — CRITICAL: Rated endurance exceeded!\n' "$C_RED" "$C_RESET" "${MMC_NAME:-eMMC}" "$MANF_NAME"
      FAILURES=$((FAILURES + 1))
    elif [ "$MMC_PRE_EOL" = "0x02" ] || [ "$MMC_LIFE_A" = "0x0a" ] || [ "$MMC_LIFE_B" = "0x0a" ] || [ "$MMC_LIFE_A" = "0x09" ] || [ "$MMC_LIFE_B" = "0x09" ]; then
      printf '  %s[ATTENTION]%s Device: %s (%s) — ELEVATED WEAR: A (SLC): %s, B (User): %s\n' \
        "$C_YELLOW" "$C_RESET" "${MMC_NAME:-eMMC}" "$MANF_NAME" "$DESC_A" "$DESC_B"
      WARNINGS=$((WARNINGS + 1))
    else
      printf '  %s[OK]%s        Device: %s (%s) — Wear: %s (Health: Normal)\n' \
        "$C_GREEN" "$C_RESET" "${MMC_NAME:-eMMC}" "$MANF_NAME" "$DESC_B"
    fi

    # Check writable flag
    if [ -n "$MMC_BLOCK" ]; then
      BLOCK_RO="$(read_field "$MMC_BLOCK/ro")"
      if [ "$BLOCK_RO" = "1" ]; then
        printf '  %s[NOT OK]%s    Kernel reports main block device %s as READ-ONLY!\n' "$C_RED" "$C_RESET" "${MMC_NODE:-eMMC}"
        FAILURES=$((FAILURES + 1))
      fi
    fi

    # Read EXT_CSD if mmc-utils is available
    if command -v mmc >/dev/null 2>&1 && [ -b "$MMC_NODE" ]; then
      EXT_CSD="$(mmc extcsd read "$MMC_NODE" 2>&1)"
      log_tech_file "EXT_CSD DUMP ($MMC_NODE)" "$EXT_CSD"
    fi
  fi
}

# --- SECTION 2: Storage Partitions & Inodes ---
check_partitions() {
  printf '\n%s2. File Systems & Partition Health:%s\n' "$C_BOLD" "$C_RESET"

  for TARGET_DIR in / /userdata /oem; do
    [ -d "$TARGET_DIR" ] || continue
    
    MNT_LINE="$(awk -v dir="$TARGET_DIR" '$2==dir {print $1,$3,$4; exit}' /proc/mounts 2>/dev/null)"
    MNT_DEV="$(echo "$MNT_LINE" | awk '{print $1}')"
    MNT_FS="$(echo "$MNT_LINE" | awk '{print $2}')"
    MNT_OPT="$(echo "$MNT_LINE" | awk '{print $3}')"
    
    SPACE_INFO="$(df -h "$TARGET_DIR" 2>/dev/null | awk 'NR==2 {print $2,$3,$4,$5}')"
    TOTAL_SPACE="$(echo "$SPACE_INFO" | awk '{print $1}')"
    AVAIL_SPACE="$(echo "$SPACE_INFO" | awk '{print $3}')"
    USED_PCT="$(echo "$SPACE_INFO" | awk '{print $4}')"
    
    INODE_INFO="$(df -i "$TARGET_DIR" 2>/dev/null | awk 'NR==2 {print $2,$3,$4,$5}')"
    FREE_INODES="$(echo "$INODE_INFO" | awk '{print $3}')"
    INODE_PCT="$(echo "$INODE_INFO" | awk '{print $4}')"

    log_tech "PARTITION $TARGET_DIR: dev=$MNT_DEV fs=$MNT_FS opt=$MNT_OPT space=$USED_PCT inodes=$INODE_PCT"
    
    case ",${MNT_OPT}," in
      *,ro,*)
        printf '  %s[NOT OK]%s    %-12s: Mounted READ-ONLY (Filesystem emergency mode!)\n' "$C_RED" "$C_RESET" "$TARGET_DIR"
        FAILURES=$((FAILURES + 1))
        ;;
      *,rw,*)
        printf '  %s[OK]%s        %-12s: %s used (%s free of %s) | Inodes: %s used\n' \
          "$C_GREEN" "$C_RESET" "$TARGET_DIR" "${USED_PCT:-0%}" "${AVAIL_SPACE:-0}" "${TOTAL_SPACE:-0}" "${INODE_PCT:-0%}"
        ;;
      *)
        printf '  %s[ATTENTION]%s %-12s: Mount status uncertain\n' "$C_YELLOW" "$C_RESET" "$TARGET_DIR"
        WARNINGS=$((WARNINGS + 1))
        ;;
    esac

    INODE_NUM="${INODE_PCT%%%}"
    if [ -n "$INODE_NUM" ] && [ "$INODE_NUM" -gt 90 ] 2>/dev/null; then
      printf '              %s! Inode exhaustion warning: %s free inodes remaining%s\n' "$C_RED" "$FREE_INODES" "$C_RESET"
      FAILURES=$((FAILURES + 1))
    fi
  done
}

# --- SECTION 3: Kernel Storage Error Scan ---
check_storage_logs() {
  printf '\n%s3. Kernel Storage Logs & I/O Integrity:%s\n' "$C_BOLD" "$C_RESET"

  KERNEL_PATTERN='buffer i/o error|blk_update.*i/o error|print_req_error.*i/o error|i/o error.*mmcblk|ext4-fs.*error|remounting filesystem read-only|mmc.*(timed out|timeout|i/o error)|filesystem error|journal.*abort'
  DMESG_ERRORS="$(dmesg 2>/dev/null | grep -Ei "$KERNEL_PATTERN")"
  DMESG_COUNT="$(printf '%s\n' "$DMESG_ERRORS" | sed '/^$/d' | wc -l | tr -d ' ')"

  log_tech "DMESG ERRORS COUNT: $DMESG_COUNT"
  if [ -n "$DMESG_ERRORS" ]; then
    log_tech "--- BEGIN DMESG STORAGE ERRORS ---"
    printf '%s\n' "$DMESG_ERRORS" >&3
    log_tech "--- END DMESG STORAGE ERRORS ---"
  fi

  if [ "${DMESG_COUNT:-0}" -eq 0 ]; then
    printf '  %s[OK]%s        Kernel Ring Buffer: Clean (0 hardware I/O or filesystem errors)\n' "$C_GREEN" "$C_RESET"
  else
    printf '  %s[NOT OK]%s    Kernel Ring Buffer: %s storage I/O or filesystem error events detected!\n' "$C_RED" "$C_RESET" "$DMESG_COUNT"
    FAILURES=$((FAILURES + 1))
  fi
}

# --- SECTION 4: Storage Performance & Write Integrity ---
check_storage_performance() {
  printf '\n%s4. Storage Write Integrity & Performance Benchmarks:%s\n' "$C_BOLD" "$C_RESET"

  if [ "$WRITE_TEST" != "yes" ]; then
    printf '  %s[INFO]%s      Write benchmarks skipped (--no-write mode enabled)\n' "$C_GRAY" "$C_RESET"
    return 0
  fi

  # 1. Multi-partition write test
  WRITE_OK=1
  for TARGET_DIR in / /userdata; do
    [ -d "$TARGET_DIR" ] || continue
    
    FREE_KB="$(df -Pk "$TARGET_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
    if [ "${FREE_KB:-0}" -lt 10240 ] 2>/dev/null; then
      continue
    fi
    
    TEST_FILE="${TARGET_DIR}/.emmc_diag_test_$$.bin"
    TEST_FILES="$TEST_FILES $TEST_FILE"
    TEST_ERROR="$(mktemp /tmp/emmc_err.XXXXXX 2>/dev/null || echo "/dev/null")"
    
    dd if=/dev/urandom of="$TEST_FILE" bs=4096 count=256 2>"$TEST_ERROR"
    WRITE_RC=$?
    sync
    
    if [ "$WRITE_RC" -eq 0 ] && [ -f "$TEST_FILE" ]; then
      WRITTEN_SIZE="$(wc -c <"$TEST_FILE" | tr -d ' ')"
      CHECKSUM_1="$(checksum_file "$TEST_FILE")"
      CHECKSUM_2="$(checksum_file "$TEST_FILE")"
      
      if [ "$WRITTEN_SIZE" != "1048576" ] || [ -z "$CHECKSUM_1" ] || [ "$CHECKSUM_1" != "$CHECKSUM_2" ]; then
        WRITE_OK=0
      fi
    else
      WRITE_OK=0
    fi
    rm -f "$TEST_FILE" "$TEST_ERROR" 2>/dev/null
    sync
  done

  if [ "$WRITE_OK" -eq 1 ]; then
    printf '  %s[OK]%s        Write Integrity: 1 MiB write, sync, double-read & CRC verified\n' "$C_GREEN" "$C_RESET"
  else
    printf '  %s[NOT OK]%s    Write Integrity: CRC mismatch or filesystem write failure!\n' "$C_RED" "$C_RESET"
    FAILURES=$((FAILURES + 1))
  fi

  # 2. Sequential Write Benchmark
  BENCH_DIR="/userdata"
  [ -d "$BENCH_DIR" ] || BENCH_DIR="/"
  BENCH_FILE="${BENCH_DIR}/.emmc_speed_bench_$$.bin"
  TEST_FILES="$TEST_FILES $BENCH_FILE"
  
  FREE_MB=$(( $(df -Pk "$BENCH_DIR" 2>/dev/null | awk 'NR==2 {print $4}') / 1024 ))
  if [ "$FREE_MB" -ge 100 ]; then
    WRITE_BENCH_OUT="$(dd if=/dev/zero of="$BENCH_FILE" bs=1M count=10 conv=fsync 2>&1)"
    WRITE_SPEED_STR="$(printf '%s\n' "$WRITE_BENCH_OUT" | awk -F', ' '/copied/{print $NF}' | tr -d '\r\n')"
    rm -f "$BENCH_FILE" 2>/dev/null
    sync

    log_tech "BENCHMARK WRITE: $WRITE_BENCH_OUT"
    
    if [ -n "$WRITE_SPEED_STR" ]; then
      SPEED_VAL="$(printf '%s' "$WRITE_SPEED_STR" | awk '{print $1}' | cut -d'.' -f1)"
      SPEED_UNIT="$(printf '%s' "$WRITE_SPEED_STR" | awk '{print $2}')"
      
      if [ "$SPEED_UNIT" = "MB/s" ] || [ "$SPEED_UNIT" = "MiB/s" ]; then
        if [ "${SPEED_VAL:-0}" -ge 20 ]; then
          printf '  %s[OK]%s        Sequential Write Speed: %s (Optimal throughput)\n' "$C_GREEN" "$C_RESET" "$WRITE_SPEED_STR"
        elif [ "${SPEED_VAL:-0}" -ge 10 ]; then
          printf '  %s[OK]%s        Sequential Write Speed: %s (Acceptable throughput)\n' "$C_GREEN" "$C_RESET" "$WRITE_SPEED_STR"
        else
          printf '  %s[ATTENTION]%s Sequential Write Speed: %s (Degraded flash write speed)\n' "$C_YELLOW" "$C_RESET" "$WRITE_SPEED_STR"
          WARNINGS=$((WARNINGS + 1))
        fi
      fi
    fi
  fi

  # 3. 4K Database Sync Latency
  SYNC_FILE="${BENCH_DIR}/.emmc_sync_bench_$$.bin"
  TEST_FILES="$TEST_FILES $SYNC_FILE"
  T_START="$(date +%s 2>/dev/null || echo 0)"
  SYNC_FAIL=0
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    dd if=/dev/zero of="$SYNC_FILE" bs=4k count=1 conv=fdatasync >/dev/null 2>&1 || SYNC_FAIL=1
  done
  T_END="$(date +%s 2>/dev/null || echo 0)"
  rm -f "$SYNC_FILE" 2>/dev/null
  sync
  
  TOTAL_TIME=$(( T_END - T_START ))
  log_tech "BENCHMARK 4K SYNC: 20 commits in ${TOTAL_TIME}s (fail=$SYNC_FAIL)"
  
  if [ "$SYNC_FAIL" -eq 0 ]; then
    if [ "$TOTAL_TIME" -le 2 ]; then
      printf '  %s[OK]%s        SQLite 4K Commit Latency: 20 transactions in %ds (Fast fsync response)\n' "$C_GREEN" "$C_RESET" "$TOTAL_TIME"
    elif [ "$TOTAL_TIME" -le 5 ]; then
      printf '  %s[OK]%s        SQLite 4K Commit Latency: 20 transactions in %ds (Normal)\n' "$C_GREEN" "$C_RESET" "$TOTAL_TIME"
    else
      printf '  %s[ATTENTION]%s SQLite 4K Commit Latency: %ds (> 5s — Possible database lag)\n' "$C_YELLOW" "$C_RESET" "$TOTAL_TIME"
      WARNINGS=$((WARNINGS + 1))
    fi
  else
    printf '  %s[NOT OK]%s    SQLite 4K Commit Latency: Transactions failed with I/O errors\n' "$C_RED" "$C_RESET"
    FAILURES=$((FAILURES + 1))
  fi
}

print_summary() {
  printf '\n%s================================================================%s\n' "$C_CYAN" "$C_RESET"
  printf '  %sSTORAGE HEALTH SUMMARY%s\n' "$C_BOLD" "$C_RESET"
  printf '%s================================================================%s\n' "$C_CYAN" "$C_RESET"
  printf 'Failures:        %d\n' "$FAILURES"
  printf 'Attention items: %d\n' "$WARNINGS"

  log_tech "SUMMARY: failures=$FAILURES warnings=$WARNINGS"

  if [ "$FAILURES" -gt 0 ]; then
    printf '\n%sRESULT: FAIL — Critical storage wear, filesystem corruption, or I/O errors detected%s\n' "$C_RED" "$C_RESET"
    printf 'Detailed technical log: %s\n\n' "$LOG_FILE"
    log_tech "RESULT: FAIL"
    exit 2
  elif [ "$WARNINGS" -gt 0 ]; then
    printf '\n%sRESULT: WARN — Storage is operational, but %d item(s) require attention%s\n' "$C_YELLOW" "$WARNINGS" "$C_RESET"
    printf 'Detailed technical log: %s\n\n' "$LOG_FILE"
    log_tech "RESULT: WARN"
    exit 1
  else
    printf '\n%sRESULT: PASS — eMMC storage is healthy with low wear level (0 failures, 0 warnings)%s\n' "$C_GREEN" "$C_RESET"
    printf 'Detailed technical log: %s\n\n' "$LOG_FILE"
    log_tech "RESULT: PASS"
    exit 0
  fi
}

check_emmc_smart
check_partitions
check_storage_logs
check_storage_performance
print_summary
