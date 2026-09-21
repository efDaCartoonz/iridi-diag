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
| `check_i3knx.sh` | Application-level checks for i3 KNX cloud resources and an active Cloud Gate session |
| `check_bus77_home.sh` | Application-level checks for Bus77 Home cloud resources |
| `check_bus77_lite.sh` | Application-level checks for Bus77 Lite cloud resources |
| `check_iridi_pro_ru.sh` | iRidi Pro Cloud checks for the RU region |
| `check_iridi_pro_eu.sh` | iRidi Pro Cloud checks for the EU region |
| `check_iridi_pro_cn.sh` | iRidi Pro Cloud checks for the CN region |
| `check_emmc_health.sh` | eMMC health, root write path, overlay, and kernel error diagnostics |
| `check_can_bus.sh` | Device inventory (HWID, model, name, firmware/profile), then CAN health |
| `monitor_can_bus.sh` | Named sender-to-receiver Bus77 messages, commands, values and route summaries |
| `scan_bus77_devices.sh` | Read-only active Bus77 discovery with model, HWID, firmware, and channel counts |

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
-Product i3knx
-Product bus77-home
-Product bus77-lite
-Product iridi-pro -Region RU
-Product iridi-pro -Region EU
-Product iridi-pro -Region CN
```

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
sh check_iridi_cloud_macos.sh --product i3knx
sh check_iridi_cloud_macos.sh --product bus77-home
sh check_iridi_cloud_macos.sh --product bus77-lite
sh check_iridi_cloud_macos.sh --product iridi-pro --region RU
sh check_iridi_cloud_macos.sh --product iridi-pro --region EU
sh check_iridi_cloud_macos.sh --product iridi-pro --region CN
```

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

---

## eMMC diagnostics

Download and run the diagnostic as `root`:

```sh
cd /tmp
wget --no-check-certificate -O check_emmc_health.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/check_emmc_health.sh
sh check_emmc_health.sh
```

The script reports the eMMC model, manufacturer, `LIFE_TIME`, `PRE_EOL_INFO`,
`USER_WP`, block-device read-only state, root filesystem, relevant kernel errors,
and the complete root write path. On overlay systems it also reports the
`upperdir`, `workdir`, backing filesystem, mount mode, free space, and inode use.

By default, it creates a temporary 1 MiB file directly under `/`, runs `sync`,
reads the file twice, compares checksums, and removes the file. This verifies the
actual write path through the root filesystem or overlay. Use the read-only mode
to collect passive information without creating the test file. Because write
capability is then unverified, the result is WARN rather than PASS:

```sh
sh check_emmc_health.sh --no-write
```

The script never writes directly to the block device, runs `fsck`, or remounts a
filesystem. A `PASS` result confirms the checks performed during that run; it
does not rule out intermittent faults or replace a full-device endurance test.

Every run creates a plain-text log such as:

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

The short diagnostic (version 2.2) shows device cards once, before bus health.
The monitor (version 2.1) also repeats them after observation.
Each `BUS DEVICES` card includes model, name, HWID, firmware version
and profile. Unavailable discovery data is explicitly reported.
The download commands replace old scripts instead of creating `.1` copies;
check `Script version: 2.2` for the short diagnostic in the report header.

The report starts with the responding devices: LID, full HWID, model, device
name, firmware version and **firmware profile number (Firmware ID)**.
Then it reports CAN controller state, bitrate, historical errors, new errors
and dropped frames, RX/TX activity and server gateway settings.
The health observation lasts 15 seconds, after discovery has finished.

### Who sends what to whom

Read the [Bus77 monitoring guide](BUS77_MONITORING_GUIDE.md) for field explanations,
button/on-off experiments, example messages and interpretation limits.

```sh
cd /tmp
wget --no-check-certificate -O monitor_can_bus.sh https://raw.githubusercontent.com/efDaCartoonz/iridi-diag/main/scripts/linux/monitor_can_bus.sh &&
sh monitor_can_bus.sh
```

The monitor first reads device identities, then listens passively for 60 seconds.
It reassembles CAN frames into Bus77 packets and displays:

```text
TIME     CAN   RX/TX  SENDER -> RECEIVER | REQUEST/RESPONSE COMMAND | DETAILS
12:34:56 can0  TX     SERVER/GW(LID 0) -> LID 2 DM-306PS | REQUEST GetChannelValue tid=42 | channel=123
12:34:56 can0  RX     LID 2 DM-306PS [464E] -> SERVER/GW(LID 0) | RESPONSE GetChannelValue tid=42 | channel=123 value=42
```

This is an illustrative format, not a claim that these exact commands are active
on every bus. `RX/TX` is relative to the server, and `ALL (broadcast)` means no
individual recipient. `S3:LID 0` identifies segment 3, local address 0;
`SERVER/GW` denotes the local transmission path, which can forward upstream
clients rather than originate every command. The monitor decodes supported channel, tag and variable
IDs and values. Unknown payloads remain hex; partial messages, unsupported
formats and CRC failures are marked explicitly. A model name is not inferred
from an unknown device address. Channel names and engineering units are not
inferred without the corresponding device descriptions.

A route summary and bus counters follow the live stream. Requests are cyan,
responses green and error notices red/yellow on a color-capable terminal.
A plain-text log is saved automatically. Logs contain device identities and bus
values; review them before sharing. Session-token and firmware-stream payloads
are hidden.

### Options and safety

```sh
sh check_can_bus.sh --interface can0 --duration 30
sh monitor_can_bus.sh --interface can1 --duration 300
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

`scan_bus77_devices.sh` remains available as an optional inventory-only tool
for compatibility; neither of the two main tools requires it as a separate file.
Protocol reference: [official BUS77 SDK](https://github.com/iRidium-Mobile/BUS77-SDK).
