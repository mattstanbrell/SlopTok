import Foundation
import FirebaseStorage

class VideoURLCache {
    static let shared = VideoURLCache()
    private init() {}
    
    private var cache: [String: URL] = [:]
    
    func getVideoURL(for videoResource: String, completion: @escaping (URL?) -> Void) {
        if let cachedURL = cache[videoResource] {
            completion(cachedURL)
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
                self?.cache[videoResource] = url
                completion(url)
            } else {
                completion(nil)
            }
        }
    }
}