import UIKit
import AVFoundation

class CameraPreviewView: UIView {

    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    var visibleRect: PiPNormalizedRect = .fullFrame {
        didSet { updatePreviewGeometry() }
    }

    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer?.removeFromSuperlayer()
        previewLayer = layer
        layer.removeFromSuperlayer()  // detach from any previous superlayer
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        updatePreviewGeometry()
    }

    /// 移除当前预览层并返回，不做任何 attach 操作。
    /// 在 swap 时需要先 detach 两端再重新 attach，避免 CALayer 单父层限制导致黑屏。
    @discardableResult
    func detach() -> AVCaptureVideoPreviewLayer? {
        let layer = previewLayer
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        return layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePreviewGeometry()
    }

    private func updatePreviewGeometry() {
        guard let previewLayer else { return }
        let rect = visibleRect.clamped()
        guard bounds.width > 0, bounds.height > 0 else {
            previewLayer.frame = bounds
            return
        }
        previewLayer.frame = CGRect(
            x: -rect.x * bounds.width / rect.width,
            y: -rect.y * bounds.height / rect.height,
            width: bounds.width / rect.width,
            height: bounds.height / rect.height
        )
    }
}
