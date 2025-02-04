import UIKit
import AVFoundation

class ThumbnailGenerator {
    static func generateThumbnail(for videoId: String, completion: @escaping (UIImage?) -> Void) {
        // First check ThumbnailCache
        if let cachedThumb = ThumbnailCache.shared.getThumbnail(for: videoId) {
            DispatchQueue.main.async {
                completion(cachedThumb)
            }
            return
        }
        
        // Get the remote URL and then the local video URL from the cache
        VideoURLCache.shared.getVideoURL(for: videoId) { remoteURL in
            guard let remoteURL = remoteURL else {
                print("Video URL is nil for videoId: \(videoId)")
                completion(nil)
                return
            }
            
            VideoFileCache.shared.getLocalVideoURL(for: videoId, remoteURL: remoteURL) { localURL in
                guard let localURL = localURL else {
                    print("Local video URL is nil for videoId: \(videoId)")
                    completion(nil)
                    return
                }
                
                let asset = AVAsset(url: localURL)
                asset.loadValuesAsynchronously(forKeys: ["preferredTransform"]) {
                    var error: NSError?
                    let status = asset.statusOfValue(forKey: "preferredTransform", error: &error)
                    if status == .loaded {
                        let imageGenerator = AVAssetImageGenerator(asset: asset)
                        imageGenerator.appliesPreferredTrackTransform = true
                        do {
                            let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 60), actualTime: nil)
                            let thumbnail = UIImage(cgImage: cgImage)
                            ThumbnailCache.shared.setThumbnail(thumbnail, for: videoId)
                            DispatchQueue.main.async {
                                completion(thumbnail)
                            }
                        } catch {
                            print("Error generating thumbnail: \(error.localizedDescription)")
                            completion(nil)
                        }
                    } else {
                        print("Failed to load preferredTransform: \(error?.localizedDescription ?? "unknown error")")
                        completion(nil)
                    }
                }
            }
        }
    }
}