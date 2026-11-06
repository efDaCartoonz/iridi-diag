"""Run each script's real eMMC section against isolated sysfs fixtures, never a block device."""
import json
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

from test_hardware_diagnostics import LINUX, shell_function

TOOLS = ('check_emmc_health.sh', 'check_server_health.sh')
HELPERS = ('normalize_hex', 'life_description', 'pre_eol_description',
           'life_defined', 'report_emmc_indicators')


def fixture_script(tool, root, life, pre_eol, *, json_mode=False):
    root = Path(root)
    node = root / 'sys/bus/mmc/devices/mmc1:0001'
    node.mkdir(parents=True, exist_ok=True)
    for key, value in [('type', 'MMC'), ('name', 'ISOCOM'), ('manfid', '0x000004'),
                       ('life_time', life), ('pre_eol_info', pre_eol)]:
        if value is not None:
            (node/key).write_text(value)
    ios = root / 'sys/kernel/debug/mmc1/ios'
    ios.parent.mkdir(parents=True, exist_ok=True)
    ios.write_text('actual clock:\t200000000 Hz\nbus width:\t3 (8 bits)\ntiming spec:\t10 (mmc HS400 enhanced strobe)\n')
    source = (LINUX/tool).read_text()
    standalone = tool == TOOLS[0]
    names = ['log_tech', 'log_tech_file']
    if standalone:
        names += ['read_field', 'normalize_hex', 'manufacturer_name']
        names += list(HELPERS[1:])
        names += ['check_emmc_smart', 'print_summary']
        action = 'check_emmc_smart'
    else:
        names += ['ok', 'warn', 'fail', 'info', 'json_string']
        names += list(HELPERS)
        names += ['check_emmc_and_storage', 'print_summary']
        action = 'check_emmc_and_storage'
    functions = '\n'.join(shell_function(source, name) for name in names)
    functions = functions.replace('/sys/', str(root)+'/sys/')
    # Only the SMART/storage section is executed. Stub unrelated host/kernel commands.
    prelude = '''
export LC_ALL=C NO_COLOR=1
WARNINGS=0; FAILURES=0; WARN_COUNT=0; FAIL_COUNT=0
WRITE_TEST=no
MODEL=fixture; SERIAL=fixture; OS_BUILD_ID=; FIRMWARE_TIMESTAMP=
log_tech_cmd() { log_tech "Optional host command omitted in sysfs fixture"; }
dmesg() { :; }
df() { printf 'Filesystem Size Used Available Use%% Mounted\\nfixture 1G 0 1G 0%% /\\n'; }
'''
    log_file = root/'audit.log'
    prelude += 'LOG_FILE='+shlex.quote(str(log_file))+'\nexec 3>"$LOG_FILE"\n'
    prelude += 'JSON_OUTPUT='+str(int(json_mode))+'\n'
    if json_mode:
        prelude += 'exec 4>&1\nexec 1>&3\n'
    return prelude+functions+'\n'+action+'\nprint_summary\n'


def run_fixture(tool, life, pre_eol, *, json_mode=False):
    with tempfile.TemporaryDirectory(prefix='iridi-emmc-') as directory:
        script = fixture_script(tool, directory, life, pre_eol, json_mode=json_mode)
        result = subprocess.run(['sh', '-c', script], text=True, capture_output=True, timeout=10)
        log = (Path(directory)/'audit.log').read_text()
        return result, log


