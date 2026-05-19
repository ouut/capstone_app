import Foundation
import WebRTC

// MARK: - WebRTC Service with full peer connection + data channel

final class WebRTCService: NSObject, ObservableObject {
    private static let factory: RTCPeerConnectionFactory = {
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
    }()

    // MARK: - WebSocket signaling

    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - WebRTC

    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private let mediaConstraints = RTCMediaConstraints(
        mandatoryConstraints: nil, optionalConstraints: nil
    )
    private var pendingIceCandidates: [RTCIceCandidate] = []

    // MARK: - State

    private let userId: String
    private let serverIP: String
    private let serverPort: String
    private let dataChannelLabel: String

    private var reconnectTimer: Timer?
    private var isActive = false
    private var peerConnectionInitiated = false

    @Published var connectionState: ConnectionState = .disconnected
    @Published var dataChannelState: DataChannelState = .closed

    var onDataReceived: ((Data) -> Void)?

    // MARK: - Init

    /// - Parameters:
    ///   - userId: Client identifier sent to the signaling server
    ///   - serverIP: Signaling server IP
    ///   - serverPort: Signaling server port
    ///   - dataChannelLabel: Label for the WebRTC data channel
    init(userId: String, serverIP: String, serverPort: String, dataChannelLabel: String = "motion") {
        self.userId = userId
        self.serverIP = serverIP
        self.serverPort = serverPort
        self.dataChannelLabel = dataChannelLabel

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.urlSession = URLSession(configuration: config)

        super.init()
    }

    deinit {
        disconnect()
        // RTCShutdownInternalTLS() called once at process exit
    }

    // MARK: - Connection lifecycle

    func setActive(_ active: Bool) {
        isActive = active
        if active {
            connect()
        } else {
            disconnect()
        }
    }

    private func connect() {
        guard isActive else { return }

        let urlString = "ws://\(serverIP):\(serverPort)/signaling"
        guard let url = URL(string: urlString) else {
            updateConnectionState(.error("Invalid signaling URL"))
            return
        }

        updateConnectionState(.connecting)
        peerConnectionInitiated = false

        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()

        let registerMsg = SignalingMessage(
            type: "register", clientId: userId, sdp: nil, candidate: nil, sdpMid: nil, sdpMLineIndex: nil
        )
        sendSignalingMessage(registerMsg)

        receiveSignalingMessages()
    }

    func disconnect() {
        isActive = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil

        dataChannel?.close()
        dataChannel = nil
        peerConnection?.close()
        peerConnection = nil
        pendingIceCandidates.removeAll()
        peerConnectionInitiated = false

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        updateConnectionState(.disconnected)
        updateDataChannelState(.closed)
    }

    // MARK: - Send data

    func sendData(_ data: Data) {
        if let channel = dataChannel, channel.readyState == .open {
            let buffer = RTCDataBuffer(data: data, isBinary: true)
            channel.sendData(buffer)
        } else {
            // WebSocket fallback while data channel isn't open
            let msg = SignalingMessage(
                type: "data", clientId: userId, sdp: nil, candidate: data.base64EncodedString(),
                sdpMid: nil, sdpMLineIndex: nil
            )
            sendSignalingMessage(msg)
        }
    }

    // MARK: - WebRTC setup

