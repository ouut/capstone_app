import AVFoundation
import CoreImage
import CoreVideo

/// Records low-resolution video chunks for training mode.
/// Each chunk is written to a temporary file and delivered via callback.
final class RecordingService: NSObject {
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var isRecording = false
    private var frameCount = 0
    private var chunkStartTime: CMTime = .zero
    private let chunkDuration: TimeInterval
    private let outputSize: CGSize

    var onChunkReady: ((URL) -> Void)?

    /// - Parameters:
    ///   - outputSize: Low-res dimensions, e.g. 160x120
    ///   - chunkDuration: Seconds per video chunk
    init(outputSize: CGSize = CGSize(width: 160, height: 120), chunkDuration: TimeInterval = 5.0) {
        self.outputSize = outputSize
        self.chunkDuration = chunkDuration
        super.init()
    }

    func start() {
        isRecording = true
        frameCount = 0
        startNewChunk(at: CMTime.zero)
    }

    func stop() {
        isRecording = false
        finishCurrentChunk()
    }

    func appendFrame(_ buffer: CMSampleBuffer) {
        guard isRecording,
              let writer = assetWriter,
              writer.status == .writing,
              let adaptor = pixelBufferAdaptor,
              adaptor.assetWriterInput.isReadyForMoreMediaData,
              let pixelBuffer = CMSampleBufferGetImageBuffer(buffer)
        else { return }

        // Resize to low resolution
        guard let resizedBuffer = resizePixelBuffer(pixelBuffer,
                                                     width: Int(outputSize.width),
                                                     height: Int(outputSize.height))
        else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
        adaptor.append(resizedBuffer, withPresentationTime: timestamp)
        frameCount += 1

        // Check if chunk duration exceeded
        let elapsed = CMTimeSubtract(timestamp, chunkStartTime)
        if CMTimeGetSeconds(elapsed) >= chunkDuration {
            finishCurrentChunk()
            startNewChunk(at: timestamp)
        }
    }

    // MARK: - Private

    private func startNewChunk(at startTime: CMTime) {
        guard isRecording else { return }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        chunkStartTime = startTime

        guard let writer = try? AVAssetWriter(url: outputURL, fileType: .mp4) else { return }
        self.assetWriter = writer

        let compressionSettings: [String: Any] = [
            AVVideoAverageBitRateKey: 200_000,  // 200 Kbps for low-res
            AVVideoMaxKeyFrameIntervalKey: 30
        ]

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoCompressionPropertiesKey: compressionSettings
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: outputSize.width,
                kCVPixelBufferHeightKey as String: outputSize.height
            ]
        )
        pixelBufferAdaptor = adaptor
        assetWriterInput = input

        writer.startWriting()
        writer.startSession(atSourceTime: startTime)
    }

    private func finishCurrentChunk() {
        guard let writer = assetWriter, writer.status == .writing else { return }

        let outputURL = writer.outputURL
        assetWriterInput?.markAsFinished()

        writer.finishWriting { [weak self] in
            guard let self else { return }
            if writer.status == .completed {
                self.onChunkReady?(outputURL)
            }
        }

        assetWriter = nil
        assetWriterInput = nil
        pixelBufferAdaptor = nil
    }

    private func resizePixelBuffer(_ buffer: CVPixelBuffer, width: Int, height: Int) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let scaleX = CGFloat(width) / CGFloat(CVPixelBufferGetWidth(buffer))
        let scaleY = CGFloat(height) / CGFloat(CVPixelBufferGetHeight(buffer))
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        var outBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            nil, &outBuffer
        )

        guard let output = outBuffer else { return nil }
        let context = CIContext()
        context.render(scaled, to: output)
        return output
    }
}
