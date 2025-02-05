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
        }
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
                    updateLRU(videoId: videoResource)  // Update LRU on cache hit
                    completion(localURL)
                    return
                } else {
                    // File is expired; remove it
                    try? fileManager.removeItem(at: localURL)
                    lruList.removeAll { $0 == videoResource }
                }
            }
        }
        
        let task = URLSession.shared.downloadTask(with: remoteURL) { [weak self] tempURL, response, error in
            if let error = error {
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
                self?.updateLRU(videoId: videoResource)  // Update LRU after successful download
                completion(localURL)
            } catch {
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