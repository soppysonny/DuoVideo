import AVFoundation
import CoreMedia

class VideoRecorder {

    enum State { case idle, waitingForDimensions, recording, finishing }

    private(set) var state: State = .idle

    // 保存配置（录制开始前由外部设置）
    var saveComposite = true
    var saveBack      = true
    var saveFront     = true

    private var compositeWriter: AVAssetWriter?
    private var backWriter:      AVAssetWriter?
    private var frontWriter:     AVAssetWriter?

    private var compositeVideoInput: AVAssetWriterInput?
    private var backVideoInput:      AVAssetWriterInput?
    private var frontVideoInput:     AVAssetWriterInput?
    private var compositeAudioInput: AVAssetWriterInput?
    private var backAudioInput:      AVAssetWriterInput?
    private var frontAudioInput:     AVAssetWriterInput?

    var isMicMuted = false

    private let compositor = PiPCompositor()
    // Screen-space PiP layout info (set by ViewController, mapped to video coords when frame size is known)
    private var storedScreenOriginX: Float?
    private var storedScreenOriginY: Float?
    private var storedScreenPipW: Float?
    private var storedScreenPipH: Float?
    private var storedScreenW: Float?
    private var storedScreenH: Float?

    private(set) var latestBackPixelBuffer:  CVPixelBuffer?
    private(set) var latestFrontPixelBuffer: CVPixelBuffer?

    private var sessionStartTime: CMTime = .invalid
    private var writersInitialized = false

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
        compositeWriter = saveComposite ? try AVAssetWriter(url: makeOutputURL(suffix: "\(timestamp)-merged"), fileType: .mp4) : nil
        backWriter      = saveBack      ? try AVAssetWriter(url: makeOutputURL(suffix: "\(timestamp)-back"),   fileType: .mp4) : nil
        frontWriter     = saveFront     ? try AVAssetWriter(url: makeOutputURL(suffix: "\(timestamp)-front"),  fileType: .mp4) : nil

