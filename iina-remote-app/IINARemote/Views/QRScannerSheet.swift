import SwiftUI

struct QRScannerSheet: View {
    @ObservedObject var scanner: QRScannerManager
    let onCancel: () -> Void
    let onConnect: (ConnectionData) -> Void

    var body: some View {
        NavigationView {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if scanner.isScanning {
                    QRScannerView(scanner: scanner)
                        .ignoresSafeArea()
                } else {
                    VStack(spacing: 20) {
                        ProgressView("Starting camera...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .foregroundColor(.white)
                        Text("Point your camera at a QR code")
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                }

                VStack {
                    Spacer()

                    if !scanner.scanningError.isEmpty {
                        Text("Error: \(scanner.scanningError)")
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .padding()
                    }

                    // Scanning guide overlay
                    if scanner.isScanning {
                        VStack {
                            RoundedRectangle(cornerSize: .init(width: 10, height: 10))
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 250, height: 250)
                                .background(Color.clear)

                            Text("Position QR code within the frame")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                        }
                    }

                    Spacer()
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        scanner.stopScanning()
                        onCancel()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onReceive(scanner.$connectionData) { connectionData in
            if let connectionData = connectionData {
                onConnect(connectionData)
            }
        }
        .onAppear {
            print("QR scanner sheet has appeared")
            // Reset scanner state when sheet appears
            scanner.connectionData = nil
            scanner.scanningError = ""

            // Start scanning
            Task {
                await scanner.startScanning()
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
