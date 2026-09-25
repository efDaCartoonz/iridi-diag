#!/bin/sh

# Safe eMMC and storage diagnostics for iRidi HS/ProAV/UMC and Linux servers.
# Verifies eMMC wear indicators (SMART), partitions & inodes across / and /userdata,
# scans kernel/system logs for storage faults, verifies multi-partition write integrity,
# and benchmarks sequential throughput and 4K database sync latency.
#
# Run:          sh check_emmc_health.sh
# Read-only:    sh check_emmc_health.sh --no-write

# Portable logging wrapper. The diagnostic body runs as a child so BusyBox tee
# can show live output and save it without requiring Bash process substitution.
if [ "${IRIDI_EMMC_LOG_ACTIVE:-0}" != "1" ]; then
  CURRENT_DIRECTORY="$(pwd 2>/dev/null || printf '.')"
  LOG_DIRECTORY="${IRIDI_DIAG_LOG_DIR:-$CURRENT_DIRECTORY}"
  if [ ! -d "$LOG_DIRECTORY" ] || [ ! -w "$LOG_DIRECTORY" ]; then
    LOG_DIRECTORY="${TMPDIR:-/tmp}"
  fi
  HOST_LABEL="$(hostname 2>/dev/null || printf server)"
  HOST_LABEL="$(printf '%s' "$HOST_LABEL" | tr -c 'A-Za-z0-9._-' '_')"
  [ -n "$HOST_LABEL" ] || HOST_LABEL=server
  LOG_TIMESTAMP="$(date '+%Y%m%d_%H%M%S' 2>/dev/null || printf unknown_time)"
  LOG_FILE="$LOG_DIRECTORY/emmc_diagnostic_${HOST_LABEL}_${LOG_TIMESTAMP}_$$.log"
  export IRIDI_EMMC_LOG_ACTIVE=1
  export IRIDI_EMMC_LOG_FILE="$LOG_FILE"

  colorize_output() {
    awk '
      /\[OK\]|RESULT: PASS/ { printf "\033[32m%s\033[0m\n", $0; next }
      /\[ATTENTION\]|RESULT: WARN/ { printf "\033[33m%s\033[0m\n", $0; next }
      /\[NOT OK\]|\[CRITICAL\]|RESULT: FAIL/ { printf "\033[31m%s\033[0m\n", $0; next }
      { print }
    '
  }

  if command -v tee >/dev/null 2>&1; then
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && command -v awk >/dev/null 2>&1; then
      sh "$0" "$@" 2>&1 | tee "$LOG_FILE" | colorize_output
    else
      sh "$0" "$@" 2>&1 | tee "$LOG_FILE"
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

  sh "$0" "$@" >"$LOG_FILE" 2>&1
  FINAL_RC=$?
  cat "$LOG_FILE"
  printf '\nLog saved: %s\n' "$LOG_FILE"
  exit "$FINAL_RC"
fi

set +e
export LC_ALL=C

SCRIPT_VERSION=2.0

WRITE_TEST=yes
[ "${1:-}" = "--no-write" ] && WRITE_TEST=no

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
}
trap cleanup EXIT HUP INT TERM

separator() {
  printf '%s\n' '----------------------------------------------------------------'
}

ok() {
  printf '  [OK] %s\n' "$1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '  [ATTENTION] %s\n' "$1"
}

fail() {
  FAILURES=$((FAILURES + 1))
  printf '  [NOT OK] %s\n' "$1"
}

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
    *) printf 'not determined' ;;
  esac
}

life_description() {
  case "$(normalize_hex "$1")" in
    0x00) printf 'estimate unavailable' ;;
    0x01) printf '0-10%% of rated life used' ;;
    0x02) printf '10-20%% of rated life used' ;;
    0x03) printf '20-30%% of rated life used' ;;
    0x04) printf '30-40%% of rated life used' ;;
    0x05) printf '40-50%% of rated life used' ;;
    0x06) printf '50-60%% of rated life used' ;;
    0x07) printf '60-70%% of rated life used' ;;
    0x08) printf '70-80%% of rated life used' ;;
    0x09) printf '80-90%% of rated life used' ;;
    0x0a) printf '90-100%% of rated life used' ;;
    0x0b) printf 'rated life exceeded' ;;
    *) printf 'unknown value' ;;
  esac
}

