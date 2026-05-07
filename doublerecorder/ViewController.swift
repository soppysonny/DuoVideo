import UIKit
import AVFoundation
import CoreImage
import Photos

// MARK: - ViewController

class ViewController: UIViewController {

    // MARK: - State

    private var isFlashOn    = false
    private var isMicMuted   = false
    private var isFrontMirror = true
    private var isGridOn     = false
    private var isAELocked   = false
    private var isSwapped    = false
    private var pipCorner: PiPCorner = .bottomRight
    private var lockedOrientation: AVCaptureVideoOrientation?
    private var recordingSeconds = 0
    private var audioLevelValue: Float = 0
    private var pipIsDragging   = false
    private var pipFreeOrigin: CGPoint? = nil  // 用户拖动后的自由坐标，nil 时使用默认角落

    enum PiPCorner { case topLeft, topRight, bottomLeft, bottomRight }

    // MARK: - Business objects

    private var cameraManager: CameraManager?
    private let videoRecorder  = VideoRecorder()
    private let photoExporter  = PhotoLibraryExporter()
    private var recordingTimer: Timer?
    private var displayLink:    CADisplayLink?

    // MARK: - Background / preview

    private let backPreviewView  = CameraPreviewView()

    // MARK: - Framing overlays

    private let gridOverlayView = GridOverlayView()
    private let cornerTicksView = CornerTicksView()
    private let crosshairView   = CrosshairView()

    // MARK: - PiP (front camera preview)

    private let pipContainerView  = UIView()
    private let frontPreviewView  = CameraPreviewView()
    private let pipLabelView      = UIView()
    private let pipBottomView     = UIView()
    private let pipRecBorderLayer = CALayer()
    private let watermarkView     = PiPWatermarkView()

    // MARK: - Top HUD

    private let topHUDView    = UIView()
    private let topLeftPill   = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let topRightPill  = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let clipLabel     = UILabel()
    private let topTimerLabel = UILabel()
    private let resLabel      = UILabel()
    private let fpsLabel      = UILabel()
    private let codecLabel    = UILabel()

    // MARK: - Dynamic Island recording pill

    private let islandPillView  = UIView()
    private let islandDot       = UIView()
    private let islandTimeLabel = UILabel()
    private var islandWaveBars: [UIView] = []

    // MARK: - Side toolbar

    private let sideToolbarBlur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let flashBtn  = ToolbarButton(icon: "bolt.fill",       iconOff: "bolt.slash.fill", title: "FLASH")
    private let micBtn    = ToolbarButton(icon: "mic.fill",         iconOff: "mic.slash.fill",  title: "MIC")
    private let mirrorBtn = ToolbarButton(icon: "camera.filters",   iconOff: nil,               title: "MIRROR")
    private let gridBtn   = ToolbarButton(icon: "grid",             iconOff: nil,               title: "GRID")
    private let aeLockBtn    = ToolbarButton(icon: "lock.fill",        iconOff: "lock.open.fill",  title: "AE/AF")
    private let settingsBtn  = ToolbarButton(icon: "gearshape.fill",   iconOff: nil,               title: "SET")

    // MARK: - Bottom dock

    private let galleryThumb    = UIView()
    private let galleryCountLbl = UILabel()
    private let recordButton    = RecordButtonView()
    private let swapBtn: UIButton = {
        let b = UIButton(type: .custom)
        b.backgroundColor = UIColor(white: 0.08, alpha: 0.6)
        b.layer.cornerRadius = 22
        b.layer.borderWidth = 0.5
        b.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        b.tintColor = .white
        return b
    }()

    // MARK: - Audio meter (portrait)

    private let meterPillView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let meterLabel    = UILabel()
    private let levelMeterView = LevelMeterView()

    // MARK: - Not-supported overlay

