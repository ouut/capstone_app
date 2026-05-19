import AVFoundation
import CoreVideo

final class CameraService: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.frame.queue", qos: .userInitiated)

    private var frameContinuation: AsyncStream<CMSampleBuffer>.Continuation?
    private(set) var frameStream: AsyncStream<CMSampleBuffer>!

    @Published var isReady = false
    @Published var errorMessage: String?
    @Published var currentPosition: AVCaptureDevice.Position = .front

    override init() {
        super.init()
        frameStream = AsyncStream { continuation in
            self.frameContinuation = continuation
        }
    }

    func requestPermissionAndConfigure() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var authorized = status == .authorized

        if status == .notDetermined {
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        }

        guard authorized else {
            await MainActor.run { errorMessage = "Camera access denied" }
            return
        }

        configureSession(position: .front)
    }

    func start() {
        // Session already started in configureSession; if stopped, restart it
        if !session.isRunning {
            queue.async { self.session.startRunning() }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        queue.async { self.session.stopRunning() }
    }

    /// Switch between front and back camera
    func switchCamera(to position: AVCaptureDevice.Position) {
        guard position != currentPosition else { return }
        let wasRunning = session.isRunning

        session.beginConfiguration()

        // Remove existing video input
        for input in session.inputs {
            session.removeInput(input)
        }

        guard let device = cameraDevice(for: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.errorMessage = "Failed to switch camera" }
            return
        }

        session.addInput(input)
        session.commitConfiguration()

        currentPosition = position

        if wasRunning {
            queue.async { self.session.startRunning() }
        }
    }

    // MARK: - Private

    private func configureSession(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        session.sessionPreset = .medium

        guard let device = cameraDevice(for: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.errorMessage = "Failed to configure camera" }
            return
        }

        session.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: queue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(videoOutput)

        session.commitConfiguration()

        currentPosition = position
        // Start the session immediately so the preview layer is never black
        queue.async { self.session.startRunning() }
        DispatchQueue.main.async { self.isReady = true }
    }

    private func cameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInUltraWideCamera]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameContinuation?.yield(sampleBuffer)
    }
}
