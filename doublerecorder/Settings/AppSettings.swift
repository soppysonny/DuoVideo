import Foundation

final class AppSettings {
    static let shared = AppSettings()
    private init() {}

    enum CaptureMode: String { case video, photo }

    var captureMode: CaptureMode {
        get { CaptureMode(rawValue: UserDefaults.standard.string(forKey: "captureMode") ?? "") ?? .video }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "captureMode") }
    }

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

    var isProUser: Bool {
        get { UserDefaults.standard.bool(forKey: "isProUser") }
        set { UserDefaults.standard.set(newValue, forKey: "isProUser") }
    }

    var atLeastOneSaveEnabled: Bool { saveComposite || saveBack || saveFront }
}

extension Notification.Name {
    static let captureModeChanged = Notification.Name("captureModeChanged")
}