    private let notSupportedView = UIView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(deviceOrientationChanged),
                                               name: UIDevice.orientationDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(captureModeChanged),
                                               name: .captureModeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(recordingsChanged),
                                               name: .recordingsChanged, object: nil)
        setupUI()
        checkSupportAndRequestPermissions()
    }

    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        displayLink?.invalidate()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cameraManager?.startRunning()
        syncOrientationIfNeeded()
        refreshGalleryBadge()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraManager?.stopRunning()
    }

    @objc private func deviceOrientationChanged() {
        guard lockedOrientation == nil else { return }
        syncOrientationIfNeeded()
    }

    private func syncOrientationIfNeeded() {
        guard let o = AVCaptureVideoOrientation(device: UIDevice.current.orientation) else { return }
        cameraManager?.setVideoOrientation(o)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersStatusBarHidden: Bool { true }

    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.applyLayout(for: size)
        })
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyLayout(for: view.bounds.size)
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .black

        // Back preview — full screen
        backPreviewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backPreviewView)
        NSLayoutConstraint.activate([
            backPreviewView.topAnchor.constraint(equalTo: view.topAnchor),
            backPreviewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backPreviewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backPreviewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Grid overlay (full screen, pointer events disabled)
        gridOverlayView.isHidden = true
        gridOverlayView.isUserInteractionEnabled = false
        gridOverlayView.frame = view.bounds
        gridOverlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(gridOverlayView)

        // Corner ticks
        cornerTicksView.isUserInteractionEnabled = false
        cornerTicksView.frame = view.bounds
        cornerTicksView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(cornerTicksView)

        // Crosshair
        crosshairView.isUserInteractionEnabled = false
        view.addSubview(crosshairView)

        setupPiP()
        setupTopHUD()
        setupIslandPill()
        setupSideToolbar()
        setupBottomDock()
        setupAudioMeter()
        setupNotSupported()

        // position on first pass
        applyLayout(for: view.bounds.size)
    }

    // MARK: - PiP Setup

    private func setupPiP() {
        pipContainerView.layer.cornerRadius = 16
        pipContainerView.clipsToBounds      = true
        pipContainerView.layer.borderWidth  = 0.5
        pipContainerView.layer.borderColor  = UIColor.white.withAlphaComponent(0.25).cgColor
        view.addSubview(pipContainerView)

        frontPreviewView.frame = CGRect(origin: .zero, size: CGSize(width: 100, height: 133))
        frontPreviewView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pipContainerView.addSubview(frontPreviewView)

        // Top label bar gradient
        let topGrad = CAGradientLayer()
        topGrad.colors = [UIColor.black.withAlphaComponent(0.65).cgColor,
                          UIColor.clear.cgColor]
        topGrad.locations = [0, 1]
        topGrad.frame = CGRect(x: 0, y: 0, width: 200, height: 28)
        pipLabelView.layer.addSublayer(topGrad)
        pipLabelView.frame = CGRect(x: 0, y: 0, width: 200, height: 28)
        pipLabelView.isUserInteractionEnabled = false
        pipContainerView.addSubview(pipLabelView)

        // Amber dot
        let dot = UIView()
        dot.backgroundColor = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1)
        dot.layer.cornerRadius = 2.5
        dot.frame = CGRect(x: 8, y: 9, width: 5, height: 5)
        dot.layer.shadowColor  = dot.backgroundColor?.cgColor
        dot.layer.shadowRadius = 4
        dot.layer.shadowOpacity = 0.9
        dot.layer.shadowOffset = .zero
        pipLabelView.addSubview(dot)

        // "FRONT · F1.9"
        let frontLabel = UILabel()
        frontLabel.text = "FRONT · F1.9"
        frontLabel.font = UIFont.monospacedSystemFont(ofSize: 8, weight: .semibold)
        frontLabel.textColor = UIColor.white.withAlphaComponent(0.95)
        frontLabel.sizeToFit()
        frontLabel.frame.origin = CGPoint(x: 18, y: 8)
        pipLabelView.addSubview(frontLabel)

        // Drag dots
        let dragDots = DragDotsView()
        dragDots.frame = CGRect(x: 0, y: 0, width: 11, height: 14)
        pipLabelView.addSubview(dragDots)

        // Bottom mini-HUD
        let bottomGrad = CAGradientLayer()
        bottomGrad.colors = [UIColor.clear.cgColor,
                             UIColor.black.withAlphaComponent(0.7).cgColor]
        bottomGrad.locations = [0, 1]
        bottomGrad.frame = CGRect(x: 0, y: 0, width: 200, height: 26)
        pipBottomView.layer.addSublayer(bottomGrad)
        pipBottomView.isUserInteractionEnabled = false
        pipContainerView.addSubview(pipBottomView)

        let mirrorStateLabel = UILabel()
        mirrorStateLabel.tag = 1001
        mirrorStateLabel.font = UIFont.monospacedSystemFont(ofSize: 8, weight: .semibold)
        mirrorStateLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        mirrorStateLabel.text = "MIRROR"
        mirrorStateLabel.frame = CGRect(x: 8, y: 6, width: 60, height: 12)
        pipBottomView.addSubview(mirrorStateLabel)

        let micStateLabel = UILabel()
        micStateLabel.tag = 1002
        micStateLabel.font = UIFont.monospacedSystemFont(ofSize: 8, weight: .semibold)
        micStateLabel.textColor = UIColor(red: 0.204, green: 0.78, blue: 0.349, alpha: 1)
        micStateLabel.text = "MIC"
        micStateLabel.sizeToFit()
        pipBottomView.addSubview(micStateLabel)

        // Recording red border layer
        pipRecBorderLayer.borderColor = UIColor(red: 1, green: 0.231, blue: 0.188, alpha: 0.85).cgColor
        pipRecBorderLayer.borderWidth = 1.5
        pipRecBorderLayer.opacity     = 0
        pipContainerView.layer.addSublayer(pipRecBorderLayer)

        // Watermark overlay (hidden for pro users)
        watermarkView.isHidden = AppSettings.shared.isProUser
        watermarkView.isUserInteractionEnabled = false
        pipContainerView.addSubview(watermarkView)

        // Drag gesture (only when not recording)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePiPDrag(_:)))
        pipContainerView.addGestureRecognizer(pan)

        // clipsToBounds must stay true for corner rounding; shadow is achieved via border only
    }

    // MARK: - Top HUD Setup

    private func setupTopHUD() {
        topHUDView.isUserInteractionEnabled = false
        view.addSubview(topHUDView)

        func pill(blur: UIVisualEffectView) {
            blur.layer.cornerRadius = 6
            blur.layer.masksToBounds = true
            blur.layer.borderWidth = 0.5
            blur.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
            topHUDView.addSubview(blur)
        }
        pill(blur: topLeftPill)
        pill(blur: topRightPill)

        clipLabel.text = "CLIP·001"
        clipLabel.font = UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        clipLabel.textColor = UIColor.white.withAlphaComponent(0.38)
        topLeftPill.contentView.addSubview(clipLabel)

        // vertical separator
        let sep = UIView()
        sep.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        sep.tag = 801
        topLeftPill.contentView.addSubview(sep)

        topTimerLabel.text = "00:00"
        topTimerLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        topTimerLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        topTimerLabel.tag = 802
        topLeftPill.contentView.addSubview(topTimerLabel)

        resLabel.text = "4K"
        resLabel.font = UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        resLabel.textColor = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1)
        topRightPill.contentView.addSubview(resLabel)

        let sep2 = UIView(); sep2.backgroundColor = UIColor.white.withAlphaComponent(0.10); sep2.tag = 811
        topRightPill.contentView.addSubview(sep2)
        fpsLabel.text = "30P"
        fpsLabel.font = UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        fpsLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        topRightPill.contentView.addSubview(fpsLabel)

        let sep3 = UIView(); sep3.backgroundColor = UIColor.white.withAlphaComponent(0.10); sep3.tag = 812
        topRightPill.contentView.addSubview(sep3)
        codecLabel.text = "HEVC"
        codecLabel.font = UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        codecLabel.textColor = UIColor(red: 0.204, green: 0.78, blue: 0.349, alpha: 1)
        topRightPill.contentView.addSubview(codecLabel)
    }

    // MARK: - Dynamic Island Pill Setup

    private func setupIslandPill() {
        islandPillView.backgroundColor = .black
        islandPillView.layer.cornerRadius = 24
        islandPillView.layer.shadowColor  = UIColor(red: 1, green: 0.231, blue: 0.188, alpha: 0.18).cgColor
        islandPillView.layer.shadowRadius = 20
        islandPillView.layer.shadowOpacity = 1
        islandPillView.layer.shadowOffset  = .zero
        islandPillView.isHidden = true
        view.addSubview(islandPillView)

        // REC dot
        islandDot.backgroundColor = UIColor(red: 1, green: 0.231, blue: 0.188, alpha: 1)
        islandDot.layer.cornerRadius = 4
        islandDot.layer.shadowColor = UIColor(red: 1, green: 0.231, blue: 0.188, alpha: 1).cgColor
        islandDot.layer.shadowRadius = 6
        islandDot.layer.shadowOpacity = 1
        islandDot.layer.shadowOffset  = .zero
        islandPillView.addSubview(islandDot)

        let recLabel = UILabel()
        recLabel.text = "REC"
        recLabel.font = UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        recLabel.textColor = UIColor(red: 1, green: 0.231, blue: 0.188, alpha: 1)
        recLabel.tag = 901
        islandPillView.addSubview(recLabel)

        islandTimeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        islandTimeLabel.textColor = .white
        islandPillView.addSubview(islandTimeLabel)

        // Waveform bars (5 bars)
        for _ in 0..<5 {
            let bar = UIView()
            bar.backgroundColor = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1)
            bar.layer.cornerRadius = 1
            islandWaveBars.append(bar)
            islandPillView.addSubview(bar)
        }
    }

    // MARK: - Side Toolbar Setup

    private func setupSideToolbar() {
        sideToolbarBlur.layer.cornerRadius = 14
        sideToolbarBlur.layer.masksToBounds = true
        sideToolbarBlur.layer.borderWidth = 0.5
        sideToolbarBlur.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
        view.addSubview(sideToolbarBlur)

        for (btn, sel) in [
            (flashBtn,    #selector(handleFlash)),
            (micBtn,      #selector(handleMic)),
            (mirrorBtn,   #selector(handleMirror)),
            (gridBtn,     #selector(handleGrid)),
            (aeLockBtn,   #selector(handleAELock)),
            (settingsBtn, #selector(handleSettings)),
        ] as [(ToolbarButton, Selector)] {
            btn.addTarget(self, action: sel, for: .touchUpInside)
            sideToolbarBlur.contentView.addSubview(btn)
        }

        // Initial active states
        mirrorBtn.isActive = isFrontMirror
    }

    // MARK: - Bottom Dock Setup

    private func setupBottomDock() {
        // Gallery thumbnail
        galleryThumb.backgroundColor = UIColor(red: 0.1, green: 0.067, blue: 0.05, alpha: 1)
        galleryThumb.layer.cornerRadius = 10
        galleryThumb.layer.borderWidth = 0.5
        galleryThumb.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        galleryThumb.isUserInteractionEnabled = true
        let tapGallery = UITapGestureRecognizer(target: self, action: #selector(handleGallery))
        galleryThumb.addGestureRecognizer(tapGallery)
        view.addSubview(galleryThumb)

        // "3" badge
        galleryCountLbl.text = "0"
        galleryCountLbl.isHidden = true
        galleryCountLbl.font = UIFont.monospacedSystemFont(ofSize: 8, weight: .semibold)
        galleryCountLbl.textColor = .white
        galleryCountLbl.backgroundColor = UIColor(red: 1, green: 0.231, blue: 0.188, alpha: 1)
        galleryCountLbl.layer.cornerRadius = 2
        galleryCountLbl.clipsToBounds = true
        galleryCountLbl.textAlignment = .center
        galleryCountLbl.frame = CGRect(x: 0, y: 0, width: 14, height: 14)
        galleryThumb.addSubview(galleryCountLbl)

        let galleryLbl = UILabel()
        galleryLbl.text = "LAST"
        galleryLbl.font = UIFont.monospacedSystemFont(ofSize: 8, weight: .semibold)
        galleryLbl.textColor = UIColor.white.withAlphaComponent(0.38)
        galleryLbl.tag = 701
        view.addSubview(galleryLbl)

        // Record button
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        view.addSubview(recordButton)

        // Swap button
        let swapIcon = UIImage(systemName: "arrow.triangle.2.circlepath.camera.fill")
        swapBtn.setImage(swapIcon, for: .normal)
        swapBtn.tintColor = .white
        swapBtn.addTarget(self, action: #selector(handleSwap), for: .touchUpInside)
        view.addSubview(swapBtn)

        let swapLbl = UILabel()
        swapLbl.text = "SWAP"
        swapLbl.font = UIFont.monospacedSystemFont(ofSize: 8, weight: .semibold)
        swapLbl.textColor = UIColor.white.withAlphaComponent(0.38)
        swapLbl.tag = 702
        view.addSubview(swapLbl)
    }

    // MARK: - Audio Meter Setup

    private func setupAudioMeter() {
        meterPillView.layer.cornerRadius = 6
        meterPillView.layer.masksToBounds = true
        meterPillView.layer.borderWidth = 0.5
        meterPillView.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
        view.addSubview(meterPillView)

        meterLabel.font = UIFont.monospacedSystemFont(ofSize: 8, weight: .semibold)
        meterLabel.textColor = UIColor.white.withAlphaComponent(0.38)
        meterLabel.text = "AUDIO"
        meterPillView.contentView.addSubview(meterLabel)

        meterPillView.contentView.addSubview(levelMeterView)
    }

    // MARK: - Not Supported

    private func setupNotSupported() {
        notSupportedView.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        notSupportedView.isHidden = true
        notSupportedView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(notSupportedView)
        NSLayoutConstraint.activate([
            notSupportedView.topAnchor.constraint(equalTo: view.topAnchor),
            notSupportedView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            notSupportedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            notSupportedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        let label = UILabel()
        label.text = "您的设备不支持双摄录制\n（需要 iPhone 11 Pro 或更新机型）"
        label.textColor = .white
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        notSupportedView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: notSupportedView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: notSupportedView.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: notSupportedView.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: notSupportedView.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Layout

    private func applyLayout(for size: CGSize) {
        let isLandscape = size.width > size.height
        let safe = view.safeAreaInsets
        let shorter = min(size.width, size.height)

        layoutTopHUD(size: size, isLandscape: isLandscape, safe: safe)
        layoutIslandPill(size: size, isLandscape: isLandscape)
        layoutSideToolbar(size: size, isLandscape: isLandscape, safe: safe)
        layoutBottomDock(size: size, isLandscape: isLandscape, safe: safe, shorter: shorter)
        layoutPiP(size: size, isLandscape: isLandscape, safe: safe, shorter: shorter)
        layoutAudioMeter(size: size, isLandscape: isLandscape, safe: safe)
        layoutCrosshair(size: size)
        applyOverlapFade(animated: false)
    }

    private func layoutTopHUD(size: CGSize, isLandscape: Bool, safe: UIEdgeInsets) {
        let topY: CGFloat = isLandscape ? safe.top + 18 : safe.top + 56
        let hPad: CGFloat = isLandscape ? 22 : 16
        let pillH: CGFloat = 30

        topHUDView.frame = CGRect(x: hPad, y: topY, width: size.width - hPad * 2, height: pillH)

        // Layout left pill
        clipLabel.sizeToFit()
        topTimerLabel.sizeToFit()
        let leftW = clipLabel.frame.width + 1 + topTimerLabel.frame.width + 28
        topLeftPill.frame = CGRect(x: 0, y: 0, width: leftW, height: pillH)

        clipLabel.frame = CGRect(x: 10, y: (pillH - 12) / 2, width: clipLabel.frame.width, height: 12)
        let sep = topLeftPill.contentView.viewWithTag(801)!
        sep.frame = CGRect(x: clipLabel.frame.maxX + 8, y: 8, width: 0.5, height: pillH - 16)
        topTimerLabel.frame = CGRect(x: sep.frame.maxX + 8, y: (pillH - 14) / 2,
                                     width: topTimerLabel.frame.width, height: 14)

        // Layout right pill
        resLabel.sizeToFit(); fpsLabel.sizeToFit(); codecLabel.sizeToFit()
        let rightW = resLabel.frame.width + fpsLabel.frame.width + codecLabel.frame.width + 50
        topRightPill.frame = CGRect(x: topHUDView.frame.width - rightW, y: 0, width: rightW, height: pillH)

        resLabel.frame = CGRect(x: 10, y: (pillH - 12) / 2, width: resLabel.frame.width, height: 12)
        let sep2 = topRightPill.contentView.viewWithTag(811)!
        sep2.frame = CGRect(x: resLabel.frame.maxX + 8, y: 8, width: 0.5, height: pillH - 16)
        fpsLabel.frame = CGRect(x: sep2.frame.maxX + 8, y: (pillH - 12) / 2, width: fpsLabel.frame.width, height: 12)
        let sep3 = topRightPill.contentView.viewWithTag(812)!
        sep3.frame = CGRect(x: fpsLabel.frame.maxX + 8, y: 8, width: 0.5, height: pillH - 16)
        codecLabel.frame = CGRect(x: sep3.frame.maxX + 8, y: (pillH - 12) / 2, width: codecLabel.frame.width, height: 12)
    }

    private func layoutIslandPill(size: CGSize, isLandscape: Bool) {
        let pillH: CGFloat = 37
        let pillW: CGFloat = 220
        let x = (size.width - pillW) / 2
        // 灵动岛机型 safeAreaInsets.top >= 59，pill 与灵动岛重叠（y=11）
        // 刘海屏 / 无刘海屏：pill 紧贴安全区下方，避免被遮挡
        let safeTop = view.safeAreaInsets.top
        let y: CGFloat = safeTop >= 59 ? 11 : safeTop + 6
        islandPillView.frame = CGRect(x: x, y: y, width: pillW, height: pillH)
        islandPillView.layer.cornerRadius = pillH / 2

        // Inner layout: [dot recLabel] [timer] [wavebars]
        islandDot.frame = CGRect(x: 14, y: (pillH - 8) / 2, width: 8, height: 8)
        let recLbl = islandPillView.viewWithTag(901) as? UILabel
        recLbl?.sizeToFit()
        recLbl?.frame.origin = CGPoint(x: islandDot.frame.maxX + 5, y: (pillH - (recLbl?.frame.height ?? 12)) / 2)

        islandTimeLabel.sizeToFit()
        islandTimeLabel.center = CGPoint(x: pillW / 2, y: pillH / 2)

        // Waveform bars (right side)
        let barW: CGFloat = 2
        let barGap: CGFloat = 3
        let totalBarsW = CGFloat(islandWaveBars.count) * barW + CGFloat(islandWaveBars.count - 1) * barGap
        let barsStartX = pillW - 14 - totalBarsW
        for (i, bar) in islandWaveBars.enumerated() {
            let h: CGFloat = 8
            bar.frame = CGRect(x: barsStartX + CGFloat(i) * (barW + barGap),
                               y: (pillH - h) / 2, width: barW, height: h)
        }
    }

    private func layoutSideToolbar(size: CGSize, isLandscape: Bool, safe: UIEdgeInsets) {
        let btnW: CGFloat  = 40
        let btnH: CGFloat  = ToolbarButton.totalHeight  // icon(40) + gap(3) + label(10) = 53
        let gap: CGFloat   = 5
        let padding: CGFloat = 6
        let count          = CGFloat(6)
        let buttons        = [flashBtn, micBtn, mirrorBtn, gridBtn, aeLockBtn, settingsBtn] as [UIView]

        if isLandscape {
            let dockW: CGFloat    = 110
            let leftClear: CGFloat = safe.left + 60
            let totalW = count * btnW + (count - 1) * gap + padding * 2
            let toolbarH = btnH + padding * 2
            let toolbarX = leftClear + (size.width - leftClear - dockW - totalW) / 2
            let toolbarY = size.height - safe.bottom - 18 - toolbarH
            sideToolbarBlur.frame = CGRect(x: toolbarX, y: toolbarY, width: totalW, height: toolbarH)

            for (i, btn) in buttons.enumerated() {
                btn.frame = CGRect(x: padding + CGFloat(i) * (btnW + gap), y: padding,
                                   width: btnW, height: btnH)
            }
        } else {
            let totalH   = count * btnH + (count - 1) * gap + padding * 2
            let toolbarW = btnW + padding * 2
            let toolbarX = size.width - safe.right - 14 - toolbarW
            let toolbarY = (size.height - totalH) / 2
            sideToolbarBlur.frame = CGRect(x: toolbarX, y: toolbarY, width: toolbarW, height: totalH)

            for (i, btn) in buttons.enumerated() {
                btn.frame = CGRect(x: padding, y: padding + CGFloat(i) * (btnH + gap),
                                   width: btnW, height: btnH)
            }
        }
    }

    private func layoutBottomDock(size: CGSize, isLandscape: Bool, safe: UIEdgeInsets, shorter: CGFloat) {
        let recSize: CGFloat = isLandscape ? 70 : 76
        let auxSize: CGFloat = 44

        if isLandscape {
            // Right column
            let dockW: CGFloat = 110
            let dockH = size.height
            let dockX = size.width - safe.right - dockW
            let cx = dockX + dockW / 2
            let padV: CGFloat = 40
            // Record in center
            recordButton.frame = CGRect(x: dockX + (dockW - recSize) / 2, y: (dockH - recSize) / 2,
                                        width: recSize, height: recSize)
            // Gallery top
            galleryThumb.frame = CGRect(x: dockX + (dockW - auxSize) / 2, y: padV, width: auxSize, height: auxSize)
            galleryCountLbl.frame = CGRect(x: auxSize - 14 - 2, y: auxSize - 14 - 2, width: 14, height: 14)
            if let lbl = view.viewWithTag(701) as? UILabel {
                lbl.sizeToFit()
                lbl.center = CGPoint(x: cx, y: galleryThumb.frame.maxY + 8)
            }
            // Swap bottom
            swapBtn.frame = CGRect(x: dockX + (dockW - auxSize) / 2, y: dockH - padV - auxSize, width: auxSize, height: auxSize)
            swapBtn.layer.cornerRadius = auxSize / 2
            if let lbl = view.viewWithTag(702) as? UILabel {
                lbl.sizeToFit()
                lbl.center = CGPoint(x: cx, y: swapBtn.frame.maxY + 8)
            }
        } else {
            // Bottom row
            let dockH: CGFloat = 138
            let dockY = size.height - safe.bottom - dockH
            let cy = dockY + dockH / 2
            let padH: CGFloat = 40
            // Record center
            recordButton.frame = CGRect(x: (size.width - recSize) / 2, y: dockY + (dockH - recSize) / 2,
                                        width: recSize, height: recSize)
            // Gallery left
            galleryThumb.frame = CGRect(x: padH, y: cy - auxSize / 2, width: auxSize, height: auxSize)
            galleryCountLbl.frame = CGRect(x: auxSize - 14 - 2, y: auxSize - 14 - 2, width: 14, height: 14)
            if let lbl = view.viewWithTag(701) as? UILabel {
                lbl.sizeToFit()
                lbl.center = CGPoint(x: galleryThumb.center.x, y: galleryThumb.frame.maxY + 8)
            }
            // Swap right
            swapBtn.frame = CGRect(x: size.width - padH - auxSize, y: cy - auxSize / 2, width: auxSize, height: auxSize)
            swapBtn.layer.cornerRadius = auxSize / 2
            if let lbl = view.viewWithTag(702) as? UILabel {
                lbl.sizeToFit()
                lbl.center = CGPoint(x: swapBtn.center.x, y: swapBtn.frame.maxY + 8)
            }
        }
    }

    private func layoutPiP(size: CGSize, isLandscape: Bool, safe: UIEdgeInsets, shorter: CGFloat) {
        guard !pipIsDragging else { return }

        let pipW = shorter * 0.30
        let pipH = pipW * 4.0 / 3.0
        pipContainerView.bounds = CGRect(x: 0, y: 0, width: pipW, height: pipH)

        let margins = isLandscape
            ? PiPMargins(top: safe.top + 14, bottom: safe.bottom + 80, left: safe.left + 60, right: safe.right + 130)
            : PiPMargins(top: safe.top + 8, bottom: safe.bottom + 150, left: 8, right: 8)

        if let freeOrigin = pipFreeOrigin {
            // 保持用户拖动后的自由坐标，旋转时做边界裁剪避免越界
            let clamped = CGPoint(
                x: min(max(freeOrigin.x, 0), size.width  - pipW),
                y: min(max(freeOrigin.y, 0), size.height - pipH)
            )
            pipContainerView.frame.origin = clamped
            pipFreeOrigin = clamped
            let normX = Float(clamped.x / size.width)
            let normY = Float(clamped.y / size.height)
            videoRecorder.updatePiPOrigin(normalizedX: normX, normalizedY: normY)
        } else {
            snapPiP(to: pipCorner, size: size, pipSize: CGSize(width: pipW, height: pipH),
                    margins: margins, animated: false)
        }

        updateWatermarkPosition()

        // Update PiP internal overlay frames
        pipLabelView.frame = CGRect(x: 0, y: 0, width: pipW, height: 28)
        // Update gradient sublayers (not subviews)
        pipLabelView.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.forEach {
            $0.frame = CGRect(x: 0, y: 0, width: pipW, height: 28)
        }
        if let dragDots = pipLabelView.subviews.first(where: { $0 is DragDotsView }) {
            dragDots.frame = CGRect(x: pipW - 8 - dragDots.bounds.width, y: (28 - 14) / 2,
                                    width: dragDots.bounds.width, height: dragDots.bounds.height)
        }
        pipBottomView.frame = CGRect(x: 0, y: pipH - 26, width: pipW, height: 26)
        pipBottomView.layer.sublayers?.compactMap { $0 as? CAGradientLayer }.forEach {
            $0.frame = CGRect(x: 0, y: 0, width: pipW, height: 26)
        }
        if let micLbl = pipBottomView.viewWithTag(1002) as? UILabel {
            micLbl.sizeToFit()
            micLbl.frame.origin = CGPoint(x: pipW - 8 - micLbl.frame.width, y: 6)
        }
        pipRecBorderLayer.frame = CGRect(x: 0, y: 0, width: pipW, height: pipH)
        pipRecBorderLayer.cornerRadius = 16
    }

    private func layoutAudioMeter(size: CGSize, isLandscape: Bool, safe: UIEdgeInsets) {
        meterPillView.isHidden = isLandscape
        guard !isLandscape else { return }
        let pillW: CGFloat = 66
        let pillH: CGFloat = 42
        let x = safe.left + 16
        let y = size.height - safe.bottom - 138 - 8 - pillH // just above bottom dock
        meterPillView.frame = CGRect(x: x, y: y, width: pillW, height: pillH)

        meterLabel.sizeToFit()
        meterLabel.frame = CGRect(x: 8, y: 7, width: meterLabel.frame.width, height: 12)
        levelMeterView.frame = CGRect(x: 8, y: meterLabel.frame.maxY + 4, width: pillW - 16, height: 10)
    }

    private func layoutCrosshair(size: CGSize) {
        let s: CGFloat = 28
        crosshairView.frame = CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2, width: s, height: s)
        (crosshairView as? CrosshairView)?.setNeedsDisplay()
    }

    // MARK: - Snap helpers

    struct PiPMargins { var top, bottom, left, right: CGFloat }

    private func pipPosition(for corner: PiPCorner, size: CGSize, pipSize: CGSize,
                              margins: PiPMargins) -> CGPoint {
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeft:
            x = margins.left
            y = margins.top
        case .topRight:
            x = size.width - pipSize.width - margins.right
            y = margins.top
        case .bottomLeft:
            x = margins.left
            y = size.height - pipSize.height - margins.bottom
        case .bottomRight:
            x = size.width - pipSize.width - margins.right
            y = size.height - pipSize.height - margins.bottom
        }
        return CGPoint(x: x, y: y)
    }

    private func snapPiP(to corner: PiPCorner, size: CGSize? = nil, pipSize: CGSize? = nil,
                          margins: PiPMargins? = nil, animated: Bool = true) {
        pipCorner = corner
        let s   = size    ?? view.bounds.size
        let ps  = pipSize ?? pipContainerView.bounds.size
        let isL = s.width > s.height
        let safe = view.safeAreaInsets
        let m = margins ?? (isL
            ? PiPMargins(top: safe.top + 14, bottom: safe.bottom + 80, left: safe.left + 60, right: safe.right + 130)
            : PiPMargins(top: safe.top + 8, bottom: safe.bottom + 150, left: 8, right: 8))

        let origin = pipPosition(for: corner, size: s, pipSize: ps, margins: m)

        // 同步合成视频里的 PiP 叠层位置（归一化坐标）
        let normX = Float(origin.x / s.width)
        let normY = Float(origin.y / s.height)
        videoRecorder.updatePiPOrigin(normalizedX: normX, normalizedY: normY)

        if animated {
            UIView.animate(withDuration: 0.22, delay: 0,
                           usingSpringWithDamping: 0.75, initialSpringVelocity: 0.3) {
                self.pipContainerView.frame.origin = origin
                self.updateWatermarkPosition()
            } completion: { _ in
                self.applyOverlapFade()
            }
        } else {
            pipContainerView.frame.origin = origin
            updateWatermarkPosition()
        }
    }

    // PiP 停止后检测重叠 view 并设为半透明
    private func applyOverlapFade(animated: Bool = true) {
        let pipFrame = pipContainerView.frame
        let overlapsTop     = pipFrame.intersects(topHUDView.frame)
        let overlapsMeter   = !meterPillView.isHidden && pipFrame.intersects(meterPillView.frame)
        let overlapsToolbar = pipFrame.intersects(sideToolbarBlur.frame)

        let block = {
            self.topHUDView.alpha      = overlapsTop     ? 0.25 : 1.0
            self.meterPillView.alpha   = overlapsMeter   ? 0.25 : 1.0
            self.sideToolbarBlur.alpha = overlapsToolbar ? 0.25 : 1.0
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: block)
        } else {
            block()
        }
    }

    private func updateWatermarkPosition() {
        let pw = pipContainerView.bounds.width
        let ph = pipContainerView.bounds.height
        guard pw > 0, ph > 0 else { return }
        watermarkView.isHidden = AppSettings.shared.isProUser
        guard !watermarkView.isHidden else { return }
        let sz  = watermarkView.preferredSize
        let pad: CGFloat = 6
        switch pipCorner {
        case .bottomRight: watermarkView.frame = CGRect(x: pad,              y: pad,              width: sz.width, height: sz.height)
        case .bottomLeft:  watermarkView.frame = CGRect(x: pw - sz.width - pad, y: pad,              width: sz.width, height: sz.height)
        case .topRight:    watermarkView.frame = CGRect(x: pad,              y: ph - sz.height - pad, width: sz.width, height: sz.height)
        case .topLeft:     watermarkView.frame = CGRect(x: pw - sz.width - pad, y: ph - sz.height - pad, width: sz.width, height: sz.height)
        }
    }

    // MARK: - PiP Drag

    @objc private func handlePiPDrag(_ g: UIPanGestureRecognizer) {
        guard videoRecorder.state != .recording else { return }

        switch g.state {
        case .began:
            pipIsDragging = true
            UIView.animate(withDuration: 0.16) {
                self.pipContainerView.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
                self.pipContainerView.layer.borderColor = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 0.7).cgColor
            }
        case .changed:
            let t = g.translation(in: view)
            pipContainerView.center = CGPoint(x: pipContainerView.center.x + t.x,
                                               y: pipContainerView.center.y + t.y)
            g.setTranslation(.zero, in: view)
        case .ended, .cancelled:
            pipIsDragging = false
            UIView.animate(withDuration: 0.16) {
                self.pipContainerView.transform = .identity
                self.pipContainerView.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
            }
            // 更新象限用于水印位置和合成视频同步，但不做吸附
            let center = pipContainerView.center
            let isLeft = center.x < view.bounds.midX
            let isTop  = center.y < view.bounds.midY
            switch (isTop, isLeft) {
            case (true,  true):  pipCorner = .topLeft
            case (true,  false): pipCorner = .topRight
            case (false, true):  pipCorner = .bottomLeft
            case (false, false): pipCorner = .bottomRight
            }
            pipFreeOrigin = pipContainerView.frame.origin
            updateWatermarkPosition()
            let origin = pipContainerView.frame.origin
            let normX = Float(origin.x / view.bounds.width)
            let normY = Float(origin.y / view.bounds.height)
            videoRecorder.updatePiPOrigin(normalizedX: normX, normalizedY: normY)
            applyOverlapFade()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        default: break
        }
    }

    // MARK: - Camera Setup

    private func checkSupportAndRequestPermissions() {
        guard #available(iOS 13.0, *) else { showNotSupported(); return }
        guard CameraManager.isMultiCamSupported else { showNotSupported(); return }
        PermissionManager.shared.requestAllPermissions { [weak self] granted in
            guard let self else { return }
            granted ? self.setupCamera() : self.showPermissionDeniedAlert()
        }
    }

    @available(iOS 13.0, *)
    private func setupCamera() {
        let mgr = CameraManager()
        mgr.delegate = self
        cameraManager = mgr

        mgr.configure { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                if let bl = mgr.backPreviewLayer  { self.backPreviewView.attachPreviewLayer(bl) }
                if let fl = mgr.frontPreviewLayer { self.frontPreviewView.attachPreviewLayer(fl) }
                mgr.startRunning()
                mgr.setFrontMirror(self.isFrontMirror)
                self.syncOrientationIfNeeded()
            case .failure(let err):
                self.showAlert(title: "摄像头初始化失败", message: err.localizedDescription)
            }
        }
    }

    // MARK: - Recording

    @objc private func recordButtonTapped() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if AppSettings.shared.captureMode == .photo {
            takePhoto()
            return
        }
        if videoRecorder.state == .recording {
            stopRecording()
        } else if videoRecorder.state == .idle {
            startRecording()
        }
    }

    private func startRecording() {
        let orientation = AVCaptureVideoOrientation(device: UIDevice.current.orientation) ?? .portrait
        lockedOrientation = orientation
        cameraManager?.setVideoOrientation(orientation)
        videoRecorder.isMicMuted    = isMicMuted
        videoRecorder.saveComposite = AppSettings.shared.saveComposite
        videoRecorder.saveBack      = AppSettings.shared.saveBack
        videoRecorder.saveFront     = AppSettings.shared.saveFront

        do {
            try videoRecorder.startRecording()
        } catch {
            lockedOrientation = nil
            showAlert(title: "录制启动失败", message: error.localizedDescription)
            return
        }

        recordButton.isRecording = true
        setRecordingUI(true)
        startTimer()
        startDisplayLink()

        // Lock PiP during recording
        UIView.animate(withDuration: 0.2) {
            self.pipRecBorderLayer.opacity = 1
        }
    }

    private func stopRecording() {
        lockedOrientation = nil
        stopTimer()
        stopDisplayLink()
        recordButton.isEnabled = false

        UIView.animate(withDuration: 0.2) { self.pipRecBorderLayer.opacity = 0 }

        videoRecorder.stopRecording { [weak self] result in
            guard let self else { return }
            self.recordButton.isEnabled  = true
            self.recordButton.isRecording = false
            self.setRecordingUI(false)

            switch result {
            case .success(let session): self.saveSession(session)
            case .failure(let err):    self.showAlert(title: "录制失败", message: err.localizedDescription)
            }
        }
    }

    private func saveSession(_ session: RecordingSession) {
        // 文件保留在沙盒供应用内画廊使用，同时异步导出到系统相册
        photoExporter.exportSession(session) { [weak self] result in
            if case .failure(let err) = result {
                self?.showAlert(title: "导出相册失败", message: err.localizedDescription)
            }
        }
        refreshGalleryBadge()
    }

    private func refreshGalleryBadge() {
        let count = RecordingsListViewController.sessionCount()
        galleryCountLbl.isHidden = count == 0
        galleryCountLbl.text     = "\(min(count, 99))"
    }

    // MARK: - Timer / DisplayLink

    private func startTimer() {
        recordingSeconds = 0
        updateTimerLabels()
        recordingTimer = Timer.scheduledTimer(timeInterval: 1, target: self,
                                              selector: #selector(timerTick), userInfo: nil, repeats: true)
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    @objc private func timerTick() {
        recordingSeconds += 1
        updateTimerLabels()
        // Update record button progress ring (max 10 min = 600s)
        recordButton.progress = min(CGFloat(recordingSeconds) / 600.0, 1.0)
    }

    private func updateTimerLabels() {
        let m = recordingSeconds / 60
        let s = recordingSeconds % 60
        let text = String(format: "%02d:%02d", m, s)
        topTimerLabel.text = text
        topTimerLabel.textColor = videoRecorder.state == .recording
            ? UIColor(red: 1, green: 0.231, blue: 0.188, alpha: 1)
            : UIColor.white.withAlphaComponent(0.62)

        // Island pill timer (cs simulated at 0)
        let cs = (Int(Date().timeIntervalSince1970 * 100)) % 100
        islandTimeLabel.text = String(format: "%02d:%02d.%02d", m, s, cs)
        islandTimeLabel.sizeToFit()
        islandTimeLabel.center = CGPoint(x: islandPillView.bounds.midX, y: islandPillView.bounds.midY)
    }

    // MARK: - DisplayLink (audio level + waveform animation)

    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkTick))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        levelMeterView.level = 0
        animateWaveBars(level: 0)
    }

    @objc private func displayLinkTick() {
        // Smoothly track the captured audio level
        let target: Float = isMicMuted ? 0 : audioLevelValue
        levelMeterView.level += (target - levelMeterView.level) * 0.2
        animateWaveBars(level: CGFloat(levelMeterView.level))
        updateAELabel()
    }

    private func animateWaveBars(level: CGFloat) {
        let now = CACurrentMediaTime()
        for (i, bar) in islandWaveBars.enumerated() {
            let phase = now * 3 + Double(i) * 1.3
            let h: CGFloat = 4 + abs(CGFloat(sin(phase))) * 12 * level
            var f = bar.frame
            f.size.height = max(2, h)
            f.origin.y = (islandPillView.bounds.height - f.height) / 2
            bar.frame = f
        }
    }

    private func updateAELabel() {
        meterLabel.text = isAELocked ? "AE/AF" : "AUDIO"
        meterLabel.textColor = isAELocked
            ? UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1)
            : UIColor.white.withAlphaComponent(0.38)
    }

    // MARK: - Recording UI State

    private func setRecordingUI(_ rec: Bool) {
        islandPillView.isHidden = !rec
        if rec { animateIslandIn() }
        if rec { startIslandDotBlink() } else { islandDot.layer.removeAllAnimations() }

        UIView.animate(withDuration: 0.22, animations: {
            let alpha: CGFloat = rec ? 0 : 1
            self.sideToolbarBlur.alpha = alpha
            self.galleryThumb.alpha    = alpha
            self.swapBtn.alpha         = alpha
            if let lbl = self.view.viewWithTag(701) { lbl.alpha = alpha }
            if let lbl = self.view.viewWithTag(702) { lbl.alpha = alpha }
        }, completion: { _ in
            if !rec { self.applyOverlapFade() }
        })
        sideToolbarBlur.isUserInteractionEnabled = !rec
        galleryThumb.isUserInteractionEnabled    = !rec
        swapBtn.isUserInteractionEnabled         = !rec
    }

    private func animateIslandIn() {
        islandPillView.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        islandPillView.alpha = 0
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            self.islandPillView.transform = .identity
            self.islandPillView.alpha = 1
        }
    }

    private func startIslandDotBlink() {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue   = 0.35
        anim.duration  = 1.0
        anim.autoreverses = true
        anim.repeatCount  = .infinity
        islandDot.layer.add(anim, forKey: "blink")
    }

    // MARK: - Control Actions

    @objc private func handleFlash() {
        isFlashOn.toggle()
        flashBtn.isActive = isFlashOn
        cameraManager?.setTorch(isFlashOn)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func handleMic() {
        isMicMuted.toggle()
        micBtn.isActive = isMicMuted  // active = muted (cross icon)
        videoRecorder.isMicMuted = isMicMuted
        if let lbl = pipBottomView.viewWithTag(1002) as? UILabel {
            lbl.text = isMicMuted ? "MUTE" : "MIC"
            lbl.textColor = isMicMuted
                ? UIColor.white.withAlphaComponent(0.38)
                : UIColor(red: 0.204, green: 0.78, blue: 0.349, alpha: 1)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func handleMirror() {
        isFrontMirror.toggle()
        mirrorBtn.isActive = isFrontMirror
        cameraManager?.setFrontMirror(isFrontMirror)
        if let lbl = pipBottomView.viewWithTag(1001) as? UILabel {
            lbl.text = isFrontMirror ? "MIRROR" : "NORMAL"
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func handleGrid() {
        isGridOn.toggle()
        gridBtn.isActive = isGridOn
        gridOverlayView.isHidden = !isGridOn
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func handleAELock() {
        isAELocked.toggle()
        aeLockBtn.isActive = isAELocked
        cameraManager?.setAEAFLock(isAELocked)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func handleSwap() {
        guard videoRecorder.state != .recording else { return }
        isSwapped.toggle()

        // 先把两个 view 都 detach，再重新 attach。
        // 直接 attach 会因为 CALayer 只能有一个父层，导致第二步把第一步刚添加的层意外移除（黑屏）。
        let bl = cameraManager?.backPreviewLayer
        let fl = cameraManager?.frontPreviewLayer
        backPreviewView.detach()
        frontPreviewView.detach()

        if isSwapped {
            if let fl { backPreviewView.attachPreviewLayer(fl) }
            if let bl { frontPreviewView.attachPreviewLayer(bl) }
        } else {
            if let bl { backPreviewView.attachPreviewLayer(bl) }
            if let fl { frontPreviewView.attachPreviewLayer(fl) }
        }

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.swapBtn.transform = self.isSwapped
                ? CGAffineTransform(rotationAngle: .pi)
                : .identity
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @objc private func handleSettings() {
        cameraManager?.stopRunning()
        let vc = SettingsViewController()
        present(vc, animated: true)
    }

    @objc private func captureModeChanged() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func recordingsChanged() {
        refreshGalleryBadge()
    }

    @objc private func handleGallery() {
        cameraManager?.stopRunning()
        let vc = RecordingsListViewController()
        present(vc, animated: true)
    }

    // MARK: - Photo Capture

    private func takePhoto() {
        guard recordButton.isEnabled else { return }
        recordButton.isEnabled = false

        // 快门闪白
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = .white
        flash.alpha = 0
        flash.isUserInteractionEnabled = false
        view.addSubview(flash)
        UIView.animate(withDuration: 0.08, animations: { flash.alpha = 0.7 }) { _ in
            UIView.animate(withDuration: 0.18) { flash.alpha = 0 } completion: { _ in
                flash.removeFromSuperview()
            }
        }

        if AppSettings.shared.saveComposite {
            videoRecorder.makePhotoComposite { [weak self] compositeBuffer in
                guard let self else { return }
                self.finalizePhotoCapture(
                    composite: compositeBuffer,
                    back:  self.videoRecorder.latestBackPixelBuffer,
                    front: self.videoRecorder.latestFrontPixelBuffer
                )
            }
        } else {
            finalizePhotoCapture(
                composite: nil,
                back:  videoRecorder.latestBackPixelBuffer,
                front: videoRecorder.latestFrontPixelBuffer
            )
        }
    }

    private func finalizePhotoCapture(composite: CVPixelBuffer?,
                                       back: CVPixelBuffer?,
                                       front: CVPixelBuffer?) {
        let settings = AppSettings.shared
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let ctx = CIContext(options: [.useSoftwareRenderer: false])
            var images: [UIImage] = []

            if let buf = composite, let img = self.cvBufferToImage(buf, context: ctx) {
                images.append(img)
            }
            if settings.saveBack, let buf = back,
               let img = self.cvBufferToImage(buf, context: ctx) { images.append(img) }
            if settings.saveFront, let buf = front,
               let img = self.cvBufferToImage(buf, context: ctx) { images.append(img) }

            guard !images.isEmpty else {
                DispatchQueue.main.async { self.recordButton.isEnabled = true }
                return
            }
            let group = DispatchGroup()
            var saveError: Error?
            for img in images {
                group.enter()
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: img)
                }) { _, error in
                    if let e = error { saveError = e }
                    group.leave()
                }
            }
            group.notify(queue: .main) { [weak self] in
                self?.recordButton.isEnabled = true
                if let e = saveError {
                    self?.showAlert(title: "拍照失败", message: e.localizedDescription)
                }
            }
        }
    }

    private func cvBufferToImage(_ buffer: CVPixelBuffer, context: CIContext) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - Not supported / alerts

    private func showNotSupported() {
        notSupportedView.isHidden = false
        recordButton.isEnabled    = false
    }

    private func showPermissionDeniedAlert() {
        let alert = UIAlertController(title: "需要权限",
                                      message: "请在【设置】中开启摄像头、麦克风和相册权限",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
            PermissionManager.shared.openAppSettings()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - CameraManagerDelegate

extension ViewController: CameraManagerDelegate {

    func cameraManager(_ manager: CameraManager, didOutputBackSampleBuffer sb: CMSampleBuffer) {
        videoRecorder.appendBackVideoFrame(sb)
    }

    func cameraManager(_ manager: CameraManager, didOutputFrontSampleBuffer sb: CMSampleBuffer) {
        videoRecorder.appendFrontVideoFrame(sb)
    }

    func cameraManager(_ manager: CameraManager, didOutputAudioSampleBuffer sb: CMSampleBuffer) {
        videoRecorder.appendAudioFrame(sb)
        // Compute RMS audio level
        audioLevelValue = computeAudioLevel(from: sb)
    }

    private func computeAudioLevel(from buffer: CMSampleBuffer) -> Float {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { return 0 }
        var totalLen = 0
        var dataPtr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &totalLen, dataPointerOut: &dataPtr) == noErr,
              let ptr = dataPtr else { return 0 }
        let sampleCount = totalLen / 2
        guard sampleCount > 0 else { return 0 }
        var sum: Float = 0
        ptr.withMemoryRebound(to: Int16.self, capacity: sampleCount) { p in
            for i in 0..<sampleCount {
                let v = Float(p[i]) / 32768.0
                sum += v * v
            }
        }
        return min(sqrt(sum / Float(sampleCount)) * 4.0, 1.0)
    }
}

// MARK: - UIDeviceOrientation → AVCaptureVideoOrientation

private extension AVCaptureVideoOrientation {
    init?(device orientation: UIDeviceOrientation) {
        switch orientation {
        case .portrait:           self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft:      self = .landscapeRight
        case .landscapeRight:     self = .landscapeLeft
        default:                  return nil
        }
    }
}

// MARK: - Helper Views

// 3×3 grid lines
final class GridOverlayView: UIView {
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.15).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1...2 {
            let x = rect.width * CGFloat(i) / 3
            ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: rect.height))
            let y = rect.height * CGFloat(i) / 3
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: rect.width, y: y))
        }
        ctx.strokePath()
    }
}

// Frame corner ticks
final class CornerTicksView: UIView {
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.30).cgColor)
        ctx.setLineWidth(1)
        let inset: CGFloat = 14; let len: CGFloat = 18
        // TL
        ctx.move(to: CGPoint(x: inset, y: inset + len)); ctx.addLine(to: CGPoint(x: inset, y: inset))
        ctx.addLine(to: CGPoint(x: inset + len, y: inset))
        // TR
        ctx.move(to: CGPoint(x: rect.maxX - inset - len, y: inset)); ctx.addLine(to: CGPoint(x: rect.maxX - inset, y: inset))
        ctx.addLine(to: CGPoint(x: rect.maxX - inset, y: inset + len))
        // BL
        ctx.move(to: CGPoint(x: inset, y: rect.maxY - inset - len)); ctx.addLine(to: CGPoint(x: inset, y: rect.maxY - inset))
        ctx.addLine(to: CGPoint(x: inset + len, y: rect.maxY - inset))
        // BR
        ctx.move(to: CGPoint(x: rect.maxX - inset - len, y: rect.maxY - inset)); ctx.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        ctx.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset - len))
        ctx.strokePath()
    }
}

