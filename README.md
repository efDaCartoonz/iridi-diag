# iRidi Diagnostics Scripts

A collection of standalone tools for diagnosing iRidi servers, storage, and
cloud connectivity. The Linux scripts use portable POSIX `sh` and support
BusyBox-based HS Server firmware. The macOS script supports interactive
launch from Finder and CLI. The Windows scripts support the built-in
Windows PowerShell versions found on Windows 7, 10, and 11.

[Русская версия](README_RU.md) | [Bus77 Monitoring Guide](BUS77_MONITORING_GUIDE.md)

## Repository layout

- `scripts/linux` — Linux, Debian, and BusyBox-based firmware;
- `scripts/macos` — macOS (interactive launcher and POSIX sh engine);
- `scripts/windows` — Windows 7, Windows 10, and Windows 11.

### Windows

| File | Purpose |
| --- | --- |
| `run_iridi_cloud_windows.cmd` | Double-click launcher with a product menu and automatic logging |
| `check_iridi_cloud_windows_10_11.ps1` | Cloud diagnostics for Windows 10/11 and Windows PowerShell 5.1 |
| `check_iridi_cloud_windows_7.ps1` | Cloud diagnostics for Windows 7 and Windows PowerShell 2.0 or newer |

### macOS

| File | Purpose |
| --- | --- |
| `run_iridi_cloud_macos.command` | Double-click Finder launcher with a product menu and automatic logging |
| `check_iridi_cloud_macos.sh` | All-in-one cloud diagnostics for macOS with CLI flags and interactive mode |

### Linux and BusyBox

| File | Purpose |
| --- | --- |
| `check_server_health.sh` | Comprehensive server overview: hardware serials, edition/firmware version, ports, thermals, RAM, and SMART |
| `check_i3knx.sh` | Application-level checks for i3 KNX cloud resources and an active Cloud Gate session |
| `check_bus77_home.sh` | Application-level checks for Bus77 Home cloud resources |
| `check_bus77_lite.sh` | Application-level checks for Bus77 Lite cloud resources |
| `check_iridi_pro_ru.sh` | iRidi Pro Cloud checks for the RU region |
| `check_iridi_pro_eu.sh` | iRidi Pro Cloud checks for the EU region |
| `check_iridi_pro_cn.sh` | iRidi Pro Cloud checks for the CN region |
| `check_emmc_health.sh` | eMMC health v2.0: SMART, multi-partition, inodes, sequential throughput and 4K database latency benchmarks |
| `check_can_bus.sh` | CAN/Bus77 diagnostics: controller health, device inventory (`--scan-only`), and JSON export |
| `monitor_can_bus.sh` | Bus77 analyzer v2.2: real-time packet decoding, Bus Load %, Top Talkers, Ping RTT, and filters |

## Result colors and exit codes

Interactive output uses the following status colors:

- green — `[OK]` and `RESULT: PASS`;
- yellow — `[ATTENTION]` and `RESULT: WARN`;
- red — `[NOT OK]` and `RESULT: FAIL`.

Linux and macOS colors are enabled only when output is connected to a terminal. Set
`NO_COLOR=1` to disable them. Log files remain plain text and never contain ANSI
color sequences.

Exit codes are consistent across the current tools:

- `0` — `PASS`: required checks passed;
- `1` — `WARN`: the main checks passed, but one or more items require attention;
- `2` — `FAIL`: a required check failed or the tool could not complete safely.

---

## Cloud diagnostics on Windows

Download all three files into the same folder and double-click `run_iridi_cloud_windows.cmd`.

**Windows 10/11 — download with curl.exe (built-in since Windows 10 1803):**

```bat
mkdir "%USERPROFILE%\Desktop\iridi-diag-windows" && cd /d "%USERPROFILE%\Desktop\iridi-diag-windows"
curl.exe -fL -o run_iridi_cloud_windows.cmd      "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/run_iridi_cloud_windows.cmd"
curl.exe -fL -o check_iridi_cloud_windows_10_11.ps1 "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/check_iridi_cloud_windows_10_11.ps1"
curl.exe -fL -o check_iridi_cloud_windows_7.ps1  "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/check_iridi_cloud_windows_7.ps1"
run_iridi_cloud_windows.cmd
```

**Windows 7 — download with certutil.exe:**

