import UIKit
import AVFoundation
import AVKit
import CoreMedia

class RecordingsListViewController: UIViewController {

    // MARK: - Data model

    struct VideoRecord {
        let filename: String  // base name without extension, e.g. "20241205143022-merged"
        let date: Date
        let type: String      // "merged", "back", "front"
        let url: URL
        var durationSeconds: Int = 0
        var isPhoto: Bool = false

        var displayTitle: String {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "MM-dd  HH:mm:ss"
            return df.string(from: date)
        }
        var displayDuration: String {
            if isPhoto { return "—" }
            guard durationSeconds > 0 else { return "—" }
            let m = durationSeconds / 60
            let s = durationSeconds % 60
            return m > 0 ? "\(m):\(String(format: "%02d", s))" : "0:\(String(format: "%02d", s))"
        }
        var typeDisplay: String { type.uppercased() }
    }

    // MARK: - Views

    private var records: [VideoRecord] = []
    private let tableView  = UITableView(frame: .zero, style: .plain)
    private let titleLabel = UILabel()
    private let emptyLabel = UILabel()

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
        tableView.register(VideoCell.self, forCellReuseIdentifier: "VideoCell")
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
        ) else { records = []; refresh(); return }

        var result: [VideoRecord] = []
        for url in files {
            let ext = url.pathExtension.lowercased()
            guard ext == "mp4" || ext == "jpg" else { continue }
            // format: yyyyMMddHHmmss-type  e.g. 20241205143022-merged
            let name = url.deletingPathExtension().lastPathComponent
            guard let dash = name.firstIndex(of: "-") else { continue }
            let ts   = String(name[name.startIndex ..< dash])
            let type = String(name[name.index(after: dash)...])
            guard ts.count == 14, !type.isEmpty else { continue }
            let date = Self.parseDate(ts) ?? Date.distantPast
            result.append(VideoRecord(filename: name, date: date, type: type, url: url, isPhoto: ext == "jpg"))
        }
        records = result.sorted { $0.date > $1.date }

        for i in records.indices {
            guard !records[i].isPhoto else { continue }
            let filename = records[i].filename
            let url = records[i].url
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let secs = Int(CMTimeGetSeconds(AVAsset(url: url).duration))
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let idx = self.records.firstIndex(where: { $0.filename == filename }) {
                        self.records[idx].durationSeconds = secs
                        self.tableView.reloadRows(at: [IndexPath(row: idx, section: 0)], with: .none)
                    }
                }
            }
        }

        refresh()
    }

    private func refresh() {
        let count = records.count
        titleLabel.text     = count == 0 ? "RECORDINGS" : "RECORDINGS  ·  \(count)"
        emptyLabel.isHidden = count > 0
        tableView.reloadData()
    }

    // MARK: - Helpers

    static func sessionCount() -> Int {
        let dir = recordingsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return 0 }
        return files.filter { ["mp4", "jpg"].contains($0.pathExtension.lowercased()) }.count
    }

    static func recordingsDirectory() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func parseDate(_ ts: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMddHHmmss"
        return df.date(from: ts)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension RecordingsListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        records.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "VideoCell", for: indexPath) as! VideoCell
        cell.configure(with: records[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 76 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = records[indexPath.row]
        if record.isPhoto {
            present(PhotoViewerController(url: record.url), animated: true)
        } else {
            let player = AVPlayer(url: record.url)
            let vc = AVPlayerViewController()
            vc.player = player
            present(vc, animated: true) { player.play() }
        }
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let del = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            guard let self else { done(false); return }
            let record = self.records.remove(at: indexPath.row)
            try? FileManager.default.removeItem(at: record.url)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            self.refresh()
            NotificationCenter.default.post(name: .recordingsChanged, object: nil)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [del])
    }
}

// MARK: - Video Cell

private final class VideoCell: UITableViewCell {

    private let thumbBG         = UIView()
    private let thumbImgView    = UIImageView()
    private let playIcon        = UIImageView()
    private let mediaTypeBadge  = UIView()
    private let mediaTypeIcon   = UIImageView()
    private let dateLabel       = UILabel()
    private let filenameLabel   = UILabel()
    private let durationLabel   = UILabel()
    private let typeBadge       = UIView()
    private let typeBadgeLbl    = UILabel()
    private var thumbTask: DispatchWorkItem?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle  = .none

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

        // Media-type badge — bottom-right corner of thumbnail
        mediaTypeBadge.backgroundColor    = UIColor.black.withAlphaComponent(0.52)
        mediaTypeBadge.layer.cornerRadius = 4
        mediaTypeBadge.translatesAutoresizingMaskIntoConstraints = false
        thumbBG.addSubview(mediaTypeBadge)

