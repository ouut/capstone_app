import Foundation

// MARK: - Pose (Vision骨骼关键点)

struct JointPoint: Codable {
    let x: Double
    let y: Double
    let z: Double?
    let confidence: Double
}

struct PoseData: Codable {
    let timestamp: TimeInterval
    let joints: [String: JointPoint]
    let gesture: String?
    let confidence: Double?

    init(timestamp: TimeInterval, joints: [String: JointPoint], gesture: String? = nil, confidence: Double? = nil) {
        self.timestamp = timestamp
        self.joints = joints
        self.gesture = gesture
        self.confidence = confidence
    }
}

// MARK: - Motion (手机姿态)

struct MotionData: Codable {
    let timestamp: TimeInterval
    /// 加速度 (G) — 含重力
    let acceleration: XYZ
    /// 陀螺仪旋转速率 (rad/s)
    let rotationRate: XYZ
    /// 姿态四元数 (x,y,z,w)
    let attitude: XYZW
    /// 重力方向 (G)
    let gravity: XYZ
    /// 用户加速度 (G) — 不含重力
    let userAcceleration: XYZ
}

struct XYZ: Codable {
    let x: Double
    let y: Double
    let z: Double
}

struct XYZW: Codable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double
}

// MARK: - Audio (声音)

struct AudioData: Codable {
    let timestamp: TimeInterval
    /// RMS 音量 (dB)
    let rmsDB: Double
    /// 峰值音量 (dB)
    let peakDB: Double
}

// MARK: - Sensor Frame (每帧聚合包)

struct SensorFrame: Codable {
    let timestamp: TimeInterval
    let pose: PoseData?
    let motion: MotionData?
    let audio: AudioData?
    let prediction: PredictionResult?
}
