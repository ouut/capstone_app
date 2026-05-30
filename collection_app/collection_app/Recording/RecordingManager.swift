import ARKit
import AVFoundation
import Combine

struct JointFrame {
    let timestamp: TimeInterval
    let frameIndex: Int
    let joints: [(name: String, transform: simd_float4x4)]
    let cameraTransform: simd_float4x4
}

struct HandJointRecord {
    let chirality: String    // "left" or "right"
    let jointName: String
    let posX: Float
    let posY: Float
    let posZ: Float         // confidence
}

struct HandFrame {
    let timestamp: TimeInterval
    let frameIndex: Int
    let joints: [HandJointRecord]
}

struct RecordedFile {
    let url: URL
    let name: String
    let size: Int64
    let date: Date
    let isCSV: Bool
}

final class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var frameCount = 0
    @Published var elapsed: TimeInterval = 0

    private var frames: [JointFrame] = []
    private var handFrames: [HandFrame] = []
    private var startTime: TimeInterval = 0
    private var index = 0
    private var lastSendTime: TimeInterval = 0

    // CSV
    private var csvEnabled = true

    // Video
    private var videoEnabled = false
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var adaptorPool: CVPixelBufferPool?
    private var videoOutputURL: URL?
    private var writerReady = false
    private let videoQueue = DispatchQueue(label: "recording.video", qos: .userInitiated)

    let udpSender = UDPSender()
    let udpVideoSender = UDPVideoSender()
    let tcpSender = TCPSender()
    let webSocketSender = WebSocketSender()
    @Published var isUDPVideoActive = false
    @Published var wsLog: [String] = []
    @Published var tcpLog: [String] = []
    @Published var wsDiag = ""
    @Published var tcpDiag = ""

    var onStatusChange: ((String) -> Void)?
    private let maxLogLines = 50

    override init() {
        super.init()
        webSocketSender.onStatusChange = { [weak self] msg in
            DispatchQueue.main.async {
                guard let self else { return }
                self.wsDiag = msg
                self.wsLog.append(msg)
                if self.wsLog.count > self.maxLogLines { self.wsLog.removeFirst() }
            }
        }
        tcpSender.onStatusChange = { [weak self] msg in
            DispatchQueue.main.async {
                guard let self else { return }
                self.tcpDiag = msg
                self.tcpLog.append(msg)
                if self.tcpLog.count > self.maxLogLines { self.tcpLog.removeFirst() }
            }
        }
    }

    // MARK: - Recording control

    func startRecording(saveCSV: Bool, saveVideo: Bool) {
        frames.removeAll()
        handFrames.removeAll()
        index = 0
        frameCount = 0
        elapsed = 0
        isRecording = true
        csvEnabled = saveCSV
        videoEnabled = saveVideo
        writerReady = false
        assetWriter = nil
        assetWriterInput = nil
        pixelBufferAdaptor = nil
        adaptorPool = nil
        videoOutputURL = nil
        let parts = [saveCSV ? "CSV" : nil, saveVideo ? "Video" : nil].compactMap { $0 }
        onStatusChange?("REC (\(parts.joined(separator: " + ")))")

        // WebSocket (skeletal only)
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "ws_enabled") {
            let url = defaults.string(forKey: "ws_url") ?? ""
            webSocketSender.configure(urlString: url)
            webSocketSender.connect()
        }

        // TCP (skeletal)
        if defaults.bool(forKey: "tcp_enabled") {
            let tHost = defaults.string(forKey: "tcp_host") ?? ""
            let tPortStr = defaults.string(forKey: "tcp_port") ?? ""
            let tPort = UInt16(tPortStr) ?? 0
            tcpSender.configure(host: tHost, port: tPort)
            tcpSender.connect()
        }

        // UDP Video
        if defaults.bool(forKey: "udp_video_enabled") {
            let vHost = defaults.string(forKey: "udp_video_host") ?? ""
            let vPortStr = defaults.string(forKey: "udp_video_port") ?? ""
            let vPort = UInt16(vPortStr) ?? 0
            udpVideoSender.configure(host: vHost, port: vPort)
            udpVideoSender.start()
            isUDPVideoActive = true
        }
    }

    func stopRecording(saveCSV: Bool, saveVideo: Bool) {
        isRecording = false
        onStatusChange?("Saving...")

        if saveVideo, let writer = assetWriter, writer.status == .writing {
            assetWriterInput?.markAsFinished()
            let url = videoOutputURL
            writer.finishWriting { [weak self] in
                if let src = url, let dst = self?.finalVideoURL() {
                    try? FileManager.default.moveItem(at: src, to: dst)
                    self?.onStatusChange?("Video saved: \(dst.lastPathComponent)")
                }
            }
        }

        if saveCSV { exportCSV(); exportHandCSV() }
        frames.removeAll()
        handFrames.removeAll()

        webSocketSender.disconnect()
        tcpSender.disconnect()
        udpVideoSender.stop()
        isUDPVideoActive = false

        onStatusChange?("Saved \(frameCount) frames")
    }

    func recordFrame(bodyAnchor: ARBodyAnchor, cameraTransform: simd_float4x4, cameraPixelBuffer: CVPixelBuffer?) {
        guard isRecording else { return }

        let now = CACurrentMediaTime()
        if startTime == 0 || index == 0 { startTime = now }

        let relativeTime = now - startTime
        elapsed = relativeTime
        frameCount = index + 1

        let t = Date().timeIntervalSince1970

        // Joint data
        let skeleton = bodyAnchor.skeleton
        let names = skeleton.definition.jointNames
        let xforms = skeleton.jointModelTransforms
        var joints: [(name: String, transform: simd_float4x4)] = []
        for i in 0..<names.count { joints.append((names[i], xforms[i])) }

        // Video
        if videoEnabled, let pb = cameraPixelBuffer {
            writeVideoFrame(pb, at: relativeTime)
        }

        // Shared metadata
        let defaults = UserDefaults.standard
        let subjectID = defaults.string(forKey: "subject_id") ?? ""
        let sessionNote = defaults.string(forKey: "session_note") ?? ""

        // FPS throttle for skeletal network sends (0 = max / native rate)
        let skeletalFPS = defaults.integer(forKey: "skeletal_fps")
        let shouldSend: Bool
        if skeletalFPS > 0 {
            let interval = 1.0 / Double(skeletalFPS)
            shouldSend = lastSendTime == 0 || (now - lastSendTime) >= interval
        } else {
            shouldSend = true
        }

        if shouldSend {
            lastSendTime = now

            // CSV
            if csvEnabled {
                frames.append(JointFrame(timestamp: t, frameIndex: index, joints: joints, cameraTransform: cameraTransform))
            }

            // UDP
            if defaults.bool(forKey: "udp_enabled") {
                let host = defaults.string(forKey: "udp_host") ?? ""
                let portStr = defaults.string(forKey: "udp_port") ?? ""
                let port = UInt16(portStr) ?? 0
                udpSender.configure(host: host, port: port)
                udpSender.send(timestamp: t, frameIndex: UInt32(index),
                               subjectID: subjectID, sessionNote: sessionNote,
                               joints: joints, cameraTransform: cameraTransform)
            }

            // Build skeletal payload once for all transports
            let payload = buildJointsPayload(timestamp: t, frameIndex: UInt32(index),
                                             subjectID: subjectID, sessionNote: sessionNote,
                                             joints: joints, cameraTransform: cameraTransform)

            // WebSocket
            let wsEnabled = defaults.bool(forKey: "ws_enabled")
            if wsEnabled {
                if defaults.bool(forKey: "udp_enabled") {
                    defaults.set(false, forKey: "udp_enabled")
                    udpSender.stop()
                }

                let url = defaults.string(forKey: "ws_url") ?? ""
                webSocketSender.configure(urlString: url)
                webSocketSender.connect()
                webSocketSender.sendSkeletal(payload: payload)

                if index % 60 == 0 {
                    let msg = "WS: sent skel #\(index)"
                    wsDiag = msg
                    wsLog.append(msg)
                    if wsLog.count > maxLogLines { wsLog.removeFirst() }
                }
            } else {
                webSocketSender.disconnect()
            }

            // TCP
            if defaults.bool(forKey: "tcp_enabled") {
                let tHost = defaults.string(forKey: "tcp_host") ?? ""
                let tPortStr = defaults.string(forKey: "tcp_port") ?? ""
                let tPort = UInt16(tPortStr) ?? 0
                tcpSender.configure(host: tHost, port: tPort)
                tcpSender.connect()
                tcpSender.send(payload: payload)

                if index % 60 == 0 {
                    let msg = "TCP: sent skel #\(index)"
                    tcpDiag = msg
                    tcpLog.append(msg)
                    if tcpLog.count > maxLogLines { tcpLog.removeFirst() }
                }
            }
        }

        index += 1
    }

    // MARK: - Hand CSV

    private static let handJointNames: [String] = [
        "wrist",
        "thumbCMC", "thumbMP", "thumbIP", "thumbTip",
        "indexMCP", "indexPIP", "indexDIP", "indexTip",
        "middleMCP", "middlePIP", "middleDIP", "middleTip",
        "ringMCP", "ringPIP", "ringDIP", "ringTip",
        "littleMCP", "littlePIP", "littleDIP", "littleTip",
    ]

    func recordHandFrame(timestamp: TimeInterval, frameIndex: Int,
                         hands: [(chirality: String, points: [CGPoint?])]) {
        guard isRecording, csvEnabled else { return }

        var records: [HandJointRecord] = []
        for hand in hands {
            for (i, pt) in hand.points.enumerated() {
                guard let p = pt, i < Self.handJointNames.count else { continue }
                records.append(HandJointRecord(
                    chirality: hand.chirality,
                    jointName: Self.handJointNames[i],
                    posX: Float(p.x),
                    posY: Float(p.y),
                    posZ: 1.0
                ))
            }
        }
        guard !records.isEmpty else { return }
        handFrames.append(HandFrame(timestamp: timestamp, frameIndex: frameIndex, joints: records))
    }

    // MARK: - Binary payload builder (shared by WS and UDP)

    private func buildJointsPayload(timestamp: Double, frameIndex: UInt32,
                                     subjectID: String, sessionNote: String,
                                     joints: [(name: String, transform: simd_float4x4)],
                                     cameraTransform: simd_float4x4) -> Data {
        let jointCount = joints.count
        var data = Data(count: 8 + 4 + 32 + 32 + jointCount * 28 + 28)
        var offset = 0

        var ts = timestamp
        Swift.withUnsafeBytes(of: &ts) { data.replaceSubrange(offset..<offset+8, with: $0) }
        offset += 8

        var idx = frameIndex
        Swift.withUnsafeBytes(of: &idx) { data.replaceSubrange(offset..<offset+4, with: $0) }
        offset += 4

        let subjectBytes = subjectID.utf8.prefix(32)
        data.replaceSubrange(offset..<offset+subjectBytes.count, with: subjectBytes)
        offset += 32

        let sessionBytes = sessionNote.utf8.prefix(32)
        data.replaceSubrange(offset..<offset+sessionBytes.count, with: sessionBytes)
        offset += 32

        for j in joints {
            let cols = j.transform.columns
            let q = simd_quatf(j.transform)
            let vals: [Float32] = [
                cols.3.x, cols.3.y, cols.3.z,
                q.vector.x, q.vector.y, q.vector.z, q.vector.w
            ]
            vals.withUnsafeBytes { data.replaceSubrange(offset..<offset+28, with: $0) }
            offset += 28
        }

        let camCols = cameraTransform.columns
        let camQ = simd_quatf(cameraTransform)
        let camVals: [Float32] = [
            camCols.3.x, camCols.3.y, camCols.3.z,
            camQ.vector.x, camQ.vector.y, camQ.vector.z, camQ.vector.w
        ]
        camVals.withUnsafeBytes { data.replaceSubrange(offset..<offset+28, with: $0) }

        return data
    }

    // MARK: - Video writing

    private func writeVideoFrame(_ pixelBuffer: CVPixelBuffer, at time: TimeInterval) {
        // Copy before dispatch: CVPixelBuffer is not Sendable, and ARFrame buffers are transient
        guard let frameCopy = copyPixelBuffer(pixelBuffer) else { return }

        videoQueue.async { [weak self] in
            guard let self else { return }

            if self.assetWriter == nil {
                self.setupVideoWriter(with: frameCopy)
                guard self.writerReady else { return }
            }

            guard self.assetWriter?.status == .writing,
                  self.assetWriterInput?.isReadyForMoreMediaData == true,
                  let adaptor = self.pixelBufferAdaptor else { return }

            let pts = CMTime(seconds: time, preferredTimescale: 1_000_000)
            adaptor.append(frameCopy, withPresentationTime: pts)
        }
    }

    private func copyPixelBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(src)
        let height = CVPixelBufferGetHeight(src)
        let format = CVPixelBufferGetPixelFormatType(src)

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: format,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var copy: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, format, attrs as CFDictionary, &copy)
        guard let copy else { return nil }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
        }

        func copyPlane(_ plane: Int) {
            guard let srcAddr = CVPixelBufferGetBaseAddressOfPlane(src, plane),
                  let dstAddr = CVPixelBufferGetBaseAddressOfPlane(copy, plane) else { return }
            let srcBytes = CVPixelBufferGetBytesPerRowOfPlane(src, plane)
            let dstBytes = CVPixelBufferGetBytesPerRowOfPlane(copy, plane)
            let h = CVPixelBufferGetHeightOfPlane(src, plane)
            let bytesPerRow = min(srcBytes, dstBytes)
            for row in 0..<h {
                memcpy(dstAddr.advanced(by: row * dstBytes),
                       srcAddr.advanced(by: row * srcBytes),
                       bytesPerRow)
            }
        }

        copyPlane(0)
        copyPlane(1)
        return copy
    }

    private func setupVideoWriter(with sample: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(sample)
        let height = CVPixelBufferGetHeight(sample)
        let format = CVPixelBufferGetPixelFormatType(sample)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("BodyMotionRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        videoOutputURL = dir.appendingPathComponent("temp_\(Int(Date().timeIntervalSince1970)).mp4")

        guard let url = videoOutputURL else { return }
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(url: url, fileType: .mp4) else {
            onStatusChange?("Video writer failed")
            return
        }

        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = true

        let sourceAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: format,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourceAttrs
        )

        // Create pool for copying frames
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, sourceAttrs as CFDictionary, &pool)

        if writer.canAdd(input) { writer.add(input) }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        assetWriter = writer
        assetWriterInput = input
        pixelBufferAdaptor = adaptor
        adaptorPool = pool
        writerReady = true
    }

    private func finalVideoURL() -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("BodyMotionRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(baseFileName()).mp4")
    }

    // MARK: - Filename

    private func baseFileName() -> String {
        let defaults = UserDefaults.standard
        let subjectID = defaults.string(forKey: "subject_id") ?? ""
        let sessionNote = defaults.string(forKey: "session_note") ?? ""
        let dateStr = dateFormatter.string(from: Date())
        let parts = [subjectID, sessionNote].filter { !$0.isEmpty }
        let prefix = parts.isEmpty ? "" : "\(parts.joined(separator: "_"))_"
        return "\(prefix)\(dateStr)"
    }

    // MARK: - CSV export

    private func exportCSV() {
        guard !frames.isEmpty else { return }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("BodyMotionRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let csvURL = dir.appendingPathComponent("\(baseFileName()).csv")

        var csv = "timestamp,frame,joint,pos_x,pos_y,pos_z,rot_x,rot_y,rot_z,rot_w\n"
        for frame in frames {
            for joint in frame.joints {
                let t = String(format: "%.4f", frame.timestamp)
                let idx = frame.frameIndex
                let cols = joint.transform.columns
                let px = cols.3.x, py = cols.3.y, pz = cols.3.z
                let rot = simd_quatf(joint.transform)
                let rx = rot.vector.x, ry = rot.vector.y, rz = rot.vector.z, rw = rot.vector.w
                csv += "\(t),\(idx),\(joint.name),\(px),\(py),\(pz),\(rx),\(ry),\(rz),\(rw)\n"
            }
            // Camera row
            let ct = String(format: "%.4f", frame.timestamp)
            let ci = frame.frameIndex
            let camCols = frame.cameraTransform.columns
            let cpx = camCols.3.x, cpy = camCols.3.y, cpz = camCols.3.z
            let camRot = simd_quatf(frame.cameraTransform)
            let crx = camRot.vector.x, cry = camRot.vector.y, crz = camRot.vector.z, crw = camRot.vector.w
            csv += "\(ct),\(ci),camera,\(cpx),\(cpy),\(cpz),\(crx),\(cry),\(crz),\(crw)\n"
        }
        try? csv.write(to: csvURL, atomically: true, encoding: .utf8)
        onStatusChange?("CSV: \(csvURL.lastPathComponent)")
    }

    private func exportHandCSV() {
        guard !handFrames.isEmpty else { return }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("BodyMotionRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let csvURL = dir.appendingPathComponent("\(baseFileName())_hand.csv")

        var csv = "timestamp,frame,joint,pos_x,pos_y,pos_z,rot_x,rot_y,rot_z,rot_w\n"
        for frame in handFrames {
            let t = String(format: "%.4f", frame.timestamp)
            let idx = frame.frameIndex
            for joint in frame.joints {
                let name = "\(joint.chirality)_\(joint.jointName)"
                csv += "\(t),\(idx),\(name),\(joint.posX),\(joint.posY),\(joint.posZ),0,0,0,1\n"
            }
        }
        try? csv.write(to: csvURL, atomically: true, encoding: .utf8)
        onStatusChange?("Hand CSV: \(csvURL.lastPathComponent)")
    }

    // MARK: - File listing

    func listRecordedFiles() -> [RecordedFile] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("BodyMotionRecordings", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return []
        }
        var files: [RecordedFile] = []
        for url in contents {
            let ext = url.pathExtension.lowercased()
            guard ext == "csv" || ext == "mp4" else { continue }
            let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
            let size = (attrs[.size] as? Int64) ?? 0
            let date = (attrs[.modificationDate] as? Date) ?? Date.distantPast
            files.append(RecordedFile(
                url: url,
                name: url.lastPathComponent,
                size: size,
                date: date,
                isCSV: ext == "csv"
            ))
        }
        files.sort { $0.date > $1.date }
        return files
    }

    func deleteRecordedFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

}

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd-HHmmss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()
