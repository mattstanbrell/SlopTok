import Foundation
import FirebaseAuth

@MainActor
class VideoCountTracker {
    static let shared = VideoCountTracker()
    private let defaults = UserDefaults.standard
    private let llmService = LLMService.shared
    private let likesService = LikesService()
    
    private enum Keys {
        static let videosSinceLastProfile = "videosSinceLastProfile"
        static let videosSinceLastGeneration = "videosSinceLastGeneration"
        static let watchedVideoIds = "watchedVideoIds"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }
    
    private init() {
        // Start monitoring for profile/prompt generation triggers
        Task {
            await likesService.loadLikedVideos()
        }
    }
    
    var videosSinceLastProfile: Int {
        get { defaults.integer(forKey: Keys.videosSinceLastProfile) }
        set { defaults.set(newValue, forKey: Keys.videosSinceLastProfile) }
    }
    
    var videosSinceLastGeneration: Int {
        get { defaults.integer(forKey: Keys.videosSinceLastGeneration) }
        set { defaults.set(newValue, forKey: Keys.videosSinceLastGeneration) }
    }
    
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }
    
    var watchedVideoIds: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.watchedVideoIds) ?? []) }
        set { defaults.set(Array(newValue), forKey: Keys.watchedVideoIds) }
    }
    
    func trackNewVideo(id: String) async {
        let isNewVideo = !watchedVideoIds.contains(id)
        if isNewVideo {
            var videos = watchedVideoIds
            videos.insert(id)
            watchedVideoIds = videos
            
            if !hasCompletedOnboarding && videos.count >= 10 {
                // Generate initial profile and prompts first
                do {
                    await generateInitialProfile()
                    await generateInitialPrompts()
                    
                    // Only mark onboarding as complete if generation succeeds
                    hasCompletedOnboarding = true
                    // Start fresh with regular counters
                    videosSinceLastProfile = 0
                    videosSinceLastGeneration = 0
                } catch {
                    print("❌ [VideoCountTracker] Failed to complete onboarding: \(error)")
                }
            } else if hasCompletedOnboarding {
                // Regular usage - increment both counters
                videosSinceLastProfile += 1
                videosSinceLastGeneration += 1
                
                // Check if we need to generate new content
                if shouldGenerateNewProfile {
                    await updateProfile()
                }
                if shouldGeneratePrompts {
                    await generateNewPrompts()
                }
            }
        }
    }
    
    private var shouldGenerateInitialProfile: Bool {
        !hasCompletedOnboarding && watchedVideoIds.count == 10
    }
    
    private var shouldGenerateNewProfile: Bool {
        hasCompletedOnboarding && videosSinceLastProfile >= 50
    }
    
    private var shouldGeneratePrompts: Bool {
        hasCompletedOnboarding && videosSinceLastGeneration >= 20
    }
    
    private func resetProfileCount() {
        videosSinceLastProfile = 0
    }
    
    private func resetGenerationCount() {
        videosSinceLastGeneration = 0
    }
    
    func clearAllCounts() {
        videosSinceLastProfile = 0
        videosSinceLastGeneration = 0
        watchedVideoIds = []
        hasCompletedOnboarding = false
    }
    
    private func generateInitialProfile() async {
        do {
            // Get liked seed videos
            let likedVideoIds = likesService.likedVideos.map { $0.id }
            let videoPrompts = try await llmService.fetchVideoPrompts(videoIds: likedVideoIds)
            let likedPrompts = zip(likedVideoIds, videoPrompts).map { (id: $0.0, metadata: $0.1) }
            
            // Generate initial profile based on seed video likes
            let profile = try await llmService.generateInitialProfile(likedVideoPrompts: likedPrompts)
            
            // Log the results for now
            print("🧬 [VideoCountTracker] Generated initial profile:")
            print(profile)
            
            // Reset the profile counter
            resetProfileCount()
        } catch {
            print("❌ [VideoCountTracker] Error generating initial profile: \(error)")
        }
    }
    
    private func generateInitialPrompts() async {
        do {
            // Get liked seed videos
            let likedVideoIds = likesService.likedVideos.map { $0.id }
            let videoPrompts = try await llmService.fetchVideoPrompts(videoIds: likedVideoIds)
            let likedPrompts = zip(likedVideoIds, videoPrompts).map { (id: $0.0, metadata: $0.1) }
            
            // Get the current profile
            let currentProfile = UserProfile() // TODO: Get actual current profile
            
            // Generate initial prompts based on seed video likes
            let prompts = try await llmService.generateInitialPrompts(
                userProfile: currentProfile,
                likedVideoPrompts: likedPrompts
            )
            
            // Log the results for now
            print("🧬 [VideoCountTracker] Generated initial prompts:")
            print(prompts)
            
            // Reset the generation counter
            resetGenerationCount()
        } catch {
            print("❌ [VideoCountTracker] Error generating initial prompts: \(error)")
        }
    }
    
    private func updateProfile() async {
        do {
            // Get the most recent 50 watched videos
            let recentWatchedIds = Array(watchedVideoIds).suffix(50)
            // Get liked videos that appear in those recent watched videos
            let recentLikedIds = likesService.likedVideos
                .filter { recentWatchedIds.contains($0.id) }
                .map { $0.id }
            
            // Get current profile
            let currentProfile = UserProfile() // TODO: Get actual current profile
            
            // Update profile based on recent likes
            let updatedProfile = try await llmService.updateUserProfile(
                existingProfile: currentProfile,
                recentVideoIds: recentLikedIds
            )
            
            // Log the results for now
            print("🧬 [VideoCountTracker] Updated profile:")
            print(updatedProfile)
            
            // Reset the profile counter
            resetProfileCount()
        } catch {
            print("❌ [VideoCountTracker] Error updating profile: \(error)")
        }
    }
    
    private func generateNewPrompts() async {
        do {
            // Get the most recent 20 watched videos
            let recentWatchedIds = Array(watchedVideoIds).suffix(20)
            // Get liked videos that appear in those recent watched videos
            let recentLikedIds = likesService.likedVideos
                .filter { recentWatchedIds.contains($0.id) }
                .map { $0.id }
            
            let videoPrompts = try await llmService.fetchVideoPrompts(videoIds: recentLikedIds)
            let likedPrompts = zip(recentLikedIds, videoPrompts).map { (id: $0.0, metadata: $0.1) }
            
            // Get current profile
            let currentProfile = UserProfile() // TODO: Get actual current profile
            
            // Generate new prompts using genetic algorithm
            let prompts = try await llmService.generateNextPrompts(
                userProfile: currentProfile,
                likedVideoPrompts: likedPrompts
            )
            
            // Log the results for now
            print("🧬 [VideoCountTracker] Generated new prompts:")
            print(prompts)
            
            // Reset the generation counter
            resetGenerationCount()
        } catch {
            print("❌ [VideoCountTracker] Error generating new prompts: \(error)")
        }
    }
} 