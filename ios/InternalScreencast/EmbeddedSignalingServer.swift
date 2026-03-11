import Foundation
import Network

/// Lightweight WebSocket signaling server embedded in the iOS app.
/// Relays SDP offers/answers and ICE candidates between the broadcast
/// extension (sender) and the TV browser (receiver). Runs on port 8765.
class EmbeddedSignalingServer: ObservableObject {
    @Published var isRunning = false
    @Published var connectedClients = 0

    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:] // role -> connection
    private let queue = DispatchQueue(label: "signaling-server", qos: .userInteractive)
    private let port: UInt16

    // Track partial WebSocket frames
    private var pendingBuffers: [ObjectIdentifier: Data] = [:]

    init(port: UInt16 = 8765) {
        self.port = port
    }

    func start() {
        guard !isRunning else { return }

        let params = NWParameters(tls: nil)
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        params.requiredInterfaceType = .wifi
        params.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("[Signaling] Failed to create listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async { self?.isRunning = true }
                print("[Signaling] Server listening on port \(self?.port ?? 0)")
            case .failed(let error):
                print("[Signaling] Server failed: \(error)")
                DispatchQueue.main.async { self?.isRunning = false }
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        DispatchQueue.main.async {
            self.isRunning = false
            self.connectedClients = 0
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[Signaling] Client connected")
                self?.receiveMessage(on: connection)
                DispatchQueue.main.async {
                    self?.connectedClients = self?.connections.count ?? 0
                }
            case .failed, .cancelled:
                self?.removeConnection(connection)
                DispatchQueue.main.async {
                    self?.connectedClients = self?.connections.count ?? 0
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("[Signaling] Receive error: \(error)")
                self.removeConnection(connection)
                return
            }

            if let data = content, let text = String(data: data, encoding: .utf8) {
                self.handleMessage(text, from: connection)
            }

            // Continue receiving
            self.receiveMessage(on: connection)
        }
    }

    private func handleMessage(_ text: String, from connection: NWConnection) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "register":
            if let role = json["role"] as? String {
                connections[role] = connection
                print("[Signaling] Registered: \(role)")
                DispatchQueue.main.async {
                    self.connectedClients = self.connections.count
                }
            }

        case "offer":
            // Forward offer from sender to receiver
            if let receiver = connections["receiver"] {
                sendJSON(text, on: receiver)
            }

        case "answer":
            // Forward answer from receiver to sender
            if let sender = connections["sender"] {
                sendJSON(text, on: sender)
            }

        case "ice_candidate":
            // Forward ICE candidates to the other peer
            let isSender = connections["sender"] === connection
            let target = isSender ? connections["receiver"] : connections["sender"]
            if let target = target {
                sendJSON(text, on: target)
            }

        default:
            break
        }
    }

    private func sendJSON(_ text: String, on connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(
            identifier: "signaling",
            metadata: [metadata]
        )
        connection.send(
            content: text.data(using: .utf8),
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error = error {
                    print("[Signaling] Send error: \(error)")
                }
            }
        )
    }

    private func removeConnection(_ connection: NWConnection) {
        connections = connections.filter { $0.value !== connection }
        connection.cancel()
    }

    /// Returns the device's WiFi IP address
    static func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" { // WiFi interface
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}
