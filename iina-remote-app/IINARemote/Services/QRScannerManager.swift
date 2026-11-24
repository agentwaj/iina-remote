import AVFoundation
import Observation
import SwiftUI

@Observable
final class QRScannerManager: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var connectionData: ConnectionData?
    var scanningError: String = ""
    private(set) var isScanning: Bool = false

    @ObservationIgnored private var captureSession: AVCaptureSession?
    @ObservationIgnored private var previewLayer: AVCaptureVideoPreviewLayer?
    /// startRunning/stopRunning block, so they run off the main thread, and on
    /// one serial queue so a stop can never overtake the start before it.
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "QRScannerManager.session")

    func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            scanningError = "Camera access denied. Please enable in Settings."
            return false
        @unknown default:
            return false
        }
    }

    func startScanning() async -> AVCaptureVideoPreviewLayer? {
        scanningError = ""
        isScanning = true

        guard await requestCameraPermission() else {
            isScanning = false
            return nil
        }

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            scanningError = "No camera available"
            isScanning = false
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
                scanningError = "Cannot add video input"
                isScanning = false
                return nil
            }

            let metadataOutput = AVCaptureMetadataOutput()

            if captureSession!.canAddOutput(metadataOutput) {
                captureSession!.addOutput(metadataOutput)

                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            } else {
                scanningError = "Cannot add metadata output"
                isScanning = false
                return nil
            }

            captureSession?.commitConfiguration()

            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            previewLayer?.videoGravity = .resizeAspectFill

            // AVCaptureSession isn't marked Sendable, but Apple documents
            // startRunning/stopRunning as safe (and recommended) off the main thread.
            nonisolated(unsafe) let session = captureSession!
            sessionQueue.async { session.startRunning() }

            let sessionID = ObjectIdentifier(session)
            Task {
                try? await Task.sleep(for: .seconds(1))
                // If a code was scanned (or the sheet closed) within the second,
                // stopScanning() already ended this session on purpose.
                guard captureSession.map(ObjectIdentifier.init) == sessionID else { return }

                if captureSession?.isRunning != true {
                    scanningError = "Failed to start camera session"
                    isScanning = false
                }
            }

            return previewLayer
        } catch {
            scanningError = "Camera setup failed: \(error.localizedDescription)"
            isScanning = false
            return nil
        }
    }

    func stopScanning() {
        // Hand over the session itself: by the time the queue runs, the
        // property below has already been cleared.
        nonisolated(unsafe) let session = captureSession
        sessionQueue.async { session?.stopRunning() }
        captureSession = nil
        previewLayer = nil
        isScanning = false
    }

    func metadataOutput(_: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from _: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }

            // Prevent processing the same QR code multiple times
            guard connectionData == nil else { return }

            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            do {
                if let data = stringValue.data(using: .utf8) {
                    connectionData = try JSONDecoder().decode(ConnectionData.self, from: data)
                    scanningError = ""
                    stopScanning()
                }
            } catch {
                scanningError = "Invalid QR code format: \(error.localizedDescription)"
            }
        }
    }
}
