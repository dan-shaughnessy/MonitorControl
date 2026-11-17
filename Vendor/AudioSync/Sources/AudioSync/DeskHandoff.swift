import Foundation

/// One coordinator (RESML), one transaction in flight. The transport must be
/// authenticated. A stale stop/start completion cannot advance a newer request.
public final class DeskHandoff {
    public enum Source: String, Codable { case resml, personal }
    public enum State: Equatable {
        case idle, stopping(UInt64), starting(UInt64, Source), playing(Source), failed(String)
    }
    public private(set) var state: State = .idle { didSet { onChange?(state) } }
    public var onChange: ((State) -> Void)?
    public typealias Stop = (@escaping (Bool) -> Void) -> Void
    public typealias Start = (Source, @escaping (Bool) -> Void) -> Void
    private let stopBoth: Stop
    private let startOne: Start
    private var generation: UInt64 = 0
    private var allowed = true
    public init(stopBoth: @escaping Stop, startOne: @escaping Start) {
        self.stopBoth = stopBoth; self.startOne = startOne
    }
    public func request(_ source: Source) {
        guard allowed else { return }
        generation &+= 1
        let token = generation
        state = .stopping(token)
        stopBoth { [weak self] stopped in
            guard let self, self.generation == token, self.allowed else { return }
            guard stopped else { self.state = .failed("Previous sender did not acknowledge stop"); return }
            self.state = .starting(token, source)
            self.startOne(source) { [weak self] started in
                guard let self, self.generation == token, self.allowed else { return }
                if started { self.state = .playing(source) }
                else {
                    self.generation &+= 1
                    self.stopBoth { _ in }
                    self.state = .failed("Audio source could not start — check Audio Outputs and retry")
                }
            }
        }
    }
    /// Pause, sleep, peer loss or settings changes invalidate every completion.
    public func cancelPending() {
        switch state {
        case .stopping, .starting: cancel()
        default: break
        }
    }
    public func cancel() {
        generation &+= 1
        state = .idle
        stopBoth { _ in }
    }
    public func setPaused(_ paused: Bool) {
        allowed = !paused
        cancel()
    }
}
