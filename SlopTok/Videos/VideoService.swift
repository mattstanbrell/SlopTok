import Foundation
import FirebaseStorage

@MainActor
class VideoService: ObservableObject {
    static let shared = VideoService()
    private let storage = Storage.storage()
    @Published private(set) var videos: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    // Dictionary mapping video categories to their prompts
    private let seedVideoPrompts: [String: String] = [
        "cooking": "young person demonstrating meal prep in modern kitchen, overhead view, bright natural lighting, stainless steel prep area, colorful fresh ingredients laid out efficiently, professional camera quality, cinematic style, focus on hand movements and ingredient organization",
        "tech": "minimalist desk setup with ultrawide monitor, custom mechanical keyboard, ambient lighting, clean cable management, soft evening lighting, professional photography style, shallow depth of field, focus on productivity tools",
        "music": "modern bedroom music studio setup, midi keyboard, audio interface, moody LED lighting, high-end headphones displayed, warm ambient lighting, professional photography style",
        "rock-climbing": "solo rock climber scaling dramatic cliff face, golden hour lighting on orange sandstone, deep blue sky background, chalk dust visible, dynamic composition from below, crisp sports photography, focus on climbing form and grip",
        "kittens": "playful kitten exploring modern minimalist room, soft natural window lighting, curious pose, shallow depth of field, professional pet photography, warm cozy atmosphere, high detail fur texture",
        "streetwear": "urban street style outfit, trendy sneakers and tech wear, moody city background, cinematic lighting, professional fashion photography, shallow depth of field, dramatic shadows",
        "cars": "JDM sports car at night, neon city reflections on glossy paint, dramatic low angle shot, rain-slicked streets, professional automotive photography, moody cinematic lighting, subtle LED accents",
        "diving": "scuba diver floating near vibrant coral reef, crystal clear turquoise water, schools of tropical fish, rays of sunlight piercing through water, professional underwater photography, deep blue ocean background, perfect visibility",
        "turtle": "scuba diver next to massive sea turtle, vibrant blue tropical water, clear visibility, close-up shot, sunbeams streaming through water, professional underwater photography, high detail scales and shell texture",
        "octopus": "octopus squished against walls of small glass tank, intelligent eye making direct contact, moody aquarium lighting, professional nature photography, visible suction cups"
    ]
    
    private init() {}
    
    func loadVideos() async {
        isLoading = true
        error = nil
        
        do {
            // Get reference to the seed folder
            let seedRef = storage.reference().child("videos/seed")
            
            // List all items in the seed folder
            let result = try await seedRef.listAll()
            
            // Extract video IDs from the items (removing .mp4 extension)
            let videoIds = result.items.map { item -> String in
                let fullPath = item.name
                return String(fullPath.dropLast(4)) // Remove .mp4
            }
            
            // Sort videos by name for consistent ordering
            videos = videoIds.sorted()
            print("📹 VideoService - Loaded \(videos.count) videos")
            
            // Set prompts for all videos
            for item in result.items {
                let videoName = String(item.name.dropLast(4)) // Remove .mp4
                print("🔍 Processing video: \(item.fullPath)")
                
                if let prompt = seedVideoPrompts[videoName] {
                    do {
                        // First try to get existing metadata
                        let existingMetadata = try await item.getMetadata()
                        print("📋 Existing metadata for \(videoName): \(String(describing: existingMetadata.customMetadata))")
                        
                        let metadata = StorageMetadata()
                        metadata.customMetadata = ["prompt": prompt]
                        
                        _ = try await item.updateMetadata(metadata)
                        print("✅ Set metadata for video: \(videoName)")
                    } catch {
                        print("❌ Error with \(videoName): \(error)")
                    }
                }
            }
            
            print("📹 VideoService - Finished setting metadata for seed videos")
        } catch {
            self.error = error
            print("❌ VideoService - Error loading videos: \(error)")
        }
        
        isLoading = false
    }
    
    /// Sets the prompt metadata for all seed videos
    func setSeedVideoPrompts() async {
        isLoading = true
        error = nil
        
        do {
            let seedRef = storage.reference().child("videos/seed")
            let result = try await seedRef.listAll()
            
            for item in result.items {
                let videoName = String(item.name.dropLast(4)) // Remove .mp4
                if let prompt = seedVideoPrompts[videoName] {
                    let metadata = StorageMetadata()
                    metadata.customMetadata = ["prompt": prompt]
                    
                    do {
                        _ = try await item.updateMetadata(metadata)
                        print("✅ Set metadata for video: \(videoName)")
                    } catch {
                        print("❌ Error setting metadata for \(videoName): \(error)")
                    }
                }
            }
            
            print("📹 VideoService - Finished setting metadata for seed videos")
        } catch {
            self.error = error
            print("❌ VideoService - Error setting video metadata: \(error)")
        }
        
        isLoading = false
    }
} 