import AVFoundation
import CoreMedia

class VideoRecorder {

    enum State { case idle, waitingForDimensions, recording, finishing }

    private(set) var state: State = .idle

    private var compositeWriter: AVAssetWriter?
    private var backWriter:      AVAssetWriter?
    private var frontWriter:     AVAssetWriter?

    // 延迟到拿到真实尺寸后才创建
    private var compositeVideoInput: AVAssetWriterInput?
    private var backVideoInput:      AVAssetWriterInput?
    private var frontVideoInput:     AVAssetWriterInput?
    private var compositeAudioInput: AVAssetWriterInput?
    private var backAudioInput:      AVAssetWriterInput?
    private var frontAudioInput:     AVAssetWriterInput?

    var isMicMuted = false

    private let compositor = PiPCompositor()

    private var latestFrontPixelBuffer: CVPixelBuffer?
    private var sessionStartTime: CMTime = .invalid
    private var writersInitialized = false

    // 从第一帧检测真实尺寸
    private var backDimensions:  (width: Int, height: Int)?
    private var frontDimensions: (width: Int, height: Int)?
    private var pendingBackBuffer: CMSampleBuffer?

    private let writeQueue = DispatchQueue(label: "com.mbjztech.doublerecorder.write",
                                           qos: .userInitiated)
    private var recordingStartDate = Date()

    // MARK: - Public

    func startRecording() throws {
        guard state == .idle else { throw RecorderError.alreadyRecording }

        let timestamp = DateFormatter.fileTimestamp.string(from: Date())
        compositeWriter = try AVAssetWriter(url: makeOutputURL(suffix: "composite_\(timestamp)"), fileType: .mp4)
        backWriter      = try AVAssetWriter(url: makeOutputURL(suffix: "back_\(timestamp)"),      fileType: .mp4)
        frontWriter     = try AVAssetWriter(url: makeOutputURL(suffix: "front_\(timestamp)"),     fileType: .mp4)

        writersInitialized = false
        backDimensions     = nil
        frontDimensions    = nil
        pendingBackBuffer  = nil
        sessionStartTime   = .invalid
        latestFrontPixelBuffer = nil
        recordingStartDate = Date()
        state = .waitingForDimensions
    }

