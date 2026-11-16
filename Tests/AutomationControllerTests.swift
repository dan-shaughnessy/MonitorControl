import AppKit

@main
struct AutomationControllerTests {
  static func main() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = ConfigStore(url: dir.appendingPathComponent("automation.json"))
    var config = CompanionConfig()
    config.enabled = true
    config.devices = [SelectedDevice(address: "11-22-33-44-55-66", name: "Test keyboard", vendorID: 1, productID: 2)]
    config.displaySerial = "TEST"
    config.displayVendorID = 1
    config.displayProductID = 2
    config.connectDelay = 0
    config.disconnectDelay = 0
    try store.save(config)
    var presence: KeyboardPresence = .connected
    let queue = DispatchQueue(label: "automation-controller-tests")
    let gate = DispatchSemaphore(value: 0)
    let entered = DispatchSemaphore(value: 0)
    queue.async { entered.signal(); gate.wait() }
    entered.wait()
    let lock = NSLock()
    var writes: [UInt16] = []
    let controller = AutomationController(store: store, commandQueue: queue, writer: { source, snapshot, isCurrent in
      guard isCurrent() else { return .superseded }
      precondition(snapshot.displaySerial == "TEST")
      lock.lock(); writes.append(source.value); lock.unlock()
      return .sent
    }, observationProvider: { ([("Test keyboard", presence)], presence) }, powerProvider: { true })
    func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.06)) }
    func count() -> Int { lock.lock(); defer { lock.unlock() }; return writes.count }
    controller.displayWillChange()
    controller.displayDidChange() // Reconfiguration while automation is not started must not block later enable.
    controller.start()
    precondition(count() == 0, "Launch must not switch")
    presence = .disconnected
    controller.reconcile()
    pump()
    try controller.setEnabled(false)
    gate.signal()
    pump()
    precondition(count() == 0, "Pausing cancels an already queued edge")
    try controller.setEnabled(true)
    pump()
    precondition(count() == 0, "Enabling never replays a paused edge")
    presence = .connected
    controller.reconcile()
    pump()
    precondition(count() == 1)
    var changed = controller.config
    changed.disconnectedInput = 0x91
    try controller.update(changed)
    pump()
    precondition(count() == 1, "Settings save must not switch")
    controller.displayWillChange()
    presence = .disconnected
    controller.reconcile()
    pump()
    precondition(count() == 1, "Display changes suppress edges")
    controller.displayDidChange()
    pump()
    precondition(count() == 1, "Display reconnect establishes a baseline")
    presence = .connected
    controller.reconcile()
    pump()
    presence = .disconnected
    controller.reconcile()
    pump()
    lock.lock(); let last = writes.last; lock.unlock()
    precondition(last == 0x91, "New jobs use the saved configuration snapshot")
    controller.stop()

    // A failed input command must not monopolize the app's shared brightness queue.
    let executor = InputCommandExecutor(queue: queue, retryDelay: 0.4, write: { _ in .failed })
    executor.submit(DDCInputSource(title: "HDMI 1", value: 0x90), generation: 0) { _ in }
    let brightnessWork = DispatchSemaphore(value: 0)
    queue.async { brightnessWork.signal() }
    precondition(brightnessWork.wait(timeout: .now() + 0.2) == .success)
    executor.setCurrentGeneration(1)
    print("Automation controller baseline, queue sharing, pause, reconnect and config snapshot tests passed")
  }
}
