# Two-Mac desk audio candidate

This branch depends on MonitorControl PR #1 at acd0dc90e5005a9c5ae1055401634e3ab86ff37b.
It must remain separate until that dependency is resolved; no merge is implied.
AudioSync source is pinned and attributed in Vendor/AudioSync/INTEGRATION.md.
This candidate requires macOS 15+, Apple Silicon and Xcode to build.

## Current setup

One MonitorControl menu contains Desk Audio, Desk Setup, Audio Outputs, manual
source requests and Pause. Both Macs use the same generated 256-bit pairing key,
stored in Keychain. RESML is the single coordinator; the personal Mac connects to
its configured LAN address on TCP 49187. TLS authentication is mandatory. Setup
Save connects but does not capture. There is no automatic session restoration on
launch, Save, wake or reconnection.

In Audio Outputs choose exactly one built-in local output and the other Mac's
AirPlay receiver. Existing AudioSync consent/PIN pairing remains required.
Streaming starts only through a desk-source request. Ordinary audio outputs and
capture source controls are retained from the native AudioSync UI. Setup chooses
Stereo, Left to Both or Right to Both for this Mac; the peer exchanges its choice
and the sender separately maps its local output and outgoing stereo stream.
No system balance or default-channel settings are changed.

An accepted LG HDMI 1 request (0x90) requests RESML audio; USB-C (0xD1) requests
personal audio. Automation emits this only after a current-generation successful
write. The manual menu applies only to the exactly configured automation display.
Physical monitor buttons are untracked; input readback cannot reveal them reliably.
Mixed/unknown Bluetooth holds an established source. Pause/settings changes stop
paired audio; reconnect from Desk Setup to enable subsequent requests.

The coordinator stops local capture, asks the peer to stop and waits for its
completed fade/capture acknowledgement before starting the selected source.
A source is reported playing only after AirPlay reports playing. A failed start,
missed heartbeat, sleep or lost peer stops capture. No unauthenticated start/capture
endpoint exists. Reconnection is explicit in this candidate and establishes idle.

## Validation and open acceptance

- Full integrated Debug build passed with macOS 15 / arm64 override.
- scripts/test-input-source.sh passes the four original suites.
- scripts/test-desk-audio.sh exercises stop-before-start, stale completions,
  pause and sample mapping, plus real loopback TLS exchange and wrong-key rejection.
- These tests do not establish two-machine handoff, audible sync, inactive-Mac
  sound suppression, receiver-buffer drain, feedback prevention or restart recovery.
- Reverse-path probe is isolated on RESML and requires ordinary user consent and
  listening confirmation. Do not treat this branch as accepted production software.
- Existing installed bundles and original settings remain rollback sources.

The inactive Mac's built-in AirPlay receiver belongs to macOS processes. A source
handoff must be tested with local sound on both Macs and receiver audio present.
Current inactive-Mac local-app suppression is not implemented. Physical testing
may require a bounded receiver or capture-exclusion change; do not enable automatic
production handoff until that behavior and role reversal have passed.

## Build and rollback

Run scripts/build-desk.sh. It builds the pinned Rust core, Release app, packages
licenses and signs the isolated /tmp/monitorcontrol-desk-release candidate. It
never invokes an installer. Save settings and old bundles before replacing any
working install. Stop the candidate and restore those bundles/config backups to
roll back; do not remove existing AirPlay discovery or router configuration.

The reverse preflight also found live selected identities changed to ProtoArc EK04
and EM01 NL. The candidate preserves existing JSON and does not seed the earlier
K5 Max selection. Machine-specific values belong in the homelab wiki, not source
configuration defaults.
