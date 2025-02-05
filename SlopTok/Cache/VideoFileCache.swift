import Foundation

class VideoFileCache {
    static let shared = VideoFileCache()
    private init() {}
    
    private func localFileURL(for videoResource: String) -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDirectory.appendingPathComponent("\(videoResource).mp4")
    }
    
    func getLocalVideoURL(for videoResource: String, remoteURL: URL, completion: @escaping (URL?) -> Void) {
        let localURL = localFileURL(for: videoResource)
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: localURL.path) {
            completion(localURL)
            return
        }
        
        let task = URLSession.shared.downloadTask(with: remoteURL) { tempURL, response, error in
            if let error = error {
                print("Error downloading video \(videoResource): \(error.localizedDescription)")
                completion(remoteURL)
                return
            }
            guard let tempURL = tempURL else {
                completion(remoteURL)
                return
            }
            do {
                if fileManager.fileExists(atPath: localURL.path) {
                    try fileManager.removeItem(at: localURL)
                }
                try fileManager.moveItem(at: tempURL, to: localURL)
                completion(localURL)
            } catch {
                print("Error caching video \(videoResource): \(error.localizedDescription)")
                completion(remoteURL)
            }
        }
        task.resume()
    }
}