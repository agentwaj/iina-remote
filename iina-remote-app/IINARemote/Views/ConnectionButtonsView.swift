import SwiftUI

struct ConnectionButtonsView: View {
    let status: ConnectionStatus
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            Button(action: onConnect) {
                Label("Connect", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(status == .disconnected ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(status != .disconnected)

            Button(action: onDisconnect) {
                Label("Disconnect", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(status == .connected ? Color.red : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(status != .connected)
        }
    }
}