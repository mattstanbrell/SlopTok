import Foundation
import FirebaseStorage

class VideoURLCache {
    static let shared = VideoURLCache()
    private init() {}

    // Cache entry holds a URL and the time it was fetched.
    private var cache: [String: (url: URL, date: Date)] = [:]

    func getVideoURL(for videoResource: String, completion: @escaping (URL?) -> Void) {
        let now = Date()
        if let cached = cache[videoResource], now.timeIntervalSince(cached.date) < 86400 {
            completion(cached.url)
            return
        }
        
        let storage = Storage.storage()
        let videoRef = storage.reference(withPath: "videos/\(videoResource).mp4")
        videoRef.downloadURL { [weak self] url, error in
            if let error = error {
                print("Error fetching video URL for \(videoResource): \(error.localizedDescription)")
                completion(nil)
                return
            }
            if let url = url {
                self?.cache[videoResource] = (url, now)
                // Enforce maximum cache limit of 1000 entries.
                if let self = self, self.cache.count > 1000 {
                    let sortedKeys = self.cache.sorted { $0.value.date < $1.value.date }.map { $0.key }
                    let removeCount = self.cache.count - 1000
                    for key in sortedKeys.prefix(removeCount) {
                        self.cache.removeValue(forKey: key)
                    }
                }
                completion(url)
            } else {
                completion(nil)
            }
        }
    }
}