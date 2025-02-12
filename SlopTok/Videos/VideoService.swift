import Foundation
import FirebaseStorage

@MainActor
class VideoService: ObservableObject {
    static let shared = VideoService()
    private let storage = Storage.storage()
    @Published private(set) var videos: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private init() {}
    
    func loadVideos() async {
        isLoading = true
        error = nil
        
        do {
            var allVideos: [String] = []
            
            // Load seed videos
            let seedRef = storage.reference().child("videos/seed")
            let seedResult = try await seedRef.listAll()
            let seedVideos = seedResult.items.map { item -> String in
                let fullPath = item.name
                return String(fullPath.dropLast(4)) // Remove .mp4
            }
            allVideos.append(contentsOf: seedVideos)
            
            // Load generated videos
            let generatedRef = storage.reference().child("videos/generated")
            let generatedResult = try await generatedRef.listAll()
            let generatedVideos = generatedResult.items.map { item -> String in
                let fullPath = item.name
                return String(fullPath.dropLast(4)) // Remove .mp4
            }
            allVideos.append(contentsOf: generatedVideos)
            
            // Sort videos by name for consistent ordering
            videos = allVideos.sorted()
            print("📹 VideoService - Loaded \(videos.count) videos (\(seedVideos.count) seed, \(generatedVideos.count) generated)")
        } catch {
            self.error = error
            print("❌ VideoService - Error loading videos: \(error)")
        }
        
        isLoading = false
    }
    
    /// Adds a video to the end of the feed
    func appendVideo(_ videoId: String) {
        print("📹 VideoService - Appending video to end: \(videoId)")
        videos.append(videoId)
    }
    
    /// Adds a video to the beginning of the feed
    func insertVideoAtBeginning(_ videoId: String) {
        print("📹 VideoService - Inserting video at beginning: \(videoId)")
        videos.insert(videoId, at: 0)
    }
    
    /// Gets the storage path for a video
    func getVideoPath(_ videoId: String) -> String {
        // Check if it's a seed video
        if videos.contains(videoId) && storage.reference().child("videos/seed/\(videoId).mp4") != nil {
            return "videos/seed/\(videoId).mp4"
        }
        // Otherwise assume it's a generated video
        return "videos/generated/\(videoId).mp4"
    }
} 