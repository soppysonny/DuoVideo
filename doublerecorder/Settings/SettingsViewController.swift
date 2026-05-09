import UIKit
import StoreKit
import MessageUI

class SettingsViewController: UIViewController {

    private let settings = AppSettings.shared

    private let modeSegment  = UISegmentedControl(items: ["VIDEO", "PHOTO"])
    private let compositeRow = SettingsToggleRow(title: "COMPOSITE", subtitle: NSLocalizedString("toggle.composite_subtitle", comment: ""))
    private let backRow      = SettingsToggleRow(title: "BACK CAM",  subtitle: NSLocalizedString("toggle.back_cam_subtitle", comment: ""))
    private let frontRow     = SettingsToggleRow(title: "FRONT CAM", subtitle: NSLocalizedString("toggle.front_cam_subtitle", comment: ""))
    private let mirrorRow    = SettingsToggleRow(title: "MIRROR",    subtitle: NSLocalizedString("toggle.mirror_subtitle", comment: ""))
    private let autoSaveRow  = SettingsToggleRow(title: "AUTO SAVE", subtitle: NSLocalizedString("toggle.autosave_subtitle", comment: ""))

    private var resTiles: [OptionTile] = []
    private var fpsTiles: [OptionTile] = []
    private var pipTiles: [OptionTile] = []

