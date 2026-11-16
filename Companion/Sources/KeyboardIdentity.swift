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
  static func presence(powerOn: Bool?, paired: Bool?, entries: [HIDEntry], config: CompanionConfig) -> KeyboardPresence {
    guard powerOn == true, paired == true, let address = CompanionConfig.normalizedAddress(config.keyboardAddress) else { return .unknown }
    let sameAddress = entries.filter { CompanionConfig.normalizedAddress($0.address) == address }
    if sameAddress.isEmpty { return .disconnected }
    let exact = sameAddress.contains { entry in
      entry.transport.lowercased().contains("bluetooth")
        && (config.keyboardVendorID == nil || entry.vendorID == config.keyboardVendorID)
        && (config.keyboardProductID == nil || entry.productID == config.keyboardProductID)
    }
    return exact ? .connected : .unknown
  }
}
