import Foundation
import Network

/// Discovers LG webOS TVs on the local network using SSDP (UPnP).
/// LG TVs respond to the DIAL search target: urn:dial-multiscreen-org:service:dial:1
class SSDPDiscovery: ObservableObject {
    @Published var discoveredTVs: [LGDevice] = []
    @Published var isScanning = false

    private var connection: NWConnection?
    private var listener: NWListener?
    private var scanTimer: DispatchSourceTimer?

    struct LGDevice: Identifiable, Hashable {
        let id: String // USN
        let name: String
        let address: String
        let port: Int
        let location: String // Description XML URL

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: LGDevice, rhs: LGDevice) -> Bool {
            lhs.id == rhs.id
        }
    }

    private let multicastGroup = "239.255.255.250"
    private let ssdpPort: UInt16 = 1900
    private let searchTarget = "urn:dial-multiscreen-org:service:dial:1"

    /// Start scanning for LG TVs. Sends 3 M-SEARCH packets over 6 seconds.
    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        discoveredTVs = []

        listenForResponses()
        sendMSearch()

        // Re-send M-SEARCH a couple times for reliability
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(100))
        var count = 0
        timer.setEventHandler { [weak self] in
            count += 1
            if count >= 2 {
                self?.scanTimer?.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.isScanning = false
                }
            }
            self?.sendMSearch()
        }
        timer.resume()
        scanTimer = timer
    }

    func stopScan() {
        scanTimer?.cancel()
        scanTimer = nil
        connection?.cancel()
        connection = nil
        isScanning = false
    }

    private func sendMSearch() {
        let message = [
            "M-SEARCH * HTTP/1.1",
            "HOST: \(multicastGroup):\(ssdpPort)",
            "MAN: \"ssdp:discover\"",
            "MX: 3",
            "ST: \(searchTarget)",
            "USER-AGENT: InternalScreencast/1.0",
            "",
            ""
        ].joined(separator: "\r\n")

        let host = NWEndpoint.Host(multicastGroup)
        let port = NWEndpoint.Port(rawValue: ssdpPort)!

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .wifi

        let conn = NWConnection(host: host, port: port, using: params)
        conn.stateUpdateHandler = { state in
            if case .ready = state {
                conn.send(content: message.data(using: .utf8), completion: .contentProcessed { _ in })
            }
        }
        conn.start(queue: .global())

        // Keep reference alive briefly
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
            conn.cancel()
        }
    }

    private func listenForResponses() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .wifi

        do {
            let listener = try NWListener(using: params, on: .any)
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    print("[SSDP] Listener failed: \(error)")
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .global())
                self?.receiveResponse(on: conn)
            }
            listener.start(queue: .global())
            self.listener = listener
        } catch {
            print("[SSDP] Could not start listener: \(error)")
        }
    }

    private func receiveResponse(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let data = data, let response = String(data: data, encoding: .utf8) else { return }
            self?.parseResponse(response, from: connection)
            // Continue receiving
            self?.receiveResponse(on: connection)
        }
    }

    private func parseResponse(_ response: String, from connection: NWConnection) {
        // Only process responses that look like SSDP
        guard response.contains("HTTP/1.1 200 OK") || response.contains("NOTIFY") else { return }

        var headers: [String: String] = [:]
        let lines = response.components(separatedBy: "\r\n")
        for line in lines {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces).uppercased()
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        guard let location = headers["LOCATION"],
              let usn = headers["USN"],
              let url = URL(string: location),
              let host = url.host else { return }

        // Filter for LG TVs — they include "LG" in the SERVER header or USN
        let server = headers["SERVER"] ?? ""
        let isLG = server.contains("LG") ||
                   server.contains("webOS") ||
                   usn.contains("LG") ||
                   response.contains("LG")

        // Fetch the device description to get the friendly name
        fetchDeviceName(from: location) { [weak self] name in
            let device = LGDevice(
                id: usn,
                name: name ?? (isLG ? "LG TV (\(host))" : "Smart TV (\(host))"),
                address: host,
                port: url.port ?? 80,
                location: location
            )

            DispatchQueue.main.async {
                if !(self?.discoveredTVs.contains(where: { $0.address == host }) ?? true) {
                    self?.discoveredTVs.append(device)
                }
            }
        }
    }

    private func fetchDeviceName(from locationURL: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: locationURL) else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let xml = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }

            // Simple XML parse for <friendlyName>
            if let start = xml.range(of: "<friendlyName>"),
               let end = xml.range(of: "</friendlyName>") {
                let name = String(xml[start.upperBound..<end.lowerBound])
                completion(name)
            } else {
                completion(nil)
            }
        }.resume()
    }
}