        let badgeCfg = UIImage.SymbolConfiguration(pointSize: 8, weight: .medium)
        mediaTypeIcon.contentMode = .center
        mediaTypeIcon.tintColor   = UIColor.white.withAlphaComponent(0.85)
        mediaTypeIcon.preferredSymbolConfiguration = badgeCfg
        mediaTypeIcon.translatesAutoresizingMaskIntoConstraints = false
        mediaTypeBadge.addSubview(mediaTypeIcon)

        dateLabel.font      = UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        dateLabel.textColor = .white
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dateLabel)

        filenameLabel.font      = UIFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        filenameLabel.textColor = UIColor.white.withAlphaComponent(0.38)
        filenameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(filenameLabel)

        durationLabel.font      = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        durationLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(durationLabel)

        typeBadge.layer.cornerRadius = 3
        typeBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(typeBadge)

        typeBadgeLbl.font          = UIFont.monospacedSystemFont(ofSize: 8, weight: .bold)
        typeBadgeLbl.textAlignment = .center
        typeBadgeLbl.translatesAutoresizingMaskIntoConstraints = false
        typeBadge.addSubview(typeBadgeLbl)

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

            mediaTypeBadge.trailingAnchor.constraint(equalTo: thumbBG.trailingAnchor, constant: -5),
            mediaTypeBadge.bottomAnchor.constraint(equalTo: thumbBG.bottomAnchor, constant: -5),
            mediaTypeBadge.widthAnchor.constraint(equalToConstant: 20),
            mediaTypeBadge.heightAnchor.constraint(equalToConstant: 16),

            mediaTypeIcon.centerXAnchor.constraint(equalTo: mediaTypeBadge.centerXAnchor),
            mediaTypeIcon.centerYAnchor.constraint(equalTo: mediaTypeBadge.centerYAnchor),

            dateLabel.leadingAnchor.constraint(equalTo: thumbBG.trailingAnchor, constant: 12),
            dateLabel.topAnchor.constraint(equalTo: thumbBG.topAnchor, constant: 4),

            filenameLabel.leadingAnchor.constraint(equalTo: thumbBG.trailingAnchor, constant: 12),
            filenameLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 4),

            durationLabel.leadingAnchor.constraint(equalTo: thumbBG.trailingAnchor, constant: 12),
            durationLabel.bottomAnchor.constraint(equalTo: thumbBG.bottomAnchor, constant: -4),

            typeBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            typeBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            typeBadgeLbl.topAnchor.constraint(equalTo: typeBadge.topAnchor, constant: 3),
            typeBadgeLbl.bottomAnchor.constraint(equalTo: typeBadge.bottomAnchor, constant: -3),
            typeBadgeLbl.leadingAnchor.constraint(equalTo: typeBadge.leadingAnchor, constant: 6),
            typeBadgeLbl.trailingAnchor.constraint(equalTo: typeBadge.trailingAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with record: RecordingsListViewController.VideoRecord) {
        dateLabel.text     = record.displayTitle
        filenameLabel.text = record.filename
        durationLabel.text = record.displayDuration

        let amber = UIColor(red: 1,     green: 0.698, blue: 0.247, alpha: 1)
        let green = UIColor(red: 0.204, green: 0.78,  blue: 0.349, alpha: 1)
        let blue  = UIColor(red: 0.4,   green: 0.7,   blue: 1.0,   alpha: 1)

        let color: UIColor
        switch record.type {
        case "merged": color = amber
        case "back":   color = green
        case "front":  color = blue
        default:       color = UIColor.white.withAlphaComponent(0.6)
        }
        typeBadgeLbl.text         = record.typeDisplay
        typeBadgeLbl.textColor    = color
        typeBadge.backgroundColor = color.withAlphaComponent(0.15)

        thumbImgView.image = nil
        thumbTask?.cancel()

        let badgeCfg = UIImage.SymbolConfiguration(pointSize: 8, weight: .medium)
        let badgeIconName = record.isPhoto ? "photo.fill" : "video.fill"
        mediaTypeIcon.image = UIImage(systemName: badgeIconName, withConfiguration: badgeCfg)

        let url = record.url
        if record.isPhoto {
            playIcon.isHidden = true
            let task = DispatchWorkItem { [weak self] in
                guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.thumbImgView.image = img
                }
            }
            thumbTask = task
            DispatchQueue.global(qos: .utility).async(execute: task)
        } else {
            playIcon.isHidden = false
            let task = DispatchWorkItem { [weak self] in
                let gen = AVAssetImageGenerator(asset: AVAsset(url: url))
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
    }
}

extension Notification.Name {
    static let recordingsChanged = Notification.Name("recordingsChanged")
}

// MARK: - Photo Viewer

private final class PhotoViewerController: UIViewController {

    private let imageView = UIImageView()

    init(url: URL) {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return }
            DispatchQueue.main.async { self?.imageView.image = img }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeTapped)))
    }

    override var prefersStatusBarHidden: Bool { true }

    @objc private func closeTapped() { dismiss(animated: true) }
}
