import UIKit

class RecordButtonView: UIControl {

    private let trackLayer    = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let idleRingLayer = CAShapeLayer()
    private let innerView     = UIView()
    private let pulseView     = UIView()

    private let recRed = UIColor(red: 1, green: 0.231, blue: 0.188, alpha: 1)

    var isRecording: Bool = false {
        didSet { guard oldValue != isRecording else { return }; applyState(animated: true) }
    }

    var progress: CGFloat = 0 {
        didSet { progressLayer.strokeEnd = progress }
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        isAccessibilityElement = true

        // CALayers first — they sit below UIView subviews in Z-order
        trackLayer.fillColor   = UIColor.clear.cgColor
        trackLayer.strokeColor = UIColor.white.withAlphaComponent(0.32).cgColor
        trackLayer.lineWidth   = 3
        layer.addSublayer(trackLayer)

        progressLayer.fillColor   = UIColor.clear.cgColor
        progressLayer.strokeColor = recRed.cgColor
        progressLayer.lineWidth   = 3
        progressLayer.lineCap     = .round
        progressLayer.strokeEnd   = 0
        layer.addSublayer(progressLayer)

        idleRingLayer.fillColor   = UIColor.clear.cgColor
        idleRingLayer.strokeColor = UIColor.white.withAlphaComponent(0.5).cgColor
        idleRingLayer.lineWidth   = 0.5
        idleRingLayer.lineDashPattern = [2, 6]
        layer.addSublayer(idleRingLayer)

        // UIView subviews on top: pulse halo → inner shape
        pulseView.backgroundColor = recRed.withAlphaComponent(0.6)
        pulseView.isUserInteractionEnabled = false
        addSubview(pulseView)

        innerView.backgroundColor = recRed
        innerView.isUserInteractionEnabled = false
        addSubview(innerView)

        applyState(animated: false)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let c  = CGPoint(x: bounds.midX, y: bounds.midY)
        let r  = bounds.width / 2 - 6      // ring radius
        let ri = bounds.width / 2 - 2      // idle ring radius (slightly outside)

        let arc = UIBezierPath(arcCenter: c, radius: r,
                               startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: true)
        trackLayer.path    = arc.cgPath
        progressLayer.path = arc.cgPath

        let outerArc = UIBezierPath(arcCenter: c, radius: ri,
                                    startAngle: -.pi / 2, endAngle: 3 * .pi / 2, clockwise: true)
        idleRingLayer.path  = outerArc.cgPath
        idleRingLayer.frame = bounds

        applyState(animated: false)
    }

    // MARK: - State

    private func applyState(animated: Bool) {
        guard bounds.width > 0 else { return }

        accessibilityLabel = isRecording ? "Stop recording" : "Start recording"

        let idleInner  = bounds.width * 0.62
        let recInner   = bounds.width * 0.36
        let innerSize  = isRecording ? recInner  : idleInner
        let innerCorner = isRecording ? CGFloat(8) : innerSize / 2

        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let update = {
            self.innerView.bounds        = CGRect(x: 0, y: 0, width: innerSize, height: innerSize)
            self.innerView.center        = center
            self.innerView.layer.cornerRadius = innerCorner
        }

        if animated {
            UIView.animate(withDuration: 0.28, delay: 0,
                           usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5,
                           options: [], animations: update)
        } else {
            update()
        }

        if isRecording {
            idleRingLayer.removeAllAnimations()
            idleRingLayer.isHidden = true
            startPulse()
        } else {
            stopPulse()
            idleRingLayer.isHidden = false
            progressLayer.strokeEnd = 0
            startIdleSpin()
        }
    }

    // MARK: - Pulse animation

    private func startPulse() {
        pulseView.isHidden = false
        pulseView.bounds   = CGRect(x: 0, y: 0, width: bounds.width * 0.7, height: bounds.width * 0.7)
        pulseView.center   = CGPoint(x: bounds.midX, y: bounds.midY)
        pulseView.layer.cornerRadius = pulseView.bounds.width / 2

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.8
        scale.toValue   = 1.6

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.45
        opacity.toValue   = 0.0

        let group          = CAAnimationGroup()
        group.animations   = [scale, opacity]
        group.duration     = 1.4
        group.repeatCount  = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)

        pulseView.layer.add(group, forKey: "pulse")
    }

    private func stopPulse() {
        pulseView.layer.removeAllAnimations()
        pulseView.isHidden = true
    }

    // MARK: - Idle ring spin

    private func startIdleSpin() {
        let spin       = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue   = 2 * Double.pi
        spin.duration  = 14
        spin.repeatCount = .infinity
        idleRingLayer.add(spin, forKey: "spin")
    }

    // MARK: - Photo mode

    private var isPhotoMode: Bool = false

    func setPhotoMode(_ photo: Bool, animated: Bool) {
        guard isPhotoMode != photo else { return }
        isPhotoMode = photo
        let update = {
            self.innerView.backgroundColor = photo
                ? UIColor(red: 1, green: 1, blue: 1, alpha: 0.9)
                : self.recRed
            self.trackLayer.strokeColor = photo
                ? UIColor.white.withAlphaComponent(0.50).cgColor
                : UIColor.white.withAlphaComponent(0.32).cgColor
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: update)
        } else {
            update()
        }
    }

    // MARK: - Touch

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.alpha = self.isHighlighted ? 0.72 : 1.0
            }
        }
    }
}
