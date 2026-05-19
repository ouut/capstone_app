import CoreML
import Foundation

class MLModelManager {
    private var model: MLModel?
    private let inferenceQueue = DispatchQueue(label: "com.bodydetection.mlinference", qos: .userInitiated)

    var isModelLoaded: Bool { model != nil || mockMode }
    var isRealModel: Bool { model != nil }
    var mockMode = true
    var modelName: String {
        if let model = model {
            return model.modelDescription.metadata[.creatorDefinedKey] as? String ?? "Unknown"
        }
        return mockMode ? "Mock (testing)" : "None"
    }

    func downloadModel(from url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let tempURL = tempURL else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "MLModelManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Download returned no file"]))) }
                return
            }

            do {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destURL = docs.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: tempURL, to: destURL)

                let compiledURL = try MLModel.compileModel(at: destURL)
                let model = try MLModel(contentsOf: compiledURL)
                self?.model = model

                let name = url.lastPathComponent
                DispatchQueue.main.async { completion(.success(name)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        task.resume()
    }

    func loadBundledModel(named name: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") ??
                         Bundle.main.url(forResource: name, withExtension: "mlmodel") else {
            completion(.failure(NSError(domain: "MLModelManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Model not found in bundle: \(name)"])))
            return
        }
        do {
            let compiledURL: URL
            if url.pathExtension == "mlmodel" {
                compiledURL = try MLModel.compileModel(at: url)
            } else {
                compiledURL = url
            }
            model = try MLModel(contentsOf: compiledURL)
            completion(.success(name))
        } catch {
            completion(.failure(error))
        }
    }

    func predict(jointPositions: [SIMD3<Float>], completion: @escaping (Result<MLMultiArray?, Error>) -> Void) {
        if let model = model {
            predictWithModel(model, jointPositions: jointPositions, completion: completion)
        } else if mockMode {
            predictMock(jointPositions: jointPositions, completion: completion)
        } else {
            completion(.failure(NSError(domain: "MLModelManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "No model loaded"])))
        }
    }

    private func predictWithModel(_ model: MLModel, jointPositions: [SIMD3<Float>], completion: @escaping (Result<MLMultiArray?, Error>) -> Void) {
        inferenceQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                guard let inputDesc = model.modelDescription.inputDescriptionsByName.first?.value else {
                    DispatchQueue.main.async { completion(.failure(NSError(domain: "MLModelManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Model has no inputs"]))) }
                    return
                }

                let result: MLMultiArray?
                if inputDesc.type == .multiArray {
                    let array = try self.createMultiArray(from: jointPositions, constraint: inputDesc.multiArrayConstraint)
                    let input = try self.createInput(multiArray: array, featureName: inputDesc.name, model: model)
                    let output = try model.prediction(from: input)
                    result = output.featureValue(for: output.featureNames.first ?? "")?.multiArrayValue
                } else if inputDesc.type == .image {
                    DispatchQueue.main.async { completion(.failure(NSError(domain: "MLModelManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Model expects image input, not skeleton data"]))) }
                    return
                } else {
                    let array = try self.createMultiArray(from: jointPositions, constraint: nil)
                    let input = try self.createInput(multiArray: array, featureName: inputDesc.name, model: model)
                    let output = try model.prediction(from: input)
                    result = output.featureValue(for: output.featureNames.first ?? "")?.multiArrayValue
                }

                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Mock inference: computes derived features from skeleton joints so the UDP pipeline works without a real model.
    private func predictMock(jointPositions: [SIMD3<Float>], completion: @escaping (Result<MLMultiArray?, Error>) -> Void) {
        inferenceQueue.async {
            guard !jointPositions.isEmpty else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "MLModelManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "Empty joint positions"]))) }
                return
            }

            // Compute body center as the centroid of all joints
            var centroid = SIMD3<Float>(0, 0, 0)
            for p in jointPositions { centroid += p }
            centroid /= Float(jointPositions.count)

            // Compute a 10-element mock prediction vector:
            // [centroid.x, centroid.y, centroid.z, body_height, spread, leftmost, rightmost, highest, lowest, jointCount]
            let ys = jointPositions.map { $0.y }
            let xs = jointPositions.map { $0.x }

            let bodyHeight = (ys.max() ?? 0) - (ys.min() ?? 0)
            let spread = (xs.max() ?? 0) - (xs.min() ?? 0)
            let mockValues: [Float] = [
                centroid.x, centroid.y, centroid.z,
                bodyHeight, spread,
                xs.min() ?? 0, xs.max() ?? 0,
                ys.min() ?? 0, ys.max() ?? 0,
                Float(jointPositions.count)
            ]

            do {
                let array = try MLMultiArray(shape: [NSNumber(value: mockValues.count)], dataType: .float32)
                let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: mockValues.count)
                for i in 0..<mockValues.count { ptr[i] = mockValues[i] }
                DispatchQueue.main.async { completion(.success(array)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func createMultiArray(from positions: [SIMD3<Float>], constraint: MLMultiArrayConstraint?) throws -> MLMultiArray {
        let count = positions.count * 3

        let shape: [NSNumber]
        if let constraint = constraint {
            shape = constraint.shape
        } else {
            shape = [NSNumber(value: count)]
        }

        let array = try MLMultiArray(shape: shape, dataType: .float32)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        for i in 0..<min(count, array.count) {
            let jointIdx = i / 3
            let component = i % 3
            if jointIdx < positions.count {
                let p = positions[jointIdx]
                switch component {
                case 0: ptr[i] = p.x
                case 1: ptr[i] = p.y
                case 2: ptr[i] = p.z
                default: ptr[i] = 0
                }
            } else {
                ptr[i] = 0
            }
        }
        return array
    }

    private func createInput(multiArray: MLMultiArray, featureName: String, model: MLModel) throws -> MLFeatureProvider {
        let inputDict: [String: MLFeatureValue] = [featureName: MLFeatureValue(multiArray: multiArray)]
        return try MLDictionaryFeatureProvider(dictionary: inputDict)
    }

    /// Serialize an MLMultiArray prediction to JSON for UDP transport.
    func serializePrediction(_ array: MLMultiArray) -> Data? {
        let count = array.count
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: count)
        let values = Array(UnsafeBufferPointer(start: ptr, count: count))
        return try? JSONSerialization.data(withJSONObject: ["prediction": values])
    }
}
