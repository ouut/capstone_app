import Foundation
import Network

final class WebSocketSender {
    private var connection: NWConnection?
    private var host: String = ""
    private var port: UInt16 = 0
    private var shouldStayConnected = false
    private var isConnected = false
    private var handshakeDone = false
    private var reconnectTimer: Timer?
    private var reconnectDelay: TimeInterval = 1.0
    private let maxReconnectDelay: TimeInterval = 60.0
    private var lastSkelSkipped = false
    private var receiveBuffer = Data()
    var videoEnabled = false

    var onStatusChange: ((String) -> Void)?

    deinit {
        disconnect()
    }

    // MARK: - API

    func configure(urlString: String) {
        guard let url = URL(string: urlString),
              let h = url.host, let p = url.port else {
            host = ""
            port = 0
            return
        }
        guard h != host || p != port else { return }
        disconnect()
        host = h
        port = UInt16(p)
    }

    func connect() {
        guard !host.isEmpty, port > 0 else {
            onStatusChange?("WS: URL is empty")
            return
        }
        guard !shouldStayConnected else { return }

        reconnectTimer?.invalidate()
        reconnectTimer = nil
        handshakeDone = false
        isConnected = false
        receiveBuffer.removeAll()

        onStatusChange?("WS: Connecting to \(host):\(port)...")

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 5
        let params = NWParameters(tls: nil, tcp: tcp)
        params.requiredLocalEndpoint = nil

        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.startHandshake()
                case .failed(let error):
                    self.isConnected = false
                    self.handshakeDone = false
                    self.onStatusChange?("WS: Failed — \(error.localizedDescription)")
                    self.handleDisconnect()
                case .cancelled:
                    self.isConnected = false
                    self.handshakeDone = false
                case .waiting(let error):
                    self.onStatusChange?("WS: Waiting — \(error.localizedDescription)")
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
        handshakeDone = false
        stopTimers()
        connection?.cancel()
        connection = nil
    }

    func sendSkeletal(payload: Data) {
        guard connection != nil, isConnected, handshakeDone else {
            if !lastSkelSkipped {
                lastSkelSkipped = true
                onStatusChange?("WS: No connection — skel skipped")
            }
            return
        }
        lastSkelSkipped = false
        var framed = Data([0x01])
        framed.append(payload)
        sendFrame(framed)
    }

    func sendVideoFrame(jpegData: Data) {
        guard videoEnabled, connection != nil, isConnected, handshakeDone else { return }
        var framed = Data([0x02])
        framed.append(jpegData)
        sendFrame(framed)
    }

    // MARK: - Handshake

    private func startHandshake() {
        guard let conn = connection else { return }
        let key = randomBase64Key()
        let request = [
            "GET / HTTP/1.1",
            "Host: \(host):\(port)",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(key)",
            "Sec-WebSocket-Version: 13",
            "", ""
        ].joined(separator: "\r\n")
        conn.send(content: request.data(using: .utf8)!, completion: .idempotent)
        receiveHandshakeResponse()
    }

    private func receiveHandshakeResponse() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.onStatusChange?("WS: Handshake failed — \(error.localizedDescription)")
                    self.handleDisconnect()
                }
                return
            }
            guard let data else { return }
            self.receiveBuffer.append(data)
            let crlfcrlf = Data("\r\n\r\n".utf8)
            if self.receiveBuffer.range(of: crlfcrlf) != nil {
                let response = String(data: self.receiveBuffer, encoding: .utf8) ?? ""
                self.receiveBuffer.removeAll()
                if response.contains("101") {
                    DispatchQueue.main.async {
                        self.isConnected = true
                        self.handshakeDone = true
                        self.reconnectDelay = 1.0
                        self.onStatusChange?("WS: Connected")
                    }
                } else {
                    let firstLine = response.components(separatedBy: "\r\n").first ?? "unknown"
                    DispatchQueue.main.async {
                        self.onStatusChange?("WS: Server rejected — \(firstLine)")
                        self.handleDisconnect()
                    }
                }
            } else {
                self.receiveHandshakeResponse()
            }
        }
    }

    // MARK: - WebSocket framing

    private func sendFrame(_ data: Data) {
        guard let conn = connection else { return }
        var frame = Data()

        // FIN + opcode (binary = 0x02)
        frame.append(0x82)

        // Masked length
        let len = data.count
        if len < 126 {
            frame.append(UInt8(len | 0x80))
        } else if len <= 65535 {
            frame.append(UInt8(126 | 0x80))
            var ext = UInt16(len).bigEndian
            frame.append(Data(bytes: &ext, count: 2))
        } else {
            frame.append(UInt8(127 | 0x80))
            var ext = UInt64(len).bigEndian
            frame.append(Data(bytes: &ext, count: 8))
        }

        // Mask key (random 4 bytes)
        var mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        frame.append(&mask, count: 4)

        // Masked payload
        for i in 0..<len {
            frame.append(data[i] ^ mask[i % 4])
        }

        conn.send(content: frame, completion: .idempotent)
    }

    private func randomBase64Key() -> String {
        var bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes: &bytes, count: 16).base64EncodedString()
    }

    // MARK: - Reconnect

    private func handleDisconnect() {
        stopTimers()
        connection?.cancel()
        connection = nil
        isConnected = false
        handshakeDone = false

        guard shouldStayConnected else { return }
        shouldStayConnected = false
        onStatusChange?("WS: Retry in \(Int(reconnectDelay))s...")
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