    // IAP state
    private var iapStatusLabel: UILabel?
    private var buyButton: UIButton?
    private var buyButtonLabel: UILabel?
    private var restoreButton: UIButton?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.06, alpha: 1)
        buildUI()
        syncFromSettings()
        updateBuyButtonPrice()
        NotificationCenter.default.addObserver(self, selector: #selector(handleProductLoaded),
                                               name: .iapProductLoaded, object: nil)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - Build UI

    private func buildUI() {
        // Title
        let titleLabel = UILabel()
        titleLabel.text      = NSLocalizedString("settings.title", comment: "")
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

        // ── 内购解锁 ──────────────────────────────────────────
        vStack.addArrangedSubview(sectionLabel(NSLocalizedString("section.iap", comment: "")))
        vStack.setCustomSpacing(10, after: vStack.arrangedSubviews.last!)

        let iapCard = makeIAPCard()
        vStack.addArrangedSubview(iapCard)
        vStack.setCustomSpacing(32, after: iapCard)

        // ── 拍摄模式 ──────────────────────────────────────────
        vStack.addArrangedSubview(sectionLabel(NSLocalizedString("section.capture_mode", comment: "")))
        vStack.setCustomSpacing(10, after: vStack.arrangedSubviews.last!)

        styleSegment(modeSegment)
        modeSegment.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeSegment.heightAnchor.constraint(equalToConstant: 36).isActive = true
        vStack.addArrangedSubview(modeSegment)
        vStack.setCustomSpacing(8, after: modeSegment)

        let modeCaption = sectionLabel(NSLocalizedString("section.capture_mode_hint", comment: ""))
        vStack.addArrangedSubview(modeCaption)
        vStack.setCustomSpacing(32, after: modeCaption)

        // ── 保存文件 ──────────────────────────────────────────
        vStack.addArrangedSubview(sectionLabel(NSLocalizedString("section.save_files", comment: "")))
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
        vStack.addArrangedSubview(sectionLabel(NSLocalizedString("section.recording_effects", comment: "")))
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
        vStack.addArrangedSubview(sectionLabel(NSLocalizedString("section.resolution", comment: "")))
        vStack.setCustomSpacing(10, after: vStack.arrangedSubviews.last!)

        let resRow = makePickerRow()
        let resOptions: [(String, String, AppSettings.VideoResolution)] = [
            ("720P",  "HD · 1280×720",   .hd720),
            ("1080P", "FHD · 1920×1080", .hd1080),
            ("4K",    "UHD · 3840×2160", .uhd4k),
        ]
        for opt in resOptions {
            let tile = OptionTile(title: opt.0, subtitle: opt.1)
            let res  = opt.2
            tile.onTap = { [weak self] in
                self?.settings.videoResolution = res
                self?.syncResTiles()
                AnalyticsManager.logConfigChanged(key: "resolution", value: res.rawValue)
            }
            resTiles.append(tile)
            resRow.addArrangedSubview(tile)
        }
        vStack.addArrangedSubview(resRow)
        vStack.setCustomSpacing(32, after: resRow)

        // ── 帧率 ──────────────────────────────────────────────
        vStack.addArrangedSubview(sectionLabel(NSLocalizedString("section.frame_rate", comment: "")))
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
                self?.syncFpsTiles()
                AnalyticsManager.logConfigChanged(key: "frame_rate", value: "\(rate.rawValue)")
            }
            fpsTiles.append(tile)
            fpsRow.addArrangedSubview(tile)
        }
        vStack.addArrangedSubview(fpsRow)
        vStack.setCustomSpacing(32, after: fpsRow)

        // ── PiP 摄像头（小窗口）────────────────────────────────
        vStack.addArrangedSubview(sectionLabel(NSLocalizedString("section.pip_camera", comment: "")))
        vStack.setCustomSpacing(10, after: vStack.arrangedSubviews.last!)

        let pipRow = makePickerRow()
        let pipOptions: [(String, String, AppSettings.PiPCamera)] = [
            (NSLocalizedString("pip.front", comment: ""),    "FRONT",     .front),
            (NSLocalizedString("pip.back_wide", comment: ""), "BACK WIDE", .backUltraWide),
        ]
        for opt in pipOptions {
            let tile = OptionTile(title: opt.0, subtitle: opt.1)
            let cam  = opt.2
            tile.onTap = { [weak self] in
                self?.settings.pipCamera = cam
                self?.syncPipTiles()
                AnalyticsManager.logConfigChanged(key: "pip_camera", value: cam.rawValue)
                NotificationCenter.default.post(name: .pipCameraChanged, object: nil)
            }
            pipTiles.append(tile)
            pipRow.addArrangedSubview(tile)
        }
        vStack.addArrangedSubview(pipRow)
        vStack.setCustomSpacing(32, after: pipRow)

        // ── 自动保存 ──────────────────────────────────────────
        vStack.addArrangedSubview(sectionLabel(NSLocalizedString("section.save", comment: "")))
        vStack.setCustomSpacing(10, after: vStack.arrangedSubviews.last!)

        autoSaveRow.onToggle = { [weak self] val in
            self?.settings.autoSaveToPhotos = val
        }
        autoSaveRow.setCorners(top: true, bottom: true)
        autoSaveRow.heightAnchor.constraint(equalToConstant: 56).isActive = true
        vStack.addArrangedSubview(autoSaveRow)
        vStack.setCustomSpacing(32, after: autoSaveRow)

        // ── 反馈 ──────────────────────────────────────────────
        vStack.addArrangedSubview(sectionLabel(NSLocalizedString("section.feedback", comment: "")))
        vStack.setCustomSpacing(10, after: vStack.arrangedSubviews.last!)

        let feedbackBtn = makeActionButton(title: NSLocalizedString("btn.send_feedback", comment: ""), icon: "envelope.fill")
        feedbackBtn.addTarget(self, action: #selector(sendFeedback), for: .touchUpInside)
        feedbackBtn.heightAnchor.constraint(equalToConstant: 52).isActive = true
        vStack.addArrangedSubview(feedbackBtn)
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
        autoSaveRow.isOn  = settings.autoSaveToPhotos
        syncResTiles()
        syncFpsTiles()
        syncPipTiles()
        syncIAPUI()
    }

    private func syncResTiles() {
        let order: [AppSettings.VideoResolution] = [.hd720, .hd1080, .uhd4k]
        for (tile, val) in zip(resTiles, order) { tile.isSelected = val == settings.videoResolution }
    }

    private func syncFpsTiles() {
        let order: [AppSettings.FrameRate] = [.fps24, .fps30, .fps60]
        for (tile, val) in zip(fpsTiles, order) { tile.isSelected = val == settings.frameRate }
    }

    private func syncPipTiles() {
        let order: [AppSettings.PiPCamera] = [.front, .backUltraWide]
        for (tile, val) in zip(pipTiles, order) { tile.isSelected = val == settings.pipCamera }
    }

    // MARK: - IAP Card

    private func makeIAPCard() -> UIView {
        let card = UIView()
        card.backgroundColor    = UIColor(white: 0.13, alpha: 1)
        card.layer.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        card.heightAnchor.constraint(equalToConstant: 130).isActive = true

        let statusLbl = UILabel()
        statusLbl.font      = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        statusLbl.textColor = .white
        statusLbl.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(statusLbl)
        iapStatusLabel = statusLbl

        let subLbl = UILabel()
        subLbl.font      = UIFont.systemFont(ofSize: 11)
        subLbl.textColor = UIColor.white.withAlphaComponent(0.40)
        subLbl.text      = NSLocalizedString("iap.description", comment: "")
        subLbl.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(subLbl)

        let btnStack = UIStackView()
        btnStack.axis    = .horizontal
        btnStack.spacing = 8
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(btnStack)

        let buy = makeActionButton(title: NSLocalizedString("btn.unlock_pro", comment: ""), icon: "star.fill")
        buy.addTarget(self, action: #selector(purchaseTapped), for: .touchUpInside)
        buyButton = buy
        if let stack = buy.subviews.first(where: { $0 is UIStackView }) as? UIStackView,
           let label = stack.arrangedSubviews.last(where: { $0 is UILabel }) as? UILabel {
            buyButtonLabel = label
        }

        let restore = makeActionButton(title: NSLocalizedString("btn.restore_purchase", comment: ""), icon: "arrow.clockwise")
        restore.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)
        restoreButton = restore

        btnStack.addArrangedSubview(buy)
        btnStack.addArrangedSubview(restore)

        NSLayoutConstraint.activate([
            statusLbl.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            statusLbl.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            subLbl.topAnchor.constraint(equalTo: statusLbl.bottomAnchor, constant: 4),
            subLbl.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            btnStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            btnStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            btnStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            btnStack.heightAnchor.constraint(equalToConstant: 40),
        ])

        return card
    }

    private func makeActionButton(title: String, icon: String) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.backgroundColor    = UIColor(white: 0.20, alpha: 1)
        btn.layer.cornerRadius = 10
        btn.layer.borderWidth  = 0.5
        btn.layer.borderColor  = UIColor.white.withAlphaComponent(0.14).cgColor
        btn.translatesAutoresizingMaskIntoConstraints = false

        let cfg = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: icon, withConfiguration: cfg))
        iv.tintColor = .white
        iv.contentMode = .scaleAspectFit
        iv.setContentHuggingPriority(.required, for: .horizontal)

        let lbl = UILabel()
        lbl.text = title
        lbl.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        lbl.textColor = .white

        let stack = UIStackView(arrangedSubviews: [iv, lbl])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        btn.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: btn.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: btn.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: btn.trailingAnchor, constant: -8),
        ])
        return btn
    }

    private func syncIAPUI() {
        let isPro = settings.isProUser
        iapStatusLabel?.text = isPro
            ? NSLocalizedString("iap.pro_unlocked", comment: "")
            : String(format: NSLocalizedString("iap.free_remaining", comment: ""), KeychainHelper.shared.remainingFreeRecordings)
        iapStatusLabel?.textColor = isPro
            ? UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1)
            : .white
        buyButton?.isEnabled  = !isPro
        buyButton?.alpha      = isPro ? 0.35 : 1.0
        restoreButton?.isEnabled = !isPro
        restoreButton?.alpha     = isPro ? 0.35 : 1.0
    }

    @objc private func handleProductLoaded() {
        updateBuyButtonPrice()
    }

    private func updateBuyButtonPrice() {
        guard let price = IAPManager.shared.priceString, !settings.isProUser else { return }
        buyButtonLabel?.text = String(format: NSLocalizedString("btn.unlock_pro_price", comment: ""), price)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func modeChanged() {
        let mode: AppSettings.CaptureMode = modeSegment.selectedSegmentIndex == 0 ? .video : .photo
        settings.captureMode = mode
        AnalyticsManager.logConfigChanged(key: "capture_mode", value: mode.rawValue)
        NotificationCenter.default.post(name: .captureModeChanged, object: nil)
    }

    @objc private func purchaseTapped() {
        AnalyticsManager.logPurchaseClick()
        IAPManager.shared.onPurchaseSuccess = { [weak self] in
            AnalyticsManager.logPurchaseOK()
            self?.syncIAPUI()
            let alert = UIAlertController(
                title: NSLocalizedString("alert.unlock_success_title", comment: ""),
                message: NSLocalizedString("alert.purchase_success_message", comment: ""),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("btn.ok", comment: ""), style: .default))
            self?.present(alert, animated: true)
        }
        IAPManager.shared.onPurchaseFailed = { [weak self] err in
            guard let err else { return } // 用户取消，不弹窗
            let alert = UIAlertController(
                title: NSLocalizedString("alert.purchase_failed", comment: ""),
                message: err.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("btn.ok", comment: ""), style: .default))
            self?.present(alert, animated: true)
        }
        IAPManager.shared.purchase()
    }

    @objc private func restoreTapped() {
        AnalyticsManager.logPurchaseClick()
        IAPManager.shared.onPurchaseSuccess = { [weak self] in
            AnalyticsManager.logPurchaseOK()
            self?.syncIAPUI()
            let alert = UIAlertController(
                title: NSLocalizedString("alert.restore_success_title", comment: ""),
                message: NSLocalizedString("alert.restore_success_message", comment: ""),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("btn.ok", comment: ""), style: .default))
            self?.present(alert, animated: true)
        }
        IAPManager.shared.onRestoreNotFound = { [weak self] in
            let alert = UIAlertController(
                title: NSLocalizedString("alert.restore_not_found_title", comment: ""),
                message: NSLocalizedString("alert.restore_not_found_message", comment: ""),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("btn.ok", comment: ""), style: .default))
            self?.present(alert, animated: true)
        }
        IAPManager.shared.onPurchaseFailed = { [weak self] err in
            guard let err else { return }
            let alert = UIAlertController(
                title: NSLocalizedString("alert.restore_failed", comment: ""),
                message: err.localizedDescription,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("btn.ok", comment: ""), style: .default))
            self?.present(alert, animated: true)
        }
        IAPManager.shared.restore()
    }

    @objc private func sendFeedback() {
        let email = "lava@mbjztech.cn"
        let subject = NSLocalizedString("feedback.email_subject", comment: "")
        if MFMailComposeViewController.canSendMail() {
            let vc = MFMailComposeViewController()
            vc.mailComposeDelegate = self
            vc.setToRecipients([email])
            vc.setSubject(subject)
            present(vc, animated: true)
        } else {
            // 没有邮件客户端时打开 mailto 链接
            let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)") {
                UIApplication.shared.open(url)
            }
        }
    }

    private func validateAndSave() {
        let c = compositeRow.isOn, b = backRow.isOn, f = frontRow.isOn
        guard c || b || f else {
            let alert = UIAlertController(
                title: NSLocalizedString("alert.output_required_title", comment: ""),
                message: NSLocalizedString("alert.output_required_message", comment: ""),
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("btn.ok", comment: ""), style: .default))
            present(alert, animated: true)
            syncFromSettings()
            return
        }
        settings.saveComposite = c
        settings.saveBack      = b
        settings.saveFront     = f
    }
}

// MARK: - MFMailComposeViewControllerDelegate

extension SettingsViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController,
                               didFinishWith result: MFMailComposeResult,
                               error: Error?) {
        controller.dismiss(animated: true)
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
