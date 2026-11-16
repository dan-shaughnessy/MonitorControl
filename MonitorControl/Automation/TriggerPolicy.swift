//  Copyright © MonitorControl contributors

import Foundation

/// For several devices: connected or disconnected only when all agree, otherwise mixed.
enum KeyboardPresence: String {
  case connected, disconnected, mixed, unknown
}

struct PolicyTiming: Equatable {
  var connectDelay: TimeInterval
  var disconnectDelay: TimeInterval
  /// After wake or Bluetooth power-on, observations are ignored while devices reconnect.
  var resumeGrace: TimeInterval = 20
}

/// Pure edge detector. Times are caller-supplied seconds, so tests can simulate them.
///
/// - The first known observation is a baseline and never acts.
/// - A change acts only after it stays stable for its delay. A bounce back cancels it.
/// - `mixed` (some selected devices connected, some not) holds: it cancels a pending change and
///   keeps the baseline. Only a launch baseline can be mixed, so the next full match acts.
/// - `unknown` (Bluetooth off, unpaired, query failure, identity mismatch) cancels and never acts.
/// - Sleep or Bluetooth power-off suspends and cancels. After resume plus a grace period, the
///   first known state becomes a new baseline without a command. Only a later Bluetooth edge acts.
/// - `generation` changes whenever earlier queued work becomes stale.
final class TriggerPolicy {
  enum Decision: Equatable {
    case none
    case schedule(at: TimeInterval)
    case edge(KeyboardPresence)
  }

  private(set) var settled: KeyboardPresence?
  private(set) var pendingTarget: KeyboardPresence?
  private(set) var pendingDue: TimeInterval?
  private(set) var generation = 0
  private(set) var suspended = false
  private(set) var resumeAt: TimeInterval?
  let timing: PolicyTiming

  /// Pass the previous policy's generation when replacing it, so older jobs stay stale.
  init(timing: PolicyTiming, after previousGeneration: Int = -1) {
    self.timing = timing
    self.generation = previousGeneration + 1
  }

  func baseline(_ observed: KeyboardPresence) {
    self.cancelPending()
    self.settled = observed == .unknown ? nil : observed
  }

  func observe(_ observed: KeyboardPresence, now: TimeInterval) -> Decision {
    if self.suspended { return .none }
    if let resumeAt = self.resumeAt {
      if now < resumeAt { return .none }
      self.resumeAt = nil
      self.baseline(observed)
      return .none
    }
    if observed == .unknown {
      self.cancelPending()
      return .none
    }
    guard let settled = self.settled else {
      self.settled = observed
      return .none
    }
    if observed == .mixed {
      self.cancelPending()
      return .none
    }
    if observed == settled {
      if self.pendingTarget != nil { self.cancelPending() }
      return .none
    }
    if self.pendingTarget == observed, let due = self.pendingDue {
      return .schedule(at: due) // Repeated observations never extend or restart the delay.
    }
    self.cancelPending()
    let due = now + (observed == .connected ? self.timing.connectDelay : self.timing.disconnectDelay)
    self.pendingTarget = observed
    self.pendingDue = due
    return .schedule(at: due)
  }

  /// Call when a scheduled time arrives, with a fresh observation.
  func fire(observed: KeyboardPresence, now: TimeInterval) -> Decision {
    guard !self.suspended, self.resumeAt == nil || now >= self.resumeAt!,
          let target = self.pendingTarget, let due = self.pendingDue else { return .none }
    if now + 0.001 < due { return .schedule(at: due) }
    guard observed == target else { return self.observe(observed, now: now) }
    self.pendingTarget = nil
    self.pendingDue = nil
    self.settled = target
    return .edge(target)
  }

  func suspend() {
    self.suspended = true
    self.cancelPending()
  }

  /// Returns the time to reconcile at.
  func resume(now: TimeInterval) -> TimeInterval {
    self.suspended = false
    self.resumeAt = now + self.timing.resumeGrace
    self.generation += 1
    return self.resumeAt!
  }

  private func cancelPending() {
    self.pendingTarget = nil
    self.pendingDue = nil
    self.generation += 1
  }
}
