# collection_app

iOS body motion capture app — tracks a person using ARKit and drives a 3D robot character in real time. Record skeletal animation data as CSV, optionally with video.

## Features

- **Real-time body tracking** via ARKit `ARBodyTrackingConfiguration` (requires A12+ chip)
- **3D character** — a robot driven by your body movements
- **CSV recording** — captures joint positions & rotations per frame
- **Optional video recording** — saves camera feed alongside skeleton data
- **Video-to-CSV extraction** — load any recorded video to extract body pose as CSV via Vision

## Requirements

| | |
|---|---|
| iOS | 15.0+ |
| Xcode | 15.0+ |
| Device | iPhone with A12 chip or newer |
| Camera | Front-facing TrueDepth or RGB |

## Quick Start

```bash
cd collection_app

# Build for device
./build.sh

# Build + install to connected iPhone
./install.sh

# Build for iOS Simulator (compilation check only — body tracking needs real device)
./build.sh --simulator
```

## Usage

1. **Point the front camera at a person** — the robot appears and mirrors their movements
2. **Tap the record button** (bottom center) to start recording skeletal data
3. **Tap again** to stop — CSV (and video if enabled) auto-saves
4. **Tap the gear button** (top right) to open settings

## Settings

| Option | Description |
|---|---|
| Data ID | Custom name for recordings (default: current timestamp) |
| Save video | Toggle to record `.mp4` alongside CSV (default: off) |
| Select Video | Load a video file to extract body pose as CSV |

## Output Files

All files are saved to `Documents/BodyMotionRecordings/` and accessible via:

- **iPhone Files app** → Browse → On My iPhone → collection_app
- **Finder / iTunes** → File Sharing → collection_app

### CSV Format

```csv
timestamp,frame,joint,pos_x,pos_y,pos_z,rot_x,rot_y,rot_z,rot_w
0.0000,0,root,0.000,0.000,0.000,0.000,0.000,0.000,1.000
0.0333,1,root,0.001,-0.002,0.001,0.000,0.000,0.000,1.000
...
```

Each row contains a joint's world-space position and rotation quaternion at a given frame.

## Project Structure

```
collection_app/
├── AppDelegate.swift              # UIKit app entry point
├── ViewController.swift           # ARKit session, body tracking, UI overlay
├── Recording/
│   └── RecordingManager.swift     # Skeleton buffering, CSV export, video recording
├── Settings/
│   └── SettingsViewController.swift  # Settings UI
├── character/
│   └── robot.usdz                 # 3D robot model (BodyTrackedEntity)
├── Assets.xcassets/               # App icons
├── Base.lproj/                    # Storyboard, launch screen
└── Info.plist                     # App configuration
```

## Build System

The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen). The `build.sh` script handles generation and compilation — no need to open Xcode.

## License

Based on Apple's [Capturing Body Motion in 3D](https://developer.apple.com/documentation/arkit/capturing_body_motion_in_3d) sample code. See `LICENSE.txt`.
