import Foundation
import Network

final class UDPVideoSender {
    private var connection: NWConnection?
    private var host: String = ""
    private var port: UInt16 = 0
    private var frameID: UInt32 = 0

    func configure(host: String, port: UInt16) {
        guard host != self.host || port != self.port else { return }
        self.host = host
        self.port = port
        connection?.cancel()
        connection = nil
    }

    func start() {
        guard !host.isEmpty, port > 0 else { return }
        let ep = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        connection = NWConnection(to: ep, using: .udp)
        connection?.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        connection?.cancel()
        connection = nil
    }

    func send(jpeg: Data) {
        guard let conn = connection, !jpeg.isEmpty else { return }
        let fid = frameID
        frameID += 1

        let maxChunk = 1380
        let total = (jpeg.count + maxChunk - 1) / maxChunk
        var offset = 0

        for chunkIdx in 0..<total {
            let end = min(offset + maxChunk, jpeg.count)
            let payload = jpeg[offset..<end]
            var packet = Data(capacity: 10 + payload.count)

            var f = fid
            var c = UInt16(chunkIdx)
            var t = UInt16(total)
            var s = UInt16(payload.count)

            packet.append(Data(bytes: &f, count: 4))
            packet.append(Data(bytes: &c, count: 2))
            packet.append(Data(bytes: &t, count: 2))
            packet.append(Data(bytes: &s, count: 2))
            packet.append(payload)

            conn.send(content: packet, completion: .idempotent)
            offset = end
        }
    }
}
