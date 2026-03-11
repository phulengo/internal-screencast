import SwiftUI
import ReplayKit

struct ContentView: View {
    @StateObject private var discovery = SSDPDiscovery()
    @StateObject private var signalingServer = EmbeddedSignalingServer()
    @StateObject private var tvController = LGTVController()

    @AppStorage("signalingServerIP", store: UserDefaults(suiteName: "group.com.internal.screencast"))
    private var signalingServerIP: String = ""

    @State private var selectedTV: SSDPDiscovery.LGDevice?
    @State private var isCasting = false
    @State private var statusMessage = ""

    private let httpServer = EmbeddedHTTPServer()

    var body: some View {
        NavigationView {
            List {
                // MARK: - TV Discovery
                Section {
                    if discovery.isScanning {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Scanning for LG TVs...")
                                .foregroundColor(.secondary)
                        }
                    }

                    if discovery.discoveredTVs.isEmpty && !discovery.isScanning {
                        Button(action: { discovery.startScan() }) {
                            Label("Scan for TVs", systemImage: "tv")
                        }
                    }

                    ForEach(discovery.discoveredTVs) { tv in
                        Button(action: { selectTV(tv) }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tv.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(tv.address)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedTV == tv {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }

                    if !discovery.discoveredTVs.isEmpty {
                        Button(action: { discovery.startScan() }) {
                            Label("Rescan", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("LG TV")
                } footer: {
                    Text("Make sure your iPhone and LG TV are on the same WiFi network.")
                }

                // MARK: - Cast Control
                Section {
                    if let tv = selectedTV {
                        if !isCasting {
                            Button(action: { startCasting(to: tv) }) {
                                HStack {
                                    Spacer()
                                    Label("Cast to \(tv.name)", systemImage: "airplayvideo")
                                        .font(.headline)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        } else {
                            VStack(spacing: 12) {
                                HStack {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 8, height: 8)
                                    Text("Casting to \(tv.name)")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                }

                                BroadcastPickerRepresentable()
                                    .frame(height: 44)

                                Text("Tap the record button above, then select \"Internal Screencast\" to start mirroring.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 8)

                            Button(role: .destructive, action: stopCasting) {
                                Label("Stop Casting", systemImage: "stop.circle")
                            }
                        }
                    } else {
                        Text("Select a TV above to start casting")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Screen Mirror")
                }

                // MARK: - Status
                Section {
                    StatusRow(label: "Signaling Server", isActive: signalingServer.isRunning)
                    StatusRow(label: "HTTP Server", isActive: httpServer.isRunning)
                    StatusRow(label: "TV Connected", isActive: tvController.isConnected)

                    if signalingServer.connectedClients > 0 {
                        HStack {
                            Text("WebRTC Clients")
                            Spacer()
                            Text("\(signalingServer.connectedClients)")
                                .foregroundColor(.secondary)
                        }
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("Status")
                }

                // MARK: - Latency
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        latencyRow(label: "ReplayKit capture", value: "~16ms")
                        latencyRow(label: "H.264 encode", value: "~8ms")
                        latencyRow(label: "Network (LAN UDP)", value: "~2ms")
                        latencyRow(label: "WebRTC jitter buffer", value: "~40ms")
                        latencyRow(label: "Decode + render", value: "~50ms")
                        Divider()
                        latencyRow(label: "Total estimate", value: "~116ms")
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                } header: {
                    Text("Latency Budget")
                }
            }
            .navigationTitle("Internal Screencast")
            .onAppear {
                discovery.startScan()
            }
        }
    }

    // MARK: - Actions

    private func selectTV(_ tv: SSDPDiscovery.LGDevice) {
        selectedTV = tv
    }

    private func startCasting(to tv: SSDPDiscovery.LGDevice) {
        // 1. Get our own WiFi IP
        guard let myIP = EmbeddedSignalingServer.getWiFiAddress() else {
            statusMessage = "Cannot determine WiFi IP. Are you connected to WiFi?"
            return
        }

        // 2. Store our IP for the broadcast extension to use
        signalingServerIP = myIP

        // 3. Start embedded servers
        signalingServer.start()
        httpServer.start()

        // 4. Connect to TV and open the receiver page
        tvController.connect(to: tv.address)

        // Give the TV a moment to connect, then launch the browser
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let receiverURL = "http://\(myIP):8080"
            tvController.launchBrowser(url: receiverURL)
            statusMessage = "Receiver opened on TV. Tap the broadcast button below."
        }

        isCasting = true
    }

    private func stopCasting() {
        tvController.disconnect()
        signalingServer.stop()
        httpServer.stop()
        isCasting = false
        statusMessage = ""
    }

    private func latencyRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

struct StatusRow: View {
    let label: String
    let isActive: Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(isActive ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(isActive ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Wraps RPSystemBroadcastPickerView for SwiftUI
struct BroadcastPickerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = "com.internal.screencast.broadcast"
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

#Preview {
    ContentView()
}
