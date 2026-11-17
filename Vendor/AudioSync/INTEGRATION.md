# AudioSync provenance and integration

Imported with `git archive 0140091e79e0ff9db36029729ef365616eb4a803` from
https://github.com/dan-shaughnessy/audiosync (fix/macos-airplay-user-agent).
Upstream v0.9.2: 66f99e5d78caa7e356d715c1f633bffd6903ce85.
Compatibility implementation: 0065318150fb44cab20f2358ffb3731a50bf9f8b.
Original GPL-3.0 license and third-party notices are retained. The build packages
Rust toolchain/crate notices with the application.

Integration changes:
- Package product DeskAudio compiles the existing native engine and UI into
  MonitorControl; main.swift is excluded, with no second visible app or icon.
- DeskAudio.swift wraps setup, speaker settings, ownership-gated start and
  asynchronous completed fades. Embedded settings use a deskAudio prefix.
- DeskHandoff.swift and DeskSession.swift own stop/ack/start transactions,
  cancellation, sleep, heartbeat leases and authenticated role requests.
- DeskPeer.swift uses TLS 1.2 PSK AES-128-GCM with a random 256-bit pairing key.
  Only the explicitly configured RESML coordinator listens. Keychain stores
  pairing keys; no controls are exposed before setup and authentication.
- DeskRouting.swift maps samples on the existing render/capture paths,
  with no allocations, logging, dispatches or locks on audio callbacks.
- MenuBar construction and automatic capture on launch are disabled in embedded
  mode. Engine starts require ownership authorization.
- Network imports are implementation-only to avoid exposing Network through
  MonitorControl's private-framework search environment.

Run ../../scripts/build-desk.sh from this directory or scripts/build-desk.sh
from the integration repository root. The AudioSync upstream build.sh is retained
for provenance but is no longer the integration build entrypoint.
