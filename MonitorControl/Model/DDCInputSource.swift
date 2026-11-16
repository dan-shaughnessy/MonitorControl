//  Copyright © MonitorControl contributors

import Foundation

/// Common assignments, not a detected inventory of a monitor's physical ports.
struct DDCInputSource: Equatable {
  let title: String
  let value: UInt16

  enum InputProtocol: Int, CaseIterable {
    case standard = 0
    case lgAlternate = 1

    var title: String {
      switch self {
      case .standard: return NSLocalizedString("Standard DDC", comment: "Input source protocol")
      case .lgAlternate: return NSLocalizedString("LG alternate", comment: "Input source protocol")
      }
    }

    var command: UInt8 { self == .standard ? 0x60 : 0xF4 }
    var sourceAddress: UInt8 { self == .standard ? 0x51 : 0x50 }

    var sources: [DDCInputSource] {
      switch self {
      case .standard:
        return [DDCInputSource(title: "HDMI 1", value: 0x11), DDCInputSource(title: "HDMI 2", value: 0x12),
                DDCInputSource(title: "DisplayPort 1", value: 0x0F), DDCInputSource(title: "DisplayPort 2 / USB-C", value: 0x10)]
      case .lgAlternate:
        return [DDCInputSource(title: "HDMI 1", value: 0x90), DDCInputSource(title: "HDMI 2", value: 0x91),
                DDCInputSource(title: "DisplayPort 1", value: 0xD0), DDCInputSource(title: "DisplayPort 2 / USB-C", value: 0xD1),
                DDCInputSource(title: "DisplayPort 3 / USB-C", value: 0xD2)]
      }
    }
  }

  /// Includes the host source address and checksum; the destination is always 0x6E (7-bit 0x37).
  static func writePacket(command: UInt8, value: UInt16, sourceAddress: UInt8) -> [UInt8] {
    let bytes: [UInt8] = [sourceAddress, 0x84, 0x03, command, UInt8(value >> 8), UInt8(value & 0xFF)]
    return bytes + [bytes.reduce(0x6E, ^)]
  }

  /// Reject unsupported, unrelated and malformed Get VCP replies, even with a valid checksum.
  static func currentValue(from reply: [UInt8], command: UInt8) -> UInt16? {
    guard reply.count == 11, reply[0] == 0x6E, reply[1] == 0x88,
          reply[2] == 0x02, reply[3] == 0, reply[4] == command,
          reply.reduce(0x50, ^) == 0 else { return nil }
    return UInt16(reply[8]) << 8 | UInt16(reply[9])
  }
}

/// Cancels queued commands when the display sleeps or is reconfigured. Never wait on
/// the main queue from the DDC queue: upstream also performs synchronous DDC reads.
final class DDCInputSourceSession {
  private let lock = NSLock()
  private var valid = true

  var isValid: Bool {
    self.lock.lock()
    defer { self.lock.unlock() }
    return self.valid
  }

  func invalidate() {
    self.lock.lock()
    self.valid = false
    self.lock.unlock()
  }
}
