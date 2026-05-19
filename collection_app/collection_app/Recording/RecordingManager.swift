import ARKit
import AVFoundation
import Vision
import Combine

struct JointFrame {
    let timestamp: TimeInterval
    let frameIndex: Int
    let joints: [(name: String, transform: simd_float4x4)]
}

final class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var frameCount = 0
    @Published var elapsed: TimeInterval = 0

    private var frames: [JointFrame] = []
    private var startTime: TimeInterval = 0
    private var index = 0

    // Video
    private var videoEnabled = false
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var adaptorPool: CVPixelBufferPool?
    private var videoOutputURL: URL?
    private var writerReady = false
    private let videoQueue = DispatchQueue(label: "recording.video", qos: .userInitiated)

    var onStatusChange: ((String) -> Void)?

    // MARK: - Recording control

    func startRecording(saveVideo: Bool) {
        frames.removeAll()
        index = 0
        frameCount = 0
        elapsed = 0
        isRecording = true
        videoEnabled = saveVideo
        writerReady = false
        assetWriter = nil
        assetWriterInput = nil
        pixelBufferAdaptor = nil
        adaptorPool = nil
        videoOutputURL = nil
        onStatusChange?(saveVideo ? "REC + Video" : "REC (CSV only)")
    }

    func stopRecording(dataID: String, saveVideo: Bool) {
        isRecording = false
        onStatusChange?("Saving...")

        if saveVideo, let writer = assetWriter, writer.status == .writing {
            assetWriterInput?.markAsFinished()
            let url = videoOutputURL
            writer.finishWriting { [weak self] in
                // Move temp video to final location
                if let src = url, let dst = self?.finalVideoURL(dataID: dataID) {
                    try? FileManager.default.moveItem(at: src, to: dst)
                    self?.onStatusChange?("Video saved: \(dst.lastPathComponent)")
                }
            }
        }

        exportCSV(dataID: dataID)
        frames.removeAll()
        onStatusChange?("Saved \(frameCount) frames")
    }

    func recordFrame(bodyAnchor: ARBodyAnchor, cameraPixelBuffer: CVPixelBuffer?) {
        guard isRecording else { return }

        let now = CACurrentMediaTime()
        if startTime == 0 || index == 0 { startTime = now }

        let t = now - startTime
        elapsed = t
        frameCount = index + 1

        // Joint data
        let skeleton = bodyAnchor.skeleton
        let names = skeleton.definition.jointNames
        let xforms = skeleton.jointModelTransforms
        var joints: [(name: String, transform: simd_float4x4)] = []
        for i in 0..<names.count { joints.append((names[i], xforms[i])) }
        frames.append(JointFrame(timestamp: t, frameIndex: index, joints: joints))

        // Video
        if videoEnabled, let pb = cameraPixelBuffer {
            writeVideoFrame(pb, at: t)
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

    private func finalVideoURL(dataID: String) -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("BodyMotionRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dateStr = dateFormatter.string(from: Date())
        return dir.appendingPathComponent("\(dataID)_\(dateStr).mp4")
    }

    // MARK: - CSV export

    private func exportCSV(dataID: String) {
        guard !frames.isEmpty else { return }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("BodyMotionRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dateStr = dateFormatter.string(from: Date())
        let csvURL = dir.appendingPathComponent("\(dataID)_\(dateStr).csv")

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
        }
        try? csv.write(to: csvURL, atomically: true, encoding: .utf8)
        onStatusChange?("CSV: \(csvURL.lastPathComponent)")
    }

    // MARK: - Video → CSV

    func generateCSV(from videoURL: URL, dataID: String) {
        onStatusChange?("Processing video...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.processVideo(url: videoURL, dataID: dataID)
        }
    }

    private func processVideo(url: URL, dataID: String) {
        let asset = AVURLAsset(url: url)
        guard let reader = try? AVAssetReader(asset: asset),
              let videoTrack = asset.tracks(withMediaType: .video).first else {
            DispatchQueue.main.async { self.onStatusChange?("Failed to read video") }
            return
        }

        let output: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: output)
        reader.add(readerOutput)
        reader.startReading()

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNSequenceRequestHandler()
        var allFrames: [JointFrame] = []
        var idx = 0

        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            do { try handler.perform([request], on: pixelBuffer, orientation: .up) }
            catch { continue }

            guard let obs = request.results?.first,
                  let points = try? obs.recognizedPoints(.all) else { continue }

            var joints: [(name: String, transform: simd_float4x4)] = []
            for (name, pt) in points where pt.confidence > 0.3 {
                let x = Float(pt.location.x)
                let y = Float(pt.location.y)
                var t = matrix_identity_float4x4
                t.columns.3 = SIMD4<Float>(x, y, 0, 1)
                joints.append((name.rawValue.rawValue, t))
            }
            if !joints.isEmpty {
                allFrames.append(JointFrame(timestamp: timestamp, frameIndex: idx, joints: joints))
                idx += 1
            }
        }
        reader.cancelReading()

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("BodyMotionRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dateStr = dateFormatter.string(from: Date())
        let csvURL = dir.appendingPathComponent("\(dataID)_fromVideo_\(dateStr).csv")

        var csv = "timestamp,frame,joint,pos_x,pos_y,pos_z\n"
        for frame in allFrames {
            for joint in frame.joints {
                let t = String(format: "%.4f", frame.timestamp)
                let cols = joint.transform.columns
                csv += "\(t),\(frame.frameIndex),\(joint.name),\(cols.3.x),\(cols.3.y),\(cols.3.z)\n"
            }
        }
        try? csv.write(to: csvURL, atomically: true, encoding: .utf8)
        DispatchQueue.main.async {
            self.onStatusChange?("CSV: \(csvURL.lastPathComponent)")
        }
    }
}

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd-HHmmss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()
