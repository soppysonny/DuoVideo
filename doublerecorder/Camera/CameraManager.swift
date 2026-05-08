import AVFoundation
import UIKit

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager,
                       didOutputBackSampleBuffer sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: CameraManager,
                       didOutputFrontSampleBuffer sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: CameraManager,
                       didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer)
}

@available(iOS 13.0, *)
class CameraManager: NSObject {

    weak var delegate: CameraManagerDelegate?

    /// 格式应用或 hardwareCost 超限导致降级时，在主线程回调一次，参数为提示文字
    var onQualityReduced: ((String) -> Void)?
    private var pendingQualityMessage: String?

    private(set) var backPreviewLayer: AVCaptureVideoPreviewLayer?
    private(set) var frontPreviewLayer: AVCaptureVideoPreviewLayer?

    /// false = 前摄在 PiP 槽（默认）；true = 超广角后摄在 PiP 槽
    private(set) var isUsingFrontCamera: Bool = true

    // 设备引用，用于闪光灯 / AE/AF 控制
    private var backDevice:  AVCaptureDevice?
    private var frontDevice: AVCaptureDevice?

    // 保存连接引用，用于运行时更新朝向。
    private var backDataConnection:    AVCaptureConnection?
    private var frontDataConnection:   AVCaptureConnection?
    private var backPreviewConnection: AVCaptureConnection?
    private var frontPreviewConnection: AVCaptureConnection?

    private let session = AVCaptureMultiCamSession()
    private let sessionQueue = DispatchQueue(label: "com.mbjztech.doublerecorder.session",
                                             qos: .userInitiated)
    private let backOutputQueue  = DispatchQueue(label: "com.mbjztech.doublerecorder.back",
                                                  qos: .userInitiated)
    private let frontOutputQueue = DispatchQueue(label: "com.mbjztech.doublerecorder.front",
                                                  qos: .userInitiated)
    private let audioOutputQueue = DispatchQueue(label: "com.mbjztech.doublerecorder.audio",
                                                  qos: .userInitiated)

    private var backVideoOutput  = AVCaptureVideoDataOutput()
    private var frontVideoOutput = AVCaptureVideoDataOutput()
    private var audioOutput      = AVCaptureAudioDataOutput()

    static var isMultiCamSupported: Bool {
        AVCaptureMultiCamSession.isMultiCamSupported
    }

    static var isUltraWideMultiCamSupported: Bool {
        guard AVCaptureMultiCamSession.isMultiCamSupported else { return false }
        return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil
    }

    // MARK: - 配置

    func configure(completion: @escaping (Result<Void, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                self.session.beginConfiguration()
                try self.configureBackCamera()
                if AppSettings.shared.pipCamera == .backUltraWide && Self.isUltraWideMultiCamSupported {
                    try self.configureUltraWideCamera()
                } else {
                    if AppSettings.shared.pipCamera == .backUltraWide {
                        AppSettings.shared.pipCamera = .front
                    }
                    try self.configureFrontCamera()
                }
                try self.configureMicrophone()
                self.session.commitConfiguration()
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func startRunning() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.pendingQualityMessage = nil
            self.session.beginConfiguration()
            self.applyFormatSettings()
            self.session.commitConfiguration()
            self.session.startRunning()
            self.checkAndReduceQualityIfNeeded()
            if let msg = self.pendingQualityMessage {
                self.pendingQualityMessage = nil
                DispatchQueue.main.async { [weak self] in self?.onQualityReduced?(msg) }
            }
        }
    }

    func stopRunning() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    // MARK: - 运行时控制

