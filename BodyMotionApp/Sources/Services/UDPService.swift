import Foundation
import Network

// MARK: - UDP Service for low-latency sensor data streaming

final class UDPService: NSObject, ObservableObject {
    private var connection: NWConnection?
    private let host: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.bodymotion.udp", qos: .userInitiated)

    @Published var connectionState: ConnectionState = .disconnected

    var onDataReceived: ((Data) -> Void)?

    // MARK: - Init

    init(host: String, port: String) {
        self.host = host
        self.port = UInt16(port) ?? 5000
        super.init()
    }

    deinit {
        disconnect()
    }

    // MARK: - Lifecycle

    func setActive(_ active: Bool) {
        if active { connect() } else { disconnect() }
    }

    private func connect() {
        updateState(.connecting)

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )
        connection = NWConnection(to: endpoint, using: .udp)

        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .setup, .preparing:
                    break
                case .ready:
                    self?.updateState(.ready)
                case .failed(let error):
                    self?.updateState(.error("UDP: \(error.localizedDescription)"))
                case .cancelled:
                    self?.updateState(.disconnected)
                case .waiting(let error):
                    self?.updateState(.error("UDP waiting: \(error.localizedDescription)"))
                @unknown default:
                    break
                }
            }
        }

        connection?.start(queue: queue)
        receive()
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        updateState(.disconnected)
    }

    // MARK: - Send

    func send(_ data: Data) {
        connection?.send(content: data, completion: .idempotent)
    }

    // MARK: - Receive

    private func receive() {
        connection?.receiveMessage { [weak self] data, _, _, error in
            if let data, !data.isEmpty {
                DispatchQueue.main.async { self?.onDataReceived?(data) }
            }
            if error == nil {
                self?.receive()
            }
        }
    }

    // MARK: - State

    private func updateState(_ state: ConnectionState) {
        DispatchQueue.main.async { self.connectionState = state }
    }
}

// MARK: - Types

extension UDPService {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case ready
        case error(String)

        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .ready: return "Ready"
            case .error(let msg): return msg
            }
        }
    }
}
