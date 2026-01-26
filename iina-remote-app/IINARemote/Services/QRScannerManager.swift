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
        await MainActor.run {
            scanningError = ""
            isScanning = true
        }

        guard await requestCameraPermission() else {
            await MainActor.run {
                isScanning = false
            }
            return nil
        }

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            await MainActor.run {
                scanningError = "No camera available"
                isScanning = false
            }
            return nil
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            captureSession = AVCaptureSession()

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

            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession?.startRunning()

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    DispatchQueue.main.async {
                        let isRunning = self.captureSession?.isRunning == true

                        if !isRunning {
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
