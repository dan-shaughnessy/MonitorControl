import Foundation

/// Hardware-free tests for the LG input companion. They never touch Bluetooth or a monitor.
@main
struct CompanionPolicyTests {
  static let timing = PolicyTiming(connectDelay: 2, disconnectDelay: 10, resumeGrace: 20)

  static let k5Device = SelectedDevice(address: "D9:27:29:C0:EB:C9", name: "Keychron K5 Max", vendorID: 0x3434, productID: 0x0A53)
  static let mouseDevice = SelectedDevice(address: "df-c8-2d-1b-44-89", name: "G604 LIGHTSPEED", vendorID: 0x046D, productID: 0xB024)

  static func k5Config() -> CompanionConfig {
    var c = CompanionConfig()
    c.enabled = true
    c.devices = [k5Device]
    c.displayName = "LG ULTRAGEAR+"
    c.displaySerial = "601INAR7V264"
    c.displayVendorID = 0x1E6D
    c.displayProductID = 0x7845
    return c
  }

  static func main() {
    self.testPolicy()
    self.testSleepAndPower()
    self.testIdentity()
    self.testMultipleDevices()
    self.testConfig()
    self.testExecutor()
    print("Companion policy, identity, config and executor tests passed")
  }

  static func testPolicy() {
    // Launch baselines: no action whatever the state.
    var p = TriggerPolicy(timing: timing)
    p.baseline(.connected)
    precondition(p.observe(.connected, now: 0) == .none)
    // Disconnect needs the long delay; repeated observations do not extend it.
    precondition(p.observe(.disconnected, now: 1) == .schedule(at: 11))
    precondition(p.observe(.disconnected, now: 5) == .schedule(at: 11))
    precondition(p.fire(observed: .disconnected, now: 6) == .schedule(at: 11), "early timer must not act")
    precondition(p.fire(observed: .disconnected, now: 11) == .edge(.disconnected))
    precondition(p.settled == .disconnected)
    // No repeated action while unchanged.
    precondition(p.observe(.disconnected, now: 12) == .none)
    precondition(p.fire(observed: .disconnected, now: 30) == .none)
    // Connect uses the short delay.
    precondition(p.observe(.connected, now: 40) == .schedule(at: 42))
    precondition(p.fire(observed: .connected, now: 42) == .edge(.connected))

    // A short disconnect (bounce) cancels without acting, and bumps the generation.
    let g = p.generation
    precondition(p.observe(.disconnected, now: 50) == .schedule(at: 60))
    precondition(p.generation != g)
    let g2 = p.generation
    precondition(p.observe(.connected, now: 53) == .none)
    precondition(p.generation != g2, "a bounce must invalidate queued work")
    precondition(p.fire(observed: .connected, now: 60) == .none)
    precondition(p.settled == .connected)

    // A stale timer that finds the opposite state does not act.
    precondition(p.observe(.disconnected, now: 70) == .schedule(at: 80))
    precondition(p.fire(observed: .connected, now: 80) == .none)
    precondition(p.settled == .connected && p.pendingTarget == nil)

    // Duplicate settled observations do not invalidate in-flight work.
    let g3 = p.generation
    precondition(p.observe(.connected, now: 90) == .none && p.generation == g3)

    // Unknown cancels and never acts; the next known state is compared with the baseline.
    precondition(p.observe(.disconnected, now: 100) == .schedule(at: 110))
    precondition(p.observe(.unknown, now: 101) == .none)
    precondition(p.pendingTarget == nil)
    precondition(p.fire(observed: .disconnected, now: 110) == .none)
    precondition(p.settled == .connected)

    // Zero delays act on the first fire, still with a fresh observation.
    let instant = TriggerPolicy(timing: PolicyTiming(connectDelay: 0, disconnectDelay: 0, resumeGrace: 20))
    instant.baseline(.connected)
    precondition(instant.observe(.disconnected, now: 5) == .schedule(at: 5))
    precondition(instant.fire(observed: .disconnected, now: 5) == .edge(.disconnected))
    precondition(instant.observe(.connected, now: 6) == .schedule(at: 6))
    precondition(instant.fire(observed: .disconnected, now: 6) == .none, "a state already gone by the fire does not act")
    precondition(instant.settled == .disconnected)
    instant.suspend()
    precondition(instant.observe(.connected, now: 7) == .none, "sleep still blocks instant edges")

    // A replacement policy (settings change) continues the generation sequence.
    let replaced = TriggerPolicy(timing: timing, after: p.generation)
    precondition(replaced.generation > p.generation)

    // Unknown at launch: the first known state is a baseline, not an edge.
    p = TriggerPolicy(timing: timing)
    p.baseline(.unknown)
    precondition(p.settled == nil)
    precondition(p.observe(.disconnected, now: 1) == .none)
    precondition(p.settled == .disconnected)
    precondition(p.observe(.connected, now: 2) == .schedule(at: 4))
  }

