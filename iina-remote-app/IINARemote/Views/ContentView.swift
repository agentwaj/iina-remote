import SwiftUI

struct ContentView: View {
    @StateObject private var webSocketManager = WebSocketManager()
    @StateObject private var qrScanner = QRScannerManager()
    @State private var showingScanner = false
    // Returning goes background → inactive → active, so the phase that
    // precedes .active is never .background; remember it instead.
    @State private var wasInBackground = false
    @Environment(\.scenePhase) private var scenePhase

    private var errorMessage: String {
        if !webSocketManager.errorMessage.isEmpty { return webSocketManager.errorMessage }
        // Scanner errors are about getting connected; once connected they're stale.
        if webSocketManager.connectionStatus == .connected { return "" }
        return qrScanner.scanningError
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                StatusView(
                    status: webSocketManager.connectionStatus,
                    errorMessage: errorMessage
                )

                ConnectionButtonsView(
                    status: webSocketManager.connectionStatus,
                    onConnect: { showingScanner = true },
                    onDisconnect: {
                        webSocketManager.disconnect()
                        qrScanner.connectionData = nil
                    }
                )

                VStack(spacing: 8) {
                    Text(webSocketManager.connectionStatus == .connected ? "Now Playing" : "Waiting to connect")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(webSocketManager.currentTitle.isEmpty ? " " : webSocketManager.currentTitle)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemBackground).opacity(0.5))
                .cornerRadius(12)
                .opacity(webSocketManager.connectionStatus == .connected ? 1 : 0.6)

                Spacer()

                MediaControlsView(
                    isEnabled: webSocketManager.connectionStatus == .connected,
                    subtitleTracks: webSocketManager.subtitleTracks,
                    currentSubtitleId: webSocketManager.currentSubtitleId,
                    onPlay: { webSocketManager.sendCommand("play") },
                    onPause: { webSocketManager.sendCommand("pause") },
                    onForward: { webSocketManager.sendCommand("forward") },
                    onBackward: { webSocketManager.sendCommand("backward") },
                    onSelectSubtitle: { webSocketManager.selectSubtitle($0) }
                )
            }
            .padding()
            .background(AuroraBackground())
            .navigationTitle("IINA Remote")
        }
        .sheet(isPresented: $showingScanner) {
            QRScannerSheet(
                scanner: qrScanner,
                onCancel: { showingScanner = false },
                onConnect: { connectionData in
                    showingScanner = false
                    webSocketManager.connect(to: connectionData)
                }
            )
        }
        .onAppear {
            webSocketManager.autoConnectIfPossible()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                wasInBackground = true
            case .active where wasInBackground:
                wasInBackground = false
                webSocketManager.autoConnectIfPossible()
            default:
                break
            }
        }
    }
}

#Preview {
    ContentView()
}
