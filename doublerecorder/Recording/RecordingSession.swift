import Foundation

struct RecordingSession {
    let sessionID: String
    let startDate: Date
    let endDate: Date
    let compositeVideoURL: URL
    let backVideoURL: URL
    let frontVideoURL: URL

    var duration: TimeInterval { endDate.timeIntervalSince(startDate) }
}
