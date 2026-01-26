import AVFoundation
import Combine
import SwiftUI

class QRScannerManager: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var connectionData: ConnectionData?
    @Published var scanningError: String = ""
    @Published var isScanning: Bool = false

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            await MainActor.run {
                scanningError = "Camera access denied. Please enable in Settings."
            }
            return false
        @unknown default:
            return false
        }
    }

    func startScanning() async -> AVCaptureVideoPreviewLayer? {
        // Reset previous errors
        await MainActor.run {
            scanningError = ""
            isScanning = true
        }

        print("🎥 Starting camera initialization...")

        // Check if running in simulator
        #if targetEnvironment(simulator)
            print("🚫 Running in simulator - camera not available")
            await MainActor.run {
                scanningError = "QR scanning not available in simulator."
                isScanning = false
            }
            return nil
        #endif

        // Check camera permission first
        print("📋 Checking camera permission...")
        guard await requestCameraPermission() else {
            print("❌ Camera permission denied")
            await MainActor.run {
                isScanning = false
            }
            return nil
        }
        print("✅ Camera permission granted")

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            print("❌ No camera device available")
            await MainActor.run {
                scanningError = "No camera available"
                isScanning = false
            }
            return nil
        }
        print("📷 Camera device found: \(videoCaptureDevice.localizedName)")

        do {
            print("🔧 Creating video input...")
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            captureSession = AVCaptureSession()

            // Configure session for better performance
            print("⚙️ Configuring capture session...")
            captureSession?.beginConfiguration()
            captureSession?.sessionPreset = .medium

            if captureSession!.canAddInput(videoInput) {
                captureSession!.addInput(videoInput)
            } else {
                await MainActor.run {
                    scanningError = "Cannot add video input"
                    isScanning = false
                }
                return nil
            }

            let metadataOutput = AVCaptureMetadataOutput()

            if captureSession!.canAddOutput(metadataOutput) {
                captureSession!.addOutput(metadataOutput)

                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            } else {
                await MainActor.run {
                    scanningError = "Cannot add metadata output"
                    isScanning = false
                }
                return nil
            }

            captureSession?.commitConfiguration()

            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            previewLayer?.videoGravity = .resizeAspectFill

            // Start session on background queue and update UI when ready
            print("🚀 Starting capture session...")
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession?.startRunning()
                print("📡 Capture session start command sent")

                // Wait a moment for the session to fully start
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    DispatchQueue.main.async {
                        let isRunning = self.captureSession?.isRunning == true
                        print("🔍 Session running check: \(isRunning)")

                        if isRunning {
                            print("✅ Camera session is running successfully")
                            // Camera is running, UI should show scanner
                            // isScanning is already true from earlier
                        } else {
                            print("❌ Camera session failed to start")
                            self.scanningError = "Failed to start camera session"
                            self.isScanning = false
                        }
                    }
                }
            }

            return previewLayer
        } catch {
            await MainActor.run {
                scanningError = "Camera setup failed: \(error.localizedDescription)"
                isScanning = false
            }
            return nil
        }
    }

    func stopScanning() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.stopRunning()
        }
        captureSession = nil
        previewLayer = nil
        isScanning = false
    }

    func metadataOutput(_: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from _: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }

            // Provide haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            do {
                if let data = stringValue.data(using: .utf8) {
                    connectionData = try JSONDecoder().decode(ConnectionData.self, from: data)
                    stopScanning()
                }
            } catch {
                scanningError = "Invalid QR code format: \(error.localizedDescription)"
            }
        }
    }
}