    /// 后摄闪光灯/手电筒
    func setTorch(_ on: Bool) {
        sessionQueue.async { [weak self] in
            guard let device = self?.backDevice, device.hasTorch else { return }
            try? device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    /// AE/AF 锁定（前后摄都锁）
    func setAEAFLock(_ locked: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            for device in [self.backDevice, self.frontDevice].compactMap({ $0 }) {
                try? device.lockForConfiguration()
                if locked {
                    if device.isFocusModeSupported(.locked)   { device.focusMode = .locked }
                    if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                } else {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
                device.unlockForConfiguration()
            }
        }
    }

    /// 前摄预览镜像（仅影响 preview，不影响录制；超广角模式下无效）
    func setFrontMirror(_ mirrored: Bool) {
        guard isUsingFrontCamera else { return }
        DispatchQueue.main.async { [weak self] in
            guard let conn = self?.frontPreviewConnection,
                  conn.isVideoMirroringSupported else { return }
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = mirrored
        }
    }

    /// 前摄录制镜像（影响数据输出，进而影响所有录制文件；超广角模式下无效）
    func setFrontRecordingMirror(_ mirrored: Bool) {
        guard isUsingFrontCamera else { return }
        sessionQueue.async { [weak self] in
            guard let conn = self?.frontDataConnection,
                  conn.isVideoMirroringSupported else { return }
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = mirrored
        }
    }

    /// 更新数据输出和预览的视频朝向（录制前调用；录制中不应调用）
    func setVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.backDataConnection?.videoOrientation  = orientation
            self.frontDataConnection?.videoOrientation = orientation
            DispatchQueue.main.async {
                self.backPreviewConnection?.videoOrientation  = orientation
                self.frontPreviewConnection?.videoOrientation = orientation
            }
        }
    }

    // MARK: - 格式 / 帧率

    private func applyFormatSettings() {
        let res = AppSettings.shared.videoResolution
        let fps = AppSettings.shared.frameRate.rawValue
        var lines: [String] = []
        var minActualFps = fps
        for device in [backDevice, frontDevice].compactMap({ $0 }) {
            let actual = applyFormat(targetWidth: res.targetWidth, fps: fps, to: device)
            minActualFps = min(minActualFps, actual)
            if actual < fps {
                let name = device.position == .back
                    ? NSLocalizedString("camera.back", comment: "")
                    : NSLocalizedString("camera.front", comment: "")
                lines.append(String(format: NSLocalizedString("camera.fps_line", comment: ""), name, fps, actual))
            }
        }
        if !lines.isEmpty {
            pendingQualityMessage = NSLocalizedString("camera.quality_partial_prefix", comment: "") + lines.joined(separator: "\n")
            if let rate = AppSettings.FrameRate(rawValue: minActualFps) {
                AppSettings.shared.frameRate = rate
            }
        }
    }

    /// session 启动后检测 hardwareCost，超限则自动降帧率并通知上层
    private func checkAndReduceQualityIfNeeded() {
        guard session.hardwareCost > 1.0 else { return }
        let res = AppSettings.shared.videoResolution
        let currentFps = AppSettings.shared.frameRate.rawValue
        let fallbackFps: Int
        switch currentFps {
        case 60: fallbackFps = 30
        case 30: fallbackFps = 24
        default: return
        }
        session.beginConfiguration()
        for device in [backDevice, frontDevice].compactMap({ $0 }) {
            applyFormat(targetWidth: res.targetWidth, fps: fallbackFps, to: device)
        }
        session.commitConfiguration()
        pendingQualityMessage = String(format: NSLocalizedString("camera.quality_fps_reduced", comment: ""), fallbackFps)
        if let rate = AppSettings.FrameRate(rawValue: fallbackFps) {
            AppSettings.shared.frameRate = rate
        }
    }

    /// 返回实际应用的帧率
    @discardableResult
    private func applyFormat(targetWidth: Int, fps: Int, to device: AVCaptureDevice) -> Int {
        let pos = device.position == .back ? "back" : "front"
        let multiCamFormats = device.formats.filter { fmt in
            guard fmt.isMultiCamSupported else { return false }
            let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            return dims.width == targetWidth
        }
        guard !multiCamFormats.isEmpty else {
            print("[MultiCam] \(pos): no MultiCam format at width=\(targetWidth), skipped")
            return fps
        }

        let exact = multiCamFormats.first {
            $0.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Float64(fps) }
        }
        let format = exact ?? multiCamFormats.max(by: {
            ($0.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0) <
            ($1.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
        })!

        let maxFps = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? Double(fps)
        let actualFps = Int(min(Double(fps), maxFps))
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        print("[MultiCam] \(pos): requested \(targetWidth)×?@\(fps)fps → actual \(dims.width)×\(dims.height)@\(actualFps)fps")

        try? device.lockForConfiguration()
        device.activeFormat = format
        let dur = CMTime(value: 1, timescale: CMTimeScale(actualFps))
        device.activeVideoMinFrameDuration = dur
        device.activeVideoMaxFrameDuration = dur
        device.unlockForConfiguration()
        return actualFps
    }

