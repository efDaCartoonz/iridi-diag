# Reading the Bus77 monitor

This guide explains the output of `scripts/linux/monitor_can_bus.sh`, including
what to look for while pressing buttons or switching a load on and off.
It describes the current tool, not every possible Bus77 device implementation.

[Русская версия](BUS77_MONITORING_GUIDE_RU.md) | [Main README](README.md)

## 1. Capture a controlled sequence

Download the monitor and observe one interface for five minutes:

```sh
cd /tmp
wget --no-check-certificate -O monitor_can_bus.sh https://raw.githubusercontent.com/efDaCartoonz/irididiag/main/scripts/linux/monitor_can_bus.sh &&
sh monitor_can_bus.sh --interface can0 --duration 300
```

The download replaces an older copy. The script first requests device identities;
wait for **Live packet exchange** before starting your actions. The 300-second
observation begins after discovery. During observation, the monitor only listens.
Do not run another diagnostic/scanner at the same time. Use `--passive` to skip
identity requests entirely; model names will then generally be unavailable.

1. Leave the system untouched for 15–30 seconds to see its normal background traffic.
2. Note the displayed monitor time and perform one ordinary, safe action: press
   a button, release it, or switch a known light using its normal controls.
3. Wait 5–10 seconds before the next action. Record press and release separately;
   short presses, long presses and repeated presses may produce different events.
4. Repeat the same action two or three times, then test its opposite (on/off).
5. Let the capture finish and keep the file named after **Log saved:**, together
   with your action notes. The log is plain text; terminal colors are not stored.

Use normal operating controls only. This procedure does not require disconnecting
CAN wires, changing termination/bitrate, cutting device power or manipulating
mains wiring. If power is intentionally removed from a device, record it separately
from switching its output off: those are different experiments.

Example action notes (fill in your own times and observations):

| Monitor time | Action | Physical result |
| --- | --- | --- |
| 12:34:10 | Briefly pressed hallway button 1 | Light turned on |
| 12:34:11 | Released button 1 | Light stayed on |
| 12:34:20 | Pressed button 1 again | Light turned off |

The monitor displays the server's clock when it decodes a message, to one-second
resolution. This is not a precise hardware timestamp or a latency measurement.
Several messages can share the same displayed time.

## 2. Identify the devices

The **BUS DEVICES** cards contain identity data requested at the start of the run:

| Field | Meaning |
| --- | --- |
| Model | Reported device model |
| Device name | Name stored in the device; it may be generic or duplicated |
| HWID | Hardware identifier used to distinguish individual devices |
| Firmware version | Installed firmware version |
| Firmware profile | Firmware ID/profile number, not a version or a health score |
| LID | Local Bus77 address |
| CAN device ID | Technical CAN sender identifier, not the full HWID |

The monitor repeats these cards at the end for convenience. They are a snapshot,
not a second discovery: a card does not prove the device remained online throughout
the run. Devices connected later may appear by address without a model name.
Only devices that returned valid identity data are included in the cards.

## 3. Read one message

Illustrative example — the numbers below are not a map of your installation:

```text
12:34:10 can0 TX SERVER/GW(S3:LID 0) -> LID 2 DM-306PS | REQUEST GetChannelValue tid=42 | channel=123
12:34:10 can0 RX LID 2 DM-306PS [464E] -> SERVER/GW(S3:LID 0) | RESPONSE GetChannelValue tid=42 | channel=123 value=42
```

| Part | How to read it |
| --- | --- |
| `can0` | CAN interface carrying this exchange |
| `TX` / `RX` | Transmitted / received relative to the server, not the physical load |
| `SERVER/GW` | Local transmission path; the server may be forwarding another client's command |
| `S3:LID 0` | Segment 3, local address 0 — not device number 768 |
| `LID 2 DM-306PS [464E]` | Local address, known model, and hexadecimal CAN device ID |
| `->` | Sender to recipient |
| `ALL (broadcast)` | No individual recipient; does not confirm that everybody received or acted on it |
| `REQUEST` / `RESPONSE` | Protocol request / response; not necessarily a user action |
| `tid=42` | Transaction identifier to help match a nearby response to its request |
| `tid=none` | Optional transaction ID was omitted; not automatically an error |
| `channel=123 value=42` | Reported channel identifier and value; purpose and units are not inferred |

Match a transaction using the interface, endpoints, command, nearby time and TID,
not TID alone: identifiers can repeat. Without TID, timing and direction are only
supporting evidence, particularly if multiple similar requests overlap.

## 4. What the common commands mean

