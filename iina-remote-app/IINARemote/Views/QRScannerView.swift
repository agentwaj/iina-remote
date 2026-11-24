import AVFoundation
import SwiftUI

struct QRScannerView: UIViewRepresentable {
    let scanner: QRScannerManager

    class Coordinator: NSObject {
        var parent: QRScannerView

        init(parent: QRScannerView) {
            self.parent = parent
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.black

        Task {
            if let previewLayer = await scanner.startScanning() {
                await MainActor.run {
                    // Remove any existing layers first
                    view.layer.sublayers?.removeAll { $0 is AVCaptureVideoPreviewLayer }

                    previewLayer.frame = view.bounds
                    view.layer.addSublayer(previewLayer)

                    // Force layout update
                    view.setNeedsLayout()
                    view.layoutIfNeeded()
                }
            }
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        // Update the preview layer frame when the view bounds change
        if let previewLayer = uiView.layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer }) as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}

#Preview {
    QRScannerView(scanner: .init())
}
