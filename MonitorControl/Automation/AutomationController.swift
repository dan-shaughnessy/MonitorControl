//  Copyright © MonitorControl contributors

import AppKit
import Foundation
import os.log

func companionLog(_ message: String) {
  let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
  os_log("%{public}@", type: .default, message)
  print("\(stamp) \(message)")
  fflush(stdout)
}

/// Connects the pure policy to IOKit, Bluetooth, sleep/wake and the DDC executor. Main thread only.
final class AutomationController {
  let store: ConfigStore
  private(set) var config: CompanionConfig
  private(set) var configError: String?
  private(set) var observed: KeyboardPresence = .unknown
  private(set) var deviceStates: [(name: String, presence: KeyboardPresence)] = []
  private(set) var lastResult: String = "No command sent since launch"
  private var policy: TriggerPolicy
  private lazy var watcher = HIDRegistryWatcher { [weak self] in self?.reconcile(reason: "registry change") }
  private var executor: InputCommandExecutor!
  private var decisionTimer: Timer?
  private var reconcileTimer: Timer?
  private var lastPowerOn: Bool?
  var onStatusChange: (() -> Void)?

  private let writer: (DDCInputSource, CompanionConfig, () -> Bool) -> WriteAttempt
  private let canAct: () -> Bool
  private let observationProvider: (() -> (states: [(name: String, presence: KeyboardPresence)], combined: KeyboardPresence))?
  private let powerProvider: () -> Bool?
  private var started = false
  private var displayChanging = false

  init(store: ConfigStore, commandQueue: DispatchQueue = DispatchQueue(label: "monitorcontrol.automation.ddc"),
       canAct: @escaping () -> Bool = { true },
       writer: @escaping (DDCInputSource, CompanionConfig, () -> Bool) -> WriteAttempt = DisplayCandidate.write,
       observationProvider: (() -> (states: [(name: String, presence: KeyboardPresence)], combined: KeyboardPresence))? = nil,
       powerProvider: @escaping () -> Bool? = BluetoothState.powerOn) {
    self.observationProvider = observationProvider
    self.powerProvider = powerProvider
    self.writer = writer
    self.canAct = canAct
    self.store = store
    do {
      self.config = try store.load()
    } catch {
      self.config = CompanionConfig()
      self.configError = "Config could not be read; automation is off until saved again"
      companionLog("config error: \(error.localizedDescription)")
    }
    self.policy = TriggerPolicy(timing: self.config.timing)
    self.executor = InputCommandExecutor(queue: commandQueue, write: { _ in .failed })
  }

  var pending: (target: KeyboardPresence, due: Date)? {
    guard let target = self.policy.pendingTarget, let due = self.policy.pendingDue else { return nil }
    return (target, Date(timeIntervalSince1970: due))
  }

  var settled: KeyboardPresence? { self.policy.settled }
  var isSuspended: Bool { self.policy.suspended || self.policy.resumeAt != nil }

