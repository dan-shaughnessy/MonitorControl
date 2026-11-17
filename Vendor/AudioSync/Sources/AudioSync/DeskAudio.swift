import AppKit
import CoreAudio

/// MonitorControl's in-process bridge. All calls are main-thread only.
/// The host owns capture permission and session ownership; launch never captures.
public final class DeskAudio {
    static var embedded = true
    static var captureAuthorized = false
    private let delegate = AppDelegate()
    private var generation: UInt64 = 0
    private var startWatch: Timer?
    public var isRunning: Bool { delegate.engine.isRunning }

    public init() {
        delegate.setUpMenuBar()
        delegate.mainWindow = MainWindowController(model: delegate.appModel)
        delegate.reconcileLocal()
        delegate.reconcileNativeAirPlay()
    }

    public func setRoutes(local: Int, remote: Int) {
        DeskRouting.local.store(local, ordering: .relaxed)
        DeskRouting.remote.store(remote, ordering: .relaxed)
    }

    public func showSettings() { delegate.showMainWindow() }

    /// Completes only after capture has halted and faded outputs have retired.
    public func stop(then completion: @escaping () -> Void) {
        generation &+= 1; startWatch?.invalidate(); startWatch = nil
        Self.captureAuthorized = false
        delegate.userStopped = true
        delegate.stopEngine(.noSpeakerOn)
        delegate.engine.stop { [weak self] in
            guard let self else { completion(); return }
            self.delegate.nativeAirPlay?.shutdown()
            self.delegate.nativeAirPlay = nil
            completion()
        }
    }

    public var peerIsPlaying: Bool {
        guard let id = delegate.playableAirPlay.first, let receiver = NativeAirPlayID.receiver(id) else { return false }
        return delegate.nativeAirPlay?.model.isPlaying(receiver) == true
    }
    public func start(then completion: @escaping (Bool) -> Void) {
        guard delegate.playableAirPlay.count == 1, delegate.enabledLocal.count == 1, delegate.castSwitchedOn.isEmpty,
              let local = delegate.enabledLocal.first,
              delegate.localDevices[local]?.transport == kAudioDeviceTransportTypeBuiltIn else { completion(false); return }
        delegate.audioSource = .system
        delegate.reconcileNativeAirPlay()
        Self.captureAuthorized = true
        delegate.userStopped = false
        delegate.startEngine(origin: .user)
        if !delegate.engine.isRunning { Self.captureAuthorized = false }
        guard delegate.engine.isRunning else { completion(false); return }
        generation &+= 1
        let token = generation
        let deadline = Date().addingTimeInterval(16)
        startWatch?.invalidate()
        startWatch = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self, self.generation == token else { timer.invalidate(); return }
            if self.peerIsPlaying { timer.invalidate(); self.startWatch = nil; completion(true) }
            else if Date() >= deadline {
                timer.invalidate(); self.startWatch = nil
                self.stop { completion(false) }
            }
        }
    }
}
