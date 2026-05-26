📑 跨平台移动动捕数据采集与归档系统（Flutter版）

🛠️ 技术需求与系统设计文档 (PRD & SDD)

1. 业务需求与功能概述 (Product Requirements)

本系统旨在通过跨平台移动端（iOS / Android）App，利用端侧 AI 技术实时捕获人体动作并进行多通道数据输出。系统核心界面包含"实时动捕预览（画布叠加）"与"后台配置中心"。

核心功能映射：

1. 实时动捕叠加： 在手机摄像头预览画面上，实时、高精度地将 3D 骨骼动画连线（2D 投影）精确叠加在人体上方。
2. 多通道本地归档：
   · CSV 数据存档： 支持将每一帧的时间戳、帧号、33个点的 3D 真实世界坐标追加写入本地 .csv 文件。
   · MP4 视频存档： 支持调用硬件编码器，将摄像头原始画面录制为高清 .mp4 文件。
3. 网络实时外发： 支持配置远程服务器的 IP 与端口，通过 UDP 协议 实时外发高效的 Protobuf 二进制骨骼流。
4. 动态模型开关： 系统默认仅开启 Pose（身体 33 点） 模型。手势与面部作为高级开关，可由底层子图动态加载。
5. 可配置帧率： 后台配置中心提供采集帧率档位选择，允许用户根据设备性能与使用场景调节。

---

2. 技术选型与架构 (Technology Stack)

· UI 运营与宿主框架： Flutter (Dart) —— 兼顾高性能原生组件调用与轻量化包体积（约 20MB）。
· 端侧 AI 算法内核： Google MediaPipe Tasks API (Vision / Pose Landmarker)。
· 数据序列化协议： Google Protocol Buffers (Protobuf v3) —— 压缩网络带宽。
· 网络传输协议： UDP (User Datagram Protocol) —— 无阻塞，追求极致实时性。

---

3. 系统核心模块详细设计 (System Module Architecture)

模块一：UI 视图与 2D 像素映射 (Camera & 3D-to-2D Overlay)

实现原理： 底层使用 Flutter camera 插件的 CameraPreview 组件作为背景渲染层。前端覆盖一层自定义画布 CustomPainter。

像素坐标转换（关键点）：
MediaPipe 传回的 Normalized Landmarks 坐标范围为 [0.0, 1.0]。Dart 层必须获取当前手机屏幕上 CameraPreview 的实际物理渲染宽高，按如下公式进行实时映射：

```
pixel_x = normalized_x × preview_actual_width
pixel_y = normalized_y × preview_actual_height
```

⚠️ 关键约束： CameraPreview 为保持画面比例，内部可能存在裁剪（Crop）或留黑边。严禁使用 MediaQuery 或屏幕尺寸替代。必须通过 GlobalKey 获取 RenderBox，在 WidgetsBinding.instance.addPostFrameCallback 回调中读取其实际 size 属性，作为映射计算的唯一依据。

跨平台边界抹平（移动端 + 桌面端）：

1. 镜像修正（全平台可配置）：
   · 移动端： 前置摄像头默认自动开启镜像（x = 1.0 - x），符合用户自拍直觉；后置摄像头默认关闭镜像。
   · 桌面端： 内置摄像头（如 MacBook 屏幕上方）建议默认开启镜像；外接 USB 摄像头建议默认关闭镜像。由于系统 API 无法可靠区分内置与外接摄像头，最终提供用户手动切换的"镜像开关"，置于预览界面工具栏，方便实时调整。
2. 旋转适配（仅移动端）：
   · 移动端： 传感器检测到手机横竖屏切换时，在图像矩阵投喂给 AI 前，必须附加对应的旋转角参数（0°/90°/180°/270°），防止 AI 识别颠倒。
   · 桌面端： 摄像头通常固定安装，不存在物理旋转场景，跳过传感器旋转逻辑，固定使用摄像头原始方向。如用户确有特殊摆放需求，可在设置中手动指定旋转角。

---

可配置帧率节流阀：

配置入口位于后台配置中心，提供六档 FPS 选择，默认 20 FPS。

档位 时间窗口 适用场景
10 FPS 100 ms 极限省电 / 后台长时间无人值守采集
15 FPS ~66 ms 低端机 / 长时录制 / 功耗优先
20 FPS 50 ms 默认平衡模式
24 FPS ~41 ms 影视行业常见帧率，与视频后期对齐
30 FPS ~33 ms 高端机 / 高精度需求 / 与视频录制帧率一致
60 FPS ~16 ms 极限精度 / 高端桌面端 / 科研用途。移动端选择此档位时 UI 须弹出性能过热警告

