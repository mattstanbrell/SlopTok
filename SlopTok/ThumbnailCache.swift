import UIKit

class ThumbnailCache {
    static let shared = ThumbnailCache()
    private init() {}
    
    // NSCache automatically purges cached items on memory pressure
    private let cache = NSCache<NSString, UIImage>()
    
    func getThumbnail(for key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }
    
    func setThumbnail(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}