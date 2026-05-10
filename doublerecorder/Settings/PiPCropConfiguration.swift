import CoreGraphics

struct PiPNormalizedRect: Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    static let fullFrame = PiPNormalizedRect(x: 0, y: 0, width: 1, height: 1)

    var isFullFrame: Bool {
        self == Self.fullFrame
    }

    var minX: CGFloat { x }
    var minY: CGFloat { y }
    var maxX: CGFloat { x + width }
    var maxY: CGFloat { y + height }

    func clamped(minSize: CGFloat = 0.12) -> PiPNormalizedRect {
        let safeMinSize = min(max(minSize, 0.05), 1)
        let clampedWidth = min(max(width, safeMinSize), 1)
        let clampedHeight = min(max(height, safeMinSize), 1)
        let clampedX = min(max(x, 0), 1 - clampedWidth)
        let clampedY = min(max(y, 0), 1 - clampedHeight)
        return PiPNormalizedRect(x: clampedX, y: clampedY, width: clampedWidth, height: clampedHeight)
    }

    func scaled(to rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX + x * rect.width,
            y: rect.minY + y * rect.height,
            width: width * rect.width,
            height: height * rect.height
        )
    }

    static func normalized(from rect: CGRect, in bounds: CGRect) -> PiPNormalizedRect {
        guard bounds.width > 0, bounds.height > 0 else { return .fullFrame }
        return PiPNormalizedRect(
            x: (rect.minX - bounds.minX) / bounds.width,
            y: (rect.minY - bounds.minY) / bounds.height,
            width: rect.width / bounds.width,
            height: rect.height / bounds.height
        ).clamped()
    }
}