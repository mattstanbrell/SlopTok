import Foundation
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth

@MainActor
class VideoService: ObservableObject {
    static let shared = VideoService()
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    @Published private(set) var videos: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    // Track which videos are seed vs generated
    private var seedVideos: Set<String> = []
    private var generatedVideos: Set<String> = []

    private init() {}
    
    func loadVideos() async {
        isLoading = true
        error = nil
        
        do {
            // Get current user's ID
            guard let userId = Auth.auth().currentUser?.uid else {
                isLoading = false
                return
            }
            
            // Get list of videos user has already seen
            let seenVideosSnapshot = try await db.collection("users")
                .document(userId)
                .collection("videoInteractions")
                .getDocuments()
            
            let seenVideoIds = Set(seenVideosSnapshot.documents.map { $0.documentID })
            
            // Load seed videos first
            let seedRef = storage.reference().child("videos/seed")
            let seedResult = try await seedRef.listAll()
            let seedVideoIds = seedResult.items.map { item -> String in
                let fullPath = item.name
                return String(fullPath.dropLast(4)) // Remove .mp4
            }.sorted() // Sort seed videos alphabetically
            
            // Load generated videos
            let generatedRef = storage.reference().child("videos/generated")
            let generatedResult = try await generatedRef.listAll()
            let generatedVideoIds = generatedResult.items.map { item -> String in
                let fullPath = item.name
                return String(fullPath.dropLast(4)) // Remove .mp4
            }.sorted(by: { $1.compare($0) == .orderedAscending }) // Sort generated videos newest first
            
            // Update our tracking sets
            seedVideos = Set(seedVideoIds)
            generatedVideos = Set(generatedVideoIds)
            
            // Filter out seen videos and combine seed videos first, then generated videos
            let unseenSeedVideos = seedVideoIds.filter { !seenVideoIds.contains($0) }
            let unseenGeneratedVideos = generatedVideoIds.filter { !seenVideoIds.contains($0) }
            
            videos = unseenSeedVideos + unseenGeneratedVideos
            print("📹 VideoService - Loaded \(videos.count) unseen videos (\(unseenSeedVideos.count) seed, \(unseenGeneratedVideos.count) generated)")
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
        if let lastSeedIndex = videos.lastIndex(where: { seedVideos.contains($0) }) {
            // Insert after the last seed video
            videos.insert(videoId, at: lastSeedIndex + 1)
        } else {
            // If no seed videos found, append to beginning
            videos.insert(videoId, at: 0)
        }
        // Mark as generated video
        generatedVideos.insert(videoId)
    }
    
    /// Adds a video to the beginning of the feed
    func insertVideoAtBeginning(_ videoId: String) {
        print("📹 VideoService - Inserting video at beginning: \(videoId)")
        videos.insert(videoId, at: 0)
        // Mark as generated video
        generatedVideos.insert(videoId)
    }
    
    /// Gets the storage path for a video
    func getVideoPath(_ videoId: String) -> String {
        // Use our tracking sets to determine the correct path
        if seedVideos.contains(videoId) {
            return "videos/seed/\(videoId).mp4"
        }
        return "videos/generated/\(videoId).mp4"
    }
} 