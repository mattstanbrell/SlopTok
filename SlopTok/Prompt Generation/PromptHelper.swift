import Foundation
import UIKit
import FirebaseVertexAI

/// Helper class for constructing prompts for video generation
enum PromptHelper {
    /// Constructs the base prompt parts array from liked videos and their thumbnails
    static func constructBaseParts(
        likedVideosWithThumbnails: [(id: String, prompt: String, image: UIImage)]
    ) -> [PartsRepresentable] {
        var parts: [PartsRepresentable] = []
        for (index, video) in likedVideosWithThumbnails.enumerated() {
            parts.append("Image \(index + 1) Prompt: \(video.prompt) (ID: \(video.id))" as PartsRepresentable)
            parts.append(video.image as PartsRepresentable)
        }
        return parts
    }
    
    /// Formats user interests into a string
    static func formatInterests(_ interests: [Interest]) -> String {
        interests.map { interest in
            """
            - \(interest.topic):
              Examples: \(interest.examples.joined(separator: ", "))
            """
        }.joined(separator: "\n")
    }
    
    /// Constructs the shared quality guidelines section
    static func qualityGuidelines() -> String {
        """
        Focus on creating prompts that will generate stunning, high-quality images. Consider:
        - Strong composition (rule of thirds, leading lines, etc.)
        - Lighting and shadows
        - Focus and detail
        - Texture and materials
        - Color harmony
        - Visual storytelling through a single frame
        - Artistic style (photorealistic, stylized, illustrated, animated, etc.)
        """
    }
    
    /// Constructs the example prompts section
    static func examplePrompts() -> String {
        """
        Example good prompt:
        "A close-up, macro photography stock photo of a strawberry intricately sculpted into the shape of a hummingbird in mid-flight, its wings a blur as it sips nectar from a vibrant, tubular flower. The backdrop features a lush, colorful garden with a soft, bokeh effect, creating a dreamlike atmosphere. The image is exceptionally detailed and captured with a shallow depth of field, ensuring a razor-sharp focus on the strawberry-hummingbird and gentle fading of the background. The high resolution, professional photographers style, and soft lighting illuminate the scene in a very detailed manner, professional color grading amplifies the vibrant colors and creates an image with exceptional clarity. The depth of field makes the hummingbird and flower stand out starkly against the bokeh background." (ID: abc123)
        """
    }
    
    /// Constructs the example crossover prompts section
    static func exampleCrossoverPrompts() -> String {
        """
        Example good prompt 1:
        "A close-up, macro photography stock photo of a strawberry intricately sculpted into the shape of a hummingbird in mid-flight, its wings a blur as it sips nectar from a vibrant, tubular flower. The backdrop features a lush, colorful garden with a soft, bokeh effect, creating a dreamlike atmosphere. The image is exceptionally detailed and captured with a shallow depth of field, ensuring a razor-sharp focus on the strawberry-hummingbird and gentle fading of the background. The high resolution, professional photographers style, and soft lighting illuminate the scene in a very detailed manner, professional color grading amplifies the vibrant colors and creates an image with exceptional clarity. The depth of field makes the hummingbird and flower stand out starkly against the bokeh background." (ID: abc123)
        
        Example good prompt 2:
        "A dramatic macro photograph of a dragon fruit carved into an intricate Eastern dragon, its serpentine body coiled around a moonlit pagoda made of dragonfruit flesh. The dragon's scales are meticulously detailed, each one individually carved to catch the light. The scene is illuminated by traditional paper lanterns, casting a warm glow that contrasts with the cool moonlight. Shot with professional lighting and a macro lens to capture the intricate details of the carving, while maintaining a dreamy atmosphere with selective focus." (ID: def456)
        """
    }
    
    /// Constructs the mutation guidelines section
    static func mutationGuidelines() -> String {
        """
        Each new prompt should be a variation of ONE parent prompt, keeping its core theme but varying elements like:
        - The specific subject or focal point
        - The visual style and composition
        - The environment or setting
        - The lighting and atmosphere
        - The perspective and framing
        - The artistic technique or medium
        - The color palette and tones
        """
    }
    
    /// Constructs the crossover guidelines section
    static func crossoverGuidelines() -> String {
        """
        Each new prompt should creatively merge elements from TWO parent prompts, considering:
        - How to meaningfully combine their subjects
        - How to blend their visual styles
        - How to merge their environments
        - How to harmonize their lighting and atmosphere
        - How to integrate their artistic techniques
        - How to combine their color palettes
        """
    }
    
