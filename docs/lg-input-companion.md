# Bluetooth input automation in MonitorControl

Bluetooth-triggered switching now runs inside the MonitorControl app. There is one menu-bar icon and one settings window; the standalone companion target, entry point and install scripts have been removed from this fork.

Open **Settings → Automation** to select Bluetooth devices, monitor, protocol, connected/disconnected input (or Do nothing), delays and enable state. The original menu retains manual input selection and brightness/volume controls. **Automatic Switching** pauses/resumes automation; **Automation Status** shows per-device, combined, pending and last-command status.

With several devices selected, all connected selects the connected input, all disconnected selects the disconnected input, and mixed or unknown state holds the input. Zero delays act as soon as a change is recognized. Real Bluetooth reconnection and monitor switching still take time. Device addresses and HID vendor/product IDs must be verified; connect a newly selected device once and refresh the list to learn its identity. Saved unavailable devices remain selectable.

## Migration from LG Input Companion

1. Install the signed merged app in `~/Applications/MonitorControl.app` using `scripts/install-monitorcontrol.sh /path/to/MonitorControl.app`. The installer keeps a dated backup of an existing app and leaves the companion running until you are ready.
2. Open MonitorControl. It imports the old `~/Library/Application Support/LGInputCompanion/config.json` into `~/Library/Application Support/MonitorControl/automation.json` only if the new file is absent. The original is preserved; a corrupt new file is reported and never replaced with older settings. The new app needs its own Bluetooth permission. Automation does not need Input Monitoring or Accessibility; MonitorControl's optional media-key controls may separately request Accessibility.
3. In **Settings → Automation**, check the migrated selections and click **Retire Old Companion**. This unloads the exact old per-user LaunchAgent, verifies it is unloaded, and moves its plist and known app bundle to Trash. It keeps the old JSON and log. Automation stays blocked while the old job or process is present, preventing two input controllers. Existing login behavior is carried over through MonitorControl's own login helper when the old LaunchAgent existed; check **General → Start at Login** after migration.
4. Save any changes. Launch, migration, settings save, wake and display reconnect establish a baseline without switching. Verify by making a later real Bluetooth change.

Do not disable Jamf/MDM, remove quarantine flags, or bypass Gatekeeper to install a build. An ad-hoc signed development build is not notarized; use the system's normal approval flow where permitted. Keep the old app/config backups until the merged workflow is confirmed. The separate `lg-input-companion` GitHub repository is unchanged; archiving it requires Dan's agreement.

## Runtime behavior

- Detection uses IOKit HID registry arrival/removal for selected Bluetooth addresses plus five-second reconciliation. HID devices are never opened and no key data is read. Bluetooth power or pairing/query failure, missing identity, or an identity mismatch is unknown and never acts.
- Launch, settings changes, resuming from pause, wake after its 20-second grace period and display reconnect establish a no-action baseline. Only subsequent Bluetooth state changes may switch inputs. Pending work is cancelled by sleep, configuration changes, pause, device changes and display reconfiguration.
- Input writes use MonitorControl's global DDC queue, also used for brightness/volume. Every job captures its configuration; it never waits for the main thread. Failed writes retry at most twice, without blocking brightness work between attempts. Unavailable monitors are not queued for later. The selected monitor must uniquely match serial, vendor and port-specific product.
- Standard DDC, LG alternate and LG USB are supported. LG USB uses the same serial-matched USB transport as the manual selector. Display discovery currently depends on the Apple Silicon display-service mapping.
- Status reports **command sent**, not physical confirmation. The tested LG's input readback is unreliable. With zero delays, transient Bluetooth drops and keyboard idle auto-sleep can count as disconnects. Raise the disconnect delay if necessary.
- New settings are in `~/Library/Application Support/MonitorControl/automation.json`. Runtime status is in the app menu; diagnostic messages also go to process stdout/Console. Pause using the menu toggle. Quit MonitorControl to stop both manual controls and automation.

## Build and validation

Full Xcode is required for MonitorControl's storyboards/assets. This integrated candidate is built for Apple Silicon on macOS 12 or later. With Xcode 27, use the local deployment-target override:

```sh
xcodebuild -project MonitorControl.xcodeproj -scheme MonitorControl \
  -configuration Release -derivedDataPath /tmp/monitorcontrol-integrated-build \
  CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 ARCHS=arm64 build
codesign --force --deep --sign - --timestamp=none \
  /tmp/monitorcontrol-integrated-build/Build/Products/Release/MonitorControl.app
./scripts/test-input-source.sh
```

The hardware-free tests cover original input protocols, byte framing, exact identity and multi-device aggregation; debounce/instant edges, stale work, settings migration/persistence, new wake baselines, bounded retries, shared-queue progress and the real controller's no-action baseline/pause/reconnect lifecycle. The debug-only native UI preview uses synthetic data, isolated settings and an always-false write gate; it does not query Bluetooth or send display commands.

Prior standalone RESML evidence remains valid for the reused HID detection/input transport: user-confirmed K5 Max → HDMI 1 / USB-C switching, zero-delay switching, and K5 Max + EM01 NL all-match switching with mixed-state holds. **The merged app needs a fresh RESML installation and physical acceptance test.** A passing test suite or visual preview is not proof of that migration. Sleep/wake hardware testing remains outstanding.
