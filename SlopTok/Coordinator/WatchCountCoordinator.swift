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
    /// TODO change back to 50
    private let profileUpdateThreshold = 25
    
    /// Flag to track if prompt generation is in progress
    private var isGeneratingPrompts = false
    
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
        // Prevent concurrent generations
        guard !isGeneratingPrompts else {
            print("⏳ Prompt generation already in progress, skipping...")
            return
        }
        
        // Set flag before starting
        isGeneratingPrompts = true
        
        // Record the generation start time before any Firebase calls
        let generationStartTime = Timestamp(date: Date())
        var initialWatchCount = 0
        var generationSucceeded = false
        var lastGeneration: Timestamp?
        
        // Get liked videos since last prompt generation
        do {
            print("🎬 Starting prompt generation process...")
            
            // Start a transaction to get the current state
            _ = try await db.runTransaction({ transaction, errorPointer in
                do {
                    let countsRef = self.db.collection("users")
                        .document(userId)
                        .collection("watchCounts")
                        .document("counts")
                    
                    let snapshot = try transaction.getDocument(countsRef)
                    lastGeneration = snapshot.data()?["lastPromptGeneration"] as? Timestamp
                    initialWatchCount = snapshot.data()?["videosWatchedSinceLastPrompt"] as? Int ?? 0
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            })
            
            print("📅 Last generation timestamp: \(lastGeneration?.dateValue().description ?? "nil")")
            
            let interactions = try await db.collection("users")
                .document(userId)
                .collection("videoInteractions")
                .whereField("liked_timestamp", isGreaterThan: lastGeneration ?? Timestamp(date: Date(timeIntervalSince1970: 0)))
                .getDocuments()
            print("🔍 Found \(interactions.documents.count) liked videos since last generation")
            
            // Extract prompts from liked videos
            let likedVideos = interactions.documents.compactMap { doc -> LikedVideo? in
                guard let prompt = doc.data()["prompt"] as? String,
                      let timestamp = doc.data()["liked_timestamp"] as? Timestamp else { return nil }
                return LikedVideo(id: doc.documentID, timestamp: timestamp.dateValue(), prompt: prompt)
            }
            print("📝 Extracted \(likedVideos.count) prompts from liked videos")
            
            // Generate new prompts if we have any liked videos
            if !likedVideos.isEmpty {
                print("👤 Fetching current profile...")
                if let profile = await ProfileService.shared.currentProfile {
                    print("✅ Got profile, generating videos...")
                    do {
                        let videoIds = try await VideoGenerator.shared.generateVideos(
                            likedVideos: likedVideos,
                            profile: profile
                        )
                        print("🎉 Successfully generated \(videoIds.count) new videos")
                        generationSucceeded = true
                    } catch {
                        print("❌ Error generating videos: \(error)")
                        throw error  // Re-throw to ensure we handle this in the outer catch
                    }
                } else {
                    print("❌ Failed to get current profile")
                    throw NSError(domain: "WatchCountCoordinator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get current profile"])
                }
            } else {
                print("⚠️ No liked videos found since last generation")
                // If no videos to process, consider it a success so we update the timestamp
                generationSucceeded = true
            }
        } catch {
            print("❌ Error during prompt generation: \(error)")
        }
        
        // Always update the counters, but only update timestamp on success
        defer {
            isGeneratingPrompts = false
            
            // Ensure we account for videos watched during generation
            Task {
                do {
                    _ = try await db.runTransaction({ transaction, errorPointer in
                        do {
                            let countsRef = self.db.collection("users")
                                .document(userId)
                                .collection("watchCounts")
                                .document("counts")
                            
                            let snapshot = try transaction.getDocument(countsRef)
                            let currentCount = snapshot.data()?["videosWatchedSinceLastPrompt"] as? Int ?? 0
                            
                            // Calculate how many videos were watched during generation
                            let videosWatchedDuringGeneration = currentCount - initialWatchCount
                            
                            var updates: [String: Any] = [
                                "videosWatchedSinceLastPrompt": videosWatchedDuringGeneration
                            ]
                            
                            // Only update the timestamp if generation succeeded
                            if generationSucceeded {
                                updates["lastPromptGeneration"] = generationStartTime
                            }
                            
                            transaction.updateData(updates, forDocument: countsRef)
                            return nil
                        } catch {
                            errorPointer?.pointee = error as NSError
                            return nil
                        }
                    })
                    print("✅ Updated watch counts" + (generationSucceeded ? " and timestamp" : "") + " after generation attempt")
                } catch {
                    print("❌ Error updating watch counts after generation: \(error)")
                }
            }
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