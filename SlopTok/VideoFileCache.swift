import Foundation

class VideoFileCache {
    static let shared = VideoFileCache()
    private init() {}
    
    // Generate a local file URL in the Caches directory for a given video resource
    private func localFileURL(for videoResource: String) -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDirectory.appendingPathComponent("\(videoResource).mp4")
    }
    
    // Check for a locally cached video file; if absent, download from remoteURL and cache it
    func getLocalVideoURL(for videoResource: String, remoteURL: URL, completion: @escaping (URL?) -> Void) {
        let localURL = localFileURL(for: videoResource)
        if FileManager.default.fileExists(atPath: localURL.path) {
            // Local file already exists, return it
            completion(localURL)
        } else {
            // Download the remote video and store it in the caches directory
            let task = URLSession.shared.downloadTask(with: remoteURL) { tempURL, response, error in
                if let error = error {
                    print("Error downloading video \(videoResource): \(error.localizedDescription)")
                    // Fallback to remote URL if download fails
                    completion(remoteURL)
                    return
                }
                guard let tempURL = tempURL else {
                    completion(remoteURL)
                    return
                }
                do {
                    // Ensure any existing file at localURL is removed before moving
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        try FileManager.default.removeItem(at: localURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: localURL)
                    completion(localURL)
                } catch {
                    print("Error caching video \(videoResource): \(error.localizedDescription)")
                    completion(remoteURL)
                }
            }
            task.resume()
        }
    }
}