import CoreML
import Foundation

final class ModelService: ObservableObject {
    private var model: MLModel?
    private var modelURL: URL?
    private var downloadTask: URLSessionDownloadTask?

    /// Sliding window of recent pose data for action recognition
    private var poseWindow: [PoseData] = []
    private let windowSize: Int
    private let jointCount: Int

    @Published var isLoaded = false
    @Published var errorMessage: String?

    init(windowSize: Int = 60, jointCount: Int = 19) {
        self.windowSize = windowSize
        self.jointCount = jointCount
    }

    // MARK: - Download & Load

    func downloadAndLoad(from urlString: String) async throws {
        guard let url = URL(string: urlString) else {
            throw ModelError.invalidURL
        }

        await MainActor.run { isLoaded = false; errorMessage = nil }

        let (tempURL, _) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Copy to cache
        let cacheDir = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let modelName = url.lastPathComponent
        let destination = cacheDir.appendingPathComponent(modelName)

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)

        // Compile if needed then load
        let compiledURL: URL
        if destination.pathExtension == "mlmodelc" {
            compiledURL = destination
        } else {
            compiledURL = try await MLModel.compileModel(at: destination)
        }

        model = try await MLModel.load(contentsOf: compiledURL)
        modelURL = destination

        // Reset pose window on new model load
        poseWindow.removeAll()

        await MainActor.run { isLoaded = true }
    }

    // MARK: - Inference

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    /// Adds a frame of pose data and returns a prediction if the window is full
    func predict(pose: PoseData) -> PredictionResult? {
        poseWindow.append(pose)
        if poseWindow.count > windowSize {
            poseWindow.removeFirst(poseWindow.count - windowSize)
        }

        guard poseWindow.count == windowSize, let model = model else { return nil }

        do {
            let input = try buildMLInput(from: poseWindow, model: model)
            let output = try model.prediction(from: input)

            guard let label = output.featureValue(for: "label")?.stringValue else {
                return nil
            }

            let confidence: Double
            if let probs = output.featureValue(for: "labelProbabilities")?.dictionaryValue,
               let prob = probs[label]?.doubleValue {
                confidence = prob
            } else {
                confidence = 1.0
            }

            return PredictionResult(gesture: label, confidence: confidence, timestamp: pose.timestamp)

        } catch {
            DispatchQueue.main.async { self.errorMessage = "Inference error: \(error.localizedDescription)" }
            return nil
        }
    }

    // MARK: - Private

    private func buildMLInput(from window: [PoseData], model: MLModel) throws -> MLFeatureProvider {
        guard let inputDesc = model.modelDescription.inputDescriptionsByName.first else {
            throw ModelError.invalidModel
        }

        let inputName = inputDesc.key
        let inputType = inputDesc.value

        // Create MLMultiArray matching the model's expected input shape
        // Shape for action classifier: [1, windowSize, jointCount * 3, 1]
        let shape: [NSNumber] = inputType.multiArrayConstraint?.shape
            ?? [1, NSNumber(value: windowSize), NSNumber(value: jointCount * 3), 1]

        let totalElements = shape.reduce(1) { $0 * $1.intValue }
        var values = [Float](repeating: 0, count: totalElements)

        // Flatten pose window into MLMultiArray in deterministic joint order
        for (frameIdx, pose) in window.enumerated() {
            let joints = orderedJoints(from: pose.joints)
            for (jointIdx, joint) in joints.enumerated() {
                let base = frameIdx * (jointCount * 3) + jointIdx * 3
                if base + 2 < values.count {
                    values[base] = Float(joint.x)
                    values[base + 1] = Float(joint.y)
                    values[base + 2] = Float(joint.z ?? 0)
                }
            }
        }

        let multiArray = try MLMultiArray(shape: shape, dataType: .float32)
        for i in 0..<min(values.count, multiArray.count) {
            multiArray[i] = NSNumber(value: values[i])
        }

        return try MLDictionaryFeatureProvider(dictionary: [inputName: multiArray])
    }
}

// MARK: - Types

struct PredictionResult: Codable {
    let gesture: String
    let confidence: Double
    let timestamp: TimeInterval

    var json: String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

enum ModelError: LocalizedError {
    case invalidURL
    case invalidModel

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid model URL"
        case .invalidModel: return "Model has unexpected input format"
        }
    }
}

/// Fixed joint order matching the skeleton overlay connections
private let jointOrder: [String] = [
    "root", "neck", "nose",
    "left_shoulder", "left_elbow", "left_wrist",
    "right_shoulder", "right_elbow", "right_wrist",
    "left_hip", "left_knee", "left_ankle",
    "right_hip", "right_knee", "right_ankle",
    "left_eye", "left_ear",
    "right_eye", "right_ear"
]

private func orderedJoints(from dict: [String: JointPoint]) -> [JointPoint] {
    jointOrder.compactMap { dict[$0] }
}
