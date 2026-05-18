import Foundation

final class AppSettings {
    static let shared = AppSettings()
    private init() {}

    // MARK: - Capture mode

    enum CaptureMode: String { case video, photo }

    var captureMode: CaptureMode {
        get { CaptureMode(rawValue: UserDefaults.standard.string(forKey: "captureMode") ?? "") ?? .video }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "captureMode") }
    }

    // MARK: - Save outputs

    var saveComposite: Bool {
        get { UserDefaults.standard.object(forKey: "saveComposite") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "saveComposite") }
    }
    var saveBack: Bool {
        get { UserDefaults.standard.object(forKey: "saveBack") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "saveBack") }
    }
    var saveFront: Bool {
        get { UserDefaults.standard.object(forKey: "saveFront") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "saveFront") }
    }
    var atLeastOneSaveEnabled: Bool { saveComposite || saveBack || saveFront }

    // MARK: - PiP crop

    var frontPreviewMirrored: Bool {
        get { UserDefaults.standard.object(forKey: "frontPreviewMirrored") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "frontPreviewMirrored") }
    }

    var pipCropRect: PiPNormalizedRect {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: "pipCropRect.x") != nil else {
                return .fullFrame
            }
            return PiPNormalizedRect(
                x: CGFloat(defaults.double(forKey: "pipCropRect.x")),
                y: CGFloat(defaults.double(forKey: "pipCropRect.y")),
                width: CGFloat(defaults.double(forKey: "pipCropRect.width")),
                height: CGFloat(defaults.double(forKey: "pipCropRect.height"))
            ).clamped()
        }
        set {
            let rect = newValue.clamped()
            let defaults = UserDefaults.standard
            defaults.set(rect.x, forKey: "pipCropRect.x")
            defaults.set(rect.y, forKey: "pipCropRect.y")
            defaults.set(rect.width, forKey: "pipCropRect.width")
            defaults.set(rect.height, forKey: "pipCropRect.height")
        }
    }

    // MARK: - Video resolution

    enum VideoResolution: String {
        case hd720  = "720p"
        case hd1080 = "1080p"
        case uhd4k  = "4K"

        var hudLabel: String { rawValue.uppercased() }
        var targetWidth: Int {
            switch self {
            case .hd720:  return 1280
            case .hd1080: return 1920
            case .uhd4k:  return 3840
            }
        }
    }

    var videoResolution: VideoResolution {
        get { VideoResolution(rawValue: UserDefaults.standard.string(forKey: "videoResolution") ?? "") ?? .hd720 }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "videoResolution") }
    }

    // MARK: - Frame rate

    enum FrameRate: Int {
        case fps24 = 24
        case fps30 = 30
        case fps60 = 60

        var hudLabel: String { "\(rawValue)P" }
    }

    var frameRate: FrameRate {
        get { FrameRate(rawValue: UserDefaults.standard.integer(forKey: "frameRate")) ?? .fps60 }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "frameRate") }
    }

    // MARK: - Recording mirror

    var recordMirrored: Bool {
        get { UserDefaults.standard.bool(forKey: "recordMirrored") }
        set { UserDefaults.standard.set(newValue, forKey: "recordMirrored") }
    }

    // MARK: - PiP camera（小窗口摄像头）

    /// 小窗口（PiP）使用哪个摄像头：.front = 前置（默认），.backUltraWide = 后置超广角
    enum PiPCamera: String { case front, backUltraWide }

    var pipCamera: PiPCamera {
        get { PiPCamera(rawValue: UserDefaults.standard.string(forKey: "pipCamera") ?? "") ?? .front }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "pipCamera") }
    }

    // MARK: - Auto save to Photos

    var autoSaveToPhotos: Bool {
        get { UserDefaults.standard.object(forKey: "autoSaveToPhotos") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoSaveToPhotos") }
    }

    // MARK: - PiP Style

    var pipStyleID: String {
        get { UserDefaults.standard.string(forKey: "pipStyleID") ?? "standard" }
        set { UserDefaults.standard.set(newValue, forKey: "pipStyleID") }
    }

    // MARK: - Pro

    var isProUser: Bool {
        get { UserDefaults.standard.bool(forKey: "isProUser") }
        set { UserDefaults.standard.set(newValue, forKey: "isProUser") }
    }
}

extension Notification.Name {
    static let captureModeChanged   = Notification.Name("captureModeChanged")
    static let recordMirrorChanged  = Notification.Name("recordMirrorChanged")
    static let pipCameraChanged     = Notification.Name("pipCameraChanged")
    static let pipCropChanged       = Notification.Name("pipCropChanged")
    static let pipStyleChanged      = Notification.Name("pipStyleChanged")
    static let iapProductLoaded     = Notification.Name("iapProductLoaded")
}
