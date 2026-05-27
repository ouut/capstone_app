"""
ARKit Body Tracking — Python Parser Library.

Parses the binary skeletal data format from the collection_app iOS client.
Supports TCP (length-prefixed), WebSocket (type-tagged), and UDP (raw) transports.

Protocol overview:
  Each frame payload is 2652 bytes:
    8B  timestamp   float64 LE
    4B  frame_index uint32 LE
    32B subject_id  UTF-8, null-padded
    32B session_note UTF-8, null-padded
    2548B joints     91 × (float32×7) = pos(xyz) + quat(xyzw)
    28B  camera     float32×7

  TCP:    [4B big-endian length] + [payload]
  WebSocket: [1B type=0x01] + [payload]
  UDP:    [payload] (raw, possibly fragmented for video)
"""

import struct
from dataclasses import dataclass
from typing import List, Optional

# ——————————————————————————————————————————————————————————————————————————————
# Constants
# ——————————————————————————————————————————————————————————————————————————————

JOINT_COUNT = 91
JOINT_SIZE = 28        # 7 × float32
PAYLOAD_SIZE = 2652    # 8 + 4 + 32 + 32 + JOINT_COUNT*28 + 28

JOINT_NAMES = [
    "root",
    "hips_joint",
    "left_upLeg_joint", "left_leg_joint", "left_foot_joint",
    "left_toes_joint", "left_toesEnd_joint",
    "right_upLeg_joint", "right_leg_joint", "right_foot_joint",
    "right_toes_joint", "right_toesEnd_joint",
    "spine_1_joint", "spine_2_joint", "spine_3_joint", "spine_4_joint",
    "spine_5_joint", "spine_6_joint", "spine_7_joint",
    "left_shoulder_1_joint", "left_arm_joint", "left_forearm_joint", "left_hand_joint",
    "left_handIndexStart_joint", "left_handIndex_1_joint",
    "left_handIndex_2_joint", "left_handIndex_3_joint", "left_handIndexEnd_joint",
    "left_handMidStart_joint", "left_handMid_1_joint",
    "left_handMid_2_joint", "left_handMid_3_joint", "left_handMidEnd_joint",
    "left_handPinkyStart_joint", "left_handPinky_1_joint",
    "left_handPinky_2_joint", "left_handPinky_3_joint", "left_handPinkyEnd_joint",
    "left_handRingStart_joint", "left_handRing_1_joint",
    "left_handRing_2_joint", "left_handRing_3_joint", "left_handRingEnd_joint",
    "left_handThumbStart_joint", "left_handThumb_1_joint",
    "left_handThumb_2_joint", "left_handThumbEnd_joint",
    "neck_1_joint", "neck_2_joint", "neck_3_joint", "neck_4_joint",
    "head_joint", "jaw_joint", "chin_joint",
    "left_eye_joint", "left_eyeLowerLid_joint",
    "left_eyeUpperLid_joint", "left_eyeball_joint", "nose_joint",
    "right_eye_joint", "right_eyeLowerLid_joint",
    "right_eyeUpperLid_joint", "right_eyeball_joint",
    "right_shoulder_1_joint", "right_arm_joint", "right_forearm_joint", "right_hand_joint",
    "right_handIndexStart_joint", "right_handIndex_1_joint",
    "right_handIndex_2_joint", "right_handIndex_3_joint", "right_handIndexEnd_joint",
    "right_handMidStart_joint", "right_handMid_1_joint",
    "right_handMid_2_joint", "right_handMid_3_joint", "right_handMidEnd_joint",
    "right_handPinkyStart_joint", "right_handPinky_1_joint",
    "right_handPinky_2_joint", "right_handPinky_3_joint", "right_handPinkyEnd_joint",
    "right_handRingStart_joint", "right_handRing_1_joint",
    "right_handRing_2_joint", "right_handRing_3_joint", "right_handRingEnd_joint",
    "right_handThumbStart_joint", "right_handThumb_1_joint",
    "right_handThumb_2_joint", "right_handThumbEnd_joint",
]


# ——————————————————————————————————————————————————————————————————————————————
# Data classes
# ——————————————————————————————————————————————————————————————————————————————

@dataclass
class Joint:
    name: str
    index: int
    x: float
    y: float
    z: float
    qx: float
    qy: float
    qz: float
    qw: float

    @property
    def position(self) -> tuple:
        return (self.x, self.y, self.z)

    @property
    def rotation(self) -> tuple:
        return (self.qx, self.qy, self.qz, self.qw)


@dataclass
class Camera:
    x: float
    y: float
    z: float
    qx: float
    qy: float
    qz: float
    qw: float

    @property
    def position(self) -> tuple:
        return (self.x, self.y, self.z)


