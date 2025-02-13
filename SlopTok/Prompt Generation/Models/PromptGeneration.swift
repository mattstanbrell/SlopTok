import Foundation

/// Single generated image prompt with optional parent information
struct PromptGeneration: Codable {
    /// The generated image prompt
    let prompt: String
    
    /// ID of the parent prompt for mutations
    let parentId: String?
    
    /// IDs of parent prompts for crossovers
    let parentIds: [String]?
    
    /// Creates a mutation prompt
    init(prompt: String, parentId: String) {
        self.prompt = prompt
        self.parentId = parentId
        self.parentIds = nil
    }
    
    /// Creates a crossover prompt
    init(prompt: String, parentIds: [String]) {
        self.prompt = prompt
        self.parentId = nil
        self.parentIds = parentIds
    }
    
    /// Creates a profile-based or random prompt
    init(prompt: String) {
        self.prompt = prompt
        self.parentId = nil
        self.parentIds = nil
    }
}

/// Response from LLM for generating new image prompts
struct PromptGenerationOpenAIResponse: Codable {
    /// The array of generated prompts
    let prompts: [PromptGeneration]
}

/// Response from Gemini for generating new image prompts
struct PromptGenerationGeminiResponse: Codable {
    /// A single mutated prompt
    struct MutatedPrompt: Codable {
        /// The generated prompt
        let prompt: String
        /// ID of the parent prompt this was mutated from
        let parentId: String
    }
    
    /// A single crossover prompt
    struct CrossoverPrompt: Codable {
        /// The generated prompt
        let prompt: String
        /// IDs of the parent prompts this was created from
        let parentIds: [String]
    }
    
    /// Array of mutated prompts (for mutation responses)
    let mutatedPrompts: [MutatedPrompt]?
    /// Array of crossover prompts (for crossover responses)
    let crossoverPrompts: [CrossoverPrompt]?
} 