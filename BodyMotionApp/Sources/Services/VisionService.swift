import Vision
import CoreVideo
import QuartzCore
import simd

final class VisionService {
    func process(
        buffer: CMSampleBuffer,
        api: VisionAPIType
    ) throws -> [PoseData] {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else {
            throw VisionError.invalidBuffer
        }

        let timestamp = CACurrentMediaTime()

        switch api {
        case .bodyPose2D:
            return try detect2DPoses(pixelBuffer: pixelBuffer, timestamp: timestamp)
        case .bodyPose3D:
            return try detect3DPose(pixelBuffer: pixelBuffer, timestamp: timestamp)
        case .personMask:
            return try detectPersonMasks(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
    }

    // MARK: - 2D Body Pose (multi-person, up to ~6)

    private func detect2DPoses(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) throws -> [PoseData] {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try handler.perform([request])

        guard let results = request.results else { return [] }

        return try results.compactMap { observation -> PoseData? in
            let points = try observation.recognizedPoints(.all)
            return map2DPoints(points, timestamp: timestamp)
        }
    }

    // MARK: - 3D Body Pose (single person, iOS 17+)

    @available(iOS 17.0, *)
    private func detect3DPose(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) throws -> [PoseData] {
        let request = try VNDetectHumanBodyPose3DRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try handler.perform([request])

        guard let result = request.results?.first else { return [] }
        let points = try result.recognizedPoints(.all)
        guard let pose = map3DPoints(points, timestamp: timestamp) else { return [] }
        return [pose]
    }

    // MARK: - Person Mask (up to 4 people)

    private func detectPersonMasks(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) throws -> [PoseData] {
        let request = try VNGeneratePersonInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try handler.perform([request])

        guard let results = request.results else { return [] }

        return results.enumerated().compactMap { (index, observation) -> PoseData? in
            // Compute bounding box from instance mask pixels
            // instanceMask is a CVPixelBuffer directly in this SDK version
            guard let bbox = computeMaskBBox(observation.instanceMask) else { return nil }
            return PoseData(
                timestamp: timestamp,
                joints: [
                    "bbox_minX": JointPoint(x: bbox.minX, y: bbox.minY, z: nil, confidence: Double(observation.confidence)),
                    "bbox_maxX": JointPoint(x: bbox.maxX, y: bbox.maxY, z: nil, confidence: Double(observation.confidence)),
                ]
            )
        }
    }

    /// Scan the mask pixel buffer and return a normalized bounding box of non-zero pixels
    private func computeMaskBBox(_ maskBuffer: CVPixelBuffer) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        guard let base = CVPixelBufferGetBaseAddress(maskBuffer) else { return nil }

        let ptr = base.assumingMemoryBound(to: Float32.self)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.size

        var minX = width, minY = height, maxX = 0, maxY = 0
        var found = false

        for y in 0..<height {
            for x in 0..<width {
                let val = ptr[y * floatsPerRow + x]
                if val > 0 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                    found = true
                }
            }
        }

        guard found else { return nil }

        // Add small padding and normalize to 0-1
        let pad = 4
        return (
            minX: Double(max(minX - pad, 0)) / Double(width),
            minY: Double(max(minY - pad, 0)) / Double(height),
            maxX: Double(min(maxX + pad, width - 1)) / Double(width),
            maxY: Double(min(maxY + pad, height - 1)) / Double(height)
        )
    }

    // MARK: - Helpers

    private func map2DPoints(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
                             timestamp: TimeInterval) -> PoseData? {
        let joints: [String: JointPoint] = points.reduce(into: [:]) { dict, entry in
            let loc = entry.value.location
            dict["\(entry.key)"] = JointPoint(
                x: Double(loc.x),
                y: Double(loc.y),
                z: nil,
                confidence: Double(entry.value.confidence)
            )
        }
        guard !joints.isEmpty else { return nil }
        return PoseData(timestamp: timestamp, joints: joints)
    }

    @available(iOS 17.0, *)
    private func map3DPoints(_ points: [VNHumanBodyPose3DObservation.JointName: VNRecognizedPoint3D],
                             timestamp: TimeInterval) -> PoseData? {
        let joints: [String: JointPoint] = points.reduce(into: [:]) { dict, entry in
            // position is a simd_float4x4 camera-space transform; column 3 is translation (x,y,z in meters)
            let pos = entry.value.position
            let x_m = Double(pos.columns.3.x)
            let y_m = Double(pos.columns.3.y)
            let z_m = max(Double(pos.columns.3.z), 0.1) // avoid division by zero

            // Pinhole projection to normalized 0-1 screen coords
            // Assumes ~60° horizontal FOV → visible width ≈ 1.15× depth
            let fovScale: Double = 1.15
            let nx = 0.5 + (x_m / z_m) / fovScale
            let ny = 0.5 - (y_m / z_m) / fovScale  // flip Y (camera Y is up, screen Y is down)

            dict["\(entry.key)"] = JointPoint(
                x: nx,
                y: ny,
                z: z_m,
                confidence: 1.0
            )
        }
        guard !joints.isEmpty else { return nil }
        return PoseData(timestamp: timestamp, joints: joints)
    }
}

enum VisionError: LocalizedError {
    case invalidBuffer

    var errorDescription: String? {
        switch self {
        case .invalidBuffer: return "Unable to extract pixel buffer from sample buffer"
        }
    }
}
