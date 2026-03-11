#!/usr/bin/env python3
"""
Internal Screencast — Signaling Server

Lightweight WebSocket relay for WebRTC signaling.
Relays SDP offers/answers and ICE candidates between sender (iOS) and receiver (TV).
Zero media passes through this server.

Usage:
    python3 server.py [--host 0.0.0.0] [--port 8765]
"""

import argparse
import asyncio
import json
import logging
import signal
import sys
from typing import Optional

try:
    import websockets
except ImportError:
    print("Error: websockets package required. Install with: pip3 install websockets")
    sys.exit(1)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("signaling")


class SignalingServer:
    def __init__(self):
        self.sender: Optional[websockets.WebSocketServerProtocol] = None
        self.receiver: Optional[websockets.WebSocketServerProtocol] = None

    async def handler(self, ws: websockets.WebSocketServerProtocol):
        remote = ws.remote_address
        log.info(f"Connection from {remote[0]}:{remote[1]}")

        try:
            async for raw in ws:
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    log.warning(f"Invalid JSON from {remote[0]}")
                    continue

                msg_type = msg.get("type", "")
                await self.route(ws, msg, msg_type)

        except websockets.ConnectionClosed:
            log.info(f"Disconnected: {remote[0]}:{remote[1]}")
        finally:
            self.unregister(ws)

    async def route(self, ws, msg: dict, msg_type: str):
        if msg_type == "register":
            role = msg.get("role", "")
            if role == "sender":
                self.sender = ws
                log.info("Sender registered")
                # Notify sender if receiver is already waiting
                if self.receiver:
                    await self.sender.send(json.dumps({"type": "receiver_ready"}))
            elif role == "receiver":
                self.receiver = ws
                log.info("Receiver registered")
                # Notify sender that receiver is ready
                if self.sender:
                    await self.sender.send(json.dumps({"type": "receiver_ready"}))
            else:
                log.warning(f"Unknown role: {role}")

        elif msg_type == "offer":
            if self.receiver:
                log.info("Relaying offer → receiver")
                await self.receiver.send(json.dumps(msg))
            else:
                log.warning("Offer received but no receiver connected")

        elif msg_type == "answer":
            if self.sender:
                log.info("Relaying answer → sender")
                await self.sender.send(json.dumps(msg))
            else:
                log.warning("Answer received but no sender connected")

        elif msg_type == "ice_candidate":
            # Relay to the other peer
            if ws == self.sender and self.receiver:
                await self.receiver.send(json.dumps(msg))
            elif ws == self.receiver and self.sender:
                await self.sender.send(json.dumps(msg))

        else:
            log.debug(f"Unhandled message type: {msg_type}")

    def unregister(self, ws):
        if ws == self.sender:
            log.info("Sender disconnected")
            self.sender = None
        elif ws == self.receiver:
            log.info("Receiver disconnected")
            self.receiver = None


async def main(host: str, port: int):
    server = SignalingServer()

    stop = asyncio.get_event_loop().create_future()

    def handle_signal():
        stop.set_result(None)

    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, handle_signal)

    async with websockets.serve(server.handler, host, port):
        log.info(f"Signaling server running on ws://{host}:{port}")
        log.info("Waiting for sender and receiver to connect...")
        await stop

    log.info("Server shut down")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Internal Screencast Signaling Server")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8765, help="Port (default: 8765)")
    args = parser.parse_args()

    asyncio.run(main(args.host, args.port))
