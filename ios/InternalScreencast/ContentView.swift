import SwiftUI
import ReplayKit

struct ContentView: View {
    @AppStorage("signalingServerIP", store: UserDefaults(suiteName: "group.com.internal.screencast"))
    private var signalingServerIP: String = ""

    @State private var isBroadcasting = false
    @State private var showCopied = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Signaling Server")) {
                    TextField("Server IP (e.g. 192.168.1.100)", text: $signalingServerIP)
                        .keyboardType(.decimalPad)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    HStack {
                        Text("ws://\(signalingServerIP.isEmpty ? "<ip>" : signalingServerIP):8765")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Copy") {
                            UIPasteboard.general.string = "ws://\(signalingServerIP):8765"
                            showCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopied = false
                            }
                        }
                        .disabled(signalingServerIP.isEmpty)
                    }
                }

                Section(header: Text("Screen Broadcast")) {
                    BroadcastPickerRepresentable()
                        .frame(height: 44)

                    Text("Tap the button above to start broadcasting. Select \"Internal Screencast\" from the picker.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Instructions")) {
                    VStack(alignment: .leading, spacing: 8) {
                        instructionRow(number: "1", text: "Run start.sh on your computer")
                        instructionRow(number: "2", text: "Enter your computer's LAN IP above")
                        instructionRow(number: "3", text: "Open the receiver URL on your TV browser")
                        instructionRow(number: "4", text: "Tap the broadcast button to start mirroring")
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("Latency Budget")) {
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
                }
            }
            .navigationTitle("Internal Screencast")
            .overlay(
                Group {
                    if showCopied {
                        Text("Copied!")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.75))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut, value: showCopied),
                alignment: .bottom
            )
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .clipShape(Circle())
            Text(text)
                .font(.caption)
        }
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