  static func testSleepAndPower() {
    // Disconnect at sleep, reconnect after wake: no switch.
    var p = TriggerPolicy(timing: timing)
    p.baseline(.connected)
    precondition(p.observe(.disconnected, now: 1) == .schedule(at: 11))
    p.suspend()
    precondition(p.pendingTarget == nil)
    precondition(p.observe(.disconnected, now: 2) == .none)
    precondition(p.fire(observed: .disconnected, now: 11) == .none)
    let reconcile = p.resume(now: 500)
    precondition(reconcile == 520)
    precondition(p.observe(.disconnected, now: 505) == .none, "grace ignores reconnect churn")
    precondition(p.observe(.connected, now: 520) == .none)
    precondition(p.settled == .connected)

    // Wake establishes a baseline even if the keyboard changed while asleep.
    p = TriggerPolicy(timing: timing)
    p.baseline(.connected)
    p.suspend()
    _ = p.resume(now: 100)
    precondition(p.observe(.disconnected, now: 120) == .none)
    precondition(p.fire(observed: .disconnected, now: 130) == .none)
    precondition(p.observe(.connected, now: 131) == .schedule(at: 133))
    precondition(p.fire(observed: .connected, now: 133) == .edge(.connected))

    // Keyboard turned on while asleep: connect edge after wake grace.
    p = TriggerPolicy(timing: timing)
    p.baseline(.disconnected)
    p.suspend()
    _ = p.resume(now: 0)
    precondition(p.observe(.connected, now: 20) == .none)
    precondition(p.fire(observed: .connected, now: 22) == .none)

    // Suspend and resume invalidate in-flight work.
    let g = p.generation
    p.suspend()
    precondition(p.generation != g)
    let g2 = p.generation
    _ = p.resume(now: 50)
    precondition(p.generation != g2)
  }

