import Foundation
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth
import UIKit

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
        print("📹 VideoService - Appending video to feed: \(videoId)")
        // Find the last generated video index, or last seed video index if no generated videos
        let insertIndex: Int
        if let lastGeneratedIndex = videos.lastIndex(where: { generatedVideos.contains($0) }) {
            // Insert after the last generated video
            insertIndex = lastGeneratedIndex + 1
        } else if let lastSeedIndex = videos.lastIndex(where: { seedVideos.contains($0) }) {
            // No generated videos yet, insert after last seed video
            insertIndex = lastSeedIndex + 1
        } else {
            // No videos at all, insert at beginning
            insertIndex = 0
        }
        
        videos.insert(videoId, at: insertIndex)
        // Mark as generated video
        generatedVideos.insert(videoId)
        print("📹 VideoService - Inserted video at index \(insertIndex)")
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
    
    /// Gets a UIImage thumbnail for a video
    /// - Parameter videoId: The ID of the video
    /// - Returns: UIImage if thumbnail could be loaded, nil otherwise
    func getUIImageThumbnail(for videoId: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            ThumbnailGenerator.generateThumbnail(for: videoId) { _ in
                let uiImage = ThumbnailCache.shared.getCachedUIImage(for: videoId)
                continuation.resume(returning: uiImage)
            }
        }
    }
} 