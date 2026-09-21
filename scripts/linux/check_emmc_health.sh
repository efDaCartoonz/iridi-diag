#!/bin/sh

# Safe eMMC diagnostics for iRidi HS/ProAV/UMC and Linux servers.
# By default, the script writes a controlled 1 MiB test file to the root
# filesystem, runs sync, verifies two reads, and removes the temporary file.
# Output is displayed live and saved to a separate log file.
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
      /\[NOT OK\]|RESULT: FAIL/ { printf "\033[31m%s\033[0m\n", $0; next }
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

SCRIPT_VERSION=1.3

WRITE_TEST=yes
[ "${1:-}" = "--no-write" ] && WRITE_TEST=no

WARNINGS=0
FAILURES=0
TEST_FILE=""
TEST_ERROR=""
EMMC_STATUS="not detected"
BLOCK_STATUS="not determined"
WEAR_STATUS="unavailable"
KERNEL_STATUS="not checked"
ROOT_WRITE_STATUS="not performed"
ROOT_LAYER_STATUS="not determined"

cleanup() {
  [ -n "$TEST_FILE" ] && rm -f "$TEST_FILE"
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

mount_record_for_path() {
  awk -v path="$1" '
    {
      mount_point = $2
      matches = 0
      if (mount_point == "/") {
        matches = 1
      } else if (path == mount_point || index(path, mount_point "/") == 1) {
        matches = 1
      }
      if (matches && length(mount_point) > best_length) {
        best_length = length(mount_point)
        record = $1 "|" $2 "|" $3 "|" $4
      }
    }
    END { print record }
  ' /proc/mounts 2>/dev/null
}

printf 'eMMC and root storage diagnostics\n'
printf 'Script version: %s\n' "$SCRIPT_VERSION"
printf 'Started: %s\n' "$(date 2>/dev/null || echo unknown)"
printf 'Device: %s\n' "$(hostname 2>/dev/null || echo unknown)"
printf 'Log file: %s\n' "${IRIDI_EMMC_LOG_FILE:-not set}"
printf 'Platform model: %s\n' "$(tr -d '\000' </proc/device-tree/model 2>/dev/null || echo unknown)"
printf 'Kernel: %s\n' "$(uname -a 2>/dev/null)"
printf 'Write test: %s\n' "$WRITE_TEST"

separator
printf '1. eMMC identification and wear indicators\n'

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
    WEAR_STATUS="partially available through sysfs"
  fi
  printf '  Sysfs device: %s\n' "${MMC_DEVICE##*/}"
  printf '  Block device: %s\n' "${MMC_NODE:-not determined}"
  printf '  eMMC model: %s\n' "${MMC_NAME:-not determined}"
  printf '  Manufacturer: %s (%s)\n' "$(manufacturer_name "$MMC_MANFID")" "${MMC_MANFID:-no data}"
  printf '  Manufacturing date: %s\n' "${MMC_DATE:-no data}"
  printf '  Serial number: %s\n' "${MMC_SERIAL:-no data}"
  printf '  LIFE_TIME A: %s - %s\n' "${MMC_LIFE_A:-no data}" "$(life_description "$MMC_LIFE_A")"
  printf '  LIFE_TIME B: %s - %s\n' "${MMC_LIFE_B:-no data}" "$(life_description "$MMC_LIFE_B")"
  printf '  PRE_EOL_INFO: %s - %s\n' "${MMC_PRE_EOL:-no data}" "$(pre_eol_description "$MMC_PRE_EOL")"

  case "$(normalize_hex "$MMC_PRE_EOL")" in
    0x01) ok "PRE_EOL_INFO is normal." ;;
    0x02) warn "PRE_EOL_INFO indicates that reserved blocks are being consumed." ;;
    0x03) fail "PRE_EOL_INFO indicates a critical eMMC condition." ;;
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
printf '  Note: mmcblk*boot0 and boot1 normally report ro=1; this is expected for boot areas.\n'

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
  printf '  EXT_CSD LIFE_TIME A/B: %s / %s\n' "${EXT_LIFE_A:-not determined}" "${EXT_LIFE_B:-not determined}"
  printf '  EXT_CSD PRE_EOL: %s\n' "${EXT_PRE_EOL:-not determined}"
  case "$(normalize_hex "$USER_WP")" in
    0x00) ok "USER_WP=0x00: write protection is not enabled for the user area." ;;
    "") warn "USER_WP could not be read from EXT_CSD." ;;
    *) warn "USER_WP is non-zero; the write-protection bits require interpretation." ;;
  esac
