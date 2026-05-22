import Foundation
import Network
import simd

final class UDPSender {
    private var connection: NWConnection?
    private var host: String = ""
    private var port: UInt16 = 0

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

    func send(timestamp: Double, frameIndex: UInt32,
              joints: [(name: String, transform: simd_float4x4)],
              cameraTransform: simd_float4x4) {
        guard let conn = connection else { return }
        let data = buildFrame(timestamp: timestamp, frameIndex: frameIndex,
                              joints: joints, cameraTransform: cameraTransform)
        conn.send(content: data, completion: .idempotent)
    }

    // MARK: - Binary frame builder

    private func buildFrame(timestamp: Double, frameIndex: UInt32,
                            joints: [(name: String, transform: simd_float4x4)],
                            cameraTransform: simd_float4x4) -> Data {
        let jointCount = joints.count
        var data = Data(count: 1 + 8 + 4 + jointCount * 28 + 28)
        var offset = 0

        // type = 1
        data[offset] = 1; offset += 1

        // timestamp (Float64, little-endian)
        var ts = timestamp
        Swift.withUnsafeBytes(of: &ts) { data.replaceSubrange(offset..<offset+8, with: $0) }
        offset += 8

        // frameIndex (UInt32, little-endian)
        var idx = frameIndex
        Swift.withUnsafeBytes(of: &idx) { data.replaceSubrange(offset..<offset+4, with: $0) }
        offset += 4

        // joints: pos(3×Float32) + rot(4×Float32) = 28 bytes each
        for j in joints {
            let cols = j.transform.columns
            let q = simd_quatf(j.transform)
            var vals: [Float32] = [
                cols.3.x, cols.3.y, cols.3.z,
                q.vector.x, q.vector.y, q.vector.z, q.vector.w
            ]
            vals.withUnsafeBytes { data.replaceSubrange(offset..<offset+28, with: $0) }
            offset += 28
        }

        // camera: same format
        let camCols = cameraTransform.columns
        let camQ = simd_quatf(cameraTransform)
        var camVals: [Float32] = [
            camCols.3.x, camCols.3.y, camCols.3.z,
            camQ.vector.x, camQ.vector.y, camQ.vector.z, camQ.vector.w
        ]
        camVals.withUnsafeBytes { data.replaceSubrange(offset..<offset+28, with: $0) }

        return data
    }
}