---

UI 配置项更新：

配置项 类型 可选值 默认值 说明
采集帧率 分段选择 10 / 15 / 20 / 24 / 30 / 60 FPS 20 FPS 控制 AI 采集与 UDP 发送频率。移动端选择 60 FPS 时弹出性能警告

原子忙碌锁（兜底保护）：
嵌套布尔变量 _isAiBusy。若某一帧处理耗时超过时间窗口，在 _isAiBusy == true 期间，新到达的相机帧直接在入口处丢弃，绝不积压，彻底规避内存暴涨。

⚠️ 执行顺序约束： 控流判断（时间戳节流阀 + 原子锁）必须在相机帧的内存拷贝之前执行。即先判断是否处理该帧，确认放行后再从 CameraImage.planes 中逐 plane 拷贝 bytes 并拼成完整 Uint8List，避免无效拷贝占用 CPU 与内存。

---

模块三：音视频录制与 AI 抢夺相机流解耦 (Camera Dual-Stream)

物理隐患：
在部分移动端设备上，同时调用原生 startVideoRecording() 录制 MP4 与 AI 的 startImageStream() 裸流抓取会竞争同一物理摄像头输出口，导致 AI 回调中断或视频编码失败。

强制规避方案（单一采集源 + 分发模式）：

Flutter 侧严禁同时调用 startImageStream() 和 startVideoRecording()。必须在 Native 侧（Swift / Kotlin）封装一个统一的双路分流接口 startDualStream()，对 AVFoundation (iOS) 或 Camera2 (Android) 的数据输出源（Output Stream）进行手动配置：

· 单路采集： 摄像头物理输出流仅开启一路。
· 双路分发： 该输出流同时分发给两个消费者：
  · 消费者 A（视频编码器）： 接收原始帧数据，写入 MP4 文件。
  · 消费者 B（AI 裸流）： 将帧数据转换为像素格式（NV21 / BGRA），通过 Platform Channel 回调至 Flutter 侧供 AI 推理。

此方案确保高清视频写入磁盘与裸帧投喂 AI 在物理层面互不干扰。

---

模块四：多线程隔离优化 (Flutter Isolate)

由于 Flutter (Dart) 是单线程架构，为防止 AI 推理、Protobuf 打包、UDP 发射阻塞 UI 导致画面卡顿，必须使用多线程架构。

线程职责划分：

线程 职责 说明
Main Isolate UI 渲染、相机预览、控流判断、帧字节拷贝、2D 骨骼重绘 保持 UI 高帧率响应
Worker Isolate MediaPipe 推理、坐标转换、CSV 写入、Protobuf 封装、UDP 发射 承载全部计算密集型任务

数据传递流程：

```
Main Isolate                              Worker Isolate
─────────────                             ─────────────
相机帧回调
  ↓
控流判断 (FPS节流 + 原子锁)
  ↓ 放行
分配 frame_sequence_id (自增)
  ↓
从 CameraImage.planes 拷贝 bytes
拼成完整 Uint8List
  ↓
SendPort.send(uint8List)  ───────────→  接收 Uint8List
                                           ↓
                                         MediaPipe 推理
                                           ↓
                                         归一化坐标 → 真实世界坐标(米)
                                           ↓
                                     ┌─────┴─────┐
                                     ↓           ↓
                                  写入 CSV   封装 Protobuf
                                              ↓
                                           UDP 裸发射
                                           ↓
                                    轻量化坐标数组回传
                                    ←─────────────
Main Isolate 接收坐标
  ↓
CustomPainter 重绘骨骼线
```

⚠️ Isolate 落地关键约束：

1. CameraImage 不可跨 Isolate 传递： CameraImage 非 Transferable 类型，不可直接通过 SendPort 发送。必须在主 Isolate 中完成 planes 字节拷贝生成 Uint8List 后，再传递给 Worker Isolate。拷贝操作本身极为轻量（1080p NV21 帧约 2-3ms），不会造成 UI 卡顿。
2. Plugin 重新注册： MediaPipe Tasks 的 Native 插件绑定于创建时的 Isolate。Worker Isolate 必须独立调用 WidgetsFlutterBinding.ensureInitialized() 及 MediaPipe 初始化方法，否则调用 Native 方法时将抛出 MissingPluginException。
3. 帧号统一管理： frame_sequence_id 由主 Isolate 在控流放行后、帧拷贝前统一分配并严格自增，同时传递给 CSV 写入与 Protobuf 封装，保证多通道数据帧号一致。严禁使用相机回调的原始帧编号。

