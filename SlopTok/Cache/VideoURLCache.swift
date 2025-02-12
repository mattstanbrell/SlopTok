import Foundation
import FirebaseStorage
import os

// Helper class to wrap cached video URL with the time it was fetched.
class CachedVideoURL: NSObject {
    let url: URL
    let date: Date

    init(url: URL, date: Date) {
        self.url = url
        self.date = date
    }
}

class VideoURLCache {
    static let shared = VideoURLCache()
    private let logger = Logger(subsystem: "com.sloptok", category: "VideoURLCache")
    
    private init() {
        // Limit cache to 1000 entries to prevent memory bloat.
        cache.countLimit = 1000
        logger.info("VideoURLCache initialized with limit of 1000 entries")
    }

    // Using NSCache to allow automatic purging under memory pressure.
    private let cache = NSCache<NSString, CachedVideoURL>()
    
    func getVideoURL(for videoResource: String, completion: @escaping (URL?) -> Void) {
        let now = Date()
        let key = videoResource as NSString
        
        logger.info("🔍 Requesting URL for video: \(videoResource)")
        
        if let cachedEntry = cache.object(forKey: key) {
            // Check if cached entry is fresh (less than 24 hours old)
            if now.timeIntervalSince(cachedEntry.date) < 86400 {
                logger.info("✅ Cache HIT for \(videoResource) - URL: \(cachedEntry.url.absoluteString)")
                completion(cachedEntry.url)
                return
            } else {
                // Remove expired entry
                logger.info("⏰ Cache entry EXPIRED for \(videoResource) - was \(Int(now.timeIntervalSince(cachedEntry.date)))s old")
                cache.removeObject(forKey: key)
            }
        } else {
            logger.info("❌ Cache MISS for \(videoResource)")
        }
        
        let storage = Storage.storage()
        
        // Try seed videos first
        let seedRef = storage.reference(withPath: "videos/seed/\(videoResource).mp4")
        logger.info("🔄 Attempting to fetch seed video URL for \(videoResource)")
        
        seedRef.downloadURL { [weak self] url, error in
            if let url = url {
                self?.logger.info("✅ Found seed video URL for \(videoResource)")
                let cachedURL = CachedVideoURL(url: url, date: now)
                self?.cache.setObject(cachedURL, forKey: key)
                completion(url)
            } else {
                // If not found in seed, try generated videos
                self?.logger.info("🔄 Seed video not found, trying generated video path for \(videoResource)")
                let generatedRef = storage.reference(withPath: "videos/generated/\(videoResource).mp4")
                generatedRef.downloadURL { [weak self] url, error in
                    if let error = error {
                        self?.logger.error("❌ Error getting download URL for \(videoResource): \(error.localizedDescription)")
                        completion(nil)
                        return
                    }
                    if let url = url {
                        self?.logger.info("✅ Found generated video URL for \(videoResource)")
                        let cachedURL = CachedVideoURL(url: url, date: now)
                        self?.cache.setObject(cachedURL, forKey: key)
                        completion(url)
                    } else {
                        self?.logger.error("❌ No URL found for \(videoResource) in either seed or generated locations")
                        completion(nil)
                    }
                }
            }
        }
    }
}