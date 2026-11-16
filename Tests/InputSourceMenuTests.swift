import AppKit

// A display fake lets the real AppKit menu run without touching monitor hardware.
final class OtherDisplay {
  var canControlInputSource = true
  var inputSourceBusy = false
  var inputSourceProtocol = DDCInputSource.InputProtocol.standard
  var lastRequest = ""
  var pendingRead: ((UInt16?) -> Void)?
  var pendingWrite: ((Bool) -> Void)?
  var requested: DDCInputSource?
  func readPrefAsString(key: PrefKey) -> String { self.lastRequest }
  func savePref(_ value: Int, key: PrefKey) { self.inputSourceProtocol = DDCInputSource.InputProtocol(rawValue: value)! }
  func readInputSource(completion: @escaping (UInt16?) -> Void) { self.pendingRead = completion }
  func requestInputSource(_ source: DDCInputSource, completion: @escaping (Bool) -> Void) {
    self.requested = source
    self.inputSourceBusy = true
    self.pendingWrite = completion
  }
}

@main
struct InputSourceMenuTests {
  static func main() {
    _ = NSApplication.shared
    let display = OtherDisplay()
    let menu = InputSourceMenu(display: display)
    precondition(menu.item(withTitle: "HDMI 1") != nil)
    menu.menuWillOpen(menu)
    precondition(menu.item(withTitle: "HDMI 1")?.isEnabled == false, "Disable source selection during readback")
    display.pendingRead?(0x11)
    precondition(menu.item(withTitle: "HDMI 1")?.state == .on)
    precondition(menu.item(withTitle: "HDMI 2")?.state == .off)
    menu.menuWillOpen(menu)
    display.pendingRead?(nil)
    precondition(menu.item(withTitle: "HDMI 1")?.state == .off, "A failed read clears old checkmarks")
    let protocolMenu = menu.item(withTitle: "Input Protocol")!.submenu!
    let lgOption = protocolMenu.item(withTitle: "LG alternate")!
    NSApp.sendAction(lgOption.action!, to: lgOption.target, from: lgOption)
    precondition(display.inputSourceProtocol == .lgAlternate, "Protocol selection persists on the display")
    precondition(menu.item(withTitle: "DisplayPort 3 / USB-C")?.tag == 0xD2)
    let hdmi = menu.item(withTitle: "HDMI 2")!
    NSApp.sendAction(hdmi.action!, to: hdmi.target, from: hdmi)
    precondition(display.requested?.value == 0x91)
    precondition(menu.item(withTitle: "HDMI 1")?.isEnabled == false, "Prevent overlapping writes")
    display.inputSourceBusy = false
    display.lastRequest = "HDMI 2 (LG alternate)"
    display.pendingWrite?(true)
    precondition(menu.item(withTitle: "HDMI 2")?.state == .off, "Sending a command does not confirm the active input")
    precondition(menu.items.contains { $0.title == "Command sent; input change unverified" })
    display.canControlInputSource = false
    menu.menuWillOpen(menu)
    precondition(menu.item(withTitle: "HDMI 1")?.isEnabled == false, "Disable unavailable hardware")
    let recreatedMenu = InputSourceMenu(display: display)
    precondition(recreatedMenu.item(withTitle: "DisplayPort 3 / USB-C") != nil)
    precondition(recreatedMenu.items.contains { $0.title == "Last requested: HDMI 2 (LG alternate)" })
    print("Native input menu state, routing and persistence tests passed")
  }
}
