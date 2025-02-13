import SwiftUI

// Helper class to wrap a cached thumbnail with the time it was cached.
private class CachedThumbnail: NSObject {
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

    // MARK: - Public Methods
    
    /// Returns a SwiftUI.Image from the cached UIImage if available and not expired
    func getCachedThumbnail(for key: String) -> Image? {
        if let uiImage = getCachedUIImageThumbnail(for: key) {
            return Image(uiImage: uiImage)
        }
        return nil
    }
    
    /// Returns the cached UIImage if available and not expired
    func getCachedUIImageThumbnail(for key: String) -> UIImage? {
        let now = Date()
        let nsKey = key as NSString
        if let cached = cache.object(forKey: nsKey) {
            if now.timeIntervalSince(cached.date) < expirationInterval {
                return cached.uiImage
            } else {
                cache.removeObject(forKey: nsKey)
            }
        }
        return nil
    }
    
    /// Caches a UIImage with the current timestamp
    func setThumbnail(_ image: UIImage, for key: String) {
        let cached = CachedThumbnail(uiImage: image, date: Date())
        cache.setObject(cached, forKey: key as NSString)
    }
}