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
        Generate a user profile based on these liked videos:
        \(formattedVideos)
        
        Focus on identifying clear interests and patterns in the videos they liked.
        For each interest:
        - Choose a specific, well-defined topic
        - Provide 3-5 examples of activities or aspects within that topic
        - Make examples specific and varied, covering different aspects like:
          * Specific activities (e.g., "downhill trails", "bouldering problems")
          * Techniques (e.g., "climbing techniques", "trail maintenance")
          * Equipment (e.g., "bike setup", "trail gear")
          * Variations (e.g., "technical singletrack", "sport climbing routes")
        
        Example interests:
        1. Mountain Biking:
           - Examples: ["downhill trails", "bike park jumps", "technical singletrack"]
        2. Rock Climbing:
           - Examples: ["bouldering problems", "sport climbing routes", "climbing techniques", "indoor training"]
        
        You MUST identify at least one interest and provide a description.
        Make the description insightful about their preferences and patterns, for example:
        "This user shows a strong interest in outdoor adventure sports, particularly gravitating towards technical challenges in mountain biking and climbing. They engage with content about both recreational aspects and skill development."
        """
        
        // Call LLM
        return await LLMService.shared.complete(
            userPrompt: prompt,
            systemPrompt: "You are analyzing a user's video preferences to identify their interests and generate a profile. Be specific and concrete in your analysis, focusing on clear patterns in their liked content. Always provide a meaningful description that captures the essence of their interests.",
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