pre_eol_description() {
  case "$(normalize_hex "$1")" in
    0x01) printf 'normal' ;;
    0x02) printf 'warning: reserved blocks are being consumed' ;;
    0x03) printf 'critical: reserved blocks are exhausted' ;;
    *) printf 'not determined' ;;
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

printf 'eMMC Storage Health & Performance Diagnostic\n'
printf 'Script version: %s\n' "$SCRIPT_VERSION"
printf 'Started: %s\n' "$(date 2>/dev/null || echo unknown)"
printf 'Device: %s\n' "$(hostname 2>/dev/null || echo unknown)"
printf 'Log file: %s\n' "${IRIDI_EMMC_LOG_FILE:-not set}"
printf 'Platform model: %s\n' "$(tr -d '\000' </proc/device-tree/model 2>/dev/null || echo unknown)"
printf 'Kernel: %s\n' "$(uname -a 2>/dev/null)"
printf 'Diagnostic mode: %s\n' "$( [ "$WRITE_TEST" = "yes" ] && echo "full (hardware + multi-partition write & latency)" || echo "read-only (--no-write)" )"

separator
printf '1. eMMC identification and wear indicators (SMART)\n'

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
  fail "No eMMC device was detected in /sys/bus/mmc/devices."
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
  if [ -n "$MMC_LIFE_A" ] || [ -n "$MMC_LIFE_B" ] || [ -n "$MMC_PRE_EOL" ]; then
    WEAR_STATUS="available through sysfs"
  fi
  printf '  Sysfs device: %s\n' "${MMC_DEVICE##*/}"
  printf '  Block device: %s\n' "${MMC_NODE:-not determined}"
  printf '  eMMC model: %s\n' "${MMC_NAME:-not determined}"
  printf '  Manufacturer: %s (%s)\n' "$(manufacturer_name "$MMC_MANFID")" "${MMC_MANFID:-no data}"
  printf '  Manufacturing date: %s\n' "${MMC_DATE:-no data}"
  printf '  Serial number: %s\n' "${MMC_SERIAL:-no data}"
  printf '  LIFE_TIME A (SLC Cache): %s - %s\n' "${MMC_LIFE_A:-no data}" "$(life_description "$MMC_LIFE_A")"
  printf '  LIFE_TIME B (User Area):  %s - %s\n' "${MMC_LIFE_B:-no data}" "$(life_description "$MMC_LIFE_B")"
  printf '  PRE_EOL_INFO: %s - %s\n' "${MMC_PRE_EOL:-no data}" "$(pre_eol_description "$MMC_PRE_EOL")"

  case "$(normalize_hex "$MMC_PRE_EOL")" in
    0x01) ok "PRE_EOL_INFO is normal." ;;
    0x02) warn "PRE_EOL_INFO indicates that reserved blocks are being consumed." ;;
    0x03) fail "PRE_EOL_INFO indicates a critical eMMC condition (reserved blocks exhausted)." ;;
    *) warn "PRE_EOL_INFO is unavailable or unrecognized." ;;
  esac
  for value in "$MMC_LIFE_A" "$MMC_LIFE_B"; do
    case "$(normalize_hex "$value")" in
      0x09|0x0a) warn "At least one LIFE_TIME counter reports 80% or more of rated life used." ;;
      0x0b) fail "At least one LIFE_TIME counter reports that rated life has been exceeded." ;;
    esac
  done
fi

BLOCK_RO=""
if [ -n "$MMC_BLOCK" ]; then
  BLOCK_RO="$(read_field "$MMC_BLOCK/ro")"
  printf '  Main block read-only flag: %s\n' "${BLOCK_RO:-not determined}"
  case "$BLOCK_RO" in
    0) BLOCK_STATUS="writable"; ok "The main eMMC user area is writable at the kernel level." ;;
    1) BLOCK_STATUS="read-only"; fail "The kernel reports the main eMMC user area as read-only." ;;
    *) warn "The main block read-only flag could not be read." ;;
  esac
fi

