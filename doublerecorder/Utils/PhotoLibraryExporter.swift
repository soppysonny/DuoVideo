import Photos

class PhotoLibraryExporter {

    func exportSession(_ session: RecordingSession,
                       completion: @escaping (Result<Void, Error>) -> Void) {
        let urls = [session.compositeVideoURL, session.backVideoURL, session.frontVideoURL]
        var saveError: Error?
        let group = DispatchGroup()

        for url in urls {
            group.enter()
            saveVideo(at: url) { result in
                if case .failure(let err) = result { saveError = err }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let error = saveError {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func saveVideo(at url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }, completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    completion(.success(()))
                } else {
                    completion(.failure(error ?? NSError(domain: "PhotoExport", code: -1)))
                }
            }
        })
    }
}
