import UIKit
import AVFoundation

class CameraPreviewView: UIView {

    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer?.removeFromSuperlayer()
        previewLayer = layer
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        layer.frame = bounds
    }

    /// 仅移除当前预览层并清空引用，不做任何 attach 操作。
    /// 在 swap 时需要先 detach 两端再重新 attach，避免 CALayer 单父层限制导致黑屏。
    func detach() {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    // 每次 Auto Layout 更新 bounds 时同步子图层尺寸
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}
