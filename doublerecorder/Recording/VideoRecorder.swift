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

    // 屏幕空间 PiP 布局（各层的坐标由 syncLayers / updatePiPLayout 写入）
    private struct StoredPiPLayout {
        let origin:       CGPoint
        let size:         CGSize
        let cornerRadius: Float
        let isCircle:     Bool
        let isSplitH:     Bool
    }
    private var storedPiPLayouts: [StoredPiPLayout] = []
    private var storedScreenBounds: CGSize = .zero

    private(set) var latestBackPixelBuffer:  CVPixelBuffer?
    private(set) var latestFrontPixelBuffer: CVPixelBuffer?

    /// true = 后摄作为 PiP 小窗，前摄铺满背景；false（默认）= 前摄作为 PiP
    var pipCameraIsBack: Bool = false

    /// PiP 小窗摄像头的宽高比（宽/高）。未收到帧时返回 nil。
    var pipFrameAspect: CGFloat? {
        let buf = pipCameraIsBack ? latestBackPixelBuffer : latestFrontPixelBuffer
        guard let buf else { return nil }
        let h = CVPixelBufferGetHeight(buf)
        guard h > 0 else { return nil }
        return CGFloat(CVPixelBufferGetWidth(buf)) / CGFloat(h)
    }

    /// 首次收到前摄帧时在主线程回调一次（用于更新依赖实际宽高比的布局）。
    var onFirstFrontFrame: (() -> Void)?
    private var didReceiveFirstFrontFrame = false

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

        let dir = recordingsDir()
        let backPrefix = pipCameraIsBack ? "wide" : "back"
        let mergedName = Self.seqFilename(prefix: "merged", in: dir)
        let backName   = Self.seqFilename(prefix: backPrefix, in: dir)
        let frontName  = Self.seqFilename(prefix: "front", in: dir)

        compositeWriter = saveComposite ? try AVAssetWriter(url: makeOutputURL(name: mergedName), fileType: .mp4) : nil
        backWriter      = saveBack      ? try AVAssetWriter(url: makeOutputURL(name: backName),   fileType: .mp4) : nil
        frontWriter     = saveFront     ? try AVAssetWriter(url: makeOutputURL(name: frontName),  fileType: .mp4) : nil

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
                let isFirst = self.latestFrontPixelBuffer == nil && !self.didReceiveFirstFrontFrame
                self.latestFrontPixelBuffer = pb
                if isFirst {
                    self.didReceiveFirstFrontFrame = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onFirstFrontFrame?()
                        self?.onFirstFrontFrame = nil
                    }
                }
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

    /// 切换摄像头配置时调用，清除旧帧缓存和首帧标记，使新相机的首帧能正确触发布局更新。
    func resetFrameTracking() {
        writeQueue.async { [weak self] in
            guard let self else { return }
            self.latestBackPixelBuffer = nil
            self.latestFrontPixelBuffer = nil
            self.didReceiveFirstFrontFrame = false
        }
    }

    func appendAudioFrame(_ sampleBuffer: CMSampleBuffer) {
        guard state == .recording, !isMicMuted else { return }
        writeQueue.async { [weak self] in
            self?.distributeAudio(sampleBuffer)
        }
    }

    // MARK: - PiP 布局同步

    /// 用 VideoLayer 数组同步 PiP 布局（主接口）。
    /// 非背景层按 zOrder 升序传入，对应 compositor 的 layer 0..N。
    func syncLayers(_ layers: [VideoLayer], screenBounds: CGSize) {
        let layouts = layers.filter { !$0.isBackground }
            .sorted { $0.zOrder < $1.zOrder }
            .map { layer -> StoredPiPLayout in
                StoredPiPLayout(origin: layer.screenOrigin, size: layer.screenSize,
                                cornerRadius: layer.normalizedCornerRadius,
                                isCircle: layer.isCircle, isSplitH: layer.isSplitH)
            }
        let bounds = screenBounds
        writeQueue.async { [weak self] in
            guard let self else { return }
            self.storedPiPLayouts = layouts
            self.storedScreenBounds = bounds
            self.applyLayerLayout()
        }
    }

    func updatePiPCropRect(_ rect: PiPNormalizedRect) {
        writeQueue.async { [weak self] in
            // applyLayerLayout 会读 AppSettings.pipCropRect（已由调用方写入），圆形另有中心裁剪
            self?.applyLayerLayout()
        }
    }

    func updateFrontMirror(_ mirrored: Bool) {
        // 镜像由 CameraManager.setFrontRecordingMirror 在数据连接上处理，合成器不额外翻转
        _ = mirrored
    }

    /// 用屏幕坐标同步 PiP 位置（向后兼容，单层场景）。
    func updatePiPLayout(screenOriginX: Float, screenOriginY: Float,
                         screenPipW: Float, screenPipH: Float,
                         screenW: Float, screenH: Float) {
        let layout = StoredPiPLayout(
            origin: CGPoint(x: CGFloat(screenOriginX), y: CGFloat(screenOriginY)),
            size: CGSize(width: CGFloat(screenPipW), height: CGFloat(screenPipH)),
            cornerRadius: 0.015,
            isCircle: false, isSplitH: false
        )
        let bounds = CGSize(width: CGFloat(screenW), height: CGFloat(screenH))
        writeQueue.async { [weak self] in
            guard let self else { return }
            self.storedPiPLayouts = [layout]
            self.storedScreenBounds = bounds
            self.applyLayerLayout()
        }
    }

    // MARK: - 内部布局计算（在 writeQueue 上调用）

    private func applyLayerLayout(bgWOverride: Int? = nil, bgHOverride: Int? = nil,
                                   pipWOverride: Int? = nil, pipHOverride: Int? = nil) {
        guard let comp = compositor else { return }
        let sW = Float(storedScreenBounds.width)
        let sH = Float(storedScreenBounds.height)
        guard sW > 0, sH > 0 else { return }

        let bgDims  = pipCameraIsBack ? frontDimensions : backDimensions
        let pipDims = pipCameraIsBack ? backDimensions  : frontDimensions
        let rawBW = bgWOverride  ?? bgDims?.width
        let rawBH = bgHOverride  ?? bgDims?.height
        let rawFW = pipWOverride ?? pipDims?.width
        let rawFH = pipHOverride ?? pipDims?.height

        for (i, layout) in storedPiPLayouts.prefix(4).enumerated() {
            let ox = Float(layout.origin.x)
            let oy = Float(layout.origin.y)
            let pw = Float(layout.size.width)

            let normOriginX, normOriginY, normW, normH: Float
            var cropOriginX: Float = 0, cropOriginY: Float = 0
            var cropSizeW:   Float = 1, cropSizeH:   Float = 1

            if layout.isSplitH {
                // 全宽下半：固定 UV，不依赖屏幕坐标
                comp.updateLayer(at: i, params: PiPCompositor.LayerParams(
                    originX: 0, originY: 0.5,
                    sizeW: 1.0, sizeH: 0.5,
                    cropOriginX: 0, cropOriginY: 0, cropSizeW: 1, cropSizeH: 1,
                    cornerRadius: 0, mirrorFront: 0
                ))
                continue
            } else if let bW = rawBW.map({ Float($0) }),
               let bH = rawBH.map({ Float($0) }), bW > 0, bH > 0 {
                // 预览使用 resizeAspectFill：确定缩放比例和裁切偏移
                let videoAspect  = bW / bH
                let screenAspect = sW / sH
                let scale: Float
                let cropX: Float
                let cropY: Float
                if videoAspect > screenAspect {
                    scale = sH / bH
                    cropX = (bW * scale - sW) / 2
                    cropY = 0
                } else {
                    scale = sW / bW
                    cropX = 0
                    cropY = (bH * scale - sH) / 2
                }
                normOriginX = (ox + cropX) / (scale * bW)
                normOriginY = (oy + cropY) / (scale * bH)
                normW = pw / (scale * bW)

                let fW = rawFW.map { Float($0) } ?? bW
                let fH = rawFH.map { Float($0) } ?? bH

                if layout.isCircle {
                    // 边界框在输出像素空间为正方形，避免 SDF 生成胶囊形
                    normH = normW * bW / bH
                    // 前摄中心正方形裁剪，匹配预览的 resizeAspectFill 行为
                    let fAspect = fW / fH
                    if fAspect > 1.0 {        // 横屏前摄
                        cropSizeW   = fH / fW
                        cropOriginX = (1.0 - cropSizeW) / 2.0
                    } else if fAspect < 1.0 { // 竖屏前摄
                        cropSizeH   = fW / fH
                        cropOriginY = (1.0 - cropSizeH) / 2.0
                    }
                } else {
                    let userCrop = AppSettings.shared.pipCropRect
                    let ucW = Float(userCrop.width), ucH = Float(userCrop.height)
                    normH = normW * bH * fW * ucH / (bW * fH * ucW)
                    cropOriginX = Float(userCrop.x);  cropOriginY = Float(userCrop.y)
                    cropSizeW   = Float(userCrop.width); cropSizeH = Float(userCrop.height)
                }
            } else {
                // 帧尺寸未知时回退：屏幕归一化
                normW = pw / sW
                normOriginX = ox / sW
                normOriginY = oy / sH
                if layout.isCircle {
                    normH = normW
                    // fW/fH 未知，保持默认全帧（稍后 tryInitializeWriters 会重算）
                } else {
                    let crop = AppSettings.shared.pipCropRect
                    normH = normW * Float(crop.height) / Float(crop.width)
                    cropOriginX = Float(crop.x);  cropOriginY = Float(crop.y)
                    cropSizeW   = Float(crop.width); cropSizeH = Float(crop.height)
                }
            }

            let clampedX = min(max(normOriginX, 0), max(1.0 - normW, 0))
            let clampedY = min(max(normOriginY, 0), max(1.0 - normH, 0))

            // 圆形：cornerR = normW/2 使 rS = normW/2 * ar = sS.x/2 = sS.y/2（横竖屏均正圆）
            // 若用 min(normW,normH)/2，竖屏时 normH<normW 会导致 rS 过小，渲染为圆角矩形
            let cornerR: Float = layout.isCircle ? normW / 2 : layout.cornerRadius
            // mirrorFront=0: 数据连接已通过 setFrontRecordingMirror 处理镜像，合成器不再额外翻转
            comp.updateLayer(at: i, params: PiPCompositor.LayerParams(
                originX: clampedX, originY: clampedY,
                sizeW: normW, sizeH: normH,
                cropOriginX: cropOriginX, cropOriginY: cropOriginY,
                cropSizeW: cropSizeW, cropSizeH: cropSizeH,
                cornerRadius: cornerR, mirrorFront: 0
            ))
        }
        comp.setActiveLayerCount(min(storedPiPLayouts.count, 4))
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
                let bW = CVPixelBufferGetWidth(back),  bH = CVPixelBufferGetHeight(back)
                let fW = CVPixelBufferGetWidth(front), fH = CVPixelBufferGetHeight(front)
                let bgW  = self.pipCameraIsBack ? fW : bW, bgH  = self.pipCameraIsBack ? fH : bH
                let pipW = self.pipCameraIsBack ? bW : fW, pipH = self.pipCameraIsBack ? bH : fH
                comp.configure(backWidth: bgW, backHeight: bgH, frontWidth: pipW, frontHeight: pipH)
                self.applyLayerLayout(bgWOverride: bgW, bgHOverride: bgH,
                                      pipWOverride: pipW, pipHOverride: pipH)
            }
            let bgBuf      = self.pipCameraIsBack ? front : back
            let overlayBuf = self.pipCameraIsBack ? back  : front
            let result = comp.composite(backBuffer: bgBuf,
                                        overlays: [(buffer: overlayBuf, index: 0)])
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

        let bgW  = pipCameraIsBack ? front.width  : back.width
        let bgH  = pipCameraIsBack ? front.height : back.height
        let pipW = pipCameraIsBack ? back.width   : front.width
        let pipH = pipCameraIsBack ? back.height  : front.height
        compositor?.configure(backWidth: bgW, backHeight: bgH, frontWidth: pipW, frontHeight: pipH)
        applyLayerLayout()  // 统一设置 position/size/crop/cornerRadius/mirrorFront(=0)

        if let w = compositeWriter {
            compositeVideoInput = makeVideoInput(settings: videoSettings(width: bgW, height: bgH))
            compositeAudioInput = makeAudioInput()
            if w.canAdd(compositeVideoInput!) { w.add(compositeVideoInput!) }
            if w.canAdd(compositeAudioInput!) { w.add(compositeAudioInput!) }
            if !w.startWriting() {
                print("[VideoRecorder] compositeWriter startWriting failed: \(w.error?.localizedDescription ?? "unknown")")
            }
        }
        if let w = backWriter {
            backVideoInput = makeVideoInput(settings: videoSettings(width: back.width, height: back.height))
            backAudioInput = makeAudioInput()
            if w.canAdd(backVideoInput!) { w.add(backVideoInput!) }
            if w.canAdd(backAudioInput!) { w.add(backAudioInput!) }
            if !w.startWriting() {
                print("[VideoRecorder] backWriter startWriting failed: \(w.error?.localizedDescription ?? "unknown")")
            }
        }
        if let w = frontWriter {
            frontVideoInput = makeVideoInput(settings: videoSettings(width: front.width, height: front.height))
            frontAudioInput = makeAudioInput()
            if w.canAdd(frontVideoInput!) { w.add(frontVideoInput!) }
            if w.canAdd(frontAudioInput!) { w.add(frontAudioInput!) }
            if !w.startWriting() {
                print("[VideoRecorder] frontWriter startWriting failed: \(w.error?.localizedDescription ?? "unknown")")
            }
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
              let frontBuffer = latestFrontPixelBuffer else { return }

        let bgBuffer      = pipCameraIsBack ? frontBuffer : backBuffer
        let overlayBuffer = pipCameraIsBack ? backBuffer  : frontBuffer
        guard let composed = compositor.composite(backBuffer: bgBuffer,
                                                  overlays: [(buffer: overlayBuffer, index: 0)]) else { return }

        let dur = CMSampleBufferGetDuration(sampleBuffer)
        appendCompositeFrame(composed, presentationTime: pts, duration: dur)
    }

    private func appendCompositeFrame(_ pixelBuffer: CVPixelBuffer,
                                      presentationTime: CMTime,
                                      duration: CMTime) {
        guard let input = compositeVideoInput, input.isReadyForMoreMediaData else { return }

        var timingInfo = CMSampleTimingInfo(
            duration: duration,
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

    private func makeOutputURL(name: String) -> URL {
        let dir = recordingsDir()
        return dir.appendingPathComponent("\(name).mp4")
    }

    private func recordingsDir() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func seqFilename(prefix: String, in dir: URL) -> String {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        var maxNum = 0
        for file in files {
            let base = file.deletingPathExtension().lastPathComponent
            guard base.hasPrefix(prefix) else { continue }
            let numPart = base.dropFirst(prefix.count)
            guard !numPart.isEmpty, numPart.allSatisfy({ $0.isNumber }) else { continue }
            if let n = Int(numPart) { maxNum = max(maxNum, n) }
        }
        let next = maxNum + 1
        return next <= 999 ? String(format: "\(prefix)%03d", next) : "\(prefix)\(next)"
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