```bat
mkdir "%USERPROFILE%\Desktop\iridi-diag-windows"
cd /d "%USERPROFILE%\Desktop\iridi-diag-windows"
certutil.exe -urlcache -split -f "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/run_iridi_cloud_windows.cmd"      run_iridi_cloud_windows.cmd
certutil.exe -urlcache -split -f "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/check_iridi_cloud_windows_10_11.ps1" check_iridi_cloud_windows_10_11.ps1
certutil.exe -urlcache -split -f "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/check_iridi_cloud_windows_7.ps1"     check_iridi_cloud_windows_7.ps1
run_iridi_cloud_windows.cmd
```

The launcher detects the installed Windows PowerShell version, selects the
compatible diagnostic engine, displays live progress, and keeps the window open
after completion. Each run is saved under `logs\` in the same folder with the
product, region, and timestamp in the file name.

The PowerShell scripts can also be run directly with a `-Product` parameter:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\check_iridi_cloud_windows_10_11.ps1 -Product bus77-home
```

Supported parameters:

```powershell
-Product i3knx [-Quality]
-Product bus77-home [-Quality]
-Product bus77-lite [-Quality]
-Product iridi-pro -Region RU [-Quality]
-Product iridi-pro -Region EU [-Quality]
-Product iridi-pro -Region CN [-Quality]
```

Use `-Quality` to run extended packet loss, latency, MTU, and download throughput tests. In interactive mode, the launcher prompts whether to run extended quality analysis.

The Windows 7 version uses the built-in WinHTTP component and explicitly enables
TLS 1.2. If the operating system does not provide TLS 1.2 support, the script
reports a connection error so it can be distinguished from a cloud service
response.

---

## Cloud diagnostics on macOS

Download both files into the same folder, then double-click `run_iridi_cloud_macos.command` in Finder.

```sh
mkdir -p ~/Desktop/iridi-diag-macos && cd ~/Desktop/iridi-diag-macos
curl -fsSL -O "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/macos/run_iridi_cloud_macos.command"
curl -fsSL -O "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/macos/check_iridi_cloud_macos.sh"
chmod +x run_iridi_cloud_macos.command check_iridi_cloud_macos.sh
open .
```

Double-click `run_iridi_cloud_macos.command` in the opened Finder window to launch.
Select i3 KNX, Bus77 Home, Bus77 Lite, or iRidi Pro (RU / EU / CN).

The script can also be run directly from Terminal with a `--product` flag:

```sh
sh check_iridi_cloud_macos.sh --product bus77-home
```

Supported CLI parameters:

```sh
sh check_iridi_cloud_macos.sh --product i3knx [--quality]
sh check_iridi_cloud_macos.sh --product bus77-home [--quality]
sh check_iridi_cloud_macos.sh --product bus77-lite [--quality]
sh check_iridi_cloud_macos.sh --product iridi-pro --region RU [--quality]
sh check_iridi_cloud_macos.sh --product iridi-pro --region EU [--quality]
sh check_iridi_cloud_macos.sh --product iridi-pro --region CN [--quality]
```

Use `--quality` (or `-q`) to run extended latency, jitter, packet loss, throughput, Cloud Gate burst, and MTU tests. In interactive mode, the launcher prompts whether to run extended quality analysis.

Each run automatically writes a log file under `logs/` in the same folder with product name and timestamp.

---

## Cloud diagnostics on Linux

The cloud checks do more than ping a host or open a port. Each script performs
DNS resolution and a real HTTP(S) GET request, reads the response payload, and
reports the actual IP address, documented IP address, HTTP status, content type,
payload size, request time, and retry count. Network failures without an HTTP
response are retried up to three times. A `403` response from protected storage
still confirms application-level reachability.

The terminal shows live progress while a separate log file is created for every
run. A typical file name is:

```text
cloud_bus77_home_SERVER_20260901_153000_1234.log
```

Download and run a script with `wget`:

```sh
cd /tmp
wget --no-check-certificate -O check_bus77_home.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_bus77_home.sh
sh check_bus77_home.sh
```

Run the other product profiles in the same way:

```sh
sh check_i3knx.sh
sh check_bus77_lite.sh
sh check_iridi_pro_ru.sh
sh check_iridi_pro_eu.sh
sh check_iridi_pro_cn.sh
```

Cloud Gate connectivity is verified by an active TCP probe to ports 9088 and 9089.

### Extended quality & stability diagnostic (`--quality` / `--deep`)

Standard mode runs a quick pre-flight check (15–20 seconds). When troubleshooting intermittent drops, latency spikes, or unstable tunnels, run with `--quality` (or `--deep` / `-q`):

