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
            
            Task {
                // Check if we need initial profile creation
                if watchCounts.lastProfileUpdate == nil && 
                   watchCounts.videosWatchedSinceLastProfile >= self.seedVideoCount {
                    await self.triggerInitialProfile(userId: userId)
                }
                // Check if we need to generate new prompts
                else if watchCounts.lastProfileUpdate != nil &&
                        watchCounts.videosWatchedSinceLastPrompt >= self.promptGenerationThreshold {
                    await self.triggerPromptGeneration(userId: userId)
                }
                // // Profile updates will be implemented later
                // else if watchCounts.lastProfileUpdate != nil && 
                //         watchCounts.videosWatchedSinceLastProfile >= 50 {
                //     await self.triggerProfileUpdate(userId: userId)
                // }
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
                "lastProfileUpdate": FieldValue.serverTimestamp()
            ])
            
        await ProfileService.shared.createInitialProfile()
    }
    
    /// Triggers generation of new prompts after threshold is reached
    private func triggerPromptGeneration(userId: String) async {
        // Get liked videos since last prompt generation
        do {
            // Reset the counter first to prevent duplicate triggers
            try await db.collection("users")
                .document(userId)
                .collection("watchCounts")
                .document("counts")
                .updateData([
                    "videosWatchedSinceLastPrompt": 0,
                    "lastPromptGeneration": FieldValue.serverTimestamp()
                ])
            
            // Get liked videos since last prompt generation
            let lastGeneration = try await db.collection("users")
                .document(userId)
                .collection("watchCounts")
                .document("counts")
                .getDocument()
                .data()?["lastPromptGeneration"] as? Timestamp
            
            let interactions = try await db.collection("users")
                .document(userId)
                .collection("videoInteractions")
                .whereField("liked", isEqualTo: true)
                .whereField("timestamp", isGreaterThan: lastGeneration ?? Timestamp(date: Date(timeIntervalSince1970: 0)))
                .getDocuments()
            
            // Extract prompts from liked videos
            let likedVideos = interactions.documents.compactMap { doc -> (id: String, prompt: String)? in
                guard let prompt = doc.data()["prompt"] as? String else { return nil }
                return (id: doc.documentID, prompt: prompt)
            }
            
            // Generate new prompts if we have any liked videos
            if !likedVideos.isEmpty, let profile = await ProfileService.shared.currentProfile {
                let promptResult = await PromptGenerationService.shared.generatePrompts(
                    likedVideos: likedVideos,
                    profile: profile
                )
                
                switch promptResult {
                case .success(let response):
                    print("✅ Generated \(response.prompts.count) new prompts")
                    // TODO: Store prompts when we implement that feature
                case .failure(let error):
                    print("❌ Error generating prompts: \(error.description)")
                }
            }
        } catch {
            print("❌ Error during prompt generation: \(error)")
        }
    }
    
    // // Profile updates will be implemented later
    // private func triggerProfileUpdate(userId: String) async {
    //     try? await db.collection("users")
    //         .document(userId)
    //         .collection("watchCounts")
    //         .document("counts")
    //         .updateData([
    //             "videosWatchedSinceLastProfile": 0,
    //             "lastProfileUpdate": FieldValue.serverTimestamp()
    //         ])
    //     
    //     await ProfileService.shared.updateProfile()
    // }
} 