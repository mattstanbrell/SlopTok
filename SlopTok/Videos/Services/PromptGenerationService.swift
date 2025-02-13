import Foundation
import AVFoundation
import FirebaseStorage
import SwiftUI
import FirebaseVertexAI

/// Helper for exponential backoff retries
private struct RetryHelper {
    /// Maximum number of retries
    static let maxRetries = 5
    
    /// Executes a task with exponential backoff retries
    /// - Parameters:
    ///   - operation: The async operation to retry
    ///   - shouldRetry: Closure that determines if an error should trigger a retry
    /// - Returns: The operation result
    static func retry<T>(
        operation: () async throws -> T,
        shouldRetry: (Error) -> Bool = { _ in true }
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                if attempt > 0 {
                    // Exponential backoff: 1s, 2s, 4s
                    let delay = pow(2.0, Double(attempt - 1))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    print("🔄 Retry attempt \(attempt) after \(delay)s delay")
                }
                return try await operation()
            } catch {
                lastError = error
                if !shouldRetry(error) || attempt == maxRetries {
                    throw error
                }
                print("❌ Attempt \(attempt) failed: \(error.localizedDescription)")
            }
        }
        
        throw lastError ?? NSError(
            domain: "RetryHelper",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown error during retry"]
        )
    }
}