```sh
sh check_bus77_home.sh --quality
sh check_iridi_pro_ru.sh --quality
```

Extended mode performs 4 additional stability tests:
1. **Latency, Jitter & Packet Loss**: 10 sequential HTTP/HTTPS probes measuring min/avg/max latency, jitter, DNS resolution speed, and packet drop rate.
2. **Download Throughput**: Real payload transfer test downloading test chunks from the product CDN/storage to measure effective transfer speed (in KB/s or MB/s).
3. **Cloud Gate TCP Burst Stability**: 3 consecutive TCP handshake attempts to verify broker stability and connection reliability under repeated connections.
4. **Path MTU & Frame Fragmentation**: Probes standard 1500-byte and VPN/tunnel-safe 1400-byte ICMP payloads with Don't-Fragment (DF) flag to detect MTU black holes (automatically skipped if ICMP is blocked upstream).

---

## Server health and system overview

A comprehensive diagnostic script for iRidi Linux hardware (HS Server, ProAV, UMC, KNX Home Server). It collects hardware serial numbers, installed server edition and firmware version, active ports, thermal sensor temperatures, CPU/RAM utilization, eMMC flash wear indicators (SMART), and network interfaces.

Download and run:

```sh
cd /tmp
wget --no-check-certificate -O check_server_health.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_server_health.sh
sh check_server_health.sh
```

Reports collected:
- **Hardware Identity**: Controller serial (`/oem/hal/ccinfo` or devicetree), CPU serial, hardware model, kernel and OS version, uptime, load average.
- **iRidi Runtime & Firmware**: Server edition (Bus77 Home, iRidi Pro, ProAV), installed `opkg` package version, binary size/path, process status (PID, RAM, threads), and active listening ports (8888, 8443, 30464, 65534, etc.).
- **Thermal & CPU Health**: SoC/CPU and GPU thermal sensors (°C), CPU core count, and frequency scaling.
- **Memory (RAM)**: Total, used, free, available RAM, and utilization percentage.
- **eMMC Flash Health (SMART)**: Flash chip model, wear estimation indicators (Type A/B), pre-EOL state, filesystem partition sizes and free space, and kernel I/O error checks.
- **Network & CAN**: Ethernet IP/MAC, link speed, default gateway, DNS servers, and CAN bus controller state (`ERROR-ACTIVE` / `ERROR-PASSIVE`).

---

## eMMC diagnostics

Download and run the diagnostic as `root`:

```sh
cd /tmp
wget --no-check-certificate -O check_emmc_health.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_emmc_health.sh
sh check_emmc_health.sh
```

The script performs a thorough, multi-layered storage diagnostic designed specifically for iRidi Linux servers:
- **SMART Wear Indicators**: eMMC model, manufacturer (Samsung, SanDisk, etc.), manufacturing date, serial, `LIFE_TIME_ESTIMATION` (SLC cache & MLC/TLC user area wear in 10% steps), `PRE_EOL_INFO`, write protection registers (`USER_WP`), and sysfs block read-only flags.
- **Multi-Partition & Inodes Health**: Checks all key partitions (`/`, `/userdata`, `/oem`) for mount options (`rw`), free disk space, and inode exhaustion (`df -i`).
- **Kernel & Persistent Storage Error Analysis**: Scans both active kernel buffer (`dmesg`) and persistent syslog (`/var/log/messages`) for I/O errors, block timeouts, and EXT4 filesystem corruption.
- **Multi-Partition Integrity Verification**: Performs controlled 1 MiB write, cache flush (`sync`), double-read, and CRC32 verification on both `/` and `/userdata` (where the SQLite database and logs reside).
- **I/O Throughput & Database Latency Benchmarks**:
  - *Sequential Write Throughput*: 10 MiB write benchmark with `conv=fsync` to measure real-world storage write throughput (MB/s).
  - *Direct Block Read Throughput*: 50 MiB direct sequential read benchmark (`iflag=direct`) measuring read speed without consuming flash endurance (0 wear).
  - *Database 4K Transaction Latency*: 20 synchronous 4K sector database commits with `fdatasync` simulating SQLite database transaction latency.
- **Strict Flash Wear Safety**: Total writes are capped to ~10.1 MB per full diagnostic run (< 0.00006% of drive lifespan), write tests are automatically skipped if partition free space is below 100 MB, and temporary files are immediately cleaned up.

