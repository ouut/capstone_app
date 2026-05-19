import Foundation

enum AppMode: String, CaseIterable, Identifiable {
    case training = "训练模式"
    case game = "游戏模式"

    var id: String { rawValue }
}

enum VisionAPIType: String, CaseIterable, Identifiable {
    case bodyPose2D = "Body Pose 2D (多人)"
    case bodyPose3D = "Body Pose 3D (单人)"
    case personMask = "Person Mask (≤4人)"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .bodyPose2D:
            return "VNDetectHumanBodyPoseRequest\n返回全身19个2D关节点(x,y) + 置信度，支持多人同时检测（约6人），速度最快。适合群体游戏场景。"
        case .bodyPose3D:
            return "VNDetectHumanBodyPose3DRequest\n返回全身19个3D关节点(x,y,z)，仅支持单人。Z轴为相对深度，适合需要空间位置判断的精细动作。"
        case .personMask:
            return "VNGeneratePersonInstanceMaskRequest\n返回人体分割蒙版，最多4人。不输出骨骼点，只输出人体轮廓区域的boundingBox + 置信度。适合需要人物位置/大小判断的场景。"
        }
    }
}

/// Which sensor data streams to send
struct SensorSelection: OptionSet {
    let rawValue: Int

    static let pose  = SensorSelection(rawValue: 1 << 0)
    static let motion = SensorSelection(rawValue: 1 << 1)
    static let audio  = SensorSelection(rawValue: 1 << 2)

    static let all: SensorSelection = [.pose, .motion, .audio]
    static let none: SensorSelection = []
}

final class AppSettings: ObservableObject {
    @Published var serverIP: String {
        didSet { UserDefaults.standard.set(serverIP, forKey: .keyServerIP) }
    }
    @Published var serverPort: String {
        didSet { UserDefaults.standard.set(serverPort, forKey: .keyServerPort) }
    }
    @Published var visionAPI: VisionAPIType {
        didSet { UserDefaults.standard.set(visionAPI.rawValue, forKey: .keyVisionAPI) }
    }
    @Published var modelURL: String {
        didSet { UserDefaults.standard.set(modelURL, forKey: .keyModelURL) }
    }
    @Published var mode: AppMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: .keyMode) }
    }
    @Published var useFrontCamera: Bool {
        didSet { UserDefaults.standard.set(useFrontCamera, forKey: .keyUseFrontCamera) }
    }

    // Individual sensor toggles — independently selectable
    @Published var sendPose: Bool {
        didSet { UserDefaults.standard.set(sendPose, forKey: .keySendPose) }
    }
    @Published var sendMotion: Bool {
        didSet { UserDefaults.standard.set(sendMotion, forKey: .keySendMotion) }
    }
    @Published var sendAudio: Bool {
        didSet { UserDefaults.standard.set(sendAudio, forKey: .keySendAudio) }
    }

    /// Bitmask of which sensors the user wants to send
    var sensorSelection: SensorSelection {
        var sel: SensorSelection = []
        if sendPose   { sel.insert(.pose) }
        if sendMotion { sel.insert(.motion) }
        if sendAudio  { sel.insert(.audio) }
        return sel
    }

    init() {
        serverIP = UserDefaults.standard.string(forKey: .keyServerIP) ?? "192.168.1.100"
        serverPort = UserDefaults.standard.string(forKey: .keyServerPort) ?? "5000"
        modelURL = UserDefaults.standard.string(forKey: .keyModelURL) ?? ""
        visionAPI = VisionAPIType(
            rawValue: UserDefaults.standard.string(forKey: .keyVisionAPI) ?? VisionAPIType.bodyPose2D.rawValue
        ) ?? .bodyPose2D
        mode = AppMode(
            rawValue: UserDefaults.standard.string(forKey: .keyMode) ?? AppMode.training.rawValue
        ) ?? .training

        let storedFrontCamera = UserDefaults.standard.object(forKey: .keyUseFrontCamera)
        useFrontCamera = (storedFrontCamera as? Bool) ?? true

        // Default: all sensors on
        let storedPose = UserDefaults.standard.object(forKey: .keySendPose)
        sendPose = (storedPose as? Bool) ?? true

        let storedMotion = UserDefaults.standard.object(forKey: .keySendMotion)
        sendMotion = (storedMotion as? Bool) ?? false

        let storedAudio = UserDefaults.standard.object(forKey: .keySendAudio)
        sendAudio = (storedAudio as? Bool) ?? false
    }
}

private extension String {
    static let keyServerIP = "server_ip"
    static let keyServerPort = "server_port"
    static let keyVisionAPI = "vision_api"
    static let keyModelURL = "model_url"
    static let keyMode = "app_mode"
    static let keySendPose = "send_pose"
    static let keyUseFrontCamera = "use_front_camera"
    static let keySendMotion = "send_motion"
    static let keySendAudio = "send_audio"
}
