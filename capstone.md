# 手机摄像头体感游戏平台 — 项目文档 V2

## 一、项目愿景

构建一个**可插拔架构的通用体感游戏平台**。用户使用 iPhone 摄像头捕捉身体动作，通过本地 AI 模型实时识别动作意图，将意图信号发送至游戏设备，实现对游戏角色和 UI 的控制。

核心定位：**gesture input for game**（专注游戏领域的手势输入方案），而非通用的系统级手势控制。

---

## 二、功能清单

| # | 功能 | 状态 |
|---|------|------|
| 1 | UI 设定 User ID | ✅ 已实现 |
| 2 | UI 设定服务端 IP + 端口 | ✅ 已实现 |
| 3 | Vision 框架提取骨骼关键点，可选发送低分辨率视频 | ✅ 已实现 |
| 4 | 热加载指定 URL 的 Core ML 动作意图模型 | ✅ 已实现 |
| 5 | 骨骼关键点输入本地 Core ML 模型，预测结果流发送到服务端 | ✅ 已实现 |
| 6 | 发送手机姿态数据（加速度、陀螺仪、四元数） | ✅ 已实现 |
| 7 | 发送麦克风音量数据（RMS / Peak dB） | ✅ 已实现 |
| 8 | UI 自由组合选择发送哪些传感器数据 | ✅ 已实现 |

---

## 三、核心架构：三层解耦 + 可插拔设计

### 3.1 整体分层

| 层级 | 位置 | 职责 |
|:---|:---|:---|
| **感知层** | iPhone | 摄像头采集 + Vision 提取骨骼 + CoreMotion 姿态 + 麦克风音量 |
| **理解层** | iPhone（本地） | Core ML 模型实时推理，将骨骼点流翻译为意图标签 |
| **通信层** | iPhone → 游戏设备 | WebRTC DataChannel 发送意图信号 / 传感器帧 |

### 3.2 传感器数据（每帧聚合）

```json
{
  "timestamp": 1.234,
  "pose": { "joints": {...}, "confidence": 0.9 },
  "motion": {
    "acceleration": {"x":0,"y":0,"z":-1},
    "rotationRate": {"x":0,"y":0,"z":0},
    "attitude": {"x":0,"y":0,"z":0,"w":1},
    "gravity": {"x":0,"y":0,"z":-1},
    "userAcceleration": {"x":0,"y":0,"z":0}
  },
  "audio": { "rmsDB": -23.5, "peakDB": -12.1 },
  "prediction": { "gesture": "punch", "confidence": 0.98 }
}
```

三种传感器数据（Pose / Motion / Audio）可通过 Settings UI 独立开关，自由组合。游戏模式下骨骼数据强制开启（模型推理必须）。

### 3.3 可插拔适配层

每个游戏对应独立的动作映射配置（JSON 格式），定义"手势词典"：
- **格斗游戏** (`fighting.json`)：右手速度 > 阈值 + 方向向前 → "出拳"
- **魔法游戏** (`magic.json`)：食指指尖轨迹匹配预设图形 → "火系魔法"

---

## 四、硬件方案

### 4.1 主设备：iPhone
- 利用内置摄像头和 A 系列芯片的 Neural Engine
- 搭配 CoreMotion 陀螺仪/加速度计 + 麦克风

### 4.2 配套工具
- **信号服务器**：本地电脑或 Ubuntu 盒子跑 Node.js WebSocket 信令（端口 3000） + Tailscale Funnel 暴露公网
- **游戏运行设备**：Mac / PC / 游戏主机（接收意图信号并驱动游戏）

---

## 五、软件方案

### 5.1 核心技术栈（苹果原生）

| 框架/工具 | 用途 |
|:---|:---|
| **Vision** | 实时提取人体骨骼关键点（3 个 API 可选） |
| **Core ML** | 在 iPhone 本地运行动作分类模型 |
| **CoreMotion** | 手机姿态：加速度、陀螺仪、四元数、重力方向 |
| **AVFoundation** | 摄像头采集 + 麦克风音量 |
| **WebRTC** | DataChannel 低延迟数据传输 |
| **URLSessionWebSocket** | WebSocket 信令（SDP / ICE 交换） |

### 5.2 Vision API 三选一

| API | 底层类 | 输出 | 人数 |
|-----|--------|------|------|
| Body Pose 2D (多人) | `VNDetectHumanBodyPoseRequest` | 19个2D关节点(x,y)+置信度 | ~6人 |
| Body Pose 3D (单人) | `VNDetectHumanBodyPose3DRequest` | 19个3D关节点(x,y,z) | 1人 |
| Person Mask (≤4人) | `VNGeneratePersonInstanceMaskRequest` | 人体区域 boundingBox+置信度 | ≤4人 |

API 可通过 Settings UI 下拉选择，选中后显示中文说明。关闭骨骼发送时该选项灰掉。

### 5.3 网络通信

- **信令**：WebSocket (`ws://ip:port/signaling`)，注册 → SDP Offer/Answer → ICE 交换
- **数据**：WebRTC DataChannel（无序传输、零重传，优化实时性）；DataChannel 未就绪时 WebSocket fallback
- **服务端 IP/端口**：通过 Settings UI 手动输入，无自动发现（Bonjour/mDNS）

### 5.4 模型热加载

