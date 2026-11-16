//  Copyright © MonitorControl contributors

import AppKit

let store = ConfigStore(url: ConfigStore.defaultDirectory.appendingPathComponent("config.json"))
let arguments = CommandLine.arguments.dropFirst()

/// Read-only diagnostics. Neither flag sends a monitor command.
if arguments.contains("--list") || arguments.contains("--status") {
  print("Bluetooth power on:", BluetoothState.powerOn().map(String.init) ?? "unknown")
  if arguments.contains("--list") {
    let entries = HIDRegistryWatcher.bluetoothEntries() ?? []
    for device in BluetoothState.pairedDevices() ?? [] {
      let ids = entries.first { CompanionConfig.normalizedAddress($0.address) == device.address }
        .map { String(format: " HID %04X:%04X %@", $0.vendorID ?? 0, $0.productID ?? 0, $0.transport) } ?? ""
      print("paired: \(device.name) \(device.address) \(device.connected ? "connected" : "not connected")\(ids)")
    }
    for display in DisplayCandidate.all() { print("display: \(display.label)") }
  }
  if arguments.contains("--status") {
    do {
      let config = try store.load()
      let controller = CompanionController(store: store)
      print("config:", store.url.path)
      print("keyboard: \(config.keyboardName) \(config.keyboardAddress) ids \(config.keyboardVendorID.map { String(format: "%04X", $0) } ?? "-"):\(config.keyboardProductID.map { String(format: "%04X", $0) } ?? "-")")
      print("keyboard state:", controller.evaluate().rawValue)
      print("monitor: \(config.displayName) \(config.displaySerial) product \(config.displayProductID.map { String(format: "0x%04X", $0) } ?? "-") \(DisplayCandidate.find(config) == nil ? "not found" : "available")")
      print("connected → \(config.input(for: .connected)?.title ?? "do nothing"), disconnected → \(config.input(for: .disconnected)?.title ?? "do nothing"), protocol \(config.protocolValue?.title ?? "invalid")")
      print("delays: connect \(config.connectDelay) s, disconnect \(config.disconnectDelay) s; automation \(config.enabled ? "enabled" : "paused")")
      print("problems:", config.problems.isEmpty ? "none" : config.problems.joined(separator: "; "))
    } catch {
      print("config error:", error.localizedDescription)
      exit(1)
    }
  }
  exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  let controller = CompanionController(store: store)
  var menu: StatusMenuController?

  func applicationDidFinishLaunching(_: Notification) {
    self.menu = StatusMenuController(controller: self.controller)
    self.controller.start()
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