  static func testIdentity() {
    let c = self.k5Config()
    let k5 = HIDEntry(address: "d9-27-29-c0-eb-c9", transport: "Bluetooth Low Energy", vendorID: 0x3434, productID: 0x0A53)
    let k10 = HIDEntry(address: "e3-22-b7-00-9b-4a", transport: "Bluetooth Low Energy", vendorID: 0x02E5, productID: 0xA1B2)
    let mouse = HIDEntry(address: "df-c8-2d-1b-44-89", transport: "Bluetooth Low Energy", vendorID: 0x046D, productID: 0xB024)
    precondition(KeyboardIdentity.presence(powerOn: true, paired: true, entries: [k10, mouse, k5], device: c.devices[0]) == .connected)
    precondition(KeyboardIdentity.presence(powerOn: true, paired: true, entries: [k10, mouse], device: c.devices[0]) == .disconnected, "other keyboards never count")
    precondition(KeyboardIdentity.presence(powerOn: false, paired: true, entries: [], device: c.devices[0]) == .unknown)
    precondition(KeyboardIdentity.presence(powerOn: nil, paired: true, entries: [], device: c.devices[0]) == .unknown)
    precondition(KeyboardIdentity.presence(powerOn: true, paired: false, entries: [], device: c.devices[0]) == .unknown)
    precondition(KeyboardIdentity.presence(powerOn: true, paired: nil, entries: [k5], device: c.devices[0]) == .unknown)
    var wrongIDs = k5
    wrongIDs.productID = 0x0001
    precondition(KeyboardIdentity.presence(powerOn: true, paired: true, entries: [wrongIDs], device: c.devices[0]) == .unknown)
    var usb = k5
    usb.transport = "USB"
    precondition(KeyboardIdentity.presence(powerOn: true, paired: true, entries: [usb], device: c.devices[0]) == .unknown)
    var noAddress = k5Device
    noAddress.address = ""
    precondition(KeyboardIdentity.presence(powerOn: true, paired: true, entries: [k5], device: noAddress) == .unknown)
    var addressOnly = k5Device
    addressOnly.vendorID = nil
    addressOnly.productID = nil
    precondition(KeyboardIdentity.presence(powerOn: true, paired: true, entries: [k5], device: addressOnly) == .unknown)
    // The mouse is judged on its own identity, never the keyboard's.
    precondition(KeyboardIdentity.presence(powerOn: true, paired: true, entries: [k5, mouse], device: mouseDevice) == .connected)
    precondition(KeyboardIdentity.presence(powerOn: true, paired: true, entries: [k5], device: mouseDevice) == .disconnected)

    precondition(CompanionConfig.normalizedAddress("D9:27:29:C0:EB:C9") == "d9-27-29-c0-eb-c9")
    precondition(CompanionConfig.normalizedAddress("d9-27-29-c0-eb") == nil)
    precondition(CompanionConfig.normalizedAddress("zz-27-29-c0-eb-c9") == nil)

    // Display: serial, vendor and port-specific product must all match exactly once.
    let hdmi = DisplayIdentity(serial: "601INAR7V264", vendorID: 0x1E6D, productID: 0x7845)
    let usbC = DisplayIdentity(serial: "601INAR7V264", vendorID: 0x1E6D, productID: 0x7847)
    let other = DisplayIdentity(serial: "OTHER", vendorID: 0x1E6D, productID: 0x7845)
    precondition(DisplayIdentity.uniqueMatch([other, hdmi], identity: { $0 }, expected: hdmi) == hdmi)
    precondition(DisplayIdentity.uniqueMatch([usbC, other], identity: { $0 }, expected: hdmi) == nil)
    precondition(DisplayIdentity.uniqueMatch([hdmi, hdmi], identity: { $0 }, expected: hdmi) == nil, "ambiguous")
    let blank = DisplayIdentity(serial: "", vendorID: 0x1E6D, productID: 0x7845)
    precondition(DisplayIdentity.uniqueMatch([blank], identity: { $0 }, expected: blank) == nil)
  }

