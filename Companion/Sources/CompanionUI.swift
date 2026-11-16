//  Copyright © MonitorControl contributors

import AppKit

final class StatusMenuController: NSObject, NSMenuDelegate {
  private let controller: CompanionController
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private lazy var settings = SettingsWindowController(controller: self.controller)

  init(controller: CompanionController) {
    self.controller = controller
    super.init()
    self.item.button?.image = NSImage(systemSymbolName: "keyboard.badge.eye", accessibilityDescription: "LG Input Companion")
      ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "LG Input Companion")
    let menu = NSMenu()
    menu.delegate = self
    self.item.menu = menu
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let c = self.controller.config
    func info(_ text: String) { menu.addItem(withTitle: text, action: nil, keyEquivalent: "").isEnabled = false }
    let name = c.keyboardName.isEmpty ? "No keyboard selected" : c.keyboardName
    info("Keyboard: \(name) — \(self.controller.observed.rawValue)")
    let display = DisplayCandidate.find(c)
    info("Monitor: \(c.displayName.isEmpty ? "none selected" : c.displayName) — \(display == nil ? "not found" : "available")")
    info("Connected → \(c.input(for: .connected)?.title ?? "do nothing"); disconnected → \(c.input(for: .disconnected)?.title ?? "do nothing")")
    if let pending = self.controller.pending {
      let seconds = max(0, Int(pending.due.timeIntervalSinceNow.rounded(.up)))
      info("Pending: \(pending.target.rawValue) in \(seconds) s")
    } else if self.controller.isSuspended {
      info("Waiting after wake or Bluetooth change")
    }
    info(self.controller.lastResult)
    if let error = self.controller.configError { info(error) }
    for problem in c.problems { info("⚠︎ \(problem)") }
    menu.addItem(.separator())
    let toggle = menu.addItem(withTitle: "Automatic Switching", action: #selector(self.toggleEnabled), keyEquivalent: "")
    toggle.target = self
    toggle.state = c.enabled ? .on : .off
    menu.addItem(withTitle: "Settings…", action: #selector(self.openSettings), keyEquivalent: ",").target = self
    menu.addItem(withTitle: "Open Log", action: #selector(self.openLog), keyEquivalent: "").target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit LG Input Companion", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
  }

  @objc private func toggleEnabled() {
    do { try self.controller.setEnabled(!self.controller.config.enabled) } catch { NSAlert(error: error).runModal() }
  }

  @objc private func openSettings() { self.settings.show() }

  @objc private func openLog() {
    let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/LGInputCompanion.log")
    NSWorkspace.shared.open(log)
  }
}

final class SettingsWindowController: NSObject {
  private let controller: CompanionController
  private var window: NSWindow?
  private let keyboardPopup = NSPopUpButton()
  private let displayPopup = NSPopUpButton()
  private let protocolPopup = NSPopUpButton()
  private let connectedPopup = NSPopUpButton()
  private let disconnectedPopup = NSPopUpButton()
  private let connectDelayField = NSTextField()
  private let disconnectDelayField = NSTextField()
  private let enabledCheckbox = NSButton(checkboxWithTitle: "Switch automatically", target: nil, action: nil)
  private var keyboards: [PairedDevice] = []
  private var displays: [(label: String, name: String, identity: DisplayIdentity)] = []

  init(controller: CompanionController) {
    self.controller = controller
  }

  func show() {
    if self.window == nil { self.window = self.makeWindow() }
    self.load(self.controller.config)
    NSApp.activate(ignoringOtherApps: true)
    self.window?.makeKeyAndOrderFront(nil)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "LG Input Companion Settings"
    window.isReleasedWhenClosed = false
    func label(_ text: String) -> NSTextField {
      let l = NSTextField(labelWithString: text)
      l.alignment = .right
      return l
    }
    for field in [self.connectDelayField, self.disconnectDelayField] {
      let formatter = NumberFormatter()
      formatter.numberStyle = .decimal
      formatter.maximumFractionDigits = 1
      field.formatter = formatter
      field.widthAnchor.constraint(equalToConstant: 70).isActive = true
    }
    self.protocolPopup.target = self
    self.protocolPopup.action = #selector(self.protocolChanged)
    let note = NSTextField(wrappingLabelWithString: "Only the selected keyboard triggers a switch. Changes start from the current state without sending a command. Monitors do not confirm input commands.")
    note.textColor = .secondaryLabelColor
    let grid = NSGridView(views: [
      [label("Bluetooth keyboard:"), self.keyboardPopup],
      [label("Monitor:"), self.displayPopup],
      [label("Input protocol:"), self.protocolPopup],
      [label("When connected:"), self.connectedPopup],
      [label("When disconnected:"), self.disconnectedPopup],
      [label("Connect delay (s):"), self.connectDelayField],
      [label("Disconnect delay (s):"), self.disconnectDelayField],
      [NSGridCell.emptyContentView, self.enabledCheckbox],
    ])
    grid.rowSpacing = 8
    grid.column(at: 0).xPlacement = .trailing
    let refresh = NSButton(title: "Refresh Lists", target: self, action: #selector(self.refresh))
    let cancel = NSButton(title: "Cancel", target: self, action: #selector(self.cancel))
    cancel.keyEquivalent = "\u{1b}"
    let save = NSButton(title: "Save", target: self, action: #selector(self.save))
    save.keyEquivalent = "\r"
    let buttons = NSStackView(views: [refresh, NSView(), cancel, save])
    let stack = NSStackView(views: [grid, note, buttons])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    stack.translatesAutoresizingMaskIntoConstraints = false
    window.contentView = NSView()
    window.contentView?.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
      stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
      stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
      buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
      note.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
      self.keyboardPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
    ])
    window.center()
    return window
  }

  /// Saved choices stay visible, marked unavailable, when the device is not present now.
  private func load(_ c: CompanionConfig) {
    self.keyboards = BluetoothState.pairedDevices() ?? []
    let savedAddress = CompanionConfig.normalizedAddress(c.keyboardAddress)
    if let savedAddress = savedAddress, !self.keyboards.contains(where: { $0.address == savedAddress }) {
      self.keyboards.append(PairedDevice(name: c.keyboardName + " (unavailable: not paired)", address: savedAddress, connected: false))
    }
    self.keyboardPopup.removeAllItems()
    self.keyboardPopup.addItem(withTitle: "None")
    for device in self.keyboards {
      self.keyboardPopup.addItem(withTitle: "\(device.name) — \(device.connected ? "connected" : "not connected") — \(device.address.uppercased())")
    }
    self.keyboardPopup.selectItem(at: (self.keyboards.firstIndex { $0.address == savedAddress } ?? -1) + 1)

    self.displays = DisplayCandidate.all().map { ($0.label, $0.name, $0.identity) }
    if let vendor = c.displayVendorID, let product = c.displayProductID {
      let saved = DisplayIdentity(serial: c.displaySerial, vendorID: vendor, productID: product)
      if !c.displaySerial.isEmpty, !self.displays.contains(where: { $0.identity == saved }) {
        self.displays.append((String(format: "%@ (%@, product 0x%04X) (unavailable)", c.displayName, c.displaySerial, product), c.displayName, saved))
      }
    }
    self.displayPopup.removeAllItems()
    self.displayPopup.addItem(withTitle: "None")
    self.displays.forEach { self.displayPopup.addItem(withTitle: $0.label) }
    let selectedDisplay = self.displays.firstIndex {
      $0.identity.serial == c.displaySerial && $0.identity.vendorID == c.displayVendorID && $0.identity.productID == c.displayProductID
    }
    self.displayPopup.selectItem(at: (selectedDisplay ?? -1) + 1)

    self.protocolPopup.removeAllItems()
    CompanionConfig.supportedProtocols.forEach { self.protocolPopup.addItem(withTitle: $0.title) }
    self.protocolPopup.selectItem(at: CompanionConfig.supportedProtocols.firstIndex { $0.rawValue == c.inputProtocol } ?? 0)
    self.reloadInputs(connected: c.connectedInput, disconnected: c.disconnectedInput)
    self.connectDelayField.doubleValue = c.connectDelay
    self.disconnectDelayField.doubleValue = c.disconnectDelay
    self.enabledCheckbox.state = c.enabled ? .on : .off
  }

  private var selectedProtocol: DDCInputSource.InputProtocol {
    CompanionConfig.supportedProtocols[max(0, self.protocolPopup.indexOfSelectedItem)]
  }

  private func reloadInputs(connected: Int?, disconnected: Int?) {
    let sources = self.selectedProtocol.sources
    for (popup, value) in [(self.connectedPopup, connected), (self.disconnectedPopup, disconnected)] {
      popup.removeAllItems()
      popup.addItem(withTitle: "Do nothing")
      sources.forEach { popup.addItem(withTitle: $0.title) }
      popup.selectItem(at: (sources.firstIndex { Int($0.value) == value } ?? -1) + 1)
    }
  }

  private func selectedInput(_ popup: NSPopUpButton) -> Int? {
    let index = popup.indexOfSelectedItem - 1
    let sources = self.selectedProtocol.sources
    return sources.indices.contains(index) ? Int(sources[index].value) : nil
  }

  @objc private func protocolChanged() {
    // Values differ between protocols; map by title so HDMI 1 stays HDMI 1.
    let titles = [self.connectedPopup.titleOfSelectedItem, self.disconnectedPopup.titleOfSelectedItem]
    let sources = self.selectedProtocol.sources
    let mapped = titles.map { title in sources.first { $0.title == title }.map { Int($0.value) } }
    self.reloadInputs(connected: mapped[0], disconnected: mapped[1])
  }

  @objc private func refresh() {
    var c = self.collect()
    c.enabled = self.enabledCheckbox.state == .on
    self.load(c)
  }

  @objc private func cancel() { self.window?.close() }

  private func collect() -> CompanionConfig {
    var c = self.controller.config
    let keyboardIndex = self.keyboardPopup.indexOfSelectedItem - 1
    if self.keyboards.indices.contains(keyboardIndex) {
      let device = self.keyboards[keyboardIndex]
      if device.address != CompanionConfig.normalizedAddress(c.keyboardAddress) {
        // Learn vendor/product IDs only from the live HID entry of the chosen address.
        let entry = HIDRegistryWatcher.bluetoothEntries()?.first { CompanionConfig.normalizedAddress($0.address) == device.address }
        c.keyboardVendorID = entry?.vendorID
        c.keyboardProductID = entry?.productID
        c.keyboardName = device.name
      }
      c.keyboardAddress = device.address
    } else {
      c.keyboardAddress = ""
      c.keyboardName = ""
      c.keyboardVendorID = nil
      c.keyboardProductID = nil
    }
    let displayIndex = self.displayPopup.indexOfSelectedItem - 1
    if self.displays.indices.contains(displayIndex) {
      let d = self.displays[displayIndex]
      c.displayName = d.name
      c.displaySerial = d.identity.serial
      c.displayVendorID = d.identity.vendorID
      c.displayProductID = d.identity.productID
    } else {
      c.displayName = ""
      c.displaySerial = ""
      c.displayVendorID = nil
      c.displayProductID = nil
    }
    c.inputProtocol = self.selectedProtocol.rawValue
    c.connectedInput = self.selectedInput(self.connectedPopup)
    c.disconnectedInput = self.selectedInput(self.disconnectedPopup)
    c.connectDelay = self.connectDelayField.doubleValue
    c.disconnectDelay = self.disconnectDelayField.doubleValue
    c.enabled = self.enabledCheckbox.state == .on
    return c
  }

  @objc private func save() {
    let c = self.collect()
    if c.enabled, !c.problems.isEmpty {
      let alert = NSAlert()
      alert.messageText = "Settings are incomplete"
      alert.informativeText = c.problems.joined(separator: "\n") + "\n\nFix these, or turn off automatic switching to save."
      alert.runModal()
      return
    }
    do {
      try self.controller.update(c)
      self.window?.close()
    } catch {
      NSAlert(error: error).runModal()
    }
  }
}
