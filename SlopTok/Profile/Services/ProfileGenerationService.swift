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
        return await LLMService.shared.complete(
            userPrompt: prompt,
            systemPrompt: "You are analyzing image generation prompts to understand a user's visual interests and content preferences. Focus on the subjects, styles, and themes they engage with in visual content. You MUST output valid JSON matching the required schema.",
            responseType: ProfileGenerationResponse.self,
            schema: ProfileGenerationSchema.schema
        )
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