class EmmcReporting(unittest.TestCase):
    def test_partial_values_are_independent_in_console_and_audit(self):
        for tool in TOOLS:
            for life, expected_a, expected_b in [
                ('0x03 0x00', '20-30% of estimated lifetime used', 'not defined'),
                ('0x00 0x03', 'not defined', '20-30% of estimated lifetime used'),
            ]:
                with self.subTest(tool=tool, life=life):
                    result, log = run_fixture(tool, life, '0x01')
                    self.assertEqual(result.returncode, 1, result.stderr)
                    a, b = life.split()
                    for label, raw, description in [('Life A', a, expected_a), ('Life B', b, expected_b),
                                                    ('Pre-EOL', '0x01', 'Normal (reserve-block condition)')]:
                        self.assertIn(label+': '+raw+' - '+description, result.stdout)
                        self.assertIn(label+": raw='"+raw+"' decoded='"+description+"'", log)
                    self.assertIn('Wear data incomplete', result.stdout)
                    self.assertNotIn('CRITICAL', result.stdout)
                    self.assertIn('does not establish a device failure', result.stdout)
                    self.assertIn('200000000 Hz', result.stdout if tool==TOOLS[0] else log)

    def test_all_lifetime_codes_and_raw_case_are_reported(self):
        for tool in TOOLS:
            for code in range(12):
                raw = f'0x{code:02X}'
                expected = ('not defined' if code==0 else 'estimated lifetime exceeded' if code==11
                            else f'{(code-1)*10}-{code*10}% of estimated lifetime used')
                with self.subTest(tool=tool, code=raw):
                    result, log = run_fixture(tool, raw+' '+raw, '0x01')
                    self.assertIn('Life A: '+raw+' - '+expected, result.stdout)
                    self.assertIn('Life B: '+raw+' - '+expected, result.stdout)
                    self.assertIn("raw='"+raw+"' decoded='"+expected+"'", log)
                    self.assertIn("life_raw='"+raw+' '+raw+"'" if tool==TOOLS[1] else "life='"+raw+' '+raw+"'", log)

    def test_missing_undefined_and_reserved_fields_are_not_zero_wear(self):
        for tool in TOOLS:
            for life, pre, description in [
                ('0x00 0x00', '0x01', 'not defined'),
                (None, None, 'not reported'),
                ('0x03', '0x01', 'not reported'),
                ('0x0c 0xff', '0x04', 'reserved value'),
                ('0x01 0x01', '0x00', 'not defined'),
                ('0x01 0x01', None, 'not reported'),
            ]:
                with self.subTest(tool=tool, life=life, pre=pre):
                    result, log = run_fixture(tool, life, pre)
                    self.assertEqual(result.returncode, 1, result.stdout+result.stderr)
                    self.assertIn(description, result.stdout)
                    self.assertIn(description, log)
                    self.assertIn('Wear data incomplete', result.stdout)
                    self.assertNotIn('within current thresholds', result.stdout)
                    self.assertNotIn('Health: Normal', result.stdout)

    def test_critical_lifetime_and_pre_eol_override_missing_values(self):
        for tool in TOOLS:
            for life, pre in [('0x0b 0x00', '0x01'), ('0x00 0x0b', '0x01'),
                              ('0x0b', None), ('0x00 0x00', '0x03'), ('0xff 0x00', '0x03')]:
                with self.subTest(tool=tool, life=life, pre=pre):
                    result, log = run_fixture(tool, life, pre)
                    self.assertEqual(result.returncode, 2, result.stdout+result.stderr)
                    self.assertIn('CRITICAL', result.stdout)
                    self.assertNotIn('Wear data incomplete', result.stdout)
                    if pre=='0x03':
                        self.assertIn('Urgent (reserve-block condition)', log)

    def test_pre_eol_warning_is_decoded_and_keeps_warn_status(self):
        for tool in TOOLS:
            result, log = run_fixture(tool, '0x01 0x01', '0x02')
            self.assertEqual(result.returncode, 1, result.stdout+result.stderr)
            self.assertIn('Pre-EOL: 0x02 - Warning (reserve-block condition)', result.stdout)
            self.assertIn("raw='0x02' decoded='Warning (reserve-block condition)'", log)

    def test_existing_numeric_thresholds_and_exit_codes_are_unchanged(self):
        # Golden results verified against the committed pre-change scripts.
        # Keep the tools' existing difference at 0x0a explicit.
        standalone_codes = [1,0,0,0,0,0,0,0,0,1,1,2,1]
        server_codes =     [1,0,0,0,0,0,0,0,0,1,2,2,1]
        cases = []
        for code, expected_emmc, expected_server in zip(range(13), standalone_codes, server_codes):
            cases += [(f'0x{code:02x} 0x01', '0x01', expected_emmc, expected_server),
                      (f'0x01 0x{code:02x}', '0x01', expected_emmc, expected_server)]
        cases += [('0x03 0x00','0x01',1,1), ('0x00 0x03','0x01',1,1), (None,None,1,1)]
        cases += [('0x01 0x01',f'0x{code:02x}',expected,expected)
                  for code,expected in enumerate([1,0,1,2,1])]
        cases += [('0x00 0x0b','0x00',2,2), ('0x0b 0x00','0xff',2,2), ('0xff 0xff','0x03',2,2)]
        for tool_index, tool in enumerate(TOOLS):
            for life, pre, emmc_rc, server_rc in cases:
                with self.subTest(tool=tool, life=life, pre=pre):
                    result, _ = run_fixture(tool, life, pre)
                    expected = (emmc_rc,server_rc)[tool_index]
                    self.assertEqual(result.returncode, expected, result.stdout+result.stderr)

    def test_memory_area_labels_and_health_caveat(self):
        for tool in TOOLS:
            result, log = run_fixture(tool, '0x03 0x04', '0x01')
            self.assertEqual(result.returncode, 0)
            for output in [result.stdout, log]:
                self.assertNotIn('A (SLC)', output)
                self.assertNotIn('B (User)', output)
                self.assertIn('manufacturer-defined', output)
                self.assertIn('not damaged-cell percentages or a health guarantee', output)

    def test_json_has_independent_raw_and_decoded_fields(self):
        result, log = run_fixture(TOOLS[1], '0x03 0x00', '0x01', json_mode=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data['emmc']['life_a'], {'raw':'0x03','description':'20-30% of estimated lifetime used'})
        self.assertEqual(data['emmc']['life_b'], {'raw':'0x00','description':'not defined'})
        self.assertEqual(data['emmc']['pre_eol']['raw'], '0x01')
        self.assertEqual(data['exit_code'], 1)
        self.assertIn("EMMC Life A: raw='0x03' decoded='20-30%", log)


if __name__=='__main__':
    unittest.main()
