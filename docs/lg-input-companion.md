# LG Input Companion

A small menu-bar app that switches an LG monitor's input when one chosen Bluetooth keyboard connects to or disconnects from this Mac. It is separate from MonitorControl: it builds with Command Line Tools only (no Xcode), runs without the MonitorControl app, and does not change MonitorControl's startup behavior.

## Install, status, disable, uninstall

```sh
scripts/install-companion.sh        # build, install, load the per-user LaunchAgent (no sudo)
"$HOME/Library/Application Support/LGInputCompanion/LGInputCompanion.app/Contents/MacOS/LGInputCompanion" --status
"$HOME/Library/Application Support/LGInputCompanion/LGInputCompanion.app/Contents/MacOS/LGInputCompanion" --list
launchctl print "gui/$(id -u)/io.github.dan-shaughnessy.lg-input-companion" | grep state
scripts/uninstall-companion.sh      # remove app and LaunchAgent, keep settings
scripts/uninstall-companion.sh --purge
```

`--status` and `--list` are read-only and never send a monitor command.

| Item | Path |
|---|---|
| App | `~/Library/Application Support/LGInputCompanion/LGInputCompanion.app` |
| Settings | `~/Library/Application Support/LGInputCompanion/config.json` |
| LaunchAgent | `~/Library/LaunchAgents/io.github.dan-shaughnessy.lg-input-companion.plist` |
| Log | `~/Library/Logs/LGInputCompanion.log` |

To pause, uncheck **Automatic Switching** in the menu. To stop it until next login, choose **Quit** (the agent only restarts after a crash). Reinstalling keeps the saved settings.

## Settings

Open the menu-bar keyboard icon → **Settings…**. Every choice is saved to `config.json`:

- **Bluetooth keyboard**: any paired device. Saved choices that are no longer paired stay listed as unavailable. When a new keyboard is chosen while it is connected, its HID vendor and product IDs are saved too and must match later.
- **Monitor**: an external display, identified by alphanumeric serial, vendor ID and EDID product ID. The LG reports a different product ID per port (`0x7845` over HDMI, `0x7847` over USB-C), so the monitor must be selected over the port this Mac uses.
- **Input protocol**: LG alternate (VCP `0xF4`, source `0x50`) or Standard DDC (VCP `0x60`). LG USB is not offered.
- **When connected / When disconnected**: an input, or **Do nothing**.
- **Connect / disconnect delay**: how long the new state must hold before acting. `0` acts as soon as macOS reports the change.
- **Switch automatically**: on or off.

Saving restarts tracking from the current state and sends nothing.

## Behavior

- **Detection.** IOKit matched/terminated notifications for `IOHIDDevice` entries with the keyboard's `DeviceAddress`, plus a 5-second reconciliation poll. Bluetooth LE keyboards appear here; the device is never opened, so no key data is read and no Input Monitoring permission is needed. A device is *connected* when Bluetooth is on, it is paired, and a Bluetooth HID entry with its address and IDs exists. It is *disconnected* when paired and absent. Anything else (Bluetooth off, not paired, query failure, lookalike with the same address but other IDs) is *unknown* and never acts.
- **Edges only.** Launch and every settings change take the current state as a baseline without sending a command; there is no initial synchronization. A command is sent only when the state changes and holds for its delay. A change that reverts first is cancelled.
- **Sleep and Bluetooth power.** On system sleep or Bluetooth power-off, pending work is cancelled and observations are ignored. After wake or power-on, the companion waits 20 seconds, then compares the state with the pre-sleep baseline. A keyboard that drops during sleep and reconnects after wake causes no switch. A keyboard that stays gone after the grace period produces one disconnect edge.
- **Stale work.** Every state change, sleep, power change or settings change invalidates queued commands. Each attempt checks this first, so an older input is never sent after a newer one. A failed write is retried at most twice, 1.5 seconds apart. If the monitor is not found, nothing is queued.
- **Pause.** While paused, edges are logged but not acted on. Resuming does not replay them.
- **Logging.** The log records keyboard name, state changes and command results. It never contains key data.

Write success means the command was sent. The LG does not report its input, so the log cannot confirm a switch.

With 0-second delays, a Bluetooth dropout of any length switches the monitor. If the link drops before macOS posts its sleep notification, a disconnect command can be sent as the Mac goes to sleep. Increase the disconnect delay if that happens. Keychron keyboards also disconnect when they auto-sleep from inactivity, which counts as a disconnect.

## Tests

`scripts/test-input-source.sh` also runs `Tests/CompanionPolicyTests.swift`. It covers baseline-without-action, debounce and bounce cancellation, zero delays, unknown states, sleep/wake and Bluetooth power, other keyboards and lookalikes, display identity per port, settings validation and persistence, bounded retries, and supersession of stale commands. These tests use no hardware.

## Validation on 2026-11-16 (RESML laptop)

M4 Pro MacBook Pro, macOS 26.6.2, Command Line Tools only (Swift 6.3.1), HyperDrive Thunderbolt 3 Mobile Dock HDMI → LG ULTRAGEAR+ HDMI 1 (`601INAR7V264`, product `0x7845`).

- The configured keyboard is the Keychron K5 Max: address `d9-27-29-c0-eb-c9`, HID `3434:0A53`, Bluetooth Low Energy, confirmed from its live registry entry. The also-connected Keychron K10 Pro (`02E5:A1B2`) and G604 mouse are ignored.
- With 10 s / 2 s delays, two full disconnect → USB-C and connect → HDMI 1 cycles were logged at the expected delays, and the user saw the switches.
- With 0 s delays, both edges logged a command in the same second as detection, and the user saw both switches as fast.
- System sleep/wake and Bluetooth power-off were tested with simulated transitions only, not on hardware.
