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

        return results.enumerated().map { (index, observation) in
            let bbox = observation.boundingBox  // normalized CGRect (0-1)
            return PoseData(
                timestamp: timestamp,
                joints: [
                    "bbox_minX": JointPoint(x: bbox.minX, y: bbox.minY, z: nil, confidence: Double(observation.confidence)),
                    "bbox_maxX": JointPoint(x: bbox.maxX, y: bbox.maxY, z: nil, confidence: Double(observation.confidence)),
                ]
            )
        }
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
            // location (inherited from VNRecognizedPoint) is the 2D image-space coordinate (0-1)
            // position is the 3D camera-space transform (meters)
            let loc = entry.value.location
            let pos = entry.value.position
            dict["\(entry.key)"] = JointPoint(
                x: Double(loc.x),
                y: Double(loc.y),
                z: Double(pos.columns.3.z),  // depth in meters
                confidence: Double(entry.value.confidence)
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