        writersInitialized = false
        backDimensions     = nil
        frontDimensions    = nil
        pendingBackBuffer  = nil
        sessionStartTime   = .invalid
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
                completion(.success(RecordingSession(
                    sessionID: UUID().uuidString,
                    startDate: self.recordingStartDate,
                    endDate: endDate,
                    compositeVideoURL: compositeURL,
                    backVideoURL: backURL,
                    frontVideoURL: frontURL
                )))
            }
        }
    }

    // MARK: - 帧输入

    func appendBackVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        writeQueue.async { [weak self] in
            guard let self else { return }

            if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                self.latestBackPixelBuffer = pb
            }

            guard self.state == .waitingForDimensions || self.state == .recording else { return }

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
        writeQueue.async { [weak self] in
            guard let self else { return }

            if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                self.latestFrontPixelBuffer = pb
            }

            guard self.state == .waitingForDimensions || self.state == .recording else { return }

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

    // MARK: - PiP 角落同步（合成视频跟随预览位置）

    func updatePiPCorner(isLeft: Bool, isTop: Bool) {
        writeQueue.async { [weak self] in
            self?.compositor?.updateCorner(isLeft: isLeft, isTop: isTop)
        }
    }

    /// 用屏幕坐标同步 PiP 位置。VideoRecorder 会根据 back 帧尺寸和 resizeAspectFill 几何关系
    /// 将屏幕坐标映射到视频归一化坐标，避免宽高比差异导致录像 PiP 被截断。
    func updatePiPLayout(screenOriginX: Float, screenOriginY: Float,
                         screenPipW: Float, screenPipH: Float,
                         screenW: Float, screenH: Float) {
        writeQueue.async { [weak self] in
            guard let self else { return }
            self.storedScreenOriginX = screenOriginX
            self.storedScreenOriginY = screenOriginY
            self.storedScreenPipW    = screenPipW
            self.storedScreenPipH    = screenPipH
            self.storedScreenW       = screenW
            self.storedScreenH       = screenH
            self.applyScreenLayout()
        }
    }

    private func applyScreenLayout(overrideBackW: Int? = nil, overrideBackH: Int? = nil) {
        guard let comp = compositor else { return }
        guard let sW = storedScreenW, let sH = storedScreenH, sW > 0, sH > 0 else { return }
        guard let ox = storedScreenOriginX, let oy = storedScreenOriginY else { return }
        guard let pw = storedScreenPipW, let ph = storedScreenPipH else { return }

        let rawBW = overrideBackW ?? backDimensions?.width
        let rawBH = overrideBackH ?? backDimensions?.height

        if let bW = rawBW.map(Float.init), let bH = rawBH.map(Float.init), bW > 0, bH > 0 {
            // 预览使用 resizeAspectFill：确定是按宽还是按高缩放及裁切偏移
            let videoAspect  = bW / bH
            let screenAspect = sW / sH
            let scale: Float
            let cropX: Float
            let cropY: Float
            if videoAspect > screenAspect {
                // 按高缩放，左右裁切
                scale = sH / bH
                cropX = (bW * scale - sW) / 2
                cropY = 0
            } else {
                // 按宽缩放，上下裁切
                scale = sW / bW
                cropX = 0
                cropY = (bH * scale - sH) / 2
            }
            comp.params.pipOriginX = (ox + cropX) / (scale * bW)
            comp.params.pipOriginY = (oy + cropY) / (scale * bH)
            comp.params.pipWidth   = pw / (scale * bW)
            comp.params.pipHeight  = ph / (scale * bH)
        } else {
            // 帧尺寸未知时回退：Y 轴按高填充时天然正确
            comp.params.pipOriginX = ox / sW
            comp.params.pipOriginY = oy / sH
            comp.params.pipWidth   = pw / sW
            comp.params.pipHeight  = ph / sH
        }
    }

    // MARK: - 拍照用快照

    func makePhotoComposite(completion: @escaping (CVPixelBuffer?) -> Void) {
        writeQueue.async { [weak self] in
            guard let self,
                  let back  = self.latestBackPixelBuffer,
                  let front = self.latestFrontPixelBuffer,
                  let comp  = self.compositor else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // 录制前拍照时 compositor 尚未被 tryInitializeWriters 配置，在此按需配置
            if !self.writersInitialized {
                let bW = CVPixelBufferGetWidth(back)
                let bH = CVPixelBufferGetHeight(back)
                comp.configure(backWidth: bW, backHeight: bH,
                               frontWidth:  CVPixelBufferGetWidth(front),
                               frontHeight: CVPixelBufferGetHeight(front))
                self.applyScreenLayout(overrideBackW: bW, overrideBackH: bH)
            }
            let result = comp.composite(backBuffer: back, frontBuffer: front)
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - 延迟初始化

    private func tryInitializeWriters() {
        guard !writersInitialized,
              let back  = backDimensions,
              let front = frontDimensions,
              state == .waitingForDimensions
        else { return }

        guard compositeWriter != nil || backWriter != nil || frontWriter != nil else { return }

        compositor?.configure(backWidth: back.width, backHeight: back.height,
                              frontWidth: front.width, frontHeight: front.height)
        applyScreenLayout()  // 用屏幕坐标精确覆盖 configure 产生的默认 PiP 参数

        if let w = compositeWriter {
            compositeVideoInput = makeVideoInput(settings: videoSettings(width: back.width, height: back.height))
            compositeAudioInput = makeAudioInput()
            if w.canAdd(compositeVideoInput!) { w.add(compositeVideoInput!) }
            if w.canAdd(compositeAudioInput!) { w.add(compositeAudioInput!) }
            w.startWriting()
        }
        if let w = backWriter {
            backVideoInput = makeVideoInput(settings: videoSettings(width: back.width, height: back.height))
            backAudioInput = makeAudioInput()
            if w.canAdd(backVideoInput!) { w.add(backVideoInput!) }
            if w.canAdd(backAudioInput!) { w.add(backAudioInput!) }
            w.startWriting()
        }
        if let w = frontWriter {
            frontVideoInput = makeVideoInput(settings: videoSettings(width: front.width, height: front.height))
            frontAudioInput = makeAudioInput()
            if w.canAdd(frontVideoInput!) { w.add(frontVideoInput!) }
            if w.canAdd(frontAudioInput!) { w.add(frontAudioInput!) }
            w.startWriting()
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

        guard saveComposite,
              let compositor,
              let backBuffer  = CMSampleBufferGetImageBuffer(sampleBuffer),
              let frontBuffer = latestFrontPixelBuffer,
              let composed    = compositor.composite(backBuffer: backBuffer, frontBuffer: frontBuffer)
        else { return }

        appendCompositeFrame(composed, presentationTime: pts)
    }

    private func appendCompositeFrame(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let input = compositeVideoInput, input.isReadyForMoreMediaData else { return }

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
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }()
}
