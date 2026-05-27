#!/usr/bin/env python3
"""WebSocket receiver for collection_app — skeletal data + JPEG video frames."""

import asyncio
import struct
import sys
import os
import argparse
from datetime import datetime

try:
    import websockets
except ImportError:
    print("Install websockets: pip install websockets")
    sys.exit(1)


class FrameStats:
    def __init__(self):
        self.skeletal_count = 0
        self.video_count = 0
        self.last_skel_time: float = 0
        self.last_vid_time: float = 0
        self.start_time: float | None = None
        self.skel_size = 0
        self.vid_size = 0

    def print(self):
        now = datetime.now().strftime("%H:%M:%S")
        print(f"\n[{now}] {'─' * 40}")
        print(f"  Skeletal: {self.skeletal_count:6d} frames  "
              f"({self.skel_size} bytes total)")
        print(f"  Video:    {self.video_count:6d} frames  "
              f"({self.vid_size / 1024:.0f} KB total)")
        if self.start_time:
            elapsed = datetime.now().timestamp() - self.start_time
            if elapsed > 0:
                print(f"  Rates:    {self.skeletal_count / elapsed:.1f} skel/s  "
                      f"{self.video_count / elapsed:.1f} vid/s")


def parse_skeletal(data: bytes):
    """Parse the 2625-byte binary skeletal frame."""
    offset = 0

    # Timestamp (Float64 LE)
    timestamp = struct.unpack_from("<d", data, offset)[0]
    offset += 8

    # Frame index (UInt32 LE)
    frame_index = struct.unpack_from("<I", data, offset)[0]
    offset += 4

    # Subject ID (32 bytes UTF-8, zero-padded)
    subject_id = data[offset:offset + 32].rstrip(b"\x00").decode("utf-8") or "-"
    offset += 32

    # Session note (32 bytes UTF-8, zero-padded)
    session_note = data[offset:offset + 32].rstrip(b"\x00").decode("utf-8") or "-"
    offset += 32

    # Joints: each 28 bytes (3×Float32 pos + 4×Float32 rot)
    joint_count = (len(data) - offset - 28) // 28
    joints = []
    for _ in range(joint_count):
        vals = struct.unpack_from("<7f", data, offset)
        joints.append({
            "pos": vals[:3],
            "rot": vals[3:7],
        })
        offset += 28

    # Camera: same 28-byte format
    cam_vals = struct.unpack_from("<7f", data, offset)
    camera = {"pos": cam_vals[:3], "rot": cam_vals[3:7]}

    return {
        "timestamp": timestamp,
        "frame_index": frame_index,
        "subject_id": subject_id,
        "session_note": session_note,
        "joint_count": joint_count,
        "joints": joints,
        "camera": camera,
    }


async def handle_client(websocket, args, stats: FrameStats):
    """Handle one WebSocket client connection."""
    peer = websocket.remote_address
    print(f"  Client connected: {peer}")
    stats.start_time = datetime.now().timestamp()

    try:
        async for message in websocket:
            if not isinstance(message, bytes):
                continue

            msg_type = message[0]
            payload = message[1:]

            if msg_type == 0x01:
                stats.skeletal_count += 1
                stats.skel_size += len(message)
                stats.last_skel_time = datetime.now().timestamp()

                if args.verbose:
                    frame = parse_skeletal(payload)
                    print(f"  SKEL #{frame['frame_index']} | "
                          f"ts={frame['timestamp']:.3f} | "
                          f"subj={frame['subject_id']} | "
                          f"note={frame['session_note']} | "
                          f"joints={frame['joint_count']} | "
                          f"cam_pos=({frame['camera']['pos'][0]:.2f}, "
                          f"{frame['camera']['pos'][1]:.2f}, "
                          f"{frame['camera']['pos'][2]:.2f})")
                elif stats.skeletal_count % 60 == 0:
                    dt = datetime.now().strftime("%H:%M:%S")
                    print(f"  [{dt}] skeletal frame #{stats.skeletal_count} "
                          f"(index {parse_skeletal(payload)['frame_index']})")

            elif msg_type == 0x02:
                stats.video_count += 1
                stats.vid_size += len(message)
                stats.last_vid_time = datetime.now().timestamp()

                if args.save_frames:
                    os.makedirs("frames", exist_ok=True)
                    path = f"frames/frame_{stats.video_count:06d}.jpg"
                    with open(path, "wb") as f:
                        f.write(payload)

                if stats.video_count % 20 == 0:
                    dt = datetime.now().strftime("%H:%M:%S")
                    print(f"  [{dt}] video frame #{stats.video_count} "
                          f"({len(payload) / 1024:.1f} KB)")

    except websockets.exceptions.ConnectionClosed:
        print(f"  Client disconnected: {peer}")
    finally:
        stats.print()


async def main():
    parser = argparse.ArgumentParser(description="WebSocket receiver for collection_app")
    parser.add_argument("--host", default="0.0.0.0", help="Listen host (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8080, help="Listen port (default: 8080)")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Print every skeletal frame detail")
    parser.add_argument("--save-frames", action="store_true",
                        help="Save JPEG video frames to ./frames/")
    args = parser.parse_args()

    print(f"WebSocket server: ws://{args.host}:{args.port}")
    print(f"  skeletal frames: verbose={'on' if args.verbose else 'off (every 60)'}")
    print(f"  video frames:    save={'on' if args.save_frames else 'off'}")
    print("  Waiting for connection...")
    print("  (Press Ctrl+C to stop)\n")

    stats = FrameStats()

    async with websockets.serve(
        lambda ws: handle_client(ws, args, stats),
        args.host, args.port,
        max_size=10 * 1024 * 1024,  # 10 MB max message
    ):
        try:
            await asyncio.get_running_loop().create_future()  # run forever
        except KeyboardInterrupt:
            print("\nShutting down...")


if __name__ == "__main__":
    asyncio.run(main())