---

4. 传输协议与数据结构规范 (Data Schema)

4.1 网络传输协议 (Protobuf)

复用设置中的 Data_id 作为唯一用户标识符（user_id），网络端无需为多用户额外修改协议结构。

```protobuf
syntax = "proto3";

package motion;

message Vector3 {
  float x = 1; // 真实世界 X 轴（米）
  float y = 2; // 真实世界 Y 轴（米）
  float z = 3; // 真实世界 Z 轴（米），以人体臀部中心为(0,0,0)
}

message BoneLandmark {
  int32 id = 1;                  // 0 - 32 骨骼点编号
  Vector3 world_position = 2;    // 3D 绝对空间坐标（米）
  float visibility = 3;          // 遮挡可见度置信度 (0.0~1.0)
}

message MotionFrame {
  string data_id = 1;            // 复用为用户唯一 ID (来自 UI 的 Data ID)
  int64 timestamp_ms = 2;        // 毫秒级绝对时间戳
  int32 frame_sequence_id = 3;   // 自增帧号（接收端据此检测丢帧与乱序）
  repeated BoneLandmark joints = 4; // 33个核心关键点数组
}
```

UDP 发送策略：
Protobuf 序列化后直接通过 UDP 裸发射，不附加额外长度头。接收端直接尝试反序列化，解析失败则自然丢弃该帧。丢帧检测完全交由 frame_sequence_id 的连续性判断实现——接收端发现序号跳跃即判定发生丢帧，属于正常的 UDP 行为，业务层可按需处理。

发送端代码示例：

```dart
// Worker Isolate
void sendFrame(RawDatagramSocket socket, InternetAddress address, int port, MotionFrame frame) {
  final bytes = frame.writeToBuffer();
  socket.send(bytes, address, port);
}
```

4.2 本地 CSV 存档规范

开启 Save CSV file 后，本地生成的文件表头必须与 Protobuf 数据结构完全对齐：

· 命名规范： [DataID]_[TIMESTAMP].csv
· 表头字段：
  ```
  data_id, timestamp_ms, frame_id, p0_x, p0_y, p0_z, p0_vis, ... p32_x, p32_y, p32_z, p32_vis
  ```

⚠️ 数据一致性约束： CSV 写入与 Protobuf 封装必须共用同一份源数据。Worker Isolate 得到 MediaPipe 推理结果后，应先将归一化坐标转换为真实世界坐标（米），生成统一的数据结构，再分别写入 CSV 文件和构造 Protobuf 消息体，杜绝两通道数据逻辑不一致。

---

5. 平台级合规与沙盒存储 (Storage & Permissions)

5.1 iOS 平台特殊配置

1. 沙盒文件导出权限：
   为了让用户勾选保存的 .csv 和 .mp4 文件能被用户通过 Mac 访达或 iPhone 自带的"文件" App 查看并拷贝，必须在 Info.plist 中强制开启以下两项：
   · UIFileSharingEnabled (Application supports iTunes file sharing) → YES
   · LSSupportsOpeningDocumentsInPlace → YES
2. 隐私权限文本：
   补充 NSCameraUsageDescription 权限申请文本，提供符合 App Store 审核要求的用户可见用途说明。

5.2 Android 平台特殊配置

1. 分区存储适配（Scoped Storage）：
   针对 Android 10（API 29）及以上系统，所有归档数据（.csv）和视频文件（.mp4）必须严格写入内部沙盒私有目录 getExternalFilesDir() 或 getFilesDir()。严禁申请全局 WRITE_EXTERNAL_STORAGE 权限，以满足最新的 Google Play 应用商店上架合规要求。

---

6. UI 配置界面规格

6.1 后台配置中心

