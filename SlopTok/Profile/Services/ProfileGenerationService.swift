import Foundation

/// Service responsible for generating user profiles using LLM
actor ProfileGenerationService {
    /// Shared instance
    static let shared = ProfileGenerationService()
    
    private init() {}
    
    /// Generates initial profile from seed video interactions
    /// - Parameter likedVideos: Array of prompts from videos the user liked from the seed set
    /// - Returns: Generated profile or error
    func generateInitialProfile(likedVideos: [(id: String, prompt: String)]) async -> LLMResponse<ProfileGenerationResponse> {
        // Format video prompts for readability
        let formattedVideos = likedVideos
            .map { "- \($0.prompt)" }
            .joined(separator: "\n")
        
        // Build the prompt
        let prompt = """
        Analyze these AI image generation prompts from images the user liked. Each prompt describes the visual content of an image they enjoyed:
        \(formattedVideos)

        Based on the visual themes and subjects in these liked images, suggest possible interests and patterns, while acknowledging the limited data.
        For each potential interest:
        - Suggest a specific topic that might match the visual content they've engaged with
        - List at least 3 examples seen in the prompts, such as:
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
        
        // Call LLM
        return await LLMService.shared.complete(
            userPrompt: prompt,
            systemPrompt: "You are analyzing image generation prompts to understand a user's visual interests and content preferences. Focus on the subjects, styles, and themes they engage with in visual content. You MUST output valid JSON matching the required schema.",
            responseType: ProfileGenerationResponse.self,
            schema: ProfileGenerationSchema.schema
        )
    }
    
    /// Response for semantic interest matching
    private struct SemanticMatchResponse: Codable {
        struct Match: Codable {
            let oldTopic: String
            let newTopic: String
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
                        }
                    },
                    "required": ["oldTopic", "newTopic"]
                }
            }
        },
        "required": ["matches"]
    }
    """
    
    /// Generates updated profile based on recent interactions
    /// - Parameter likedVideos: Array of prompts from images the user liked since last update
    /// - Returns: Generated profile or error
    func generateUpdatedProfile(likedVideos: [(id: String, prompt: String)]) async -> LLMResponse<ProfileGenerationResponse> {
        // Format video prompts for readability
        let formattedVideos = likedVideos
            .map { "- \($0.prompt)" }
            .joined(separator: "\n")
        
        // Build the prompt
        let prompt = """
        Analyze these AI image generation prompts from images the user liked. Each prompt describes the visual content of an image they enjoyed:
        \(formattedVideos)

        Based on the visual themes and subjects in these liked images, identify interests and patterns.
        For each interest:
        - Choose a specific, well-defined topic that matches the visual content they engage with
        - List at least 3 examples seen in the prompts, such as:
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
          "description": "Based on these interactions, the user shows a strong interest in detailed nature photography, particularly images that capture intricate botanical details. They've also engaged with architectural content, suggesting an appreciation for geometric forms and structural compositions."
        }

        You MUST identify at least one interest and provide at least 3 examples for each interest.
        Make the description focus on their visual preferences and what kind of content they've engaged with.
        Risqué content (eg cleavage, tight clothing, etc) is ok to include if the user's interests align with it, but avoid describing actual nudity.
        """
        
        // Call LLM
        let result = await LLMService.shared.complete(
            userPrompt: prompt,
            systemPrompt: "You are analyzing image generation prompts to understand a user's visual interests and content preferences. Focus on the subjects, styles, and themes they engage with in visual content. You MUST output valid JSON matching the required schema.",
            responseType: ProfileGenerationResponse.self,
            schema: ProfileGenerationSchema.schema
        )
        
        // If we have a current profile, merge the interests
        if case let .success((response, _)) = result,
           let currentProfile = await ProfileService.shared.currentProfile {
            return await mergeProfiles(newResponse: response, currentProfile: currentProfile)
        }
        
        return result
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
                
                // Merge examples and increase weight
                var mergedInterest = oldInterest
                mergedInterest.examples = Array(Set(oldInterest.examples + newInterest.examples))
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
            
            Existing interests:
            \(oldInterestsFormatted)
            
            New interests:
            \(newInterestsFormatted)
            
            Example response:
            {
                "matches": [
                    {
                        "oldTopic": "Mountain Biking",
                        "newTopic": "MTB"
                    }
                ]
            }
            
            If there are no semantic matches, return an empty matches array.
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
                        
                        // Merge examples and increase weight
                        var mergedInterest = oldInterest
                        mergedInterest.examples = Array(Set(oldInterest.examples + newInterest.examples))
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
        for var oldInterest in unmatchedOldInterests {
            oldInterest.weight = max(0.0, oldInterest.weight - 0.1)
            oldInterest.lastUpdated = Date()
            if oldInterest.weight > 0 {
                mergedInterests.append(oldInterest)
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
            responseType: String.self,
            schema: """
            {
                "type": "string",
                "description": "Natural language description of the user's interests"
            }
            """
        )
        
        let updatedDescription = if case let .success((description, _)) = descriptionResult {
            description
        } else {
            newResponse.description
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