| Command | Interpretation |
| --- | --- |
| `Ping` | Availability check; a reply proves protocol communication, not load operation |
| `Search`, `DeviceInfo` | Discovery and identity requests; often diagnostic/configuration traffic |
| `SetVariable` | Publishes/sets a global variable value; may be a button event, sensor update or automation |
| `GetVariable` | Requests a global variable value |
| `SetChannelValue` | Requests a control-channel value change; check the subsequent response and physical result |
| `GetChannelValue` | Reads a control-channel value; repeated reads may be routine polling |
| `SetTagValue`, `GetTagValue` | Writes/reads a feedback tag value; the tag's actual meaning needs its description |
| `GetChannels`, `GetTags` | Requests channel/tag information, not necessarily a change in state |
| `GetChannelDescription`, `GetTagDescription` | Requests descriptions; the current monitor does not turn all such payloads into friendly names |

The monitor decodes common Boolean, integer, floating-point and string values.
Some other types remain hex. `true/false` or `1/0` does not universally mean
on/off: a value might represent an edge, status flag, alarm or inverted input.

## 5. Relate traffic to a button or switch

An illustrative broadcast:

```text
12:34:10 can0 RX LID 5 FS-BT6-OLED [6789] -> ALL (broadcast) | REQUEST SetVariable tid=none | variable=500 value=true
12:34:11 can0 RX LID 5 FS-BT6-OLED [6789] -> ALL (broadcast) | REQUEST SetVariable tid=none | variable=500 value=false
```

If these changes consistently follow press and release in your action notes,
variable 500 is a **candidate** for that button's event. This alone does not prove
which light it controls. A receiver may act directly on a broadcast, so there
need not be a separate server-to-actuator command for every action.

Look for this evidence chain, without assuming every stage must be visible:

1. **Input:** a repeatable message/value change from the button device.
2. **Control:** a related variable or control-channel command to an actuator.
3. **Reported state:** a related response or feedback value, if configured.
4. **Physical result:** the actual light/output changes as expected.

A response labelled `acknowledgement` means the decoder saw a response without
payload; it is not proof that a lamp illuminated. A feedback value may itself be
a commanded state rather than a measurement. Device/project documentation is
needed to establish that distinction.

Record discoveries as candidates until checked against the project:

| Observed action | Source LID/HWID | Command and ID | Values | Confidence |
| --- | --- | --- | --- | --- |
| Button press/release | Fill in | e.g. `SetVariable`, 500 | true/false | Repeated correlation; function not yet confirmed |

Do not label a numeric value as temperature, CO2, brightness or a room name
without the corresponding mapping and units. The script does not automatically
learn those meanings while you press buttons.

## 6. When the output looks unusual

| Observation | What it does and does not establish |
| --- | --- |
| Mostly Ping requests/replies | Background availability checks; not proof of button or actuator operation |
| No new message after a press | Could be local-only logic, another interface, an unconfigured input or unsupported traffic; not proof of a dead button |
| Repeated matching event after each press | Good correlation; confirm the project binding before assigning a function |
| Request without a visible reply | Check broadcasts, capture boundaries and optional replies before concluding a device failed; the tool has no automatic response-timeout analysis |
| `ERROR data=...` | Protocol error flag; the numeric error payload needs interpretation in context |
| `CRC mismatch` | Integrity check failed for the assembled packet; content is not decoded. Capture/reassembly gaps as well as communication issues must be considered |
| `unfinished packets` | Capture ended with incomplete data; can happen at an observation boundary |
| `MORE (message fragment)` | Part of a multi-message sequence; the tool does not interpret the whole sequence as one application value |
| `UNKNOWN_0x...`, `ENCRYPTED`, unsupported type, or hex data | Decoder limitation/unsupported content, not by itself a failed device |
| `payload hidden` | Intentional suppression of selected sensitive/control data, not missing reception |

CAN controller **ERROR-ACTIVE is the normal operating state**, despite its name.
ERROR-WARNING/ERROR-PASSIVE warrant investigation; BUS-OFF means the controller
has stopped participating due to errors. Distinguish historical counters from
new errors/drops during this run. A historical warning alone does not establish
an ongoing fault.

The route summary counts decoded Bus77 packets, while RX/TX counters count CAN
frames. A packet can span several frames, so these numbers need not match.
`PASS` means the checks performed passed, not that every project function works;
`WARN` requires reading the stated reason; `FAIL` means a required check failed
or could not run, not necessarily that hardware needs replacement.

## 7. Keep enough context for analysis

Keep the full log, script version, selected interface, action times, physical
results and relevant device/channel mappings. Redact unnecessary identifiers,
values and other sensitive information before sharing. Some sensitive payloads
are hidden by the tool, but logs are **not guaranteed to be secret-free**.

This guide does not replay or send control commands. No server or device settings
need to be changed to collect a normal monitoring log.

See also: [tool instructions and safety notes](README.md#canbus77-diagnostics-on-hss-and-proav).