else
  warn "The mmc utility is unavailable; the script is using the available sysfs fields."
fi

separator
printf '2. Root filesystem\n'
ROOT_SOURCE="$(awk '$2=="/" {print $1; exit}' /proc/mounts 2>/dev/null)"
ROOT_FS="$(awk '$2=="/" {print $3; exit}' /proc/mounts 2>/dev/null)"
ROOT_OPTIONS="$(awk '$2=="/" {print $4; exit}' /proc/mounts 2>/dev/null)"
ROOT_REAL_SOURCE="$(mount 2>/dev/null | awk '$2=="on" && $3=="/" {print $1; exit}')"
printf '  Source: %s\n' "${ROOT_REAL_SOURCE:-${ROOT_SOURCE:-not determined}}"
printf '  Filesystem: %s\n' "${ROOT_FS:-not determined}"
printf '  Mount options: %s\n' "${ROOT_OPTIONS:-not determined}"
df -h / 2>/dev/null | sed 's/^/  /'
case ",${ROOT_OPTIONS}," in
  *,rw,*) ROOT_RW=yes; ok "The root filesystem is mounted read-write." ;;
  *) ROOT_RW=no; fail "The root filesystem is not mounted read-write." ;;
esac

if [ "$ROOT_FS" = "overlay" ]; then
  OVERLAY_UPPER="$(printf '%s\n' "$ROOT_OPTIONS" | tr ',' '\n' | sed -n 's/^upperdir=//p' | head -n 1)"
  OVERLAY_WORK="$(printf '%s\n' "$ROOT_OPTIONS" | tr ',' '\n' | sed -n 's/^workdir=//p' | head -n 1)"
  printf '  Overlay upperdir: %s\n' "${OVERLAY_UPPER:-not determined}"
  printf '  Overlay workdir: %s\n' "${OVERLAY_WORK:-not determined}"
  if [ -z "$OVERLAY_UPPER" ] || [ -z "$OVERLAY_WORK" ]; then
    ROOT_LAYER_STATUS="overlay without upperdir or workdir"
    fail "The writable overlay upperdir or workdir could not be determined."
  elif [ ! -d "$OVERLAY_UPPER" ] || [ ! -d "$OVERLAY_WORK" ]; then
    ROOT_LAYER_STATUS="overlay directories unavailable"
    fail "The overlay upperdir or workdir is missing or inaccessible."
  else
    OVERLAY_RECORD="$(mount_record_for_path "$OVERLAY_UPPER")"
    OVERLAY_SOURCE="$(printf '%s' "$OVERLAY_RECORD" | cut -d '|' -f 1)"
    OVERLAY_MOUNT_POINT="$(printf '%s' "$OVERLAY_RECORD" | cut -d '|' -f 2)"
    OVERLAY_FS="$(printf '%s' "$OVERLAY_RECORD" | cut -d '|' -f 3)"
    OVERLAY_OPTIONS="$(printf '%s' "$OVERLAY_RECORD" | cut -d '|' -f 4)"
    printf '  Upperdir backing device: %s\n' "${OVERLAY_SOURCE:-not determined}"
    printf '  Upperdir mount point: %s\n' "${OVERLAY_MOUNT_POINT:-not determined}"
    printf '  Upperdir filesystem: %s\n' "${OVERLAY_FS:-not determined}"
    printf '  Upperdir mount options: %s\n' "${OVERLAY_OPTIONS:-not determined}"
    df -h "$OVERLAY_UPPER" 2>/dev/null | sed 's/^/  /'
    if df -i "$OVERLAY_UPPER" >/dev/null 2>&1; then
      printf '  Inode usage:\n'
      df -i "$OVERLAY_UPPER" 2>/dev/null | sed 's/^/  /'
    else
      printf '  Inode usage: not supported by this firmware.\n'
    fi
    case ",${OVERLAY_OPTIONS}," in
      *,rw,*)
        ROOT_LAYER_STATUS="overlay on ${OVERLAY_SOURCE:-unknown device}, rw"
        ok "The overlay upperdir backing filesystem is mounted read-write."
        ;;
      *,ro,*)
        ROOT_LAYER_STATUS="upperdir backing filesystem is read-only"
        fail "The physical block may be writable, but the overlay upperdir backing filesystem is mounted read-only."
        ;;
      *)
        ROOT_LAYER_STATUS="upperdir mount mode not determined"
        warn "The overlay upperdir backing mount mode could not be determined."
        ;;
    esac
  fi