    func stopRecording(completion: @escaping (Result<RecordingSession, Error>) -> Void) {
        guard state == .recording || state == .waitingForDimensions else {
            completion(.failure(RecorderError.notRecording)); return
        }
        state = .finishing

        writeQueue.async { [weak self] in
            guard let self else { return }

            guard self.writersInitialized else {
                DispatchQueue.main.async { [weak self] in
                    self?.state = .idle
                    completion(.failure(RecorderError.writerSetupFailed("未收到任何视频帧")))
                }
                return
            }

            self.compositeVideoInput?.markAsFinished()
            self.backVideoInput?.markAsFinished()
            self.frontVideoInput?.markAsFinished()
            self.compositeAudioInput?.markAsFinished()
            self.backAudioInput?.markAsFinished()
            self.frontAudioInput?.markAsFinished()

            let endDate      = Date()
            let compositeURL = self.compositeWriter?.outputURL
            let backURL      = self.backWriter?.outputURL
            let frontURL     = self.frontWriter?.outputURL

            let group = DispatchGroup()
            var finishError: Error?

            for writer in [self.compositeWriter, self.backWriter, self.frontWriter].compactMap({ $0 }) {
                group.enter()
                writer.finishWriting {
                    if let err = writer.error { finishError = err }
                    group.leave()
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self else { return }
                self.state = .idle

                if let err = finishError { completion(.failure(err)); return }
                guard let cURL = compositeURL, let bURL = backURL, let fURL = frontURL else {
                    completion(.failure(RecorderError.writerSetupFailed("输出路径为空"))); return
                }
                completion(.success(RecordingSession(
                    sessionID: UUID().uuidString,
                    startDate: self.recordingStartDate,
                    endDate: endDate,
                    compositeVideoURL: cURL,
                    backVideoURL: bURL,
                    frontVideoURL: fURL
                )))
            }
        }
    }

    // MARK: - 帧输入

    func appendBackVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard state == .waitingForDimensions || state == .recording else { return }
        writeQueue.async { [weak self] in
            guard let self else { return }

            if !self.writersInitialized {
                if self.backDimensions == nil,
                   let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    self.backDimensions = (CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb))
                    self.pendingBackBuffer = sampleBuffer
                    self.tryInitializeWriters()
                }
                return
            }
            self.processBackFrame(sampleBuffer)
        }
    }

    func appendFrontVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard state == .waitingForDimensions || state == .recording else { return }
        writeQueue.async { [weak self] in
            guard let self else { return }

            // 始终更新最新前摄帧供合成使用
            if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                self.latestFrontPixelBuffer = pb
            }

            if !self.writersInitialized {
                if self.frontDimensions == nil,
                   let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    self.frontDimensions = (CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb))
                    self.tryInitializeWriters()
                }
                return
            }

            guard self.sessionStartTime != .invalid,
                  let input = self.frontVideoInput,
                  input.isReadyForMoreMediaData else { return }
            input.append(sampleBuffer)
        }
    }

    func appendAudioFrame(_ sampleBuffer: CMSampleBuffer) {
        guard state == .recording, !isMicMuted else { return }
        writeQueue.async { [weak self] in
            self?.distributeAudio(sampleBuffer)
        }
    }

    // MARK: - 延迟初始化（拿到前后摄真实尺寸后）

    private func tryInitializeWriters() {
        guard !writersInitialized,
              let back  = backDimensions,
              let front = frontDimensions,
              let compositeWriter, let backWriter, let frontWriter
        else { return }

        // 用真实尺寸配置 PiP 宽高比
        compositor?.configure(backWidth: back.width, backHeight: back.height,
                              frontWidth: front.width, frontHeight: front.height)

        // 合成视频用后摄分辨率，独立视频各用各自分辨率
        compositeVideoInput = makeVideoInput(settings: videoSettings(width: back.width,  height: back.height))
        backVideoInput      = makeVideoInput(settings: videoSettings(width: back.width,  height: back.height))
        frontVideoInput     = makeVideoInput(settings: videoSettings(width: front.width, height: front.height))
        compositeAudioInput = makeAudioInput()
        backAudioInput      = makeAudioInput()
        frontAudioInput     = makeAudioInput()

        for (writer, videoInput, audioInput) in [
            (compositeWriter, compositeVideoInput!, compositeAudioInput!),
            (backWriter,      backVideoInput!,      backAudioInput!),
            (frontWriter,     frontVideoInput!,     frontAudioInput!)
        ] {
            if writer.canAdd(videoInput) { writer.add(videoInput) }
            if writer.canAdd(audioInput) { writer.add(audioInput) }
            writer.startWriting()
        }

        writersInitialized = true
        state = .recording

        if let pending = pendingBackBuffer {
            pendingBackBuffer = nil
            processBackFrame(pending)
        }
    }

    // MARK: - 帧处理

    private func processBackFrame(_ sampleBuffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if sessionStartTime == .invalid {
            sessionStartTime = pts
            compositeWriter?.startSession(atSourceTime: pts)
            backWriter?.startSession(atSourceTime: pts)
            frontWriter?.startSession(atSourceTime: pts)
        }

        if let input = backVideoInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }

        guard
            let compositor,
            let backBuffer  = CMSampleBufferGetImageBuffer(sampleBuffer),
            let frontBuffer = latestFrontPixelBuffer,
            let composed    = compositor.composite(backBuffer: backBuffer, frontBuffer: frontBuffer)
        else { return }

        appendCompositeFrame(composed, presentationTime: pts)
    }

    private func appendCompositeFrame(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard
            let input = compositeVideoInput,
            input.isReadyForMoreMediaData
        else { return }

        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var fmt: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &fmt)
        guard let fmt else { return }

        var sb: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: fmt,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sb
        )
        if let sb { input.append(sb) }
    }

    private func distributeAudio(_ sampleBuffer: CMSampleBuffer) {
        guard sessionStartTime != .invalid else { return }

        if let input = compositeAudioInput, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
        if let input = backAudioInput, input.isReadyForMoreMediaData {
            var copy: CMSampleBuffer?
            CMSampleBufferCreateCopy(allocator: kCFAllocatorDefault,
                                     sampleBuffer: sampleBuffer, sampleBufferOut: &copy)
            if let copy { input.append(copy) }
        }
        if let input = frontAudioInput, input.isReadyForMoreMediaData {
            var copy: CMSampleBuffer?
            CMSampleBufferCreateCopy(allocator: kCFAllocatorDefault,
                                     sampleBuffer: sampleBuffer, sampleBufferOut: &copy)
            if let copy { input.append(copy) }
        }
    }

    // MARK: - 工厂

    private func makeVideoInput(settings: [String: Any]) -> AVAssetWriterInput {
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    private func makeAudioInput() -> AVAssetWriterInput {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    private func videoSettings(width: Int, height: Int) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]
    }

    private var audioSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128_000
        ]
    }

    private func makeOutputURL(suffix: String) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(suffix).mp4")
    }
}

enum RecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case writerSetupFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:         return "已在录制中"
        case .notRecording:             return "未在录制"
        case .writerSetupFailed(let m): return m
        }
    }
}

private extension DateFormatter {
    static let fileTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()
}
