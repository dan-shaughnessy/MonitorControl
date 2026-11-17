import Synchronization

/// Only samples belonging to this process's paired session are mapped. No
/// device balance/default-channel settings are changed; stop restores stereo.
enum DeskRouting {
    static let local = Atomic<Int>(0)
    static let remote = Atomic<Int>(0)
    @inline(__always)
    static func apply(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int = 2, mode: Int) {
        guard channels >= 2, mode == 1 || mode == 2 else { return }
        let selected = mode - 1
        for frame in 0..<frames {
            let value = samples[frame * channels + selected]
            samples[frame * channels] = value
            samples[frame * channels + 1] = value
        }
    }
}
