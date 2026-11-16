//  Copyright © MonitorControl contributors

import AppKit
import Settings

final class AutomationPrefsViewController: NSViewController, SettingsPane {
  let paneIdentifier = Settings.PaneIdentifier.automation
  let paneTitle = NSLocalizedString("Automation", comment: "Settings pane")
  var toolbarItemIcon: NSImage {
    if #available(macOS 11.0, *) { return NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: self.paneTitle)! }
    return NSImage(named: NSImage.actionTemplateName)!
  }
  private let controller: AutomationController
  private let pairedDevices: () -> [PairedDevice]?
  private let displayCandidates: () -> [DisplayCandidate]
  private let hidEntries: () -> [HIDEntry]?
  private let migrationButton = NSButton(title: "Retire Old Companion", target: nil, action: nil)
  private let deviceDocument = AutomationDeviceDocument()
  private let savedLabel = NSTextField(wrappingLabelWithString: "")
  private let deviceStack = NSStackView()
  private var deviceChecks: [NSButton] = []
  private let displayPopup = NSPopUpButton()
  private let protocolPopup = NSPopUpButton()
  private let connectedPopup = NSPopUpButton()
  private let disconnectedPopup = NSPopUpButton()
  private let connectDelayField = NSTextField()
  private let disconnectDelayField = NSTextField()
  private let enabledCheckbox = NSButton(checkboxWithTitle: "Switch automatically", target: nil, action: nil)
  private var keyboards: [PairedDevice] = []
  private var displays: [(label: String, name: String, identity: DisplayIdentity)] = []

  init(controller: AutomationController, pairedDevices: @escaping () -> [PairedDevice]? = BluetoothState.pairedDevices,
       displays: @escaping () -> [DisplayCandidate] = DisplayCandidate.all,
       hidEntries: @escaping () -> [HIDEntry]? = HIDRegistryWatcher.bluetoothEntries) {
    self.controller = controller
    self.pairedDevices = pairedDevices
    self.displayCandidates = displays
    self.hidEntries = hidEntries
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewWillAppear() {
    super.viewWillAppear()
    self.load(self.controller.config)
  }

  override func loadView() {
    self.view = NSView(frame: NSRect(x: 0, y: 0, width: 650, height: 560))
    self.view.widthAnchor.constraint(equalToConstant: 650).isActive = true
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
    self.deviceStack.orientation = .vertical
    self.deviceStack.alignment = .leading
    self.deviceStack.spacing = 4
    let note = NSTextField(wrappingLabelWithString: "Only selected devices count. With several selected, the connected input is used once all are connected and the disconnected input once all are disconnected; in between, the input is left alone. Changes start from the current state without sending a command. Monitors do not confirm input commands.")
    note.textColor = .secondaryLabelColor
    let grid = NSGridView(views: [
      [label("Bluetooth devices:"), self.deviceStack],
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
    let cancel = NSButton(title: "Revert", target: self, action: #selector(self.cancel))
    let save = NSButton(title: "Save Changes", target: self, action: #selector(self.save))
    let buttons = NSStackView(views: [refresh, NSView(), cancel, save])
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    scroll.documentView = self.deviceDocument
    self.deviceDocument.addSubview(self.deviceStack)
    self.deviceStack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      self.deviceStack.leadingAnchor.constraint(equalTo: self.deviceDocument.leadingAnchor, constant: 6),
      self.deviceStack.topAnchor.constraint(equalTo: self.deviceDocument.topAnchor, constant: 6),
      self.deviceStack.widthAnchor.constraint(equalTo: self.deviceDocument.widthAnchor, constant: -12),
      scroll.heightAnchor.constraint(equalToConstant: 125),
    ])
    grid.cell(atColumnIndex: 1, rowIndex: 0).contentView = scroll
    self.migrationButton.target = self
    self.migrationButton.action = #selector(self.retireCompanion)
    let stack = NSStackView(views: [grid, note, self.migrationButton, self.savedLabel, buttons])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    stack.translatesAutoresizingMaskIntoConstraints = false
    self.view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
      stack.topAnchor.constraint(equalTo: self.view.topAnchor),
      stack.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
      grid.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
      buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
      note.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
      self.displayPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
    ])
    self.load(self.controller.config)
  }

  /// Saved choices stay visible, marked unavailable, when the device is not present now.
  private func load(_ c: CompanionConfig) {
    self.migrationButton.isHidden = !LegacyCompanion.isPresent
    self.keyboards = self.pairedDevices() ?? []
    let saved = Set(c.devices.compactMap { CompanionConfig.normalizedAddress($0.address) })
    for device in c.devices {
      guard let address = CompanionConfig.normalizedAddress(device.address), !self.keyboards.contains(where: { $0.address == address }) else { continue }
      self.keyboards.append(PairedDevice(name: device.name + " (unavailable: not paired)", address: address, connected: false))
    }
    self.deviceChecks.forEach { self.deviceStack.removeArrangedSubview($0); $0.removeFromSuperview() }
    self.deviceChecks = self.keyboards.map { device in
      let check = NSButton(checkboxWithTitle: "\(device.name) — \(device.connected ? "connected" : "not connected")", target: nil, action: nil)
      check.state = saved.contains(device.address) ? .on : .off
      check.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      check.toolTip = "\(device.name) — Bluetooth \(device.address.uppercased())"
      return check
    }
    self.deviceChecks.forEach { self.deviceStack.addArrangedSubview($0) }
    self.deviceDocument.frame = NSRect(x: 0, y: 0, width: 440, height: max(125, CGFloat(self.deviceChecks.count) * 24 + 12))

    self.displays = self.displayCandidates().map { ($0.label, $0.name, $0.identity) }
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
    self.savedLabel.stringValue = self.controller.configError ?? ""
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

  @objc private func cancel() { self.load(self.controller.config) }

  private func collect() -> CompanionConfig {
    var c = self.controller.config
    let entries = self.hidEntries()
    c.devices = zip(self.keyboards, self.deviceChecks).filter { $0.1.state == .on }.map { device, _ in
      // Keep saved identity; learn vendor/product IDs only from the live HID entry of a newly chosen address.
      if var existing = self.controller.config.devices.first(where: { CompanionConfig.normalizedAddress($0.address) == device.address }) {
        if let live = entries?.first(where: { CompanionConfig.normalizedAddress($0.address) == device.address }) {
          if existing.vendorID == nil { existing.vendorID = live.vendorID }
          if existing.productID == nil { existing.productID = live.productID }
        }
        return existing
      }
      let entry = entries?.first { CompanionConfig.normalizedAddress($0.address) == device.address }
      return SelectedDevice(address: device.address, name: device.name, vendorID: entry?.vendorID, productID: entry?.productID)
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

  @objc private func retireCompanion() {
    do {
      let wasEnabledAtLogin = FileManager.default.fileExists(atPath: LegacyCompanion.plist.path)
      try LegacyCompanion.retire()
      self.controller.displayDidChange()
      let loginReady = !wasEnabledAtLogin || app.setStartAtLogin(enabled: true)
      self.load(self.controller.config)
      self.savedLabel.stringValue = loginReady ? "Old companion retired. Saved devices and inputs were kept."
        : "Companion retired. Check Start at Login in General; macOS did not register the login helper."
    } catch { NSAlert(error: error).runModal() }
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
      self.load(self.controller.config)
      self.savedLabel.stringValue = "Changes saved. Tracking restarts without switching inputs."
    } catch {
      NSAlert(error: error).runModal()
    }
  }
}

private final class AutomationDeviceDocument: NSView {
  override var isFlipped: Bool { true }
}
