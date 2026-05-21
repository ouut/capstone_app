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

Two CSV variants are produced depending on the data source.

#### 1. Live ARKit recording (`exportCSV`)

Produced when tapping record during a live ARKit session.

```
timestamp,frame,joint,pos_x,pos_y,pos_z,rot_x,rot_y,rot_z,rot_w
```

| Column | Type | Description |
|---|---|---|
| `timestamp` | float (4 dp) | Seconds elapsed since recording started |
| `frame` | int | Zero-based frame index |
| `joint` | string | ARKit skeleton joint name (e.g. `root`, `left_hand_joint`, `right_foot_joint`) — see [ARSkeleton.JointName](https://developer.apple.com/documentation/arkit/arskeleton/jointname) for the full list of ~90 joints |
| `pos_x`, `pos_y`, `pos_z` | float | World-space **position** (meters). Translation extracted from column 3 of the joint's 4×4 transform matrix |
| `rot_x`, `rot_y`, `rot_z`, `rot_w` | float | World-space **rotation** as a quaternion. `rot_w` is the scalar (real) part; `rot_x/rot_y/rot_z` are the vector (imaginary) part |

The hierarchy is **flattened**: each row is one joint. A single frame produces ~90 rows (one per skeleton joint), all sharing the same `timestamp` and `frame` values.

#### 2. Video-extracted pose (`generateCSV` / `processVideo`)

Produced by running Vision body-pose detection over a pre-recorded video file.

```
timestamp,frame,joint,pos_x,pos_y,pos_z
```

| Column | Type | Description |
|---|---|---|
| `timestamp` | float (4 dp) | Video presentation timestamp in seconds |
| `frame` | int | Zero-based frame index |
| `joint` | string | Vision human body pose joint name (e.g. `right_wrist`, `left_elbow`) — see [VNHumanBodyPoseObservation.JointName](https://developer.apple.com/documentation/vision/vnhumanbodyposeobservation/jointname) |
| `pos_x`, `pos_y`, `pos_z` | float | 2D **image-space** position (pixels). `pos_z` is always 0 — Vision provides only (x, y) screen coordinates |

No rotation data is available from video extraction because Vision's 2D pose detector does not produce 3D orientation. Only joints with confidence > 0.3 are included, so the number of joints per frame varies.

### Why CSV instead of JSON?

CSV is the default because it is compact and works directly with ML/analysis tools (pandas, NumPy, Excel). However, CSV **flattens** the frame → joints hierarchy: the timestamp and frame index are repeated on every row, which is redundant.

JSON would naturally model the hierarchy:

```json
{
  "frames": [
    {
      "timestamp": 0.0000,
      "index": 0,
      "joints": [
        { "name": "root", "pos": [0, 0, 0], "rot": [0, 0, 0, 1] },
        { "name": "left_hand_joint", "pos": [0.1, 0.5, -0.2], "rot": [0, 0, 0, 1] }
      ]
    }
  ]
}
```

**Trade-offs:**

| | CSV | JSON |
|---|---|---|
| File size | Smaller (no repeated key names) | Larger (~2–3× for the same data) |
| Hierarchy | Flat — must group by `frame` column | Natural — `frames[].joints[]` |
| ML / pandas | `pd.read_csv()` works directly | Needs `json_normalize` or custom parsing |
| Web / JS | Needs CSV parser | `JSON.parse()` natively |
| Metadata | None (just column headers) | Can embed recording config, skeleton definition, etc. |

If JSON export would be useful for your pipeline, it's a straightforward addition — the `JointFrame` struct already holds the hierarchy, so serializing it with `Codable` is minimal work.

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
