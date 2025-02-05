import Foundation
import FirebaseStorage

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
    private init() {
        // Limit cache to 1000 entries to prevent memory bloat.
        cache.countLimit = 1000
    }

    // Using NSCache to allow automatic purging under memory pressure.
    private let cache = NSCache<NSString, CachedVideoURL>()
    
    func getVideoURL(for videoResource: String, completion: @escaping (URL?) -> Void) {
        let now = Date()
        let key = videoResource as NSString
        
        if let cachedEntry = cache.object(forKey: key) {
            // Check if cached entry is fresh (less than 24 hours old)
            if now.timeIntervalSince(cachedEntry.date) < 86400 {
                completion(cachedEntry.url)
                return
            } else {
                // Remove expired entry
                cache.removeObject(forKey: key)
            }
        }
        
        let storage = Storage.storage()
        let videoRef = storage.reference(withPath: "videos/\(videoResource).mp4")
        videoRef.downloadURL { [weak self] url, error in
            if let error = error {
                completion(nil)
                return
            }
            if let url = url {
                let cachedURL = CachedVideoURL(url: url, date: now)
                self?.cache.setObject(cachedURL, forKey: key)
                completion(url)
            } else {
                completion(nil)
            }
        }
    }
}