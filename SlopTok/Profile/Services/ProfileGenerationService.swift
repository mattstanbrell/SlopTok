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
        Analyze these AI video generation prompts from videos the user liked. Each prompt describes the visual content of a video they enjoyed watching:
        \(formattedVideos)

        Based on the visual themes and subjects in these liked videos, identify clear interests and patterns.
        For each interest:
        - Choose a specific, well-defined topic that matches the visual content they engage with
        - List relevant examples seen in the prompts, such as:
          * Specific subjects or activities shown
          * Visual styles or techniques they appreciate
          * Equipment or props featured
          * Settings or environments they're drawn to

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
          "description": "This user is drawn to intimate nature photography, particularly appreciating close-up shots that reveal detail and personality in marine life. They also engage with dynamic outdoor sports content, showing interest in how photographers capture the intensity and technical aspects of these activities."
        }

        You MUST identify at least one interest and provide a description.
        Make the description focus on their visual preferences and what kind of content engages them.
        Risqué content (eg cleavage, tight clothing, etc) is ok to include if the user's profile interests align with it, but avoid describing actual nudity.
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