Use read-only mode to collect passive hardware SMART indicators and log scans without writing any test data:

```sh
sh check_emmc_health.sh --no-write
```

The script never writes directly to raw block devices, runs `fsck`, or remounts filesystems. Every run generates a timestamped log file:

```text
emmc_diagnostic_SERVER_20260901_153000_1234.log
```


---

## CAN/Bus77 diagnostics on HSS and ProAV

Two self-contained tools: download only the file you want to run.
No companion script, package installation or interface reconfiguration is needed
when the server already provides `ip`, `candump`, `cansend` and BusyBox awk.

### Device inventory and bus health

```sh
cd /tmp
wget --no-check-certificate -O check_can_bus.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_can_bus.sh &&
sh check_can_bus.sh
```

The diagnostic script (version 2.3) performs:
- **Bus77 Module Discovery**: Identifies all connected devices, reporting their LID, full HWID, model, device name, firmware version, profile number (Firmware ID), and channel/tag counts.
- **CAN Subsystem Health**: Checks controller state (`ERROR-ACTIVE`), bitrate, kernel error counters (`rx_errors`, `tx_errors`, `dropped`), `iRidium Server` gateway status, and takes a 15-second live traffic sample.

#### Additional `check_can_bus.sh` modes:

```sh
# Instant device inventory without waiting for the 15-second traffic sample:
sh check_can_bus.sh --scan-only

# Export structured inventory to JSON:
sh check_can_bus.sh --scan-only --json

# Passive mode without sending active Search/DeviceInfo queries:
sh check_can_bus.sh --passive
```


### Who sends what to whom (Monitoring, Bus Load & Ping)

Read the [Bus77 monitoring guide](BUS77_MONITORING_GUIDE.md) for field explanations,
button/on-off experiments, example messages and interpretation limits.

```sh
cd /tmp
wget --no-check-certificate -O monitor_can_bus.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/monitor_can_bus.sh &&
sh monitor_can_bus.sh
```

The monitor (version 2.2) provides:
1. **LID Conflict Detection**: Detects duplicated Logical IDs across multiple distinct physical devices.
2. **Real-Time Traffic Decoding**: Reassembles CAN frames into Bus77 packets, resolving device models, commands, channels, tags, and variable changes.
3. **Bus Load Calculation**: Computes average frame rate (FPS) and CAN bus bandwidth utilization % (with alerts if load exceeds 60%).
4. **Top Talkers Breakdown**: Device activity ranking table to pinpoint flapping inputs, packet storms, or looped automation scripts.

```text
TIME     CAN   RX/TX  SENDER -> RECEIVER | REQUEST/RESPONSE COMMAND | DETAILS
12:34:56 can0  TX     SERVER/GW(LID 70) -> ALL (broadcast) | REQUEST SetVariable tid=none | variable=316 value=32
12:34:56 can0  RX     LID 11 FS-V-M-IL-S-IR-BIC [C6AF] -> ALL (broadcast) | REQUEST SetVariable tid=none | variable=315 value=true
```

### Advanced Monitoring Options:

```sh
# 1. Test responsiveness and measure round-trip latency to a specific device (Ping RTT in ms):
sh monitor_can_bus.sh --ping 2 --count 5

# 2. Filter live packet stream by Logical ID (LID):
sh monitor_can_bus.sh --lid 11 --duration 30

# 3. Filter live packet stream by command name:
sh monitor_can_bus.sh --cmd SetVariable --duration 60

# 4. Display raw CAN frames alongside decoded packets:
sh monitor_can_bus.sh --raw --duration 15

# 5. Passive mode without active preflight discovery requests:
sh monitor_can_bus.sh --passive --duration 60
```


Both tools default to all detected SocketCAN interfaces. `--duration` controls
the observation time, not discovery. `--passive` suppresses all outgoing
diagnostic requests; identities and firmware profiles will not be read.

By default, discovery sends only one System Search and one Device Info request
per discovered LID. It never changes addresses, channels, firmware or CAN
configuration. Only responding devices can be listed. Run only one diagnostic
or monitor at a time: discovery uses CAN ID `0xFFFE` and LID `254`, aborting if
that identity is observed in the initial sample. Silent address conflicts cannot
be excluded. Incomplete identity data or traffic yields an explicit warning.

Protocol reference: [official BUS77 SDK](https://github.com/iRidium-Mobile/BUS77-SDK).