else
  ROOT_LAYER_STATUS="direct ${ROOT_FS:-unknown filesystem} on ${ROOT_SOURCE:-unknown source}"
  printf '  Overlay: not in use; writes go directly to the root filesystem.\n'
fi

separator
printf '3. Kernel errors since boot\n'
KERNEL_PATTERN='buffer i/o error|blk_update.*i/o error|print_req_error.*i/o error|i/o error.*mmcblk|ext4-fs.*error|remounting filesystem read-only|mmc.*(timed out|timeout|i/o error)|filesystem error|journal.*abort'
KERNEL_ERRORS="$(dmesg 2>/dev/null | grep -Ei "$KERNEL_PATTERN")"
KERNEL_ERROR_COUNT="$(printf '%s\n' "$KERNEL_ERRORS" | sed '/^$/d' | wc -l | tr -d ' ')"
printf '  Critical log entries found: %s\n' "${KERNEL_ERROR_COUNT:-0}"
if [ "${KERNEL_ERROR_COUNT:-0}" -gt 0 ] 2>/dev/null; then
  KERNEL_STATUS="errors found"
  printf '%s\n' "$KERNEL_ERRORS" | tail -n 60 | sed 's/^/  /'
  fail "The kernel log contains signs of storage or filesystem errors."
else
  KERNEL_STATUS="no errors found"
  ok "No critical I/O, timeout, or EXT4 errors were found."
fi

separator
printf '4. Controlled write test on the root filesystem\n'
if [ "$WRITE_TEST" != "yes" ]; then
  ROOT_WRITE_STATUS="skipped (--no-write)"
  warn "The write test was disabled with --no-write; write capability is unverified."
  printf '  [SKIP] The write test was disabled with --no-write.\n'
elif [ "$ROOT_RW" != "yes" ]; then
  ROOT_WRITE_STATUS="not possible: root is not read-write"
  fail "The write test cannot run because the root filesystem is not read-write."
