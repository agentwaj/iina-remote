import SwiftUI

struct ContentView: View {
    @StateObject private var webSocketManager = WebSocketManager()
    @StateObject private var qrScanner = QRScannerManager()
    @State private var showingScanner = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                StatusView(
                    status: webSocketManager.connectionStatus,
                    errorMessage: webSocketManager.errorMessage.isEmpty ? qrScanner.scanningError : webSocketManager.errorMessage
                )

                ConnectionButtonsView(
                    status: webSocketManager.connectionStatus,
                    onConnect: { showingScanner = true },
                    onDisconnect: {
                        webSocketManager.disconnect()
                        qrScanner.connectionData = nil
                    }
                )

                Spacer()

                MediaControlsView(
                    isEnabled: webSocketManager.connectionStatus == .connected,
                    onPlay: { webSocketManager.sendCommand("play") },
                    onPause: { webSocketManager.sendCommand("pause") },
                    onForward: { webSocketManager.sendCommand("forward") },
                    onBackward: { webSocketManager.sendCommand("backward") }
                )
            }
            .padding()
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
    }
}

#Preview {
    ContentView()
}
