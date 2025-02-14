import SwiftUI
import AVFoundation
import FirebaseStorage

class ThumbnailGenerator {
    static func getThumbnail(for videoId: String) async -> Image? {
        // First check ThumbnailCache for SwiftUI Image
        if let cachedThumb = ThumbnailCache.shared.getCachedThumbnail(for: videoId) {
            return cachedThumb
        }
        
        // Generate if not found
        if let uiImage = await generateThumbnailUIImage(for: videoId) {
            return Image(uiImage: uiImage)
        }
        return nil
    }
    
    static func getThumbnailUIImage(for videoId: String) async -> UIImage? {
        // First check ThumbnailCache for UIImage
        if let cachedThumb = ThumbnailCache.shared.getCachedUIImageThumbnail(for: videoId) {
            return cachedThumb
        }
        
        // Generate if not found
        return await generateThumbnailUIImage(for: videoId)
    }
    
    private static func generateThumbnailUIImage(for videoId: String) async -> UIImage? {
        // First check if we have the video file cached locally without remote URL
        let localURL = VideoFileCache.shared.localFileURL(for: videoId)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return await generateThumbnailFromLocalVideo(localURL: localURL, videoId: videoId)
        }
        
        // If no local file, get the storage path and download URL
        let storagePath = await VideoService.shared.getVideoPath(videoId)
        let storage = Storage.storage()
        let videoRef = storage.reference(withPath: storagePath)
        
        do {
            let remoteURL = try await videoRef.downloadURL()
            
            // Download the video using the cache
            return await withCheckedContinuation { continuation in
                VideoFileCache.shared.getLocalVideoURL(for: videoId, remoteURL: remoteURL) { localURL in
                    if let localURL = localURL {
                        Task {
                            let thumbnail = await generateThumbnailFromLocalVideo(localURL: localURL, videoId: videoId)
                            continuation.resume(returning: thumbnail)
                        }
                        return
                    }
                    
                    print("❌ Failed to access video file for thumbnail generation")
                    continuation.resume(returning: nil)
                }
            }
        } catch {
            print("❌ Failed to get download URL for video \(videoId): \(error.localizedDescription)")
            return nil
        }
    }
    
    private static func generateThumbnailFromLocalVideo(localURL: URL, videoId: String) async -> UIImage? {
        return await withCheckedContinuation { continuation in
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
                        continuation.resume(returning: thumbnailUIImage)
                    } catch {
                        print("Error generating thumbnail: \(error.localizedDescription)")
                        continuation.resume(returning: nil)
                    }
                } else {
                    print("Failed to load preferredTransform: \(error?.localizedDescription ?? "unknown error")")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}