  static func testMultipleDevices() {
    // All must agree; partial is mixed; any unknown makes the set unknown.
    precondition(KeyboardIdentity.aggregate([.connected, .connected]) == .connected)
    precondition(KeyboardIdentity.aggregate([.disconnected, .disconnected]) == .disconnected)
    precondition(KeyboardIdentity.aggregate([.connected, .disconnected]) == .mixed)
    precondition(KeyboardIdentity.aggregate([.connected, .unknown]) == .unknown)
    precondition(KeyboardIdentity.aggregate([]) == .unknown)
    precondition(KeyboardIdentity.aggregate([.connected]) == .connected)

    // All connected → one disconnects (hold) → both gone (USB-C) → one back (hold) → both back (HDMI 1).
    let p = TriggerPolicy(timing: PolicyTiming(connectDelay: 0, disconnectDelay: 0, resumeGrace: 20))
    p.baseline(.connected)
    precondition(p.observe(.mixed, now: 1) == .none && p.settled == .connected)
    precondition(p.observe(.disconnected, now: 2) == .schedule(at: 2))
    precondition(p.fire(observed: .disconnected, now: 2) == .edge(.disconnected))
    precondition(p.observe(.mixed, now: 3) == .none && p.settled == .disconnected)
    precondition(p.observe(.connected, now: 4) == .schedule(at: 4))
    precondition(p.fire(observed: .connected, now: 4) == .edge(.connected))
    // Mixed cancels a pending change and holds.
    let slow = TriggerPolicy(timing: timing)
    slow.baseline(.connected)
    precondition(slow.observe(.disconnected, now: 0) == .schedule(at: 10))
    precondition(slow.observe(.mixed, now: 5) == .none && slow.pendingTarget == nil)
    precondition(slow.fire(observed: .mixed, now: 10) == .none && slow.settled == .connected)
    // Mixed at launch is the baseline; the first full match then acts.
    let launch = TriggerPolicy(timing: timing)
    launch.baseline(.mixed)
    precondition(launch.observe(.mixed, now: 0) == .none)
    precondition(launch.observe(.connected, now: 1) == .schedule(at: 3))
    precondition(launch.fire(observed: .connected, now: 3) == .edge(.connected))
    precondition(k5Config().input(for: .mixed) == nil)

    // Settings validation for device sets.
    var c = k5Config()
    c.devices.append(mouseDevice)
    precondition(c.problems.isEmpty && c.devicesSummary == "Keychron K5 Max + G604 LIGHTSPEED")
    c.devices.append(SelectedDevice(address: "d9-27-29-c0-eb-c9", name: "dup", vendorID: nil, productID: nil))
    precondition(c.problems.contains("A device is selected twice"))
    c.devices = []
    precondition(c.problems.contains("No Bluetooth device selected"))
    c.devices = [SelectedDevice(address: "bad", name: "x", vendorID: nil, productID: nil)]
    precondition(c.problems.contains("A selected device has an invalid address"))

    // First-release single-keyboard settings migrate to a one-device list.
    let legacy = try! JSONDecoder().decode(CompanionConfig.self, from: Data(#"{"enabled":true,"keyboardAddress":"d9-27-29-c0-eb-c9","keyboardName":"Keychron K5 Max","keyboardVendorID":13364,"keyboardProductID":2643}"#.utf8))
    precondition(legacy.devices == [SelectedDevice(address: "d9-27-29-c0-eb-c9", name: "Keychron K5 Max", vendorID: 0x3434, productID: 0x0A53)])
    let reencoded = String(data: try! JSONEncoder().encode(legacy), encoding: .utf8)!
    precondition(reencoded.contains("\"devices\"") && !reencoded.contains("keyboardAddress"))
  }

  static func testConfig() {
    var c = self.k5Config()
    precondition(c.problems.isEmpty, "\(c.problems)")
    precondition(c.input(for: .connected)?.value == 0x90 && c.input(for: .connected)?.title == "HDMI 1")
    precondition(c.input(for: .disconnected)?.value == 0xD1)
    precondition(c.input(for: .unknown) == nil)
    c.disconnectedInput = nil
    precondition(c.input(for: .disconnected) == nil && c.problems.isEmpty, "do nothing is valid")
    c.connectedInput = 0x11 // A standard value under LG alternate.
    precondition(c.input(for: .connected) == nil && !c.problems.isEmpty)
    c.inputProtocol = DDCInputSource.InputProtocol.standard.rawValue
    precondition(c.input(for: .connected)?.value == 0x11 && c.problems.isEmpty)
    c.inputProtocol = DDCInputSource.InputProtocol.lgUSB.rawValue
    precondition(c.protocolValue == .lgUSB && c.input(for: .connected) == nil, "USB mode requires its own explicit input values")
    c = self.k5Config()
    c.disconnectDelay = -1
    precondition(!c.problems.isEmpty)
    c.disconnectDelay = 0
    c.connectDelay = 0
    precondition(c.problems.isEmpty, "0 s means act when recognized")
    precondition(!CompanionConfig().enabled && !CompanionConfig().problems.isEmpty, "default is disabled and unconfigured")

    // Round trip, explicit null kept as "do nothing", absent keys use defaults.
    let migrationDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: migrationDirectory) }
    let legacyStore = ConfigStore(url: migrationDirectory.appendingPathComponent("legacy.json"))
    let expected = self.k5Config()
    try! legacyStore.save(expected)
    let migratedStore = ConfigStore(url: migrationDirectory.appendingPathComponent("automation.json"), legacyURL: legacyStore.url)
    precondition(try! migratedStore.load() == expected)
    precondition(FileManager.default.fileExists(atPath: migratedStore.url.path))
    precondition(try! legacyStore.load() == expected, "Migration retains the original config")
    var newer = expected
    newer.connectDelay = 0
    try! migratedStore.save(newer)
    precondition(try! migratedStore.load() == newer, "Legacy never overwrites newer app settings")
    try! Data("invalid".utf8).write(to: migratedStore.url)
    precondition((try? migratedStore.load()) == nil, "Corrupt new config is never replaced with legacy")

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = ConfigStore(url: dir.appendingPathComponent("config.json"))
    precondition((try? store.load()) == CompanionConfig())
    var saved = self.k5Config()
    saved.disconnectedInput = nil
    try! store.save(saved)
    precondition(try! store.load() == saved)
    let partial = try! JSONDecoder().decode(CompanionConfig.self, from: Data(#"{"devices":[{"address":"d9-27-29-c0-eb-c9","name":"K5"}]}"#.utf8))
    precondition(partial.connectedInput == 0x90 && partial.disconnectedInput == 0xD1 && !partial.enabled)
    try! Data("{not json".utf8).write(to: store.url)
    precondition((try? store.load()) == nil, "corrupt config must be reported")
  }

  static func testExecutor() {
    let hdmi = DDCInputSource(title: "HDMI 1", value: 0x90)
    var writes: [UInt16] = []
    var outcomes: [WriteAttempt] = [.failed, .failed, .sent]
    var executor: InputCommandExecutor!
    executor = InputCommandExecutor(maxAttempts: 3, retryDelay: 0, write: { s in writes.append(s.value); return outcomes.removeFirst() }, sleep: { _ in })
    executor.setCurrentGeneration(5)
    precondition(executor.run(hdmi, generation: 5) == .sent(attempts: 3))
    precondition(writes == [0x90, 0x90, 0x90])

    // Each queued job uses its captured configuration writer, not mutable main-thread state.
    writes = []
    precondition(executor.run(hdmi, generation: 5, write: { source in writes.append(source.value); return .sent }) == .sent(attempts: 1))
    precondition(writes == [0x90])

    // Bounded retries.
    writes = []
    outcomes = [.failed, .failed, .failed, .sent]
    precondition(executor.run(hdmi, generation: 5) == .failed(attempts: 3))
    precondition(writes.count == 3)

    // A stale generation never writes.
    writes = []
    precondition(executor.run(hdmi, generation: 4) == .superseded && writes.isEmpty)

    // A newer state during retries stops the old job before its next attempt.
    writes = []
    executor = InputCommandExecutor(maxAttempts: 3, retryDelay: 0, write: { s in writes.append(s.value); return .failed }, sleep: { _ in executor.setCurrentGeneration(6) })
    executor.setCurrentGeneration(5)
    precondition(executor.run(hdmi, generation: 5) == .superseded)
    precondition(writes.count == 1)

    // Display unavailable is not retried or queued.
    writes = []
    executor = InputCommandExecutor(maxAttempts: 3, retryDelay: 0, write: { s in writes.append(s.value); return .displayUnavailable }, sleep: { _ in })
    precondition(executor.run(hdmi, generation: 0) == .displayUnavailable && writes.count == 1)
  }
}