    /// Constructs the example mutation response section
    static func exampleMutationResponse() -> String {
        """
        Example response:
        {
          "mutatedPrompts": [
            {
              "prompt": "A close-up, macro photography capture of a strawberry intricately sculpted into a hummingbird, illuminated by ethereal moonlight in a night garden scene. Tiny dewdrops glisten on its carved feathers, catching the moonlight like diamonds. The background garden is bathed in cool blue tones with fireflies providing points of warm light, their glow reflecting in the dewdrops. Shot with exceptional detail and shallow depth of field, emphasizing the interplay of light and shadow in the nocturnal setting",
              "parentId": "abc123"
            }
          ]
        }
        """
    }
    
    /// Constructs the example crossover response section
    static func exampleCrossoverResponse() -> String {
        """
        Example response:
        {
          "crossoverPrompts": [
            {
              "prompt": "A masterfully executed macro photograph of a fruit sculpture garden where a strawberry hummingbird and dragon fruit dragon dance through the air together. The scene captures their aerial ballet with crystalline clarity - the hummingbird's delicate carved wings complementing the dragon's flowing serpentine form. The backdrop features a fusion of Eastern and Western garden elements: vibrant tubular flowers intertwined with moonlit pagoda archways. Professional lighting combines soft daylight and warm lantern glow, while selective focus emphasizes the intricate details of both creatures against a dreamy, bokeh-rich background",
              "parentIds": ["abc123", "def456"]
            }
          ]
        }
        """
    }
    
    /// Constructs the complete mutation prompt
    static func constructMutationPrompt(
        count: Int,
        profile: UserProfile,
        likedVideosWithThumbnails: [(id: String, prompt: String, image: UIImage)]
    ) -> String {
        let formattedInterests = formatInterests(profile.interests)
        
        return """
        Generate \(count) new image prompts by mutating these prompts and images the user liked.
        \(mutationGuidelines())
        
        User's interests for context:
        \(formattedInterests)
        User description: \(profile.description)
        
        \(qualityGuidelines())
        
        \(examplePrompts())
        
        \(exampleMutationResponse())
        
        Generate \(count) unique prompts, each building upon one of the provided images.
        If there are less than \(count) images, mutate some of the prompts multiple times.
        For each prompt, include the parentId of the source image.
        """
    }
    
    /// Constructs the complete crossover prompt
    static func constructCrossoverPrompt(
        count: Int,
        profile: UserProfile,
        likedVideosWithThumbnails: [(id: String, prompt: String, image: UIImage)]
    ) -> String {
        let formattedInterests = formatInterests(profile.interests)
        
        return """
        Generate \(count) new image prompts by combining elements from pairs of prompts and images the user liked.
        \(crossoverGuidelines())
        
        User's interests for context:
        \(formattedInterests)
        User description: \(profile.description)
        
        \(qualityGuidelines())
        
        \(exampleCrossoverPrompts())
        
        \(exampleCrossoverResponse())
        
        Generate \(count) unique prompts, each combining elements from TWO of the provided images.
        For each prompt, include the parentIds of BOTH source images.
        """
    }
    
    /// Constructs the example profile-based prompt section
    static func exampleProfileBasedPrompt() -> String {
        """
        Example prompt structure (unrelated to user's interests, just showing format):
        "An extreme close-up of a professional rock climber's chalk-covered hands gripping a vividly colored climbing hold, shot with macro photography style and attention to detail. Each grain of chalk and texture in the skin is captured with razor-sharp focus, while the climbing gym's colorful walls create a beautiful bokeh background. The lighting is dramatic and professional, highlighting the tension in the grip and the interplay of textures"
        """
    }
    
    /// Constructs the complete profile-based prompt
    static func constructProfileBasedPrompt(
        count: Int,
        profile: UserProfile
    ) -> String {
        let formattedInterests = formatInterests(profile.interests)
        
        return """
        Generate \(count) new image prompts based purely on this user's interests and preferences.
        Create prompts that align with their interests but explore new subjects and styles.
        
        User's interests:
        \(formattedInterests)
        User description: \(profile.description)
        
        \(qualityGuidelines())
        
        \(exampleProfileBasedPrompt())
        
        Generate \(count) unique prompts that match the user's interests, using the same high-quality prompt structure.
        Do not include any parentIds in the response.
        """
    }
} 