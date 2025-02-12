import Foundation
import os

class VideoFileCache {
    static let shared = VideoFileCache()
    private let logger = Logger(subsystem: "com.sloptok", category: "VideoFileCache")
    
    private init() {
        logger.info("VideoFileCache initialized with \(self.maxCachedVideos) max videos and \(Int(self.cacheExpiration))s expiration")
    }
    
    // Duration threshold for cached files: 7 days (in seconds)
    private let cacheExpiration: TimeInterval = 604800
    private let maxCachedVideos = 10
    
    // LRU tracking: most recent at the end
    private var lruList: [String] = []
    
    private func updateLRU(videoId: String) {
        logger.info("🔄 [Video File Cache] Updating recently used list for video: \(videoId)")
        
        // Remove if exists (to move to end)
        let wasPresent = self.lruList.contains(videoId)
        self.lruList.removeAll { [self] in $0 == videoId }
        
        if wasPresent {
            logger.info("📍 [Video File Cache] Moving existing video to most recent: \(videoId)")
        }
        
        // Add to end (most recent)
        self.lruList.append(videoId)
        logger.info("➕ [Video File Cache] Added to most recently used: \(videoId)")
        
        // Evict oldest if over limit
        while self.lruList.count > self.maxCachedVideos {
            let oldestId = self.lruList.removeFirst()
            let url = localFileURL(for: oldestId)
            do {
                try FileManager.default.removeItem(at: url)
                logger.info("🗑️ [Video File Cache] Removed least recently used video: \(oldestId)")
            } catch {
                logger.error("❌ [Video File Cache] Failed to remove old video file: \(oldestId), error: \(error.localizedDescription)")
            }
        }
        
        logger.info("📊 [Video File Cache] Current state - Total files: \(self.lruList.count), Most recent first: \(self.lruList.reversed().joined(separator: ", "))")
    }

    // Direct LRU update without cache check
    func updateLRUPosition(_ videoId: String) {
        logger.info("📝 [Video File Cache] Updating position for video: \(videoId)")
        updateLRU(videoId: videoId)
    }
    
    func localFileURL(for videoResource: String) -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDirectory.appendingPathComponent("\(videoResource).mp4")
    }
    
    func getLocalVideoURL(for videoResource: String, remoteURL: URL, completion: @escaping (URL?) -> Void) {
        let localURL = localFileURL(for: videoResource)
        let fileManager = FileManager.default
        
        logger.info("🔍 [Video File Cache] Checking for cached video file: \(videoResource)")
        
        // Check if file exists and is not expired
        if fileManager.fileExists(atPath: localURL.path) {
            if let attributes = try? fileManager.attributesOfItem(atPath: localURL.path),
               let modDate = attributes[.modificationDate] as? Date {
                let now = Date()
                if now.timeIntervalSince(modDate) < self.cacheExpiration {
                    logger.info("✅ [Video File Cache] Found valid cached video file: \(videoResource)")
                    updateLRU(videoId: videoResource)  // Update LRU on cache hit
                    completion(localURL)
                    return
                } else {
                    // File is expired; remove it
                    logger.info("⏰ [Video File Cache] Removing expired video file: \(videoResource)")
                    try? fileManager.removeItem(at: localURL)
                    self.lruList.removeAll { $0 == videoResource }
                }
            }
        } else {
            logger.info("❌ [Video File Cache] No cached file found for video: \(videoResource)")
        }
        
        logger.info("⬇️ [Video File Cache] Downloading video file: \(videoResource)")
        let task = URLSession.shared.downloadTask(with: remoteURL) { [weak self] tempURL, response, error in
            if let error = error {
                self?.logger.error("❌ [Video File Cache] Download failed for \(videoResource): \(error.localizedDescription)")
                completion(remoteURL)
                return
            }
            guard let tempURL = tempURL else {
                self?.logger.error("❌ [Video File Cache] No temporary file for downloaded video: \(videoResource)")
                completion(remoteURL)
                return
            }
            do {
                if fileManager.fileExists(atPath: localURL.path) {
                    try fileManager.removeItem(at: localURL)
                    self?.logger.info("🗑️ [Video File Cache] Removed existing file before saving new download: \(videoResource)")
                }
                try fileManager.moveItem(at: tempURL, to: localURL)
                self?.logger.info("✅ [Video File Cache] Successfully saved downloaded video: \(videoResource)")
                self?.updateLRU(videoId: videoResource)  // Update LRU after successful download
                completion(localURL)
            } catch {
                self?.logger.error("❌ [Video File Cache] Failed to save downloaded video \(videoResource): \(error.localizedDescription)")
                completion(remoteURL)
            }
        }
        task.resume()
    }
    
    // For debugging: get current LRU state
    func getLRUState() -> [String] {
        logger.info("📊 Current LRU state (\(self.lruList.count) videos): \(self.lruList.joined(separator: ", "))")
        return lruList
    }
}
