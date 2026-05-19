import AVFoundation

final class AudioService: ObservableObject {
    private let engine = AVAudioEngine()
    private var isRunning = false

    @Published var isActive = false
    @Published var latestData: AudioData?

    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized { return true }
        if status == .notDetermined {
            return await AVCaptureDevice.requestAccess(for: .audio)
        }
        return false
    }

    /// Start capturing audio level (RMS + peak) at ~10 Hz
    func start() {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
            guard let self else { return }

            let channelData = buffer.floatChannelData
            let frameLength = Int(buffer.frameLength)

            guard let data = channelData?[0] else { return }

            // Compute RMS and peak
            var sumSquares: Float = 0
            var peak: Float = 0

            for i in 0..<frameLength {
                let sample = data[i]
                sumSquares += sample * sample
                peak = max(peak, abs(sample))
            }

            let rms = sqrt(sumSquares / Float(frameLength))
            let rmsDB = rms > 0 ? 20 * log10(rms) : -160
            let peakDB = peak > 0 ? 20 * log10(peak) : -160

            let audioData = AudioData(
                timestamp: CACurrentMediaTime(),
                rmsDB: Double(rmsDB),
                peakDB: Double(peakDB)
            )
            DispatchQueue.main.async { self.latestData = audioData }
        }

        do {
            try engine.start()
            isRunning = true
            isActive = true
        } catch {
            print("[AudioService] Failed to start: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        isActive = false
    }
}
