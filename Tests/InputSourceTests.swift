import Foundation

@main
struct InputSourceTests {
  static func main() {
    let usbHDMI = DDCInputSource.lgUSBWriteReport(value: 0x90)
    precondition(usbHDMI.count == 64)
    precondition(Array(usbHDMI.prefix(15)) == [0x08, 0x01, 0x55, 0x03, 0x07, 0, 0x03, 0x37, 0x50, 0x04, 0x03, 0xF4, 0, 0x90, 0x5D])
    precondition(usbHDMI.dropFirst(15).allSatisfy { $0 == 0 })
    let usbReturn = DDCInputSource.lgUSBWriteReport(value: 0xD1)
    precondition(usbReturn[9] == 0x04, "LG USB requires 0x04, not the video DDC length 0x84")
    precondition(usbReturn[13] == 0xD1)
    precondition(usbReturn[8 ... 14].reduce(0x6E, ^) == 0)
    precondition(!LGUSBInputControl.matches(serialNumber: "", expectedSerialNumber: "", usagePage: 0xFF00))
    precondition(!LGUSBInputControl.matches(serialNumber: "OTHER", expectedSerialNumber: "LG123", usagePage: 0xFF00))
    precondition(!LGUSBInputControl.matches(serialNumber: "LG123", expectedSerialNumber: "LG123", usagePage: 0xFF01))
    precondition(LGUSBInputControl.matches(serialNumber: "LG123", expectedSerialNumber: "LG123", usagePage: 0xFF00))
    precondition(DDCInputSource.InputProtocol.resolve(savedValue: nil, usbAvailable: true) == .lgUSB)
    precondition(DDCInputSource.InputProtocol.resolve(savedValue: nil, usbAvailable: false) == .standard)
    precondition(DDCInputSource.InputProtocol.resolve(savedValue: 0, usbAvailable: true) == .standard)
    precondition(DDCInputSource.InputProtocol.resolve(savedValue: 2, usbAvailable: false) == .lgUSB)
    let standard = DDCInputSource.InputProtocol.standard
    let lg = DDCInputSource.InputProtocol.lgAlternate
    precondition(standard.command == 0x60 && standard.sourceAddress == 0x51)
    precondition(lg.command == 0xF4 && lg.sourceAddress == 0x50)
    precondition(standard.sources.map(\.value) == [0x11, 0x12, 0x0F, 0x10])
    precondition(lg.sources.map(\.value) == [0x90, 0x91, 0xD0, 0xD1, 0xD2])
    precondition(DDCInputSource.writePacket(command: 0x60, value: 0x11, sourceAddress: 0x51) == [0x51, 0x84, 0x03, 0x60, 0, 0x11, 0xC9])
    precondition(DDCInputSource.writePacket(command: 0xF4, value: 0xD1, sourceAddress: 0x50) == [0x50, 0x84, 0x03, 0xF4, 0, 0xD1, 0x9C])
    // High byte survives packet generation; each transport uses the same bytes/checksum.
    precondition(DDCInputSource.writePacket(command: 0x60, value: 0x1234, sourceAddress: 0x51).dropLast().suffix(2) == [0x12, 0x34])
    func reply(status: UInt8 = 0, command: UInt8 = 0x60, value: UInt16 = 0x11) -> [UInt8] {
      let bytes: [UInt8] = [0x6E, 0x88, 0x02, status, command, 0, 0, 0x12, UInt8(value >> 8), UInt8(value & 0xFF)]
      return bytes + [bytes.reduce(0x50, ^)]
    }
    precondition(DDCInputSource.currentValue(from: reply(), command: 0x60) == 0x11)
    precondition(DDCInputSource.currentValue(from: reply(value: 0x1234), command: 0x60) == 0x1234)
    // Valid checksums alone do not prove support or identify the requested VCP.
    precondition(DDCInputSource.currentValue(from: reply(status: 1), command: 0x60) == nil)
    precondition(DDCInputSource.currentValue(from: reply(command: 0x10), command: 0x60) == nil)
    precondition(DDCInputSource.currentValue(from: Array(reply().dropLast()), command: 0x60) == nil)
    var corrupt = reply()
    corrupt[10] ^= 1
    precondition(DDCInputSource.currentValue(from: corrupt, command: 0x60) == nil)
    for inputProtocol in DDCInputSource.InputProtocol.allCases {
      precondition(Set(inputProtocol.sources.map(\.value)).count == inputProtocol.sources.count)
      for source in inputProtocol.sources {
        let bytes = DDCInputSource.writePacket(command: inputProtocol.command, value: source.value, sourceAddress: inputProtocol.sourceAddress)
        precondition(bytes.reduce(0x6E, ^) == 0)
      }
    }
    let session = DDCInputSourceSession()
    precondition(session.isValid)
    let queue = DispatchQueue(label: "Input source cancellation test")
    let ready = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    let done = DispatchSemaphore(value: 0)
    queue.async {
      ready.signal()
      resume.wait()
      precondition(!session.isValid, "A queued command must not survive reconfiguration")
      done.signal()
    }
    ready.wait()
    session.invalidate()
    session.invalidate()
    resume.signal()
    precondition(done.wait(timeout: .now() + 2) == .success)
    precondition(DDCInputSourceSession().isValid, "A new connection gets a fresh session")
    print("Input source protocol, packet, readback and cancellation tests passed")
  }
}
