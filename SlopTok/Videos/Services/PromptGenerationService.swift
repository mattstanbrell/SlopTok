import Foundation

/// Service responsible for generating new video prompts using LLM
actor PromptGenerationService {
    /// Shared instance
    static let shared = PromptGenerationService()
    
    private init() {}
    
    /// Generates the initial set of prompts after seed videos
    /// - Parameters:
    ///   - likedVideos: Array of prompts from seed videos the user liked
    ///   - profile: The user's current profile
    /// - Returns: Array of generated prompts or error
    func generateInitialPrompts(
        likedVideos: [(id: String, prompt: String)],
        profile: UserProfile
    ) async -> LLMResponse<PromptGenerationResponse> {
        // Format liked video prompts for readability
        let formattedPrompts = likedVideos
            .map { "- \($0.prompt) (ID: \($0.id))" }
            .joined(separator: "\n")
        
        // Format profile interests for context
        let formattedInterests = profile.interests
            .map { interest in
                """
                - \(interest.topic):
                  Examples: \(interest.examples.joined(separator: ", "))
                """
            }
            .joined(separator: "\n")
        
        // Build the prompt
        let prompt = """
        Generate new video prompts based on these liked videos and the user's profile.
        
        Liked video prompts:
        \(formattedPrompts)
        
        User's interests and profile:
        \(formattedInterests)
        Description: \(profile.description)
        
        Generate 20 new prompts:
        1. Create mutations of successful prompts by varying elements like (but not limited to):
           - The specific subject or action
           - The visual style or composition
           - The environment or setting
           - The lighting or time of day
           - The camera angle or distance
           - The mood or atmosphere
        2. Create crossovers by combining compelling elements from pairs of successful prompts
        3. Create new prompts inspired by the user's interests and profile description
        4. Create some completely novel prompts for exploration
        
        For mutations and crossovers, include the parent prompt IDs.
        - Mutations should have one parent ID
        - Crossovers should have two parent IDs
        - Profile-based and novel prompts should have no parent IDs
        
        Example response:
        {
            "prompts": [
                {
                    "prompt": "A close-up, macro photography stock photo of a strawberry intricately sculpted into the shape of a hummingbird in mid-flight, its wings a blur as it sips nectar from a vibrant, tubular flower. The backdrop features a lush, colorful garden with a soft, bokeh effect, creating a dreamlike atmosphere. The image is exceptionally detailed and captured with a shallow depth of field, ensuring a razor-sharp focus on the strawberry-hummingbird and gentle fading of the background. The high resolution, professional photographers style, and soft lighting illuminate the scene in a very detailed manner, professional color grading amplifies the vibrant colors and creates an image with exceptional clarity. The depth of field makes the hummingbird and flower stand out starkly against the bokeh background",
                    "parentIds": ["abc123"]  // Original prompt
                },
                {
                    "prompt": "A close-up, macro photography capture of the same strawberry-hummingbird now illuminated by moonlight, creating an ethereal night garden scene. Tiny dewdrops glisten on its carved feathers, catching the moonlight like diamonds. The background garden is bathed in cool blue tones with fireflies providing points of warm light, their glow reflecting in the dewdrops. Shot with the same exceptional detail and shallow depth of field, but now emphasizing the interplay of light and shadow in the nocturnal setting",
                    "parentIds": ["abc123"]  // Mutation: changing time and lighting
                },
                {
                    "prompt": "A masterfully executed fusion of two fruit sculptures: a strawberry hummingbird and a dragon fruit dragon, locked in an intricate aerial dance. The hummingbird's delicate form contrasts with the dragon's serpentine body, both captured in stunning macro detail. Professional lighting emphasizes the unique textures of each fruit, while the shallow depth of field creates a dreamy backdrop of a misty Chinese garden. The high-resolution capture ensures every carved scale and feather is crystal clear",
                    "parentIds": ["abc123", "def456"]  // Crossover combining themes
                },
                {
                    "prompt": "An extreme close-up of a professional rock climber's chalk-covered hands gripping a vividly colored climbing hold, shot with the same macro photography style and attention to detail as the strawberry-hummingbird. Each grain of chalk and texture in the skin is captured with razor-sharp focus, while the climbing gym's colorful walls create a beautiful bokeh background. The lighting is dramatic and professional, highlighting the tension in the grip and the interplay of textures"  // Based on profile interests
                }
            ]
        }
        """
        
        // Call LLM
        return await LLMService.shared.complete(
            userPrompt: prompt,
            systemPrompt: "You are generating creative video prompts that build upon successful prompts and user interests. Focus on visual elements and composition that will create engaging videos. Be imaginative while maintaining high production value and visual appeal. Pay special attention to lighting, detail, and professional photography techniques.",
            responseType: PromptGenerationResponse.self,
            schema: PromptGenerationSchema.schema
        )
    }
} 