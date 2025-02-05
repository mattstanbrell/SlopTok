import Foundation

class VideoFileCache {
    static let shared = VideoFileCache()
    private init() {}
    
    // Duration threshold for cached files: 7 days (in seconds)
    private let cacheExpiration: TimeInterval = 604800
    private let maxCachedVideos = 10
    
    // LRU tracking: most recent at the end
    private var lruList: [String] = []
    
    private func updateLRU(videoId: String) {
        // Remove if exists (to move to end)
        lruList.removeAll { $0 == videoId }
        
        // Add to end (most recent)
        lruList.append(videoId)
        
        // Evict oldest if over limit
        while lruList.count > maxCachedVideos {
            let oldestId = lruList.removeFirst()
            let url = localFileURL(for: oldestId)
            try? FileManager.default.removeItem(at: url)
            VideoLogger.shared.log(.cacheExpired, videoId: oldestId, message: "Evicted from LRU cache")
        }
        
        VideoLogger.shared.log(.cacheHit, videoId: videoId, message: "Updated LRU position")
    }

    // Direct LRU update without cache check
    func updateLRUPosition(_ videoId: String) {
        updateLRU(videoId: videoId)
    }
    
    func localFileURL(for videoResource: String) -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDirectory.appendingPathComponent("\(videoResource).mp4")
    }
    
    func getLocalVideoURL(for videoResource: String, remoteURL: URL, completion: @escaping (URL?) -> Void) {
        let localURL = localFileURL(for: videoResource)
        let fileManager = FileManager.default
        
        // Check if file exists and is not expired
        if fileManager.fileExists(atPath: localURL.path) {
            if let attributes = try? fileManager.attributesOfItem(atPath: localURL.path),
               let modDate = attributes[.modificationDate] as? Date {
                let now = Date()
                if now.timeIntervalSince(modDate) < cacheExpiration {
                    VideoLogger.shared.log(.cacheHit, videoId: videoResource, message: "Found cached video file")
                    updateLRU(videoId: videoResource)  // Update LRU on cache hit
                    completion(localURL)
                    return
                } else {
                    // File is expired; remove it
                    VideoLogger.shared.log(.cacheExpired, videoId: videoResource, message: "Cache expired after \(Int(now.timeIntervalSince(modDate))) seconds")
                    try? fileManager.removeItem(at: localURL)
                    lruList.removeAll { $0 == videoResource }
                }
            }
        }
        
        VideoLogger.shared.log(.cacheMiss, videoId: videoResource, message: "Starting download from \(remoteURL.lastPathComponent)")
        VideoLogger.shared.log(.downloadStarted, videoId: videoResource)
        
        let task = URLSession.shared.downloadTask(with: remoteURL) { [weak self] tempURL, response, error in
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
                VideoLogger.shared.log(.downloadCompleted, videoId: videoResource)
                
                self?.updateLRU(videoId: videoResource)  // Update LRU after successful download
                completion(localURL)
            } catch {
                VideoLogger.shared.log(.downloadFailed, videoId: videoResource, error: error)
                completion(remoteURL)
            }
        }
        task.resume()
    }
    
    // For debugging: get current LRU state
    func getLRUState() -> [String] {
        return lruList
    }
}