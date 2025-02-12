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
    
    /// Generates the initial set of prompts after seed videos
    /// - Parameters:
    ///   - likedVideos: Array of prompts from seed videos the user liked
    ///   - profile: The user's current profile
    /// - Returns: Array of generated prompts or error
    func generateInitialPrompts(
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
        case .success(let response):
            print("✅ Generated \(response.prompts.count) initial prompts")
            
            // Process only the first prompt
            if let firstPrompt = response.prompts.first {
                do {
                    print("🎨 Processing first prompt: \(firstPrompt.prompt)")
                    
                    // 1. Generate image
                    let imageData = try await generateImage(from: firstPrompt.prompt)
                    print("✅ Generated image from prompt")
                    
                    // 2. Convert to video
                    let videoURL = try await convertImageToVideo(imageData)
                    print("✅ Converted image to video")
                    
                    // 3. Upload video with metadata
                    try await uploadVideo(at: videoURL, prompt: firstPrompt)
                    print("✅ Uploaded video to Firebase")
                    
                    // Clean up temporary video file
                    try? FileManager.default.removeItem(at: videoURL)
                    print("🧹 Cleaned up temporary files")
                } catch {
                    print("❌ Error processing prompt: \(error.localizedDescription)")
                }
            }
            
            return .success(response)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Generates videos from an array of prompts
    private func generateVideosFromPrompts(_ prompts: [PromptGeneration]) async throws {
        for prompt in prompts {
            do {
                // 1. Generate image
                let imageData = try await generateImage(from: prompt.prompt)
                
                // 2. Convert to video
                let videoURL = try await convertImageToVideo(imageData)
                
                // 3. Upload video with metadata
                try await uploadVideo(at: videoURL, prompt: prompt)
                
                // Clean up temporary video file
                try? FileManager.default.removeItem(at: videoURL)
            } catch {
                print("❌ Error processing prompt: \(error.localizedDescription)")
                // Continue with next prompt even if one fails
                continue
            }
        }
    }

    /// Generates an image from a prompt using our worker
    private func generateImage(from prompt: String) async throws -> Data {
        print("🖼️ Generating image for prompt: \(prompt)")
        
        let request = URLRequest(url: URL(string: "https://sloptok-images.mattstanbrell.workers.dev/")!)
        var imageRequest = request
        imageRequest.httpMethod = "POST"
        imageRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ["prompt": prompt]
        imageRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: imageRequest)
        let imageResponse = try JSONDecoder().decode(ImageResponse.self, from: data)
        
        guard let imageData = Data(base64Encoded: imageResponse.imageData) else {
            throw NSError(domain: "PromptGenerationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }
        
        return imageData
    }

    /// Converts an image to a 3-second video
    private func convertImageToVideo(_ imageData: Data) async throws -> URL {
        print("🎬 Converting image to video")
        
        let tempImageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try imageData.write(to: tempImageURL)
        
        guard let image = UIImage(contentsOfFile: tempImageURL.path) else {
            throw NSError(domain: "PromptGenerationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create UIImage from data"])
        }
        
        // Use our new converter
        let videoURL = try await ImageToVideoConverter.convertImageToVideo(
            image: image,
            duration: 3.0,
            size: CGSize(width: 1080, height: 1920) // 9:16 aspect ratio for vertical video
        )
        
        try? FileManager.default.removeItem(at: tempImageURL)
        
        return videoURL
    }

    /// Uploads a video to Firebase Storage with metadata
    private func uploadVideo(at videoURL: URL, prompt: PromptGeneration) async throws {
        print("📤 Starting video upload process")
        print("📤 Video file exists: \(FileManager.default.fileExists(atPath: videoURL.path))")
        
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int64 {
            print("📤 Video file size: \(fileSize) bytes")
        } else {
            print("❌ Could not get file size")
        }
        
        // Generate a shorter video ID: timestamp (6 chars) + random (4 chars)
        let timestamp = String(format: "%06x", Int(Date().timeIntervalSince1970) % 0xFFFFFF)
        let randomChars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let random = String((0..<4).map { _ in randomChars.randomElement()! })
        let videoId = "\(timestamp)\(random)" // Results in a 10-character ID like "f5e21cabcd"
        
        let storage = Storage.storage()
        let videoRef = storage.reference().child("videos/generated/\(videoId).mp4")
        
        print("📤 Created storage reference: videos/generated/\(videoId).mp4")
        
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        metadata.customMetadata = [
            "prompt": prompt.prompt,
            "parentIds": prompt.parentIds?.joined(separator: ",") ?? ""
        ]
        
        do {
            print("📤 Starting Firebase upload...")
            _ = try await videoRef.putFile(from: videoURL, metadata: metadata)
            print("📤 Upload completed")
            
            // Add a small delay to allow Firebase to process the upload
            try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second delay
            
            // Verify the upload by trying to get the download URL
            let downloadURL = try await videoRef.downloadURL()
            print("📤 Successfully got download URL: \(downloadURL)")
            
            // Add to end of feed
            await MainActor.run {
                VideoService.shared.appendVideo(videoId)
            }
            print("📤 Added video to end of feed: \(videoId)")
        } catch {
            print("❌ Upload failed with error: \(error)")
            throw error
        }
    }
}

/// Response from the image generation worker
private struct ImageResponse: Codable {
    let success: Bool
    let imageData: String
} 
