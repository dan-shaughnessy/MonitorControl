//  Copyright © MonitorControl contributors

import CoreGraphics
import Foundation
import IOBluetooth
import IOKit

/// Watches IOKit HID registry entries. Devices are never opened, so no key data is available
/// and no Input Monitoring permission is needed.
final class HIDRegistryWatcher {
  private var port: IONotificationPortRef?
  private var iterators: [io_iterator_t] = []
  private let onChange: () -> Void

  init(onChange: @escaping () -> Void) {
    self.onChange = onChange
  }

  deinit { self.stop() }

  /// Matched/terminated notifications for HID devices with this Bluetooth address.
  func start(address: String) {
    self.stop()
    guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
    self.port = port
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
    let context = Unmanaged.passUnretained(self).toOpaque()
    let callback: IOServiceMatchingCallback = { context, iterator in
      HIDRegistryWatcher.drain(iterator)
      guard let context = context else { return }
      Unmanaged<HIDRegistryWatcher>.fromOpaque(context).takeUnretainedValue().onChange()
    }
    for type in [kIOMatchedNotification, kIOTerminatedNotification] {
      let matching = IOServiceMatching("IOHIDDevice") as NSMutableDictionary
      matching[kIOPropertyMatchKey] = ["DeviceAddress": address]
      var iterator: io_iterator_t = 0
      if IOServiceAddMatchingNotification(port, type, matching, callback, context, &iterator) == KERN_SUCCESS {
        Self.drain(iterator) // Arms the notification.
        self.iterators.append(iterator)
      }
    }
  }

  func stop() {
    self.iterators.forEach { IOObjectRelease($0) }
    self.iterators = []
    if let port = self.port { IONotificationPortDestroy(port) }
    self.port = nil
  }

  private static func drain(_ iterator: io_iterator_t) {
    while case let entry = IOIteratorNext(iterator), entry != 0 { IOObjectRelease(entry) }
  }

  /// Bluetooth HID registry entries. Returns nil if the registry query fails.
  static func bluetoothEntries() -> [HIDEntry]? {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iterator) }
    var result: [HIDEntry] = []
    while case let entry = IOIteratorNext(iterator), entry != 0 {
      defer { IOObjectRelease(entry) }
      func prop(_ key: String) -> Any? { IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
      guard let address = prop("DeviceAddress") as? String, let transport = prop("Transport") as? String,
            transport.lowercased().contains("bluetooth") else { continue }
      result.append(HIDEntry(address: address, transport: transport, vendorID: (prop("VendorID") as? NSNumber)?.intValue,
                             productID: (prop("ProductID") as? NSNumber)?.intValue))
    }
    return result
  }
}

struct PairedDevice: Equatable {
  var name: String
  var address: String
  var connected: Bool
}

enum BluetoothState {
  static func powerOn() -> Bool? {
    guard let controller = IOBluetoothHostController.default() else { return nil }
    return controller.powerState == kBluetoothHCIPowerStateON
  }

  static func pairedDevices() -> [PairedDevice]? {
    guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
    return devices.compactMap { device in
      guard let raw = device.addressString, let address = CompanionConfig.normalizedAddress(raw) else { return nil }
      return PairedDevice(name: device.name ?? address, address: address, connected: device.isConnected())
    }
  }

  static func isPaired(_ address: String) -> Bool? {
    guard let devices = self.pairedDevices() else { return nil }
    return devices.contains { $0.address == address }
  }
}

struct DisplayCandidate {
  var displayID: CGDirectDisplayID
  var name: String
  var identity: DisplayIdentity
  var service: IOAVService?

  var label: String {
    String(format: "%@ (%@, product 0x%04X)", self.name, self.identity.serial, self.identity.productID)
  }

  /// External displays with a DDC service, from MonitorControl's own Apple Silicon matching.
  static func all() -> [DisplayCandidate] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return [] }
    return Arm64DDC.getServiceMatches(displayIDs: Array(ids[0 ..< Int(count)])).compactMap { match in
      let details = match.serviceDetails
      guard match.service != nil, !match.dummy,
            let product = details.displayAttributes?.value(forKeyPath: "ProductAttributes.ProductID") as? NSNumber,
            let vendor = details.displayAttributes?.value(forKeyPath: "ProductAttributes.LegacyManufacturerID") as? NSNumber
      else { return nil }
      return DisplayCandidate(displayID: match.displayID, name: details.productName,
                              identity: DisplayIdentity(serial: details.alphanumericSerialNumber, vendorID: vendor.intValue, productID: product.intValue),
                              service: match.service)
    }
  }

  static func find(_ config: CompanionConfig) -> DisplayCandidate? {
    guard let vendor = config.displayVendorID, let product = config.displayProductID else { return nil }
    return DisplayIdentity.uniqueMatch(self.all(), identity: { $0.identity },
                                       expected: DisplayIdentity(serial: config.displaySerial, vendorID: vendor, productID: product))
  }

  /// Resolves the display at write time, so a dock or monitor change is never written to a stale service.
  static func write(_ source: DDCInputSource, config: CompanionConfig) -> WriteAttempt {
    guard let proto = config.protocolValue, proto.sources.contains(source) else { return .failed }
    guard let display = self.find(config) else { return .displayUnavailable }
    let ok = Arm64DDC.write(service: display.service, command: proto.command, value: source.value,
                            sourceAddress: proto.sourceAddress, numOfWriteCycles: 1, numOfRetryAttemps: 0)
    return ok ? .sent : .failed
  }
}