// Center crosshair
final class CrosshairView: UIView {
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.32).cgColor)
        ctx.setLineWidth(1)
        let cx = rect.midX, cy = rect.midY
        // Circle
        ctx.addEllipse(in: CGRect(x: cx - 2, y: cy - 2, width: 4, height: 4))
        ctx.strokePath()
        // Arms
        ctx.move(to: CGPoint(x: cx, y: rect.minY + 2)); ctx.addLine(to: CGPoint(x: cx, y: cy - 4))
        ctx.move(to: CGPoint(x: cx, y: cy + 4)); ctx.addLine(to: CGPoint(x: cx, y: rect.maxY - 2))
        ctx.move(to: CGPoint(x: rect.minX + 2, y: cy)); ctx.addLine(to: CGPoint(x: cx - 4, y: cy))
        ctx.move(to: CGPoint(x: cx + 4, y: cy)); ctx.addLine(to: CGPoint(x: rect.maxX - 2, y: cy))
        ctx.strokePath()
    }
}

// Audio level meter (12 segments)
final class LevelMeterView: UIView {
    var level: Float = 0 {
        didSet { setNeedsDisplay() }
    }
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()!
        let segments = 12
        let gap: CGFloat = 1.5
        let segW = (rect.width - CGFloat(segments - 1) * gap) / CGFloat(segments)
        for i in 0..<segments {
            let t = Float(i) / Float(segments - 1)
            let lit = t <= level
            let color: UIColor
            if lit {
                if t > 0.78 { color = UIColor(red: 1, green: 0.231, blue: 0.188, alpha: 1) }
                else if t > 0.55 { color = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1) }
                else { color = UIColor(red: 0.204, green: 0.78, blue: 0.349, alpha: 1) }
            } else {
                color = UIColor.white.withAlphaComponent(0.12)
            }
            ctx.setFillColor(color.cgColor)
            let x = CGFloat(i) * (segW + gap)
            ctx.fill(CGRect(x: x, y: 0, width: segW, height: rect.height).insetBy(dx: 0, dy: 0.5))
        }
    }
}

