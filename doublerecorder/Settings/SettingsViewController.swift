import UIKit

class SettingsViewController: UIViewController {

    private let settings = AppSettings.shared

    private let modeSegment    = UISegmentedControl(items: ["VIDEO", "PHOTO"])
    private let compositeRow   = SettingsToggleRow(title: "COMPOSITE", subtitle: "前后摄 PiP 合成视频")
    private let backRow        = SettingsToggleRow(title: "BACK CAM",  subtitle: "后摄独立视频")
    private let frontRow       = SettingsToggleRow(title: "FRONT CAM", subtitle: "前摄独立视频")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.07, alpha: 1)
        setupSheetIfAvailable()
        buildUI()
        syncFromSettings()
    }

    private func setupSheetIfAvailable() {
        if #available(iOS 15.0, *) {
            if let sheet = sheetPresentationController {
                sheet.detents = [.medium()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 20
            }
        }
        modalPresentationStyle = .automatic
    }

    // MARK: - Build UI

    private func buildUI() {
        let cv = view!

        // Title bar
        let titleLabel = UILabel()
        titleLabel.text = "SETTINGS"
        titleLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.50)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(titleLabel)

        // Mode section header
        let modeHeader = sectionHeader("CAPTURE MODE")
        cv.addSubview(modeHeader)

        // Mode segment
        modeSegment.selectedSegmentTintColor = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 0.9)
        modeSegment.backgroundColor = UIColor(white: 0.14, alpha: 1)
        let normal: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.62)
        ]
        let selected: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        modeSegment.setTitleTextAttributes(normal,   for: .normal)
        modeSegment.setTitleTextAttributes(selected, for: .selected)
        modeSegment.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        modeSegment.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(modeSegment)

        // Save outputs section header
        let saveHeader = sectionHeader("SAVE OUTPUTS")
        cv.addSubview(saveHeader)

        // Toggle rows
        for row in [compositeRow, backRow, frontRow] {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.onToggle = { [weak self] _ in self?.validateAndSave() }
            cv.addSubview(row)
        }

        let gap: CGFloat = 1

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            modeHeader.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 22),
            modeHeader.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),

            modeSegment.topAnchor.constraint(equalTo: modeHeader.bottomAnchor, constant: 8),
            modeSegment.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            modeSegment.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
            modeSegment.heightAnchor.constraint(equalToConstant: 36),

            saveHeader.topAnchor.constraint(equalTo: modeSegment.bottomAnchor, constant: 24),
            saveHeader.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),

            compositeRow.topAnchor.constraint(equalTo: saveHeader.bottomAnchor, constant: 8),
            compositeRow.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            compositeRow.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            compositeRow.heightAnchor.constraint(equalToConstant: 56),

            backRow.topAnchor.constraint(equalTo: compositeRow.bottomAnchor, constant: gap),
            backRow.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            backRow.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            backRow.heightAnchor.constraint(equalToConstant: 56),

            frontRow.topAnchor.constraint(equalTo: backRow.bottomAnchor, constant: gap),
            frontRow.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            frontRow.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            frontRow.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    private func sectionHeader(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        l.textColor = UIColor.white.withAlphaComponent(0.35)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    // MARK: - State

    private func syncFromSettings() {
        modeSegment.selectedSegmentIndex = settings.captureMode == .video ? 0 : 1
        compositeRow.isOn = settings.saveComposite
        backRow.isOn      = settings.saveBack
        frontRow.isOn     = settings.saveFront
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

    private let bg            = UIView()
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
}
