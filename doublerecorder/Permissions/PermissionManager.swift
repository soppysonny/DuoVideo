import AVFoundation
import Photos
import UIKit

class PermissionManager {

    static let shared = PermissionManager()
    private init() {}

    func requestAllPermissions(completion: @escaping (_ allGranted: Bool) -> Void) {
        requestCameraPermission { [weak self] cameraGranted in
            guard let self, cameraGranted else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.requestMicrophonePermission { micGranted in
                guard micGranted else {
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                self.requestPhotoLibraryPermission { photoGranted in
                    DispatchQueue.main.async { completion(photoGranted) }
                }
            }
        }
    }

    func cameraStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func microphoneStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { completion($0) }
        default:
            completion(false)
        }
    }

    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { completion($0) }
        default:
            completion(false)
        }
    }

    private func requestPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 14, *) {
            let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            switch status {
            case .authorized, .limited:
                completion(true)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            default:
                completion(false)
            }
        } else {
            let status = PHPhotoLibrary.authorizationStatus()
            switch status {
            case .authorized:
                completion(true)
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization { newStatus in
                    completion(newStatus == .authorized)
                }
            default:
                completion(false)
            }
        }
    }
}