// Drag handle dots (3×2 grid of dots)
final class DragDotsView: UIView {
    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 11, height: 14))
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.7).cgColor)
        let r: CGFloat = 1.0
        let cols: [(CGFloat, CGFloat)] = [(0, 0), (4, 0), (0, 4), (4, 4), (0, 8), (4, 8)]
        let ox = (rect.width  - 4 - 2 * r) / 2
        let oy = (rect.height - 8 - 2 * r) / 2
        for (dx, dy) in cols {
            ctx.fillEllipse(in: CGRect(x: ox + dx, y: oy + dy, width: r * 2, height: r * 2))
        }
    }
}

// Toolbar button: rounded icon area + small mono label below
final class ToolbarButton: UIControl {

    static let iconAreaH: CGFloat  = 40
    static let labelGap: CGFloat   = 3
    static let labelH: CGFloat     = 10
    static var totalHeight: CGFloat { iconAreaH + labelGap + labelH }

    var isActive: Bool = false { didSet { updateStyle() } }

    private let iconOn:  String
    private let iconOff: String?
    private let bgView      = UIView()
    private let iconImgView = UIImageView()
    private let titleLbl    = UILabel()

    init(icon: String, iconOff: String?, title: String) {
        self.iconOn  = icon
        self.iconOff = iconOff
        super.init(frame: .zero)

        // Rounded background (icon area only)
        bgView.layer.cornerRadius  = 10
        bgView.layer.borderWidth   = 0.5
        bgView.isUserInteractionEnabled = false
        addSubview(bgView)

        // Icon
        iconImgView.contentMode = .center
        iconImgView.isUserInteractionEnabled = false
        bgView.addSubview(iconImgView)

        // Label below background
        titleLbl.text          = title
        titleLbl.font          = UIFont.monospacedSystemFont(ofSize: 7, weight: .semibold)
        titleLbl.textAlignment = .center
        titleLbl.isUserInteractionEnabled = false
        addSubview(titleLbl)

        updateStyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        bgView.frame      = CGRect(x: 0, y: 0, width: bounds.width, height: Self.iconAreaH)
        iconImgView.frame = bgView.bounds
        titleLbl.frame    = CGRect(x: 0, y: Self.iconAreaH + Self.labelGap,
                                   width: bounds.width, height: Self.labelH)
    }

