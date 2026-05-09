import FirebaseAnalytics

enum AnalyticsManager {

    // MARK: - Event Names

    private enum Event: String {
        case captureTap     = "capture_tap"
        case recordingStart = "recording_start"
        case recordingStop  = "recording_stop"
        case shareContent   = "share_content"
        case purchaseClick  = "purchase_click"
        case purchaseOK     = "purchase_ok"
        case configChanged  = "config_changed"
    }

    private enum Param: String {
        case resolution = "resolution"
        case frameRate  = "frame_rate"
        case isPhoto    = "is_photo"
        case isMirror   = "is_mirror"
        case pipCamera  = "pip_camera"
        case settingKey = "setting_key"
        case settingVal = "setting_value"
        case contentType = "content_type"
        case durationS   = "duration_seconds"
        case fileCount   = "file_count"
    }

    // MARK: - Capture

    static func logCaptureTap(isPhoto: Bool, resolution: String, frameRate: String,
                              isMirror: Bool, pipCamera: String) {
        log(.captureTap, params: [
            .isPhoto:    "\(isPhoto)",
            .resolution: resolution,
            .frameRate:  frameRate,
            .isMirror:   "\(isMirror)",
            .pipCamera:  pipCamera,
        ])
    }

    // MARK: - Recording

    static func logRecordingStart(resolution: String, frameRate: String,
                                  isMirror: Bool, pipCamera: String) {
        log(.recordingStart, params: [
            .resolution: resolution,
            .frameRate:  frameRate,
            .isMirror:   "\(isMirror)",
            .pipCamera:  pipCamera,
        ])
    }

    static func logRecordingStop(durationSeconds: Int, fileCount: Int) {
        log(.recordingStop, params: [
            .durationS: "\(durationSeconds)",
            .fileCount: "\(fileCount)",
        ])
    }

    // MARK: - Share

    static func logShare(contentType: String) {
        log(.shareContent, params: [.contentType: contentType])
    }

    // MARK: - IAP

    static func logPurchaseClick() {
        log(.purchaseClick)
    }

    static func logPurchaseOK() {
        log(.purchaseOK)
    }

    // MARK: - Config

    static func logConfigChanged(key: String, value: String) {
        log(.configChanged, params: [.settingKey: key, .settingVal: value])
    }

    // MARK: - Private

    private static func log(_ event: Event, params: [Param: String] = [:]) {
        let p = Dictionary(uniqueKeysWithValues: params.map { ($0.rawValue, $1) })
        Analytics.logEvent(event.rawValue, parameters: p)
    }
}
