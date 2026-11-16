//  Copyright © MonitorControl contributors

import Foundation
import IOKit.hid

/// Only the LG HID-to-I2C interface is used. Never open the serial/debug interface.
/// Correlate by the display's alphanumeric EDID serial, never by first LG device found.
final class LGUSBInputControl {
  private let serialNumber: String

  init?(serialNumber: String) {
    guard !serialNumber.isEmpty else { return nil }
    self.serialNumber = serialNumber
    guard self.device() != nil else { return nil }
  }

  static func matches(serialNumber: String, expectedSerialNumber: String, usagePage: Int) -> Bool {
    !expectedSerialNumber.isEmpty && serialNumber == expectedSerialNumber && usagePage == 0xFF00
  }

  private func device() -> IOHIDDevice? {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x043E, kIOHIDProductIDKey: 0x9A8A] as CFDictionary)
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
    let matches = devices.filter { device in
      let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? ""
      let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
      return Self.matches(serialNumber: serial, expectedSerialNumber: self.serialNumber, usagePage: usage)
    }
    return matches.count == 1 ? matches.first : nil
  }

  /// Call on the serial DDC queue. A successful USB write is not physical confirmation.
  func write(value: UInt16, canWrite: () -> Bool = { true }) -> Bool {
    guard DDCInputSource.InputProtocol.lgUSB.sources.contains(where: { $0.value == value }),
          let device = self.device(), IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else { return false }
    defer { IOHIDDeviceClose(device, 0) }
    guard canWrite() else { return false }
    var report = DDCInputSource.lgUSBWriteReport(value: value)
    return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), &report, report.count) == kIOReturnSuccess
  }
}
