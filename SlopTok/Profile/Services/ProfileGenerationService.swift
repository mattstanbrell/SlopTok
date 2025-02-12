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
        Analyze these AI video generation prompts from videos the user liked. Each prompt describes the visual content of a video they enjoyed watching. Note that this is a very limited initial dataset, so any patterns identified should be considered preliminary and tentative:
        \(formattedVideos)

        Based on the visual themes and subjects in these liked videos, suggest possible interests and patterns, while acknowledging the limited data.
        For each potential interest:
        - Suggest a specific topic that might match the visual content they've engaged with
        - List relevant examples seen in the prompts, such as:
          * Specific subjects or activities shown
          * Visual styles or techniques they seem to appreciate
          * Equipment or props featured
          * Settings or environments they appear drawn to

        Example response:
        {
          "interests": [
            {
              "topic": "Marine Life Photography",
              "examples": ["close-up octopus behavior", "moody aquarium lighting", "underwater creature details"]
            },
            {
              "topic": "Adventure Sports",
              "examples": ["dramatic climbing shots", "golden hour outdoor photography", "dynamic action angles"]
            }
          ],
          "description": "Based on this limited initial set of interactions, the user appears to show interest in intimate nature photography, particularly content featuring close-up shots that reveal detail in marine life. They've also engaged with some dynamic outdoor sports content, suggesting a possible interest in how photographers capture the intensity of these activities. As more data becomes available, these preferences may evolve or reveal different patterns."
        }

        You MUST identify at least one interest and provide a description.
        Make the description focus on their visual preferences and what kind of content they've engaged with so far, while acknowledging the preliminary nature of these observations.
        Risqué content (eg cleavage, tight clothing, etc) is ok to include if the user's interests align with it, but avoid describing actual nudity.
        """
        
        // Call LLM
        return await LLMService.shared.complete(
            userPrompt: prompt,
            systemPrompt: "You are analyzing video generation prompts to understand a user's visual interests and content preferences. Focus on the subjects, styles, and themes they engage with in video content.",
            responseType: ProfileGenerationResponse.self,
            schema: ProfileGenerationSchema.schema
        )
    }
    
    /// Converts LLM-generated interests into domain model interests
    /// - Parameter response: The LLM generation response
    /// - Returns: Array of Interest models
    func convertToInterests(_ response: ProfileGenerationResponse) async -> [Interest] {
        response.interests.map { generation in
            Interest(
                topic: generation.topic,
                examples: generation.examples.filter { !$0.isEmpty }  // Filter out empty strings
            )
        }
    }
} 