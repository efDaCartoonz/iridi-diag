"""Offline regression cases. Run: python3 -m unittest discover -s tests -v."""
import os
import json
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LINUX = ROOT / 'scripts/linux'


def shell_function(source, name):
    match = re.search(r'^' + re.escape(name) + r'\(\) ([{(])\n.*?^[})]\n', source, re.M | re.S)
    if not match:
        raise AssertionError('Function not found: ' + name)
    return match.group()


def run_shell(script):
    return subprocess.run(['sh', '-c', script], text=True, capture_output=True, timeout=5, check=True).stdout


class HardwareTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.server = (LINUX / 'check_server_health.sh').read_text()

    def write(self, path, content):
        target = self.root / path.lstrip('/')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        return target

    def rtc(self, battery=None, offset=0, date_present=True):
        self.write('/sys/class/rtc/rtc0/name', 'test-rtc\n')
        if date_present:
            self.write('/sys/class/rtc/rtc0/date', '2023-11-14\n')
            self.write('/sys/class/rtc/rtc0/time', '22:13:20\n')
        self.write('/sys/class/rtc/rtc0/since_epoch', str(1700000000 + offset))
        if battery is not None:
            self.write('/sys/class/rtc/rtc0/device/battery_low', battery)
        function = shell_function(self.server, 'check_rtc_health')
        for path in ['/sys/class/rtc', '/proc/driver/rtc', '/etc/localtime']:
            function = function.replace(path, str(self.root) + path)
        return run_shell('''
WARN_COUNT=0; FAIL_COUNT=0
ok() { printf 'OK: %s\n' "$*"; }
info() { printf 'INFO: %s\n' "$*"; }
warn() { WARN_COUNT=$((WARN_COUNT+1)); printf 'WARN: %s\n' "$*"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); printf 'FAIL: %s\n' "$*"; }
log_tech() { :; }; log_tech_file() { :; }; log_tech_cmd() { :; }
date() { if [ "$*" = '-u +%s' ]; then echo 1700000000; else command date "$@"; fi; }
''' + function + '\ncheck_rtc_health\nprintf "COUNTS %s %s\\n" "$WARN_COUNT" "$FAIL_COUNT"')

    def test_rtc_unknown_battery_is_not_healthy(self):
        out = self.rtc()
        self.assertIn('battery state is unknown', out)
        self.assertNotIn('Battery: OK', out)
        self.assertIn('COUNTS 1 0', out)

    def test_rtc_clear_flag_does_not_claim_retention_test(self):
        out = self.rtc('0')
        self.assertIn('retention not tested', out)
        self.assertIn('COUNTS 0 0', out)

    def test_rtc_low_battery_fails(self):
        self.assertIn('COUNTS 0 1', self.rtc('1'))

    def test_rtc_invalid_battery_warns(self):
        self.assertIn('COUNTS 1 0', self.rtc('invalid'))

    def test_rtc_unreadable_date_warns(self):
        out = self.rtc('0', date_present=False)
        self.assertIn('clock operation is unverified', out)
        self.assertIn('COUNTS 1 0', out)

    def test_rtc_both_offset_directions(self):
        for offset in [18014, -18014, 61, -61]:
            with self.subTest(offset=offset):
                self.assertIn('COUNTS 1 0', self.rtc('0', offset))

    def test_rtc_tolerance_boundary(self):
        for offset in [-60, 60]:
            with self.subTest(offset=offset):
                self.assertIn('COUNTS 0 0', self.rtc('0', offset))

    def serial_helpers(self):
        return '\n'.join(shell_function(self.server, n) for n in
                         ['hal_serial_port', 'serial_port_roles', 'detect_serial_ports']).replace(
                             '/oem/hal', str(self.root / 'hal'))

    def test_hal_symlink_and_text_map_and_deduplicate(self):
        hal = self.root / 'hal'
        hal.mkdir()
        (hal / '485_port').symlink_to('/dev/null')
        (hal / '232_port').write_text('/dev/null\r\n')
        out = run_shell(self.serial_helpers() + '\nserial_port_roles /dev/null\ndetect_serial_ports')
        self.assertIn('RS-485 (/dev/null)', out)
        self.assertIn('RS-232 (/dev/null)', out)
        self.assertEqual(out.splitlines().count('/dev/null'), 1)

    def test_hal_fifo_and_character_device_are_never_read(self):
        hal = self.root / 'hal'
        hal.mkdir()
        os.mkfifo(hal / 'fifo_port')
        (hal / 'knx_port').symlink_to('/dev/zero')
        out = run_shell(self.serial_helpers() + '\nhal_serial_port ' + shlex.quote(str(hal / 'fifo_port')) +
                        '\nhal_serial_port ' + shlex.quote(str(hal / 'knx_port')))
        self.assertEqual(out.strip(), '/dev/zero')

    def test_hal_broken_or_non_device_map_ignored(self):
        hal = self.root / 'hal'
        hal.mkdir()
        (hal / '485_port').symlink_to('/dev/iridi-no-such-port')
        (hal / '232_port').write_text('/tmp/not-a-port\n')
        self.assertEqual(run_shell(self.serial_helpers() + '\nserial_port_roles /dev/null'), '')

    def test_standalone_serial_helpers_match(self):
        serial = (LINUX / 'check_serial_ports.sh').read_text()
        for name in ['hal_serial_port', 'serial_port_roles', 'detect_serial_ports']:
            self.assertEqual(shell_function(self.server, name), shell_function(serial, name))

    def test_firmware_metadata_is_data_not_shell(self):
        marker = self.root / 'should-not-exist'
        self.write('/etc/os-release', 'BUILD_ID="$(touch ' + str(marker) + ')"\n')
        self.write('/timestamp', 'built at 2026-05-20 12:34:56\n')
        function = shell_function(self.server, 'check_hardware_identity')
        for path in ['/oem', '/sys', '/etc', '/usr/lib', '/timestamp', '/proc']:
            function = function.replace(path, str(self.root) + path)
        out = run_shell('log_tech() { :; }; log_tech_file() { :; }\n' + function + '\ncheck_hardware_identity')
        self.assertIn('$(touch ', out)
        self.assertIn('built at 2026-05-20', out)
        self.assertFalse(marker.exists())

    def test_json_summary_matches_exit_status_and_escapes_strings(self):
        functions = '\n'.join(shell_function(self.server, n) for n in ['json_string', 'print_summary'])
        model = 'HS "test"\\model\nnext\tline'
        for warnings, failures, expected in [(0, 0, 'PASS'), (1, 0, 'WARN'), (0, 1, 'FAIL')]:
            with self.subTest(status=expected):
                script = ('exec 4>&1; exec 1>/dev/null\nlog_tech() { :; }\n' + functions +
                          '\nJSON_OUTPUT=1\nMODEL=' + shlex.quote(model) +
                          '\nSERIAL=test\nLOG_FILE=test.log\nOS_BUILD_ID=\nFIRMWARE_TIMESTAMP=\n' +
                          f'WARN_COUNT={warnings}\nFAIL_COUNT={failures}\nprint_summary')
                result = subprocess.run(['sh', '-c', script], text=True, capture_output=True, timeout=5)
                data = json.loads(result.stdout)
                self.assertEqual(data['status'], expected)
                self.assertEqual(data['exit_code'], result.returncode)
                self.assertEqual(data['model'], model)
                self.assertIsNone(data['rtc']['offset_seconds'])

    def emmc(self, life='0x01 0x01', pre_eol='0x01', debugfs=True):
        source = (LINUX / 'check_emmc_health.sh').read_text()
        node = '/sys/bus/mmc/devices/mmc2:0001/'
        for name, value in [('type', 'MMC'), ('name', 'test-flash'),
                            ('life_time', life), ('pre_eol_info', pre_eol)]:
            self.write(node + name, value)
        # A different host represents an SD card and must not be selected.
        self.write('/sys/bus/mmc/devices/mmc0:0001/type', 'SD')
        if debugfs:
            self.write('/sys/kernel/debug/mmc2/ios',
                       'actual clock:\t200000000 Hz\nbus width:\t3 (8 bits)\ntiming spec:\t10 (mmc HS400 enhanced strobe)\n')
        functions = '\n'.join(shell_function(source, n) for n in
                              ['read_field', 'normalize_hex', 'manufacturer_name',
                               'life_description', 'check_emmc_smart'])
        functions = functions.replace('/sys/', str(self.root) + '/sys/')
        return run_shell('''
WARNINGS=0; FAILURES=0
log_tech() { :; }; log_tech_file() { :; }; log_tech_cmd() { :; }
''' + functions + '\ncheck_emmc_smart\nprintf "COUNTS %s %s\\n" "$WARNINGS" "$FAILURES"')

    def test_emmc_selects_mmc_host_not_sd(self):
        out = self.emmc()
        self.assertIn('eMMC bus (mmc2): clock 200000000 Hz', out)
        self.assertIn('COUNTS 0 0', out)

    def test_emmc_missing_debugfs_does_not_hide_smart(self):
        out = self.emmc(debugfs=False)
        self.assertIn('bus parameters unavailable', out)
        self.assertIn('Health: Normal', out)

    def test_emmc_unknown_wear_is_not_normal(self):
        out = self.emmc('', '')
        self.assertIn('Wear status unknown', out)
        self.assertNotIn('Health: Normal', out)
        self.assertIn('COUNTS 1 0', out)

    def test_emmc_critical_wear_takes_precedence(self):
        out = self.emmc('0x00 0x0B', '0x03')
        self.assertIn('CRITICAL', out)
        self.assertIn('COUNTS 0 1', out)

    def test_emmc_no_write_skips_benchmarks(self):
        source = (LINUX / 'check_emmc_health.sh').read_text()
        out = run_shell('WRITE_TEST=no\ndd() { echo UNEXPECTED_WRITE; }\n' +
                        shell_function(source, 'check_storage_performance') + '\ncheck_storage_performance')
        self.assertIn('skipped', out)
        self.assertNotIn('UNEXPECTED_WRITE', out)


