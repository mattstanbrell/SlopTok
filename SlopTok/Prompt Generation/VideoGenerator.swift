import Foundation

actor VideoGenerator {
    /// Total number of prompts to generate
    private static let TOTAL_PROMPT_COUNT = 20

    static let shared = VideoGenerator()

    private init() {
    }

    func generateVideos(
        likedVideos: [LikedVideo], profile: UserProfile
    ) async throws -> [TODO] {
        let distribution = calculateDistribution(likedCount: likedVideos.count, totalCount: TOTAL_PROMPT_COUNT)
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
        if generatedVideoIDs.count < TOTAL_PROMPT_COUNT {
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
                        let prompts = try await generateMutationPrompts(count: count, profile: profile, likedVideos: likedVideos)
                        return (type, prompts)
                    case .crossover:
                        let prompts = try await generateCrossoverPrompts(count: count, profile: profile, likedVideos: likedVideos)
                        return (type, prompts)
                    case .profileBased:
                        let prompts = try await generateProfileBasedPrompts(count: count, profile: profile)
                        return (type, prompts)
                    case .exploration:
                        let prompts = try await generateRandomPrompts(count: count)
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
            if generatedVideoIDs.count < TOTAL_PROMPT_COUNT && !excessPrompts.isEmpty {
                let needed = TOTAL_PROMPT_COUNT - generatedVideoIDs.count
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
        
    }

    private func generateCrossoverPrompts(count: Int, profile: UserProfile, likedVideos: [LikedVideo]) async throws -> [CrossoverPrompt] {
        // TODO
    }

    private func generateProfileBasedPrompts(count: Int, profile: UserProfile) async throws -> [ProfileBasedPrompt] {
        // TODO
    }

    private func generateRandomPrompts(count: Int) async throws -> [RandomPrompt] {
        // TODO
    }

    private func calculatePromptDistribution(likedCount: Int) -> PromptDistribution {
        // TODO
    }

    private func generateVideo(prompt: String) async throws -> Video {
        // TODO
    }

    private func uploadVideo()

    // if something fails, retry. only return ids of successful stuff.
    private func generateAndUploadAndPushVideos(prompts: [Prompt]) async throws -> [String] { 
        // TODO
    }
}
