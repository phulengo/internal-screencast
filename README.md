# Internal Screencast

Full screen mirroring from iPhone to LG TV — sub-150ms latency, no laptop required.

Built for internal use. No App Store restrictions. Optimized for low latency on LAN.

## How It Works

```
iPhone                                    LG TV (webOS)
┌─────────────────────┐                  ┌──────────────────┐
│ ReplayKit Capture    │                  │ Built-in Browser │
│        ↓             │                  │                  │
│ H.264 (VideoToolbox) │  ── WebRTC ──→  │ receiver.html    │
│        ↓             │     UDP          │ (auto-opened)    │
│ Signaling Server     │  ← WebSocket →  │                  │
│ HTTP Server          │  ── serves ──→  │                  │
│ LG SSAP Controller   │  ── opens ───→  │                  │
└─────────────────────┘                  └──────────────────┘
```

Everything runs on the iPhone. The TV just opens a browser page.

## Quick Start

1. Build and install the iOS app (see [ios/SETUP.md](ios/SETUP.md))
2. Make sure iPhone and LG TV are on the same WiFi (5GHz recommended)
3. Open the app — it auto-scans for your LG TV
4. Tap your TV, then tap **Cast**
5. Tap the broadcast button → select "Internal Screencast" → mirroring starts

The app automatically:
- Discovers your LG TV via SSDP
- Starts embedded signaling + HTTP servers
- Opens the receiver page on the TV's browser
- Streams your screen over WebRTC

## What's In The Box

| File | Purpose |
|------|---------|
| `ios/InternalScreencast/ContentView.swift` | Main UI — TV discovery, cast control, status |
| `ios/InternalScreencast/SSDPDiscovery.swift` | Finds LG TVs on the network via UPnP/SSDP |
| `ios/InternalScreencast/LGTVController.swift` | Controls LG TV via SSAP (open browser, toast) |
| `ios/InternalScreencast/EmbeddedSignalingServer.swift` | WebSocket relay for SDP/ICE (Network.framework) |
| `ios/InternalScreencast/EmbeddedHTTPServer.swift` | Serves receiver.html to the TV browser |
| `ios/BroadcastExtension/SampleHandler.swift` | ReplayKit → WebRTC H.264 pipeline |
| `receiver/index.html` | Fullscreen WebRTC receiver + stats overlay |
| `signaling/server.py` | Standalone Python signaling server (optional, for dev/debug) |

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

- **Fully self-contained**: No laptop or server needed. iPhone runs signaling + HTTP servers.
- **Auto-discovery**: SSDP finds LG TVs automatically. No manual IP entry.
- **LG SSAP integration**: Auto-opens the receiver in the TV's browser. One-tap experience.
- **ReplayKit → WebRTC direct pipeline**: No intermediate encoding step.
- **H.264 Baseline profile**: No B-frames, no frame reordering, minimum latency.
- **No STUN/TURN**: LAN-only, no ICE server lookups.
- **UDP transport**: Dropped packets skipped, not retransmitted.

## Requirements

- **iPhone**: iOS 15+, same WiFi as TV
- **TV**: LG webOS Smart TV (2018+)
- **Network**: 5GHz WiFi recommended
- **Build**: Xcode 15+, CocoaPods

## TV Stats Overlay

Press **S** on the TV browser to toggle a live stats overlay:
- Resolution and FPS
- Bitrate (Mbps)
- Jitter (ms)
- Packet loss percentage

Press **F** for fullscreen.

## Standalone Server (Optional)

For development/debugging, you can still run the Python signaling server separately:

```bash
chmod +x start.sh && ./start.sh
```

This starts the signaling server on `:8765` and serves the receiver on `:8080`.