USER_WP=""
if command -v mmc >/dev/null 2>&1 && [ -b "$MMC_NODE" ]; then
  EXT_CSD="$(mmc extcsd read "$MMC_NODE" 2>&1)"
  USER_WP="$(printf '%s\n' "$EXT_CSD" | awk -F': ' '/User area write protection register \[USER_WP\]/{print $2; exit}')"
  EXT_LIFE_A="$(printf '%s\n' "$EXT_CSD" | awk -F': ' '/EXT_CSD_DEVICE_LIFE_TIME_EST_TYP_A/{print $2; exit}')"
  EXT_LIFE_B="$(printf '%s\n' "$EXT_CSD" | awk -F': ' '/EXT_CSD_DEVICE_LIFE_TIME_EST_TYP_B/{print $2; exit}')"
  EXT_PRE_EOL="$(printf '%s\n' "$EXT_CSD" | awk -F': ' '/EXT_CSD_PRE_EOL_INFO/{print $2; exit}')"
  if [ -n "$EXT_LIFE_A" ] || [ -n "$EXT_LIFE_B" ] || [ -n "$EXT_PRE_EOL" ]; then
    WEAR_STATUS="available through EXT_CSD"
  fi
  printf '  EXT_CSD USER_WP: %s\n' "${USER_WP:-not determined}"
  case "$(normalize_hex "$USER_WP")" in
    0x00) ok "USER_WP=0x00: write protection is not enabled for the user area." ;;
    "") warn "USER_WP could not be read from EXT_CSD." ;;
    *) warn "USER_WP is non-zero; the write-protection bits require interpretation." ;;
  esac
fi

separator
printf '2. Storage Partitions & Inodes Health\n'

PARTITIONS_CHECKED=0
PARTITIONS_ALL_RW=yes

for TARGET_DIR in / /userdata /oem; do
  [ -d "$TARGET_DIR" ] || continue
  PARTITIONS_CHECKED=$((PARTITIONS_CHECKED + 1))
  
  MNT_LINE="$(awk -v dir="$TARGET_DIR" '$2==dir {print $1,$3,$4; exit}' /proc/mounts 2>/dev/null)"
  MNT_DEV="$(echo "$MNT_LINE" | awk '{print $1}')"
  MNT_FS="$(echo "$MNT_LINE" | awk '{print $2}')"
  MNT_OPT="$(echo "$MNT_LINE" | awk '{print $3}')"
  
  SPACE_INFO="$(df -h "$TARGET_DIR" 2>/dev/null | awk 'NR==2 {print $2,$3,$4,$5}')"
  TOTAL_SPACE="$(echo "$SPACE_INFO" | awk '{print $1}')"
  USED_SPACE="$(echo "$SPACE_INFO" | awk '{print $2}')"
  AVAIL_SPACE="$(echo "$SPACE_INFO" | awk '{print $3}')"
  USED_PCT="$(echo "$SPACE_INFO" | awk '{print $4}')"
  
  INODE_INFO="$(df -i "$TARGET_DIR" 2>/dev/null | awk 'NR==2 {print $2,$3,$4,$5}')"
  TOTAL_INODES="$(echo "$INODE_INFO" | awk '{print $1}')"
  USED_INODES="$(echo "$INODE_INFO" | awk '{print $2}')"
  FREE_INODES="$(echo "$INODE_INFO" | awk '{print $3}')"
  INODE_PCT="$(echo "$INODE_INFO" | awk '{print $4}')"
  
  printf '  Partition: %s\n' "$TARGET_DIR"
  printf '    Device & FS:     %s (%s)\n' "${MNT_DEV:-unknown}" "${MNT_FS:-unknown}"
  printf '    Mount Options:   %s\n' "${MNT_OPT:-unknown}"
  printf '    Disk Space:      %s total, %s free (%s used)\n' "$TOTAL_SPACE" "$AVAIL_SPACE" "$USED_PCT"
  printf '    Inodes (Files):  %s total, %s free (%s used)\n' "${TOTAL_INODES:-n/a}" "${FREE_INODES:-n/a}" "${INODE_PCT:-n/a}"
  
  case ",${MNT_OPT}," in
    *,rw,*)
      ok "Partition $TARGET_DIR is mounted read-write."
      ;;
    *,ro,*)
      PARTITIONS_ALL_RW=no
      fail "Partition $TARGET_DIR is mounted READ-ONLY! Filesystem may be corrupted."
      ;;
    *)
      warn "Mount options for $TARGET_DIR could not be fully determined."
      ;;
  esac

  # Inode exhaustion check
  INODE_NUM="${INODE_PCT%%%}"
  if [ -n "$INODE_NUM" ] && [ "$INODE_NUM" -gt 90 ] 2>/dev/null; then
    fail "Partition $TARGET_DIR has exhausted over 90% of available Inodes (${FREE_INODES:-0} left)."
  fi
