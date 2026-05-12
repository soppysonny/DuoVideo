import UIKit

protocol PiPStylePanelDelegate: AnyObject {
    func stylePanel(_ panel: PiPStylePanelView, didSelect preset: PiPStylePreset)
    func stylePanelDidToggleCollapse(_ panel: PiPStylePanelView)
}

final class PiPStylePanelView: UIView {

    weak var delegate: PiPStylePanelDelegate?
    private(set) var isExpanded = true

    var selectedID: String = "standard" {
        didSet { collectionView.reloadData() }
    }

    static let headerH: CGFloat    = 40
    static let collectionH: CGFloat = 104
    static let expandedH: CGFloat  = headerH + collectionH
    static let collapsedH: CGFloat = headerH

    private let blurView      = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let headerLabel   = UILabel()
    private let chevronBtn    = UIButton(type: .system)
    private let collectionView: UICollectionView

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 72, height: 88)
        layout.minimumInteritemSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        layer.cornerRadius = 14
        clipsToBounds = true

        blurView.frame = bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blurView)

        headerLabel.text = "PiP 风格"
        headerLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        blurView.contentView.addSubview(headerLabel)

        if let img = UIImage(systemName: "chevron.up") {
            chevronBtn.setImage(img, for: .normal)
        }
        chevronBtn.tintColor = UIColor.white.withAlphaComponent(0.5)
        chevronBtn.addTarget(self, action: #selector(toggleCollapse), for: .touchUpInside)
        blurView.contentView.addSubview(chevronBtn)

        // Separator below header
        let sep = UIView()
        sep.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        sep.frame = CGRect(x: 0, y: PiPStylePanelView.headerH - 0.5,
                           width: 1000, height: 0.5)
        sep.autoresizingMask = .flexibleWidth
        blurView.contentView.addSubview(sep)

        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate   = self
        collectionView.register(PiPStyleCell.self, forCellWithReuseIdentifier: "cell")
        blurView.contentView.addSubview(collectionView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = PiPStylePanelView.headerH
        headerLabel.sizeToFit()
        headerLabel.frame = CGRect(x: 16, y: (h - headerLabel.frame.height) / 2,
                                   width: headerLabel.frame.width, height: headerLabel.frame.height)
        let btnSz: CGFloat = 32
        chevronBtn.frame = CGRect(x: bounds.width - btnSz - 8, y: (h - btnSz) / 2,
                                  width: btnSz, height: btnSz)
        collectionView.frame = CGRect(x: 0, y: h, width: bounds.width,
                                       height: PiPStylePanelView.collectionH)
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        isExpanded = expanded
        let rotation: CGFloat = expanded ? 0 : .pi
        if animated {
            UIView.animate(withDuration: 0.25) {
                self.chevronBtn.transform = CGAffineTransform(rotationAngle: rotation)
            }
        } else {
            chevronBtn.transform = CGAffineTransform(rotationAngle: rotation)
        }
    }

    @objc private func toggleCollapse() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        delegate?.stylePanelDidToggleCollapse(self)
    }
}

// MARK: - Collection data source / delegate

extension PiPStylePanelView: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        PiPStylePreset.all.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: "cell", for: indexPath) as! PiPStyleCell
        let preset = PiPStylePreset.all[indexPath.item]
        cell.configure(preset: preset, selected: preset.id == selectedID)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        let preset = PiPStylePreset.all[indexPath.item]
        selectedID = preset.id
        delegate?.stylePanel(self, didSelect: preset)
    }
}

// MARK: - Cell

private final class PiPStyleCell: UICollectionViewCell {

    private let thumbnailView = StyleThumbnailView()
    private let nameLabel     = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        thumbnailView.layer.cornerRadius = 8
        thumbnailView.clipsToBounds = true
        contentView.addSubview(thumbnailView)

        nameLabel.font = UIFont.systemFont(ofSize: 10, weight: .medium)
        nameLabel.textAlignment = .center
        contentView.addSubview(nameLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let thumbH = contentView.bounds.height - 18
        thumbnailView.frame = CGRect(x: 0, y: 0, width: contentView.bounds.width, height: thumbH)
        nameLabel.frame = CGRect(x: 0, y: thumbH + 4, width: contentView.bounds.width, height: 14)
    }

    func configure(preset: PiPStylePreset, selected: Bool) {
        thumbnailView.preset = preset
        thumbnailView.setNeedsDisplay()
        nameLabel.text = preset.name
        let amber = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1)
        nameLabel.textColor = selected ? amber : UIColor.white.withAlphaComponent(0.7)
        contentView.layer.cornerRadius = 8
        contentView.layer.borderWidth  = selected ? 1.5 : 0
        contentView.layer.borderColor  = amber.cgColor
    }
}

// MARK: - Thumbnail drawing

private final class StyleThumbnailView: UIView {

    var preset: PiPStylePreset?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let preset else { return }

        // Background
        UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 8).fill()

        // Main camera fill (inset)
        let inset: CGFloat = 5
        let bg = rect.insetBy(dx: inset, dy: inset)
        UIColor(red: 0.28, green: 0.28, blue: 0.32, alpha: 1).setFill()
        UIBezierPath(roundedRect: bg, cornerRadius: 5).fill()

        // PiP rectangle
        let pipW = bg.width  * CGFloat(preset.sizeRatio) * 0.85
        let pipH = pipH(for: preset.shape, pipW: pipW)
        let pad: CGFloat = 4
        let pipX: CGFloat
        let pipY: CGFloat
        switch preset.corner {
        case .topLeft:
            pipX = bg.minX + pad; pipY = bg.minY + pad
        case .topRight:
            pipX = bg.maxX - pipW - pad; pipY = bg.minY + pad
        case .bottomLeft:
            pipX = bg.minX + pad; pipY = bg.maxY - pipH - pad
        case .bottomRight:
            pipX = bg.maxX - pipW - pad; pipY = bg.maxY - pipH - pad
        }
        let pipRect = CGRect(x: pipX, y: pipY, width: pipW, height: pipH)

        UIColor(red: 0.85, green: 0.85, blue: 0.88, alpha: 1).setFill()
        switch preset.shape {
        case .roundedRect:
            UIBezierPath(roundedRect: pipRect, cornerRadius: 3).fill()
        case .circle:
            let side = min(pipW, pipH)
            let cr = CGRect(x: pipX + (pipW - side) / 2, y: pipY + (pipH - side) / 2,
                            width: side, height: side)
            UIBezierPath(ovalIn: cr).fill()
        }

        // Amber border for the PiP rectangle
        ctx.saveGState()
        UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 0.55).setStroke()
        let strokePath: UIBezierPath
        switch preset.shape {
        case .roundedRect:
            strokePath = UIBezierPath(roundedRect: pipRect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3)
        case .circle:
            let side = min(pipW, pipH)
            let cr = CGRect(x: pipX + (pipW - side) / 2 + 0.5, y: pipY + (pipH - side) / 2 + 0.5,
                            width: side - 1, height: side - 1)
            strokePath = UIBezierPath(ovalIn: cr)
        }
        strokePath.lineWidth = 1
        strokePath.stroke()
        ctx.restoreGState()
    }

    private func pipH(for shape: LayerShape, pipW: CGFloat) -> CGFloat {
        switch shape {
        case .roundedRect: return pipW * 1.35  // approximate portrait aspect
        case .circle:      return pipW
        }
    }
}
