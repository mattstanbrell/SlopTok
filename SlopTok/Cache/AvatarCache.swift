import SwiftUI
import FirebaseAuth

enum AvatarSize: Int {
    case small = 96   // Default from Google
    case medium = 200 // Comments
    case large = 400  // Profile
    
    var cacheKey: String {
        switch self {
        case .small: return "avatar_small"
        case .medium: return "avatar_medium"
        case .large: return "avatar_large"
        }
    }
}

class CachedAvatar: NSObject {
    let image: UIImage
    let timestamp: Date
    let sizeInBytes: Int
    let size: AvatarSize
    
    init(image: UIImage, sizeInBytes: Int, size: AvatarSize) {
        self.image = image
        self.timestamp = Date()
        self.sizeInBytes = sizeInBytes
        self.size = size
    }
}

class AvatarCache {
    static let shared = AvatarCache()
    private let cache = NSCache<NSString, CachedAvatar>()
    private let expirationInterval: TimeInterval = 3600 // 1 hour
    
    private init() {}
    
    private func modifyURLForSize(_ originalURL: URL, targetSize: AvatarSize) -> URL {
        var urlString = originalURL.absoluteString
        
        // Check if URL already has a size parameter
        if let range = urlString.range(of: "=s\\d+(-c)?$", options: .regularExpression) {
            // Replace existing size
            urlString = urlString.replacingCharacters(in: range, with: "=s\(targetSize.rawValue)-c")
        } else {
            // Add size parameter
            urlString += "=s\(targetSize.rawValue)-c"
        }
        
        return URL(string: urlString) ?? originalURL
    }
    
    private func fetchImage(from url: URL) async -> (UIImage, Int)? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            return (image, data.count)
        } catch {
            return nil
        }
    }
    
    func getAvatar(size: AvatarSize) async -> UIImage? {
        let key = size.cacheKey as NSString
        
        // 1. Check cache first
        if let cached = cache.object(forKey: key),
           Date().timeIntervalSince(cached.timestamp) < expirationInterval {
            return cached.image
        }
        
        // 2. Get original URL from Firebase
        guard let originalURL = Auth.auth().currentUser?.photoURL else {
            return nil
        }
        
        // 3. Try to get the requested size
        let targetURL = modifyURLForSize(originalURL, targetSize: size)
        
        // First try the modified URL
        if let (image, bytes) = await fetchImage(from: targetURL) {
            let cached = CachedAvatar(image: image, sizeInBytes: bytes, size: size)
            cache.setObject(cached, forKey: key)
            return image
        }
        
        // If modified URL fails, try the original URL
        if let (image, bytes) = await fetchImage(from: originalURL) {
            let cached = CachedAvatar(image: image, sizeInBytes: bytes, size: size)
            cache.setObject(cached, forKey: key)
            return image
        }
        
        return nil
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
}
