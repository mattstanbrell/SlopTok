import Foundation

class VideoFileCache {
    static let shared = VideoFileCache()
    private init() {}

    // Duration threshold for cached files: 7 days (in seconds)
    private let cacheExpiration: TimeInterval = 604800

    func localFileURL(for videoResource: String) -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDirectory.appendingPathComponent("\(videoResource).mp4")
    }
    
    func getLocalVideoURL(for videoResource: String, remoteURL: URL, completion: @escaping (URL?) -> Void) {
        let localURL = localFileURL(for: videoResource)
        let fileManager = FileManager.default
        
        // Check if file exists and is not expired.
        if fileManager.fileExists(atPath: localURL.path) {
            if let attributes = try? fileManager.attributesOfItem(atPath: localURL.path),
               let modDate = attributes[.modificationDate] as? Date {
                let now = Date()
                if now.timeIntervalSince(modDate) < cacheExpiration {
                    VideoLogger.shared.log(.cacheHit, videoId: videoResource, message: "Found cached video file")
                    completion(localURL)
                    return
                } else {
                    // File is expired; remove it.
                    VideoLogger.shared.log(.cacheExpired, videoId: videoResource, message: "Cache expired after \(Int(now.timeIntervalSince(modDate))) seconds")
                    try? fileManager.removeItem(at: localURL)
                }
            }
        }
        
        VideoLogger.shared.log(.cacheMiss, videoId: videoResource, message: "Starting download from \(remoteURL.lastPathComponent)")
        VideoLogger.shared.log(.downloadStarted, videoId: videoResource)
        
        let task = URLSession.shared.downloadTask(with: remoteURL) { tempURL, response, error in
            if let error = error {
                VideoLogger.shared.log(.downloadFailed, videoId: videoResource, error: error)
                completion(remoteURL)
                return
            }
            guard let tempURL = tempURL else {
                VideoLogger.shared.log(.downloadFailed, videoId: videoResource, message: "No temporary URL provided")
                completion(remoteURL)
                return
            }
            do {
                if fileManager.fileExists(atPath: localURL.path) {
                    try fileManager.removeItem(at: localURL)
                }
                try fileManager.moveItem(at: tempURL, to: localURL)
                VideoLogger.shared.log(.downloadCompleted, videoId: videoResource, message: "Cached at \(localURL.lastPathComponent)")
                completion(localURL)
            } catch {
                VideoLogger.shared.log(.downloadFailed, videoId: videoResource, error: error)
                completion(remoteURL)
            }
        }
        task.resume()
    }
}