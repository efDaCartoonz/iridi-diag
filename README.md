# iRidi Diagnostics Scripts

A collection of standalone tools for diagnosing iRidi servers, storage, CAN/Bus77 bus, and
cloud connectivity. The Linux scripts use portable POSIX `sh` and support
BusyBox-based HS Server firmware. The macOS script supports interactive
launch from Finder and CLI. The Windows scripts support the built-in
Windows PowerShell versions found on Windows 7, 10, and 11.

[Русская версия](README_RU.md) | [Bus77 Monitoring Guide](BUS77_MONITORING_GUIDE.md)

---

## Repository layout

- `scripts/linux` — Linux, Debian, and BusyBox-based firmware;
- `scripts/macos` — macOS (interactive launcher and POSIX sh engine);
- `scripts/windows` — Windows 7, Windows 10, and Windows 11.

### Windows

| File | Purpose |
| --- | --- |
| `run_iridi_cloud_windows.cmd` | Double-click launcher with a product menu and automatic logging |
| `check_iridi_cloud_windows_10_11.ps1` | Cloud diagnostics (v1.5) for Windows 10/11 and Windows PowerShell 5.1 / PowerShell 7+ |
| `check_iridi_cloud_windows_7.ps1` | Cloud diagnostics (v1.5) for Windows 7 and Windows PowerShell 2.0 or newer |

### macOS

| File | Purpose |
| --- | --- |
| `run_iridi_cloud_macos.command` | Double-click Finder launcher with a product menu and automatic logging |
| `check_iridi_cloud_macos.sh` | All-in-one cloud diagnostics (v1.5) for macOS with CLI flags and interactive mode |

### Linux and BusyBox

| File | Purpose |
| --- | --- |
| `check_server_health.sh` | Comprehensive server overview (v1.1): hardware serials, edition/firmware version, ports, thermals, RAM, and SMART |
| `check_i3knx.sh` | Application-level checks for i3 KNX cloud resources and Cloud Gate session (v1.5) |
| `check_bus77_home.sh` | Application-level checks for Bus77 Home cloud resources (v1.5) |
| `check_bus77_lite.sh` | Application-level checks for Bus77 Lite cloud resources (v1.5) |
| `check_iridi_pro_ru.sh` | iRidi Pro Cloud checks for RU region (v1.5) |
| `check_iridi_pro_eu.sh` | iRidi Pro Cloud checks for EU region (v1.5) |
| `check_iridi_pro_cn.sh` | iRidi Pro Cloud checks for CN region (v1.5) |
| `check_emmc_health.sh` | eMMC health (v2.1): SMART, multi-partition, inodes, write speed and 4K database latency benchmarks |
| `check_can_bus.sh` | CAN/Bus77 diagnostics (v2.3): controller health, device inventory (`--scan-only`), and JSON export |
| `monitor_can_bus.sh` | **Bus77 Protocol Decoder & Monitor (v2.2)**: real-time packet decoding, Bus Load %, Top Talkers, Ping RTT |

---

## Dual-Stream Architecture: Clean Human UI & Deep Technical Log

All diagnostic scripts employ a **Dual-Stream model**:

1. **Terminal Screen (Human UI):**
   - Clean, readable status dashboard.
   - Colored status indicators `[OK]`, `[ATTENTION]`, `[NOT OK]`.
   - Concise metrics: latency in `ms`, HTTP status, IP addresses, throughput in `MB/s`, temperature in `°C`, eMMC wear in `%`.
   - Zero repetitive noise or raw intermediate dumps.
2. **Technical Audit Log (Log File):**
   - Automatically persisted to a dedicated file (`/tmp/` or `scripts/.../logs/`).
   - Microsecond/second timestamps `[YYYY-MM-DD HH:MM:SS]` for every step.
   - Full HTTP/HTTPS request and response headers (`dump-header`), raw error bodies.
   - Complete dumps of system files (`/proc/cpuinfo`, `/proc/meminfo`, `/oem/hal/ccinfo`, `df -h`, `ss -tulpn`).
   - Raw eMMC registers (`ext_csd`, `cid`, `csd`, `life_time`, `pre_eol_info`).
   - Kernel logs (`dmesg`), interface statistics, and raw CAN dumps (`candump -x -e`).
   - Plain-text format without ANSI escape codes for easy editor viewing and automated parsing.

---

## Result colors and exit codes

Interactive output uses the following status colors:

- green — `[OK]` and `RESULT: PASS`;
- yellow — `[ATTENTION]` and `RESULT: WARN`;
- red — `[NOT OK]` and `RESULT: FAIL`.

Linux and macOS colors are enabled only when output is connected to a terminal. Set `NO_COLOR=1` to disable them.

Exit codes are consistent across all tools:

- `0` — `PASS`: all required checks passed;
- `1` — `WARN`: required checks passed, but warnings were detected;
- `2` — `FAIL`: a required check failed or execution encountered a critical error.

---

## Cloud diagnostics on Windows

Download all three files into the same folder and double-click `run_iridi_cloud_windows.cmd`.

**Windows 10/11 — download with curl.exe (built-in since Windows 10 1803):**

