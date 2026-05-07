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
        modalPresentationStyle = .fullScreen
    }

    // MARK: - Build UI

    private func buildUI() {
        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeBtn.tintColor = UIColor.white.withAlphaComponent(0.55)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeBtn.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            closeBtn.widthAnchor.constraint(equalToConstant: 30),
            closeBtn.heightAnchor.constraint(equalToConstant: 30),
        ])

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
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func closeTapped() { dismiss(animated: true) }

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
            present(VideoPlayerViewController(url: record.url), animated: true)
        }
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let del = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            guard let self else { done(false); return }
            let record = self.records.remove(at: indexPath.row)
            try? FileManager.default.removeItem(at: record.url)
            ThumbnailCache.shared.remove(key: record.filename)
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
        thumbTask = nil

        let badgeCfg = UIImage.SymbolConfiguration(pointSize: 8, weight: .medium)
        let badgeIconName = record.isPhoto ? "photo.fill" : "video.fill"
        mediaTypeIcon.image = UIImage(systemName: badgeIconName, withConfiguration: badgeCfg)

        let url = record.url
        let cacheKey = record.filename

        // 先命中缓存，直接显示
        if let cached = ThumbnailCache.shared.get(key: cacheKey) {
            thumbImgView.image = cached
            playIcon.isHidden  = true
            return
        }

        if record.isPhoto {
            playIcon.isHidden = true
            let task = DispatchWorkItem { [weak self] in
                guard let data = try? Data(contentsOf: url),
                      let img = UIImage(data: data) else { return }
                // 缩小为缩略图尺寸再缓存
                let thumb: UIImage
                if #available(iOS 15.0, *) {
                    thumb = img.preparingThumbnail(of: CGSize(width: 160, height: 116)) ?? img
                } else {
                    let size = CGSize(width: 160, height: 116)
                    UIGraphicsBeginImageContextWithOptions(size, false, 0)
                    img.draw(in: CGRect(origin: .zero, size: size))
                    thumb = UIGraphicsGetImageFromCurrentImageContext() ?? img
                    UIGraphicsEndImageContext()
                }
                ThumbnailCache.shared.set(thumb, key: cacheKey)
                DispatchQueue.main.async { [weak self] in
                    self?.thumbImgView.image = thumb
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
                ThumbnailCache.shared.set(img, key: cacheKey)
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

// MARK: - Thumbnail Cache (memory + disk, JPEG compressed)

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private init() {}

    private let memory = NSCache<NSString, UIImage>()
    private let diskQueue = DispatchQueue(label: "com.mbjztech.thumbcache", qos: .utility)
    private var diskDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThumbnailCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func get(key: String) -> UIImage? {
        if let img = memory.object(forKey: key as NSString) { return img }
        let path = diskDir.appendingPathComponent(key + ".jpg").path
        if let data = FileManager.default.contents(atPath: path), let img = UIImage(data: data) {
            memory.setObject(img, forKey: key as NSString)
            return img
        }
        return nil
    }

    func set(_ image: UIImage, key: String) {
        memory.setObject(image, forKey: key as NSString)
        let url = diskDir.appendingPathComponent(key + ".jpg")
        diskQueue.async {
            if let data = image.jpegData(compressionQuality: 0.72) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func remove(key: String) {
        memory.removeObject(forKey: key as NSString)
        diskQueue.async { [diskDir] in
            try? FileManager.default.removeItem(at: diskDir.appendingPathComponent(key + ".jpg"))
        }
    }
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

// MARK: - Video Player (AVPlayerLayer-based, no system chrome)

final class VideoPlayerViewController: UIViewController {

    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var timeObserver: Any?

    // Controls
    private let controlsView  = UIView()
    private let playPauseBtn  = UIButton(type: .system)
    private let scrubber      = UISlider()
    private let currentTimeLbl = UILabel()
    private let totalTimeLbl   = UILabel()
    private let closeBtn       = UIButton(type: .system)
    private var hideControlsTimer: Timer?
    private var isScrubbing = false

    init(url: URL) {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item  = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        playerLayer.player       = player
        playerLayer.videoGravity = .resizeAspect
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Player layer
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)

        // Tap to toggle controls
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)

        buildControls()
        addTimeObserver()
        scheduleHideControls()
        player?.play()

        NotificationCenter.default.addObserver(self, selector: #selector(playerDidEnd),
                                               name: .AVPlayerItemDidPlayToEndTime,
                                               object: player?.currentItem)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = view.bounds
        let safe = view.safeAreaInsets
        let cH: CGFloat = 80
        controlsView.frame = CGRect(x: 0, y: view.bounds.height - safe.bottom - cH,
                                    width: view.bounds.width, height: cH)
        closeBtn.frame = CGRect(x: safe.left + 16, y: safe.top + 12, width: 36, height: 36)
    }

    override var prefersStatusBarHidden: Bool { true }

    private func buildControls() {
        // Semi-transparent bottom bar
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
        blur.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 80)
        blur.autoresizingMask = [.flexibleWidth]
        controlsView.addSubview(blur)
        view.addSubview(controlsView)

        // Play/pause
        let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        playPauseBtn.setImage(UIImage(systemName: "pause.fill", withConfiguration: cfg), for: .normal)
        playPauseBtn.tintColor = .white
        playPauseBtn.translatesAutoresizingMaskIntoConstraints = false
        playPauseBtn.addTarget(self, action: #selector(togglePlayPause), for: .touchUpInside)
        controlsView.addSubview(playPauseBtn)

        // Scrubber
        scrubber.minimumTrackTintColor = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 1)
        scrubber.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        scrubber.thumbTintColor        = .white
        scrubber.translatesAutoresizingMaskIntoConstraints = false
        scrubber.addTarget(self, action: #selector(scrubberChanged), for: .valueChanged)
        scrubber.addTarget(self, action: #selector(scrubberTouchDown), for: .touchDown)
        scrubber.addTarget(self, action: #selector(scrubberTouchUp), for: [.touchUpInside, .touchUpOutside])
        controlsView.addSubview(scrubber)

        let timeFontSize: CGFloat = 10
        for lbl in [currentTimeLbl, totalTimeLbl] {
            lbl.font      = UIFont.monospacedDigitSystemFont(ofSize: timeFontSize, weight: .regular)
            lbl.textColor = UIColor.white.withAlphaComponent(0.7)
            lbl.translatesAutoresizingMaskIntoConstraints = false
            controlsView.addSubview(lbl)
        }
        currentTimeLbl.text = "0:00"
        totalTimeLbl.text   = "0:00"

        // Close button
        let closeCfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        closeBtn.setImage(UIImage(systemName: "xmark", withConfiguration: closeCfg), for: .normal)
        closeBtn.tintColor       = UIColor.white.withAlphaComponent(0.8)
        closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        closeBtn.layer.cornerRadius = 18
        closeBtn.clipsToBounds = true
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            playPauseBtn.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 16),
            playPauseBtn.centerYAnchor.constraint(equalTo: controlsView.centerYAnchor),
            playPauseBtn.widthAnchor.constraint(equalToConstant: 36),
            playPauseBtn.heightAnchor.constraint(equalToConstant: 36),

            currentTimeLbl.leadingAnchor.constraint(equalTo: playPauseBtn.trailingAnchor, constant: 8),
            currentTimeLbl.centerYAnchor.constraint(equalTo: controlsView.centerYAnchor),

            totalTimeLbl.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -16),
            totalTimeLbl.centerYAnchor.constraint(equalTo: controlsView.centerYAnchor),

            scrubber.leadingAnchor.constraint(equalTo: currentTimeLbl.trailingAnchor, constant: 6),
            scrubber.trailingAnchor.constraint(equalTo: totalTimeLbl.leadingAnchor, constant: -6),
            scrubber.centerYAnchor.constraint(equalTo: controlsView.centerYAnchor),
        ])

        // Fetch total duration asynchronously
        player?.currentItem?.asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      let dur = self.player?.currentItem?.asset.duration,
                      dur.isNumeric else { return }
                self.totalTimeLbl.text = Self.formatTime(CMTimeGetSeconds(dur))
            }
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.isScrubbing else { return }
            let secs    = CMTimeGetSeconds(time)
            let durSecs = CMTimeGetSeconds(self.player?.currentItem?.duration ?? .zero)
            self.currentTimeLbl.text = Self.formatTime(secs)
            if durSecs > 0 { self.scrubber.value = Float(secs / durSecs) }
            let isPlaying = self.player?.timeControlStatus == .playing
            let iconName  = isPlaying ? "pause.fill" : "play.fill"
            let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            self.playPauseBtn.setImage(UIImage(systemName: iconName, withConfiguration: cfg), for: .normal)
        }
    }

    private func scheduleHideControls() {
        hideControlsTimer?.invalidate()
        hideControlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3) { self?.controlsView.alpha = 0; self?.closeBtn.alpha = 0 }
        }
    }

    private static func formatTime(_ secs: Double) -> String {
        guard secs.isFinite && secs >= 0 else { return "0:00" }
        let s = Int(secs)
        let m = s / 60
        return "\(m):\(String(format: "%02d", s % 60))"
    }

    // MARK: - Actions

    @objc private func handleTap() {
        let hidden = controlsView.alpha < 0.5
        UIView.animate(withDuration: 0.2) {
            self.controlsView.alpha = hidden ? 1 : 0
            self.closeBtn.alpha     = hidden ? 1 : 0
        }
        if hidden { scheduleHideControls() }
    }

    @objc private func togglePlayPause() {
        guard let player else { return }
        if player.timeControlStatus == .playing { player.pause() }
        else { player.play() }
        scheduleHideControls()
    }

    @objc private func scrubberTouchDown() { isScrubbing = true; hideControlsTimer?.invalidate() }

    @objc private func scrubberChanged() {
        guard let dur = player?.currentItem?.duration, dur.isNumeric else { return }
        let secs = Double(scrubber.value) * CMTimeGetSeconds(dur)
        currentTimeLbl.text = Self.formatTime(secs)
    }

    @objc private func scrubberTouchUp() {
        guard let dur = player?.currentItem?.duration, dur.isNumeric else { isScrubbing = false; return }
        let secs   = Double(scrubber.value) * CMTimeGetSeconds(dur)
        let target = CMTime(seconds: secs, preferredTimescale: 600)
        player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.isScrubbing = false
        }
        scheduleHideControls()
    }

    @objc private func playerDidEnd() {
        player?.seek(to: .zero)
        let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        playPauseBtn.setImage(UIImage(systemName: "play.fill", withConfiguration: cfg), for: .normal)
        UIView.animate(withDuration: 0.2) { self.controlsView.alpha = 1; self.closeBtn.alpha = 1 }
        hideControlsTimer?.invalidate()
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    deinit {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        NotificationCenter.default.removeObserver(self)
    }
}
