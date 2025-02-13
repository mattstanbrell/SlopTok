import Foundation
import FirebaseVertexAI
import UIKit

/// Service responsible for generating user profiles using LLM
actor ProfileGenerationService {
    /// Shared instance
    static let shared = ProfileGenerationService()
    
    private let vertex: VertexAI
    private let model: GenerativeModel
    
    private init() {
        self.vertex = VertexAI.vertexAI()
        self.model = vertex.generativeModel(
            modelName: "gemini-2.0-flash",
            generationConfig: GenerationConfig(
                responseMIMEType: "application/json",
                responseSchema: ProfileGenerationGeminiSchema.schema
            )
        )
    }
    
    /// Generates initial profile from seed video interactions
    /// - Parameter likedVideos: Array of prompts from videos the user liked from the seed set
    /// - Returns: Generated profile or error
    func generateInitialProfile(likedVideos: [(id: String, prompt: String)]) async -> LLMResponse<ProfileGenerationResponse> {
        // Format video prompts for readability
        let formattedPrompts = likedVideos.enumerated().map { index, video in
            "Image \(index + 1) Prompt: \(video.prompt)"
        }.joined(separator: "\n")
        
        // Load thumbnails for liked videos
        var thumbnailImages: [(label: String, image: UIImage?)] = []
        
        // Get thumbnails for all videos
        for (index, video) in likedVideos.enumerated() {
            if let image = await VideoService.shared.getUIImageThumbnail(for: video.id) {
                thumbnailImages.append(("Image \(index + 1)", image))
            }
        }
        
        // Filter out any nil images and prepare for analysis
        let validImages = thumbnailImages.compactMap { label, image -> (label: String, image: UIImage)? in
            if let image = image {
                return (label: label, image: image)
            }
            return nil
        }
        
        // Build the parts array with prompts and images
        var parts: [PartsRepresentable] = []
        for (index, image) in validImages.enumerated() {
            parts.append("Image \(index + 1) Prompt:" as PartsRepresentable)
            parts.append(likedVideos[index].prompt as PartsRepresentable)
            parts.append(image.image as PartsRepresentable)
        }
        
        // Build the prompt
        let prompt = """
        Analyze these AI-generated images and their generation prompts. Each pair shows an image the user liked and the prompt used to create it.

        Based on the visual content and themes in these liked images, suggest possible interests and patterns, while acknowledging the limited data.
        For each interest:
        - Suggest a specific topic that matches the visual content they've engaged with
        - List at least 3 examples seen in the images and prompts, such as:
          * Specific subjects shown
          * Visual styles and techniques
          * Props and objects featured
          * Settings and environments

        Example response:
        {
          "interests": [
            {
              "topic": "Nature Photography",
              "examples": [
                "macro flower details",
                "soft natural lighting",
                "botanical compositions"
              ]
            },
            {
              "topic": "Architectural Photography",
              "examples": [
                "geometric patterns",
                "dramatic building angles",
                "minimalist structures"
              ]
            }
          ],
          "description": "Based on this limited initial set of interactions, the user appears to show interest in detailed nature photography, particularly images that capture intricate botanical details. They've also engaged with architectural content, suggesting a possible appreciation for geometric forms and structural compositions. As more data becomes available, these preferences may evolve or reveal different patterns."
        }

        You MUST identify at least one interest and provide at least 3 examples for each interest.
        Make the description focus on their visual preferences and what kind of content they've engaged with so far, while acknowledging the preliminary nature of these observations.
        Risqué content (eg cleavage, tight clothing, etc) is ok to include if the user's interests align with it, but avoid describing actual nudity.
        """
        
        // Call Gemini with retry logic
        let maxRetries = 2
        var lastError: LLMError?
        
        for attempt in 0...maxRetries {
            do {
                if attempt > 0 {
                    print("🔄 Retry attempt \(attempt) for initial profile generation")
                    // Add exponential backoff delay
                    try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * Double(attempt)))
                }
                
                let response = try await model.generateContent(parts + [prompt as PartsRepresentable])
                
                if let text = response.text,
                   let data = text.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(ProfileGenerationResponse.self, from: data) {
                    return .success(decoded, rawContent: text)
                } else {
                    return .failure(.apiError("Invalid response format"))
                }
            } catch {
                lastError = .systemError(error)
                if attempt == maxRetries {
                    print("❌ All retry attempts failed for initial profile generation")
                    return .failure(.systemError(error))
                }
            }
        }
        
        return .failure(lastError ?? .systemError(NSError(domain: "ProfileGenerationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error during profile generation"])))
    }
    
    /// Response for semantic interest matching
    private struct SemanticMatchResponse: Codable {
        struct Match: Codable {
            let oldTopic: String
            let newTopic: String
            let canonicalTopic: String
        }
        let matches: [Match]
    }
    
    /// Schema for semantic matching
    private let semanticMatchSchema = """
    {
        "type": "object",
        "properties": {
            "matches": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "oldTopic": {
                            "type": "string",
                            "description": "Topic from the existing profile"
                        },
                        "newTopic": {
                            "type": "string",
                            "description": "Semantically matching topic from the new profile"
                        },
                        "canonicalTopic": {
                            "type": "string",
                            "description": "The best, most clear and complete name for this topic"
                        }
                    },
                    "required": ["oldTopic", "newTopic", "canonicalTopic"]
                }
            }
        },
        "required": ["matches"]
    }
    """
    
    /// Response for description generation
    private struct DescriptionResponse: Codable {
        let description: String
    }
    
    /// Generates updated profile based on recent interactions
    /// - Parameter likedVideos: Array of prompts from videos the user liked since last update
    /// - Returns: Generated profile or error
    func generateUpdatedProfile(likedVideos: [(id: String, prompt: String)]) async -> LLMResponse<ProfileGenerationResponse> {
        // Format video prompts for readability
        let formattedPrompts = likedVideos.enumerated().map { index, video in
            "Image \(index + 1) Prompt: \(video.prompt)"
        }.joined(separator: "\n")
        
        // Load thumbnails for liked videos
        var thumbnailImages: [(label: String, image: UIImage?)] = []
        
        // Get thumbnails for all videos
        for (index, video) in likedVideos.enumerated() {
            if let image = await VideoService.shared.getUIImageThumbnail(for: video.id) {
                thumbnailImages.append(("Image \(index + 1)", image))
            }
        }
        
        // Filter out any nil images and prepare for analysis
        let validImages = thumbnailImages.compactMap { label, image -> (label: String, image: UIImage)? in
            if let image = image {
                return (label: label, image: image)
            }
            return nil
        }
        
        // Build the parts array with prompts and images
        var parts: [PartsRepresentable] = []
        for (index, image) in validImages.enumerated() {
            parts.append("Image \(index + 1) Prompt:" as PartsRepresentable)
            parts.append(likedVideos[index].prompt as PartsRepresentable)
            parts.append(image.image as PartsRepresentable)
        }
        
        // Build the prompt
        let prompt = """
        Analyze these AI-generated images and their generation prompts. Each pair shows an image the user liked and the prompt used to create it.

        Based on the visual content and themes in these liked images, identify interests and patterns.
        For each interest:
        - Choose a specific, well-defined topic that matches the visual content they engage with
        - List at least 3 examples seen in the images and prompts, such as:
          * Specific subjects shown
          * Visual styles and techniques
          * Props and objects featured
          * Settings and environments

        Example response:
        {
          "interests": [
            {
              "topic": "Portrait Photography",
              "examples": [
                "dramatic side lighting",
                "urban backdrops",
                "candid expressions"
              ]
            },
            {
              "topic": "Street Fashion",
              "examples": [
                "high contrast aesthetics",
                "urban streetwear styling",
                "dynamic poses"
              ]
            }
          ],
          "description": "The user shows a strong interest in portrait and fashion photography with an urban edge. Their preferences lean towards dramatic lighting and contemporary styling, particularly in city environments. The images they engage with often feature a blend of candid moments and styled compositions."
        }

        You MUST identify at least one interest and provide at least 3 examples for each interest.
        Make the description focus on their visual preferences and what kind of content they've engaged with.
        Risqué content (eg cleavage, tight clothing, etc) is ok to include if the user's interests align with it, but avoid describing actual nudity.
        """
        
        // Call Gemini with retry logic
        let maxRetries = 2
        var lastError: LLMError?
        
        for attempt in 0...maxRetries {
            do {
                if attempt > 0 {
                    print("🔄 Retry attempt \(attempt) for profile update")
                    // Add exponential backoff delay
                    try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * Double(attempt)))
                }
                
                let response = try await model.generateContent(parts + [prompt as PartsRepresentable])
                
                if let text = response.text,
                   let data = text.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(ProfileGenerationResponse.self, from: data) {
                    // If we have a current profile, merge the interests
                    if let currentProfile = await ProfileService.shared.currentProfile {
                        return await mergeProfiles(newResponse: decoded, currentProfile: currentProfile)
                    }
                    return .success(decoded, rawContent: text)
                } else {
                    return .failure(.apiError("Invalid response format"))
                }
            } catch {
                lastError = .systemError(error)
                if attempt == maxRetries {
                    print("❌ All retry attempts failed for profile update")
                    return .failure(.systemError(error))
                }
            }
        }
        
        return .failure(lastError ?? .systemError(NSError(domain: "ProfileGenerationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error during profile update"])))
    }
    
    /// Merges new interests with existing profile, handling semantic matches and weight updates
    private func mergeProfiles(newResponse: ProfileGenerationResponse, currentProfile: UserProfile) async -> LLMResponse<ProfileGenerationResponse> {
        var mergedInterests: [Interest] = []
        var unmatchedNewInterests = newResponse.interests
        var unmatchedOldInterests = currentProfile.interests
        
        // 1. First handle exact string matches
        for newInterest in newResponse.interests {
            if let matchIndex = unmatchedOldInterests.firstIndex(where: { $0.topic == newInterest.topic }) {
                let oldInterest = unmatchedOldInterests[matchIndex]
                
                // Create new interest with merged data
                var mergedInterest = Interest(
                    topic: oldInterest.topic,  // Keep existing topic name for exact matches
                    examples: Array(Set(oldInterest.examples + newInterest.examples))
                )
                
                // Update weight and timestamp
                mergedInterest.weight = min(1.0, oldInterest.weight + 0.1)
                mergedInterest.lastUpdated = Date()
                
                mergedInterests.append(mergedInterest)
                unmatchedOldInterests.remove(at: matchIndex)
                if let newIndex = unmatchedNewInterests.firstIndex(where: { $0.topic == newInterest.topic }) {
                    unmatchedNewInterests.remove(at: newIndex)
                }
            }
        }
        
        // 2. Then use LLM for semantic matching of remaining interests
        if !unmatchedOldInterests.isEmpty && !unmatchedNewInterests.isEmpty {
            let oldInterestsFormatted = unmatchedOldInterests
                .map { "- \($0.topic)" }
                .joined(separator: "\n")
            
            let newInterestsFormatted = unmatchedNewInterests
                .map { "- \($0.topic)" }
                .joined(separator: "\n")
            
            let semanticPrompt = """
            Identify any semantically matching topics between these two lists of interests.
            Only match topics that mean the same thing but are written differently (e.g., "Mountain Biking" and "MTB").
            Do not match topics that are merely related or similar.
            For each match, provide the best, most clear and complete name for the topic.
            
            Existing interests:
            \(oldInterestsFormatted)
            
            New interests:
            \(newInterestsFormatted)
            
            Example response:
            {
                "matches": [
                    {
                        "oldTopic": "Mountain Biking",
                        "newTopic": "MTB",
                        "canonicalTopic": "Mountain Biking"
                    },
                    {
                        "oldTopic": "Portrait Photos",
                        "newTopic": "Portrait Photography",
                        "canonicalTopic": "Portrait Photography"
                    }
                ]
            }
            
            If there are no semantic matches, return an empty matches array.
            When choosing the canonical topic name:
            - Use the most complete, clear, and professional version
            - Avoid abbreviations unless they're more commonly used
            - Keep consistent with existing naming patterns
            - Ensure it's descriptive and unambiguous
            """
            
            let semanticResult = await LLMService.shared.complete(
                userPrompt: semanticPrompt,
                systemPrompt: "You are identifying semantically equivalent topics that are written differently. Only match topics that mean exactly the same thing.",
                responseType: SemanticMatchResponse.self,
                schema: semanticMatchSchema
            )
            
            if case let .success((semanticResponse, _)) = semanticResult {
                // Process semantic matches
                for match in semanticResponse.matches {
                    if let oldIndex = unmatchedOldInterests.firstIndex(where: { $0.topic == match.oldTopic }),
                       let newIndex = unmatchedNewInterests.firstIndex(where: { $0.topic == match.newTopic }) {
                        let oldInterest = unmatchedOldInterests[oldIndex]
                        let newInterest = unmatchedNewInterests[newIndex]
                        
                        // Create new interest with canonical topic name and merged data
                        var mergedInterest = Interest(
                            topic: match.canonicalTopic,  // Use canonical name
                            examples: Array(Set(oldInterest.examples + newInterest.examples))
                        )
                        
                        // Update weight and timestamp
                        mergedInterest.weight = min(1.0, oldInterest.weight + 0.1)
                        mergedInterest.lastUpdated = Date()
                        
                        mergedInterests.append(mergedInterest)
                        unmatchedOldInterests.remove(at: oldIndex)
                        unmatchedNewInterests.remove(at: newIndex)
                    }
                }
            }
        }
        
        // 3. Handle remaining unmatched interests
        
        // Decrease weight of unmatched old interests
        for oldInterest in unmatchedOldInterests {
            // Create new interest with decreased weight
            var updatedInterest = Interest(
                topic: oldInterest.topic,
                examples: oldInterest.examples
            )
            updatedInterest.weight = max(0.0, oldInterest.weight - 0.1)
            updatedInterest.lastUpdated = Date()
            
            if updatedInterest.weight > 0 {
                mergedInterests.append(updatedInterest)
            }
        }
        
        // Add new interests with initial weight
        for newInterest in unmatchedNewInterests {
            let interest = Interest(topic: newInterest.topic, examples: newInterest.examples)
            mergedInterests.append(interest)
        }
        
        // 4. Generate updated description
        let descriptionPrompt = """
        Given this merged profile and the previous and new descriptions, create an updated description that reflects the user's current interests and how they've evolved.
        
        Previous description:
        \(currentProfile.description)
        
        New description from recent interactions:
        \(newResponse.description)
        
        Current interests:
        \(mergedInterests.map { "- \($0.topic) (weight: \($0.weight))" }.joined(separator: "\n"))
        
        Create a natural description that:
        1. Focuses on their strongest interests (higher weights)
        2. Notes any significant changes or trends
        3. Highlights what aspects of these topics they engage with
        """
        
        let descriptionResult = await LLMService.shared.complete(
            userPrompt: descriptionPrompt,
            systemPrompt: "You are writing a natural description of a user's visual preferences and interests, focusing on their strongest interests and how they've evolved.",
            responseType: DescriptionResponse.self,
            schema: """
            {
                "type": "object",
                "properties": {
                    "description": {
                        "type": "string",
                        "description": "Natural language description of the user's interests"
                    }
                },
                "required": ["description"],
                "additionalProperties": false
            }
            """
        )
        
        let updatedDescription: String
        switch descriptionResult {
        case let .success((response, rawContent)):
            print("✅ Generated merged description:")
            print(rawContent)
            updatedDescription = response.description
        case let .failure(error):
            print("❌ Failed to generate merged description: \(error.description)")
            // If LLM fails, do a basic merge of the descriptions
            updatedDescription = """
                \(newResponse.description)
                
                This builds upon their previous interests: \(currentProfile.description)
                """
        }
        
        // Create merged response
        let mergedResponse = ProfileGenerationResponse(
            interests: mergedInterests.map { interest in
                InterestGeneration(topic: interest.topic, examples: interest.examples)
            },
            description: updatedDescription
        )
        
        return .success(mergedResponse, rawContent: "")
    }
    
    /// Converts LLM-generated interests into domain model interests
    /// - Parameter response: The LLM generation response
    /// - Returns: Array of Interest models
    func convertToInterests(_ response: ProfileGenerationResponse) async -> [Interest] {
        // Filter interests to ensure each has at least 3 non-empty examples
        let validInterests = response.interests.filter { interest in
            let nonEmptyExamples = interest.examples.filter { !$0.isEmpty }
            return nonEmptyExamples.count >= 3
        }
        
        // Ensure we have at least one valid interest
        guard !validInterests.isEmpty else {
            print("❌ No valid interests found with at least 3 examples")
            return []
        }
        
        return validInterests.map { generation in
            Interest(
                topic: generation.topic,
                examples: generation.examples.filter { !$0.isEmpty }
            )
        }
    }
} 