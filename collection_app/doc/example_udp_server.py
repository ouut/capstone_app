#!/usr/bin/env python3
"""Example: UDP server receiving ARKit skeletal data.

Usage:
  python3 example_udp_server.py --host 0.0.0.0 --port 8080
"""

import argparse
import socket
from arkit_parser import parse_payload


def main(host: str, port: int):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((host, port))
    print(f"Listening on {host}:{port}")

    count = 0
    try:
        while True:
            data, addr = sock.recvfrom(65536)
            bf = parse_payload(data)
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
        sock.close()


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="UDP server for ARKit body tracking")
    p.add_argument("--host", default="0.0.0.0")
    p.add_argument("--port", type=int, default=8080)
    args = p.parse_args()
    main(args.host, args.port)
