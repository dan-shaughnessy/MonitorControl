import Foundation

@main struct DeskAudioTests {
    static func main() {
        var stops: [(Bool) -> Void] = []
        var starts: [(DeskHandoff.Source, (Bool) -> Void)] = []
        let handoff = DeskHandoff(stopBoth: { stops.append($0) }, startOne: { starts.append(($0, $1)) })
        handoff.request(.personal)
        assert(starts.isEmpty)
        handoff.request(.resml)
        stops[0](true)
        assert(starts.isEmpty, "superseded stop must not start old source")
        stops[1](true)
        assert(starts.count == 1 && starts[0].0 == .resml)
        handoff.cancel()
        starts[0].1(true)
        assert(handoff.state == .idle, "stale start must not claim ownership")
        handoff.setPaused(true)
        handoff.request(.personal)
        assert(starts.count == 1)
        var stereo: [Float] = [1, 2, 3, 4]
        stereo.withUnsafeMutableBufferPointer { DeskRouting.apply($0.baseAddress!, frames: 2, mode: 1) }
        assert(stereo == [1, 1, 3, 3])
        stereo = [1, 2, 3, 4]
        stereo.withUnsafeMutableBufferPointer { DeskRouting.apply($0.baseAddress!, frames: 2, mode: 2) }
        assert(stereo == [2, 2, 4, 4])
        stereo = [1, 2, 3, 4]
        stereo.withUnsafeMutableBufferPointer { DeskRouting.apply($0.baseAddress!, frames: 2, mode: 0) }
        assert(stereo == [1, 2, 3, 4])
        print("PASS handoff ordering, stale completions, pause, stereo/left/right routing")
        let server = DeskPeer(port: 49188)
        let client = DeskPeer(port: 49188)
        let key = Data(repeating: 42, count: 32)
        var received = false
        server.onMessage = { message in received = message.kind == "probe" && message.generation == 17 }
        client.onConnected = { client.send(.init(kind: "probe", generation: 17)) }
        do {
            try server.open(key: key, coordinator: true, host: "")
            try client.open(key: key, coordinator: false, host: "127.0.0.1")
        } catch { fatalError("TLS socket setup failed: \(error)") }
        let limit = Date().addingTimeInterval(8)
        while !received && Date() < limit { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        assert(received, "TLS-PSK peers with identical keys must exchange bounded protocol messages")
        server.close(); client.close()
        print("PASS real loopback TLS-PSK exchange")
        let wrongServer = DeskPeer(port: 49189)
        let wrongClient = DeskPeer(port: 49189)
        var authenticated = false
        wrongClient.onConnected = { authenticated = true }
        try! wrongServer.open(key: key, coordinator: true, host: "")
        try! wrongClient.open(key: Data(repeating: 43, count: 32), coordinator: false, host: "127.0.0.1")
        let rejectLimit = Date().addingTimeInterval(2)
        while Date() < rejectLimit { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        assert(!authenticated, "different pairing key must never authenticate")
        wrongServer.close(); wrongClient.close()
        print("PASS wrong pairing key rejected")
    }
}
