import Foundation

/// Manages connection to an LG webOS TV via SSAP (Second Screen Application Protocol).
/// Used to auto-launch the receiver URL in the TV's built-in browser.
class LGTVController: ObservableObject {
    @Published var isConnected = false
    @Published var isPaired = false
    @Published var statusMessage = ""

    private var webSocket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var commandId = 0

    /// Connect to the LG TV's SSAP WebSocket endpoint
    func connect(to address: String, port: Int = 3000) {
        let urlString = "ws://\(address):\(port)"
        guard let url = URL(string: urlString) else {
            statusMessage = "Invalid TV address"
            return
        }

        statusMessage = "Connecting to TV..."
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()

        // Send pairing/registration request
        // For internal/development TVs, this typically auto-accepts
        sendRegistration()
        receiveMessages()
    }

    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        isConnected = false
        isPaired = false
        statusMessage = ""
    }

    /// Launch a URL in the TV's built-in browser
    func launchBrowser(url: String) {
        let payload: [String: Any] = [
            "id": nextCommandId(),
            "type": "request",
            "uri": "ssap://system.launcher/open",
            "payload": [
                "target": url
            ]
        ]
        sendJSON(payload)
        statusMessage = "Opening receiver on TV..."
    }

    /// Show a toast notification on the TV
    func showToast(message: String) {
        let payload: [String: Any] = [
            "id": nextCommandId(),
            "type": "request",
            "uri": "ssap://system.notifications/createToast",
            "payload": [
                "message": message
            ]
        ]
        sendJSON(payload)
    }

    // MARK: - Private

    private func sendRegistration() {
        let payload: [String: Any] = [
            "id": nextCommandId(),
            "type": "register",
            "payload": [
                "pairingType": "PROMPT",
                "manifest": [
                    "manifestVersion": 1,
                    "appVersion": "1.0",
                    "signed": [
                        "created": "20240101",
                        "appId": "com.internal.screencast",
                        "vendorId": "com.internal",
                        "localizedAppNames": [
                            "": "Internal Screencast"
                        ],
                        "localizedVendorNames": [
                            "": "Internal"
                        ],
                        "permissions": [
                            "LAUNCH",
                            "LAUNCH_WEBAPP",
                            "CONTROL_DISPLAY",
                            "CONTROL_INPUT_TEXT"
                        ],
                        "serial": "internal001"
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ]
        sendJSON(payload)
    }

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self?.receiveMessages()

            case .failure(let error):
                print("[LGTV] WebSocket error: \(error)")
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.statusMessage = "Disconnected from TV"
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "registered":
            DispatchQueue.main.async {
                self.isConnected = true
                self.isPaired = true
                self.statusMessage = "Connected to TV"
            }
            print("[LGTV] Paired successfully")

        case "response":
            let returnValue = json["payload"] as? [String: Any]
            let returnVal = returnValue?["returnValue"] as? Bool ?? false
            if returnVal {
                print("[LGTV] Command succeeded")
            } else {
                let errorText = returnValue?["errorText"] as? String ?? "Unknown error"
                print("[LGTV] Command failed: \(errorText)")
                DispatchQueue.main.async {
                    self.statusMessage = "Error: \(errorText)"
                }
            }

        case "error":
            let errorText = json["error"] as? String ?? "Unknown error"
            print("[LGTV] Error: \(errorText)")
            DispatchQueue.main.async {
                self.statusMessage = "Error: \(errorText)"
            }

        default:
            break
        }
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        webSocket?.send(.string(text)) { error in
            if let error = error {
                print("[LGTV] Send error: \(error)")
            }
        }
    }

    private func nextCommandId() -> String {
        commandId += 1
        return "cmd_\(commandId)"
    }
}
