import UIKit

enum VideoSource {
    case back
    case front
}

enum LayerShape {
    case roundedRect(cornerRadius: Float)
    case circle
}

final class VideoLayer {
    let source: VideoSource

    weak var containerView: UIView?

    var screenOrigin: CGPoint
    var screenSize: CGSize
    var shape: LayerShape
    var zOrder: Int
    var isBackground: Bool

    init(source: VideoSource,
         containerView: UIView? = nil,
         screenOrigin: CGPoint = .zero,
         screenSize: CGSize = .zero,
         shape: LayerShape = .roundedRect(cornerRadius: 0.015),
         zOrder: Int = 0,
         isBackground: Bool = false) {
        self.source = source
        self.containerView = containerView
        self.screenOrigin = screenOrigin
        self.screenSize = screenSize
        self.shape = shape
        self.zOrder = zOrder
        self.isBackground = isBackground
    }

    var isCircle: Bool {
        if case .circle = shape { return true }
        return false
    }

    // For roundedRect: returns the normalized corner radius.
    // For circle: returns 0 — VideoRecorder computes min(normW,normH)/2 in normalized video space.
    var normalizedCornerRadius: Float {
        switch shape {
        case .roundedRect(let r): return r
        case .circle:             return 0
        }
    }
}