```bat
mkdir "%USERPROFILE%\Desktop\iridi-diag-windows" && cd /d "%USERPROFILE%\Desktop\iridi-diag-windows"
curl.exe -fL -o run_iridi_cloud_windows.cmd         "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/run_iridi_cloud_windows.cmd"
curl.exe -fL -o check_iridi_cloud_windows_10_11.ps1 "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/check_iridi_cloud_windows_10_11.ps1"
curl.exe -fL -o check_iridi_cloud_windows_7.ps1     "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/check_iridi_cloud_windows_7.ps1"
run_iridi_cloud_windows.cmd
```

**Windows 7 — download with certutil.exe:**

```bat
mkdir "%USERPROFILE%\Desktop\iridi-diag-windows"
cd /d "%USERPROFILE%\Desktop\iridi-diag-windows"
certutil.exe -urlcache -split -f "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/run_iridi_cloud_windows.cmd"         run_iridi_cloud_windows.cmd
certutil.exe -urlcache -split -f "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/check_iridi_cloud_windows_10_11.ps1"  check_iridi_cloud_windows_10_11.ps1
certutil.exe -urlcache -split -f "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/windows/check_iridi_cloud_windows_7.ps1"      check_iridi_cloud_windows_7.ps1
run_iridi_cloud_windows.cmd
```

The launcher detects the installed Windows PowerShell version, selects the compatible diagnostic engine, and displays live progress.

PowerShell scripts can also be run directly with `-Product`:

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

Use `-Quality` to run extended packet loss, latency, MTU, and download throughput tests.

---

## Cloud diagnostics on macOS

Download both files into the same folder, then double-click `run_iridi_cloud_macos.command` in Finder:

```sh
mkdir -p ~/Desktop/iridi-diag-macos && cd ~/Desktop/iridi-diag-macos
curl -fsSL -O "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/macos/run_iridi_cloud_macos.command"
curl -fsSL -O "https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/macos/check_iridi_cloud_macos.sh"
chmod +x run_iridi_cloud_macos.command check_iridi_cloud_macos.sh
open .
```

Run directly from Terminal:

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

---

## Cloud diagnostics on Linux

Download and run via `wget`:

```sh
cd /tmp
wget --no-check-certificate -O check_bus77_home.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_bus77_home.sh
sh check_bus77_home.sh
```

Run profiles for other products:

```sh
sh check_i3knx.sh
sh check_bus77_lite.sh
sh check_iridi_pro_ru.sh
sh check_iridi_pro_eu.sh
sh check_iridi_pro_cn.sh
```

### Extended channel quality & stability analysis (`--quality` / `--deep`)

Standard mode runs an express check (10–15 seconds). Use `--quality` (or `-q`) to run deep channel testing:

```sh
sh check_bus77_home.sh --quality
sh check_iridi_pro_ru.sh --quality
```

Extended tests include:
1. **Latency, jitter, and packet loss**: 10 sequential HTTP/HTTPS probes measuring min/avg/max latency, DNS resolution speed, and packet loss %.
2. **Download throughput**: real data transfer benchmark calculating download bandwidth (in KB/s or MB/s).
3. **Cloud Gate burst stability**: 3 rapid sequential TCP handshakes.
4. **Path MTU & packet fragmentation**: ICMP probes at 1500 bytes and 1400 bytes with Don't-Fragment (DF).

---

## Server Health & System Overview (Linux)

Comprehensive health check for iRidi Linux controllers (HS Server, ProAV, UMC, KNX Home Server):

```sh
cd /tmp
wget --no-check-certificate -O check_server_health.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_server_health.sh
sh check_server_health.sh
```

Reported metrics:
- **Hardware Identity**: controller serial, processor serial, board model, kernel/OS version, uptime, and load averages.
- **iRidi Runtime & Services**: server edition (Bus77 Home, iRidi Pro, ProAV), installed `opkg` version, process status (PID, RAM, threads), and listening ports.
- **Thermals & CPU**: SoC/CPU temperature sensors in °C, core count, and frequencies.
- **Memory (RAM)**: total, used, free, available (MB and %).
- **eMMC Storage Wear (SMART)**: chip manufacturer, SLC and MLC/TLC wear %, Pre-EOL status, partition free space, and kernel storage ring buffer error scan.
- **Network & CAN**: Ethernet (`eth0`) state, link speed, IP/MAC, gateway, DNS, and SocketCAN state.

---

## eMMC Flash Storage Diagnostic

Deep diagnostics for built-in eMMC flash storage:

```sh
cd /tmp
wget --no-check-certificate -O check_emmc_health.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_emmc_health.sh
sh check_emmc_health.sh
```

- **Hardware SMART Wear**: manufacturer, manufacturing date, `LIFE_TIME_ESTIMATION` (Type A/B with 10% steps), `PRE_EOL_INFO` status, write-protect flags (`USER_WP`).
- **Partition & Inode Health**: read-write status, free disk space, and inode exhaustion (`df -i`) across `/`, `/userdata`, and `/oem`.
- **Kernel Storage Error Logs**: deep scan for I/O and EXT4 filesystem errors in `dmesg` and `/var/log/messages`.
- **Multi-Partition Write Integrity**: safe 1 MiB write, cache flush (`sync`), double-read, and CRC32 verification on `/` and `/userdata`.
- **Performance Benchmarks**:
  - *Sequential write*: 10 MiB write with `conv=fsync` (MB/s).
  - *Direct block read*: 50 MiB read (`iflag=direct`) with 0% flash wear.
  - *SQLite 4K Commit Latency*: 20 synchronous 4 KB commits with `fdatasync`.