    private func createPeerConnection() {
        guard peerConnection == nil else { return }

        let iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"]),
        ]

        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        config.iceCandidatePoolSize = 2

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueFalse,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse,
            ],
            optionalConstraints: nil
        )

        peerConnection = Self.factory.peerConnection(
            with: config, constraints: constraints, delegate: self
        )
    }

    private func createDataChannel() {
        guard let pc = peerConnection, dataChannel == nil else { return }

        let channelConfig = RTCDataChannelConfiguration()
        channelConfig.isOrdered = false        // Unordered for low latency
        channelConfig.maxRetransmits = 0       // No retransmits, fire-and-forget
        // Alternatively: maxPacketLifeTime = 100ms for time-limited retransmits

        dataChannel = pc.dataChannel(forLabel: dataChannelLabel, configuration: channelConfig)
        dataChannel?.delegate = self
    }

    private func initiatePeerConnection() {
        guard !peerConnectionInitiated else { return }
        peerConnectionInitiated = true

        createPeerConnection()
        createDataChannel()

        peerConnection?.offer(for: mediaConstraints) { [weak self] sdp, error in
            guard let self, let sdp else {
                if let error {
                    DispatchQueue.main.async {
                        self?.updateConnectionState(.error("Offer failed: \(error.localizedDescription)"))
                    }
                }
                return
            }

            self.peerConnection?.setLocalDescription(sdp) { err in
                if let err {
                    DispatchQueue.main.async {
                        self.updateConnectionState(.error("Set local desc failed: \(err.localizedDescription)"))
                    }
                    return
                }

                let offerMsg = SignalingMessage(
                    type: "offer", clientId: self.userId,
                    sdp: sdp.sdp, candidate: nil, sdpMid: nil, sdpMLineIndex: nil
                )
                self.sendSignalingMessage(offerMsg)
            }
        }
    }

    // MARK: - Signaling message handling

    private func receiveSignalingMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handleSignalingData(data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self.handleSignalingData(data)
                    }
                @unknown default:
                    break
                }
                self.receiveSignalingMessages()

            case .failure(let error):
                DispatchQueue.main.async {
                    self.updateConnectionState(.error("WS: \(error.localizedDescription)"))
                }
                self.scheduleReconnect()
            }
        }
    }

    private func handleSignalingData(_ data: Data) {
        guard let msg = try? decoder.decode(SignalingMessage.self, from: data) else { return }

        switch msg.type {
        case "registered":
            DispatchQueue.main.async { self.updateConnectionState(.connected) }
            // Start WebRTC negotiation once registered
            self.initiatePeerConnection()

        case "offer":
            self.handleRemoteOffer(msg)

        case "answer":
            self.handleRemoteAnswer(msg)

        case "ice":
            self.handleRemoteICE(msg)

        case "data":
            if let b64 = msg.candidate, let payload = Data(base64Encoded: b64) {
                DispatchQueue.main.async { self.onDataReceived?(payload) }
            }

        default:
            break
        }
    }

    private func handleRemoteOffer(_ msg: SignalingMessage) {
        guard let sdpFromMsg = msg.sdp, let pc = peerConnection else {
            // We received an offer but haven't created a peer connection yet — or sdp is missing
            guard let sdp = msg.sdp else { return }
            createPeerConnection()
            dataChannel = nil // Don't create data channel; the offerer owns it
            guard let newPC = peerConnection else { return }
            applyRemoteOffer(sdp, to: newPC)
            return
        }
        applyRemoteOffer(sdpFromMsg, to: pc)
    }

    private func applyRemoteOffer(_ sdpString: String, to pc: RTCPeerConnection) {
        let remoteDesc = RTCSessionDescription(type: .offer, sdp: sdpString)
        pc.setRemoteDescription(remoteDesc) { [weak self] error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    self.updateConnectionState(.error("Set remote offer: \(error.localizedDescription)"))
                }
                return
            }

            // Drain queued ICE candidates now that remote description is set
            self.drainPendingIceCandidates()

            // Create answer
            pc.answer(for: self.mediaConstraints) { sdp, error in
                guard let sdp else {
                    if let error {
                        DispatchQueue.main.async {
                            self.updateConnectionState(.error("Answer failed: \(error.localizedDescription)"))
                        }
                    }
                    return
                }
                pc.setLocalDescription(sdp) { err in
                    if let err {
                        DispatchQueue.main.async {
                            self.updateConnectionState(.error("Set local answer: \(err.localizedDescription)"))
                        }
                        return
                    }
                    let answerMsg = SignalingMessage(
                        type: "answer", clientId: self.userId,
                        sdp: sdp.sdp, candidate: nil, sdpMid: nil, sdpMLineIndex: nil
                    )
                    self.sendSignalingMessage(answerMsg)
                }
            }
        }
    }

    private func handleRemoteAnswer(_ msg: SignalingMessage) {
        guard let sdpString = msg.sdp, let pc = peerConnection else { return }
        let remoteDesc = RTCSessionDescription(type: .answer, sdp: sdpString)
        pc.setRemoteDescription(remoteDesc) { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    self?.updateConnectionState(.error("Set remote answer: \(error.localizedDescription)"))
                }
                return
            }
            self?.drainPendingIceCandidates()
        }
    }

    private func handleRemoteICE(_ msg: SignalingMessage) {
        guard let candidateString = msg.candidate,
              let sdpMid = msg.sdpMid,
              let sdpMLineIndex = msg.sdpMLineIndex
        else { return }

        let candidate = RTCIceCandidate(sdp: candidateString, sdpMLineIndex: Int32(sdpMLineIndex), sdpMid: sdpMid)

        if peerConnection?.remoteDescription != nil {
            peerConnection?.add(candidate, completionHandler: { _ in })
        } else {
            pendingIceCandidates.append(candidate)
        }
    }

    private func drainPendingIceCandidates() {
        guard !pendingIceCandidates.isEmpty else { return }
        for candidate in pendingIceCandidates {
            peerConnection?.add(candidate, completionHandler: { _ in })
        }
        pendingIceCandidates.removeAll()
    }

    // MARK: - Signaling send

    private func sendSignalingMessage(_ message: SignalingMessage) {
        guard let data = try? encoder.encode(message),
              let json = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(json)) { _ in }
    }

    private func sendICECandidate(_ candidate: RTCIceCandidate) {
        let msg = SignalingMessage(
            type: "ice",
            clientId: userId,
            sdp: nil,
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: Int(candidate.sdpMLineIndex)
        )
        sendSignalingMessage(msg)
    }

    // MARK: - State updates

    private func updateConnectionState(_ state: ConnectionState) {
        DispatchQueue.main.async { self.connectionState = state }
    }

    private func updateDataChannelState(_ state: DataChannelState) {
        DispatchQueue.main.async { self.dataChannelState = state }
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        guard isActive else { return }
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            guard let self, self.isActive else { return }
            // Tear down old peer connection before reconnecting
            self.dataChannel?.close()
            self.dataChannel = nil
            self.peerConnection?.close()
            self.peerConnection = nil
            self.pendingIceCandidates.removeAll()
            self.peerConnectionInitiated = false
            self.connect()
        }
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCService: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async {
            switch newState {
            case .connected, .completed:
                self.updateConnectionState(.connected)
            case .disconnected:
                self.updateConnectionState(.disconnected)
                self.scheduleReconnect()
            case .failed:
                self.updateConnectionState(.error("ICE connection failed"))
                self.scheduleReconnect()
            case .checking:
                break
            case .new, .closed, .count:
                break
            @unknown default:
                break
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        sendICECandidate(candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        // Remote side created a data channel — use it
        self.dataChannel = dataChannel
        dataChannel.delegate = self
    }
}

// MARK: - RTCDataChannelDelegate

extension WebRTCService: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        DispatchQueue.main.async {
            switch dataChannel.readyState {
            case .connecting:
                self.dataChannelState = .opening
            case .open:
                self.dataChannelState = .open
            case .closing, .closed:
                self.dataChannelState = .closed
            @unknown default:
                break
            }
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        DispatchQueue.main.async {
            self.onDataReceived?(buffer.data)
        }
    }
}

// MARK: - Types

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return msg
        }
    }
}

enum DataChannelState {
    case closed
    case opening
    case open
    case error
}

struct SignalingMessage: Codable {
    let type: String
    let clientId: String?
    let sdp: String?
    let candidate: String?
    let sdpMid: String?
    let sdpMLineIndex: Int?

    init(type: String, clientId: String?, sdp: String?, candidate: String?, sdpMid: String?, sdpMLineIndex: Int?) {
        self.type = type
        self.clientId = clientId
        self.sdp = sdp
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }
}
