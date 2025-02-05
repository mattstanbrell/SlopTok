import Foundation

class VideoFileCache {
    static let shared = VideoFileCache()
    private init() {}
    
    // Generate a local file URL in the Caches directory for a given video resource
    private func localFileURL(for videoResource: String) -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDirectory.appendingPathComponent("\(videoResource).mp4")
    }
    
    // Check for a locally cached video file; if absent or expired (>24hrs), download from remoteURL and cache it.
    func getLocalVideoURL(for videoResource: String, remoteURL: URL, completion: @escaping (URL?) -> Void) {
        let localURL = localFileURL(for: videoResource)
        let fileManager = FileManager.default
        
        // If local file exists, check its creationDate for expiration.
        if fileManager.fileExists(atPath: localURL.path) {
            if let attributes = try? fileManager.attributesOfItem(atPath: localURL.path),
               let creationDate = attributes[.creationDate] as? Date,
               Date().timeIntervalSince(creationDate) < 86400 {
                completion(localURL)
                return
            } else {
                // File is expired; remove it.
                try? fileManager.removeItem(at: localURL)
            }
        }
        
        // Enforce maximum of 20 cached videos.
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        if let fileURLs = try? fileManager.contentsOfDirectory(at: cachesDirectory, includingPropertiesForKeys: [.creationDateKey], options: []) {
            let videoFiles = fileURLs.filter { $0.pathExtension == "mp4" }
            if videoFiles.count >= 20 {
                let sortedFiles = videoFiles.sorted { (url1, url2) -> Bool in
                    let date1 = (try? fileManager.attributesOfItem(atPath: url1.path)[.creationDate] as? Date) ?? Date.distantPast
                    let date2 = (try? fileManager.attributesOfItem(atPath: url2.path)[.creationDate] as? Date) ?? Date.distantPast
                    return date1 < date2
                }
                let removeCount = videoFiles.count - 19  // remove enough files to have room for new one
                for file in sortedFiles.prefix(removeCount) {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
        
        // Download the remote video and store it in the caches directory.
        let task = URLSession.shared.downloadTask(with: remoteURL) { tempURL, response, error in
            if let error = error {
                print("Error downloading video \(videoResource): \(error.localizedDescription)")
                completion(remoteURL)
                return
            }
            guard let tempURL = tempURL else {
                completion(remoteURL)
                return
            }
            do {
                if fileManager.fileExists(atPath: localURL.path) {
                    try fileManager.removeItem(at: localURL)
                }
                try fileManager.moveItem(at: tempURL, to: localURL)
                completion(localURL)
            } catch {
                print("Error caching video \(videoResource): \(error.localizedDescription)")
                completion(remoteURL)
            }
        }
        task.resume()
    }
}