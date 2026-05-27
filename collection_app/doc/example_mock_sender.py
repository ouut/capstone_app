#!/usr/bin/env python3
"""Example: Mock sender — replay CSV recordings as network data.

Feeds binary payloads (same as real network sends) to a callback,
useful for testing TCP/UDP/WebSocket servers without a physical device.

Usage:
  python3 example_mock_sender.py ./recordings/

Assumes directory contains files like:
  cc_walking1_2026-05-27-150633.csv
  king1_2026-05-27-150633.csv
"""

import sys
from arkit_parser import (
    mock_from_dir,
    parse_payload,
    build_payload,
    tcp_frame,
    ws_frame,
)


def handle_payload(payload: bytes, filename: str, frame_index: int):
    """Called for every frame — payload is raw 2652B, same as UDP.

    Decorate with tcp_frame() / ws_frame() to simulate other transports.
    """
    bf = parse_payload(payload)
    if bf is None:
        return

    # Print every 30th frame
    if frame_index % 30 == 0:
        root = bf.get("root")
        print(f"[{filename}] frame={bf.frame_index} "
              f"subject={bf.subject_id} root=({root.x:.2f}, {root.y:.2f}, {root.z:.2f})")

    # --- Simulate sending over actual transports ---

    # TCP: 4B length prefix + payload
    tcp_data = tcp_frame(payload)
    # await tcp_socket.send(tcp_data)

    # WebSocket: 1B type tag + payload
    ws_data = ws_frame(payload)
    # await websocket.send(ws_data)

    # UDP: raw payload (no framing)
    # udp_socket.sendto(payload, addr)


import argparse

if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Mock sender from CSV recordings")
    p.add_argument("dir", help="Directory containing CSV files")
    p.add_argument("--speed", type=float, default=0,
                   help="Replay speed: 0=max, 1=real-time")
    args = p.parse_args()

    # subject_id & session_note are auto-extracted from filenames like:
    #   {subject}_{session}_{timestamp}.csv
    mock_from_dir(args.dir, handle_payload, speed=args.speed)
    print("Done.")
