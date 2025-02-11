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
            // Get reference to the seed folder
            let seedRef = storage.reference().child("videos/seed")
            
            // List all items in the seed folder
            let result = try await seedRef.listAll()
            
            // Extract video IDs from the items (removing .mp4 extension)
            let videoIds = result.items.map { item -> String in
                let fullPath = item.name
                return String(fullPath.dropLast(4)) // Remove .mp4
            }
            
            // Sort videos by name for consistent ordering
            videos = videoIds.sorted()
            print("📹 VideoService - Loaded \(videos.count) videos")
        } catch {
            self.error = error
            print("❌ VideoService - Error loading videos: \(error)")
        }
        
        isLoading = false
    }
    
} 