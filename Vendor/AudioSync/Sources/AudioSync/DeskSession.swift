import AppKit
import Security

/// Desk lifecycle, with RESML as the sole authority. A connection's loss stops
/// capture; reconnect establishes an idle baseline and never restores ownership.
public final class DeskSession {
    private let audio = DeskAudio()
    private let peer = DeskPeer()
    private var remoteMode = 0
    private var localMode: Int { UserDefaults.standard.integer(forKey: "desk.channelMode") }
    private var connected = false
    private var epoch: UInt64 = 0
    private var acknowledged: ((Bool) -> Void)?
    private var pendingKind: String?
    private var deadline: Timer?
    private var heartbeat: Timer?
    private var lastHeartbeat = Date.distantPast
    private var permitted = false
    private var remoteGeneration: UInt64 = 0
    public private(set) var status = "Audio off — pair both Macs to begin"
    public var onStatus: ((String) -> Void)?
    public var coordinator: Bool { UserDefaults.standard.bool(forKey: "desk.coordinator") }
    private lazy var handoff = DeskHandoff(stopBoth: { [weak self] done in
        guard let self else { done(false); return }
        self.audio.stop {
            guard self.connected else { done(false); return }
            self.command("stop", source: nil, completion: done)
        }
    }, startOne: { [weak self] source, done in
        guard let self, self.connected, self.permitted else { done(false); return }
        if source == .resml { self.audio.start(then: done) }
        else { self.command("start", source: source, completion: done) }
    })
    public init() {
        peer.onConnected = { [weak self] in
            guard let self else { return }
            self.connected = true; self.lastHeartbeat = Date()
            self.peer.send(.init(kind: "routing", generation: 0, mode: self.localMode))
            self.setStatus("Paired — audio off until the next input request")
            self.heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                if Date().timeIntervalSince(self.lastHeartbeat) > 4 { self.disconnect(); return }
                self.peer.send(.init(kind: "heartbeat", generation: 0))
            }
        }
        peer.onLost = { [weak self] in self?.disconnect() }
        peer.onMessage = { [weak self] message in self?.receive(message) }
        handoff.onChange = { [weak self] state in
            switch state {
            case .idle: self?.setStatus("Audio off")
            case .stopping: self?.setStatus("Stopping previous audio source…")
            case let .starting(_, source): self?.setStatus("Starting \(source.rawValue) audio…")
            case let .playing(source): self?.setStatus("Audio source: \(source.rawValue)")
            case let .failed(message): self?.setStatus(message)
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.disconnect() }
    }
    public func showAudioSettings() { audio.showSettings() }
    public func request(_ source: DeskHandoff.Source) {
        guard connected, permitted else { setStatus("Audio off — connect and enable desk audio first"); return }
        if coordinator { handoff.request(source) }
        else { peer.send(.init(kind: "request", generation: 0, source: source)) }
    }
    public func cancelPending() { if coordinator { handoff.cancelPending() } }
    public func pause() {
        permitted = false
        if connected { peer.send(.init(kind: "pause", generation: 0)) }
        handoff.cancel()
        audio.stop {}
        setStatus("Desk audio paused")
    }
    public func disconnect() {
        permitted = false; connected = false; epoch &+= 1
        deadline?.invalidate(); heartbeat?.invalidate()
        acknowledged = nil; peer.close(); handoff.cancel(); audio.stop {}
        setStatus("Audio off — peer disconnected; reconnect in Desk Setup")
    }
    private func setStatus(_ message: String) { status = message; onStatus?(message) }
    private func command(_ kind: String, source: DeskHandoff.Source?, completion: @escaping (Bool) -> Void) {
        epoch &+= 1
        let generation = epoch
        acknowledged = completion; pendingKind = kind
        deadline?.invalidate()
        peer.send(.init(kind: kind, generation: generation, source: source))
        deadline = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self, self.epoch == generation else { return }
            let done = self.acknowledged; self.acknowledged = nil
            self.disconnect(); done?(false)
        }
    }
    private func receive(_ message: DeskPeer.Message) {
        if message.kind == "routing", let mode = message.mode, (0...2).contains(mode) {
            remoteMode = mode; audio.setRoutes(local: localMode, remote: mode); return
        }
        if message.kind == "heartbeat" { lastHeartbeat = Date(); return }
        if message.kind == "pause" { pauseLocally(); return }
        if coordinator {
            if message.kind == "request", let source = message.source, permitted { handoff.request(source) }
            if message.kind == "ack", message.generation == epoch {
                deadline?.invalidate()
                let done = acknowledged; acknowledged = nil
                done?(message.success == true)
            }
            return
        }
        guard (permitted || message.kind == "stop"), message.generation >= remoteGeneration else { return }
        switch message.kind {
        case "stop":
            remoteGeneration = message.generation
            let generation = remoteGeneration
            audio.stop { [weak self] in
                guard let self, self.connected, self.remoteGeneration == generation else { return }
                self.peer.send(.init(kind: "ack", generation: generation, success: true))
                self.setStatus("Audio source: RESML or off")
            }
        case "start":
            guard message.generation > remoteGeneration, message.source == .personal else { return }
            remoteGeneration = message.generation
            let generation = remoteGeneration
            audio.start { [weak self] started in
                guard let self, self.connected, self.remoteGeneration == generation else { return }
                self.peer.send(.init(kind: "ack", generation: generation, success: started))
                self.setStatus(started ? "Audio source: personal" : "Personal audio failed to start — check Audio Outputs")
            }
        default: break
        }
    }
    private func pauseLocally() {
        permitted = false; epoch &+= 1
        acknowledged = nil; deadline?.invalidate(); handoff.cancel(); audio.stop {}
        setStatus("Desk audio paused by peer")
    }
    /// The pairing secret is only shown locally and stored in Keychain.
    /// No network endpoint opens until the user connects in this setup panel.
    public func showSetup() {
        let alert = NSAlert()
        alert.messageText = "Two-Mac Desk Setup"
        alert.informativeText = "Use the same pairing key on both Macs. RESML coordinates handoffs. Save establishes an idle baseline. Configure speakers in Audio Outputs before enabling audio."
        let view = NSStackView()
        view.orientation = .vertical; view.alignment = .leading; view.spacing = 10
        let role = NSButton(checkboxWithTitle: "This Mac is RESML (handoff coordinator)", target: nil, action: nil)
        role.state = coordinator ? .on : .off
        let host = NSTextField(string: UserDefaults.standard.string(forKey: "desk.host") ?? "")
        host.placeholderString = "RESML IP address (personal Mac only)"
        let routing = NSPopUpButton()
        routing.addItems(withTitles: ["Stereo", "Left to Both", "Right to Both"])
        routing.selectItem(at: min(2, max(0, localMode)))
        let key = NSSecureTextField(string: Self.loadKey() ?? "")
        key.placeholderString = "64 hexadecimal characters — pairing key"
        for element in [role, host, key, routing] { view.addArrangedSubview(element) }
        view.frame = NSRect(x: 0, y: 0, width: 460, height: 140)
        alert.accessoryView = view
        alert.addButton(withTitle: "Save and Connect")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Generate Pairing Key")
        let response = alert.runModal()
        if response == .alertThirdButtonReturn {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return }
            let value = bytes.map { String(format: "%02x", $0) }.joined()
            let display = NSAlert(); display.messageText = "Pairing key"
            display.informativeText = "Enter this key in Desk Setup on the other Mac. It grants audio control. It is saved in this Mac’s Keychain."
            let field = NSTextField(string: value); field.isEditable = false; field.isSelectable = true
            field.frame = NSRect(x: 0, y: 0, width: 530, height: 24); display.accessoryView = field
            if Self.saveKey(value) { display.runModal() }
            return
        }
        guard response == .alertFirstButtonReturn else { return }
        let value = key.stringValue.lowercased()
        guard value.count == 64, value.allSatisfy({ $0.isHexDigit }), role.state == .on || !host.stringValue.isEmpty, Self.saveKey(value) else {
            setStatus("Setup failed — use a 64-character pairing key and RESML address"); return
        }
        disconnect()
        UserDefaults.standard.set(routing.indexOfSelectedItem, forKey: "desk.channelMode")
        audio.setRoutes(local: localMode, remote: remoteMode)
        UserDefaults.standard.set(role.state == .on, forKey: "desk.coordinator")
        UserDefaults.standard.set(host.stringValue, forKey: "desk.host")
        let bytes = stride(from: 0, to: 64, by: 2).map { offset -> UInt8 in
            let a = value.index(value.startIndex, offsetBy: offset)
            let b = value.index(a, offsetBy: 2)
            return UInt8(value[a..<b], radix: 16)!
        }
        do {
            try peer.open(key: Data(bytes), coordinator: coordinator, host: host.stringValue)
            permitted = true; remoteGeneration = 0
            setStatus("Connecting — both Macs must use the same pairing key")
        } catch { setStatus("Could not open desk connection") }
    }
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "app.monitorcontrol.desk-pairing", kSecAttrAccount as String: "peer"]
    private static func loadKey() -> String? {
        var q = query; q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private static func saveKey(_ value: String) -> Bool {
        let update = [kSecValueData as String: Data(value.utf8)]
        let result = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(update) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }
}
