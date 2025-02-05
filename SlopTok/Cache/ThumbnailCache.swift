import SwiftUI

// Helper class to wrap a cached thumbnail with the time it was cached.
class CachedThumbnail: NSObject {
    let uiImage: UIImage
    let date: Date

    init(uiImage: UIImage, date: Date) {
        self.uiImage = uiImage
        self.date = date
    }
}

class ThumbnailCache {
    static let shared = ThumbnailCache()
    private init() {
        cache.countLimit = 100
    }
    
    // NSCache automatically purges cached items on memory pressure.
    private let cache = NSCache<NSString, CachedThumbnail>()
    
    // Threshold for thumbnail cache expiration: 24 hours (86400 seconds)
    private let expirationInterval: TimeInterval = 86400

    // Returns a SwiftUI.Image from the cached UIImage if available.
    func getThumbnail(for key: String) -> Image? {
        let now = Date()
        let nsKey = key as NSString
        if let cached = cache.object(forKey: nsKey) {
            if now.timeIntervalSince(cached.date) < expirationInterval {
                return Image(uiImage: cached.uiImage)
            } else {
                cache.removeObject(forKey: nsKey)
            }
        }
        return nil
    }
    
    // Accepts a UIImage and caches it.
    func setThumbnail(_ image: UIImage, for key: String) {
        let cached = CachedThumbnail(uiImage: image, date: Date())
        cache.setObject(cached, forKey: key as NSString)
    }
}