  func start() {
    guard !self.started else { return }
    self.started = true
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.systemWillSleep() }
    center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.systemDidWake() }
    self.reconcileTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.reconcile(reason: nil) }
    self.applyCurrentConfig(reason: "launch")
  }

  /// Saves and applies new settings. Effective state restarts from a no-action baseline.
  func update(_ newConfig: CompanionConfig) throws {
    try self.store.save(newConfig)
    self.config = newConfig
    self.configError = nil
    if self.started { self.applyCurrentConfig(reason: "settings saved") } else if newConfig.enabled { self.start() }
  }

  func setEnabled(_ enabled: Bool) throws {
    var c = self.config
    c.enabled = enabled
    try self.store.save(c)
    self.config = c
    self.cancelDecisionTimer()
    self.policy.baseline(self.observed)
    self.syncGeneration()
    if enabled && !self.started { self.start() }
    // Pausing keeps tracking the keyboard, so resuming never replays an earlier edge.
    companionLog(enabled ? "automation enabled" : "automation paused")
    self.onStatusChange?()
  }

  private func applyCurrentConfig(reason: String) {
    self.decisionTimer?.invalidate()
    self.policy = TriggerPolicy(timing: self.config.timing, after: self.policy.generation)
    let addresses = self.config.devices.compactMap { CompanionConfig.normalizedAddress($0.address) }
    if self.observationProvider == nil {
      if addresses.isEmpty { self.watcher.stop() } else { self.watcher.start(addresses: addresses) }
    }
    self.lastPowerOn = self.powerProvider()
    self.observed = self.evaluate()
    self.policy.baseline(self.observed)
    self.syncGeneration()
    let problems = self.config.problems
    companionLog("\(reason): \(self.describeStates()) (baseline, no command); "
      + "automation \(self.config.enabled ? "enabled" : "paused")" + (problems.isEmpty ? "" : "; incomplete: " + problems.joined(separator: ", ")))
    self.onStatusChange?()
  }

  /// Per-device states and their combined state. Read-only.
  func evaluateDevices() -> (states: [(name: String, presence: KeyboardPresence)], combined: KeyboardPresence) {
    if let observe = self.observationProvider { return observe() }
    let entries = HIDRegistryWatcher.bluetoothEntries()
    let power = self.powerProvider()
    let paired = BluetoothState.pairedDevices()?.map(\.address)
    let states = self.config.devices.map { device -> (name: String, presence: KeyboardPresence) in
      guard let entries = entries, let address = CompanionConfig.normalizedAddress(device.address) else { return (device.name, .unknown) }
      return (device.name, KeyboardIdentity.presence(powerOn: power, paired: paired.map { $0.contains(address) }, entries: entries, device: device))
    }
    return (states, KeyboardIdentity.aggregate(states.map(\.presence)))
  }

  func evaluate() -> KeyboardPresence {
    let result = self.evaluateDevices()
    self.deviceStates = result.states
    return result.combined
  }

  private func describeStates() -> String {
    guard !self.deviceStates.isEmpty else { return "no device selected" }
    let each = self.deviceStates.map { "\"\($0.name)\" \($0.presence.rawValue)" }.joined(separator: ", ")
    return self.deviceStates.count == 1 ? each : "\(each) → \(self.observed.rawValue)"
  }

  func displayWillChange() {
    self.displayChanging = true
    self.cancelDecisionTimer()
    self.policy.suspend()
    self.syncGeneration()
  }

  func displayDidChange() {
    self.displayChanging = false
    guard self.started else { return }
    self.applyCurrentConfig(reason: "display changed")
  }

  func stop() {
    self.cancelDecisionTimer()
    self.reconcileTimer?.invalidate()
    self.watcher.stop()
    self.policy.suspend()
    self.syncGeneration()
  }

  func reconcile(reason: String? = nil) {
    guard !self.displayChanging else { return }
    let power = self.powerProvider()
    if power != self.lastPowerOn {
      if self.lastPowerOn == true {
        companionLog("Bluetooth is off or unavailable; pending work cancelled")
        self.cancelDecisionTimer()
        self.policy.suspend()
      } else if power == true {
        companionLog("Bluetooth is on; waiting \(Int(self.policy.timing.resumeGrace)) s before comparing state")
        self.scheduleReconcile(at: self.policy.resume(now: Date().timeIntervalSince1970))
      }
      self.lastPowerOn = power
      self.syncGeneration()
    }
    let previous = self.deviceStates.map(\.presence)
    self.observed = self.evaluate()
    if self.deviceStates.map(\.presence) != previous {
      companionLog(self.describeStates() + (reason.map { " (\($0))" } ?? ""))
    }
    self.handle(self.policy.observe(self.observed, now: Date().timeIntervalSince1970))
  }

  private func handle(_ decision: TriggerPolicy.Decision) {
    self.syncGeneration()
    switch decision {
    case .none:
      if self.policy.pendingTarget == nil { self.cancelDecisionTimer() }
    case let .schedule(at: due):
      if self.decisionTimer?.fireDate != Date(timeIntervalSince1970: due) {
        self.cancelDecisionTimer()
        let timer = Timer(fireAt: Date(timeIntervalSince1970: due), interval: 0, target: BlockTarget { [weak self] in self?.decisionTimerFired() },
                          selector: #selector(BlockTarget.run), userInfo: nil, repeats: false)
        RunLoop.main.add(timer, forMode: .common)
        self.decisionTimer = timer
      }
    case let .edge(presence):
      self.cancelDecisionTimer()
      self.act(on: presence)
    }
    self.onStatusChange?()
  }

  private func decisionTimerFired() {
    self.decisionTimer = nil
    self.observed = self.evaluate()
    self.handle(self.policy.fire(observed: self.observed, now: Date().timeIntervalSince1970))
  }

  private func act(on presence: KeyboardPresence) {
    guard self.config.enabled && self.canAct() else {
      companionLog("edge \(presence.rawValue): automation paused, no command")
      return
    }
    guard self.config.problems.isEmpty else {
      companionLog("edge \(presence.rawValue): settings incomplete, no command")
      return
    }
    guard let source = self.config.input(for: presence) else {
      companionLog("edge \(presence.rawValue): set to do nothing")
      return
    }
    let generation = self.policy.generation
    companionLog("edge \(presence.rawValue): sending \(source.title) (0x\(String(source.value, radix: 16, uppercase: true)))")
    let config = self.config
    let writer = self.writer
    self.executor.submit(source, generation: generation, write: { [executor = self.executor!] source in writer(source, config, { executor.isCurrent(generation) }) }) { result in
      DispatchQueue.main.async {
        let text: String
        switch result {
        case let .sent(attempts): text = "\(source.title) command sent (attempt \(attempts); monitor does not confirm)"
        case let .failed(attempts): text = "\(source.title) command failed after \(attempts) attempts"
        case .displayUnavailable: text = "\(source.title) not sent: monitor not found"
        case .superseded: text = "\(source.title) cancelled: keyboard state changed"
        }
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        self.lastResult = "\(time): \(text)"
        companionLog("result: \(text)")
        self.onStatusChange?()
      }
    }
  }

  private func systemWillSleep() {
    companionLog("system sleep: pending work cancelled")
    self.cancelDecisionTimer()
    self.policy.suspend()
    self.syncGeneration()
    self.onStatusChange?()
  }

  private func systemDidWake() {
    let at = self.policy.resume(now: Date().timeIntervalSince1970)
    self.syncGeneration()
    companionLog("system wake: waiting \(Int(self.policy.timing.resumeGrace)) s before comparing with pre-sleep state")
    self.scheduleReconcile(at: at)
    self.onStatusChange?()
  }

  private func scheduleReconcile(at time: TimeInterval) {
    let timer = Timer(fireAt: Date(timeIntervalSince1970: time + 0.1), interval: 0, target: BlockTarget { [weak self] in self?.reconcile(reason: "after grace") },
                      selector: #selector(BlockTarget.run), userInfo: nil, repeats: false)
    RunLoop.main.add(timer, forMode: .common)
  }

  private func cancelDecisionTimer() {
    self.decisionTimer?.invalidate()
    self.decisionTimer = nil
  }

  private func syncGeneration() {
    self.executor.setCurrentGeneration(self.policy.generation)
  }
}

final class BlockTarget: NSObject {
  private let block: () -> Void
  init(_ block: @escaping () -> Void) { self.block = block }
  @objc func run() { self.block() }
}