配置项 类型 可选值 默认值 说明
Data ID 文本输入 任意字符串 空 用户唯一标识，复用为 CSV 文件名前缀及 Protobuf data_id
采集帧率 分段选择 不同 FPS 控制 AI 采集与 UDP 发送频率
CSV 存档 开关 ON / OFF OFF 是否写入本地 CSV 文件
MP4 录制 开关 ON / OFF OFF 是否启用视频录制
UDP 外发 开关 ON / OFF OFF 是否启用网络实时传输
目标 IP 文本输入 有效 IPv4 地址 127.0.0.1 UDP 数据包目标地址
目标端口 数字输入 1024 - 65535 8888 UDP 数据包目标端口
手势模型 开关 ON / OFF OFF 动态加载手势识别子模型
面部模型 开关 ON / OFF OFF 动态加载面部识别子模型

6.2 实时预览界面

· 全屏 CameraPreview 作为背景层
· 顶层 CustomPainter 叠加 33 点骨骼连线
· 前置摄像头时自动镜像 X 轴
· 骨骼线颜色建议：关键关节点（白点）+ 骨架连线（绿色半透明线条）

---

7. 完整数据流总览

```
┌─────────────────────────────────────────────────────────┐
│                      Main Isolate                        │
│                                                          │
│  ┌──────────────────┐                                   │
│  │  CameraPreview   │  ← UI 渲染层                       │
│  └────────┬─────────┘                                   │
│           │ 相机帧回调                                    │
│           ↓                                              │
│  ┌────────────────────────┐                              │
│  │  控流判断               │                              │
│  │  · FPS 节流阀 (可配置)   │ ← 配置来自后台设置            │
│  │  · 原子锁 _isAiBusy     │                              │
│  └────────┬───────────────┘                              │
│           │ 放行                                         │
│           ↓                                              │
│  ┌────────────────────────┐                              │
│  │  分配 frame_sequence_id │ ← 自增计数器                  │
│  └────────┬───────────────┘                              │
│           ↓                                              │
│  ┌────────────────────────┐                              │
│  │  CameraImage.planes    │                              │
│  │  → 拷贝 bytes          │                              │
│  │  → 拼成 Uint8List      │                              │
│  └────────┬───────────────┘                              │
│           │                                              │
└───────────┼──────────────────────────────────────────────┘
            │ SendPort
            ↓
┌─────────────────────────────────────────────────────────┐
│                     Worker Isolate                        │
│                                                          │
│  ┌────────────────────────┐                              │
│  │  接收 Uint8List         │                              │
│  └────────┬───────────────┘                              │
│           ↓                                              │
│  ┌────────────────────────┐                              │
│  │  MediaPipe 模型推理     │ ← 当前加载: Pose (33点)       │
│  └────────┬───────────────┘    可选: 手势 / 面部          │
│           ↓                                              │
│  ┌────────────────────────┐                              │
│  │  坐标转换               │                              │
│  │  归一化 [0,1] → 米      │                              │
│  └────────┬───────────────┘                              │
│           ↓                                              │
│  ┌───────┴───────┐                                       │
│  ↓               ↓                                       │
│  ┌──────────┐  ┌──────────────────────┐                  │
│  │ CSV 写入  │  │ Protobuf 封装         │                  │
│  │ (本地文件) │  │ → socket.send() 裸发射 │                 │
│  └──────────┘  └──────────────────────┘                  │
│                      ↓                                   │
│                UDP 网络发出                                │
│                                                          │
│  ┌────────────────────────────────────┐                  │
│  │  轻量化坐标数组回传 Main Isolate    │                  │
│  │  (仅 33 个点的 x, y, visibility)    │                  │
│  └────────────────────────────────────┘                  │
│                                                          │
└──────────────────────┬───────────────────────────────────┘
                       │ 回传
                       ↓
┌─────────────────────────────────────────────────────────┐
│                      Main Isolate                        │
│                                                          │
│  ┌────────────────────────┐                              │
│  │  接收轻量化坐标数组      │                              │
│  │  → setState() 触发重绘  │                              │
│  └────────┬───────────────┘                              │
│           ↓                                              │
│  ┌────────────────────────┐                              │
│  │  CustomPainter 重绘     │                              │
│  │  · 33 点关节点          │                              │
│  │  · 骨架连线             │                              │
│  │  · 前置镜像处理         │                              │
│  └────────────────────────┘                              │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

文档版本： v2.1
最后修订日期： 2026-05-26
修订摘要：

· 移除 UDP 长度头设计，采用 Protobuf 裸发射 + frame_sequence_id 丢帧检测
· 新增可配置采集帧率功能（15/20/30 FPS 三档可选）
· 新增 UI 配置界面规格说明
· 补充完整数据流总览图
· 明确主 Isolate 帧拷贝操作的不可规避性及性能影响说明