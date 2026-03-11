# iOS Setup Guide

## Prerequisites

- Xcode 15+
- CocoaPods (`sudo gem install cocoapods`)
- An Apple Developer account (free works for personal device)
- iPhone and LG TV on the same WiFi network

## Step-by-Step Setup

### 1. Install Dependencies

```bash
cd ios/
pod install
```

Open `InternalScreencast.xcworkspace` (not `.xcodeproj`).

### 2. Create Xcode Project Structure

Since this repo provides source files only (no `.xcodeproj`), create the project in Xcode:

1. **File → New → Project → App**
   - Product Name: `InternalScreencast`
   - Bundle Identifier: `com.internal.screencast`
   - Interface: SwiftUI
   - Language: Swift

2. **Add Broadcast Upload Extension**
   - File → New → Target → Broadcast Upload Extension
   - Product Name: `BroadcastExtension`
   - Bundle Identifier: `com.internal.screencast.broadcast`
   - Language: Swift
   - **Uncheck** "Include UI Extension"

3. **Replace the generated source files** with the ones from this repo:
   - Copy `InternalScreencast/InternalScreencastApp.swift` → main app target
   - Copy `InternalScreencast/ContentView.swift` → main app target
   - Copy `InternalScreencast/SSDPDiscovery.swift` → main app target
   - Copy `InternalScreencast/EmbeddedSignalingServer.swift` → main app target
   - Copy `InternalScreencast/EmbeddedHTTPServer.swift` → main app target
   - Copy `InternalScreencast/LGTVController.swift` → main app target
   - Copy `InternalScreencast/Info.plist` → main app target
   - Copy `BroadcastExtension/SampleHandler.swift` → extension target
   - Copy `BroadcastExtension/Info.plist` → extension target

4. **Add receiver.html to bundle**
   - Drag `receiver/index.html` into the Xcode project (main app target)
   - Rename to `receiver.html` in the Copy Bundle Resources build phase
   - This is served to the TV by the embedded HTTP server

### 3. Configure App Groups

Both the main app and extension need to share data via App Groups:

1. Select the **InternalScreencast** target → Signing & Capabilities
2. Click **+ Capability → App Groups**
3. Add group: `group.com.internal.screencast`
4. Repeat for the **BroadcastExtension** target

### 4. Configure Signing

Since this is internal-only:

1. Select each target → Signing & Capabilities
2. Set Team to your Apple Developer account
3. For internal distribution, use **Ad Hoc** or **Enterprise** provisioning

### 5. Build & Run

1. Connect your iPhone via USB
2. Select your device as the build target
3. Build and run the **InternalScreencast** scheme
4. Trust the developer certificate on device: Settings → General → VPN & Device Management

## How It Works (No Laptop Required)

The app is now fully self-contained — no separate signaling server or computer needed:

1. **Open the app** → it auto-scans for LG TVs on your WiFi
2. **Tap your TV** → select it from the discovered list
3. **Tap "Cast"** → the app:
   - Starts an embedded WebSocket signaling server on port 8765
   - Starts an embedded HTTP server on port 8080 (serves the receiver page)
   - Connects to your LG TV via SSAP (WebSocket on port 3000)
   - Auto-opens the receiver URL in the TV's built-in browser
4. **Tap the broadcast button** → select "Internal Screencast" → mirroring starts

## Architecture Notes

### Why Embedded Servers?

Previous versions required a separate computer running Python scripts. Now everything
runs on the iPhone:

- **EmbeddedSignalingServer** — WebSocket server using Network.framework, relays SDP/ICE between the broadcast extension (sender) and TV browser (receiver)
- **EmbeddedHTTPServer** — serves `receiver.html` to the TV browser
- **SSDPDiscovery** — finds LG TVs via UPnP multicast
- **LGTVController** — controls the TV via LG's SSAP protocol (open browser, show toast)

### Why ReplayKit + WebRTC?

- **ReplayKit** provides system-level screen capture with zero overhead
- **WebRTC** gives us hardware-accelerated H.264 encoding via VideoToolbox and UDP transport
- The combination skips the HTTP/TCP re-encoding layers that App Store apps use

### Broadcast Extension Memory Limit

iOS enforces a **50MB memory limit** on Broadcast Upload Extensions. The current implementation stays well within this because:
- WebRTC's encoder uses VideoToolbox (hardware), not software encoding
- We don't buffer frames — each is sent immediately
- No UI or view hierarchy in the extension

### H.264 Profile Choice

We use **Baseline Profile Level 3.1** (`42e01f`):
- No B-frames → no frame reordering → lower latency
- Widely supported on all WebRTC receivers
- 4 Mbps is sufficient for 1080p screen content (text/UI compresses well)

### LG TV Pairing

The first time you cast, the LG TV will show a pairing prompt. Accept it once and it's remembered. For development TVs in developer mode, this may auto-accept.
