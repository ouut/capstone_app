# Capstone App - Questions to Clarify Before Finishing

## 1. Network Protocol Decision
WebRTC DataChannel vs UDP Socket — which one? If WebRTC, what signaling mechanism?

Answer: 
WebRTC DataChannel 
本地的电脑或 Ubuntu 盒子上用 Node.js 跑一个最简单的 WebSocket 信令服务器（监听 localhost:3000）。然后运行 tailscale funnel 3000 


## 2. Service Discovery
Manual IP/port only, or auto-discovery via Bonjour/mDNS? What happens on connection timeout or network drop?

Answer: 
Manual IP/port only

## 3. Model Hot-Load Approach
MLModelCollection + CloudKit, or manual .mlmodelc download from custom server? How should versioning, checksum validation, and rollback work? Minimum iOS version?

Answer: 
manual .mlmodelc download from custom server 
custom server like  https://ip:port/model_name
ip:port come from question 2 - the Manual IP/port input in UI



## 4. Action Mapping JSON Schema
What does the schema look like for `fighting.json` / `magic.json`? Required fields, threshold format, multi-gesture combos?
Answer: 
discuss later

## 5. Error & Edge Case Handling
What should happen when: multiple people in frame, model hot-load fails, network drops mid-session, confidence stays below threshold, device overheats?
Answer: 
VNDetectHumanBodyPoseRequest - support multiple people
VNDetectHumanBodyPose3DRequest - only one person
VNGeneratePersonInstanceMaskRequest - 4 people at most

need select the api in UI to steam the data

## 6. Security & Privacy
Encryption for skeletal data / video? User consent flow? Local data storage policy?
Answer: 
discuss later

## 7. UI Architecture / Screen Flow
What screens exist and how do they connect? Settings → Capture → ? Navigation hierarchy and state diagram needed?
Answer: 
2 tabs
1- capture video and show 骨骼关键点 on the video
2- setting to set config like ip, port, api, 意图识别模型url...
训练模式 － 发送骨骼数据到服务端，附带低质量视频，时间，游戏名称，动作标签等
游戏模式 － 实时将骨骼数据输入本地模型，发送预测结果

## 8. Testing & Validation Plan
Unit tests, integration tests, gesture accuracy validation? Benchmark targets beyond latency?
Answer: 
discuss later

## 9. Version Compatibility
How do app version, model version, and server protocol version stay compatible? Minimum deployment target?
Answer: 
尽量好的兼容性，也要保证app性能

## 10. Thermal & Battery Budget
Thermal throttling strategy? Battery impact targets? Graceful degradation when device is hot or low battery?
Answer: 
discuss later