else
  FREE_KB="$(df -Pk / 2>/dev/null | awk 'NR==2 {print $4}')"
  printf '  Free space before test: %s KiB\n' "${FREE_KB:-not determined}"
  if [ "${FREE_KB:-0}" -lt 4096 ] 2>/dev/null; then
    ROOT_WRITE_STATUS="skipped: insufficient space"
    fail "Less than 4 MiB is free; the write test was skipped."
  else
    TEST_FILE="/server-diag-emmc-test-$$.bin"
    TEST_ERROR="$(mktemp /tmp/server-diag-emmc-test.XXXXXX 2>/dev/null)"
    if [ -z "$TEST_ERROR" ]; then
      TEST_ERROR="/dev/null"
      warn "Could not create a private temporary error file; write-test diagnostics may be incomplete."
    fi
    umask 077
    printf '  Temporary file: %s\n' "$TEST_FILE"
    dd if=/dev/urandom of="$TEST_FILE" bs=4096 count=256 2>"$TEST_ERROR"
    WRITE_RC=$?
    sync
    if [ "$WRITE_RC" -eq 0 ] && [ -f "$TEST_FILE" ]; then
      WRITTEN_SIZE="$(wc -c <"$TEST_FILE" | tr -d ' ')"
      CHECKSUM_1="$(checksum_file "$TEST_FILE")"
      CHECKSUM_2="$(checksum_file "$TEST_FILE")"
      printf '  Bytes written: %s\n' "${WRITTEN_SIZE:-0}"
      printf '  Checksum after sync: %s\n' "${CHECKSUM_1:-unavailable}"
      printf '  Checksum on second read: %s\n' "${CHECKSUM_2:-unavailable}"
      if [ "$WRITTEN_SIZE" = "1048576" ] && [ -n "$CHECKSUM_1" ] && [ "$CHECKSUM_1" = "$CHECKSUM_2" ]; then
        ROOT_WRITE_STATUS="successful"
        ok "The 1 MiB write, sync, and second read completed successfully."
      else
        ROOT_WRITE_STATUS="verification failed"
        fail "The file size or checksum did not match after the write."
      fi
    else
      ROOT_WRITE_STATUS="write failed"
      WRITE_ERROR_TEXT="$(tail -n 3 "$TEST_ERROR" 2>/dev/null | tr '\n' ' ')"
      fail "Writing to the root filesystem failed: ${WRITE_ERROR_TEXT:-unknown error}"
    fi
    rm -f "$TEST_FILE" "$TEST_ERROR"
    sync
    if [ -e "$TEST_FILE" ]; then
      fail "The temporary test file could not be removed."
    else
      ok "The temporary test file was removed."
      TEST_FILE=""
      TEST_ERROR=""
    fi
  fi
fi

separator
printf 'SUMMARY\n'
printf '  eMMC: %s\n' "$EMMC_STATUS"
printf '  Main block: %s\n' "$BLOCK_STATUS"
printf '  Wear indicators: %s\n' "$WEAR_STATUS"
printf '  Root write layer: %s\n' "$ROOT_LAYER_STATUS"
printf '  Kernel errors: %s\n' "$KERNEL_STATUS"
printf '  Write test on /: %s\n' "$ROOT_WRITE_STATUS"
case "$ROOT_WRITE_STATUS" in
  "write failed"|"verification failed"|"not possible: root is not read-write")
    if [ "$BLOCK_STATUS" = "writable" ]; then
      printf '  Layer diagnosis: The kernel does not mark the eMMC as read-only, but writes through the root filesystem or overlay fail.\n'
      printf '  Most likely problem area: overlay, filesystem, free space, inodes, or mount options.\n'
    fi
    ;;
esac
if [ "$FAILURES" -eq 0 ] && [ "$ROOT_WRITE_STATUS" = "successful" ] && [ "$KERNEL_STATUS" = "no errors found" ]; then
  printf '  Conclusion: the current write and read tests work, and no critical errors were detected.\n'
  if [ "$WEAR_STATUS" = "unavailable" ]; then
    printf '  Limitation: this firmware does not expose the remaining eMMC life estimate.\n'
  fi
elif [ "$FAILURES" -gt 0 ]; then
  printf '  Conclusion: an error was detected; the storage device or filesystem requires analysis.\n'
else
  printf '  Conclusion: the diagnostic is incomplete; review the attention items above.\n'
fi

separator
printf 'SUMMARY: %s failures, %s attention items\n' "$FAILURES" "$WARNINGS"
if [ "$FAILURES" -gt 0 ]; then
  printf 'RESULT: FAIL - NOT OK: signs of a fault or an inability to write were detected.\n'
  exit 2
fi
if [ "$WARNINGS" -gt 0 ]; then
  printf 'RESULT: WARN - ATTENTION REQUIRED: no critical errors were found, but some data needs review.\n'
  exit 1
fi
printf 'RESULT: PASS - OK: available eMMC indicators are normal, no kernel errors were found, and writes work.\n'
printf 'Important: the file test does not replace a full storage test and cannot rule out intermittent or hidden faults.\n'
exit 0
