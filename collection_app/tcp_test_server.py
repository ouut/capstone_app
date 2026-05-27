#!/usr/bin/env python3
"""TCP test server for the collection_app skeletal data stream.

Protocol (per message):
  [4 bytes: big-endian uint32 payload_length]
  [payload: same binary format as UDP/WS]

Payload layout (little-endian, matching Swift withUnsafeBytes):
  Offset  Size  Type          Field
  0        8    float64       timestamp (Unix epoch)
  8        4    uint32        frame_index
  12      32    UTF-8 str     subject_id (null-padded to 32)
  44      32    UTF-8 str     session_note (null-padded to 32)
  76     N*28   float32[7]    joints: [x, y, z, qx, qy, qz, qw] per joint
  +0      28    float32[7]    camera:  [x, y, z, qx, qy, qz, qw]

ARKit skeleton: 91 joints → payload = 2652 bytes, framed = 2656 bytes
"""

import argparse
import socket
import struct
import time
import sys


def parse_payload(data: bytes):
    """Parse the binary joints payload and return a dict."""
    if len(data) < 76:
        return {"error": f"payload too short: {len(data)} bytes (min 76)"}

    offset = 0

    # Timestamp (float64 LE)
    ts = struct.unpack_from("<d", data, offset)[0]
    offset += 8

    # Frame index (uint32 LE)
    frame_idx = struct.unpack_from("<I", data, offset)[0]
    offset += 4

    # Subject ID (32 bytes UTF-8, null-padded)
    raw_subject = data[offset : offset + 32]
    subject_id = raw_subject.rstrip(b"\x00").decode("utf-8", errors="replace")
    offset += 32

    # Session note (32 bytes UTF-8, null-padded)
    raw_session = data[offset : offset + 32]
    session_note = raw_session.rstrip(b"\x00").decode("utf-8", errors="replace")
    offset += 32

    # Remaining bytes: joints * 28 + camera * 28
    remaining = len(data) - offset
    joint_count = (remaining - 28) // 28

    joints = []
    for i in range(joint_count):
        vals = struct.unpack_from("<7f", data, offset)
        offset += 28
        joints.append({
            "index": i,
            "x": round(vals[0], 4),
            "y": round(vals[1], 4),
            "z": round(vals[2], 4),
            "qx": round(vals[3], 4),
            "qy": round(vals[4], 4),
            "qz": round(vals[5], 4),
            "qw": round(vals[6], 4),
        })

    # Camera
    cam_vals = struct.unpack_from("<7f", data, offset)
    offset += 28
    camera = {
        "x": round(cam_vals[0], 4),
        "y": round(cam_vals[1], 4),
        "z": round(cam_vals[2], 4),
        "qx": round(cam_vals[3], 4),
        "qy": round(cam_vals[4], 4),
        "qz": round(cam_vals[5], 4),
        "qw": round(cam_vals[6], 4),
    }

    return {
        "timestamp": ts,
        "frame_index": frame_idx,
        "subject_id": subject_id,
        "session_note": session_note,
        "joint_count": joint_count,
        "joints": joints,
        "camera": camera,
    }


def serve(host: str, port: int, verbose: bool, save):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((host, port))
    server.listen(1)
    print(f"TCP server listening on {host}:{port}")
    print(f"  Connect from app: {host}:{port}")
    print()

    fh = None
    if save:
        fh = open(save, "ab")

    client = None
    addr = None
    try:
        while True:
            if client is None:
                client, addr = server.accept()
                print(f"[{time.strftime('%H:%M:%S')}] Connected: {addr[0]}:{addr[1]}")

            try:
                # Read 4-byte length prefix (big-endian uint32)
                header = b""
                while len(header) < 4:
                    chunk = client.recv(4 - len(header))
                    if not chunk:
                        raise ConnectionError("client disconnected")
                    header += chunk
                    if len(header) == 0:
                        raise ConnectionError("empty header")

                payload_len = struct.unpack(">I", header)[0]

                # Read payload
                payload = b""
                while len(payload) < payload_len:
                    chunk = client.recv(payload_len - len(payload))
                    if not chunk:
                        raise ConnectionError("client disconnected")
                    payload += chunk

                msg_count = getattr(serve, "count", 0) + 1
                serve.count = msg_count  # type: ignore[attr-defined]

                if fh:
                    fh.write(header + payload)

                parsed = parse_payload(payload)

                if verbose or msg_count % 60 == 0:
                    # Timestamp as ISO-ish
                    ts_iso = time.strftime("%H:%M:%S", time.localtime(parsed.get("timestamp", 0)))
                    print(
                        f"[{ts_iso}] frame={parsed.get('frame_index', '?')} "
                        f"joints={parsed.get('joint_count', '?')} "
                        f"subject={parsed.get('subject_id', '') or '-'} "
                        f"session={parsed.get('session_note', '') or '-'} "
                        f"payload={payload_len}B  "
                        f"(msg #{msg_count})"
                    )

                    if verbose:
                        cam = parsed.get("camera", {})
                        print(f"  camera: pos=({cam.get('x')}, {cam.get('y')}, {cam.get('z')})")
                        # Show first 3 joints
                        for j in parsed.get("joints", [])[:3]:
                            print(f"  joint[{j['index']}]: pos=({j['x']}, {j['y']}, {j['z']})")

            except (ConnectionError, ConnectionResetError, BrokenPipeError, TimeoutError):
                print(f"[{time.strftime('%H:%M:%S')}] Disconnected: {addr}")
                client.close()
                client = None
                addr = None
            except struct.error as e:
                print(f"[{time.strftime('%H:%M:%S')}] Parse error: {e}")
                client.close()
                client = None
                addr = None

    except KeyboardInterrupt:
        print("\nShutting down.")
    finally:
        if fh:
            fh.close()
            print(f"Saved raw frames to: {save}")
        if client:
            client.close()
        server.close()
        print("Done. Total frames:", getattr(serve, "count", 0))


serve.count = 0  # type: ignore[attr-defined]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="TCP test server for collection_app skeletal data"
    )
    parser.add_argument("--host", default="0.0.0.0", help="Bind address (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8080, help="Port (default: 8080)")
    parser.add_argument("-v", "--verbose", action="store_true", help="Print every frame (default: every 60th)")
    parser.add_argument("--save", help="Save raw framed data to file")
    args = parser.parse_args()

    serve(args.host, args.port, args.verbose, args.save)
