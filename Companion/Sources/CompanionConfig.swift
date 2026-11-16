//  Copyright © MonitorControl contributors

import Foundation

/// One Bluetooth device whose presence counts toward switching.
struct SelectedDevice: Codable, Equatable {
  var address: String
  var name: String
  var vendorID: Int?
  var productID: Int?
}

/// User settings, saved as JSON. Effective runtime state is never stored here.
struct CompanionConfig: Codable, Equatable {
  static let supportedProtocols: [DDCInputSource.InputProtocol] = [.lgAlternate, .standard]
  /// 0 acts as soon as the registry reports the change.
  static let connectDelayRange: ClosedRange<Double> = 0 ... 30
  static let disconnectDelayRange: ClosedRange<Double> = 0 ... 300

  var enabled = false
  /// Connected input when all are connected; disconnected input when all are disconnected.
  var devices: [SelectedDevice] = []
  var displayName = ""
  var displaySerial = ""
  var displayVendorID: Int?
  var displayProductID: Int?
  var inputProtocol = DDCInputSource.InputProtocol.lgAlternate.rawValue
  /// nil means "do nothing" for that edge.
  var connectedInput: Int? = 0x90
  var disconnectedInput: Int? = 0xD1
  var connectDelay = 2.0
  var disconnectDelay = 10.0

  init() {}

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = CompanionConfig()
    self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
    if let devices = try c.decodeIfPresent([SelectedDevice].self, forKey: .devices) {
      self.devices = devices
    } else if let address = try c.decodeIfPresent(String.self, forKey: .keyboardAddress), !address.isEmpty {
      // Single-keyboard settings from the first release.
      self.devices = [SelectedDevice(address: address, name: try c.decodeIfPresent(String.self, forKey: .keyboardName) ?? address,
                                     vendorID: try c.decodeIfPresent(Int.self, forKey: .keyboardVendorID),
                                     productID: try c.decodeIfPresent(Int.self, forKey: .keyboardProductID))]
    }
    self.displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? d.displayName
    self.displaySerial = try c.decodeIfPresent(String.self, forKey: .displaySerial) ?? d.displaySerial
    self.displayVendorID = try c.decodeIfPresent(Int.self, forKey: .displayVendorID)
    self.displayProductID = try c.decodeIfPresent(Int.self, forKey: .displayProductID)
    self.inputProtocol = try c.decodeIfPresent(Int.self, forKey: .inputProtocol) ?? d.inputProtocol
    // An absent key keeps the default; an explicit null means "do nothing".
    self.connectedInput = c.contains(.connectedInput) ? try c.decodeIfPresent(Int.self, forKey: .connectedInput) : d.connectedInput
    self.disconnectedInput = c.contains(.disconnectedInput) ? try c.decodeIfPresent(Int.self, forKey: .disconnectedInput) : d.disconnectedInput
    self.connectDelay = try c.decodeIfPresent(Double.self, forKey: .connectDelay) ?? d.connectDelay
    self.disconnectDelay = try c.decodeIfPresent(Double.self, forKey: .disconnectDelay) ?? d.disconnectDelay
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(self.enabled, forKey: .enabled)
    try c.encode(self.devices, forKey: .devices)
    try c.encode(self.displayName, forKey: .displayName)
    try c.encode(self.displaySerial, forKey: .displaySerial)
    try c.encode(self.displayVendorID, forKey: .displayVendorID)
    try c.encode(self.displayProductID, forKey: .displayProductID)
    try c.encode(self.inputProtocol, forKey: .inputProtocol)
    try c.encode(self.connectedInput, forKey: .connectedInput)
    try c.encode(self.disconnectedInput, forKey: .disconnectedInput)
    try c.encode(self.connectDelay, forKey: .connectDelay)
    try c.encode(self.disconnectDelay, forKey: .disconnectDelay)
  }

  enum CodingKeys: String, CodingKey {
    case enabled, devices, keyboardAddress, keyboardName, keyboardVendorID, keyboardProductID
    case displayName, displaySerial, displayVendorID, displayProductID
    case inputProtocol, connectedInput, disconnectedInput, connectDelay, disconnectDelay
  }

  /// Bluetooth addresses appear as "aa:bb:…" or "aa-bb-…"; IOKit uses lower-case dashes.
  static func normalizedAddress(_ address: String) -> String? {
    let parts = address.lowercased().replacingOccurrences(of: ":", with: "-").split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 6, parts.allSatisfy({ $0.count == 2 && UInt8($0, radix: 16) != nil }) else { return nil }
    return parts.joined(separator: "-")
  }

  var protocolValue: DDCInputSource.InputProtocol? {
    guard let p = DDCInputSource.InputProtocol(rawValue: self.inputProtocol), Self.supportedProtocols.contains(p) else { return nil }
    return p
  }

  /// Only values listed for the selected protocol are ever written.
  func input(for presence: KeyboardPresence) -> DDCInputSource? {
    guard let p = self.protocolValue else { return nil }
    let value: Int?
    switch presence {
    case .connected: value = self.connectedInput
    case .disconnected: value = self.disconnectedInput
    case .mixed, .unknown: value = nil
    }
    guard let value = value else { return nil }
    return p.sources.first { Int($0.value) == value }
  }

  /// Reasons this configuration cannot act. Empty means it is complete.
  var problems: [String] {
    var result: [String] = []
    let addresses = self.devices.map { Self.normalizedAddress($0.address) }
    if addresses.isEmpty { result.append("No Bluetooth device selected") }
    if addresses.contains(nil) { result.append("A selected device has an invalid address") }
    if Set(addresses.compactMap { $0 }).count != addresses.compactMap({ $0 }).count { result.append("A device is selected twice") }
    if self.displaySerial.isEmpty || self.displayProductID == nil || self.displayVendorID == nil { result.append("No monitor selected") }
    if self.protocolValue == nil { result.append("Unsupported input protocol") }
    if self.connectedInput != nil, self.input(for: .connected) == nil { result.append("Connected input is not valid for this protocol") }
    if self.disconnectedInput != nil, self.input(for: .disconnected) == nil { result.append("Disconnected input is not valid for this protocol") }
    if !Self.connectDelayRange.contains(self.connectDelay) { result.append("Connect delay out of range") }
    if !Self.disconnectDelayRange.contains(self.disconnectDelay) { result.append("Disconnect delay out of range") }
    return result
  }

  var devicesSummary: String {
    self.devices.isEmpty ? "No device selected" : self.devices.map(\.name).joined(separator: " + ")
  }

  var timing: PolicyTiming {
    PolicyTiming(connectDelay: self.connectDelay, disconnectDelay: self.disconnectDelay)
  }
}

struct ConfigStore {
  let url: URL

  static var defaultDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LGInputCompanion", isDirectory: true)
  }

  /// A missing file gives a disabled, unconfigured default. A corrupt file is reported, never silently replaced.
  func load() throws -> CompanionConfig {
    guard FileManager.default.fileExists(atPath: self.url.path) else { return CompanionConfig() }
    return try JSONDecoder().decode(CompanionConfig.self, from: Data(contentsOf: self.url))
  }

  func save(_ config: CompanionConfig) throws {
    try FileManager.default.createDirectory(at: self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(config).write(to: self.url, options: .atomic)
  }
}
