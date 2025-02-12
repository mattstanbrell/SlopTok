import Foundation
import AVFoundation
import FirebaseStorage
import SwiftUI

/// Service responsible for generating new video prompts using LLM
actor PromptGenerationService {
    /// Shared instance
    static let shared = PromptGenerationService()
    
    private init() {}
    
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
        Generate new image prompts based on these prompts for images the user liked and the user's profile.
        
        Liked image prompts:
        \(formattedPrompts)
        
        User's interests:
        \(formattedInterests)
        User description: \(profile.description)
        
        Generate exactly 20 prompts with this precise distribution:
        - \(distribution.mutationCount) mutations of any liked prompts
        - \(distribution.crossoverCount) crossover prompts combining different pairs of liked prompts
        - \(distribution.profileBasedCount) prompts based purely on the user's profile interests
        - \(distribution.explorationCount) completely novel exploration prompts
        
        When creating prompts:
        1. Vary elements like:
           - The specific subject or focal point
           - The visual style and composition
           - The environment or setting
           - The lighting and atmosphere
           - The perspective and framing
           - The artistic technique or medium
           - The color palette and tones
        
        Focus on creating prompts that will generate stunning, high-quality images. Consider:
        - Strong composition (rule of thirds, leading lines, etc.)
        - Lighting and shadows
        - Focus and detail
        - Texture and materials
        - Color harmony
        - Visual storytelling through a single frame
        - Artistic style (photorealistic, stylized, illustrated, etc.)

        Risqué content (eg cleavage, tight clothing, etc) is ok, but avoid depicting actual nudity.

        Prompt writing tips:
        - Use precise descriptive language (e.g., "muted orange warm tones" vs "orange")
        - Reference specific styles (e.g., "street photography", "movie still")
        - For faces, use "portrait" and specify key details
        - Compose for vertical phone viewing (9:16 aspect ratio, centered subjects)
        
        For mutations and crossovers, include the parent prompt IDs:
        - Mutations should have one parent ID from the liked prompts
        - Crossovers should have two parent IDs from the liked prompts
        - Profile-based and novel prompts should have no parent IDs

        Example good prompt: "A close-up, macro photography stock photo of a strawberry intricately sculpted into the shape of a hummingbird in mid-flight, its wings a blur as it sips nectar from a vibrant, tubular flower. The backdrop features a lush, colorful garden with a soft, bokeh effect, creating a dreamlike atmosphere. The image is exceptionally detailed and captured with a shallow depth of field, ensuring a razor-sharp focus on the strawberry-hummingbird and gentle fading of the background. The high resolution, professional photographers style, and soft lighting illuminate the scene in a very detailed manner, professional color grading amplifies the vibrant colors and creates an image with exceptional clarity. The depth of field makes the hummingbird and flower stand out starkly against the bokeh background."
        
        Example subset of a response (showing different prompt types):
        {
            "prompts": [
                {
                    "prompt": "A close-up, macro photography capture of the same strawberry-hummingbird now illuminated by moonlight, creating an ethereal night garden scene. Tiny dewdrops glisten on its carved feathers, catching the moonlight like diamonds. The background garden is bathed in cool blue tones with fireflies providing points of warm light, their glow reflecting in the dewdrops. Shot with the same exceptional detail and shallow depth of field, but now emphasizing the interplay of light and shadow in the nocturnal setting",
                    "parentIds": ["abc123"]  // Mutation example
                },
                {
                    "prompt": "A masterfully executed fusion of two fruit sculptures: a strawberry hummingbird and a dragon fruit dragon, locked in an intricate aerial dance. The hummingbird's delicate form contrasts with the dragon's serpentine body, both captured in stunning macro detail. Professional lighting emphasizes the unique textures of each fruit, while the shallow depth of field creates a dreamy backdrop of a misty Chinese garden. The high-resolution capture ensures every carved scale and feather is crystal clear",
                    "parentIds": ["abc123", "def456"]  // Crossover example
                },
                {
                    "prompt": "An extreme close-up of a professional rock climber's chalk-covered hands gripping a vividly colored climbing hold, shot with the same macro photography style and attention to detail as the strawberry-hummingbird. Each grain of chalk and texture in the skin is captured with razor-sharp focus, while the climbing gym's colorful walls create a beautiful bokeh background. The lighting is dramatic and professional, highlighting the tension in the grip and the interplay of textures" // Profile-based example
                },
                {
                    "prompt": "An otherworldly scene captured through a crystalline prism: a bioluminescent jellyfish floating through a field of suspended diamond dust in zero gravity. Each particle catches and refracts light differently, creating a mesmerizing rainbow spectrum. Shot in ultra-high resolution with cutting-edge microscopy techniques, revealing both the delicate translucent tissues of the jellyfish and the geometric perfection of each suspended crystal" // Random exploration example
                }
            ]
        }

        You must generate 20 prompts.
        """
        
        // Call LLM
        let promptResult = await LLMService.shared.complete(
            userPrompt: prompt,
            systemPrompt: "You are generating creative photo prompts that build upon successful prompts and user interests. Focus on creating prompts that will result in visually stunning still images with strong composition, lighting, and attention to detail. Be imaginative while maintaining high production value and visual appeal. Pay special attention to photographic elements like composition rules, lighting, depth of field, and color harmony.",
            responseType: PromptGenerationResponse.self,
            schema: PromptGenerationSchema.schema
        )

        switch promptResult {
        case let .success((response, rawContent)):
            var allPrompts = response.prompts
            
            // Start processing initial prompts immediately
            let processingTask = Task {
                do {
                    try await generateVideosFromPrompts(allPrompts)
                } catch {
                    print("❌ Error processing initial prompts: \(error.localizedDescription)")
                }
            }
            
            // Request more prompts if needed
            if allPrompts.count < 20 {
                print("⚠️ Only received \(allPrompts.count) prompts, requesting \(20 - allPrompts.count) more in background")
                
                // Create conversation messages
                let messages: [LLMMessage] = [
                    LLMMessage(
                        role: .system,
                        content: "You are generating creative photo prompts that build upon successful prompts and user interests. Focus on creating prompts that will result in visually stunning still images with strong composition, lighting, and attention to detail. Be imaginative while maintaining high production value and visual appeal. Pay special attention to photographic elements like composition rules, lighting, depth of field, and color harmony."
                    ),
                    LLMMessage(
                        role: .user,
                        content: prompt // Original prompt with all context
                    ),
                    LLMMessage(
                        role: .assistant,
                        content: rawContent // Use exact content from LLM
                    ),
                    LLMMessage(
                        role: .user,
                        content: "Please generate \(20 - allPrompts.count) more prompts following the same guidelines and distribution as before. Make sure these new prompts are different from the ones above."
                    )
                ]
                
                print("\n📝 Message Chain for Additional Prompts:")
                print("=== System Message ===")
                print(messages[0].content)
                print("\n=== Initial User Message ===")
                print(messages[1].content)
                print("\n=== Assistant Response ===")
                print(messages[2].content)
                print("\n=== Follow-up User Message ===")
                print(messages[3].content)
                print("\n===================\n")
                
                let additionalResult = await LLMService.shared.complete(
                    messages: messages,
                    responseType: PromptGenerationResponse.self,
                    schema: PromptGenerationSchema.schema
                )
                
                switch additionalResult {
                case let .success((additionalResponse, _)):
                    print("✅ Generated \(additionalResponse.prompts.count) additional prompts")
                    // Process additional prompts
                    do {
                        try await generateVideosFromPrompts(additionalResponse.prompts)
                        allPrompts.append(contentsOf: additionalResponse.prompts)
                    } catch {
                        print("❌ Error processing additional prompts: \(error.localizedDescription)")
                    }
                case .failure(let error):
                    print("❌ Error generating additional prompts: \(error.description)")
                }
            }
            
            // Wait for initial prompts to finish processing
            await processingTask.value
            
            print("✅ Generated \(allPrompts.count) total prompts")
            return .success(PromptGenerationResponse(prompts: allPrompts), rawContent: rawContent)
        case .failure(let error):
            return .failure(error)
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
                    let maxRetries = 2
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
