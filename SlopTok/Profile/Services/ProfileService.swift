import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Service responsible for managing user profiles, including creation, updates, and storage
@MainActor
class ProfileService: ObservableObject {
    /// Shared instance
    static let shared = ProfileService()
    
    /// The current user's profile
    @Published private(set) var currentProfile: UserProfile?
    
    /// The current watch counts
    @Published private(set) var watchCounts: WatchCounts
    
    /// Firestore database reference
    private let db = Firestore.firestore()
    
    /// Whether initial profile load has completed
    private var initialLoadCompleted = false
    
    /// Creates a new profile service and loads the current user's profile
    private init() {
        self.watchCounts = WatchCounts()
        Task {
            await loadProfile()
        }
    }
    
    /// Creates the initial profile after seed videos
    func createInitialProfile() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            // 1. Get liked seed videos
            let interactions = try await db.collection("users")
                .document(userId)
                .collection("videoInteractions")
                .whereField("liked", isEqualTo: true)
                .getDocuments()
            
            // Extract prompts from liked videos
            let likedVideos = interactions.documents.compactMap { doc -> (id: String, prompt: String)? in
                guard let prompt = doc.data()["prompt"] as? String else { return nil }
                return (id: doc.documentID, prompt: prompt)
            }
            
            // 2. Generate profile using LLM
            let result = await ProfileGenerationService.shared.generateInitialProfile(likedVideos: likedVideos)
            
            switch result {
            case .success(let response):
                // 3. Convert LLM response to interests
                let interests = await ProfileGenerationService.shared.convertToInterests(response)
                
                // 4. Create and store profile
                let profile = UserProfile(
                    interests: interests,
                    description: response.description
                )
                
                // Store in Firestore
                try await storeProfile(profile)
                
                // Update local state
                self.currentProfile = profile
                
                // Generate initial prompts
                if let profile = self.currentProfile {
                    let promptResult = await PromptGenerationService.shared.generateInitialPrompts(
                        likedVideos: likedVideos,
                        profile: profile
                    )
                    
                    switch promptResult {
                    case .success(let response):
                        print("✅ Generated \(response.prompts.count) initial prompts")
                        // TODO: Store prompts when we implement that feature
                    case .failure(let error):
                        print("❌ Error generating initial prompts: \(error.description)")
                    }
                }
                
            case .failure(let error):
                print("❌ Error generating initial profile: \(error.description)")
            }
            
        } catch {
            print("❌ Error creating initial profile: \(error)")
        }
    }
    
    /// Stores a profile in Firestore
    private func storeProfile(_ profile: UserProfile) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Batch write for consistency
        let batch = db.batch()
        
        // Store description at user level
        let userRef = db.collection("users").document(userId)
        batch.setData([
            "description": profile.description,
            "lastUpdated": FieldValue.serverTimestamp()
        ], forDocument: userRef, merge: true)
        
        // Store each interest
        for interest in profile.interests {
            let interestRef = userRef.collection("interests").document(interest.id)
            batch.setData([
                "topic": interest.topic,
                "weight": interest.weight,
                "examples": interest.examples,
                "lastUpdated": FieldValue.serverTimestamp()
            ], forDocument: interestRef)
        }
        
        try await batch.commit()
    }
    
    /// Loads the current user's profile from Firestore
    private func loadProfile() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            // Load watch counts
            let watchCountsDoc = try await db.collection("users")
                .document(userId)
                .collection("watchCounts")
                .document("counts")
                .getDocument()
            
            if let data = watchCountsDoc.data() {
                if let counts = WatchCounts(from: data) {
                    self.watchCounts = counts
                }
            }
            
            // Load interests
            let interestsSnapshot = try await db.collection("users")
                .document(userId)
                .collection("interests")
                .getDocuments()
            
            var interests: [Interest] = []
            for doc in interestsSnapshot.documents {
                if let topic = doc.data()["topic"] as? String,
                   let weight = doc.data()["weight"] as? Double,
                   let examples = doc.data()["examples"] as? [String],
                   let lastUpdated = (doc.data()["lastUpdated"] as? Timestamp)?.dateValue() {
                    let interest = Interest(topic: topic, examples: examples)
                    interests.append(interest)
                }
            }
            
            // Load profile description
            let userDoc = try await db.collection("users")
                .document(userId)
                .getDocument()
            
            let description = userDoc.data()?["description"] as? String ?? ""
            let lastUpdated = (userDoc.data()?["lastUpdated"] as? Timestamp)?.dateValue() ?? Date()
            
            // Create profile
            self.currentProfile = UserProfile(
                interests: interests,
                description: description
            )
            
            self.initialLoadCompleted = true
            
        } catch {
            print("❌ Error loading profile: \(error)")
        }
    }
    
    /// Increments video watch counts and triggers profile/prompt updates if needed
    func incrementWatchCounts() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Increment counts
        watchCounts.videosWatchedSinceLastPrompt += 1
        watchCounts.videosWatchedSinceLastProfile += 1
        
        // Update Firestore
        do {
            try await db.collection("users")
                .document(userId)
                .collection("watchCounts")
                .document("counts")
                .setData(watchCounts.firestoreData)
            
            // TODO: Trigger profile/prompt updates when counts reach thresholds
            
        } catch {
            print("❌ Error updating watch counts: \(error)")
        }
    }
    
    /// Updates the profile based on recent video interactions
    func updateProfile() async {
        // TODO: Implement profile updates
    }
} 