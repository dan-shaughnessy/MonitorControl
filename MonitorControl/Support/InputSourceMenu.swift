//  Copyright © MonitorControl contributors

import AppKit

/// Native menu rows remain keyboard accessible, including when sliders are combined or hidden.
class InputSourceMenu: NSMenu, NSMenuDelegate {
  private weak var display: OtherDisplay?
  private var currentValue: UInt16?
  private var status = NSLocalizedString("Current input unavailable", comment: "Input source status")
  private var isReading = false

  init(display: OtherDisplay) {
    self.display = display
    super.init(title: NSLocalizedString("Input Source", comment: "Shown in menu"))
    self.autoenablesItems = false
    self.delegate = self
    self.rebuild()
  }

  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func info(_ title: String) {
    let item = self.addItem(withTitle: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
  }

  private func rebuild() {
    self.removeAllItems()
    guard let display = self.display else { return }
    let inputProtocol = display.inputSourceProtocol
    self.info(self.status)
    let lastRequest = display.readPrefAsString(key: .lastRequestedInputSource)
    if !lastRequest.isEmpty {
      self.info(String(format: NSLocalizedString("Last requested: %@", comment: "Input source status, not confirmation"), lastRequest))
    }
    self.addItem(.separator())
    for source in inputProtocol.sources {
      let item = self.addItem(withTitle: source.title, action: #selector(self.selectSource(_:)), keyEquivalent: "")
      item.target = self
      item.tag = Int(source.value)
      item.state = self.currentValue == source.value ? .on : .off
      item.isEnabled = display.canControlInputSource && !display.inputSourceBusy && !self.isReading
    }
    self.addItem(.separator())
    let protocolMenu = NSMenu()
    protocolMenu.autoenablesItems = false
    for option in DDCInputSource.InputProtocol.allCases {
      let item = protocolMenu.addItem(withTitle: option.title, action: #selector(self.selectProtocol(_:)), keyEquivalent: "")
      item.target = self
      item.tag = option.rawValue
      item.state = inputProtocol == option ? .on : .off
      item.isEnabled = !display.inputSourceBusy && !self.isReading && (option != .lgUSB || display.supportsLGUSBInput)
    }
    let protocolItem = self.addItem(withTitle: NSLocalizedString("Input Protocol", comment: "Input source submenu"), action: nil, keyEquivalent: "")
    protocolItem.submenu = protocolMenu
    self.addItem(.separator())
    self.info(NSLocalizedString("Common inputs; available ports vary by monitor", comment: "Input source help"))
    self.info(NSLocalizedString("Use monitor buttons to return if needed", comment: "Input source help"))
  }

  func menuWillOpen(_: NSMenu) {
    self.currentValue = nil
    guard let display = self.display else { return }
    if !display.canControlInputSource {
      self.status = NSLocalizedString("DDC unavailable — reconnect or check display settings", comment: "Input source status")
      self.rebuild()
      return
    }
    if display.inputSourceBusy {
      self.status = NSLocalizedString("Sending input command…", comment: "Input source status")
    } else if display.inputSourceProtocol != .standard {
      self.status = NSLocalizedString("Input change unverified; readback unavailable", comment: "Input source status")
    } else if !self.isReading {
      self.isReading = true
      self.status = NSLocalizedString("Reading current input…", comment: "Input source status")
      display.readInputSource { [weak self] value in
        guard let self = self else { return }
        self.isReading = false
        self.currentValue = value
        self.status = value.map { String(format: NSLocalizedString("Current input: 0x%02X", comment: "Input source status"), Int($0)) }
          ?? NSLocalizedString("Current input unavailable", comment: "Input source status")
        self.rebuild()
      }
    }
    self.rebuild()
  }

  @objc private func selectProtocol(_ sender: NSMenuItem) {
    guard let display = self.display, !display.inputSourceBusy, !self.isReading,
          let inputProtocol = DDCInputSource.InputProtocol(rawValue: sender.tag) else { return }
    display.savePref(inputProtocol.rawValue, key: .inputSourceProtocol)
    self.currentValue = nil
    self.status = NSLocalizedString("Current input unavailable", comment: "Input source status")
    self.rebuild()
  }

  @objc private func selectSource(_ sender: NSMenuItem) {
    guard let display = self.display,
          let source = display.inputSourceProtocol.sources.first(where: { Int($0.value) == sender.tag }) else { return }
    self.currentValue = nil
    display.requestInputSource(source) { [weak self] sent in
      self?.status = sent ? NSLocalizedString("Command sent; input change unverified", comment: "Input source status")
        : NSLocalizedString("Command failed — check connection or input protocol", comment: "Input source status")
      self?.rebuild()
      if !sent {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Could not send input command", comment: "Input source error")
        alert.informativeText = NSLocalizedString("Check the monitor connection and DDC settings. For compatible LG monitors, try Input Protocol → LG alternate or LG USB. LG USB requires a matching USB control connection. You can always use the monitor’s input buttons.", comment: "Input source error recovery")
        alert.runModal()
      }
    }
    self.rebuild()
  }
}
