# DDC input selector

This fork adds a native **Input Source** submenu for each hardware-DDC external display. Inputs remain separate when brightness sliders are combined, and are available with brightness/volume sliders hidden. Apple, virtual and dummy displays do not get an input selector.

## Use

1. Quit the stock MonitorControl app before launching this build; they share its bundle identifier and settings.
2. Open the menu-bar app and choose **[display name] — Input Source**.
3. Choose an HDMI or DisplayPort input. USB-C video often shares a DisplayPort input number; assignments vary by monitor.
4. If a compatible LG ignores standard commands, choose **Input Protocol → LG alternate**, then choose the input again. Changing the protocol alone sends no switch command.

The protocol and last requested input are saved separately for each display using MonitorControl's existing preference identity. Inputs are **never restored or automatically switched** at startup, wake or reconnection. The source list contains common assignments, not detected ports. Unsupported ports may do nothing.

Standard mode uses VCP `0x60` and host source address `0x51`. LG alternate uses VCP `0xF4` and host source address `0x50`, with HDMI 1/2 at `0x90`/`0x91` and DP/USB-C candidates at `0xD0`–`0xD2`. No other factory/service controls are exposed. These assignments come from the [ddcutil LG input-switching documentation](https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors); not every LG supports them.

Only a validated standard Get VCP reply sets a checkmark. An accepted write means **command sent**, not a confirmed switch. LG alternate readback is not attempted. Failed writes offer connection/protocol recovery guidance. Input operations share the global serial DDC queue; queued work is invalidated on sleep/reconfiguration and cannot deadlock upstream's main-thread synchronous reads.

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
- No actual input switch or switch-back was tested. Intel transport is compiled but has no hardware validation. Computer-use inspection exposed only the app's invisible gamma helper; live menu appearance remains unverified.