@dataclass
class BodyFrame:
    timestamp: float
    frame_index: int
    subject_id: str
    session_note: str
    joints: List[Joint]
    camera: Camera

    def get(self, name_or_index) -> Optional[Joint]:
        """Lookup joint by name (str) or index (int)."""
        if isinstance(name_or_index, str):
            for j in self.joints:
                if j.name == name_or_index:
                    return j
            return None
        return self.joints[name_or_index] if 0 <= name_or_index < len(self.joints) else None

    def __repr__(self):
        return (f"BodyFrame(#{self.frame_index}, ts={self.timestamp:.3f}, "
                f"subject={self.subject_id or '-'}, joints={len(self.joints)})")


# ——————————————————————————————————————————————————————————————————————————————
# Parser
# ——————————————————————————————————————————————————————————————————————————————

def parse_payload(data: bytes) -> Optional[BodyFrame]:
    """Parse a raw 2652-byte payload into a BodyFrame.

    Returns None if data is too short.
    """
    if len(data) < PAYLOAD_SIZE:
        return None

    offset = 0

    # Header
    ts = struct.unpack_from("<d", data, offset)[0]
    offset += 8
    frame_idx = struct.unpack_from("<I", data, offset)[0]
    offset += 4

    raw_subject = data[offset:offset + 32]
    subject_id = raw_subject.rstrip(b"\x00").decode("utf-8", errors="replace")
    offset += 32

    raw_session = data[offset:offset + 32]
    session_note = raw_session.rstrip(b"\x00").decode("utf-8", errors="replace")
    offset += 32

    # Joints
    joint_count = JOINT_COUNT
    joints = []
    for i in range(joint_count):
        vals = struct.unpack_from("<7f", data, offset)
        offset += JOINT_SIZE
        joints.append(Joint(
            name=JOINT_NAMES[i],
            index=i,
            x=vals[0], y=vals[1], z=vals[2],
            qx=vals[3], qy=vals[4], qz=vals[5], qw=vals[6],
        ))

    # Camera
    cam_vals = struct.unpack_from("<7f", data, offset)
    camera = Camera(
        x=cam_vals[0], y=cam_vals[1], z=cam_vals[2],
        qx=cam_vals[3], qy=cam_vals[4], qz=cam_vals[5], qw=cam_vals[6],
    )

    return BodyFrame(
        timestamp=ts,
        frame_index=frame_idx,
        subject_id=subject_id,
        session_note=session_note,
        joints=joints,
        camera=camera,
    )


# ——————————————————————————————————————————————————————————————————————————————
# Transport helpers (TCP length framing, WebSocket type stripping)
# ——————————————————————————————————————————————————————————————————————————————

def extract_tcp_frames(data: bytes) -> tuple:
    """Yield (payload, remainder) from a TCP stream buffer.

    TCP framing: 4B big-endian uint32 length + payload.

    Returns (parsed_frames, leftover_bytes).
    Only parses the payload — call parse_payload() on each yielded payload.
    """
    frames = []
    offset = 0
    while offset + 4 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        if offset + 4 + length > len(data):
            break  # incomplete frame
        payload = data[offset + 4:offset + 4 + length]
        frames.append(payload)
        offset += 4 + length
    return frames, data[offset:]


def extract_ws_frames(data: bytes) -> tuple:
    """Like extract_tcp_frames but for WebSocket binary messages.

    WebSocket framing is handled by the WebSocket library, so this just
    strips the 1-byte type tag (0x01 = skeletal).
    """
    frames = []
    offset = 0
    while offset + 1 <= len(data):
        msg_type = data[offset]
        if offset + 1 + PAYLOAD_SIZE > len(data):
            break
        payload = data[offset + 1:offset + 1 + PAYLOAD_SIZE]
        if msg_type == 0x01:  # skeletal
            frames.append(payload)
        offset += 1 + PAYLOAD_SIZE
    return frames, data[offset:]


# ——————————————————————————————————————————————————————————————————————————————
# Binary encoder (CSV → network payload)
# ——————————————————————————————————————————————————————————————————————————————

def build_payload(
    timestamp: float,
    frame_index: int,
    subject_id: str,
    session_note: str,
    joints: list,   # list of (x,y,z,qx,qy,qz,qw) tuples, len 91
    camera: tuple,  # (x,y,z,qx,qy,qz,qw)
) -> bytes:
    """Build a 2652-byte network payload from raw data."""
    data = bytearray(PAYLOAD_SIZE)
    offset = 0

    struct.pack_into("<d", data, offset, timestamp)
    offset += 8

    struct.pack_into("<I", data, offset, frame_index)
    offset += 4

    sb = subject_id.encode("utf-8")[:32]
    data[offset:offset + len(sb)] = sb
    offset += 32

    sn = session_note.encode("utf-8")[:32]
    data[offset:offset + len(sn)] = sn
    offset += 32

    for j in joints:
        struct.pack_into("<7f", data, offset, *j)
        offset += JOINT_SIZE

    struct.pack_into("<7f", data, offset, *camera)

    return bytes(data)


