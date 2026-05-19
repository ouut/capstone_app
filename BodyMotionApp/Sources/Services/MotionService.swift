import CoreMotion
import QuartzCore

final class MotionService: ObservableObject {
    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    @Published var isActive = false
    @Published var latestData: MotionData?

    /// Check if device motion is available
    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    init() {
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
    }

    /// Start streaming device motion at the specified interval.
    /// - Parameter interval: Seconds between samples (e.g. 1/30 for 30 Hz)
    func start(interval: TimeInterval = 1.0 / 30.0) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }

        manager.deviceMotionUpdateInterval = interval
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }

            let data = MotionData(
                timestamp: CACurrentMediaTime(),
                acceleration: XYZ(x: motion.userAcceleration.x + motion.gravity.x,
                                  y: motion.userAcceleration.y + motion.gravity.y,
                                  z: motion.userAcceleration.z + motion.gravity.z),
                rotationRate: XYZ(x: motion.rotationRate.x,
                                  y: motion.rotationRate.y,
                                  z: motion.rotationRate.z),
                attitude: XYZW(x: motion.attitude.quaternion.x,
                               y: motion.attitude.quaternion.y,
                               z: motion.attitude.quaternion.z,
                               w: motion.attitude.quaternion.w),
                gravity: XYZ(x: motion.gravity.x,
                             y: motion.gravity.y,
                             z: motion.gravity.z),
                userAcceleration: XYZ(x: motion.userAcceleration.x,
                                      y: motion.userAcceleration.y,
                                      z: motion.userAcceleration.z)
            )
            DispatchQueue.main.async { self.latestData = data }
        }
        isActive = true
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        isActive = false
    }
}
