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
            // Load seed videos first
            let seedRef = storage.reference().child("videos/seed")
            let seedResult = try await seedRef.listAll()
            let seedVideos = seedResult.items.map { item -> String in
                let fullPath = item.name
                return String(fullPath.dropLast(4)) // Remove .mp4
            }.sorted() // Sort seed videos alphabetically
            
            // Load generated videos
            let generatedRef = storage.reference().child("videos/generated")
            let generatedResult = try await generatedRef.listAll()
            let generatedVideos = generatedResult.items.map { item -> String in
                let fullPath = item.name
                return String(fullPath.dropLast(4)) // Remove .mp4
            }.sorted(by: { $1.compare($0) == .orderedAscending }) // Sort generated videos newest first
            
            // Combine with seed videos first, then generated videos
            videos = seedVideos + generatedVideos
            print("📹 VideoService - Loaded \(videos.count) videos (\(seedVideos.count) seed, \(generatedVideos.count) generated)")
        } catch {
            self.error = error
            print("❌ VideoService - Error loading videos: \(error)")
        }
        
        isLoading = false
    }
    
    /// Adds a video to the end of the feed
    func appendVideo(_ videoId: String) {
        print("📹 VideoService - Appending video after seed videos")
        // Find the last seed video index
        let seedRef = storage.reference().child("videos/seed")
        if let lastSeedIndex = videos.lastIndex(where: { videoId in
            seedRef.child("\(videoId).mp4") != nil
        }) {
            // Insert after the last seed video
            videos.insert(videoId, at: lastSeedIndex + 1)
        } else {
            // If no seed videos found, append to beginning
            videos.insert(videoId, at: 0)
        }
        
        // Reload the complete video list to ensure everything is in sync
        Task {
            await loadVideos()
        }
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