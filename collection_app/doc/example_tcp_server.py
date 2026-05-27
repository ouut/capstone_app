#!/usr/bin/env python3
"""Example: TCP server receiving ARKit skeletal data.

Usage:
  python3 example_tcp_server.py --host 0.0.0.0 --port 8080
"""

import argparse
import socket
from arkit_parser import parse_payload, extract_tcp_frames


def main(host: str, port: int):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((host, port))
    server.listen(1)
    print(f"Listening on {host}:{port}")

    buf = b""
    client = None
    count = 0

    try:
        while True:
            if client is None:
                client, addr = server.accept()
                print(f"Connected: {addr}")

            chunk = client.recv(8192)
            if not chunk:
                print("Disconnected")
                client = None
                buf = b""
                continue

            buf += chunk
            frames, buf = extract_tcp_frames(buf)

            for payload in frames:
                bf = parse_payload(payload)
                if bf is None:
                    continue
                count += 1

                if count % 60 == 0:
                    root = bf.get("root")
                    print(f"[#{count}] frame={bf.frame_index} "
                          f"subject={bf.subject_id or '-'} "
                          f"root=({root.x:.2f}, {root.y:.2f}, {root.z:.2f})")

    except KeyboardInterrupt:
        print(f"\nDone. Received {count} frames.")
    finally:
        server.close()


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="TCP server for ARKit body tracking")
    p.add_argument("--host", default="0.0.0.0")
    p.add_argument("--port", type=int, default=8080)
    args = p.parse_args()
    main(args.host, args.port)
