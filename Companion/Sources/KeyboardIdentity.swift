//  Copyright © MonitorControl contributors

import Foundation

/// Registry facts about one HID device. No reports or key data are read.
struct HIDEntry: Equatable {
  var address: String
  var transport: String
  var vendorID: Int?
  var productID: Int?
}

enum KeyboardIdentity {
  /// - Bluetooth off or unreadable, or the keyboard not paired: unknown.
  /// - Paired, Bluetooth on and no HID entry for its address: disconnected.
  /// - An entry with the address but the wrong transport or IDs: unknown (never act on a lookalike).
  static func presence(powerOn: Bool?, paired: Bool?, entries: [HIDEntry], device: SelectedDevice) -> KeyboardPresence {
    guard powerOn == true, paired == true, let address = CompanionConfig.normalizedAddress(device.address) else { return .unknown }
    let sameAddress = entries.filter { CompanionConfig.normalizedAddress($0.address) == address }
    if sameAddress.isEmpty { return .disconnected }
    let exact = sameAddress.contains { entry in
      entry.transport.lowercased().contains("bluetooth")
        && (device.vendorID == nil || entry.vendorID == device.vendorID)
        && (device.productID == nil || entry.productID == device.productID)
    }
    return exact ? .connected : .unknown
  }

  /// Any unknown device makes the whole set unknown, so a half-known set never acts.
  static func aggregate(_ states: [KeyboardPresence]) -> KeyboardPresence {
    if states.isEmpty || states.contains(.unknown) { return .unknown }
    if states.allSatisfy({ $0 == .connected }) { return .connected }
    if states.allSatisfy({ $0 == .disconnected }) { return .disconnected }
    return .mixed
  }
}
