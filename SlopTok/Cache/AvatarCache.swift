import SwiftUI
import FirebaseAuth

class CachedAvatar: NSObject {
    let image: UIImage
    let timestamp: Date
    
    init(image: UIImage) {
        self.image = image
        self.timestamp = Date()
    }
}

class AvatarCache {
    static let shared = AvatarCache()
    private let cache = NSCache<NSString, CachedAvatar>()
    private let expirationInterval: TimeInterval = 3600 // 1 hour
    
    private init() {}
    
    func getAvatar() async -> UIImage? {
        // 1. Check cache first
        if let cached = cache.object(forKey: "avatar" as NSString),
           Date().timeIntervalSince(cached.timestamp) < expirationInterval {
            return cached.image
        }
        
        // 2. If not in cache or expired, get from Firebase
        guard let photoURL = Auth.auth().currentUser?.photoURL,
              let (data, _) = try? await URLSession.shared.data(from: photoURL),
              let image = UIImage(data: data) else {
            return nil
        }
        
        // 3. Cache the new image
        cache.setObject(CachedAvatar(image: image), forKey: "avatar" as NSString)
        return image
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
}
