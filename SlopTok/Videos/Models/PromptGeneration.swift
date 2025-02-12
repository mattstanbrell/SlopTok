import Foundation

/// Single generated image prompt with optional parent information
struct PromptGeneration: Codable {
    /// The generated image prompt
    let prompt: String
    
    /// IDs of parent prompts that influenced this generation
    /// - One ID for mutations (variation of a single prompt)
    /// - Two IDs for crossovers (combining elements from two prompts)
    let parentIds: [String]?
}

/// Response from LLM for generating new image prompts
struct PromptGenerationResponse: Codable {
    /// The array of generated prompts
    let prompts: [PromptGeneration]
} 