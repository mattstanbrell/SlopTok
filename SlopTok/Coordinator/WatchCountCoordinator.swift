import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class WatchCountCoordinator: ObservableObject {
    static let shared = WatchCountCoordinator()
    private let db = Firestore.firestore()
    
    /// Number of seed videos needed before initial profile creation
    private let seedVideoCount = 10
    
    /// Number of videos to watch before generating new prompts
    private let promptGenerationThreshold = 20
    
    /// Number of videos to watch before updating profile
    private let profileUpdateThreshold = 50
    
    private init() {}
    
    /// Ensures watch counts document exists and starts monitoring
    func startMonitoring() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let watchCountsRef = db.collection("users")
            .document(userId)
            .collection("watchCounts")
            .document("counts")
            
        // First ensure the document exists
        do {
            let snapshot = try await watchCountsRef.getDocument()
            if !snapshot.exists {
                // Create initial watch counts
                try await watchCountsRef.setData(WatchCounts().firestoreData)
            }
        } catch {
            print("❌ Error initializing watch counts: \(error)")
            return
        }
        
        // Then start monitoring
        watchCountsRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self,
                  let data = snapshot?.data(),
                  let watchCounts = WatchCounts(from: data) else { return }
            
            print("📊 Watch Counts Update:")
            print("  Videos since last prompt: \(watchCounts.videosWatchedSinceLastPrompt)")
            print("  Videos since last profile: \(watchCounts.videosWatchedSinceLastProfile)")
            print("  Last profile update: \(watchCounts.lastProfileUpdate?.description ?? "nil")")
            print("  Last prompt generation: \(watchCounts.lastPromptGeneration?.description ?? "nil")")
            
            Task {
                // Check if we need initial profile creation
                if watchCounts.lastProfileUpdate == nil && 
                   watchCounts.videosWatchedSinceLastProfile >= self.seedVideoCount {
                    print("🎯 Triggering initial profile creation")
                    await self.triggerInitialProfile(userId: userId)
                }
                // Check if we need to generate new prompts
                else if watchCounts.lastProfileUpdate != nil &&
                        watchCounts.videosWatchedSinceLastPrompt >= self.promptGenerationThreshold {
                    print("🎯 Triggering prompt generation - Threshold reached")
                    await self.triggerPromptGeneration(userId: userId)
                }
                // Check if we need to update profile
                else if watchCounts.lastProfileUpdate != nil && 
                        watchCounts.videosWatchedSinceLastProfile >= self.profileUpdateThreshold {
                    print("🎯 Triggering profile update - Threshold reached")
                    await self.triggerProfileUpdate(userId: userId)
                } else {
                    print("⏳ Not triggering updates:")
                    print("  Has profile? \(watchCounts.lastProfileUpdate != nil)")
                    print("  Videos needed for prompts: \(self.promptGenerationThreshold - watchCounts.videosWatchedSinceLastPrompt)")
                    print("  Videos needed for profile: \(self.profileUpdateThreshold - watchCounts.videosWatchedSinceLastProfile)")
                }
            }
        }
    }
    
    /// Triggers initial profile creation after seed videos
    private func triggerInitialProfile(userId: String) async {
        // Reset the counter first to prevent duplicate triggers
        try? await db.collection("users")
            .document(userId)
            .collection("watchCounts")
            .document("counts")
            .updateData([
                "videosWatchedSinceLastProfile": 0,
                "videosWatchedSinceLastPrompt": 0,
                "lastProfileUpdate": FieldValue.serverTimestamp(),
                "lastPromptGeneration": FieldValue.serverTimestamp()
            ])
            
        await ProfileService.shared.createInitialProfile()
    }
    
    /// Triggers generation of new prompts after threshold is reached
    private func triggerPromptGeneration(userId: String) async {
        // Get liked videos since last prompt generation
        do {
            print("🎬 Starting prompt generation process...")
            
            // Get liked videos since last prompt generation
            let lastGeneration = try await db.collection("users")
                .document(userId)
                .collection("watchCounts")
                .document("counts")
                .getDocument()
                .data()?["lastPromptGeneration"] as? Timestamp
            print("📅 Last generation timestamp: \(lastGeneration?.dateValue().description ?? "nil")")
            
            let interactions = try await db.collection("users")
                .document(userId)
                .collection("videoInteractions")
                .whereField("liked_timestamp", isGreaterThan: lastGeneration ?? Timestamp(date: Date(timeIntervalSince1970: 0)))
                .getDocuments()
            print("🔍 Found \(interactions.documents.count) liked videos since last generation")
            
            // Extract prompts from liked videos
            let likedVideos = interactions.documents.compactMap { doc -> (id: String, prompt: String)? in
                guard let prompt = doc.data()["prompt"] as? String else { return nil }
                return (id: doc.documentID, prompt: prompt)
            }
            print("📝 Extracted \(likedVideos.count) prompts from liked videos")
            
            // Generate new prompts if we have any liked videos
            if !likedVideos.isEmpty {
                print("👤 Fetching current profile...")
                if let profile = await ProfileService.shared.currentProfile {
                    print("✅ Got profile, generating prompts...")
                    let promptResult = await PromptGenerationService.shared.generatePrompts(
                        likedVideos: likedVideos,
                        profile: profile
                    )
                    
                    switch promptResult {
                    case let .success((response, _)):
                        print("🎉 Successfully generated \(response.prompts.count) new prompts")
                        // Reset counters and update timestamp only after successful generation
                        try await db.collection("users")
                            .document(userId)
                            .collection("watchCounts")
                            .document("counts")
                            .updateData([
                                "videosWatchedSinceLastPrompt": 0,
                                "lastPromptGeneration": FieldValue.serverTimestamp()
                            ])
                        print("✅ Reset watch counts and updated timestamp")
                    case .failure(let error):
                        print("❌ Error generating prompts: \(error.description)")
                    }
                } else {
                    print("❌ Failed to get current profile")
                }
            } else {
                print("⚠️ No liked videos found since last generation, skipping prompt generation")
                // Still reset the counter to prevent getting stuck
                try await db.collection("users")
                    .document(userId)
                    .collection("watchCounts")
                    .document("counts")
                    .updateData([
                        "videosWatchedSinceLastPrompt": 0,
                        "lastPromptGeneration": FieldValue.serverTimestamp()
                    ])
                print("✅ Reset watch counts and updated timestamp")
            }
        } catch {
            print("❌ Error during prompt generation: \(error)")
        }
    }
    
    /// Triggers profile update after threshold is reached
    private func triggerProfileUpdate(userId: String) async {
        print("🔄 Starting profile update process...")
        
        // Reset the counter first to prevent duplicate triggers
        try? await db.collection("users")
            .document(userId)
            .collection("watchCounts")
            .document("counts")
            .updateData([
                "videosWatchedSinceLastProfile": 0,
                "lastProfileUpdate": FieldValue.serverTimestamp()
            ])
        
        await ProfileService.shared.updateProfile()
    }
} 