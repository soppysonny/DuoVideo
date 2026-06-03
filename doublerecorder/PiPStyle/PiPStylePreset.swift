import UIKit

enum PiPCorner: String { case topLeft, topRight, bottomLeft, bottomRight }

struct PiPStylePreset {
    let id: String
    let name: String
    let corner: PiPCorner
    let sizeRatio: CGFloat
    let shape: LayerShape

    var isCircle: Bool {
        if case .circle = shape { return true }
        return false
    }

    var isSplitH: Bool {
        if case .splitH = shape { return true }
        return false
    }

    static let all: [PiPStylePreset] = [
        PiPStylePreset(id: "standard", name: NSLocalizedString("pip.style.standard", comment: ""), corner: .bottomRight, sizeRatio: 0.30, shape: .roundedRect(cornerRadius: 0.015)),
        PiPStylePreset(id: "large",    name: NSLocalizedString("pip.style.large",    comment: ""), corner: .bottomRight, sizeRatio: 0.45, shape: .roundedRect(cornerRadius: 0.015)),
        PiPStylePreset(id: "small",    name: NSLocalizedString("pip.style.small",    comment: ""), corner: .bottomRight, sizeRatio: 0.18, shape: .roundedRect(cornerRadius: 0.015)),
        PiPStylePreset(id: "circle",   name: NSLocalizedString("pip.style.circle",   comment: ""), corner: .bottomRight, sizeRatio: 0.25, shape: .circle),
        PiPStylePreset(id: "split",    name: NSLocalizedString("pip.style.split",    comment: ""), corner: .bottomRight, sizeRatio: 0.50, shape: .splitH),
    ]
}
