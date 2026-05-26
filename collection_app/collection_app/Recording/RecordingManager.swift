import ARKit
import AVFoundation
import Combine

struct JointFrame {
    let timestamp: TimeInterval
    let frameIndex: Int
    let joints: [(name: String, transform: simd_float4x4)]
    let cameraTransform: simd_float4x4
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
    private var startTime: TimeInterval = 0
    private var index = 0

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

    var onStatusChange: ((String) -> Void)?

    // MARK: - Recording control

    func startRecording(saveCSV: Bool, saveVideo: Bool) {
        frames.removeAll()
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

        if saveCSV { exportCSV() }
        frames.removeAll()
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
        if csvEnabled {
            frames.append(JointFrame(timestamp: t, frameIndex: index, joints: joints, cameraTransform: cameraTransform))
        }

        // Video
        if videoEnabled, let pb = cameraPixelBuffer {
            writeVideoFrame(pb, at: relativeTime)
        }

        // UDP
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "udp_enabled") {
            let host = defaults.string(forKey: "udp_host") ?? ""
            let portStr = defaults.string(forKey: "udp_port") ?? ""
            let port = UInt16(portStr) ?? 0
            let subjectID = defaults.string(forKey: "subject_id") ?? ""
            let sessionNote = defaults.string(forKey: "session_note") ?? ""
            udpSender.configure(host: host, port: port)
            udpSender.send(timestamp: t, frameIndex: UInt32(index),
                           subjectID: subjectID, sessionNote: sessionNote,
                           joints: joints, cameraTransform: cameraTransform)
        }

        index += 1
    }

    // MARK: - Video writing

    private func writeVideoFrame(_ pixelBuffer: CVPixelBuffer, at time: TimeInterval) {
        videoQueue.async { [weak self] in
            guard let self else { return }

            // Lazy init writer on first frame
            if self.assetWriter == nil {
                self.setupVideoWriter(with: pixelBuffer)
                guard self.writerReady else { return }
            }

            guard let writer = self.assetWriter, writer.status == .writing,
                  let input = self.assetWriterInput, input.isReadyForMoreMediaData,
                  let pool = self.adaptorPool else { return }

            // Copy pixel buffer via pool (ARFrame buffer is transient)
            var copy: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &copy)
            guard let copy else { return }

            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            CVPixelBufferLockBaseAddress(copy, [])
            defer {
                CVPixelBufferUnlockBaseAddress(copy, [])
                CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            }

            // Copy Y plane
            if let srcY = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
               let dstY = CVPixelBufferGetBaseAddressOfPlane(copy, 0) {
                let srcBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
                let dstBytes = CVPixelBufferGetBytesPerRowOfPlane(copy, 0)
                let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
                let bytesPerRow = min(srcBytes, dstBytes)
                for row in 0..<height {
                    let src = srcY.advanced(by: row * srcBytes)
                    let dst = dstY.advanced(by: row * dstBytes)
                    memcpy(dst, src, bytesPerRow)
                }
            }

            // Copy CbCr plane
            if let srcUV = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1),
               let dstUV = CVPixelBufferGetBaseAddressOfPlane(copy, 1) {
                let srcBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
                let dstBytes = CVPixelBufferGetBytesPerRowOfPlane(copy, 1)
                let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
                let bytesPerRow = min(srcBytes, dstBytes)
                for row in 0..<height {
                    let src = srcUV.advanced(by: row * srcBytes)
                    let dst = dstUV.advanced(by: row * dstBytes)
                    memcpy(dst, src, bytesPerRow)
                }
            }

            let pts = CMTime(seconds: time, preferredTimescale: 1_000_000)
            self.pixelBufferAdaptor?.append(copy, withPresentationTime: pts)
        }
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
