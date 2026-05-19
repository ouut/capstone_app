import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showSettingsSaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP Address", text: $viewModel.settings.serverIP)
                        .keyboardType(.decimalPad)
                    TextField("Port", text: $viewModel.settings.serverPort)
                        .keyboardType(.numberPad)
                } header: {
                    Text("游戏主机 (UDP)")
                } footer: {
                    Text("iPhone 将通过 UDP 直接向该地址发送传感器数据。游戏主机运行 udp-receiver.js 接收。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Toggle("前置摄像头", isOn: $viewModel.settings.useFrontCamera)
                } header: {
                    Text("摄像头")
                } footer: {
                    Text(viewModel.settings.useFrontCamera ? "当前使用前置摄像头" : "当前使用后置摄像头")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Picker("Mode", selection: $viewModel.settings.mode) {
                        ForEach(AppMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("模式")
                } footer: {
                    Text(viewModel.settings.mode == .training
                         ? "训练模式：发送传感器数据到服务端用于训练"
                         : "游戏模式：本地模型推理后发送预测结果")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - 传感器数据选择

                Section {
                    Toggle("人体骨骼 (Pose)", isOn: $viewModel.settings.sendPose)
                    Toggle("手机姿态 (Motion)", isOn: $viewModel.settings.sendMotion)
                    Toggle("麦克风音量 (Audio)", isOn: $viewModel.settings.sendAudio)
                } header: {
                    Text("发送哪些传感器数据")
                } footer: {
                    Text(sensorFooter)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Vision API

                Section {
                    Picker("接口", selection: $viewModel.settings.visionAPI) {
                        ForEach(VisionAPIType.allCases) { api in
                            Text(api.rawValue).tag(api)
                        }
                    }
                    .disabled(!viewModel.settings.sendPose)
                } header: {
                    Text("Vision API")
                } footer: {
                    Text(viewModel.settings.visionAPI.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Model

                Section("意图识别模型") {
                    TextField("Model URL", text: $viewModel.settings.modelURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disabled(viewModel.settings.mode != .game)
                }

                Section {
                    Button("Save") {
                        showSettingsSaved = true
                    }
                    .frame(maxWidth: .infinity)
                    .alert("Settings Saved", isPresented: $showSettingsSaved) {
                        Button("OK", role: .cancel) {}
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var sensorFooter: String {
        var lines: [String] = []
        if viewModel.settings.mode == .game {
            lines.append("游戏模式下骨骼数据始终需要（模型推理必须）。")
        }
        let sel = viewModel.settings.sensorSelection
        if sel.isEmpty {
            lines.append("⚠️ 未选择任何传感器数据，不会发送任何数据。")
        } else {
            var sending: [String] = []
            if sel.contains(.pose)  { sending.append("骨骼") }
            if sel.contains(.motion) { sending.append("姿态") }
            if sel.contains(.audio)  { sending.append("音量") }
            lines.append("当前发送：\(sending.joined(separator: " + "))")
        }
        return lines.joined(separator: "\n")
    }
}
