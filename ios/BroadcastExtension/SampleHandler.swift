import ReplayKit
import WebRTC

class SampleHandler: RPBroadcastSampleHandler {

    // MARK: - Configuration

    private static let videoBitrate: Int = 4_000_000       // 4 Mbps
    private static let maxFPS: Int = 30
    private static let keyFrameInterval: Int = 60          // Every 2s at 30fps
    private static let appGroupID = "group.com.internal.screencast"

    // MARK: - WebRTC

    private var peerConnectionFactory: RTCPeerConnectionFactory!
    private var peerConnection: RTCPeerConnection?
    private var videoSource: RTCVideoSource!
    private var videoTrack: RTCVideoTrack!
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!

    private var hasConnectedPeer = false
    private let frameQueue = DispatchQueue(label: "com.internal.screencast.frames", qos: .userInteractive)

    // MARK: - Lifecycle

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        setupWebRTC()
        connectSignaling()
    }

    override func broadcastPaused() {
        // No-op: keep connection alive
    }

    override func broadcastResumed() {
        // No-op: frames will resume automatically
    }

    override func broadcastFinished() {
        disconnect()
    }

    // MARK: - Frame Processing

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, hasConnectedPeer else { return }

        frameQueue.async { [weak self] in
            guard let self = self else { return }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let timeStampNs = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let timeStampNsValue = Int64(CMTimeGetSeconds(timeStampNs) * 1_000_000_000)

            let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
            let videoFrame = RTCVideoFrame(
                buffer: rtcPixelBuffer,
                rotation: ._0,
                timeStampNs: timeStampNsValue
            )

            self.videoSource.capturer(RTCVideoCapturer(), didCapture: videoFrame)
        }
    }

    // MARK: - WebRTC Setup

    private func setupWebRTC() {
        RTCInitializeSSL()

        // Use hardware-accelerated H.264 via VideoToolbox
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()

        // Force H.264 Baseline profile — no B-frames, lowest latency
        let h264Codec = RTCVideoCodecInfo(
            name: kRTCVideoCodecH264Name,
            parameters: [
                "profile-level-id": "42e01f",  // Baseline 3.1
                "level-asymmetry-allowed": "1",
                "packetization-mode": "1"
            ]
        )

        encoderFactory.preferredCodec = h264Codec

        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )

        // Create video source and track
        videoSource = peerConnectionFactory.videoSource()
        videoTrack = peerConnectionFactory.videoTrack(with: videoSource, trackId: "screen0")
        videoTrack.isEnabled = true
    }

    private func createPeerConnection() {
        let config = RTCConfiguration()
        // LAN-only: no STUN/TURN needed
        config.iceServers = []
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        // Minimize buffering
        config.candidateNetworkPolicy = .all

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        peerConnection = peerConnectionFactory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )

        // Add video track
        peerConnection?.add(videoTrack, streamIds: ["screen"])

        // Configure encoding parameters for low latency
        if let sender = peerConnection?.senders.first(where: { $0.track?.kind == "video" }) {
            let params = sender.parameters
            if let encoding = params.encodings.first {
                encoding.maxBitrateBps = NSNumber(value: SampleHandler.videoBitrate)
            }

            // Disable bandwidth probing for faster start
            params.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainFramerate.rawValue)
            sender.parameters = params
        }
    }

    // MARK: - Signaling

    private func connectSignaling() {
        // Read the iPhone's own IP from App Group — the embedded signaling server
        // runs on the same device, so we connect to ourselves on port 8765.
        guard let serverIP = UserDefaults(suiteName: SampleHandler.appGroupID)?.string(forKey: "signalingServerIP"),
              !serverIP.isEmpty else {
            finishBroadcastWithError(NSError(
                domain: "InternalScreencast",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No server running. Open the app and tap Cast first."]
            ))
            return
        }

        // Connect to the embedded signaling server on this device
        let urlString = "ws://\(serverIP):8765"
        guard let url = URL(string: urlString) else {
            finishBroadcastWithError(NSError(
                domain: "InternalScreencast",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL: \(urlString)"]
            ))
            return
        }

        urlSession = URLSession(configuration: .default)
        webSocket = urlSession.webSocketTask(with: url)
        webSocket?.resume()

        // Register as sender
        sendSignalingMessage(["type": "register", "role": "sender"])

        // Listen for messages
        receiveSignalingMessage()
    }

    private func sendSignalingMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }

        webSocket?.send(.string(text)) { error in
            if let error = error {
                NSLog("InternalScreencast: WebSocket send error: \(error)")
            }
        }
    }

    private func receiveSignalingMessage() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleSignalingMessage(text)
                default:
                    break
                }
                // Continue listening
                self.receiveSignalingMessage()

            case .failure(let error):
                NSLog("InternalScreencast: WebSocket receive error: \(error)")
            }
        }
    }

    private func handleSignalingMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "receiver_ready":
            // A receiver connected — create offer
            createPeerConnection()
            createOffer()

        case "answer":
            guard let sdpString = json["sdp"] as? String else { return }
            let sdp = RTCSessionDescription(type: .answer, sdp: sdpString)
            peerConnection?.setRemoteDescription(sdp) { error in
                if let error = error {
                    NSLog("InternalScreencast: Set remote description error: \(error)")
                }
            }

        case "ice_candidate":
            guard let candidateDict = json["candidate"] as? [String: Any],
                  let sdp = candidateDict["candidate"] as? String,
                  let sdpMLineIndex = candidateDict["sdpMLineIndex"] as? Int32,
                  let sdpMid = candidateDict["sdpMid"] as? String else { return }

            let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
            peerConnection?.add(candidate)

        default:
            break
        }
    }

    private func createOffer() {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )

        peerConnection?.offer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp else {
                NSLog("InternalScreencast: Create offer error: \(error?.localizedDescription ?? "unknown")")
                return
            }

            // Modify SDP for low latency
            let modifiedSDP = self.applyLowLatencySDP(sdp.sdp)
            let lowLatencySDP = RTCSessionDescription(type: .offer, sdp: modifiedSDP)

            self.peerConnection?.setLocalDescription(lowLatencySDP) { error in
                if let error = error {
                    NSLog("InternalScreencast: Set local description error: \(error)")
                    return
                }

                self.sendSignalingMessage([
                    "type": "offer",
                    "sdp": modifiedSDP
                ])
            }
        }
    }

    /// Tweak SDP for minimal latency: set max bitrate, disable remb estimation ramp-up
    private func applyLowLatencySDP(_ sdp: String) -> String {
        let lines = sdp.components(separatedBy: "\r\n")
        var result: [String] = []

        for line in lines {
            result.append(line)

            // After the H.264 codec line, inject bitrate constraints
            if line.hasPrefix("a=rtpmap:") && line.contains("H264") {
                let payloadType = line.components(separatedBy: " ").first?
                    .replacingOccurrences(of: "a=rtpmap:", with: "") ?? ""
                result.append("a=fmtp:\(payloadType) max-mbps=108000;max-fs=3600")
            }
        }

        return result.joined(separator: "\r\n")
    }

    // MARK: - Cleanup

    private func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        peerConnection?.close()
        peerConnection = nil
        RTCCleanupSSL()
    }
}

// MARK: - RTCPeerConnectionDelegate

extension SampleHandler: RTCPeerConnectionDelegate {

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        NSLog("InternalScreencast: Signaling state changed")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        NSLog("InternalScreencast: ICE connection state: \(newState.rawValue)")
        switch newState {
        case .connected, .completed:
            hasConnectedPeer = true
        case .disconnected, .failed, .closed:
            hasConnectedPeer = false
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        NSLog("InternalScreencast: ICE gathering state: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        sendSignalingMessage([
            "type": "ice_candidate",
            "candidate": [
                "candidate": candidate.sdp,
                "sdpMLineIndex": candidate.sdpMLineIndex,
                "sdpMid": candidate.sdpMid ?? ""
            ]
        ])
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
