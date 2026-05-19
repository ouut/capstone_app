import AVFoundation
import Combine

final class CaptureViewModel: ObservableObject {
    let settings: AppSettings
    let cameraService = CameraService()
    private let visionService = VisionService()
    private let modelService = ModelService()
    private let recordingService = RecordingService()
    private let motionService = MotionService()
    private let audioService = AudioService()
    private var udpService: UDPService?

    private var processingTask: Task<Void, Never>?
    private let encoder = JSONEncoder()

    @Published var currentPoses: [PoseData] = []
    @Published var lastPrediction: PredictionResult?
    @Published var isConnected = false
    @Published var statusText = "Initializing..."

    @Published var latestMotion: MotionData?
    @Published var latestAudio: AudioData?

    var cameraSession: AVCaptureSession { cameraService.session }
    var isCameraReady: Bool { cameraService.isReady }
    var modeLabel: String { settings.mode.rawValue }

    /// In game mode, pose is always required for model inference
    private var effectiveSendPose: Bool {
        settings.mode == .game || settings.sendPose
    }

    init(settings: AppSettings) {
        self.settings = settings
        setupUDP()
        observeSensorToggles()
        observeMotion()
        observeAudio()
    }

    func start() {
        Task {
            await cameraService.requestPermissionAndConfigure()
            cameraService.start()
            startProcessingFrames()
            udpService?.setActive(true)

            if settings.sendMotion { motionService.start() }
            if settings.sendAudio  { startAudioIfPermitted() }

            if settings.mode == .training {
                recordingService.start()
                statusText = cameraService.isReady ? "Camera ready" : "Camera unavailable"
            } else {
                loadModel()
            }

            // If UDP isn't configured, show final status now.
            if udpService == nil && statusText == "Initializing..." {
                statusText = cameraService.isReady ? "Camera ready" : "Camera unavailable"
            }
        }
    }

    func stop() {
        processingTask?.cancel()
        cameraService.stop()
        recordingService.stop()
        motionService.stop()
        audioService.stop()
        udpService?.setActive(false)
        modelService.cancelDownload()
    }

    func loadModel() {
        guard settings.mode == .game else { return }
        guard !settings.modelURL.isEmpty else {
            statusText = "No model URL configured"
            return
        }
        Task {
            do {
                try await modelService.downloadAndLoad(from: settings.modelURL)
                statusText = "Model loaded"
            } catch {
                statusText = "Model failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Private

    private func setupUDP() {
        guard !settings.serverIP.isEmpty else { return }

        let udp = UDPService(host: settings.serverIP, port: settings.serverPort)
        udp.onDataReceived = { [weak self] _ in }
        udp.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.isConnected = (state == .ready)
                self?.statusText = state.label
            }
            .store(in: &cancellables)

        udpService = udp
    }

    /// React to sensor toggle changes at runtime without restart
    private func observeSensorToggles() {
        settings.$sendMotion
            .dropFirst()
            .sink { [weak self] on in
                if on { self?.motionService.start() } else { self?.motionService.stop() }
            }
            .store(in: &cancellables)

        settings.$sendAudio
            .dropFirst()
            .sink { [weak self] on in
                if on { self?.startAudioIfPermitted() } else { self?.audioService.stop() }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    private func observeMotion() {
        motionService.$latestData
            .receive(on: DispatchQueue.main)
            .assign(to: \.latestMotion, on: self)
            .store(in: &cancellables)
    }

    private func observeAudio() {
        audioService.$latestData
            .receive(on: DispatchQueue.main)
            .assign(to: \.latestAudio, on: self)
            .store(in: &cancellables)
    }

    private func startAudioIfPermitted() {
        Task {
            guard await audioService.requestPermission() else { return }
            audioService.start()
        }
    }

    private func startProcessingFrames() {
        processingTask = Task { [weak self] in
            guard let self else { return }

            for await frame in self.cameraService.frameStream {
                guard !Task.isCancelled else { break }
                await self.processFrame(frame)
            }
        }
    }

    private func processFrame(_ frame: CMSampleBuffer) async {
        let timestamp = CACurrentMediaTime()
        let sel = settings.sensorSelection

        // Only run Vision if we need pose data
        let pose: PoseData?
        if effectiveSendPose {
            let poses = (try? visionService.process(buffer: frame, api: settings.visionAPI)) ?? []
            await MainActor.run { currentPoses = poses }
            pose = poses.first
        } else {
            pose = nil
        }

        // Build sensor frame with only the selected data streams
        let sensorFrame = SensorFrame(
            timestamp: timestamp,
            pose: pose,
            motion: sel.contains(.motion) ? motionService.latestData : nil,
            audio: sel.contains(.audio) ? audioService.latestData : nil,
            prediction: nil
        )

        switch settings.mode {
        case .training:
            await handleTrainingMode(frame: frame, sensorFrame: sensorFrame)

        case .game:
            await handleGameMode(pose: pose, sensorFrame: sensorFrame)
        }
    }

    private func handleTrainingMode(frame: CMSampleBuffer, sensorFrame: SensorFrame) async {
        if settings.sendPose {
            recordingService.appendFrame(frame)
        }
        send(sensorFrame)
    }

    private func handleGameMode(pose: PoseData?, sensorFrame: SensorFrame) async {
        guard let pose else { return }

        let prediction = modelService.predict(pose: pose)
        await MainActor.run { lastPrediction = prediction }

        let frame = SensorFrame(
            timestamp: sensorFrame.timestamp,
            pose: sensorFrame.pose,
            motion: sensorFrame.motion,
            audio: sensorFrame.audio,
            prediction: prediction
        )
        send(frame)
    }

    private func send(_ frame: SensorFrame) {
        guard let data = try? encoder.encode(frame) else { return }
        udpService?.send(data)
    }
}
