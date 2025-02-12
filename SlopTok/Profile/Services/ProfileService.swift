import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseVertexAI

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
            case let .success((response, _)):
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
                    let promptResult = await PromptGenerationService.shared.generatePrompts(
                        likedVideos: likedVideos,
                        profile: profile
                    )
                    
                    switch promptResult {
                    case let .success((response, _)):
                        print("✅ Generated \(response.prompts.count) initial prompts")
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
    
    /// Updates the profile based on recent video interactions
    func updateProfile() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            // Get liked videos since last profile update
            let lastUpdate = try await db.collection("users")
                .document(userId)
                .collection("watchCounts")
                .document("counts")
                .getDocument()
                .data()?["lastProfileUpdate"] as? Timestamp
            print("📅 Last profile update timestamp: \(lastUpdate?.dateValue().description ?? "nil")")
            
            let interactions = try await db.collection("users")
                .document(userId)
                .collection("videoInteractions")
                .whereField("liked_timestamp", isGreaterThan: lastUpdate ?? Timestamp(date: Date(timeIntervalSince1970: 0)))
                .getDocuments()
            print("🔍 Found \(interactions.documents.count) liked videos since last profile update")
            
            // Extract prompts from liked videos
            let likedVideos = interactions.documents.compactMap { doc -> (id: String, prompt: String)? in
                guard let prompt = doc.data()["prompt"] as? String else { return nil }
                return (id: doc.documentID, prompt: prompt)
            }
            print("📝 Extracted \(likedVideos.count) prompts from liked videos")
            
            // Generate updated profile if we have any liked videos
            if !likedVideos.isEmpty {
                print("✨ Generating updated profile...")
                let profileResult = await ProfileGenerationService.shared.generateUpdatedProfile(likedVideos: likedVideos)
                
                switch profileResult {
                case let .success((response, _)):
                    print("🎉 Successfully generated updated profile")
                    // Convert LLM response to interests
                    let interests = await ProfileGenerationService.shared.convertToInterests(response)
                    
                    // Create and store profile
                    let profile = UserProfile(
                        interests: interests,
                        description: response.description
                    )
                    
                    // Store in Firestore
                    try await storeProfile(profile)
                    
                    // Update local state
                    self.currentProfile = profile
                    
                case .failure(let error):
                    print("❌ Error generating updated profile: \(error.description)")
                }
            } else {
                print("⚠️ No liked videos found since last update, skipping profile update")
            }
        } catch {
            print("❌ Error updating profile: \(error)")
        }
    }
}

class VertexAIService {
    static let shared = VertexAIService()
    private let vertex = VertexAI.vertexAI()
    private let model: GenerativeModel
    
    private init() {
        self.model = vertex.generativeModel(modelName: "gemini-2.0-flash")
    }
    
    func analyzeText(_ prompt: String) async throws -> String {
        let response = try await model.generateContent(prompt)
        return response.text ?? "No analysis available"
    }
    
    func analyzeImage(_ image: UIImage, prompt: String = "What's in this picture?") async throws -> String {
        let response = try await model.generateContent(image, prompt)
        return response.text ?? "No analysis available"
    }
    
    func generateContent(_ textA: String, _ imageA: UIImage, _ textB: String, _ imageB: UIImage, _ prompt: String) async throws -> String {
        let response = try await model.generateContent(textA, imageA, textB, imageB, prompt)
        return response.text ?? "No analysis available"
    }
    
    func generateContentForFive(images: [(label: String, image: UIImage)], prompt: String) async throws -> String {
        guard !images.isEmpty else {
            return "No images to analyze"
        }
        
        if images.count == 1 {
            return try await model.generateContent(
                "Image 1", images[0].image,
                "Describe Image 1"
            ).text ?? "No analysis available"
        } else if images.count == 2 {
            return try await model.generateContent(
                "Image 1", images[0].image,
                "Image 2", images[1].image,
                "Describe Image 1 and Image 2"
            ).text ?? "No analysis available"
        } else if images.count == 3 {
            return try await model.generateContent(
                "Image 1", images[0].image,
                "Image 2", images[1].image,
                "Image 3", images[2].image,
                "Describe Image 1, Image 2, and Image 3"
            ).text ?? "No analysis available"
        } else if images.count == 4 {
            return try await model.generateContent(
                "Image 1", images[0].image,
                "Image 2", images[1].image,
                "Image 3", images[2].image,
                "Image 4", images[3].image,
                "Describe Image 1, Image 2, Image 3, and Image 4"
            ).text ?? "No analysis available"
        } else {
            return try await model.generateContent(
                "Image 1", images[0].image,
                "Image 2", images[1].image,
                "Image 3", images[2].image,
                "Image 4", images[3].image,
                "Image 5", images[4].image,
                "Describe Image 1, Image 2, Image 3, Image 4, and Image 5"
            ).text ?? "No analysis available"
        }
    }
} 