    // MARK: - Private 配置

    private func configureBackCamera() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .back) else {
            throw CameraError.deviceUnavailable(NSLocalizedString("camera.back_unavailable", comment: ""))
        }
        backDevice = device
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput(NSLocalizedString("camera.cannot_add_back_input", comment: ""))
        }
        session.addInputWithNoConnections(input)

        backVideoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        backVideoOutput.alwaysDiscardsLateVideoFrames = true
        backVideoOutput.setSampleBufferDelegate(self, queue: backOutputQueue)
        guard session.canAddOutput(backVideoOutput) else {
            throw CameraError.cannotAddOutput(NSLocalizedString("camera.cannot_add_back_output", comment: ""))
        }
        session.addOutputWithNoConnections(backVideoOutput)

        guard let inputPort = input.ports(for: .video,
                                          sourceDeviceType: device.deviceType,
                                          sourceDevicePosition: .back).first else {
            throw CameraError.cannotAddInput(NSLocalizedString("camera.cannot_get_back_port", comment: ""))
        }
        let connection = AVCaptureConnection(inputPorts: [inputPort], output: backVideoOutput)
        guard session.canAddConnection(connection) else {
            throw CameraError.cannotAddInput(NSLocalizedString("camera.cannot_connect_back", comment: ""))
        }
        session.addConnection(connection)
        connection.videoOrientation = .portrait
        backDataConnection = connection

        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.setSessionWithNoConnection(session)
        let previewConnection = AVCaptureConnection(inputPort: inputPort, videoPreviewLayer: previewLayer)
        guard session.canAddConnection(previewConnection) else { return }
        session.addConnection(previewConnection)
        previewConnection.videoOrientation = .portrait
        backPreviewConnection = previewConnection
        previewLayer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async { self.backPreviewLayer = previewLayer }
    }

    private func configureUltraWideCamera() throws {
        guard let device = AVCaptureDevice.default(.builtInUltraWideCamera,
                                                   for: .video, position: .back) else {
            throw CameraError.deviceUnavailable(NSLocalizedString("camera.ultrawide_unavailable", comment: ""))
        }
        frontDevice = device
        isUsingFrontCamera = false
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput(NSLocalizedString("camera.cannot_add_ultrawide_input", comment: ""))
        }
        session.addInputWithNoConnections(input)

        frontVideoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        frontVideoOutput.alwaysDiscardsLateVideoFrames = true
        frontVideoOutput.setSampleBufferDelegate(self, queue: frontOutputQueue)
        guard session.canAddOutput(frontVideoOutput) else {
            throw CameraError.cannotAddOutput(NSLocalizedString("camera.cannot_add_ultrawide_output", comment: ""))
        }
        session.addOutputWithNoConnections(frontVideoOutput)

        guard let inputPort = input.ports(for: .video,
                                          sourceDeviceType: device.deviceType,
                                          sourceDevicePosition: .back).first else {
            throw CameraError.cannotAddInput(NSLocalizedString("camera.cannot_get_ultrawide_port", comment: ""))
        }
        let connection = AVCaptureConnection(inputPorts: [inputPort], output: frontVideoOutput)
        guard session.canAddConnection(connection) else {
            throw CameraError.cannotAddInput(NSLocalizedString("camera.cannot_connect_ultrawide", comment: ""))
        }
        session.addConnection(connection)
        connection.videoOrientation = .portrait
        frontDataConnection = connection
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }

        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.setSessionWithNoConnection(session)
        let previewConnection = AVCaptureConnection(inputPort: inputPort, videoPreviewLayer: previewLayer)
        guard session.canAddConnection(previewConnection) else { return }
        session.addConnection(previewConnection)
        previewConnection.videoOrientation = .portrait
        frontPreviewConnection = previewConnection
        if previewConnection.isVideoMirroringSupported {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            previewConnection.isVideoMirrored = false
        }
        previewLayer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async { self.frontPreviewLayer = previewLayer }
    }

    private func configureFrontCamera() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .front) else {
            throw CameraError.deviceUnavailable(NSLocalizedString("camera.front_unavailable", comment: ""))
        }
        frontDevice = device
        isUsingFrontCamera = true
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput(NSLocalizedString("camera.cannot_add_front_input", comment: ""))
        }
        session.addInputWithNoConnections(input)

        frontVideoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        frontVideoOutput.alwaysDiscardsLateVideoFrames = true
        frontVideoOutput.setSampleBufferDelegate(self, queue: frontOutputQueue)
        guard session.canAddOutput(frontVideoOutput) else {
            throw CameraError.cannotAddOutput(NSLocalizedString("camera.cannot_add_front_output", comment: ""))
        }
        session.addOutputWithNoConnections(frontVideoOutput)

        guard let inputPort = input.ports(for: .video,
                                          sourceDeviceType: device.deviceType,
                                          sourceDevicePosition: .front).first else {
            throw CameraError.cannotAddInput(NSLocalizedString("camera.cannot_get_front_port", comment: ""))
        }
        let connection = AVCaptureConnection(inputPorts: [inputPort], output: frontVideoOutput)
        guard session.canAddConnection(connection) else {
            throw CameraError.cannotAddInput(NSLocalizedString("camera.cannot_connect_front", comment: ""))
        }
        session.addConnection(connection)
        connection.videoOrientation = .portrait
        frontDataConnection = connection
        // 前摄不做镜像（Metal shader 里会处理）
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }

        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.setSessionWithNoConnection(session)
        let previewConnection = AVCaptureConnection(inputPort: inputPort, videoPreviewLayer: previewLayer)
        guard session.canAddConnection(previewConnection) else { return }
        session.addConnection(previewConnection)
        previewConnection.videoOrientation = .portrait
        frontPreviewConnection = previewConnection
        if previewConnection.isVideoMirroringSupported {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            previewConnection.isVideoMirrored = true
        }
        previewLayer.videoGravity = .resizeAspectFill
        DispatchQueue.main.async { self.frontPreviewLayer = previewLayer }
    }

    private func configureMicrophone() throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw CameraError.deviceUnavailable(NSLocalizedString("camera.mic_unavailable", comment: ""))
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput(NSLocalizedString("camera.cannot_add_mic_input", comment: ""))
        }
        session.addInputWithNoConnections(input)

        audioOutput.setSampleBufferDelegate(self, queue: audioOutputQueue)
        guard session.canAddOutput(audioOutput) else {
            throw CameraError.cannotAddOutput(NSLocalizedString("camera.cannot_add_audio_output", comment: ""))
        }
        session.addOutputWithNoConnections(audioOutput)

        guard let inputPort = input.ports(for: .audio,
                                          sourceDeviceType: device.deviceType,
                                          sourceDevicePosition: .unspecified).first else {
            throw CameraError.cannotAddInput(NSLocalizedString("camera.cannot_get_mic_port", comment: ""))
        }
        let connection = AVCaptureConnection(inputPorts: [inputPort], output: audioOutput)
        guard session.canAddConnection(connection) else {
            throw CameraError.cannotAddInput(NSLocalizedString("camera.cannot_connect_audio", comment: ""))
        }
        session.addConnection(connection)
    }
}

// MARK: - Sample Buffer Delegates

@available(iOS 13.0, *)
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate,
                          AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === backVideoOutput {
            delegate?.cameraManager(self, didOutputBackSampleBuffer: sampleBuffer)
        } else if output === frontVideoOutput {
            delegate?.cameraManager(self, didOutputFrontSampleBuffer: sampleBuffer)
        } else if output === audioOutput {
            delegate?.cameraManager(self, didOutputAudioSampleBuffer: sampleBuffer)
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didDrop sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {}
}

// MARK: - Error

enum CameraError: LocalizedError {
    case deviceUnavailable(String)
    case cannotAddInput(String)
    case cannotAddOutput(String)

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable(let msg): return msg
        case .cannotAddInput(let msg):    return msg
        case .cannotAddOutput(let msg):   return msg
        }
    }
}
