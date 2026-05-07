import UIKit

class SettingsViewController: UIViewController {

    private let settings = AppSettings.shared

    private let modeSegment  = UISegmentedControl(items: ["VIDEO", "PHOTO"])
    private let compositeRow = SettingsToggleRow(title: "COMPOSITE", subtitle: "前后摄 PiP 合成视频")
    private let backRow      = SettingsToggleRow(title: "BACK CAM",  subtitle: "后摄独立视频")
    private let frontRow     = SettingsToggleRow(title: "FRONT CAM", subtitle: "前摄独立视频")
    private let mirrorRow    = SettingsToggleRow(title: "MIRROR",    subtitle: "前摄录制镜像翻转")

    private var resTiles: [OptionTile] = []
    private var fpsTiles: [OptionTile] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.06, alpha: 1)
        buildUI()
        syncFromSettings()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - Build UI

    private func buildUI() {
        // Title
        let titleLabel = UILabel()
        titleLabel.text      = "SETTINGS"
        titleLabel.font      = UIFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Close button
        let closeBtn = UIButton(type: .system)
        let iconCfg  = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        closeBtn.setImage(UIImage(systemName: "xmark", withConfiguration: iconCfg), for: .normal)
        closeBtn.tintColor = UIColor.white.withAlphaComponent(0.55)
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeBtn)

        // Header divider
        let divider = UIView()
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        // Scroll view
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical      = true
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        let safeTop = view.safeAreaLayoutGuide.topAnchor
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: safeTop, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            closeBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeBtn.widthAnchor.constraint(equalToConstant: 30),
            closeBtn.heightAnchor.constraint(equalToConstant: 30),

            divider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        buildScrollContent(in: scroll)
    }

    private func buildScrollContent(in scroll: UIScrollView) {
        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(vStack)

        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 24),
            vStack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            vStack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
            vStack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -40),
            vStack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32),
        ])

        // ── 拍摄模式 ──────────────────────────────────────────
        vStack.addArrangedSubview(sectionLabel("拍摄模式"))
        vStack.setCustomSpacing(10, after: vStack.arrangedSubviews.last!)

        styleSegment(modeSegment)
        modeSegment.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeSegment.heightAnchor.constraint(equalToConstant: 36).isActive = true
        vStack.addArrangedSubview(modeSegment)
        vStack.setCustomSpacing(8, after: modeSegment)

        let modeCaption = sectionLabel("切换此选项即切换拍摄模式")
        vStack.addArrangedSubview(modeCaption)
        vStack.setCustomSpacing(32, after: modeCaption)

        // ── 保存文件 ──────────────────────────────────────────
        vStack.addArrangedSubview(sectionLabel("保存文件"))
        vStack.setCustomSpacing(10, after: vStack.arrangedSubviews.last!)

        let toggleRows: [SettingsToggleRow] = [compositeRow, backRow, frontRow]
        for (i, row) in toggleRows.enumerated() {
            row.onToggle = { [weak self] _ in self?.validateAndSave() }
            row.setCorners(top: i == 0, bottom: i == toggleRows.count - 1)
            row.heightAnchor.constraint(equalToConstant: 56).isActive = true
            vStack.addArrangedSubview(row)
            vStack.setCustomSpacing(i < toggleRows.count - 1 ? 1 : 32, after: row)
        }

        // ── 录制效果 ──────────────────────────────────────────
        vStack.addArrangedSubview(sectionLabel("录制效果"))
        vStack.setCustomSpacing(10, after: vStack.arrangedSubviews.last!)

        mirrorRow.onToggle = { [weak self] val in
            self?.settings.recordMirrored = val
            NotificationCenter.default.post(name: .recordMirrorChanged, object: nil)
        }
        mirrorRow.setCorners(top: true, bottom: true)
        mirrorRow.heightAnchor.constraint(equalToConstant: 56).isActive = true
        vStack.addArrangedSubview(mirrorRow)
        vStack.setCustomSpacing(32, after: mirrorRow)

        // ── 清晰度 ────────────────────────────────────────────
        vStack.addArrangedSubview(sectionLabel("清晰度"))
        vStack.setCustomSpacing(10, after: vStack.arrangedSubviews.last!)

        let resRow = makePickerRow()
        let resOptions: [(String, String, AppSettings.VideoResolution)] = [
            ("720P",  "HD · 1280×720",   .hd720),
            ("1080P", "FHD · 1920×1080", .hd1080),
        ]
        for opt in resOptions {
            let tile = OptionTile(title: opt.0, subtitle: opt.1)
            let res  = opt.2
            tile.onTap = { [weak self] in
                self?.settings.videoResolution = res
                // 1080p 不支持 60fps 双摄，自动降到 30fps
                if res == .hd1080 && self?.settings.frameRate == .fps60 {
                    self?.settings.frameRate = .fps30
                    self?.syncFpsTiles()
                }
                self?.syncResTiles()
            }
            resTiles.append(tile)
            resRow.addArrangedSubview(tile)
        }
        vStack.addArrangedSubview(resRow)
        vStack.setCustomSpacing(8, after: resRow)

        let resCaption = sectionLabel("双摄模式下 1080P 最高支持 30fps")
        vStack.addArrangedSubview(resCaption)
        vStack.setCustomSpacing(32, after: resCaption)

        // ── 帧率 ──────────────────────────────────────────────
        vStack.addArrangedSubview(sectionLabel("帧率"))
        vStack.setCustomSpacing(10, after: vStack.arrangedSubviews.last!)

        let fpsRow = makePickerRow()
        let fpsOptions: [(String, String, AppSettings.FrameRate)] = [
            ("24", "fps", .fps24),
            ("30", "fps", .fps30),
            ("60", "fps", .fps60),
        ]
        for opt in fpsOptions {
            let tile = OptionTile(title: opt.0, subtitle: opt.1)
            let rate = opt.2
            tile.onTap = { [weak self] in
                self?.settings.frameRate = rate
                // 60fps 不支持 1080p 双摄，自动降到 720p
                if rate == .fps60 && self?.settings.videoResolution == .hd1080 {
                    self?.settings.videoResolution = .hd720
                    self?.syncResTiles()
                }
                self?.syncFpsTiles()
            }
            fpsTiles.append(tile)
            fpsRow.addArrangedSubview(tile)
        }
        vStack.addArrangedSubview(fpsRow)
        vStack.setCustomSpacing(8, after: fpsRow)

        let fpsCaption = sectionLabel("60fps 仅支持 720P")
        vStack.addArrangedSubview(fpsCaption)
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text      = text
        l.font      = UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        l.textColor = UIColor.white.withAlphaComponent(0.35)
        return l
    }

    private func makePickerRow() -> UIStackView {
        let s = UIStackView()
        s.axis         = .horizontal
        s.spacing      = 8
        s.distribution = .fillEqually
        s.heightAnchor.constraint(equalToConstant: 72).isActive = true
        return s
    }

    private func styleSegment(_ seg: UISegmentedControl) {
        seg.selectedSegmentTintColor = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 0.9)
        seg.backgroundColor = UIColor(white: 0.14, alpha: 1)
        seg.setTitleTextAttributes([
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.62),
        ], for: .normal)
        seg.setTitleTextAttributes([
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.black,
        ], for: .selected)
    }

    // MARK: - Sync

    private func syncFromSettings() {
        modeSegment.selectedSegmentIndex = settings.captureMode == .video ? 0 : 1
        compositeRow.isOn = settings.saveComposite
        backRow.isOn      = settings.saveBack
        frontRow.isOn     = settings.saveFront
        mirrorRow.isOn    = settings.recordMirrored
        syncResTiles()
        syncFpsTiles()
    }

    private func syncResTiles() {
        let order: [AppSettings.VideoResolution] = [.hd720, .hd1080]
        for (tile, val) in zip(resTiles, order) { tile.isSelected = val == settings.videoResolution }
    }

    private func syncFpsTiles() {
        let order: [AppSettings.FrameRate] = [.fps24, .fps30, .fps60]
        for (tile, val) in zip(fpsTiles, order) { tile.isSelected = val == settings.frameRate }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func modeChanged() {
        settings.captureMode = modeSegment.selectedSegmentIndex == 0 ? .video : .photo
        NotificationCenter.default.post(name: .captureModeChanged, object: nil)
    }

    private func validateAndSave() {
        let c = compositeRow.isOn, b = backRow.isOn, f = frontRow.isOn
        guard c || b || f else {
            let alert = UIAlertController(title: "至少选择一种输出",
                                          message: "合成视频、后摄和前摄至少保留一种",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
            syncFromSettings()
            return
        }
        settings.saveComposite = c
        settings.saveBack      = b
        settings.saveFront     = f
    }
}

// MARK: - SettingsToggleRow

final class SettingsToggleRow: UIView {

    var isOn: Bool {
        get { toggle.isOn }
        set { toggle.setOn(newValue, animated: false) }
    }
    var onToggle: ((Bool) -> Void)?

    fileprivate let bg     = UIView()
    private let titleLabel    = UILabel()
    private let subtitleLabel = UILabel()
    private let toggle        = UISwitch()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)

        bg.backgroundColor    = UIColor(white: 0.13, alpha: 1)
        bg.layer.cornerRadius = 12
        bg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bg)

        titleLabel.text      = title
        titleLabel.font      = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(titleLabel)

        subtitleLabel.text      = subtitle
        subtitleLabel.font      = UIFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.40)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(subtitleLabel)

        toggle.onTintColor = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1)
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(toggle)

        NSLayoutConstraint.activate([
            bg.topAnchor.constraint(equalTo: topAnchor),
            bg.bottomAnchor.constraint(equalTo: bottomAnchor),
            bg.leadingAnchor.constraint(equalTo: leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: trailingAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: bg.topAnchor, constant: 11),

            subtitleLabel.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 16),
            subtitleLabel.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -10),

            toggle.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggleChanged() { onToggle?(toggle.isOn) }

    func setCorners(top: Bool, bottom: Bool) {
        var mask: CACornerMask = []
        if top    { mask.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if bottom { mask.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        bg.layer.maskedCorners = mask
        bg.layer.cornerRadius  = (top || bottom) ? 12 : 0
    }
}

// MARK: - OptionTile

private final class OptionTile: UIView {

    var isSelected: Bool = false { didSet { updateStyle() } }
    var onTap: (() -> Void)?

    private let titleLbl = UILabel()
    private let subLbl   = UILabel()

    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        layer.cornerRadius = 12
        layer.borderWidth  = 1

        let vStack = UIStackView()
        vStack.axis      = .vertical
        vStack.alignment = .center
        vStack.spacing   = 4
        vStack.isUserInteractionEnabled = false
        vStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vStack)

        titleLbl.text = title
        titleLbl.font = UIFont.monospacedSystemFont(ofSize: 18, weight: .semibold)
        vStack.addArrangedSubview(titleLbl)

        subLbl.text = subtitle
        subLbl.font = UIFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        vStack.addArrangedSubview(subLbl)

        NSLayoutConstraint.activate([
            vStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            vStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        updateStyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func tapped() {
        onTap?()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func updateStyle() {
        let amber = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1)
        if isSelected {
            backgroundColor   = amber.withAlphaComponent(0.12)
            layer.borderColor = amber.withAlphaComponent(0.50).cgColor
            titleLbl.textColor = amber
            subLbl.textColor   = amber.withAlphaComponent(0.65)
        } else {
            backgroundColor   = UIColor(white: 0.13, alpha: 1)
            layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
            titleLbl.textColor = UIColor.white.withAlphaComponent(0.70)
            subLbl.textColor   = UIColor.white.withAlphaComponent(0.35)
        }
    }
}
