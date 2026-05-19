# game_client_app

iOS ARKit body tracking app that streams real-time skeleton predictions to a UDP server, with optional CoreML inference.

## Overview

The app uses ARKit's body tracking to capture 93-joint skeleton data from the camera feed, feeds it through a CoreML model (or a built-in mock predictor), then sends the prediction output as JSON over UDP.

```
iPhone Camera (60 fps)
      │
      ▼
ARKit Body Tracking ── 93 joint positions
      │
      ▼ (every 6th frame, ~10 fps)
CoreML Inference ── or ── Mock Predictor
      │
      ▼
JSON ──UDP──▶ game_server_app (:8888)
```

## Requirements

- iPhone or iPad with A12 chip or later (required by `ARBodyTrackingConfiguration`)
- iOS 13.0+
- Xcode 16+ (for build)
- [game_server_app](../game_server_app) — Node.js UDP receiver

## Quick Start

### 1. Start the server

```bash
cd ../game_server_app
node server.js
```

### 2. Build & install the app

```bash
# Simulator (no signing required)
./build.sh --simulator

# Physical device (auto-detects connected iPhone)
./install.sh
```

## Features

### Body Tracking
ARKit detects a person in the camera frame and produces `ARBodyAnchor` with 93 skeleton joints in 3D world space. A USDZ robot character mirrors the detected person's pose in real time.

### CoreML Inference
- Download a `.mlmodel` from any URL via the in-app settings
- The model is automatically compiled and loaded
- Skeleton joint positions are flattened into an `MLMultiArray` and passed to the model
- Prediction output is serialized to JSON and sent over UDP

### Mock Mode
When no CoreML model is loaded, the app runs in **mock mode** by default. It computes 10 derived body metrics from the skeleton data:

| Index | Field | Description |
|-------|-------|-------------|
| 0–2 | centroid | Body center of mass (x, y, z) in meters |
| 3 | height | Vertical span from lowest to highest joint |
| 4 | spread | Horizontal width from leftmost to rightmost joint |
| 5–6 | x range | Min/max x positions |
| 7–8 | y range | Min/max y positions |
| 9 | joints | Joint count (always 93) |

This lets you test the full UDP pipeline end-to-end without a model file.

### Settings UI
Tap the gear icon (top-right) to configure:

| Setting | Default | Validation |
|---------|---------|------------|
| UDP IP | `100.99.98.5` | IPv4 address check |
| UDP Port | `8888` | 1–65535 |
| Model URL | (empty) | `http://` or `https://` only |

Settings persist across launches via `UserDefaults`. Input fields show green/red borders for live validation, and invalid values trigger a shake animation on save.

### Send Feedback
A status capsule in the top-left corner shows:
- Connection status dot (green = connected, red = disconnected)
- Packet counter with paper plane icon
- Brief yellow flash animation on each successful UDP send

## Project Structure

```
game_client_app/
├── game_client_app.xcodeproj/
├── game_client_app/
│   ├── AppDelegate.swift              # Application entry point
│   ├── ViewController.swift           # ARKit session, inference, UDP orchestration
│   ├── SettingsViewController.swift   # UDP + model configuration UI
│   ├── MLModelManager.swift           # CoreML download, compile, load, predict
│   ├── UDPClient.swift                # UDP socket via Network.framework
│   ├── character/robot.usdz           # 3D body-tracked character model
│   ├── Info.plist                     # App manifest + network permissions
│   └── Assets.xcassets/               # App icons
├── build.sh                           # CLI build script
└── install.sh                         # CLI build + device install
```

## UDP Protocol

### Prediction JSON Format

```json
{
  "prediction": [0.12, 0.25, 0.33, 1.75, 0.52, -0.41, 0.55, 0.01, 1.82, 93]
}
```

The array length depends on the CoreML model output. For mock mode it is always 10 elements. Real model output dimensions vary by model.

### Server Receipt

The `game_server_app` receiver parses and prints each packet:

```
📦 Packet #42  │  from 192.168.1.100:54321  │  +0.2s
  🧍 Body Metrics:
  centroid         (0.120, 0.250, 0.330)
  body height      1.750 m
  spread (width)   0.520 m
  x range          [-0.410, 0.550]
  y range          [0.010, 1.820]
  joint count      93
```

## Building from CLI

The project is configured for command-line builds — no Xcode GUI required.

```bash
# Simulator build
./build.sh --simulator

# Device build (archives and exports .ipa)
./build.sh

# Device build + install
./install.sh
```

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `DEVELOPMENT_TEAM` | `ZWG49Y3378` | Apple Developer Team ID |
| `DEVELOPER_DIR` | Xcode default | Path to Xcode |

## Permissions

The app requires two privacy permissions (configured in `Info.plist`):

- **Camera** (`NSCameraUsageDescription`) — for ARKit body tracking
- **Local Network** (`NSLocalNetworkUsageDescription`) — for UDP streaming

## License

See [LICENSE.txt](LICENSE.txt). Based on Apple sample code "Capturing Body Motion in 3D."
