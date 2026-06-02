import UIKit

enum PiPCorner { case topLeft, topRight, bottomLeft, bottomRight }

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
        PiPStylePreset(id: "standard",    name: "标准", corner: .bottomRight, sizeRatio: 0.30, shape: .roundedRect(cornerRadius: 0.015)),
        PiPStylePreset(id: "large",       name: "大窗", corner: .bottomRight, sizeRatio: 0.45, shape: .roundedRect(cornerRadius: 0.015)),
        PiPStylePreset(id: "small",       name: "小窗", corner: .bottomRight, sizeRatio: 0.18, shape: .roundedRect(cornerRadius: 0.015)),
        PiPStylePreset(id: "circle",      name: "圆形", corner: .bottomRight, sizeRatio: 0.25, shape: .circle),
        PiPStylePreset(id: "split",       name: "均分", corner: .bottomRight, sizeRatio: 0.50, shape: .splitH),
        PiPStylePreset(id: "top_left",    name: "左上", corner: .topLeft,     sizeRatio: 0.30, shape: .roundedRect(cornerRadius: 0.015)),
        PiPStylePreset(id: "top_right",   name: "右上", corner: .topRight,    sizeRatio: 0.30, shape: .roundedRect(cornerRadius: 0.015)),
        PiPStylePreset(id: "bottom_left", name: "左下", corner: .bottomLeft,  sizeRatio: 0.30, shape: .roundedRect(cornerRadius: 0.015)),
    ]
}
