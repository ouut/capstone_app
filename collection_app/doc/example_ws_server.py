#!/usr/bin/env python3
"""Example: WebSocket server receiving ARKit skeletal data.

Requires: pip install websockets

Usage:
  pip install websockets
  python3 example_ws_server.py --host 0.0.0.0 --port 8080
"""

import argparse
import asyncio
from arkit_parser import parse_payload

try:
    import websockets
except ImportError:
    print("pip install websockets")
    raise


async def handler(websocket):
    count = 0
    print(f"Connected: {websocket.remote_address}")
    try:
        async for message in websocket:
            if isinstance(message, bytes):
                # Message format: [0x01] + payload
                if len(message) < 2 or message[0] != 0x01:
                    continue
                bf = parse_payload(message[1:])
                if bf is None:
                    continue
                count += 1

                if count % 60 == 0:
                    root = bf.get("root")
                    print(f"[#{count}] frame={bf.frame_index} "
                          f"subject={bf.subject_id or '-'} "
                          f"root=({root.x:.2f}, {root.y:.2f}, {root.z:.2f})")
    except websockets.ConnectionClosed:
        pass
    finally:
        print(f"Disconnected. Received {count} frames.")


async def main(host: str, port: int):
    async with websockets.serve(handler, host, port):
        print(f"Listening on ws://{host}:{port}")
        await asyncio.Future()


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="WebSocket server for ARKit body tracking")
    p.add_argument("--host", default="0.0.0.0")
    p.add_argument("--port", type=int, default=8080)
    args = p.parse_args()
    asyncio.run(main(args.host, args.port))
