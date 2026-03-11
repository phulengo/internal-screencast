# iOS Setup Guide

## Prerequisites

- Xcode 15+
- CocoaPods (`sudo gem install cocoapods`)
- An Apple Developer account (free works for personal device)
- iPhone on the same LAN as the receiver

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
   - Copy `BroadcastExtension/SampleHandler.swift` → extension target
   - Copy `BroadcastExtension/Info.plist` → extension target

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

## Architecture Notes

### Why ReplayKit + WebRTC?

- **ReplayKit** provides system-level screen capture with zero overhead — it's the same pipeline iOS uses for native screen recording
- **WebRTC** gives us hardware-accelerated H.264 encoding via VideoToolbox and UDP transport
- The combination skips the HTTP/TCP re-encoding layers that App Store screen mirroring apps use

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
