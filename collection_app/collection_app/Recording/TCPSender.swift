import Foundation
import Network

final class TCPSender {
    private var connection: NWConnection?
    private var host: String = ""
    private var port: UInt16 = 0
    private var shouldStayConnected = false
    private var isConnected = false
    private var reconnectTimer: Timer?
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 60.0

    var onStatusChange: ((String) -> Void)?

    deinit { disconnect() }

    func configure(host: String, port: UInt16) {
        guard host != self.host || port != self.port else { return }
        disconnect()
        self.host = host
        self.port = port
    }

    func connect() {
        guard !host.isEmpty, port > 0 else {
            onStatusChange?("TCP: missing host or port")
            return
        }
        guard !shouldStayConnected else { return }
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        isConnected = false
        onStatusChange?("TCP: Connecting to \(host):\(port)...")

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 5
        let params = NWParameters(tls: nil, tcp: tcp)
        let ep = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let conn = NWConnection(to: ep, using: params)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.isConnected = true
                    self.reconnectDelay = 1.0
                    self.onStatusChange?("TCP: Connected")
                case .failed(let error):
                    self.isConnected = false
                    self.onStatusChange?("TCP: Failed — \(error.localizedDescription)")
                    self.handleDisconnect()
                case .cancelled:
                    self.isConnected = false
                case .waiting(let error):
                    self.onStatusChange?("TCP: Waiting — \(error.localizedDescription)")
                default:
                    break
                }
            }
        }

        conn.start(queue: .global(qos: .userInitiated))
        connection = conn
        shouldStayConnected = true
    }

    func disconnect() {
        shouldStayConnected = false
        isConnected = false
        stopTimers()
        connection?.cancel()
        connection = nil
    }

    func send(payload: Data) {
        guard let conn = connection, isConnected else { return }
        var packet = Data(capacity: 4 + payload.count)
        var len = UInt32(payload.count).bigEndian
        packet.append(Data(bytes: &len, count: 4))
        packet.append(payload)
        conn.send(content: packet, completion: .idempotent)
    }

    // MARK: - Reconnect

    private func handleDisconnect() {
        stopTimers()
        connection?.cancel()
        connection = nil
        isConnected = false
        guard shouldStayConnected else { return }
        shouldStayConnected = false
        onStatusChange?("TCP: Retry in \(Int(reconnectDelay))s...")
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectTimer == nil else { return }
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: reconnectDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.reconnectTimer = nil
            self.connect()
            self.reconnectDelay = min(self.reconnectDelay * 2, self.maxReconnectDelay)
        }
    }

    private func stopTimers() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
}
