import SwiftUI

struct QRScannerSheet: View {
    @ObservedObject var scanner: QRScannerManager
    let onCancel: () -> Void
    let onConnect: (ConnectionData) -> Void

    @State private var hasConnected = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if scanner.isScanning {
                    QRScannerView(scanner: scanner)
                        .ignoresSafeArea()
                } else {
                    VStack(spacing: 20) {
                        ProgressView("Starting camera...")
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .foregroundStyle(.white)
                    }
                }

                VStack {
                    Spacer()

                    if !scanner.scanningError.isEmpty {
                        Text("Error: \(scanner.scanningError)")
                            .padding()
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(.rect(cornerRadius: 10))
                            .padding()
                    }

                    if scanner.isScanning {
                        VStack {
                            RoundedRectangle(cornerSize: .init(width: 10, height: 10))
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 250, height: 250)
                                .background(Color.clear)

                            Text("Position QR code within the frame")
                                .foregroundStyle(.white)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .clipShape(.rect(cornerRadius: 8))
                        }
                    }

                    Spacer()
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        scanner.stopScanning()
                        onCancel()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .onReceive(scanner.$connectionData) { connectionData in
            if let connectionData = connectionData, !hasConnected {
                hasConnected = true
                onConnect(connectionData)
            }
        }
        .onAppear {
            hasConnected = false
            scanner.connectionData = nil
            scanner.scanningError = ""

            Task {
                _ = await scanner.startScanning()
            }
        }
        .onDisappear {
            scanner.stopScanning()
        }
    }
}

#Preview {
    QRScannerSheet(scanner: .init(), onCancel: {}, onConnect: { _ in })
}
