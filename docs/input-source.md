# DDC input selector

This fork adds a native **Input Source** submenu for each supported external display. Inputs remain separate when brightness sliders are combined, and are available with brightness/volume sliders hidden. Apple, virtual and dummy displays do not get an input selector.

## Use

1. Quit the stock MonitorControl app before launching this build; they share its bundle identifier and settings.
2. Open the menu-bar app and choose **[display name] — Input Source**.
3. Choose the input. When an exactly matched LG USB control interface is available on Apple Silicon, **LG USB** is the default for displays without a saved protocol. It offers HDMI 1, HDMI 2, DisplayPort and USB-C.
4. If a compatible LG ignores standard commands, choose **Input Protocol → LG alternate**, then choose the input again. Changing the protocol alone sends no switch command. **LG USB** is also available here for a matching USB control connection.

The protocol and last requested input are saved separately for each display using MonitorControl's existing preference identity. Inputs are **never restored or automatically switched** at startup, wake or reconnection. The source list contains common assignments, not detected ports. Unsupported ports may do nothing.

Standard mode uses VCP `0x60` and host source address `0x51`. LG alternate uses VCP `0xF4` and host source address `0x50`, with HDMI 1/2 at `0x90`/`0x91` and DP/USB-C candidates at `0xD0`–`0xD2`. No other factory/service controls are exposed. These assignments come from the [ddcutil LG input-switching documentation](https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors); not every LG supports them.

Only a validated standard Get VCP reply sets a checkmark. An accepted write means **command sent**, not a confirmed switch. LG alternate and LG USB readback are not used to confirm input. On the tested LG, standard readback remains `0x0F` even while HDMI 1 is visibly active. Failed writes offer connection/protocol recovery guidance. Input operations share the global serial DDC queue; queued work is invalidated on sleep/reconfiguration and cannot deadlock upstream's main-thread synchronous reads.

## LG USB control

The tested LG requires its USB HID-to-I2C interface (`043E:9A8A`, usage page `0xFF00`), sending a 64-byte report whose DDC payload starts `50 04 03 F4`. The length/protocol byte is `0x04`, **not** the `0x84` used over video DDC. Both the transport and framing matter. The report wraps only input-source writes, with HDMI 1 `0x90` and USB-C `0xD1` confirmed on the connected LG ULTRAGEAR+.

The app correlates the HID device's serial with the selected display's alphanumeric serial from the existing Apple Silicon display-service match. It rejects empty, different or ambiguous serials and the other UltraGear HID interface (`0xFF01`). It never opens the monitor's serial/debug port, and sends no firmware or memory commands. USB mode is currently discovered on Apple Silicon only. Existing saved protocol choices take precedence over the USB default.

The USB bridge layout and protocol class were independently checked against [the original LG USB implementation](https://github.com/shinyquagsire23/lg_display_manager/blob/c49e8749c1c98f113ef0f6039e473730bda7bcc1/display_manager.py). That reference also contains unrelated, firmware-specific memory patches; none are executed or included in this fork.

Some monitors stop accepting DDC commands from an inactive connection. Use the monitor's input buttons, or software on the other computer, to return. Input selection does not separately route USB peripherals. Disable upstream automatic updates in Settings when using this fork: an upstream release will replace the custom feature.

## Build and test

Xcode is required. With Xcode 27, upstream's macOS 10.14 deployment target is too old for the SDK. Use a local override (this fork preserves upstream compatibility settings):

```sh
xcodebuild -project MonitorControl.xcodeproj -scheme MonitorControl \
  -configuration Release -derivedDataPath /tmp/monitorcontrol-build \
  CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 ARCHS=arm64 build
```

Run hardware-independent protocol, packet, readback, cancellation and native AppKit menu tests:

```sh
./scripts/test-input-source.sh
```

Tests use a fake display; they never send monitor commands. The built application is at `/tmp/monitorcontrol-build/Build/Products/Release/MonitorControl.app`. A local build is not notarized; sign it for local use before launch. Do not run the stock and fork builds together.

## Validation on 2026-11-16

- Debug and Release builds passed with the macOS 12 deployment-target override on Apple Silicon. SwiftFormat and SwiftLint were not installed; their optional build phases warned and skipped. Existing deprecated-API warnings remain.
- Protocol/packet checks cover the distinct standard/LG source addresses, checksums, high bytes, valid and unsupported/unrelated/corrupt replies, and queued-session invalidation.
- Native menu tests cover read/unknown/busy/unavailable states, protocol persistence, correct LG command routing, and no false confirmation after sending a request.
- A read-only probe compiled from the production `Arm64DDC.swift` and `DDCInputSource.swift` matched the connected LG ULTRAGEAR+ and returned standard input `0x000F`, max `0x0012`. The user reports a USB-C connection; USB-C labels cannot establish the DDC number.
- Initial standard and LG alternate writes over video DDC were accepted by macOS but did not visibly switch the monitor (user confirmed). USB bridge writes with `0x84` framing also left readback unchanged. USB bridge LG input writes with `0x04` framing successfully switched to HDMI 1 and back to USB-C (both visually confirmed by the user). This explains why transport-only write success is insufficient.
- Regression tests first reproduced the framing error (`0x84` generated versus `0x04` expected), then passed after the correction. Tests cover the exact 64-byte report/checksum, serial/interface matching, default selection and the LG USB menu route.
- HDMI through a dock behaves differently from the USB-C video route. On an M4 Pro MacBook Pro (macOS 26.6.2) connected through a HyperDrive Thunderbolt 3 Mobile Dock's HDMI port to the same LG's HDMI 1, the LG USB interface is not visible (no `043E` USB device), so the menu defaults to Standard DDC. The production `Arm64DDC.write` sent **LG alternate** `0xF4` = `0xD1` and the LG switched to USB-C, then `0xF4` = `0x90` over the now-inactive HDMI link and it switched back to HDMI 1 (both visually confirmed by the user). On this route choose **Input Protocol → LG alternate** once; the choice is saved per display. The HDMI EDID reports product `0x7845`; the USB-C route reports `0x7847`. Standard input writes were not tried over HDMI.
- Over that HDMI route, reads that use upstream's request checksum (seed `0x6E` without the `0x51` source byte) return capabilities-string fragments instead of a VCP reply, so upstream brightness reads fail there. The spec checksum (`0x6E ^ 0x51`) returns valid replies: brightness `100/100`, input `0x0F` (max `0x12`). Input writes already use the spec checksum.
- The isolated production USB writer switched to HDMI 1 without the diagnostic read commands (user visually confirmed); its return-to-USB-C write was sent afterward. The diagnostic USB writer had already completed a user-confirmed round trip. This is tested separately from the native menu. Intel has no hardware validation. Computer-use inspection exposed only the app's invisible gamma helper; live menu appearance remains unverified.

## Automatic switching

To switch inputs when a chosen Bluetooth keyboard connects or disconnects, see [LG Input Companion](lg-input-companion.md).
