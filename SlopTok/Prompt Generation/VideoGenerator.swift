import Foundation
import FirebaseVertexAI
import FirebaseStorage
import UIKit

actor VideoGenerator {
    /// Total number of prompts to generate
    private static let TOTAL_PROMPT_COUNT = 20
    
    /// Number of times to retry failed operations
    private static let NUM_RETRIES = 5
    
    /// Model name
    private static let LLM_MODEL = "gemini-2.0-flash"
    
    /// Model name for image generation
    private static let IMAGE_MODEL = "flux-schnell"

    static let shared = VideoGenerator()
    
    /// Model for generating mutation prompts
    private let mutationModel: GenerativeModel
    
    /// Model for generating crossover prompts
    private let crossoverModel: GenerativeModel

    private init() {
        self.mutationModel = VertexAIService.createGeminiModel(
            modelName: Self.LLM_MODEL,
            schema: PromptGenerationGeminiSchema.mutationSchema
        )
        
        self.crossoverModel = VertexAIService.createGeminiModel(
            modelName: Self.LLM_MODEL,
            schema: PromptGenerationGeminiSchema.crossoverSchema
        )
    }

    func generateVideos(
        likedVideos: [LikedVideo], profile: UserProfile
    ) async throws -> [String] {
        let distribution = PromptDistribution.calculateDistribution(likedCount: likedVideos.count, totalCount: Self.TOTAL_PROMPT_COUNT)
        print("❤️ User liked \(likedVideos.count) videos")
        print("📊 Prompt distribution:")
        print("  - Mutations: \(distribution.mutationCount)")
        print("  - Crossovers: \(distribution.crossoverCount)")
        print("  - Profile-based: \(distribution.profileBasedCount)")
        print("  - Exploration: \(distribution.explorationCount)")

        var generatedVideoIDs: [String] = []
        var currentCounts: [PromptType: Int] = [:]
        
        // Initial generation
        let initialCounts: [PromptType: Int] = [
            .mutation: distribution.mutationCount,
            .crossover: distribution.crossoverCount,
            .profileBased: distribution.profileBasedCount,
            .exploration: distribution.explorationCount
        ]
        
        try await generateAndProcessPrompts(
            targetCounts: initialCounts,
            currentCounts: &currentCounts,
            generatedVideoIDs: &generatedVideoIDs,
            distribution: distribution,
            profile: profile,
            likedVideos: likedVideos
        )
        
        // If we still need more videos, retry with missing counts
        if generatedVideoIDs.count < Self.TOTAL_PROMPT_COUNT {
            var missingCounts: [PromptType: Int] = [:]
            for (type, desiredCount) in distribution.promptCount {
                let currentCount = currentCounts[type] ?? 0
                if currentCount < desiredCount {
                    missingCounts[type] = desiredCount - currentCount
                }
            }
            
            if !missingCounts.isEmpty {
                try await generateAndProcessPrompts(
                    targetCounts: missingCounts,
                    currentCounts: &currentCounts,
                    generatedVideoIDs: &generatedVideoIDs,
                    distribution: distribution,
                    profile: profile,
                    likedVideos: likedVideos
                )
            }
        }

        return generatedVideoIDs
    }
    
    /// Helper function to generate and process prompts for given target counts
    private func generateAndProcessPrompts(
        targetCounts: [PromptType: Int],
        currentCounts: inout [PromptType: Int],
        generatedVideoIDs: inout [String],
        distribution: PromptDistribution,
        profile: UserProfile,
        likedVideos: [LikedVideo]
    ) async throws {
        var excessPrompts: [PromptType: [Prompt]] = [:]
        
        try await withThrowingTaskGroup(of: (PromptType, [Prompt]).self) { group in
            // Add generation tasks
            for (type, count) in targetCounts where count > 0 {
                group.addTask {
                    switch type {
                    case .mutation:
                        let prompts = try await self.generateMutationPrompts(count: count, profile: profile, likedVideos: likedVideos)
                        return (type, prompts)
                    case .crossover:
                        let prompts = try await self.generateCrossoverPrompts(count: count, profile: profile, likedVideos: likedVideos)
                        return (type, prompts)
                    case .profileBased:
                        let prompts = try await self.generateProfileBasedPrompts(count: count, profile: profile)
                        return (type, prompts)
                    case .exploration:
                        let prompts = try await self.generateRandomPrompts(count: count)
                        return (type, prompts)
                    }
                }
            }
            
            // Process generated prompts
            for try await (promptType, prompts) in group {
                let desiredCount = targetCounts[promptType] ?? 0
                
                let (toGenerate, excess) = prompts.count > desiredCount ? 
                    (Array(prompts[..<desiredCount]), Array(prompts[desiredCount...])) : 
                    (prompts, [])
                    
                excessPrompts[promptType] = excess
                
                let videoIDs = try await generateAndUploadAndPushVideos(prompts: toGenerate)
                currentCounts[promptType] = (currentCounts[promptType] ?? 0) + videoIDs.count
                generatedVideoIDs.append(contentsOf: videoIDs)
            }
            
            // Use excess if needed
            if generatedVideoIDs.count < Self.TOTAL_PROMPT_COUNT && !excessPrompts.isEmpty {
                let needed = Self.TOTAL_PROMPT_COUNT - generatedVideoIDs.count
                let additionalCounts = distribution.distributeExcess(excessCount: needed, currentCounts: currentCounts)
                
                for (type, count) in additionalCounts {
                    if let typeExcess = excessPrompts[type] {
                        let prompts = Array(typeExcess.prefix(count))
                        let videoIDs = try await generateAndUploadAndPushVideos(prompts: prompts)
                        generatedVideoIDs.append(contentsOf: videoIDs)
                    }
                }
            }
        }
    }

    private func generateMutationPrompts(count: Int, profile: UserProfile, likedVideos: [LikedVideo]) async throws -> [MutationPrompt] {
        // Load thumbnails for liked videos
        var thumbnailImages: [(id: String, prompt: String, image: UIImage)] = []
        for video in likedVideos {
            if let image = await VideoService.shared.getUIImageThumbnail(for: video.id),
               let prompt = video.prompt {  // Only include videos that have both an image and a prompt
                thumbnailImages.append((id: video.id, prompt: prompt, image: image))
            }
        }
        
        // Build the parts array with prompts and images
        let parts = PromptHelper.constructBaseParts(likedVideosWithThumbnails: thumbnailImages)
        let prompt = PromptHelper.constructMutationPrompt(
            count: count,
            profile: profile,
            likedVideosWithThumbnails: thumbnailImages
        )
        
        return try await RetryHelper.retry(numRetries: Self.NUM_RETRIES, operation: "mutation prompts") {
            let response = try await mutationModel.generateContent(parts + [prompt as PartsRepresentable])
            
            guard let text = response.text else {
                throw LLMError.apiError("Empty response")
            }
            
            guard let data = text.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(PromptGenerationGeminiResponse.self, from: data) else {
                throw LLMError.apiError("Invalid response format")
            }
            
            guard let mutatedPrompts = decoded.mutatedPrompts else {
                throw LLMError.apiError("Invalid response format - no mutation prompts found")
            }
            
            // Convert to MutationPrompt objects
            return mutatedPrompts.map { mutation -> MutationPrompt in
                return MutationPrompt(prompt: mutation.prompt, parentId: mutation.parentId)
            }
        }
    }

    private func generateCrossoverPrompts(count: Int, profile: UserProfile, likedVideos: [LikedVideo]) async throws -> [CrossoverPrompt] {
        // Load thumbnails for liked videos
        var thumbnailImages: [(id: String, prompt: String, image: UIImage)] = []
        for video in likedVideos {
            if let image = await VideoService.shared.getUIImageThumbnail(for: video.id),
               let prompt = video.prompt {  // Only include videos that have both an image and a prompt
                thumbnailImages.append((id: video.id, prompt: prompt, image: image))
            }
        }
        
        // Build the parts array with prompts and images
        let parts = PromptHelper.constructBaseParts(likedVideosWithThumbnails: thumbnailImages)
        let prompt = PromptHelper.constructCrossoverPrompt(
            count: count,
            profile: profile,
            likedVideosWithThumbnails: thumbnailImages
        )
        
        return try await RetryHelper.retry(numRetries: Self.NUM_RETRIES, operation: "crossover prompts") {
            let response = try await crossoverModel.generateContent(parts + [prompt as PartsRepresentable])
            
            guard let text = response.text else {
                throw LLMError.apiError("Empty response")
            }
            
            guard let data = text.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(PromptGenerationGeminiResponse.self, from: data) else {
                throw LLMError.apiError("Invalid response format")
            }
            
            guard let crossoverPrompts = decoded.crossoverPrompts else {
                throw LLMError.apiError("Invalid response format - no crossover prompts found")
            }
            
            // Convert to CrossoverPrompt objects
            return crossoverPrompts.map { crossover -> CrossoverPrompt in
                return CrossoverPrompt(prompt: crossover.prompt, parentIds: crossover.parentIds)
            }
        }
    }

    private func generateProfileBasedPrompts(count: Int, profile: UserProfile) async throws -> [ProfileBasedPrompt] {
        let prompt = PromptHelper.constructProfileBasedPrompt(
            count: count,
            profile: profile
        )
        
        return try await RetryHelper.retry(numRetries: Self.NUM_RETRIES, operation: "profile-based prompts") {
            let result = await LLMService.shared.complete(
                userPrompt: prompt,
                systemPrompt: "You are generating creative photo prompts based on a user's interests and preferences. Focus on creating prompts that align with their interests while maintaining high visual quality and appeal.",
                responseType: PromptGenerationOpenAIResponse.self,
                schema: PromptGenerationOpenAISchema.profileBasedSchema
            )
            
            switch result {
            case .success((let response, _)):
                print("✅ Successfully decoded response into \(response.prompts.count) profile-based prompts")
                
                // Convert to ProfileBasedPrompt objects
                let generatedPrompts = response.prompts.map { prompt -> ProfileBasedPrompt in
                    return ProfileBasedPrompt(prompt: prompt.prompt)
                }
                print("✅ Generated \(generatedPrompts.count) profile-based prompts")
                return generatedPrompts
            case .failure(let error):
                throw error
            }
        }
    }

    private func generateRandomPrompts(count: Int) async throws -> [RandomPrompt] {
        let prompt = """
        Generate \(count) unique, highly creative image prompts that explore diverse subjects, styles, and compositions.
        
        \(PromptHelper.qualityGuidelines())
        
        Focus on creating prompts that are:
        - Highly imaginative and unique
        - Visually striking and memorable
        - Diverse in subject matter and style
        - Technically detailed and precise
        - Suitable for high-quality image generation
        
        Example creative prompts:
        "A hyperrealistic macro photograph of a soap bubble at the exact moment of bursting, capturing the iridescent surface tension breaking apart into a constellation of miniature droplets. Shot with ultra-high-speed photography, the image reveals intricate rainbow patterns in the membrane and crystalline clarity in each suspended droplet. Professional studio lighting creates dramatic highlights while maintaining the delicate, ethereal quality of the scene."
        
        "An architectural abstract capturing the geometric patterns of a modern glass skyscraper at sunset, shot from a dramatic upward angle. The golden hour light creates a mesmerizing interplay of reflections, shadows, and color gradients across the glass facade. The composition emphasizes leading lines and repetitive elements, while selective focus draws attention to the intricate details of the structure's design."
        
        Generate \(count) unique prompts that showcase creativity and visual appeal.
        Do not include any parentIds in the response.
        """
        
        return try await RetryHelper.retry(numRetries: Self.NUM_RETRIES, operation: "random prompts") {
            let result = await LLMService.shared.complete(
                userPrompt: prompt,
                systemPrompt: "You are generating creative, diverse photo prompts that explore unique subjects and styles. Focus on creating prompts that are visually striking and technically detailed.",
                responseType: PromptGenerationOpenAIResponse.self,
                schema: PromptGenerationOpenAISchema.randomSchema
            )
            
            switch result {
            case .success((let response, _)):
                print("✅ Successfully decoded response into \(response.prompts.count) random prompts")
                
                // Convert to RandomPrompt objects
                let generatedPrompts = response.prompts.map { prompt -> RandomPrompt in
                    return RandomPrompt(prompt: prompt.prompt)
                }
                print("✅ Generated \(generatedPrompts.count) random prompts")
                return generatedPrompts
            case .failure(let error):
                throw error
            }
        }
    }

    // if something fails, retry. only return ids of successful stuff.
    private func generateAndUploadAndPushVideos(prompts: [Prompt]) async throws -> [String] {
        // Track successful and failed operations
        var completedVideoIds: [String] = []
        var failedPrompts: [(prompt: Prompt, error: Error)] = []
        
        // Limit concurrent tasks to 3
        let semaphore = DispatchSemaphore(value: 3)
        
        try await withThrowingTaskGroup(of: String?.self) { group in
            // Add tasks for each prompt
            for (index, prompt) in prompts.enumerated() {
                // Wait for semaphore slot
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().async {
                        semaphore.wait()
                        continuation.resume()
                    }
                }
                
                group.addTask {
                    defer { semaphore.signal() }  // Release slot when done
                    
                    // Create unique temp directory
                    let taskTempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: taskTempDir) }
                    
                    do {
                        // Create temp directory
                        try FileManager.default.createDirectory(at: taskTempDir, withIntermediateDirectories: true)
                        
                        // 1. Generate image
                        let imageData = try await ImageGenerationService.shared.generateImage(
                            modelName: Self.IMAGE_MODEL,
                            prompt: prompt.prompt
                        )
                        print("✅ Task \(index + 1): Generated image")
                        
                        // 2. Convert to video
                        guard let image = UIImage(data: imageData) else {
                            throw LLMError.apiError("Failed to create UIImage from data")
                        }
                        
                        let videoURL = try await ImageToVideoConverter.convertImageToVideo(
                            image: image,
                            duration: 3.0,
                            size: CGSize(width: 1080, height: 1920)
                        )
                        print("✅ Task \(index + 1): Converted to video")
                        
                        // 3. Upload video and get ID
                        let videoId = try await self.uploadVideo(at: videoURL, prompt: prompt)
                        print("✅ Task \(index + 1): Uploaded video \(videoId)")
                        
                        return videoId
                    } catch {
                        print("❌ Task \(index + 1) failed: \(error.localizedDescription)")
                        await MainActor.run {
                            failedPrompts.append((prompt: prompt, error: error))
                        }
                        return nil
                    }
                }
            }
            
            // Process results as they complete
            for try await videoId in group {
                if let videoId = videoId {
                    await MainActor.run {
                        completedVideoIds.append(videoId)
                        
                        // Add to feed in batches
                        if completedVideoIds.count <= 5 {
                            // First 5 videos added individually
                            VideoService.shared.appendVideo(videoId)
                        } else if completedVideoIds.count % 5 == 0 {
                            // After first 5, add in batches of 5
                            let startIndex = completedVideoIds.count - 5
                            let batch = Array(completedVideoIds[startIndex..<completedVideoIds.count])
                            for id in batch {
                                VideoService.shared.appendVideo(id)
                            }
                        }
                    }
                }
            }
            
            // Add any remaining videos to feed
            await MainActor.run {
                if completedVideoIds.count > 5 {
                    let remainingCount = (completedVideoIds.count - 5) % 5
                    if remainingCount > 0 {
                        let startIndex = completedVideoIds.count - remainingCount
                        let batch = Array(completedVideoIds[startIndex..<completedVideoIds.count])
                        for id in batch {
                            VideoService.shared.appendVideo(id)
                        }
                    }
                }
                
                // Log completion statistics
                print("🎉 Video generation completed:")
                print("  ✅ Successfully completed: \(completedVideoIds.count) videos")
                print("  ❌ Failed: \(failedPrompts.count) prompts")
            }
        }
        
        return completedVideoIds
    }
    
    /// Uploads a video to Firebase Storage with metadata
    private func uploadVideo(at videoURL: URL, prompt: Prompt) async throws -> String {
        // Generate video ID: timestamp (6 chars) + random (4 chars)
        let timestamp = String(format: "%06x", Int(Date().timeIntervalSince1970) % 0xFFFFFF)
        let randomChars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let random = String((0..<4).map { _ in randomChars.randomElement()! })
        let videoId = "\(timestamp)\(random)"
        
        let storage = Storage.storage()
        let videoRef = storage.reference().child("videos/generated/\(videoId).mp4")
        
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        metadata.customMetadata = [
            "prompt": prompt.prompt,
            "parentIds": prompt.parentIds?.joined(separator: ",") ?? ""
        ]
        
        // Upload and verify
        _ = try await videoRef.putFileAsync(from: videoURL, metadata: metadata)
        _ = try await videoRef.getMetadata()
        
        return videoId
    }
}