For read-only inspection without writing test files:

```sh
sh check_emmc_health.sh --no-write
```

---

## CAN / Bus77 Diagnostics & Live Traffic Decoder

Two specialized tools for CAN bus and Bus77 networks on HSS and ProAV servers.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        BUS77 / CAN TOOLSET                             │
├───────────────────────────────────┬────────────────────────────────────┤
│         check_can_bus.sh          │         monitor_can_bus.sh         │
│     (Diagnostics & Inventory)     │  (Protocol Decoder & Live Traffic) │
├───────────────────────────────────┼────────────────────────────────────┤
│ • Controller state (can0/can1)    │ • Full Bus77 packet decoding       │
│ • Fast device search (Discovery)  │ • Command & variable interpretation│
│ • Model, serial & firmware read   │ • Device model name substitution   │
│ • 15-sec error counter sample     │ • Bus load calculation (Bus Load %)│
│ • Network passport JSON export    │ • Top talkers ranking table        │
│ • iRidi CAN gateway status check  │ • Device ping & latency (Ping RTT) │
└───────────────────────────────────┴────────────────────────────────────┘
```

---

### 1. Device Inventory & Controller Health (`check_can_bus.sh`)

Inspects SocketCAN state, sends safe read-only System Search (`0x03`) and Device Info (`0x04`) requests, and produces an inventory of connected Bus77 modules.

```sh
cd /tmp
wget --no-check-certificate -O check_can_bus.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_can_bus.sh
sh check_can_bus.sh
```

#### Additional modes:

```sh
# Instant device discovery without 15-second traffic sampling:
sh check_can_bus.sh --scan-only

# Export device inventory to JSON:
sh check_can_bus.sh --scan-only --json

# Passive mode without sending frames:
sh check_can_bus.sh --passive
```

---

### 2. Bus77 Protocol Decoder & Live Monitor (`monitor_can_bus.sh`)

Standalone protocol analyzer (v2.2) that decodes raw 8-byte CAN frames into meaningful Bus77 automation events in real time.

```sh
cd /tmp
wget --no-check-certificate -O monitor_can_bus.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/monitor_can_bus.sh
sh monitor_can_bus.sh
```

#### Key capabilities:

1. **Multi-frame Packet Reassembly**: automatically assembles split Bus77 packets (Start / Middle / End frames) and verifies CRC16 checksums.
2. **Real-Time Command Decoding**:
   - `SetVariable` (`0x05`) — variable changes, relay switching, dimming, status updates.
   - `GetVariable` (`0x06`) — tag/channel value requests.
   - `System Search` (`0x03`) and `Device Info` (`0x04`) — discovery and device passports.
   - `SendEvent`, `Subscribe` / `Unsubscribe`.
3. **Model Name Substitution**: translates raw hex IDs into human-readable model names (e.g. `B77-DIM-4CH`, `B77-REL-8CH`, `FS-V-M-IL-S-IR-BIC`).
4. **LID Conflict Detection**: instantly identifies duplicate Logical IDs across different physical modules.
5. **Bus Load Calculation (Bus Load %)**: measures frame rate (FPS) and percentage utilization of the 125 kbps channel (warnings when > 60%).
6. **Top Talkers Ranking**: summary table of the most active transmitting devices to pinpoint spamming sensors, contact bounce, or feedback loops.

#### Decoded stream preview:

```text
TIME     CAN   DIR  SENDER -> RECEIVER                 | COMMAND / STATUS     | DETAILS
12:34:56 can0  TX   SERVER/GW(LID 70) -> ALL           | REQUEST SetVariable  | variable=316 value=32
12:34:56 can0  RX   LID 11 (B77-DIM-4CH) -> ALL        | REQUEST SetVariable  | variable=315 value=true
12:34:57 can0  RX   LID 03 (B77-SENSOR-T) -> SERVER    | RESPONSE GetVariable | tag=1 (Temperature) value=23.5°C
```

#### Additional modes & filters:

```sh
# 1. Measure device response latency (Ping RTT in ms with packet loss %):
sh monitor_can_bus.sh --ping 2 --count 5

# 2. Filter live stream by device LID:
sh monitor_can_bus.sh --lid 11 --duration 30

# 3. Filter live stream by command name:
sh monitor_can_bus.sh --cmd SetVariable --duration 60

# 4. Display raw CAN hex payloads alongside decoded packets:
sh monitor_can_bus.sh --raw --duration 15

# 5. Completely passive monitoring without initial discovery requests:
sh monitor_can_bus.sh --passive --duration 60
```

For detailed protocol explanations and troubleshooting walkthroughs, refer to the [Bus77 Monitoring Guide](BUS77_MONITORING_GUIDE.md).
