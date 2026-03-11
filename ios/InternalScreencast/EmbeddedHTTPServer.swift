import Foundation
import Network

/// Minimal HTTP server that serves the receiver HTML page from the iOS app.
/// This lets the TV load the receiver by navigating to http://<iphone-ip>:8080
class EmbeddedHTTPServer {
    private var listener: NWListener?
    private let port: UInt16
    private let queue = DispatchQueue(label: "http-server", qos: .userInteractive)
    private let receiverHTML: String

    var isRunning = false

    init(port: UInt16 = 8080) {
        self.port = port

        // Load the receiver HTML from the app bundle
        if let path = Bundle.main.path(forResource: "receiver", ofType: "html"),
           let html = try? String(contentsOfFile: path, encoding: .utf8) {
            self.receiverHTML = html
        } else {
            // Fallback: minimal page that redirects
            self.receiverHTML = """
            <!DOCTYPE html>
            <html><body><h1>Receiver not found in bundle</h1></body></html>
            """
        }
    }

    func start() {
        guard !isRunning else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .wifi

        do {
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            print("[HTTP] Failed to create listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.isRunning = true
                print("[HTTP] Server listening on port \(self?.port ?? 0)")
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("[HTTP] Connection failed: \(error)")
            }
        }
        connection.start(queue: queue)

        // Read the HTTP request
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self = self, let data = data else {
                connection.cancel()
                return
            }

            let request = String(data: data, encoding: .utf8) ?? ""

            // Serve the receiver page for any GET request
            if request.hasPrefix("GET") {
                let body = Data(self.receiverHTML.utf8)
                let response = [
                    "HTTP/1.1 200 OK",
                    "Content-Type: text/html; charset=utf-8",
                    "Content-Length: \(body.count)",
                    "Connection: close",
                    "Cache-Control: no-cache",
                    "Access-Control-Allow-Origin: *",
                    "",
                    ""
                ].joined(separator: "\r\n")

                var responseData = Data(response.utf8)
                responseData.append(body)

                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else {
                // 404 for anything else
                let response = "HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }
}
