"""Remote-tool integration tests with isolated proc/sys fixtures and fake utilities."""
import csv
import json
import os
from pathlib import Path
import re
import shlex
import struct
import subprocess
import sys
import shutil
import signal
import tarfile
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'scripts/linux'
TOOLS = ['monitor_server_runtime.sh', 'check_ethernet.sh', 'capture_network.sh', 'collect_support_bundle.sh']


class RemoteTools(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='iridi-test-')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.fs = self.base / 'fs'
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.out = self.base / 'out'
        self.out.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        FIXTURE_ROOT=str(self.fs), NO_COLOR='1')
        self.write('/proc/uptime', '100.00 50.00\n')
        self.write('/proc/stat', 'cpu 100 0 100 1000 0 0 0 0 0 0\ncpu0 0\ncpu1 0\n')
        self.write('/proc/meminfo', 'MemTotal: 1024 kB\n')
        self.tool('pidof', '#!/bin/sh\necho 711\n')
        self.tool('ethtool', '#!/bin/sh\nprintf "driver counters for %s\\n" "$*"\n')
        self.tool('ip', '#!/bin/sh\necho "eth0: UP 1000 full"\n')
        self.tool('dmesg', '#!/bin/sh\necho "eth0 Link is Up"\n')
        # Match the HSS tar build: separate gzip exists, tar -z is unsupported.
        real_tar = shutil.which('tar')
        self.tool('tar', '#!/bin/sh\ncase "$1" in *z*) echo "tar -z unsupported" >&2; exit 2 ;; esac\nexec ' + shlex.quote(real_tar) + ' "$@"\n')
        self.tool('sleep', '''#!/bin/sh
root=$FIXTURE_ROOT
n=$(awk '{print int($1)}' "$root/proc/uptime")
printf '%s.00 0.00\n' "$((n+$1))" >"$root/proc/uptime"
printf 'cpu %s 0 100 1000 0 0 0 0 0 0\ncpu0 0\ncpu1 0\n' "$((n+100))" >"$root/proc/stat"
if [ -f "$root/sys/class/net/eth0/statistics/rx_packets" ]; then
 echo 12 >"$root/sys/class/net/eth0/statistics/rx_packets"
 if [ "${ETHER_ERROR:-0}" = 1 ]; then echo 2 >"$root/sys/class/net/eth0/statistics/rx_crc_errors"; fi
 if [ "${ETHER_RESET:-0}" = 1 ]; then echo 0 >"$root/sys/class/net/eth0/statistics/tx_packets"; fi
fi
if [ "${PROCESS_EXIT:-0}" = 1 ]; then rm -f "$root/proc/711/stat"; fi
''')

    def write(self, path, value):
        p = self.fs / path.lstrip('/')
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(value)
        return p

    def tool(self, name, text):
        p = self.bin / name
        p.write_text(text)
        p.chmod(0o755)

    def script(self, name, directory=None):
        directory = directory or self.base
        directory.mkdir(parents=True, exist_ok=True)
        source = (SCRIPTS / name).read_text()
        for path in ['/proc/', '/sys/', '/oem/', '/etc/']:
            source = source.replace(path, str(self.fs) + path)
        # Product paths in data-root candidates are not used when --data-dir is set.
        p = directory / name
        p.write_text(source)
        return p

    def run_tool(self, name, *args, env=None, directory=None):
        p = self.script(name, directory)
        result = subprocess.run(['sh', str(p), '--output-dir', str(self.out), *args],
                                env=env or self.env, text=True, capture_output=True, timeout=8)
        self.assertNotIn('\x1b[', result.stdout)
        matches = re.findall(r'^Artifacts: (.+)$', result.stdout, re.M)
        artifact = Path(matches[0]) if matches else None
        if artifact:
            self.assertEqual(artifact.stat().st_mode & 0o777, 0o700)
            self.assertTrue((artifact / 'audit.log').is_file())
            self.assertEqual(int((artifact / 'exit_code').read_text()), result.returncode)
        return result, artifact

    def ethernet_fixture(self):
        root = '/sys/class/net/eth0/'
        (self.fs/'sys/class/net/eth0/device').mkdir(parents=True, exist_ok=True)
        for name, value in [('type', '1'), ('operstate', 'up'), ('speed', '1000'), ('duplex', 'full'), ('carrier_changes', '0')]:
            self.write(root + name, value)
        fields = 'rx_bytes tx_bytes rx_packets tx_packets rx_errors tx_errors rx_dropped tx_dropped rx_crc_errors rx_frame_errors rx_length_errors rx_over_errors rx_missed_errors tx_carrier_errors'
        for field in fields.split():
            self.write(root + 'statistics/' + field, '10' if field.endswith(('bytes', 'packets')) else '0')

    def process_fixture(self):
        fields = ['0'] * 52
        fields[0] = '711'
        fields[1] = '(iridium worker (test))'
        fields[2] = 'S'
        fields[13] = '100'
        fields[14] = '50'
        fields[21] = '777'
        self.write('/proc/711/stat', ' '.join(fields) + '\n')
        self.write('/proc/711/status', 'Name:\tiridium\nVmRSS:\t1024 kB\nThreads:\t4\n')
        self.write('/proc/711/io', 'read_bytes: 400\nwrite_bytes: 800\n')
        fd = self.fs / 'proc/711/fd'
        fd.mkdir()
        (fd / '0').symlink_to('/dev/null')

    def test_help_and_argument_validation_have_no_artifacts(self):
        for tool in TOOLS:
            for args, expected in [(['--help'], 0), (['--duration'], 2), (['--duration', '0'], 2),
                                   (['--duration', '99999999999999999999999'], 2), (['--unknown'], 2)]:
                with self.subTest(tool=tool, args=args):
                    r = subprocess.run(['sh', str(SCRIPTS/tool), *args], env=self.env, text=True, capture_output=True)
                    self.assertEqual(r.returncode, expected, r.stderr)
                    self.assertNotIn('Artifacts:', r.stdout)

    def test_runtime_csv_and_comm_with_spaces_parentheses(self):
        self.process_fixture()
        self.write('/proc/meminfo', 'MemTotal: 4096 kB\nMemAvailable: 3072 kB\nMemFree: 512 kB\n')
        r, folder = self.run_tool('monitor_server_runtime.sh', '--pid', '711', '--duration', '2', '--interval', '1')
        self.assertEqual(r.returncode, 0, r.stdout+r.stderr)
        rows = list(csv.DictReader((folder/'runtime.csv').read_text().splitlines()))
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0]['cpu_percent_one_core'], 'n/a')
        self.assertEqual(rows[-1]['rss_kib'], '1024')
        self.assertEqual(rows[-1]['open_fds'], '1')
        self.assertEqual(rows[-1]['ram_process_percent'], '25.0')
        self.assertEqual(rows[-1]['ram_system_used_percent'], '25.0')
        self.assertEqual(rows[-1]['ram_total_kib'], '4096')
        self.assertEqual(rows[-1]['ram_available_kib'], '3072')
        self.assertIn('RAM PROC%', r.stdout)
        self.assertIn('RAM ALL%', r.stdout)

    def test_ram_missing_invalid_and_boundary_counters(self):
        from test_hardware_diagnostics import shell_function, run_shell
        function = shell_function((SCRIPTS/'monitor_server_runtime.sh').read_text(), 'memory_percentages')
        meminfo = self.fs/'proc/meminfo'
        function = function.replace('/proc/meminfo', str(meminfo))
        cases = [
            ('MemTotal: 4096 kB\nMemAvailable: 4096 kB\n', '0', '0.0 0.0 4096 4096'),
            ('MemTotal: 4096 kB\nMemAvailable: 0 kB\n', '1024', '25.0 100.0 4096 0'),
            ('MemTotal: 4096 kB\nMemFree: 0 kB\n', '1024', '25.0 n/a 4096 n/a'),
            ('MemTotal: 4096 kB\nMemAvailable: 5000 kB\n', '1024', '25.0 n/a 4096 n/a'),
            ('MemTotal: 0 kB\nMemAvailable: 0 kB\n', '1024', 'n/a n/a n/a n/a'),
            ('MemTotal: 4096 kB\nMemAvailable: 2048 kB\n', 'n/a', 'n/a 50.0 4096 2048'),
            ('', '1024', 'n/a n/a n/a n/a'),
        ]
        for content, rss, expected in cases:
            with self.subTest(content=content, rss=rss):
                meminfo.write_text(content)
                output = run_shell(function+'\nmemory_percentages '+shlex.quote(rss))
                self.assertEqual(output.strip(), expected)

    def test_system_per_core_and_process_cpu_have_distinct_scales(self):
        self.process_fixture()
        self.write('/proc/stat', 'cpu 100 0 100 800 0 0 0 0 0 0\ncpu0 50 0 50 400 0 0 0 0 0 0\ncpu1 50 0 50 400 0 0 0 0 0 0\n')
        # 100 total ticks: 50 busy, 30 idle, 20 iowait. Core0 busy 100%, core1 0%.
        # Process uses 40 ticks: 40% of the machine, 80% of one core.
        self.tool('sleep', '#!' + sys.executable + '\n' + '''import os
from pathlib import Path
root=Path(os.environ['FIXTURE_ROOT'])
(root/'proc/uptime').write_text('101.00 0.00\\n')
(root/'proc/stat').write_text('cpu 140 0 110 830 20 0 0 0 20 0\\ncpu0 90 0 60 400 0 0 0 0 20 0\\ncpu1 50 0 50 430 20 0 0 0 0 0\\n')
p=root/'proc/711/stat';before,rest=p.read_text().rsplit(') ',1)
fields=rest.split();fields[11]=str(int(fields[11])+40)
p.write_text(before+') '+' '.join(fields)+'\\n')
''')
        result, folder = self.run_tool('monitor_server_runtime.sh', '--duration', '1', '--interval', '1')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        rows = list(csv.DictReader((folder/'runtime.csv').read_text().splitlines()))
        self.assertEqual(rows[0]['cpu_system_percent'], 'n/a')
        self.assertEqual(rows[0]['cpu0_percent'], 'n/a')
        self.assertEqual(rows[1]['cpu_system_percent'], '50.0')
        self.assertEqual(rows[1]['cpu0_percent'], '100.0')
        self.assertEqual(rows[1]['cpu1_percent'], '0.0')
        self.assertEqual(rows[1]['cpu_process_capacity_percent'], '40.0')
        self.assertEqual(rows[1]['cpu_percent_one_core'], '80.0')
        self.assertIn('CPU0%', result.stdout)
        self.assertIn('CPU1%', result.stdout)
        self.assertNotIn('  Cores:', result.stdout)

    def test_cpu_counter_resets_zero_delta_and_missing_core_are_unknown(self):
        from test_hardware_diagnostics import shell_function, run_shell
        previous = self.base/'cpu.before'
        current = self.base/'cpu.after'
        previous.write_text('cpu 100 50 10\ncpu0 50 25 5\ncpu1 50 25 5\n')
        function = shell_function((SCRIPTS/'monitor_server_runtime.sh').read_text(), 'cpu_deltas')
        for data in ['cpu 100 50 10\ncpu0 50 25 5\n',
                     'cpu 90 40 5\ncpu0 40 20 2\n',
                     'cpu 120 55 9\ncpu0 60 27 4\n']:
            with self.subTest(data=data):
                current.write_text(data)
                out = run_shell('CPU_LABELS="cpu cpu0 cpu1"\n' + function + '\ncpu_deltas ' +
                                shlex.quote(str(previous))+' '+shlex.quote(str(current)))
                self.assertEqual(dict(line.split() for line in out.splitlines()),
                                 {'cpu':'n/a','cpu0':'n/a','cpu1':'n/a'})

    def test_runtime_process_exit_is_fail_not_silent_reattach(self):
        self.process_fixture()
        env = dict(self.env, PROCESS_EXIT='1')
        r, _ = self.run_tool('monitor_server_runtime.sh', '--duration', '2', '--interval', '1', env=env)
        self.assertEqual(r.returncode, 2)
        self.assertIn('exited or was reused', r.stdout)

    def test_runtime_missing_process_is_fail(self):
        r, _ = self.run_tool('monitor_server_runtime.sh', '--pid', '999')
        self.assertEqual(r.returncode, 2)

    def test_runtime_interrupts_sleep_and_retains_partial_csv(self):
        self.process_fixture()
        (self.bin/'sleep').unlink()
        p = self.script('monitor_server_runtime.sh')
        p.write_text(re.sub(r'monotonic_seconds\(\) \{[^\n]*\}', 'monotonic_seconds() { date +%s; }', p.read_text()))
        process = subprocess.Popen(['sh', str(p), '--duration', '30', '--interval', '20', '--output-dir', str(self.out)],
                                   env=self.env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        try:
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                files = list(self.out.glob('*/runtime.csv'))
                if files and len(files[0].read_text().splitlines()) >= 2:
                    break
                time.sleep(.02)
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=3)
            self.assertEqual(process.returncode, 1, stdout+stderr)
            self.assertIn('partial CSV retained', stdout)
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate()

    def test_ethernet_pass_counter_error_and_reset(self):
        for mode, expected in [({}, 0), ({'ETHER_ERROR':'1'}, 1), ({'ETHER_RESET':'1'}, 1)]:
            with self.subTest(mode=mode):
                self.ethernet_fixture()
                r, folder = self.run_tool('check_ethernet.sh', '--interface', 'eth0', '--duration', '1', env=dict(self.env, **mode))
                self.assertEqual(r.returncode, expected, r.stdout+r.stderr)
                self.assertIn('ETHTOOL DRIVER COUNTERS', (folder/'audit.log').read_text())

    def test_ethernet_missing_interface_and_name_injection(self):
        r, _ = self.run_tool('check_ethernet.sh', '--interface', 'no-such-interface')
        self.assertEqual(r.returncode, 2)
        r, folder = self.run_tool('check_ethernet.sh', '--interface', 'eth0;id')
        self.assertEqual(r.returncode, 2)
        self.assertIsNone(folder)

    def test_project_and_log_discovery_with_spaces_and_no_xml_secrets(self):
        self.ethernet_fixture()
        data = self.base / "data root's directory"
        (data/'Documents').mkdir(parents=True)
        (data/'Logs').mkdir()
        (data/'Documents/irconfig.xml').write_text('''<Config><WMI Hash="DO_NOT_COPY_HASH"/><DataBase Password="DO_NOT_COPY_CONFIG"/><Designs Current="example"><Design Name="example" File="guid/Project.irp" ServerPassword="DO_NOT_COPY_PROJECT"/></Designs></Config>''')
        (data/'Logs/live.txt').write_text('normal event\nPassword=DO_NOT_COPY_LOG\nloading project example\n')
        (data/'Documents/license.xml').write_text('DO_NOT_COPY_LICENSE')
        r, folder = self.run_tool('collect_support_bundle.sh', '--data-dir', str(data), '--duration', '1', '--log-kib', '1', '--max-mb', '4')
        # Standalone collector deliberately reports absent optional siblings.
        self.assertEqual(r.returncode, 1, r.stdout+r.stderr)
        with tarfile.open(folder/'support-bundle.tar.gz') as archive:
            names = archive.getnames()
            text = '\n'.join(archive.extractfile(member).read().decode(errors='replace') for member in archive if member.isfile())
        self.assertIn('Configured current reference: example', text)
        self.assertIn('normal event', text)
        self.assertIn('[REDACTED credential-like line]', text)
        self.assertNotIn('DO_NOT_COPY', text)
        self.assertFalse(any(n.endswith('license.xml') or n.endswith('irconfig.xml') for n in names))
        self.assertLess(int(subprocess.check_output(['du', '-sk', str(folder/'payload')]).split()[0]), 4096)

    def test_complete_bundle_runs_siblings_without_packet_capture(self):
        self.process_fixture()
        self.ethernet_fixture()
        data = self.base/'server-data'
        (data/'Logs').mkdir(parents=True)
        (data/'Logs/live.txt').write_text('Normal application log\n')
        siblings = self.base/'siblings'
        self.script('monitor_server_runtime.sh', siblings)
        self.script('check_ethernet.sh', siblings)
        marker = self.base/'tcpdump-should-not-run'
        self.tool('tcpdump', '#!/bin/sh\ntouch '+shlex.quote(str(marker))+'\nexit 2\n')
        r, folder = self.run_tool('collect_support_bundle.sh', '--data-dir', str(data), '--duration', '1', directory=siblings)
        self.assertEqual(r.returncode, 0, r.stdout+r.stderr)
        manifest = (folder/'payload/manifest.txt').read_text()
        self.assertIn('runtime_exit_code=0', manifest)
        self.assertIn('ethernet_exit_code=0', manifest)
        self.assertFalse(marker.exists())

    def tcpdump_fixture(self):
        self.ethernet_fixture()
        # Capture tests use a real one-second wait and host wall time instead of synthetic /proc uptime.
        (self.bin/'sleep').unlink()
        code = '''import os,signal,struct,sys,time
args=sys.argv[1:]
if '-d' in args:
 if os.environ.get('BPF_BAD')=='1': sys.exit(1)
 print('BPF compiled');sys.exit(0)
if '-r' in args:
 data=open(args[args.index('-r')+1],'rb').read()
 if len(data)<24:sys.exit(1)
 if len(data)>24:print('IP fixture packet')
 sys.exit(0)
path=args[args.index('-w')+1]+'0'
header=struct.pack('<IHHIIII',0xa1b2c3d4,2,4,0,0,128,1)
payload=b'\\0'*60
with open(path,'wb') as f:
 f.write(header)
 if os.environ.get('NO_PACKETS')!='1':f.write(struct.pack('<IIII',1,0,len(payload),len(payload))+payload)
def stop(*_):
 print('1 packets captured',file=sys.stderr);print('0 packets dropped by kernel',file=sys.stderr);sys.exit(0)
signal.signal(signal.SIGINT,stop)
while True:time.sleep(.02)
'''
        self.tool('tcpdump', '#!'+sys.executable+'\n'+code)
        p = self.script('capture_network.sh')
        source = p.read_text()
        source = re.sub(r'monotonic_seconds\(\) \{[^\n]*\}', 'monotonic_seconds() { date +%s; }', source)
        p.write_text(source)
        return p

    def run_capture(self, *args, extra_env=None):
        p = self.tcpdump_fixture()
        r = subprocess.run(['sh', str(p), '--duration', '1', '--output-dir', str(self.out), *args],
                           env=dict(self.env, **(extra_env or {})), text=True, capture_output=True, timeout=6)
        match = re.search('^Artifacts: (.+)$', r.stdout, re.M)
        return r, Path(match[1])

    def test_capture_validates_pcap_and_no_packet_warning(self):
        r, folder = self.run_capture()
        self.assertEqual(r.returncode, 0, r.stdout+r.stderr)
        self.assertTrue(list(folder.glob('capture.pcap*')))
        self.assertIn('1 packets retained', r.stdout)

    def test_capture_empty_is_warn(self):
        r, _ = self.run_capture(extra_env={'NO_PACKETS':'1'})
        self.assertEqual(r.returncode, 1, r.stdout+r.stderr)
        self.assertIn('No matching packets', r.stdout)

    def test_capture_bad_filter_is_fail(self):
        r, _ = self.run_capture('--filter', 'bad', extra_env={'BPF_BAD':'1'})
        self.assertEqual(r.returncode, 2)

    def test_capture_host_must_be_numeric_address(self):
        for value in ['example.com', 'dead.beef', '999.1.2.3', '1.2.3']:
            with self.subTest(host=value):
                result = subprocess.run(['sh', str(SCRIPTS/'capture_network.sh'), '--host', value],
                                        text=True, capture_output=True, env=self.env)
                self.assertEqual(result.returncode, 2)
                self.assertNotIn('Artifacts:', result.stdout)

    def test_capture_filter_never_evaluates_shell_text(self):
        marker = self.base/'injection-would-create-this'
        r, _ = self.run_capture('--filter', 'tcp; touch '+str(marker))
        self.assertEqual(r.returncode, 0, r.stdout+r.stderr)
        self.assertFalse(marker.exists())


if __name__ == '__main__':
    unittest.main()
