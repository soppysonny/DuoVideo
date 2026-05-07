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

    private(set) var backPreviewLayer: AVCaptureVideoPreviewLayer?
    private(set) var frontPreviewLayer: AVCaptureVideoPreviewLayer?

    // 设备引用，用于闪光灯 / AE/AF 控制
    private var backDevice:  AVCaptureDevice?
    private var frontDevice: AVCaptureDevice?

    // 保存连接引用，用于运行时更新朝向
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

    // MARK: - 配置

    func configure(completion: @escaping (Result<Void, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                self.session.beginConfiguration()
                try self.configureBackCamera()
                try self.configureFrontCamera()
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
            self.session.beginConfiguration()
            self.applyFormatSettings()
            self.session.commitConfiguration()
            self.session.startRunning()
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

    /// 前摄预览镜像
    func setFrontMirror(_ mirrored: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let conn = self?.frontPreviewConnection,
                  conn.isVideoMirroringSupported else { return }
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = mirrored
        }
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
        for device in [backDevice, frontDevice].compactMap({ $0 }) {
            applyFormat(targetWidth: res.targetWidth, fps: fps, to: device)
        }
    }

    private func applyFormat(targetWidth: Int, fps: Int, to device: AVCaptureDevice) {
        let candidates = device.formats.filter { fmt in
            guard fmt.isMultiCamSupported else { return false }
            let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            guard dims.width == targetWidth else { return false }
            return fmt.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Float64(fps) }
        }
        guard let format = candidates.first else { return }
        try? device.lockForConfiguration()
        device.activeFormat = format
        let dur = CMTime(value: 1, timescale: CMTimeScale(fps))
        device.activeVideoMinFrameDuration = dur
        device.activeVideoMaxFrameDuration = dur
        device.unlockForConfiguration()
    }

    // MARK: - Private 配置

    private func configureBackCamera() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .back) else {
            throw CameraError.deviceUnavailable("后置摄像头不可用")
        }
        backDevice = device
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput("无法添加后摄 input")
        }
        session.addInputWithNoConnections(input)

        backVideoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        backVideoOutput.alwaysDiscardsLateVideoFrames = true
        backVideoOutput.setSampleBufferDelegate(self, queue: backOutputQueue)
        guard session.canAddOutput(backVideoOutput) else {
            throw CameraError.cannotAddOutput("无法添加后摄 output")
        }
        session.addOutputWithNoConnections(backVideoOutput)

        guard let inputPort = input.ports(for: .video,
                                          sourceDeviceType: device.deviceType,
                                          sourceDevicePosition: .back).first else {
            throw CameraError.cannotAddInput("无法获取后摄 port")
        }
        let connection = AVCaptureConnection(inputPorts: [inputPort], output: backVideoOutput)
        guard session.canAddConnection(connection) else {
            throw CameraError.cannotAddInput("无法建立后摄连接")
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

    private func configureFrontCamera() throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .front) else {
            throw CameraError.deviceUnavailable("前置摄像头不可用")
        }
        frontDevice = device
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput("无法添加前摄 input")
        }
        session.addInputWithNoConnections(input)

        frontVideoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        frontVideoOutput.alwaysDiscardsLateVideoFrames = true
        frontVideoOutput.setSampleBufferDelegate(self, queue: frontOutputQueue)
        guard session.canAddOutput(frontVideoOutput) else {
            throw CameraError.cannotAddOutput("无法添加前摄 output")
        }
        session.addOutputWithNoConnections(frontVideoOutput)

        guard let inputPort = input.ports(for: .video,
                                          sourceDeviceType: device.deviceType,
                                          sourceDevicePosition: .front).first else {
            throw CameraError.cannotAddInput("无法获取前摄 port")
        }
        let connection = AVCaptureConnection(inputPorts: [inputPort], output: frontVideoOutput)
        guard session.canAddConnection(connection) else {
            throw CameraError.cannotAddInput("无法建立前摄连接")
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
            throw CameraError.deviceUnavailable("麦克风不可用")
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput("无法添加麦克风 input")
        }
        session.addInputWithNoConnections(input)

        audioOutput.setSampleBufferDelegate(self, queue: audioOutputQueue)
        guard session.canAddOutput(audioOutput) else {
            throw CameraError.cannotAddOutput("无法添加音频 output")
        }
        session.addOutputWithNoConnections(audioOutput)

        guard let inputPort = input.ports(for: .audio,
                                          sourceDeviceType: device.deviceType,
                                          sourceDevicePosition: .unspecified).first else {
            throw CameraError.cannotAddInput("无法获取麦克风 port")
        }
        let connection = AVCaptureConnection(inputPorts: [inputPort], output: audioOutput)
        guard session.canAddConnection(connection) else {
            throw CameraError.cannotAddInput("无法建立音频连接")
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