- **方式**：手动从自定义服务器下载 `.mlmodelc`（URL 格式 `https://ip:port/model_name`）
- **IP/端口**：复用 Settings 中配置的服务端地址
- **加载后缓存**到本地，切换模型时滑动窗口重置

### 5.5 两种工作模式

| 模式 | 行为 |
|------|------|
| **训练模式** | 发送骨骼数据 + 可选低分辨率视频(160×120) + 手机姿态 + 麦克风音量到服务端 |
| **游戏模式** | 骨骼数据输入本地 Core ML 模型，仅发送预测结果 (gesture + confidence) |

---

## 六、推理方案

- **策略**：云端训练 + 本地推理
- **延迟**：本地 Core ML < 30ms，满足格斗游戏 < 66ms 要求
- **架构**：MLP（首选快速验证）→ ST-GCN（进阶）→ Transformer（极致精度）

---

## 七、技术决策汇总（来自 Q&A 澄清）

| # | 问题 | 决策 |
|---|------|------|
| 1 | 网络协议 | WebRTC DataChannel + WebSocket 信令 |
| 2 | 服务发现 | 手动输入 IP + 端口 |
| 3 | 模型热加载 | 手动下载 `.mlmodelc`，URL 可配置 |
| 4 | 动作映射 Schema | 待讨论 |
| 5 | 多人检测 | Vision API 三选一，UI 切换 |
| 6 | 安全隐私 | 待讨论 |
| 7 | UI 架构 | 2 Tab：Capture（摄像头+骨骼叠加+状态栏） + Settings（表单配置） |
| 8 | 测试方案 | 待讨论 |
| 9 | 版本兼容 | 部署目标 iOS 17.0，尽量好的兼容性 |
| 10 | 热/电池 | 待讨论 |
| 11 | 传感器选择 | Pose / Motion / Audio 三个独立 Toggle 自由组合 |

---

## 八、项目结构

```
capstone_app/
├── capstone.md
├── questions.md
├── TODO.md
├── BodyMotionApp/
│   ├── project.yml              # XcodeGen 项目描述
│   ├── Info.plist               # 摄像头 + 麦克风权限
│   ├── exportOptions.plist      # IPA 导出配置
│   ├── build.sh                 # 一键构建脚本
│   ├── .gitignore
│   └── Sources/
│       ├── App.swift
│       ├── Models/
│       │   ├── AppSettings.swift    # 持久化设置 + Vision/Mode 枚举
│       │   └── PoseData.swift       # Pose/Motion/Audio/SensorFrame 数据模型
│       ├── Services/
│       │   ├── CameraService.swift  # AVFoundation 前置摄像头 → AsyncStream
│       │   ├── VisionService.swift  # 3 个 Vision API + 骨骼映射
│       │   ├── MotionService.swift  # CoreMotion 姿态数据
│       │   ├── AudioService.swift   # 麦克风 RMS/Peak 音量
│       │   ├── WebRTCService.swift  # 信令 + DataChannel
│       │   ├── ModelService.swift   # Core ML 下载/编译/推理
│       │   └── RecordingService.swift # 低分辨率视频录制
│       ├── ViewModels/
│       │   ├── CaptureViewModel.swift  # 帧处理管线总协调
│       │   └── SettingsViewModel.swift
│       └── Views/
│           ├── ContentView.swift    # 2-Tab 容器
│           ├── CaptureView.swift    # 摄像头 + Canvas 骨骼叠加 + 状态栏
│           └── SettingsView.swift   # 配置表单
└── server/
    ├── package.json
    ├── signaling-server.js       # WebSocket 信令中继
    ├── data-server.js            # 训练数据接收（.jsonl 存储）
    └── test-signaling.js         # 信令服务器 11 项测试
```

---

## 九、构建与部署

### 9.1 前提条件
- Xcode 26+（Mac App Store）
- Homebrew（`brew install xcodegen node`）
- Apple ID（免费账号即可，用于真机签名）

### 9.2 模拟器构建
```bash
cd BodyMotionApp
xcodegen generate --spec project.yml
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project BodyMotionApp.xcodeproj \
  -scheme BodyMotionApp -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### 9.3 真机构建 + 安装
```bash
cd BodyMotionApp
./install.sh
```

### 9.4 信令服务器
```bash
cd server
npm install
node signaling-server.js    # 监听 ws://0.0.0.0:3000
npm test                    # 运行 11 项自动化测试
```

### 9.5 暴露公网
```bash
tailscale funnel 3000
```

---

## 十、当前实现状态

| 组件 | 状态 | 验证 |
|------|------|------|
| iOS App（15 个 Swift 源文件） | ✅ 完成 | 模拟器编译通过、运行正常 |
| WebRTC 集成 | ✅ 完成 | SPM 依赖解析成功 |
| 信令服务器 | ✅ 完成 | 11/11 测试通过 |
| 数据服务器 | ✅ 完成 | 代码审查通过 |
| 真机安装 | ⚠️ 待用户终端执行 | 签名证书已就绪 (Team: 3DGN76WC8B) |
| 动作映射 Schema | 🔲 待讨论 | — |
| 安全隐私 | 🔲 待讨论 | — |
| 测试方案 | 🔲 待讨论 | — |
| 热/电池优化 | 🔲 待讨论 | — |
