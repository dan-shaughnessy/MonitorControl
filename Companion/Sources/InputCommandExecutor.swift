//  Copyright © MonitorControl contributors

import Foundation

struct DisplayIdentity: Equatable {
  var serial: String
  var vendorID: Int
  var productID: Int

  /// The LG reports a different EDID product ID per port (HDMI 0x7845, USB-C 0x7847), so all three must match.
  static func uniqueMatch<T>(_ candidates: [T], identity: (T) -> DisplayIdentity, expected: DisplayIdentity) -> T? {
    guard !expected.serial.isEmpty else { return nil }
    let matches = candidates.filter { identity($0) == expected }
    return matches.count == 1 ? matches[0] : nil
  }
}

enum WriteAttempt {
  case sent
  case failed
  case displayUnavailable
}

enum CommandResult: Equatable {
  case sent(attempts: Int)
  case failed(attempts: Int)
  case displayUnavailable
  case superseded
}

/// Runs input writes one at a time. A job whose generation is no longer current is
/// dropped before every attempt, so an older desired input is never sent after a newer one.
final class InputCommandExecutor {
  private let queue = DispatchQueue(label: "lg-input-companion.ddc")
  private let lock = NSLock()
  private var currentGeneration = 0
  let maxAttempts: Int
  let retryDelay: TimeInterval
  private let write: (DDCInputSource) -> WriteAttempt
  private let sleep: (TimeInterval) -> Void

  init(maxAttempts: Int = 3, retryDelay: TimeInterval = 1.5,
       write: @escaping (DDCInputSource) -> WriteAttempt,
       sleep: @escaping (TimeInterval) -> Void = { usleep(UInt32($0 * 1_000_000)) }) {
    self.maxAttempts = max(1, maxAttempts)
    self.retryDelay = retryDelay
    self.write = write
    self.sleep = sleep
  }

  func setCurrentGeneration(_ generation: Int) {
    self.lock.lock()
    self.currentGeneration = generation
    self.lock.unlock()
  }

  func isCurrent(_ generation: Int) -> Bool {
    self.lock.lock()
    defer { self.lock.unlock() }
    return self.currentGeneration == generation
  }

  func submit(_ source: DDCInputSource, generation: Int, completion: @escaping (CommandResult) -> Void) {
    self.queue.async {
      completion(self.run(source, generation: generation))
    }
  }

  /// Synchronous body, exposed for tests.
  func run(_ source: DDCInputSource, generation: Int) -> CommandResult {
    for attempt in 1 ... self.maxAttempts {
      guard self.isCurrent(generation) else { return .superseded }
      switch self.write(source) {
      case .sent: return .sent(attempts: attempt)
      case .displayUnavailable: return .displayUnavailable // Not queued for later: it would be stale.
      case .failed:
        if attempt < self.maxAttempts { self.sleep(self.retryDelay) }
      }
    }
    return .failed(attempts: self.maxAttempts)
  }
}
