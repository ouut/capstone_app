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

        configureSession()
    }

    func start() {
        guard !session.isRunning else { return }
        queue.async { self.session.startRunning() }
    }

    func stop() {
        guard session.isRunning else { return }
        queue.async { self.session.stopRunning() }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
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
        DispatchQueue.main.async { self.isReady = true }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameContinuation?.yield(sampleBuffer)
    }
}
