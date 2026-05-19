import Foundation
import Network

class UDPClient {
    private var connection: NWConnection?
    private var host: String = "127.0.0.1"
    private var port: UInt16 = 8888
    private let queue = DispatchQueue(label: "com.bodydetection.udp")
    private(set) var isConnected = false

    var onSend: (() -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    func configure(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    func connect() {
        disconnect()

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        connection = NWConnection(to: endpoint, using: .udp)
        connection?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print("UDP: connected to \(self.host):\(self.port)")
                self.isConnected = true
                DispatchQueue.main.async { self.onConnectionChange?(true) }
            case .failed(let error):
                print("UDP: connection failed: \(error)")
                self.isConnected = false
                DispatchQueue.main.async { self.onConnectionChange?(false) }
            case .cancelled:
                print("UDP: cancelled")
                self.isConnected = false
                DispatchQueue.main.async { self.onConnectionChange?(false) }
            default:
                break
            }
        }
        connection?.start(queue: queue)
    }

    func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                print("UDP: send error: \(error)")
            } else {
                DispatchQueue.main.async { self?.onSend?() }
            }
        }))
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }
}