/// Service responsible for generating new video prompts using LLM
actor PromptGenerationService {
    /// Shared instance
    static let shared = PromptGenerationService()
    
    private let mutationModel: GenerativeModel
    private let crossoverModel: GenerativeModel
    
    private init() {
        self.mutationModel = VertexAIService.createGeminiModel(
            modelName: "gemini-2.0-flash",
            generationConfig: GenerationConfig(
                responseMIMEType: "application/json",
                responseSchema: PromptGenerationGeminiSchema.mutationSchema
            )
        )
        
        self.crossoverModel = VertexAIService.createGeminiModel(
            modelName: "gemini-2.0-flash",
            generationConfig: GenerationConfig(
                responseMIMEType: "application/json",
                responseSchema: PromptGenerationGeminiSchema.crossoverSchema
            )
        )
    }
    
    /// Calculate the distribution of prompt types based on number of liked prompts
    private func calculatePromptDistribution(likedCount: Int) -> (
        mutationCount: Int,
        crossoverCount: Int,
        profileBasedCount: Int,
        explorationCount: Int
    ) {
        switch likedCount {
        case 0:
            // No liked prompts -> heavy on profile and exploration
            return (mutationCount: 0, crossoverCount: 0, profileBasedCount: 15, explorationCount: 5)
            
        case 1:
            // Can't do crossovers with one prompt
            return (mutationCount: 4, crossoverCount: 0, profileBasedCount: 12, explorationCount: 4)
            
        case 2:
            // Limited crossover potential with two prompts
            return (mutationCount: 6, crossoverCount: 2, profileBasedCount: 8, explorationCount: 4)
            
        case 3...5:
            // Scale up mutations based on available prompts, maintain good exploration
            let mutations = min(10, likedCount * 2)
            let crossovers = min(5, likedCount)  // Scale crossovers with available prompts
            let remaining = 20 - mutations - crossovers
            return (mutationCount: mutations,
                   crossoverCount: crossovers,
                   profileBasedCount: remaining - 2,  // Save 2 for exploration
                   explorationCount: 2)
            
        case 6...9:
            // Close to target distribution
            return (mutationCount: min(10, likedCount),
                   crossoverCount: 5,
                   profileBasedCount: 3,
                   explorationCount: 2)
            
        default: // >= 10 prompts
            // Target distribution
            return (mutationCount: 10,
                   crossoverCount: 5,
                   profileBasedCount: 3,
                   explorationCount: 2)
        }
    }
    
    /// Generate mutation prompts from liked prompts
    private func generateMutationPrompts(
        count: Int,
        likedVideos: [(id: String, prompt: String)],
        profile: UserProfile
    ) async throws -> [PromptGeneration] {
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
            parts.append("Image \(index + 1) Prompt: \(likedVideos[index].prompt) (ID: \(likedVideos[index].id))" as PartsRepresentable)
            parts.append(image.image as PartsRepresentable)
        }
        
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
        Generate \(count) new image prompts by mutating these prompts and images the user liked.
        Each new prompt should be a variation of ONE parent prompt, keeping its core theme but varying elements like:
        - The specific subject or focal point
        - The visual style and composition
        - The environment or setting
        - The lighting and atmosphere
        - The perspective and framing
        - The artistic technique or medium
        - The color palette and tones
        
        User's interests for context:
        \(formattedInterests)
        User description: \(profile.description)
        
        Focus on creating prompts that will generate stunning, high-quality images. Consider:
        - Strong composition (rule of thirds, leading lines, etc.)
        - Lighting and shadows
        - Focus and detail
        - Texture and materials
        - Color harmony
        - Visual storytelling through a single frame
        - Artistic style (photorealistic, stylized, illustrated, animated, etc.)
        
        Example good prompt:
        "A close-up, macro photography stock photo of a strawberry intricately sculpted into the shape of a hummingbird in mid-flight, its wings a blur as it sips nectar from a vibrant, tubular flower. The backdrop features a lush, colorful garden with a soft, bokeh effect, creating a dreamlike atmosphere. The image is exceptionally detailed and captured with a shallow depth of field, ensuring a razor-sharp focus on the strawberry-hummingbird and gentle fading of the background. The high resolution, professional photographers style, and soft lighting illuminate the scene in a very detailed manner, professional color grading amplifies the vibrant colors and creates an image with exceptional clarity. The depth of field makes the hummingbird and flower stand out starkly against the bokeh background." (ID: abc123)
        
        Example response:
        {
          "mutatedPrompts": [
            {
              "prompt": "A close-up, macro photography capture of a strawberry intricately sculpted into a hummingbird, illuminated by ethereal moonlight in a night garden scene. Tiny dewdrops glisten on its carved feathers, catching the moonlight like diamonds. The background garden is bathed in cool blue tones with fireflies providing points of warm light, their glow reflecting in the dewdrops. Shot with exceptional detail and shallow depth of field, emphasizing the interplay of light and shadow in the nocturnal setting",
              "parentId": "abc123"
            }
          ]
        }
        
        Generate \(count) unique prompts, each building upon one of the provided images.
        If there are less than \(count) images, mutate some of the prompts multiple times.
        For each prompt, include the parentId of the source image.
        """
        
        // Call Gemini with retry logic
        let maxRetries = 5
        var lastError: Error?
        
        // Log the full prompt we're sending
        print("\n📝 Sending prompt to Gemini:")
        print("=== PROMPT START ===")
        print(prompt)
        print("=== PROMPT END ===\n")
        
        for attempt in 0...maxRetries {
            do {
                if attempt > 0 {
                    print("🔄 Retry attempt \(attempt) for mutation prompts")
                    try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * Double(attempt)))
                }
                
                let response = try await mutationModel.generateContent(parts + [prompt as PartsRepresentable])
                
                if let text = response.text {
                    print("\n📥 Received response from Gemini:")
                    print("=== RESPONSE START ===")
                    print(text)
                    print("=== RESPONSE END ===\n")
                    
                    if let data = text.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode(PromptGenerationGeminiResponse.self, from: data) {
                        if let mutatedPrompts = decoded.mutatedPrompts {
                            print("✅ Successfully decoded response into \(mutatedPrompts.count) mutation prompts")
                            
                            // Convert to PromptGeneration objects
                            let prompts = mutatedPrompts.map { mutation -> PromptGeneration in
                                return PromptGeneration(prompt: mutation.prompt, parentId: mutation.parentId)
                            }
                            
                            return prompts
                        } else if let crossoverPrompts = decoded.crossoverPrompts {
                            print("✅ Successfully decoded response into \(crossoverPrompts.count) crossover prompts")
                            
                            // Convert to PromptGeneration objects
                            let prompts = crossoverPrompts.map { crossover -> PromptGeneration in
                                return PromptGeneration(prompt: crossover.prompt, parentIds: crossover.parentIds)
                            }
                            
                            return prompts
                        } else {
                            print("❌ Response contained neither mutation nor crossover prompts")
                            throw LLMError.apiError("Invalid response format - no prompts found")
                        }
                    } else {
                        print("❌ Failed to decode response as PromptGenerationGeminiResponse")
                        throw LLMError.apiError("Invalid response format")
                    }
                } else {
                    print("❌ Empty response from Gemini")
                    throw LLMError.apiError("Empty response")
                }
            } catch {
                lastError = error
                if attempt == maxRetries {
                    print("❌ All retry attempts failed for mutation prompts")
                    throw error
                }
            }
        }
        
        throw lastError ?? LLMError.systemError(NSError(
            domain: "PromptGenerationService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown error during mutation generation"]
        ))
    }
    
    /// Generate crossover prompts from liked prompts
    private func generateCrossoverPrompts(
        count: Int,
        likedVideos: [(id: String, prompt: String)],
        profile: UserProfile
    ) async throws -> [PromptGeneration] {
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
            parts.append("Image \(index + 1) Prompt: \(likedVideos[index].prompt) (ID: \(likedVideos[index].id))" as PartsRepresentable)
            parts.append(image.image as PartsRepresentable)
        }
        
        let formattedInterests = profile.interests
            .map { interest in
                """
                - \(interest.topic):
                  Examples: \(interest.examples.joined(separator: ", "))
                """
            }
            .joined(separator: "\n")
        
        let prompt = """
        Generate \(count) new image prompts by combining elements from pairs of prompts and images the user liked.
        Each new prompt should creatively merge elements from TWO parent prompts, considering:
        - How to meaningfully combine their subjects
        - How to blend their visual styles
        - How to merge their environments
        - How to harmonize their lighting and atmosphere
        - How to integrate their artistic techniques
        - How to combine their color palettes
        
        User's interests for context:
        \(formattedInterests)
        User description: \(profile.description)
        
        Focus on creating prompts that will generate stunning, high-quality images. Consider:
        - Strong composition (rule of thirds, leading lines, etc.)
        - Lighting and shadows
        - Focus and detail
        - Texture and materials
        - Color harmony
        - Visual storytelling through a single frame
        - Artistic style (photorealistic, stylized, illustrated, etc.)
        
        Example good prompt 1:
        "A close-up, macro photography stock photo of a strawberry intricately sculpted into the shape of a hummingbird in mid-flight, its wings a blur as it sips nectar from a vibrant, tubular flower. The backdrop features a lush, colorful garden with a soft, bokeh effect, creating a dreamlike atmosphere. The image is exceptionally detailed and captured with a shallow depth of field, ensuring a razor-sharp focus on the strawberry-hummingbird and gentle fading of the background. The high resolution, professional photographers style, and soft lighting illuminate the scene in a very detailed manner, professional color grading amplifies the vibrant colors and creates an image with exceptional clarity. The depth of field makes the hummingbird and flower stand out starkly against the bokeh background." (ID: abc123)
        
        Example good prompt 2:
        "A dramatic macro photograph of a dragon fruit carved into an intricate Eastern dragon, its serpentine body coiled around a moonlit pagoda made of dragonfruit flesh. The dragon's scales are meticulously detailed, each one individually carved to catch the light. The scene is illuminated by traditional paper lanterns, casting a warm glow that contrasts with the cool moonlight. Shot with professional lighting and a macro lens to capture the intricate details of the carving, while maintaining a dreamy atmosphere with selective focus." (ID: def456)
        
        Example response:
        {
          "crossoverPrompts": [
            {
              "prompt": "A masterfully executed macro photograph of a fruit sculpture garden where a strawberry hummingbird and dragon fruit dragon dance through the air together. The scene captures their aerial ballet with crystalline clarity - the hummingbird's delicate carved wings complementing the dragon's flowing serpentine form. The backdrop features a fusion of Eastern and Western garden elements: vibrant tubular flowers intertwined with moonlit pagoda archways. Professional lighting combines soft daylight and warm lantern glow, while selective focus emphasizes the intricate details of both creatures against a dreamy, bokeh-rich background",
              "parentIds": ["abc123", "def456"]
            }
          ]
        }
        
        Generate \(count) unique prompts, each combining elements from TWO of the provided images.
        For each prompt, include the parentIds of BOTH source images.
        """
        
        // Call Gemini with retry logic
        let maxRetries = 5
        var lastError: Error?
        
        // Log the full prompt we're sending
        print("\n📝 Sending prompt to Gemini:")
        print("=== PROMPT START ===")
        print(prompt)
        print("=== PROMPT END ===\n")
        
        for attempt in 0...maxRetries {
            do {
                if attempt > 0 {
                    print("🔄 Retry attempt \(attempt) for crossover prompts")
                    try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * Double(attempt)))
                }
                
                let response = try await crossoverModel.generateContent(parts + [prompt as PartsRepresentable])
                
                if let text = response.text {
                    print("\n📥 Received response from Gemini:")
                    print("=== RESPONSE START ===")
                    print(text)
                    print("=== RESPONSE END ===\n")
                    
                    if let data = text.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode(PromptGenerationGeminiResponse.self, from: data) {
                        if let mutatedPrompts = decoded.mutatedPrompts {
                            print("✅ Successfully decoded response into \(mutatedPrompts.count) mutation prompts")
                            
                            // Convert to PromptGeneration objects
                            let prompts = mutatedPrompts.map { mutation -> PromptGeneration in
                                return PromptGeneration(prompt: mutation.prompt, parentId: mutation.parentId)
                            }
                            
                            return prompts
                        } else if let crossoverPrompts = decoded.crossoverPrompts {
                            print("✅ Successfully decoded response into \(crossoverPrompts.count) crossover prompts")
                            
                            // Convert to PromptGeneration objects
                            let prompts = crossoverPrompts.map { crossover -> PromptGeneration in
                                return PromptGeneration(prompt: crossover.prompt, parentIds: crossover.parentIds)
                            }
                            
                            return prompts
                        } else {
                            print("❌ Response contained neither mutation nor crossover prompts")
                            throw LLMError.apiError("Invalid response format - no prompts found")
                        }
                    } else {
                        print("❌ Failed to decode response as PromptGenerationGeminiResponse")
                        throw LLMError.apiError("Invalid response format")
                    }
                } else {
                    print("❌ Empty response from Gemini")
                    throw LLMError.apiError("Empty response")
                }
            } catch {
                lastError = error
                if attempt == maxRetries {
                    print("❌ All retry attempts failed for crossover prompts")
                    throw error
                }
            }
        }
        
        throw lastError ?? LLMError.systemError(NSError(
            domain: "PromptGenerationService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown error during crossover generation"]
        ))
    }
    
    /// Generate prompts based on user profile
    private func generateProfileBasedPrompts(
        count: Int,
        profile: UserProfile
    ) async throws -> [PromptGeneration] {
        let formattedInterests = profile.interests
            .map { interest in
                """
                - \(interest.topic):
                  Examples: \(interest.examples.joined(separator: ", "))
                """
            }
            .joined(separator: "\n")
        
        let prompt = """
        Generate \(count) new image prompts based purely on this user's interests and preferences.
        Create prompts that align with their interests but explore new subjects and styles.
        
        User's interests:
        \(formattedInterests)
        User description: \(profile.description)
        
        Focus on creating prompts that will generate stunning, high-quality images. Consider:
        - Strong composition (rule of thirds, leading lines, etc.)
        - Lighting and shadows
        - Focus and detail
        - Texture and materials
        - Color harmony
        - Visual storytelling through a single frame
        - Artistic style (photorealistic, stylized, illustrated, etc.)
        
        Example prompt structure (unrelated to user's interests, just showing format):
        "An extreme close-up of a professional rock climber's chalk-covered hands gripping a vividly colored climbing hold, shot with macro photography style and attention to detail. Each grain of chalk and texture in the skin is captured with razor-sharp focus, while the climbing gym's colorful walls create a beautiful bokeh background. The lighting is dramatic and professional, highlighting the tension in the grip and the interplay of textures"
        
        Generate \(count) unique prompts that match the user's interests, using the same high-quality prompt structure.
        Do not include any parentIds in the response.
        """
        
        return try await RetryHelper.retry {
            let result = await LLMService.shared.complete(
                userPrompt: prompt,
                systemPrompt: "You are generating creative photo prompts based on a user's interests and preferences. Focus on creating prompts that align with their interests while maintaining high visual quality and appeal.",
                responseType: PromptGenerationResponse.self,
                schema: PromptGenerationSchema.profileBasedSchema
            )
            
            switch result {
            case .success((let response, _)):
                return response.prompts
            case .failure(let error):
                throw error
            }
        }
    }
    
    /// Generate random exploration prompts
    private func generateRandomPrompts(count: Int) async throws -> [PromptGeneration] {
        let prompt = """
        Generate \(count) completely novel, creative image prompts for exploration.
        These should be unique and unexpected, not tied to any existing prompts or user preferences.
        
        Focus on creating prompts that will generate stunning, high-quality images. Consider:
        - Strong composition (rule of thirds, leading lines, etc.)
        - Lighting and shadows
        - Focus and detail
        - Texture and materials
        - Color harmony
        - Visual storytelling through a single frame
        - Artistic style (photorealistic, stylized, illustrated, etc.)
        
        Example good random prompts:
        1. "An otherworldly scene captured through a crystalline prism: a bioluminescent jellyfish floating through a field of suspended diamond dust. Each particle catches and refracts light differently, creating a mesmerizing rainbow spectrum. Shot in ultra-high resolution with cutting-edge microscopy techniques, revealing both the delicate translucent tissues of the jellyfish and the geometric perfection of each suspended crystal"
        2. "A surreal architectural photograph capturing the precise moment when a Baroque cathedral begins transforming into a living tree. The stone pillars flow like liquid into wooden trunks, while stained glass windows blossomed into leaves. Golden hour sunlight streams through the metamorphosing structure, creating an interplay of hard and soft shadows. Shot with a tilt-shift lens to maintain focus on the transformation point while softly blurring the edges"
        
        Generate \(count) unique prompts with similar quality and creativity.
        Do not include any parentIds in the response.
        """
        
        return try await RetryHelper.retry {
            let result = await LLMService.shared.complete(
                userPrompt: prompt,
                systemPrompt: "You are generating creative photo prompts for pure exploration. Focus on creating unique and unexpected concepts while maintaining high visual quality and appeal.",
                responseType: PromptGenerationResponse.self,
                schema: PromptGenerationSchema.randomSchema
            )
            
            switch result {
            case .success((let response, _)):
                return response.prompts
            case .failure(let error):
                throw error
            }
        }
    }
    
    /// Generates prompts based on seed videos
    /// - Parameters:
    ///   - likedVideos: Array of prompts from seed videos the user liked
    ///   - profile: The user's current profile
    /// - Returns: Array of generated prompts or error
    func generatePrompts(
        likedVideos: [(id: String, prompt: String)],
        profile: UserProfile
    ) async -> LLMResponse<PromptGenerationResponse> {
        // Calculate prompt distribution
        let distribution = calculatePromptDistribution(likedCount: likedVideos.count)
        print("📊 Prompt distribution:")
        print("  - Mutations: \(distribution.mutationCount)")
        print("  - Crossovers: \(distribution.crossoverCount)")
        print("  - Profile-based: \(distribution.profileBasedCount)")
        print("  - Exploration: \(distribution.explorationCount)")
        
        // Track all generated prompts
        var allPrompts: [PromptGeneration] = []
        
        do {
            // Create task group for parallel generation
            try await withThrowingTaskGroup(of: [PromptGeneration].self) { group in
                // Add mutation task if needed
                if distribution.mutationCount > 0 {
                    group.addTask {
                        print("🧬 Starting mutation prompt generation...")
                        let prompts = try await self.generateMutationPrompts(
                            count: distribution.mutationCount,
                            likedVideos: likedVideos,
                            profile: profile
                        )
                        print("✅ Generated \(prompts.count) mutation prompts")
                        return prompts
                    }
                }
                
                // Add crossover task if needed
                if distribution.crossoverCount > 0 {
                    group.addTask {
                        print("🔄 Starting crossover prompt generation...")
                        let prompts = try await self.generateCrossoverPrompts(
                            count: distribution.crossoverCount,
                            likedVideos: likedVideos,
                            profile: profile
                        )
                        print("✅ Generated \(prompts.count) crossover prompts")
                        return prompts
                    }
                }
                
                // Add profile-based task if needed
                if distribution.profileBasedCount > 0 {
                    group.addTask {
                        print("👤 Starting profile-based prompt generation...")
                        let prompts = try await self.generateProfileBasedPrompts(
                            count: distribution.profileBasedCount,
                            profile: profile
                        )
                        print("✅ Generated \(prompts.count) profile-based prompts")
                        return prompts
                    }
                }
                
                // Add random exploration task if needed
                if distribution.explorationCount > 0 {
                    group.addTask {
                        print("🎲 Starting random prompt generation...")
                        let prompts = try await self.generateRandomPrompts(
                            count: distribution.explorationCount
                        )
                        print("✅ Generated \(prompts.count) random prompts")
                        return prompts
                    }
                }
                
                // Process prompts as they complete
                for try await prompts in group {
                    // Start processing these prompts immediately
                    Task {
                        do {
                            try await generateVideosFromPrompts(prompts)
                        } catch {
                            print("❌ Error processing prompts: \(error.localizedDescription)")
                        }
                    }
                    
                    // Add to our collection
                    allPrompts.append(contentsOf: prompts)
                }
            }
            
            // Check if we got enough prompts
            let expectedTotal = distribution.mutationCount + distribution.crossoverCount + 
                              distribution.profileBasedCount + distribution.explorationCount
            
            if allPrompts.count < expectedTotal {
                print("⚠️ Only received \(allPrompts.count) prompts, expected \(expectedTotal)")
                
                // Calculate how many more we need of each type
                let remainingMutations = distribution.mutationCount - allPrompts.filter { $0.parentId != nil }.count
                let remainingCrossovers = distribution.crossoverCount - allPrompts.filter { $0.parentIds?.count == 2 }.count
                let remainingProfileBased = distribution.profileBasedCount - allPrompts.filter { $0.parentId == nil && $0.parentIds == nil }.count
                let remainingRandom = distribution.explorationCount - (allPrompts.count - (allPrompts.filter { $0.parentId != nil || $0.parentIds != nil }.count))
                
                // Try to generate the remaining prompts
                if remainingMutations > 0 {
                    print("🔄 Retrying mutation prompts for \(remainingMutations) prompts")
                    let additional = try await generateMutationPrompts(
                        count: remainingMutations,
                        likedVideos: likedVideos,
                        profile: profile
                    )
                    try await generateVideosFromPrompts(additional)
                    allPrompts.append(contentsOf: additional)
                }
                
                if remainingCrossovers > 0 {
                    print("🔄 Retrying crossover prompts for \(remainingCrossovers) prompts")
                    let additional = try await generateCrossoverPrompts(
                        count: remainingCrossovers,
                        likedVideos: likedVideos,
                        profile: profile
                    )
                    try await generateVideosFromPrompts(additional)
                    allPrompts.append(contentsOf: additional)
                }
                
                if remainingProfileBased > 0 {
                    print("🔄 Retrying profile-based prompts for \(remainingProfileBased) prompts")
                    let additional = try await generateProfileBasedPrompts(
                        count: remainingProfileBased,
                        profile: profile
                    )
                    try await generateVideosFromPrompts(additional)
                    allPrompts.append(contentsOf: additional)
                }
                
                if remainingRandom > 0 {
                    print("🔄 Retrying random prompts for \(remainingRandom) prompts")
                    let additional = try await generateRandomPrompts(count: remainingRandom)
                    try await generateVideosFromPrompts(additional)
                    allPrompts.append(contentsOf: additional)
                }
            }
            
            print("✅ Generated \(allPrompts.count) total prompts")
            return .success(PromptGenerationResponse(prompts: allPrompts), rawContent: "")
            
        } catch {
            print("❌ Error during prompt generation: \(error.localizedDescription)")
            return .failure(.systemError(error))
        }
    }

    /// Result of processing a single prompt
    private struct ProcessingResult {
        let videoId: String
        let prompt: PromptGeneration
    }

    /// Generates videos from an array of prompts in parallel
    private func generateVideosFromPrompts(_ prompts: [PromptGeneration]) async throws {
        print("🎬 Starting video generation for \(prompts.count) prompts")
        
        // Create a task group for parallel processing
        var completedVideoIds: [String] = []
        var failedPrompts: [(prompt: PromptGeneration, error: Error)] = []
        
        // Semaphore to limit concurrent tasks to avoid overwhelming the system
        let maxConcurrentTasks = 3 // Reduced from 5 to lower system load
        let semaphore = DispatchSemaphore(value: maxConcurrentTasks)
        
        try await withThrowingTaskGroup(of: ProcessingResult?.self) { group in
            // Start all tasks
            for (index, prompt) in prompts.enumerated() {
                // Check if the task group has been cancelled
                try Task.checkCancellation()
                
                // Wait for a slot to become available
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().async {
                        semaphore.wait()
                        continuation.resume()
                    }
                }
                
                group.addTask { [weak self] in
                    guard let self = self else { 
                        throw NSError(domain: "PromptGenerationService", code: -1, 
                                    userInfo: [NSLocalizedDescriptionKey: "Service was deallocated"])
                    }
                    
                    defer {
                        semaphore.signal() // Release the slot when done
                    }
                    
                    // Create a unique directory for this task's temporary files
                    let taskTempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    
                    defer {
                        // Clean up temporary directory when task is done
                        try? FileManager.default.removeItem(at: taskTempDir)
                    }
                    
                    print("🎯 Starting task \(index + 1)/\(prompts.count)")
                    
                    // Retry logic for the entire pipeline
                    let maxRetries = 5
                    var lastError: Error?
                    
                    for attempt in 0...maxRetries {
                        do {
                            // Check for cancellation at the start of each attempt
                            try Task.checkCancellation()
                            
                            if attempt > 0 {
                                print("🔄 Retry attempt \(attempt) for task \(index + 1)")
                            }
                            
                            // Create the temp directory if it doesn't exist
                            try FileManager.default.createDirectory(at: taskTempDir, 
                                                                  withIntermediateDirectories: true)
                            
                            // 1. Generate image
                            let imageData = try await self.generateImage(from: prompt.prompt)
                            try Task.checkCancellation()
                            print("✅ Task \(index + 1): Generated image")
                            
                            // 2. Convert to video
                            let videoURL = try await self.convertImageToVideo(
                                imageData,
                                tempDirectory: taskTempDir
                            )
                            try Task.checkCancellation()
                            print("✅ Task \(index + 1): Converted to video")
                            
                            // Verify the video file exists and is accessible
                            guard FileManager.default.fileExists(atPath: videoURL.path) else {
                                throw NSError(
                                    domain: "PromptGenerationService",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Video file not found after conversion"]
                                )
                            }
                            
                            // 3. Upload video and get video ID
                            let videoId = try await self.uploadVideo(at: videoURL, prompt: prompt)
                            try Task.checkCancellation()
                            print("✅ Task \(index + 1): Uploaded video \(videoId)")
                            
                            return ProcessingResult(videoId: videoId, prompt: prompt)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            lastError = error
                            print("❌ Task \(index + 1) attempt \(attempt) failed: \(error.localizedDescription)")
                            
                            if attempt == maxRetries {
                                await MainActor.run {
                                    failedPrompts.append((prompt: prompt, error: error))
                                }
                                return nil
                            }
                            
                            try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * Double(attempt + 1)))
                        }
                    }
                    return nil
                }
            }
            
            // Collect results and update feed in batches
            for try await result in group {
                if let result = result {
                    await MainActor.run {
                        completedVideoIds.append(result.videoId)
                        
                        // First 5 videos added individually
                        if completedVideoIds.count <= 5 {
                            print("📱 Adding video to feed (first 5): \(result.videoId)")
                            VideoService.shared.appendVideo(result.videoId)
                        }
                        // After first 5, add in batches of 5
                        else if completedVideoIds.count % 5 == 0 {
                            let startIndex = completedVideoIds.count - 5
                            let batch = Array(completedVideoIds[startIndex..<completedVideoIds.count])
                            print("📱 Adding batch of \(batch.count) videos to feed")
                            for videoId in batch {
                                VideoService.shared.appendVideo(videoId)
                            }
                        }
                    }
                }
            }
            
            // Add any remaining videos
            await MainActor.run {
                if completedVideoIds.count > 5 {
                    let remainingCount = (completedVideoIds.count - 5) % 5
                    if remainingCount > 0 {
                        let startIndex = completedVideoIds.count - remainingCount
                        let batch = Array(completedVideoIds[startIndex..<completedVideoIds.count])
                        print("📱 Adding final batch of \(batch.count) videos to feed")
                        for videoId in batch {
                            VideoService.shared.appendVideo(videoId)
                        }
                    }
                }
                
                // Log completion statistics
                print("🎉 Video generation completed:")
                print("  ✅ Successfully completed: \(completedVideoIds.count) videos")
                print("  ❌ Failed: \(failedPrompts.count) prompts")
                
                if !failedPrompts.isEmpty {
                    print("\nFailed prompts and their errors:")
                    for (index, failedPrompt) in failedPrompts.enumerated() {
                        print("\n\(index + 1). Prompt: \(failedPrompt.prompt.prompt.prefix(50))...")
                        print("   Error: \(failedPrompt.error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Generates an image from a prompt using Flux Schnell
    private func generateImage(from prompt: String) async throws -> Data {
        print("🖼️ Generating image for prompt: \(prompt)")
        
        let request = URLRequest(url: URL(string: "https://sloptok-schnell.mattstanbrell.workers.dev/")!)
        var imageRequest = request
        imageRequest.httpMethod = "POST"
        imageRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ["prompt": prompt]
        imageRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: imageRequest)
        let imageResponse = try JSONDecoder().decode(FluxSchnellResponse.self, from: data)
        
        guard imageResponse.success,
              let imageUrl = URL(string: imageResponse.imageUrl) else {
            throw NSError(domain: "PromptGenerationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image response"])
        }
        
        // Download the image data from the URL
        let (imageData, _) = try await URLSession.shared.data(from: imageUrl)
        return imageData
    }

    /// Converts an image to a 3-second video
    private func convertImageToVideo(_ imageData: Data, tempDirectory: URL) async throws -> URL {
        print("🎬 Converting image to video")
        
        let tempImageURL = tempDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try imageData.write(to: tempImageURL)
        
        guard let image = UIImage(contentsOfFile: tempImageURL.path) else {
            throw NSError(domain: "PromptGenerationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create UIImage from data"])
        }
        
        // Use the converter with the standard parameters
        let videoURL = try await ImageToVideoConverter.convertImageToVideo(
            image: image,
            duration: 3.0,
            size: CGSize(width: 1080, height: 1920) // 9:16 aspect ratio for vertical video
        )
        
        // Clean up the temporary image file
        try? FileManager.default.removeItem(at: tempImageURL)
        
        // Move the video to our task's temp directory for better management
        let finalVideoURL = tempDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try FileManager.default.moveItem(at: videoURL, to: finalVideoURL)
        
        // Verify the video was created successfully
        guard FileManager.default.fileExists(atPath: finalVideoURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: finalVideoURL.path),
              let fileSize = attributes[.size] as? Int64,
              fileSize > 0 else {
            throw NSError(
                domain: "PromptGenerationService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Video file is missing or empty after conversion"]
            )
        }
        
        return finalVideoURL
    }

    /// Uploads a video to Firebase Storage with metadata
    /// Returns the generated video ID
    private func uploadVideo(at videoURL: URL, prompt: PromptGeneration) async throws -> String {
        print("📤 Starting video upload process")
        print("📤 Video file exists: \(FileManager.default.fileExists(atPath: videoURL.path))")
        
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int64 {
            print("📤 Video file size: \(fileSize) bytes")
        }
        
        // Generate a shorter video ID: timestamp (6 chars) + random (4 chars)
        let timestamp = String(format: "%06x", Int(Date().timeIntervalSince1970) % 0xFFFFFF)
        let randomChars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let random = String((0..<4).map { _ in randomChars.randomElement()! })
        let videoId = "\(timestamp)\(random)"
        
        let storage = Storage.storage()
        let videoRef = storage.reference().child("videos/generated/\(videoId).mp4")
        
        print("📤 Created storage reference: videos/generated/\(videoId).mp4")
        
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        metadata.customMetadata = [
            "prompt": prompt.prompt,
            "parentIds": prompt.parentIds?.joined(separator: ",") ?? ""
        ]
        print("📤 Created metadata with prompt and parentIds")
        
        do {
            // Upload the file and wait for completion
            _ = try await videoRef.putFileAsync(from: videoURL, metadata: metadata)
            print("📤 Upload completed successfully")
            
            // Verify the upload
            let uploadedMetadata = try await videoRef.getMetadata()
            print("📤 Verified upload with metadata:")
            print("  - Size: \(uploadedMetadata.size) bytes")
            print("  - Content Type: \(uploadedMetadata.contentType ?? "none")")
            print("  - Custom Metadata: \(uploadedMetadata.customMetadata ?? [:])")
            
            // Clean up the video file after successful upload
            try? FileManager.default.removeItem(at: videoURL)
            print("🧹 Cleaned up video file")
            
            return videoId
        } catch {
            print("❌ Upload failed with error: \(error.localizedDescription)")
            throw error
        }
    }
}

/// Response from the Flux Schnell worker
private struct FluxSchnellResponse: Codable {
    let success: Bool
    let imageUrl: String
} 
