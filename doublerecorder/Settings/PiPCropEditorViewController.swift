import UIKit
import AVFoundation

final class PiPCropEditorViewController: UIViewController {

    var onSave: ((PiPNormalizedRect) -> Void)?
    var onDismiss: (() -> Void)?

    private let previewLayer: AVCaptureVideoPreviewLayer
    private let initialCropRect: PiPNormalizedRect

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let imageContainerView = UIView()
    private let previewHostView = UIView()
    private let overlayView = PiPCropOverlayView()
    private let resetButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)

    init(previewLayer: AVCaptureVideoPreviewLayer, initialCropRect: PiPNormalizedRect) {
        self.previewLayer = previewLayer
        self.initialCropRect = initialCropRect.clamped()
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.04, alpha: 1)
        buildUI()
        overlayView.normalizedSelectionRect = initialCropRect
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = imageContainerView.bounds
        previewHostView.frame = bounds
        previewLayer.frame = bounds
        overlayView.frame = bounds
        overlayView.contentFrame = bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            onDismiss?()
        }
    }

    private func buildUI() {
        titleLabel.text = "PIP CUSTOM RANGE"
        titleLabel.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        subtitleLabel.text = "拖动矩形或四角，选中的区域会用于 PiP 预览和最终合成"
        subtitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)

        imageContainerView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        imageContainerView.layer.cornerRadius = 20
        imageContainerView.layer.borderWidth = 0.5
        imageContainerView.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        imageContainerView.clipsToBounds = true
        imageContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageContainerView)

        previewLayer.videoGravity = .resizeAspectFill
        previewHostView.layer.addSublayer(previewLayer)
        previewHostView.backgroundColor = .black
        imageContainerView.addSubview(previewHostView)

        overlayView.translatesAutoresizingMaskIntoConstraints = true
        imageContainerView.addSubview(overlayView)

        configureButton(cancelButton, title: "取消", tint: UIColor.white.withAlphaComponent(0.82), action: #selector(cancelTapped))
        configureButton(resetButton, title: "重置", tint: UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1), action: #selector(resetTapped))
        configureButton(saveButton, title: "应用", tint: .black, action: #selector(saveTapped))
        saveButton.backgroundColor = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            imageContainerView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            imageContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            imageContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            imageContainerView.bottomAnchor.constraint(equalTo: resetButton.topAnchor, constant: -20),

            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            cancelButton.heightAnchor.constraint(equalToConstant: 52),
            cancelButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.28),

            resetButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 12),
            resetButton.bottomAnchor.constraint(equalTo: cancelButton.bottomAnchor),
            resetButton.heightAnchor.constraint(equalToConstant: 52),
            resetButton.widthAnchor.constraint(equalTo: cancelButton.widthAnchor),

            saveButton.leadingAnchor.constraint(equalTo: resetButton.trailingAnchor, constant: 12),
            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: cancelButton.bottomAnchor),
            saveButton.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func configureButton(_ button: UIButton, title: String, tint: UIColor, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(tint, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = UIColor.white.withAlphaComponent(button === saveButton ? 1 : 0.08)
        button.layer.cornerRadius = 16
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        view.addSubview(button)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func resetTapped() {
        overlayView.normalizedSelectionRect = .fullFrame
    }

    @objc private func saveTapped() {
        onSave?(overlayView.normalizedSelectionRect)
        dismiss(animated: true)
    }
}

private final class PiPCropOverlayView: UIView {

    private var storedNormalizedSelectionRect: PiPNormalizedRect = .fullFrame

    var contentFrame: CGRect = .zero {
        didSet { updateSelectionRectFromNormalized(); setNeedsDisplay() }
    }

    var normalizedSelectionRect: PiPNormalizedRect {
        get { storedNormalizedSelectionRect }
        set {
            storedNormalizedSelectionRect = newValue.clamped()
            updateSelectionRectFromNormalized()
            setNeedsDisplay()
        }
    }

    private var selectionRect: CGRect = .zero
    private var editMode: EditMode?
    private var dragStartPoint: CGPoint = .zero
    private var dragStartRect: CGRect = .zero
    private let minSelectionSize: CGFloat = 60

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard contentFrame.width > 0, contentFrame.height > 0, selectionRect.width > 0, selectionRect.height > 0 else { return }

        let outerPath = UIBezierPath(rect: contentFrame)
        outerPath.append(UIBezierPath(rect: selectionRect))
        outerPath.usesEvenOddFillRule = true
        UIColor.black.withAlphaComponent(0.55).setFill()
        outerPath.fill()

        let contentBorder = UIBezierPath(rect: contentFrame)
        UIColor.white.withAlphaComponent(0.12).setStroke()
        contentBorder.lineWidth = 1
        contentBorder.stroke()

        let selectionPath = UIBezierPath(roundedRect: selectionRect, cornerRadius: 14)
        UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1).setStroke()
        selectionPath.lineWidth = 2
        selectionPath.stroke()

        drawGrid(in: selectionRect)
        drawHandles(in: selectionRect)
    }

    private func drawGrid(in rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.30).cgColor)
        ctx.setLineWidth(0.8)
        for index in 1...2 {
            let x = rect.minX + rect.width * CGFloat(index) / 3
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
            let y = rect.minY + rect.height * CGFloat(index) / 3
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        ctx.strokePath()
    }

    private func drawHandles(in rect: CGRect) {
        let radius: CGFloat = 8
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]

        for point in points {
            let handleRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            let path = UIBezierPath(ovalIn: handleRect)
            UIColor.white.setFill()
            path.fill()
            UIColor.black.withAlphaComponent(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func updateSelectionRectFromNormalized() {
        guard contentFrame.width > 0, contentFrame.height > 0 else { return }
        selectionRect = normalizedSelectionRect.scaled(to: contentFrame)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)

        switch gesture.state {
        case .began:
            guard contentFrame.contains(point) else { return }
            editMode = editMode(for: point)
            dragStartPoint = point
            dragStartRect = selectionRect
            if editMode == .create {
                selectionRect = CGRect(origin: point, size: .zero)
            }
        case .changed:
            guard let editMode else { return }
            selectionRect = adjustedRect(for: editMode, point: point)
            normalizedSelectionRect = PiPNormalizedRect.normalized(from: selectionRect, in: contentFrame)
        case .ended, .cancelled, .failed:
            editMode = nil
            normalizedSelectionRect = PiPNormalizedRect.normalized(from: selectionRect, in: contentFrame)
        default:
            break
        }
    }

    private func editMode(for point: CGPoint) -> EditMode {
        let handleInset: CGFloat = 28
        let corners: [(CGRect, EditMode)] = [
            (CGRect(x: selectionRect.minX - handleInset, y: selectionRect.minY - handleInset, width: handleInset * 2, height: handleInset * 2), .topLeft),
            (CGRect(x: selectionRect.maxX - handleInset, y: selectionRect.minY - handleInset, width: handleInset * 2, height: handleInset * 2), .topRight),
            (CGRect(x: selectionRect.minX - handleInset, y: selectionRect.maxY - handleInset, width: handleInset * 2, height: handleInset * 2), .bottomLeft),
            (CGRect(x: selectionRect.maxX - handleInset, y: selectionRect.maxY - handleInset, width: handleInset * 2, height: handleInset * 2), .bottomRight)
        ]

        if let matched = corners.first(where: { $0.0.contains(point) }) {
            return matched.1
        }
        if selectionRect.contains(point) {
            return .move
        }
        return .create
    }

    private func adjustedRect(for mode: EditMode, point: CGPoint) -> CGRect {
        switch mode {
        case .move:
            return movedRect(to: point)
        case .topLeft:
            return resizedRect(point: point, movingMinX: true, movingMinY: true)
        case .topRight:
            return resizedRect(point: point, movingMinX: false, movingMinY: true)
        case .bottomLeft:
            return resizedRect(point: point, movingMinX: true, movingMinY: false)
        case .bottomRight:
            return resizedRect(point: point, movingMinX: false, movingMinY: false)
        case .create:
            return createdRect(to: point)
        }
    }

    private func movedRect(to point: CGPoint) -> CGRect {
        let translation = CGPoint(x: point.x - dragStartPoint.x, y: point.y - dragStartPoint.y)
        var rect = dragStartRect.offsetBy(dx: translation.x, dy: translation.y)
        rect.origin.x = min(max(rect.origin.x, contentFrame.minX), contentFrame.maxX - rect.width)
        rect.origin.y = min(max(rect.origin.y, contentFrame.minY), contentFrame.maxY - rect.height)
        return rect
    }

    private func resizedRect(point: CGPoint, movingMinX: Bool, movingMinY: Bool) -> CGRect {
        var minX = dragStartRect.minX
        var maxX = dragStartRect.maxX
        var minY = dragStartRect.minY
        var maxY = dragStartRect.maxY

        if movingMinX {
            minX = min(max(point.x, contentFrame.minX), maxX - minSelectionSize)
        } else {
            maxX = max(min(point.x, contentFrame.maxX), minX + minSelectionSize)
        }

        if movingMinY {
            minY = min(max(point.y, contentFrame.minY), maxY - minSelectionSize)
        } else {
            maxY = max(min(point.y, contentFrame.maxY), minY + minSelectionSize)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func createdRect(to point: CGPoint) -> CGRect {
        let clampedPoint = CGPoint(
            x: min(max(point.x, contentFrame.minX), contentFrame.maxX),
            y: min(max(point.y, contentFrame.minY), contentFrame.maxY)
        )
        let rect = CGRect(
            x: min(dragStartPoint.x, clampedPoint.x),
            y: min(dragStartPoint.y, clampedPoint.y),
            width: abs(clampedPoint.x - dragStartPoint.x),
            height: abs(clampedPoint.y - dragStartPoint.y)
        )
        let minWidth = max(rect.width, minSelectionSize)
        let minHeight = max(rect.height, minSelectionSize)
        let adjusted = CGRect(x: rect.minX, y: rect.minY, width: minWidth, height: minHeight)
        return adjusted.intersection(contentFrame)
    }

    private enum EditMode {
        case move
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
        case create
    }
}
