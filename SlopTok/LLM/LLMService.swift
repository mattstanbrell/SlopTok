import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

extension Data {
    var prettyPrintedJSONString: String? {
        guard let object = try? JSONSerialization.jsonObject(with: self, options: []),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let prettyPrintedString = String(data: data, encoding: .utf8) else { return nil }
        return prettyPrintedString
    }
}

extension String {
    var prettyPrintedJSONString: String? {
        guard let data = self.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) else { return nil }
        return String(data: prettyData, encoding: .utf8)
    }
}

@MainActor
class LLMService {
    static let shared = LLMService()
    private let apiKey: String
    private let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    
    private init() {
        // OpenAI API key in XCode env for local testing.
    }
    
    // MARK: - Generic LLM Call
    
    private struct LLMResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let content: String
            }
            let message: Message
        }
        let choices: [Choice]
    }
    
    private func callLLM<T: Codable>(prompt: String, schema: [String: Any]) async throws -> T {
        print("🤖 Sending prompt to LLM:")
        print(prompt)
        print("\n🔍 Using schema:")
        print(try JSONSerialization.data(withJSONObject: schema, options: .prettyPrinted).prettyPrintedJSONString ?? "")
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": prompt]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": String(describing: T.self).lowercased(),
                    "schema": schema,
                    "strict": true
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let response = try JSONDecoder().decode(LLMResponse.self, from: data)
        guard let content = response.choices.first?.message.content else {
            throw URLError(.badServerResponse)
        }
        
        print("\n✅ Received response:")
        print(content.prettyPrintedJSONString ?? content)
        print("-------------------\n")
        
        return try JSONDecoder().decode(T.self, from: content.data(using: .utf8)!)
    }
    
    // MARK: - Helpers
    
    // MARK: - Profile Generation
    
    struct UserProfile: Codable {
        struct Interest: Codable, Identifiable {
            var id: String  // Firestore document ID
            let topic: String
            var weight: Double  // 0-1, var to allow updates
            let examples: [String]
            var lastUpdated: Date
            
            init(id: String = UUID().uuidString,
                 topic: String,
                 weight: Double = 0.5,  // New interests start at 0.5
                 examples: [String],
                 lastUpdated: Date = Date()) {
                self.id = id
                self.topic = topic
                self.weight = weight
                self.examples = examples
                self.lastUpdated = lastUpdated
            }
        }
        
        struct WeightedContentType: Codable, Identifiable {
            var id: String
            let type: String
            var weight: Double  // 0-1, var to allow updates
            var lastUpdated: Date
            
            init(id: String = UUID().uuidString,
                 type: String,
                 weight: Double = 0.5,  // New content types start at 0.5
                 lastUpdated: Date = Date()) {
                self.id = id
                self.type = type
                self.weight = weight
                self.lastUpdated = lastUpdated
            }
        }
        
        var interests: [Interest]
        var description: String
        var contentTypes: [WeightedContentType]  // Changed from preferredContentTypes
        var lastUpdated: Date
        
        init(interests: [Interest] = [],
             description: String = "",
             contentTypes: [WeightedContentType] = [],  // Updated parameter
             lastUpdated: Date = Date()) {
            self.interests = interests
            self.description = description
            self.contentTypes = contentTypes
            self.lastUpdated = lastUpdated
        }
    }
    
    // MARK: - Profile Storage
    
    private func saveProfile(_ profile: UserProfile) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        
        // Update profile document
        try await db.collection("users").document(userId).setData([
            "description": profile.description,
            "lastUpdated": Timestamp(date: profile.lastUpdated)
        ], merge: true)
        
        // Update interests
        let interestsRef = db.collection("users").document(userId).collection("interests")
        let contentTypesRef = db.collection("users").document(userId).collection("contentTypes")
        
        // Get existing interests and content types
        let interestsSnapshot = try await interestsRef.getDocuments()
        let contentTypesSnapshot = try await contentTypesRef.getDocuments()
        
        let existingInterestIds = Set(interestsSnapshot.documents.map { $0.documentID })
        let existingContentTypeIds = Set(contentTypesSnapshot.documents.map { $0.documentID })
        
        // Batch write for better performance
        let batch = db.batch()
        
        // Update or create interests
        for interest in profile.interests {
            let interestRef = interestsRef.document(interest.id)
            batch.setData([
                "topic": interest.topic,
                "weight": interest.weight,
                "examples": interest.examples,
                "lastUpdated": Timestamp(date: interest.lastUpdated)
            ], forDocument: interestRef)
        }
        
        // Update or create content types
        for contentType in profile.contentTypes {
            let contentTypeRef = contentTypesRef.document(contentType.id)
            batch.setData([
                "type": contentType.type,
                "weight": contentType.weight,
                "lastUpdated": Timestamp(date: contentType.lastUpdated)
            ], forDocument: contentTypeRef)
        }
        
        // Delete interests that no longer exist
        let currentInterestIds = Set(profile.interests.map { $0.id })
        for id in existingInterestIds.subtracting(currentInterestIds) {
            batch.deleteDocument(interestsRef.document(id))
        }
        
        // Delete content types that no longer exist
        let currentContentTypeIds = Set(profile.contentTypes.map { $0.id })
        for id in existingContentTypeIds.subtracting(currentContentTypeIds) {
            batch.deleteDocument(contentTypesRef.document(id))
        }
        
        try await batch.commit()
    }
    
    private func loadProfile() async throws -> UserProfile {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw URLError(.userAuthenticationRequired)
        }
        
        let db = Firestore.firestore()
        let userDoc = try await db.collection("users").document(userId).getDocument()
        let interestsSnapshot = try await db.collection("users").document(userId).collection("interests").getDocuments()
        let contentTypesSnapshot = try await db.collection("users").document(userId).collection("contentTypes").getDocuments()
        
        let interests = interestsSnapshot.documents.compactMap { doc -> UserProfile.Interest? in
            guard let topic = doc["topic"] as? String,
                  let weight = doc["weight"] as? Double,
                  let examples = doc["examples"] as? [String],
                  let lastUpdated = (doc["lastUpdated"] as? Timestamp)?.dateValue() else {
                return nil
            }
            
            return UserProfile.Interest(
                id: doc.documentID,
                topic: topic,
                weight: weight,
                examples: examples,
                lastUpdated: lastUpdated
            )
        }
        
        let contentTypes = contentTypesSnapshot.documents.compactMap { doc -> UserProfile.WeightedContentType? in
            guard let type = doc["type"] as? String,
                  let weight = doc["weight"] as? Double,
                  let lastUpdated = (doc["lastUpdated"] as? Timestamp)?.dateValue() else {
                return nil
            }
            
            return UserProfile.WeightedContentType(
                id: doc.documentID,
                type: type,
                weight: weight,
                lastUpdated: lastUpdated
            )
        }
        
        return UserProfile(
            interests: interests,
            description: userDoc.get("description") as? String ?? "",
            contentTypes: contentTypes,
            lastUpdated: (userDoc.get("lastUpdated") as? Timestamp)?.dateValue() ?? Date()
        )
    }
    
    // MARK: - Profile Update Helpers
    
    private struct RawProfile: Codable {
        struct RawInterest: Codable {
            let topic: String
            let examples: [String]
            let weight: Double
        }
        
        let interests: [RawInterest]
        let description: String
        let contentTypes: [String]  // Changed from preferredContentTypes
        
        // Helper to convert to UserProfile
        func toUserProfile() -> UserProfile {
            let profileInterests = interests.map { raw in
                UserProfile.Interest(
                    topic: raw.topic,
                    weight: raw.weight,
                    examples: raw.examples
                )
            }
            
            let profileContentTypes = contentTypes.map { type in
                UserProfile.WeightedContentType(
                    type: type,
                    weight: 0.5  // Default weight for new content types
                )
            }
            
            return UserProfile(
                interests: profileInterests,
                description: description,
                contentTypes: profileContentTypes
            )
        }
    }
    
    private let userProfileSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "interests": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "topic": ["type": "string"],
                        "examples": ["type": "array", "items": ["type": "string"]],
                        "weight": ["type": "number"]
                    ],
                    "required": ["topic", "examples", "weight"],
                    "additionalProperties": false
                ]
            ],
            "description": ["type": "string"],
            "contentTypes": ["type": "array", "items": ["type": "string"]]  // Changed from preferredContentTypes
        ],
        "required": ["interests", "description", "contentTypes"],
        "additionalProperties": false
    ]
    
    // Helper function to update weights and prune/normalize interests
    private func updateWeights(_ profile: inout UserProfile, newTopics: Set<String>) {
        // First update weights
        for i in profile.interests.indices {
            if newTopics.contains(profile.interests[i].topic) {
                // Increase weight for interests that appear in new profile
                profile.interests[i].weight = min(1.0, profile.interests[i].weight + 0.1)
            } else {
                // Decrease weight for interests that don't appear
                profile.interests[i].weight = max(0.0, profile.interests[i].weight - 0.1)
            }
            profile.interests[i].lastUpdated = Date()
        }
        
        // Remove interests with too low weight
        profile.interests.removeAll { $0.weight <= 0.1 }
        
        // Normalize remaining weights
        let total = profile.interests.map { $0.weight }.reduce(0, +)
        if total > 0 {
            for i in profile.interests.indices {
                profile.interests[i].weight /= total
            }
        }
    }
    
    // Helper function to update weights and prune/normalize content types
    private func updateContentTypeWeights(_ profile: inout UserProfile, newTypes: Set<String>) {
        // First update weights
        for i in profile.contentTypes.indices {
            if newTypes.contains(profile.contentTypes[i].type) {
                // Increase weight for content types that appear in new profile
                profile.contentTypes[i].weight = min(1.0, profile.contentTypes[i].weight + 0.1)
            } else {
                // Decrease weight for content types that don't appear
                profile.contentTypes[i].weight = max(0.0, profile.contentTypes[i].weight - 0.1)
            }
            profile.contentTypes[i].lastUpdated = Date()
        }
        
        // Remove content types with too low weight
        profile.contentTypes.removeAll { $0.weight <= 0.1 }
        
        // Normalize remaining weights
        let total = profile.contentTypes.map { $0.weight }.reduce(0, +)
        if total > 0 {
            for i in profile.contentTypes.indices {
                profile.contentTypes[i].weight /= total
            }
        }
    }
    
    // Main update function
    func updateUserProfile(existingProfile: UserProfile, recentVideoIds: [String]) async throws -> UserProfile {
        // Stage 1: Generate new profile from recent videos
        let newProfile = try await generateNewProfile(recentVideoIds: recentVideoIds)
        
        // Convert raw interests and content types to proper ones with weights
        let newTopics = Set(newProfile.interests.map { $0.topic })
        let newTypes = Set(newProfile.contentTypes.map { $0.type })
        
        // Update weights and prune/normalize existing interests and content types
        var finalProfile = existingProfile
        updateWeights(&finalProfile, newTopics: newTopics)
        updateContentTypeWeights(&finalProfile, newTypes: newTypes)
        
        // Add new interests
        for rawInterest in newProfile.interests {
            if !finalProfile.interests.contains(where: { $0.topic == rawInterest.topic }) {
                finalProfile.interests.append(UserProfile.Interest(
                    topic: rawInterest.topic,
                    weight: 0.5,  // New interests start at 0.5
                    examples: rawInterest.examples
                ))
            }
        }
        
        // Add new content types
        for rawType in newProfile.contentTypes {
            if !finalProfile.contentTypes.contains(where: { $0.type == rawType }) {
                finalProfile.contentTypes.append(UserProfile.WeightedContentType(
                    type: rawType,
                    weight: 0.5  // New content types start at 0.5
                ))
            }
        }
        
        // Normalize again after adding new items
        let interestTotal = finalProfile.interests.map { $0.weight }.reduce(0, +)
        if interestTotal > 0 {
            for i in finalProfile.interests.indices {
                finalProfile.interests[i].weight /= interestTotal
            }
        }
        
        let contentTypeTotal = finalProfile.contentTypes.map { $0.weight }.reduce(0, +)
        if contentTypeTotal > 0 {
            for i in finalProfile.contentTypes.indices {
                finalProfile.contentTypes[i].weight /= contentTypeTotal
            }
        }
        
        // Update other profile fields
        finalProfile.description = newProfile.description
        finalProfile.lastUpdated = Date()
        
        // Save to Firestore
        try await saveProfile(finalProfile)
        
        return finalProfile
    }
    
    // MARK: - Video Prompt Fetching
    
    private struct VideoMetadata: Codable {
        let prompt: String
        let style: String
        let targetLength: Int
        let parentIds: [String]?  // Optional array of parent video IDs
    }
    
    func fetchVideoPrompts(videoIds: [String]) async throws -> [VideoMetadata] {
        let storage = Storage.storage()
        var prompts: [VideoMetadata] = []
        
        for videoId in videoIds {
            let metadataRef = storage.reference().child("videos/\(videoId)/metadata.json")
            let data = try await metadataRef.data(maxSize: 1 * 1024 * 1024) // 1MB max
            let metadata = try JSONDecoder().decode(VideoMetadata.self, from: data)
            prompts.append(metadata)
        }
        
        return prompts
    }
    
    // Update profile generation functions to use video prompts
    
    func generateInitialPrompts(userProfile: UserProfile, likedVideoPrompts: [(id: String, metadata: VideoMetadata)]) async throws -> [GeneticPrompt] {
        // For initial prompts, we want a mix of refinement of liked content and some exploration
        let numRefine = 10  // Prompts that build on what they've liked
        let numExplore = 7  // Fresh combinations of their interests
        let numRandom = 3   // Some random exploration to find unexpected interests
        
        let prompt = """
        Generate the first set of video prompts for a new user based on their initial profile and the seed videos they liked.
        Since they've already shown preferences through their liked videos, use these as strong signals while still maintaining variety.
        
        User Profile:
        Interests (sorted by weight):
        \(userProfile.interests.sorted { $0.weight > $1.weight }.map { "- \($0.topic) (weight: \($0.weight), examples: \($0.examples.joined(separator: ", ")))" }.joined(separator: "\n"))
        
        Content Type Preferences (sorted by weight):
        \(userProfile.contentTypes.sorted { $0.weight > $1.weight }.map { "- \($0.type) (weight: \($0.weight))" }.joined(separator: "\n"))
        
        Liked Seed Video Prompts:
        \(likedVideoPrompts.map { "- \($0.metadata.prompt) [ID: \($0.id), Style: \($0.metadata.style)]" }.joined(separator: "\n"))
        
        Please generate:
        
        1. \(numRefine) REFINEMENT prompts:
        - Build upon elements from the liked seed videos
        - Include the original video's ID in parentIds
        - Make variations that keep what they liked but explore new angles
        
        2. \(numExplore) EXPLORATION prompts:
        - Use ONLY the user profile information (interests and content types)
        - Focus on creating fresh combinations of their interests and preferred content types
        - Do NOT include parentIds for these
        
        3. \(numRandom) RANDOM EXPLORATION prompts:
        - Generate completely new prompts exploring topics and styles NOT in the user profile
        - These should still be high-quality and coherent, but different from their usual preferences
        - Do NOT include parentIds for these
        
        For each prompt, include:
        - A target video length (in seconds, typically between 15-60)
        - A style description (e.g., "POV", "Tutorial", "Cinematic", etc.)
        - Parent IDs where appropriate (omit for exploration/random prompts)
        """
        
        let rawProfile = try await callLLM(prompt: prompt, schema: userProfileSchema)
        return rawProfile.toUserProfile()
    }
    
    private func generateNewProfile(recentVideoIds: [String]) async throws -> UserProfile {
        // First get all video prompts
        let videoPrompts = try await fetchVideoPrompts(videoIds: recentVideoIds)
        
        // Get liked videos from the likesService instance
        let likesService = LikesService()
        let likedVideoIds = Set(likesService.likedVideos.map { $0.id })
        
        // Filter prompts to only include liked videos
        let likedPrompts = videoPrompts.enumerated().compactMap { index, metadata -> String? in
            likedVideoIds.contains(recentVideoIds[index]) ? metadata.prompt : nil
        }
        
        let prompt = """
        Based on these recent videos that the user has LIKED, generate a fresh profile of their interests.
        Since these are videos the user explicitly liked, they strongly indicate their current interests and preferences.
        Do not try to merge or consider any previous profile - just analyze these liked video prompts in isolation.
        Focus on both the topics/interests and the content style/type from each prompt.
        
        For example, a prompt like "Create a POV mountain biking video showing technical downhill trails with jumps"
        indicates both an interest (mountain biking) and content type preferences (POV, action).
        
        Recent Liked Video Prompts:
        \(likedPrompts.map { "- \($0)" }.joined(separator: "\n"))
        """
        
        let rawProfile = try await callLLM(prompt: prompt, schema: userProfileSchema)
        return rawProfile.toUserProfile()
    }
    
    // MARK: - Prompt Generation
    
    struct GeneticPrompt: Codable {
        let prompt: String
        let parentIds: [String]?  // Optional array of parent video IDs
        let targetLength: Int
        let style: String
    }
    
    private let geneticPromptsSchema: [String: Any] = [
        "type": "array",
        "items": [
            "type": "object",
            "properties": [
                "prompt": ["type": "string"],
                "parentIds": ["type": "array", "items": ["type": "string"]],
                "targetLength": ["type": "integer"],
                "style": ["type": "string"]
            ],
            "required": ["prompt", "targetLength", "style"],
            "additionalProperties": false
        ]
    ]
    
    func generateInitialPrompts(userProfile: UserProfile, likedVideoPrompts: [(id: String, metadata: VideoMetadata)]) async throws -> [GeneticPrompt] {
        // For initial prompts, we want a mix of refinement of liked content and some exploration
        let numRefine = 10  // Prompts that build on what they've liked
        let numExplore = 7  // Fresh combinations of their interests
        let numRandom = 3   // Some random exploration to find unexpected interests
        
        let prompt = """
        Generate the first set of video prompts for a new user based on their initial profile and the seed videos they liked.
        Since they've already shown preferences through their liked videos, use these as strong signals while still maintaining variety.
        
        User Profile:
        Interests (sorted by weight):
        \(userProfile.interests.sorted { $0.weight > $1.weight }.map { "- \($0.topic) (weight: \($0.weight), examples: \($0.examples.joined(separator: ", ")))" }.joined(separator: "\n"))
        
        Content Type Preferences (sorted by weight):
        \(userProfile.contentTypes.sorted { $0.weight > $1.weight }.map { "- \($0.type) (weight: \($0.weight))" }.joined(separator: "\n"))
        
        Liked Seed Video Prompts:
        \(likedVideoPrompts.map { "- \($0.metadata.prompt) [ID: \($0.id), Style: \($0.metadata.style)]" }.joined(separator: "\n"))
        
        Please generate:
        
        1. \(numRefine) REFINEMENT prompts:
        - Build upon elements from the liked seed videos
        - Include the original video's ID in parentIds
        - Make variations that keep what they liked but explore new angles
        
        2. \(numExplore) EXPLORATION prompts:
        - Use ONLY the user profile information (interests and content types)
        - Focus on creating fresh combinations of their interests and preferred content types
        - Do NOT include parentIds for these
        
        3. \(numRandom) RANDOM EXPLORATION prompts:
        - Generate completely new prompts exploring topics and styles NOT in the user profile
        - These should still be high-quality and coherent, but different from their usual preferences
        - Do NOT include parentIds for these
        
        For each prompt, include:
        - A target video length (in seconds, typically between 15-60)
        - A style description (e.g., "POV", "Tutorial", "Cinematic", etc.)
        - Parent IDs where appropriate (omit for exploration/random prompts)
        """
        
        return try await callLLM(prompt: prompt, schema: geneticPromptsSchema)
    }
    
    func generateNextPrompts(userProfile: UserProfile, likedVideoPrompts: [(id: String, metadata: VideoMetadata)]) async throws -> [GeneticPrompt] {
        // First, fetch all lineages to understand our prompt history
        let lineages = try await PromptLineageService.shared.fetchAllLineages()
        
        // Group prompts by their status
        let successfulRoots = likedVideoPrompts.map { $0.id }
        let activeLineages = lineages.filter { lineage in
            successfulRoots.contains(lineage.rootId) && lineage.shouldTryAgain
        }
        let abandonedLineages = lineages.filter { $0.shouldAbandon }
        
        // Calculate how many prompts of each type to generate
        let numLikedPrompts = likedVideoPrompts.count
        let numActiveLineages = activeLineages.count
        
        // Adjust ratios based on active lineages
        let (numExplore, numRandom, numCrossover, numMutate) = if numLikedPrompts < 3 {
            // Very few liked prompts - focus on exploration
            (10, 5, 0, 5)  // No crossover since we need at least 2 prompts for that
        } else if numLikedPrompts < 5 {
            // Few liked prompts - limited crossover
            (5, 5, 3, 7)
        } else {
            // Normal case - full genetic algorithm
            (3, 2, 5, 10)
        }
        
        // Build the prompt with lineage information
        let prompt = """
        Generate new video prompts using genetic algorithm principles, considering the user's profile, successful prompts, and previous attempts.
        
        User Profile:
        Interests (sorted by weight):
        \(userProfile.interests.sorted { $0.weight > $1.weight }.map { "- \($0.topic) (weight: \($0.weight), examples: \($0.examples.joined(separator: ", ")))" }.joined(separator: "\n"))
        
        Content Type Preferences (sorted by weight):
        \(userProfile.contentTypes.sorted { $0.weight > $1.weight }.map { "- \($0.type) (weight: \($0.weight))" }.joined(separator: "\n"))
        
        Successful Past Prompts and Their Attempts:
        \(activeLineages.map { lineage in
            let rootPrompt = likedVideoPrompts.first { $0.id == lineage.rootId }?.metadata.prompt ?? ""
            let failedAttempts = lineage.failedAttempts.map { "  - Failed Attempt: \($0.prompt)" }.joined(separator: "\n")
            return """
            Original [ID: \(lineage.rootId)]: \(rootPrompt)
            Failed Attempts:
            \(failedAttempts)
            """
        }.joined(separator: "\n\n"))
        
        Abandoned Prompts (do not use these approaches):
        \(abandonedLineages.map { lineage in
            let attempts = lineage.attempts.map { "  - \($0.prompt)" }.joined(separator: "\n")
            return """
            Root [ID: \(lineage.rootId)]:
            \(attempts)
            """
        }.joined(separator: "\n\n"))
        
        Please generate:
        
        1. \(numExplore) EXPLORATION prompts:
        - Use ONLY the user profile information (interests and content types)
        - Do NOT reference the successful prompts
        - Focus on creating fresh combinations of their interests and preferred content types
        
        2. \(numRandom) RANDOM EXPLORATION prompts:
        - Generate completely new prompts exploring topics and styles NOT in the user profile
        - These should still be high-quality and coherent, but different from their usual preferences
        - Do NOT include parentIds for these
        
        3. \(numCrossover) CROSSOVER prompts:
        - Combine elements from TWO successful prompts to create something new
        - Include BOTH parent IDs in the parentIds array
        - Avoid combinations that were already tried and failed
        
        4. \(numMutate) MUTATION prompts:
        - For prompts with failed attempts, try completely different angles
        - For prompts without failed attempts, make smaller variations
        - Include the original prompt's ID in parentIds
        - IMPORTANT: Look at failed attempts for each prompt and avoid similar approaches
        
        For each prompt, include:
        - A target video length (in seconds, typically between 15-60)
        - A style description (e.g., "POV", "Tutorial", "Cinematic", etc.)
        - Parent IDs where appropriate (omit for exploration/random prompts)
        
        When mutating or crossing over:
        - If a prompt has failed attempts, use very different approaches
        - Study the failed attempts to understand what didn't work
        - Never generate something too similar to a failed attempt
        """
        
        let prompts = try await callLLM(prompt: prompt, schema: geneticPromptsSchema)
        
        // Record all new attempts in the lineage service
        for prompt in prompts {
            if let parentIds = prompt.parentIds {
                // For mutations (single parent) or crossovers (two parents)
                for parentId in parentIds {
                    try await PromptLineageService.shared.recordAttempt(
                        videoId: UUID().uuidString, // This will be replaced with actual video ID
                        prompt: prompt.prompt,
                        parentId: parentId,
                        style: prompt.style,
                        targetLength: prompt.targetLength
                    )
                }
            }
        }
        
        return prompts
    }
    
    // MARK: - Profile Update Helpers
    
    private struct SemanticMatches: Codable {
        struct InterestMatch: Codable {
            let existingTopic: String
            let newTopic: String
            let mergedExamples: [String]  // LLM will merge examples semantically
        }
        struct ContentTypeMatch: Codable {
            let existingType: String
            let newType: String
        }
        let interestMatches: [InterestMatch]
        let contentTypeMatches: [ContentTypeMatch]
    }
    
    private struct DescriptionUpdate: Codable {
        let updatedDescription: String
        let reasoning: String
    }
    
    private let semanticMatchesSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "interestMatches": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "existingTopic": ["type": "string"],
                        "newTopic": ["type": "string"],
                        "mergedExamples": ["type": "array", "items": ["type": "string"]]
                    ],
                    "required": ["existingTopic", "newTopic", "mergedExamples"],
                    "additionalProperties": false
                ]
            ],
            "contentTypeMatches": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "existingType": ["type": "string"],
                        "newType": ["type": "string"]
                    ],
                    "required": ["existingType", "newType"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["interestMatches", "contentTypeMatches"],
        "additionalProperties": false
    ]
    
    private let descriptionUpdateSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "updatedDescription": ["type": "string"],
            "reasoning": ["type": "string"]
        ],
        "required": ["updatedDescription", "reasoning"],
        "additionalProperties": false
    ]
    
    // Helper function to do basic string matching on examples
    private func findBasicExampleMatches(_ examples1: [String], _ examples2: [String]) -> [String] {
        // First normalize all examples to lowercase for comparison
        let normalized1 = examples1.map { $0.lowercased() }
        let normalized2 = examples2.map { $0.lowercased() }
        
        // Create a set of unique examples, preferring the original casing from examples1
        var uniqueExamples = Set<String>()
        
        // Add examples from first set
        for (i, normalized) in normalized1.enumerated() {
            uniqueExamples.insert(examples1[i])
        }
        
        // Add non-duplicate examples from second set
        for (i, normalized) in normalized2.enumerated() {
            if !normalized1.contains(normalized) {
                uniqueExamples.insert(examples2[i])
            }
        }
        
        return Array(uniqueExamples)
    }
    
    // Stage 1: Generate new profile from recent videos
    private func generateNewProfile(recentVideoIds: [String]) async throws -> RawProfile {
        let prompt = """
        Based on these recent video generation prompts the user has watched, generate a fresh profile of their interests.
        Do not try to merge or consider any previous profile - just analyze these prompts in isolation.
        Focus on both the topics/interests and the content style/type from each prompt.
        
        For example, a prompt like "Create a POV mountain biking video showing technical downhill trails with jumps"
        indicates both an interest (mountain biking) and content type preferences (POV, action).
        
        Recent Video Prompts:
        \(recentVideoIds.map { "- \($0)" }.joined(separator: "\n"))
        """
        
        return try await callLLM(prompt: prompt, schema: userProfileSchema)
    }
    
    // Stage 2: Basic string matching and merging
    private func mergeProfiles(_ existing: UserProfile, _ new: RawProfile) -> (merged: UserProfile, unmergedExisting: RawProfile, unmergedNew: RawProfile) {
        var mergedInterests: [UserProfile.Interest] = []
        var unmergedExistingInterests: [UserProfile.Interest] = []
        var unmergedNewInterests: [UserProfile.Interest] = []
        
        // Track which interests have been merged
        var mergedExistingIndices = Set<Int>()
        var mergedNewIndices = Set<Int>()
        
        // First pass: exact string matches
        for (i, existingInterest) in existing.interests.enumerated() {
            for (j, newInterest) in new.interests.enumerated() {
                if existingInterest.topic == newInterest.topic {
                    let mergedExamples = findBasicExampleMatches(existingInterest.examples, newInterest.examples)
                    let mergedInterest = UserProfile.Interest(
                        topic: existingInterest.topic,
                        weight: (existingInterest.weight + newInterest.weight) / 2,
                        examples: mergedExamples
                    )
                    mergedInterests.append(mergedInterest)
                    mergedExistingIndices.insert(i)
                    mergedNewIndices.insert(j)
                }
            }
        }
        
        // Collect unmerged interests
        for (i, interest) in existing.interests.enumerated() {
            if !mergedExistingIndices.contains(i) {
                unmergedExistingInterests.append(interest)
            }
        }
        
        for (i, interest) in new.interests.enumerated() {
            if !mergedNewIndices.contains(i) {
                unmergedNewInterests.append(interest)
            }
        }
        
        // Similar process for content types
        let mergedContentTypes = Array(Set(existing.contentTypes).intersection(Set(new.contentTypes)))
        let unmergedExistingTypes = Array(Set(existing.contentTypes).subtracting(Set(mergedContentTypes)))
        let unmergedNewTypes = Array(Set(new.contentTypes).subtracting(Set(mergedContentTypes)))
        
        return (
            UserProfile(
                interests: mergedInterests,
                description: "", // Will be updated later
                contentTypes: mergedContentTypes
            ),
            RawProfile(
                interests: unmergedExistingInterests,
                description: existing.description,
                contentTypes: unmergedExistingTypes
            ),
            RawProfile(
                interests: unmergedNewInterests,
                description: new.description,
                contentTypes: unmergedNewTypes
            )
        )
    }
    
    // Stage 3: Find semantic matches
    private func findSemanticMatches(existing: RawProfile, new: RawProfile) async throws -> SemanticMatches {
        let prompt = """
        Analyze these two sets of interests and content types to identify any that are semantically the same but weren't caught by exact string matching.
        Only identify truly equivalent items - DO NOT force matches if there aren't any.
        
        IMPORTANT: If you find NO semantic matches, you MUST return:
        {
            "interestMatches": [],
            "contentTypeMatches": []
        }
        
        When you DO find matches:
        - For interests: merge their examples, removing duplicates and near-duplicates
        - For content types: only match if they truly represent the same type of content
        - Combine examples that represent the same concept even if worded differently

        Examples of valid semantic matches:
        1. Interest match:
           - Topic "Mountain Biking" with examples ["downhill trails", "mountain bike jumps"]
           - Topic "MTB" with examples ["downhill racing", "trail jumping", "mountain bike jumps"]
           These should be merged as they refer to the same activity, with examples combined and deduplicated.

        2. Content type match:
           - "POV Action" and "First Person" are the same type of content
           - "Tutorial" and "How-To" are the same type of content

        Examples of what NOT to match:
        1. Interest match:
           - Topic "Skiing" with examples ["powder skiing", "ski jumps"]
           - Topic "Snowboarding" with examples ["powder riding", "snowboard tricks"]
           Although related, these are distinct activities and should NOT be merged.

        2. Content type match:
           - "Tutorial" and "Demonstration" - while similar, they serve different purposes
           - "POV" and "Third Person" - these are opposites and should not be matched

        Your task - analyze these interests and content types:

        Existing Profile Interests:
        \(existing.interests.map { "- \($0.topic) (examples: \($0.examples.joined(separator: ", ")))" }.joined(separator: "\n"))
        
        New Profile Interests:
        \(new.interests.map { "- \($0.topic) (examples: \($0.examples.joined(separator: ", ")))" }.joined(separator: "\n"))
        
        Existing Content Types:
        \(existing.contentTypes.joined(separator: ", "))
        
        New Content Types:
        \(new.contentTypes.joined(separator: ", "))
        """
        
        return try await callLLM(prompt: prompt, schema: semanticMatchesSchema)
    }
    
    // Stage 6: Generate final description
    private func generateFinalDescription(profile: UserProfile, existingDescription: String, newDescription: String) async throws -> DescriptionUpdate {
        let prompt = """
        Create an updated profile description that combines insights from both the existing and new descriptions,
        while accurately reflecting the current set of interests and content types.
        
        Current Interests:
        \(profile.interests.map { "- \($0.topic) (weight: \($0.weight), examples: \($0.examples.joined(separator: ", ")))" }.joined(separator: "\n"))
        
        Current Content Types:
        \(profile.contentTypes.map { "- \($0.type) (weight: \($0.weight))" }.joined(separator: "\n"))
        
        Existing Description:
        \(existingDescription)
        
        New Description:
        \(newDescription)
        """
        
        return try await callLLM(prompt: prompt, schema: descriptionUpdateSchema)
    }
    
    func generateGeneticPrompts(userProfile: UserProfile, likedVideoPrompts: [(id: String, metadata: VideoMetadata)]) async throws -> [GeneticPrompt] {
        // Calculate how many prompts of each type to generate based on number of liked prompts
        let numLikedPrompts = likedVideoPrompts.count
        let (numExplore, numRandom, numCrossover, numMutate) = if numLikedPrompts < 3 {
            // Very few liked prompts - focus on exploration
            (10, 5, 0, 5)  // No crossover since we need at least 2 prompts for that
        } else if numLikedPrompts < 5 {
            // Few liked prompts - limited crossover
            (5, 5, 3, 7)
        } else {
            // Normal case - full genetic algorithm
            (3, 2, 5, 10)
        }
        
        let prompt = """
        Generate new video prompts using genetic algorithm principles, considering both the user's profile and successful past prompts.
        The prompts should maintain high quality and coherence while exploring variations and new combinations.
        
        User Profile:
        Interests (sorted by weight):
        \(userProfile.interests.sorted { $0.weight > $1.weight }.map { "- \($0.topic) (weight: \($0.weight), examples: \($0.examples.joined(separator: ", ")))" }.joined(separator: "\n"))
        
        Content Type Preferences (sorted by weight):
        \(userProfile.contentTypes.sorted { $0.weight > $1.weight }.map { "- \($0.type) (weight: \($0.weight))" }.joined(separator: "\n"))
        
        Successful Past Prompts:
        \(likedVideoPrompts.map { "- \($0.metadata.prompt) [ID: \($0.id)]" }.joined(separator: "\n"))
        
        Please generate:
        
        1. \(numExplore) EXPLORATION prompts:
        - Use ONLY the user profile information (interests and content types)
        - Do NOT reference the successful prompts
        - Focus on creating fresh combinations of their interests and preferred content types
        
        2. \(numRandom) RANDOM EXPLORATION prompts:
        - Generate completely new prompts exploring topics and styles NOT in the user profile
        - These should still be high-quality and coherent, but different from their usual preferences
        - Do NOT include parentIds for these
        
        3. \(numCrossover) CROSSOVER prompts:
        - Combine elements from TWO successful prompts to create something new
        - Include BOTH parent IDs in the parentIds array
        - Example format (fill in your own examples):
        [Space for crossover examples]
        
        4. \(numMutate) MUTATION prompts:
        - Take ONE successful prompt and make a small modification
        - Changes can include: setting, time of day, camera angle, style, difficulty level, etc.
        - Include the original prompt's ID in parentIds
        - Example format (fill in your own examples):
        [Space for mutation examples]
        
        Note: If a prompt doesn't have parent IDs (exploration/random), omit the parentIds field entirely.
        """
        
        return try await callLLM(prompt: prompt, schema: geneticPromptsSchema)
    }
} 