def tcp_frame(payload: bytes) -> bytes:
    """Wrap a payload with TCP 4-byte big-endian length prefix."""
    return struct.pack(">I", len(payload)) + payload


def ws_frame(payload: bytes) -> bytes:
    """Wrap a payload with WebSocket type tag 0x01."""
    return b"\x01" + payload


# ——————————————————————————————————————————————————————————————————————————————
# Mock sender — replays CSV recordings as network data
# ——————————————————————————————————————————————————————————————————————————————

import csv
import os
import time
from typing import Callable


def mock_from_csv(
    csv_path: str,
    callback: Callable[[bytes, str, int], None],
    subject_id: str = "",
    session_note: str = "",
    speed: float = 0,
):
    """Read a single CSV and call callback with binary payload for each frame.

    Args:
        csv_path: Path to a CSV recording.
        callback: Called as callback(payload, filename, frame_index) for each frame.
                  payload is 2652 bytes (same as UDP/WS payload, without framing).
        subject_id: Override subject ID extracted from filename.
        session_note: Override session note extracted from filename.
        speed: 0 = as fast as possible. 1.0 = real-time based on CSV timestamps.
    """
    basename = os.path.basename(csv_path)
    if not subject_id or not session_note:
        # Parse filename: {subject}_{session}_{timestamp}.csv
        stem = os.path.splitext(basename)[0]
        parts = stem.rsplit("_", 2)  # timestamp is last 2 parts
        if len(parts) >= 3 and not subject_id:
            subject_id = "_".join(parts[:-2])
        if len(parts) >= 3 and not session_note:
            session_note = parts[-2]

    # Read and group rows by frame_index
    frame_rows: dict[int, list[dict]] = {}
    frame_ts: dict[int, float] = {}
    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            fi = int(row["frame"])
            if fi not in frame_rows:
                frame_rows[fi] = []
                frame_ts[fi] = float(row["timestamp"])
            frame_rows[fi].append(row)

    indices = sorted(frame_rows.keys())
    prev_ts = None

    for fi in indices:
        rows = frame_rows[fi]
        ts = frame_ts[fi]

        # Separate joints from camera
        joints_rows = [r for r in rows if r["joint"] != "camera"]
        cam_rows = [r for r in rows if r["joint"] == "camera"]

        if len(joints_rows) != JOINT_COUNT:
            print(f"[mock] WARNING: {basename} frame {fi} has {len(joints_rows)} joints, expected {JOINT_COUNT}")
            continue

        joints = []
        for r in joints_rows:
            joints.append((
                float(r["pos_x"]), float(r["pos_y"]), float(r["pos_z"]),
                float(r["rot_x"]), float(r["rot_y"]), float(r["rot_z"]), float(r["rot_w"]),
            ))

        if cam_rows:
            c = cam_rows[0]
            camera = (
                float(c["pos_x"]), float(c["pos_y"]), float(c["pos_z"]),
                float(c["rot_x"]), float(c["rot_y"]), float(c["rot_z"]), float(c["rot_w"]),
            )
        else:
            camera = (0, 0, 0, 0, 0, 0, 1)

        payload = build_payload(ts, fi, subject_id, session_note, joints, camera)

        # Speed control
        if speed > 0 and prev_ts is not None:
            dt = (ts - prev_ts) / speed
            if dt > 0:
                time.sleep(dt)
        prev_ts = ts

        callback(payload, basename, fi)


def _extract_ts_from_filename(path: str) -> float:
    """Extract timestamp from filename pattern: {subject}_{session}_{YYYY-MM-DD-HHmmss}.csv"""
    stem = os.path.splitext(os.path.basename(path))[0]
    parts = stem.rsplit("_", 2)
    if len(parts) >= 3:
        try:
            return time.mktime(time.strptime(parts[-1], "%Y-%m-%d-%H%M%S"))
        except ValueError:
            pass
    return 0


def mock_from_dir(
    dir_path: str,
    callback: Callable[[bytes, str, int], None],
    **kwargs,
):
    """Read all CSV files in dir_path, calling callback per frame.

    Files are sorted by timestamp extracted from filename (oldest first).
    See mock_from_csv for kwargs.
    """
    csv_files = [
        os.path.join(dir_path, f)
        for f in os.listdir(dir_path)
        if f.endswith(".csv")
    ]
    csv_files.sort(key=_extract_ts_from_filename)
    for fp in csv_files:
        print(f"[mock] Processing: {os.path.basename(fp)}")
        mock_from_csv(fp, callback, **kwargs)