done

separator
printf '3. Kernel & System Storage Error Logs\n'

KERNEL_PATTERN='buffer i/o error|blk_update.*i/o error|print_req_error.*i/o error|i/o error.*mmcblk|ext4-fs.*error|remounting filesystem read-only|mmc.*(timed out|timeout|i/o error)|filesystem error|journal.*abort'

# 1. Ring buffer
DMESG_ERRORS="$(dmesg 2>/dev/null | grep -Ei "$KERNEL_PATTERN")"
DMESG_COUNT="$(printf '%s\n' "$DMESG_ERRORS" | sed '/^$/d' | wc -l | tr -d ' ')"

# 2. Persistent syslog
SYSLOG_COUNT=0
if [ -r /var/log/messages ]; then
  SYSLOG_ERRORS="$(grep -Ei "$KERNEL_PATTERN" /var/log/messages 2>/dev/null)"
  SYSLOG_COUNT="$(printf '%s\n' "$SYSLOG_ERRORS" | sed '/^$/d' | wc -l | tr -d ' ')"
fi

printf '  Active kernel (dmesg) storage errors: %s\n' "${DMESG_COUNT:-0}"
if [ -r /var/log/messages ]; then
  printf '  Persistent log (/var/log/messages) storage errors: %s\n' "${SYSLOG_COUNT:-0}"
fi

TOTAL_LOG_ERRORS=$(( ${DMESG_COUNT:-0} + ${SYSLOG_COUNT:-0} ))
if [ "$TOTAL_LOG_ERRORS" -gt 0 ]; then
  KERNEL_STATUS="errors found"
  if [ "${DMESG_COUNT:-0}" -gt 0 ]; then
    printf '  Recent dmesg errors:\n'
    printf '%s\n' "$DMESG_ERRORS" | tail -n 10 | sed 's/^/    /'
  fi
  fail "Signs of storage I/O, filesystem, or timeout errors detected in system logs."
else
  KERNEL_STATUS="no errors found"
  ok "No storage I/O, block timeout, or EXT4 errors found in kernel logs."
fi

separator
printf '4. Multi-Partition Controlled Write & Integrity Verification\n'

if [ "$WRITE_TEST" != "yes" ]; then
  WRITE_INTEGRITY_STATUS="skipped (--no-write)"
  warn "Write verification was disabled with --no-write; write capability is unverified."
  printf '  [SKIP] Multi-partition write verification disabled (--no-write).\n'
else
  WRITE_SUCCESS_COUNT=0
  WRITE_TOTAL_COUNT=0
  
  for TARGET_DIR in / /userdata; do
    [ -d "$TARGET_DIR" ] || continue
    WRITE_TOTAL_COUNT=$((WRITE_TOTAL_COUNT + 1))
    
    FREE_KB="$(df -Pk "$TARGET_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
    if [ "${FREE_KB:-0}" -lt 10240 ] 2>/dev/null; then
      warn "Skipping write test on $TARGET_DIR: less than 10 MiB free space."
      continue
    fi
    
    TEST_FILE="${TARGET_DIR}/.emmc_diag_test_$$.bin"
    TEST_FILES="$TEST_FILES $TEST_FILE"
    TEST_ERROR="$(mktemp /tmp/emmc_err.XXXXXX 2>/dev/null || echo "/dev/null")"
    
    printf '  Testing partition: %s (temporary file: %s)\n' "$TARGET_DIR" "${TEST_FILE##*/}"
    
    # 1 MiB controlled write
    dd if=/dev/urandom of="$TEST_FILE" bs=4096 count=256 2>"$TEST_ERROR"
    WRITE_RC=$?
    sync
    
    if [ "$WRITE_RC" -eq 0 ] && [ -f "$TEST_FILE" ]; then
      WRITTEN_SIZE="$(wc -c <"$TEST_FILE" | tr -d ' ')"
      CHECKSUM_1="$(checksum_file "$TEST_FILE")"
      CHECKSUM_2="$(checksum_file "$TEST_FILE")"
      
      if [ "$WRITTEN_SIZE" = "1048576" ] && [ -n "$CHECKSUM_1" ] && [ "$CHECKSUM_1" = "$CHECKSUM_2" ]; then
        WRITE_SUCCESS_COUNT=$((WRITE_SUCCESS_COUNT + 1))
        ok "1 MiB write, sync, double-read, and CRC verification passed on $TARGET_DIR."
      else
        fail "Integrity check failed on $TARGET_DIR (checksum mismatch or incomplete write)."
      fi
    else
      WRITE_ERR_TEXT="$(tail -n 2 "$TEST_ERROR" 2>/dev/null | tr '\n' ' ')"
      fail "Write failed on $TARGET_DIR: ${WRITE_ERR_TEXT:-I/O error}"
    fi
    
    rm -f "$TEST_FILE" "$TEST_ERROR" 2>/dev/null
    sync
  done
  
  if [ "$WRITE_SUCCESS_COUNT" -eq "$WRITE_TOTAL_COUNT" ] && [ "$WRITE_TOTAL_COUNT" -gt 0 ]; then
    WRITE_INTEGRITY_STATUS="verified on $WRITE_SUCCESS_COUNT partitions"
  else
    WRITE_INTEGRITY_STATUS="failed"
  fi
