import Foundation
@_implementationOnly import Network
import Security

/// TLS-PSK channel: no listener exists before a 256-bit pairing key is installed.
/// Frames are bounded, ordered and confined to this authenticated connection.
final class DeskPeer {
    struct Message: Codable {
        var kind: String
        var generation: UInt64
        var source: DeskHandoff.Source?
        var success: Bool?
        var mode: Int?
    }
    var onMessage: ((Message) -> Void)?
    var onConnected: (() -> Void)?
    var onLost: (() -> Void)?
    private var listener: NWListener?
    private var connection: NWConnection?
    private var buffer = Data()
    private var ready = false
    private var epoch = UUID()
    private let port: NWEndpoint.Port
    init(port: UInt16 = 49187) { self.port = NWEndpoint.Port(rawValue: port)! }

    private static func parameters(_ key: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let identity = Data("MonitorControlDesk-v1".utf8)
        key.withUnsafeBytes { k in identity.withUnsafeBytes { i in
            sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,
                DispatchData(bytes: k) as __DispatchData, DispatchData(bytes: i) as __DispatchData)
        } }
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        // TLS_PSK_WITH_AES_128_GCM_SHA256: this channel authenticates only with
        // the paired 256-bit key, never an unauthenticated certificate fallback.
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, tls_ciphersuite_t(rawValue: 0x00A8)!)
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }
    func open(key: Data, coordinator: Bool, host: String) throws {
        close()
        guard key.count == 32 else { throw NSError(domain: "DeskPairing", code: 1) }
        let params = Self.parameters(key)
        if coordinator {
            let listener = try NWListener(using: params, on: port)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] incoming in
                guard let self, self.connection == nil else { incoming.cancel(); return }
                self.accept(incoming)
            }
            listener.start(queue: .main)
        } else {
            accept(NWConnection(host: NWEndpoint.Host(host), port: port, using: params))
        }
    }
    private func accept(_ connection: NWConnection) {
        self.connection = connection
        buffer.removeAll(keepingCapacity: false)
        let token = UUID(); epoch = token
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.epoch == token else { return }
            switch state {
            case .ready:
                self.ready = true; self.onConnected?(); self.receive(connection, token)
            case .failed, .cancelled:
                self.connection = nil; self.ready = false; self.onLost?()
            default: break
            }
        }
        connection.start(queue: .main)
    }
    func send(_ message: Message) {
        guard ready, let connection, var data = try? JSONEncoder().encode(message), data.count <= 2048 else { return }
        data.append(10)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { DispatchQueue.main.async { self?.close(); self?.onLost?() } }
        })
    }
    private func receive(_ connection: NWConnection, _ token: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
            guard let self, self.epoch == token else { return }
            if let data { self.buffer.append(data) }
            while let end = self.buffer.firstIndex(of: 10) {
                guard end <= 2048, let message = try? JSONDecoder().decode(Message.self, from: self.buffer[..<end]) else { self.close(); self.onLost?(); return }
                self.buffer.removeSubrange(...end)
                self.onMessage?(message)
            }
            guard self.buffer.count <= 2048, !done, error == nil else { self.close(); self.onLost?(); return }
            self.receive(connection, token)
        }
    }
    func close() {
        epoch = UUID(); ready = false
        connection?.cancel(); connection = nil
        listener?.cancel(); listener = nil
        buffer.removeAll()
    }
}
