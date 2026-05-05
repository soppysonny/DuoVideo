import UIKit
import AVFoundation
import AVKit

class RecordingsListViewController: UIViewController {

    // MARK: - Data model

    struct SessionRecord {
        let timestamp: String
        let date: Date
        var compositeURL: URL?
        var backURL: URL?
        var frontURL: URL?
        var durationSeconds: Int = 0

        var primaryURL: URL? { compositeURL ?? backURL ?? frontURL }

        var displayTitle: String {
            let df = DateFormatter()
            df.dateFormat = "MM-dd  HH:mm:ss"
            return df.string(from: date)
        }
        var displayDuration: String {
            guard durationSeconds > 0 else { return "—" }
            let m = durationSeconds / 60
            let s = durationSeconds % 60
            return m > 0 ? "\(m):\(String(format: "%02d", s))" : "0:\(String(format: "%02d", s))"
        }
    }

    // MARK: - Views

    private var sessions: [SessionRecord] = []
    private let tableView   = UITableView(frame: .zero, style: .plain)
    private let titleLabel  = UILabel()
    private let emptyLabel  = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.07, alpha: 1)
        setupSheet()
        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadRecordings()
    }

    private func setupSheet() {
        if #available(iOS 15.0, *) {
            if let sheet = sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 20
            }
        }
        modalPresentationStyle = .automatic
    }

    // MARK: - Build UI

    private func buildUI() {
        titleLabel.font      = UIFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.50)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        tableView.backgroundColor = .clear
        tableView.separatorStyle  = .none
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.register(SessionCell.self, forCellReuseIdentifier: "SessionCell")
        tableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 24, right: 0)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        emptyLabel.text          = "暂无录制记录"
        emptyLabel.font          = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        emptyLabel.textColor     = UIColor.white.withAlphaComponent(0.28)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden      = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Load

    func loadRecordings() {
        let dir = Self.recordingsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { sessions = []; refresh(); return }

        var map: [String: SessionRecord] = [:]

        for url in files where url.pathExtension.lowercased() == "mp4" {
            let name  = url.deletingPathExtension().lastPathComponent
            // name format: composite_20241205_143022 or back_20241205_143022 or front_…
            guard let under = name.firstIndex(of: "_") else { continue }
            let type = String(name[name.startIndex ..< under])
            let ts   = String(name[name.index(after: under)...])
            guard !ts.isEmpty else { continue }

            if map[ts] == nil {
                map[ts] = SessionRecord(timestamp: ts, date: Self.parseDate(ts) ?? Date.distantPast)
            }
            switch type {
            case "composite": map[ts]?.compositeURL = url
            case "back":      map[ts]?.backURL      = url
            case "front":     map[ts]?.frontURL     = url
            default: break
            }
        }

        sessions = map.values.sorted { $0.date > $1.date }

        // Async duration loading
        for i in sessions.indices {
            let ts = sessions[i].timestamp
            guard let url = sessions[i].primaryURL else { continue }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let asset = AVAsset(url: url)
                let dur   = asset.duration
                let secs  = Int(CMTimeGetSeconds(dur))
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let idx = self.sessions.firstIndex(where: { $0.timestamp == ts }) {
                        self.sessions[idx].durationSeconds = secs
                        self.tableView.reloadRows(at: [IndexPath(row: idx, section: 0)], with: .none)
                    }
                }
            }
        }

        refresh()
    }

    private func refresh() {
        let count = sessions.count
        titleLabel.text    = count == 0 ? "RECORDINGS" : "RECORDINGS  ·  \(count)"
        emptyLabel.isHidden = count > 0
        tableView.reloadData()
    }

    // MARK: - Helpers

    static func sessionCount() -> Int {
        let dir   = recordingsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return 0 }
        var timestamps = Set<String>()
        for url in files where url.pathExtension.lowercased() == "mp4" {
            let name = url.deletingPathExtension().lastPathComponent
            guard let idx = name.firstIndex(of: "_") else { continue }
            timestamps.insert(String(name[name.index(after: idx)...]))
        }
        return timestamps.count
    }

    private static func recordingsDirectory() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func parseDate(_ ts: String) -> Date? {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        return df.date(from: ts)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension RecordingsListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sessions.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SessionCell", for: indexPath) as! SessionCell
        cell.configure(with: sessions[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 76 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let session = sessions[indexPath.row]

        // If multiple files exist, let user pick which to play
        let available: [(String, URL)] = [
            ("合成视频", session.compositeURL),
            ("后摄视频", session.backURL),
            ("前摄视频", session.frontURL),
        ].compactMap { name, url in url.map { (name, $0) } }

        guard !available.isEmpty else { return }

        if available.count == 1 {
            playVideo(available[0].1)
        } else {
            let sheet = UIAlertController(title: "选择播放", message: nil, preferredStyle: .actionSheet)
            for (name, url) in available {
                sheet.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                    self?.playVideo(url)
                })
            }
            sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
            if let pop = sheet.popoverPresentationController {
                pop.sourceView = tableView.cellForRow(at: indexPath)
            }
            present(sheet, animated: true)
        }
    }

    private func playVideo(_ url: URL) {
        let player = AVPlayer(url: url)
        let vc = AVPlayerViewController()
        vc.player = player
        present(vc, animated: true) { player.play() }
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let del = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            guard let self else { done(false); return }
            let session = self.sessions.remove(at: indexPath.row)
            [session.compositeURL, session.backURL, session.frontURL]
                .compactMap { $0 }
                .forEach { try? FileManager.default.removeItem(at: $0) }
            tableView.deleteRows(at: [indexPath], with: .automatic)
            self.refresh()
            NotificationCenter.default.post(name: .recordingsChanged, object: nil)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [del])
    }
}