class Bus77Values(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = (LINUX / 'monitor_can_bus.sh').read_text()
        helpers = []
        for name in ['hx', 'pow2', 'bit', 'bxor', 'crcstep', 'uint', 'raw', 'clean']:
            helpers.append(re.search(r'^function ' + name + r'\(.*$', source, re.M).group())
        helpers.append(re.search(r'^function value\(.*?^}\n', source, re.M | re.S).group())
        cls.awk = '\n'.join(helpers)

    def decode(self, data):
        program = self.awk + '''
BEGIN {
 n=split(hex,a," "); for(i=1;i<=n;i++)bytes[i-1]=hx(a[i]);
 print value(0,n); print value_ok; print value_end;
}
'''
        result = subprocess.run(['awk', '-v', 'hex=' + data.hex(' '), program],
                                text=True, capture_output=True, timeout=5, check=True)
        lines = result.stdout.splitlines()
        return lines[0], int(lines[1]), int(lines[2])

    def test_boolean_and_absent_numeric(self):
        for data, expected in [(b'\x81', 'true'), (b'\x01', 'false'), (b'\x07', '0')]:
            with self.subTest(data=data):
                self.assertEqual(self.decode(data), (expected, 1, 1))

    def test_signed_float_string_array(self):
        for data, expected in [(bytes.fromhex('82ff'), '-1'),
                               (bytes.fromhex('880000803f'), '1'),
                               (bytes.fromhex('8c0300616263'), '"abc"'),
                               (bytes.fromhex('8f020000ff'), 'bytes[00 FF]')]:
            with self.subTest(data=data):
                self.assertEqual(self.decode(data), (expected, 1, len(data)))

    def test_sdk_time_optional_date_and_time_words(self):
        for flags in [1, 2, 3]:
            date_word = (2026 << 2) | (11 << 16) | (3 << 20) | flags
            time_word = (13 << 2) | (19 << 7) | (5 << 13) | (123 << 19) | flags
            body = (date_word.to_bytes(4, 'little') if flags & 1 else b'') + (
                time_word.to_bytes(4, 'little') if flags & 2 else b'')
            data = b'\x8e' + body
            expected = 'TIME(' + ('2026-11-03' if flags & 1 else '') + (
                ' ' if flags == 3 else '') + ('13:19:05.123' if flags & 2 else '') + ')'
            with self.subTest(flags=flags):
                self.assertEqual(self.decode(data), (expected, 1, len(data)))

    def test_absent_and_truncated_time(self):
        self.assertEqual(self.decode(b'\x0e'), ('TIME(empty)', 1, 1))
        self.assertEqual(self.decode(bytes.fromhex('8e03000000'))[1], 0)
        self.assertEqual(self.decode(bytes.fromhex('8e0200'))[1], 0)

    def test_reserved_pointer_remains_unsupported(self):
        self.assertEqual(self.decode(b'\x8d\0\0\0\0')[1], 0)

    def test_truncated_values_are_not_decoded_as_valid(self):
        for value in ['87', '8c030061', '8f020000', '880000']:
            with self.subTest(value=value):
                self.assertEqual(self.decode(bytes.fromhex(value))[1], 0)

    def test_crc16_modbus_known_vector(self):
        program = self.awk + '\nBEGIN {s="123456789";c=65535;for(i=1;i<=9;i++)c=crcstep(c,48+substr(s,i,1));printf "%04X\\n",c}'
        out = subprocess.run(['awk', program], text=True, capture_output=True, check=True).stdout
        self.assertEqual(out.strip(), '4B37')


if __name__ == '__main__':
    unittest.main()