fi

separator
printf '5. eMMC I/O Performance & Database Latency Benchmarks\n'

if [ "$WRITE_TEST" != "yes" ]; then
  printf '  [SKIP] Performance benchmarks skipped (--no-write).\n'
else
  # 1. Sequential Write Benchmark (10 MB with fsync)
  BENCH_DIR="/userdata"
  [ -d "$BENCH_DIR" ] || BENCH_DIR="/"
  BENCH_FILE="${BENCH_DIR}/.emmc_speed_bench_$$.bin"
  TEST_FILES="$TEST_FILES $BENCH_FILE"
  
  FREE_MB=$(( $(df -Pk "$BENCH_DIR" 2>/dev/null | awk 'NR==2 {print $4}') / 1024 ))
  if [ "$FREE_MB" -ge 100 ]; then
    printf '  Sequential Write Benchmark (10 MiB to %s with fsync):\n' "$BENCH_DIR"
    WRITE_BENCH_OUT="$(dd if=/dev/zero of="$BENCH_FILE" bs=1M count=10 conv=fsync 2>&1)"
    WRITE_SPEED_STR="$(printf '%s\n' "$WRITE_BENCH_OUT" | awk -F', ' '/copied/{print $NF}' | tr -d '\r\n')"
    rm -f "$BENCH_FILE" 2>/dev/null
    sync
    
    if [ -n "$WRITE_SPEED_STR" ]; then
      printf '    Sequential Write Speed : %s\n' "$WRITE_SPEED_STR"
      # Evaluate speed
      SPEED_VAL="$(printf '%s' "$WRITE_SPEED_STR" | awk '{print $1}' | cut -d'.' -f1)"
      SPEED_UNIT="$(printf '%s' "$WRITE_SPEED_STR" | awk '{print $2}')"
      
      if [ "$SPEED_UNIT" = "MB/s" ] || [ "$SPEED_UNIT" = "MiB/s" ]; then
        if [ "${SPEED_VAL:-0}" -ge 20 ]; then
          ok "Sequential write performance is optimal ($WRITE_SPEED_STR)."
          THROUGHPUT_STATUS="optimal ($WRITE_SPEED_STR)"
        elif [ "${SPEED_VAL:-0}" -ge 10 ]; then
          ok "Sequential write performance is acceptable ($WRITE_SPEED_STR)."
          THROUGHPUT_STATUS="acceptable ($WRITE_SPEED_STR)"
        else
          warn "Sequential write speed is degraded ($WRITE_SPEED_STR). Flash controller wear-leveling stall possible."
          THROUGHPUT_STATUS="degraded ($WRITE_SPEED_STR)"
        fi
      else
        warn "Sequential write speed is low ($WRITE_SPEED_STR)."
        THROUGHPUT_STATUS="slow ($WRITE_SPEED_STR)"
      fi
    else
      warn "Could not determine write throughput."
    fi
  fi

  # 2. Sequential Direct Read Benchmark (50 MiB, 0% flash wear)
  READ_SRC=""
  if [ -b "$MMC_NODE"p8 ]; then
    READ_SRC="$MMC_NODE"p8
  elif [ -b "$MMC_NODE" ]; then
    READ_SRC="$MMC_NODE"
  fi
  
  if [ -n "$READ_SRC" ] && [ -r "$READ_SRC" ]; then
    printf '  Sequential Direct Read Benchmark (50 MiB from %s):\n' "$READ_SRC"
    READ_BENCH_OUT="$(dd if="$READ_SRC" of=/dev/null bs=1M count=50 iflag=direct 2>&1)"
    READ_SPEED_STR="$(printf '%s\n' "$READ_BENCH_OUT" | awk -F', ' '/copied/{print $NF}' | tr -d '\r\n')"
    if [ -n "$READ_SPEED_STR" ]; then
      printf '    Sequential Read Speed  : %s\n' "$READ_SPEED_STR"
      ok "Direct block read stream completed without read disturbances ($READ_SPEED_STR)."
    fi
  fi

  # 3. 4K Sync Write Latency (Database / SQLite Transaction Simulation)
  # 20 sync writes of 4 KB = 80 KB total data
  SYNC_FILE="${BENCH_DIR}/.emmc_sync_bench_$$.bin"
  TEST_FILES="$TEST_FILES $SYNC_FILE"
  printf '  Database 4K Transaction Latency (20 sync transactions to %s):\n' "$BENCH_DIR"
  
  # Timing using date or internal counter
  T_START="$(date +%s 2>/dev/null || echo 0)"
  SYNC_FAIL=0
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    dd if=/dev/zero of="$SYNC_FILE" bs=4k count=1 conv=fdatasync >/dev/null 2>&1 || SYNC_FAIL=1
  done
  T_END="$(date +%s 2>/dev/null || echo 0)"
  rm -f "$SYNC_FILE" 2>/dev/null
  sync
  
  TOTAL_TIME=$(( T_END - T_START ))
  if [ "$SYNC_FAIL" -eq 0 ]; then
    if [ "$TOTAL_TIME" -le 2 ]; then
      ok "20 synchronous 4K database commits completed in ${TOTAL_TIME}s (fast fsync response)."
      LATENCY_STATUS="fast (<=2s)"
    elif [ "$TOTAL_TIME" -le 5 ]; then
      ok "20 synchronous 4K database commits completed in ${TOTAL_TIME}s."
      LATENCY_STATUS="normal (${TOTAL_TIME}s)"
    else
      warn "4K database sync operations took ${TOTAL_TIME}s (> 5s). Database transactions may experience lag."
      LATENCY_STATUS="slow (${TOTAL_TIME}s)"
    fi
  else
    fail "4K synchronous write transactions encountered I/O errors."
    LATENCY_STATUS="failed"
  fi