// MARK: - Session Cell

private final class SessionCell: UITableViewCell {

    private let thumbBG       = UIView()
    private let thumbImgView  = UIImageView()
    private let playIcon      = UIImageView()
    private let dateLabel     = UILabel()
    private let durationLabel = UILabel()
    private let badgeStack    = UIStackView()
    private var thumbTask: DispatchWorkItem?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor  = .clear
        selectionStyle   = .none

        let sep = UIView()
        sep.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        sep.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sep)

        thumbBG.backgroundColor    = UIColor(white: 0.14, alpha: 1)
        thumbBG.layer.cornerRadius = 8
        thumbBG.clipsToBounds      = true
        thumbBG.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumbBG)

        thumbImgView.contentMode = .scaleAspectFill
        thumbImgView.translatesAutoresizingMaskIntoConstraints = false
        thumbBG.addSubview(thumbImgView)

        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .light)
        playIcon.image       = UIImage(systemName: "play.fill", withConfiguration: cfg)
        playIcon.tintColor   = UIColor.white.withAlphaComponent(0.40)
        playIcon.contentMode = .center
        playIcon.translatesAutoresizingMaskIntoConstraints = false
        thumbBG.addSubview(playIcon)

        dateLabel.font      = UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        dateLabel.textColor = .white
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dateLabel)

        durationLabel.font      = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        durationLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(durationLabel)

        badgeStack.axis      = .horizontal
        badgeStack.spacing   = 4
        badgeStack.alignment = .center
        badgeStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(badgeStack)

        NSLayoutConstraint.activate([
            sep.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            sep.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 0.5),

            thumbBG.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumbBG.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbBG.widthAnchor.constraint(equalToConstant: 80),
            thumbBG.heightAnchor.constraint(equalToConstant: 58),

            thumbImgView.topAnchor.constraint(equalTo: thumbBG.topAnchor),
            thumbImgView.bottomAnchor.constraint(equalTo: thumbBG.bottomAnchor),
            thumbImgView.leadingAnchor.constraint(equalTo: thumbBG.leadingAnchor),
            thumbImgView.trailingAnchor.constraint(equalTo: thumbBG.trailingAnchor),

            playIcon.centerXAnchor.constraint(equalTo: thumbBG.centerXAnchor),
            playIcon.centerYAnchor.constraint(equalTo: thumbBG.centerYAnchor),

            dateLabel.leadingAnchor.constraint(equalTo: thumbBG.trailingAnchor, constant: 12),
            dateLabel.topAnchor.constraint(equalTo: thumbBG.topAnchor, constant: 6),

            durationLabel.leadingAnchor.constraint(equalTo: thumbBG.trailingAnchor, constant: 12),
            durationLabel.bottomAnchor.constraint(equalTo: thumbBG.bottomAnchor, constant: -6),

            badgeStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            badgeStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with session: RecordingsListViewController.SessionRecord) {
        dateLabel.text     = session.displayTitle
        durationLabel.text = session.displayDuration

        // Format badges
        badgeStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (label, url) in [("C", session.compositeURL), ("B", session.backURL), ("F", session.frontURL)] {
            badgeStack.addArrangedSubview(makeBadge(label, active: url != nil))
        }

        // Thumbnail
        thumbImgView.image = nil
        playIcon.isHidden  = false
        thumbTask?.cancel()
        guard let url = session.primaryURL else { return }

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let asset = AVAsset(url: url)
            let gen   = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 160, height: 116)
            guard let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) else { return }
            let img = UIImage(cgImage: cg)
            DispatchQueue.main.async { [weak self] in
                self?.thumbImgView.image = img
                self?.playIcon.isHidden  = true
            }
        }
        thumbTask = task
        DispatchQueue.global(qos: .utility).async(execute: task)
    }

    private func makeBadge(_ text: String, active: Bool) -> UIView {
        let lbl = UILabel()
        lbl.text          = text
        lbl.font          = UIFont.monospacedSystemFont(ofSize: 8, weight: .bold)
        lbl.textColor     = active
            ? UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1)
            : UIColor.white.withAlphaComponent(0.20)
        lbl.textAlignment = .center

        let box = UIView()
        box.layer.cornerRadius = 3
        box.backgroundColor    = active
            ? UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 0.12)
            : .clear
        lbl.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: box.topAnchor, constant: 2),
            lbl.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -2),
            lbl.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 5),
            lbl.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -5),
        ])
        return box
    }
}

extension Notification.Name {
    static let recordingsChanged = Notification.Name("recordingsChanged")
}
