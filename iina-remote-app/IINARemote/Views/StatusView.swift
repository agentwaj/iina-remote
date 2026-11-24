import SwiftUI

struct StatusView: View {
    let status: ConnectionStatus
    let errorMessage: String

    var statusText: String {
        switch status {
        case .disconnected:
            return "Disconnected"
        case .scanning:
            return "Scanning QR Code..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        }
    }

    var statusColor: Color {
        switch status {
        case .disconnected:
            return .red
        case .scanning, .connecting:
            return .orange
        case .connected:
            return .green
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(statusText)
                    .font(.headline)
            }

            if !errorMessage.isEmpty {
                Text("Error: \(errorMessage)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(.rect(cornerRadius: 10))
    }
}

#Preview {
    StatusView(status: .disconnected, errorMessage: "Error message")
    StatusView(status: .disconnected, errorMessage: "")
    StatusView(status: .scanning, errorMessage: "")
    StatusView(status: .connecting, errorMessage: "")
    StatusView(status: .connected, errorMessage: "")
}
