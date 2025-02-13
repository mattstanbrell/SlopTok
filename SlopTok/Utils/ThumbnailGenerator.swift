import SwiftUI
import AVFoundation
import FirebaseStorage

class ThumbnailGenerator {
    static func getThumbnail(for videoId: String, completion: @escaping (Image?) -> Void) {
        // First check ThumbnailCache for SwiftUI Image
        if let cachedThumb = ThumbnailCache.shared.getCachedThumbnail(for: videoId) {
            DispatchQueue.main.async {
                completion(cachedThumb)
            }
            return
        }
        
        // Generate if not found
        generateThumbnailUIImage(for: videoId) { uiImage in
            DispatchQueue.main.async {
                completion(uiImage.map { Image(uiImage: $0) })
            }
        }
    }
    
    static func getThumbnailUIImage(for videoId: String, completion: @escaping (UIImage?) -> Void) {
        // First check ThumbnailCache for UIImage
        if let cachedThumb = ThumbnailCache.shared.getCachedUIImageThumbnail(for: videoId) {
            DispatchQueue.main.async {
                completion(cachedThumb)
            }
            return
        }
        
        // Generate if not found
        generateThumbnailUIImage(for: videoId) { uiImage in
            DispatchQueue.main.async {
                completion(uiImage)
            }
        }
    }
    
    private static func generateThumbnailUIImage(for videoId: String, completion: @escaping (UIImage?) -> Void) {
        // First check if we have the video file cached locally
        VideoFileCache.shared.getLocalVideoURL(for: videoId, remoteURL: nil) { localURL in
            if let localURL = localURL {
                generateThumbnailFromLocalVideo(localURL: localURL, videoId: videoId, completion: completion)
                return
            }
            
            // If no local file, get the storage path and download URL
            let storagePath = VideoService.shared.getVideoPath(videoId)
            let storage = Storage.storage()
            let videoRef = storage.reference(withPath: storagePath)
            
            videoRef.downloadURL { url, error in
                guard let remoteURL = url else {
                    print("Could not get download URL for videoId: \(videoId), error: \(error?.localizedDescription ?? "unknown")")
                    completion(nil)
                    return
                }
                
                // Get the local video file using the remote URL
                VideoFileCache.shared.getLocalVideoURL(for: videoId, remoteURL: remoteURL) { localURL in
                    guard let localURL = localURL else {
                        print("Local video URL is nil for videoId: \(videoId)")
                        completion(nil)
                        return
                    }
                    
                    generateThumbnailFromLocalVideo(localURL: localURL, videoId: videoId, completion: completion)
                }
            }
        }
    }
    
    private static func generateThumbnailFromLocalVideo(localURL: URL, videoId: String, completion: @escaping (UIImage?) -> Void) {
        let asset = AVAsset(url: localURL)
        asset.loadValuesAsynchronously(forKeys: ["preferredTransform"]) {
            var error: NSError?
            let status = asset.statusOfValue(forKey: "preferredTransform", error: &error)
            if status == .loaded {
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                do {
                    let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 60), actualTime: nil)
                    let thumbnailUIImage = UIImage(cgImage: cgImage)
                    // Cache the thumbnail using the existing UIKit UIImage internally.
                    ThumbnailCache.shared.setThumbnail(thumbnailUIImage, for: videoId)
                    completion(thumbnailUIImage)
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