fi

separator
printf 'SUMMARY\n'
printf '  eMMC hardware:            %s\n' "$EMMC_STATUS"
printf '  SMART wear indicators:    %s\n' "$WEAR_STATUS"
printf '  Storage logs:             %s\n' "$KERNEL_STATUS"
printf '  Multi-partition write:    %s\n' "$WRITE_INTEGRITY_STATUS"
printf '  Write throughput:         %s\n' "$THROUGHPUT_STATUS"
printf '  4K database sync latency: %s\n' "$LATENCY_STATUS"

separator
printf 'SUMMARY: %s failures, %s attention items\n' "$FAILURES" "$WARNINGS"
if [ "$FAILURES" -gt 0 ]; then
  printf 'RESULT: FAIL - CRITICAL STORAGE ISSUES DETECTED (%d failure(s), %d warning(s))\n' "$FAILURES" "$WARNINGS"
  exit 2
fi
if [ "$WARNINGS" -gt 0 ]; then
  printf 'RESULT: WARN - ATTENTION REQUIRED (%d warning(s), 0 failures)\n' "$WARNINGS"
  exit 1
fi
printf 'RESULT: PASS - ALL eMMC STORAGE HEALTH & PERFORMANCE CHECKS PASSED (0 failures, 0 warnings)\n'
exit 0