    private func updateStyle() {
        let imgName = isActive ? iconOn : (iconOff ?? iconOn)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        iconImgView.image = UIImage(systemName: imgName, withConfiguration: cfg)

        let amber = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1)
        bgView.backgroundColor = isActive
            ? UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 0.16)
            : UIColor(white: 0.08, alpha: 0.55)
        iconImgView.tintColor  = isActive ? amber : .white
        bgView.layer.borderColor = (isActive ? amber : UIColor.white.withAlphaComponent(0.10)).cgColor
        titleLbl.textColor       = isActive
            ? amber.withAlphaComponent(0.9)
            : UIColor.white.withAlphaComponent(0.38)
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1.0 }
    }
}

// PiP 水印：应用图标 + 文字，仅非会员显示
final class PiPWatermarkView: UIView {

    private let iconView  = UIImageView()
    private let textLabel = UILabel()

    var preferredSize: CGSize {
        textLabel.sizeToFit()
        return CGSize(width: 14 + 3 + textLabel.frame.width, height: 16)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        iconView.image = UIImage(named: "icon_200")
        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 2
        iconView.clipsToBounds = true
        addSubview(iconView)

        textLabel.text      = "Double Rec"
        textLabel.font      = UIFont.monospacedSystemFont(ofSize: 7.5, weight: .semibold)
        textLabel.textColor = .white
        textLabel.layer.shadowColor   = UIColor.black.cgColor
        textLabel.layer.shadowOffset  = CGSize(width: 0.5, height: 0.5)
        textLabel.layer.shadowRadius  = 1.5
        textLabel.layer.shadowOpacity = 1.0
        textLabel.layer.rasterizationScale = UIScreen.main.scale
        textLabel.layer.shouldRasterize   = true
        addSubview(textLabel)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let iconSize: CGFloat = 12
        iconView.frame = CGRect(x: 0, y: (bounds.height - iconSize) / 2,
                                width: iconSize, height: iconSize)
        textLabel.sizeToFit()
        textLabel.frame.origin = CGPoint(x: iconSize + 3,
                                          y: (bounds.height - textLabel.frame.height) / 2)
    }
}
