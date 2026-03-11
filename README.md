# Internal Screencast

Full screen mirroring from iPhone to any smart TV browser — sub-150ms latency on LAN.

Built for internal use. Bypasses App Store restrictions and optimizes aggressively for low latency.

## Architecture

```
iPhone (ReplayKit) → H.264/WebRTC/UDP → TV Browser (WebRTC)
                          ↕
                  Signaling Server (WebSocket)
                  (SDP + ICE relay only)
```

Three components:

| Component | Location | What it does |
|-----------|----------|-------------|
| **iOS App** | `ios/` | Captures screen via ReplayKit, encodes H.264 via VideoToolbox, streams over WebRTC |
| **Signaling Server** | `signaling/` | Python WebSocket relay — coordinates SDP offers/answers and ICE candidates |
| **TV Receiver** | `receiver/` | Single HTML file — receives WebRTC stream, renders fullscreen |

## Quick Start

```bash
chmod +x start.sh
./start.sh
```

This starts the signaling server on `:8765` and serves the receiver on `:8080`.

Then:
1. Open `http://<your-ip>:8080` on your TV browser
2. Open the iOS app, enter your computer's LAN IP
3. Tap the broadcast button to start mirroring

## Latency Budget

| Stage | Time |
|-------|------|
| ReplayKit capture | ~16ms |
| H.264 encode (VideoToolbox HW) | ~8ms |
| Network (5GHz LAN, UDP) | ~2ms |
| WebRTC jitter buffer | ~40ms |
| Decode + render | ~50ms |
| **Total** | **~116ms** |

## Key Design Decisions

- **ReplayKit → WebRTC direct pipeline**: No intermediate encoding step. ReplayKit's `CMSampleBuffer` feeds directly into WebRTC's VideoToolbox encoder.
- **H.264 Baseline profile**: No B-frames means no frame reordering, which eliminates a common source of latency.
- **No STUN/TURN**: LAN-only deployment means we skip ICE server lookups entirely.
- **UDP transport**: WebRTC uses SRTP over UDP — dropped packets are skipped, not retransmitted, preventing stalls.
- **4 Mbps bitrate**: Sufficient for 1080p screen content (text and UI compress efficiently in H.264).

## Requirements

- **iOS**: iPhone running iOS 15+, Xcode 15+, CocoaPods
- **Server**: Python 3.8+ with `websockets` package
- **Receiver**: Any modern browser with WebRTC support (Chrome, Safari, Edge, Firefox)
- **Network**: All devices on the same LAN (5GHz Wi-Fi recommended)

## iOS Setup

See [ios/SETUP.md](ios/SETUP.md) for detailed Xcode setup instructions.

## Stats Overlay

Press **S** on the TV browser to toggle a live stats overlay showing:
- Resolution and FPS
- Bitrate (Mbps)
- Jitter (ms)
- Packet loss percentage

Press **F** for fullscreen.
