# collection_app

iOS body motion capture app — tracks a person using ARKit and drives a 3D robot character in real time. Record skeletal animation data as CSV, optionally with video, and stream over UDP.

## Features

- **Real-time body tracking** via ARKit `ARBodyTrackingConfiguration` (requires A12+ chip)
- **3D character** — a robot driven by your body movements
- **CSV recording** — captures joint positions, rotations, and camera pose per frame
- **Optional video recording** — saves camera feed alongside skeleton data
- **UDP streaming** — binary body tracking data to a local server for real-time visualization
- **Camera pose tracking** — device position and orientation recorded per frame
- **File browser** — browse, share, and delete recordings from Settings via iOS Files picker

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

### Recording Config

| Option | Description |
|---|---|
| Data ID | Custom name appended to timestamp in filename (default: empty, uses timestamp only) |
| Save video | Toggle to record `.mp4` alongside CSV (default: off) |

### UDP Streaming

| Option | Description |
|---|---|
| IP / Hostname | Target server address (e.g. `192.168.1.100` or `myserver.local`) |
| Port | UDP port number (1024–65535) |
| Send via UDP | Toggle to enable streaming during recording (default: off) |

When enabled, each frame is sent as a **binary UDP packet** (2561 bytes) to the configured host:port. See [UDP Protocol](#udp-protocol) below.

### Recorded Files

**Browse Recordings…** — opens the iOS Files picker filtered to CSV and MP4. Select a file to share (AirDrop, save to Files, etc.) or delete.

## Output Files

All files are saved to `Documents/BodyMotionRecordings/` and accessible via:

- **Settings → Browse Recordings** — system file picker with share & delete
- **iPhone Files app** → Browse → On My iPhone → collection_app
- **Finder / iTunes** → File Sharing → collection_app

### File Naming

```
{timestamp}.csv                     — empty Data ID
{timestamp}_{name}.csv              — custom Data ID
{timestamp}.mp4                     — video (same naming)
```

Example: `2026-05-22-143001_mysession.csv`

### CSV Format

```
timestamp,frame,joint,pos_x,pos_y,pos_z,rot_x,rot_y,rot_z,rot_w
```

| Column | Type | Description |
|---|---|---|
| `timestamp` | float (4 dp) | Seconds elapsed since recording started |
| `frame` | int | Zero-based frame index |
| `joint` | string | ARKit skeleton joint name (e.g. `root`, `left_hand_joint`) — see [ARSkeleton.JointName](https://developer.apple.com/documentation/arkit/arskeleton/jointname) for the full list of ~90 joints. Special value `camera` for the device pose |
| `pos_x`, `pos_y`, `pos_z` | float | World-space **position** (meters). Translation from column 3 of the 4×4 transform matrix |
| `rot_x`, `rot_y`, `rot_z`, `rot_w` | float | World-space **rotation** as a quaternion. `rot_w` is the scalar (real) part |

The hierarchy is **flattened**: each row is one joint. A single frame produces ~91 rows (~90 joints + 1 camera), all sharing the same `timestamp` and `frame` values.

**Camera row** — `joint=camera` contains the device's ARKit camera transform, useful for reconstructing the world coordinate frame or computing relative positions.

## UDP Protocol

Each frame is a fixed-size binary packet sent over UDP to the configured host:port.

### Frame Layout (2561 bytes total)

```
Offset  Size  Type      Field
──────  ────  ────────  ────────────
0       1     UInt8     type = 1
1       8     Float64   timestamp (seconds)
9       4     UInt32    frameIndex
13      2520  Float32[] joints[90] — 7 floats each (pos_x, pos_y, pos_z, rot_x, rot_y, rot_z, rot_w)
2533    28    Float32[] camera       — 7 floats (same layout)
──────  ────
Total:  2561 bytes
```

All multi-byte values are **little-endian**. IP fragmentation splits this into 2 packets; the kernel reassembles automatically.

### Joint Order

The 90 joints follow `ARSkeletonDefinition.jointNames` order and are always consistent. The mapping (e.g. `joint[0] = root`, `joint[1] = hips_joint`) can be obtained from any ARKit skeleton definition.

### Python Receiver Example

```python
import socket, struct

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", 9999))

JOINT_COUNT = 90

while True:
    data, addr = sock.recvfrom(4096)
    type_byte = data[0]
    ts, idx = struct.unpack('<dI', data[1:13])

    joints = []
    for i in range(JOINT_COUNT):
        offset = 13 + i * 28
        vals = struct.unpack('<7f', data[offset:offset+28])
        joints.append(vals)

    cam = struct.unpack('<7f', data[-28:])
    print(f"frame {idx}  ts={ts:.4f}  joints={len(joints)}  cam_pos=({cam[0]:.2f},{cam[1]:.2f},{cam[2]:.2f})")
```

## Project Structure

```
collection_app/
├── AppDelegate.swift              # UIKit app entry point
├── ViewController.swift           # ARKit session, body tracking, UI overlay
├── Recording/
│   ├── RecordingManager.swift     # Skeleton buffering, CSV export, video recording, UDP config
│   └── UDPSender.swift            # NWConnection UDP sender, binary frame builder
├── Settings/
│   └── SettingsViewController.swift  # Settings UI, UDP config, file browser
├── character/
│   └── robot.usdz                 # 3D robot model (BodyTrackedEntity)
├── Assets.xcassets/               # App icons
├── Base.lproj/                    # Storyboard, launch screen
├── Info.plist                     # App configuration
└── project.yml                    # XcodeGen project spec
```

## Build System

The Xcode project is generated from `project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen). The `install.sh` script handles generation, compilation, and device installation — no need to open Xcode.

## License

Based on Apple's [Capturing Body Motion in 3D](https://developer.apple.com/documentation/arkit/capturing_body_motion_in_3d) sample code. See `LICENSE.txt`.
